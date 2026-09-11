module PreviewSync exposing
    ( SyncPoint
    , measureSyncPoints
    , scrollToHeadingCmd
    , syncAnchors
    , syncPreview
    )

{-| Keeping the preview's scroll position in step with the editor's, and
scrolling either pane to a heading. Main passes in the pieces of its model
these read (the layout mode as booleans, the measured points and the heading
anchors) and the messages the commands resolve to.
-}

import Array
import Browser.Dom
import Editor
import EditorLayout
import Markdown
import Process
import Task


{-| Keep the preview following the editor's scroll position.

Mapping source lines to rendered pixels exactly would need a position for
every block; headings are the anchors we already have, so the editor's top
line is placed between the two headings that bracket it, and the preview is
scrolled to the matching point between their rendered positions.

Two things keep it smooth. The top line is fractional, so the preview moves
with the editor rather than once per line. And every heading's pixel position
is measured in one pass whenever the preview's layout changes, never while
scrolling: a `getElement` between the editor's own row updates would force a
synchronous layout of the whole page on every scroll event, which is exactly
what this editor exists to avoid. Scrolling is then pure arithmetic and a
single scroll write.

Only the editor drives this: mapping the preview's DOM back to source would
need the same data in reverse, for much less gain.

-}
type alias SyncPoint =
    { line : Float, y : Float }


{-| `inSplit` is whether both panes are showing; nothing to sync otherwise. -}
syncPreview : msg -> Bool -> List SyncPoint -> Editor.Model -> Cmd msg
syncPreview noOp inSplit syncPoints editor =
    let
        topLine =
            if editor.softWrap then
                EditorLayout.sourceLine (editor.scrollTop / Basics.max 1 editor.metrics.lineHeight) editor.layout

            else
                editor.scrollTop / Basics.max 1 editor.metrics.lineHeight
    in
    if not inSplit || Editor.dragging editor then
        Cmd.none

    else
        case bracketing topLine syncPoints of
            Just ( from, to ) ->
                scrollPreviewTo noOp (interpolate from to topLine)

            Nothing ->
                Cmd.none


{-| The measured points bracketing a line.
-}
bracketing : Float -> List SyncPoint -> Maybe ( SyncPoint, SyncPoint )
bracketing topLine points =
    case points of
        first :: second :: rest ->
            if topLine < second.line || List.isEmpty rest then
                Just ( first, second )

            else
                bracketing topLine (second :: rest)

        _ ->
            Nothing


interpolate : SyncPoint -> SyncPoint -> Float -> Float
interpolate from to topLine =
    let
        span =
            to.line - from.line
    in
    if span <= 0 then
        from.y

    else
        from.y + clamp 0 1 ((topLine - from.line) / span) * (to.y - from.y)


scrollPreviewTo : msg -> Float -> Cmd msg
scrollPreviewTo noOp y =
    ignoreResult noOp (Browser.Dom.setViewportOf "preview-container" 0 y)


{-| Measure where every heading sits in the rendered preview, plus the two
ends of the document. One pass, off the scrolling path: consecutive reads with
no writes between them share a single layout.

The wait is not decoration. Elm applies a view on the animation frame after
the update that produced it, so reading the DOM in the same update would
measure the *previous* render - and right after a parse that is a preview
without the headings in it.

-}
measureSyncPoints : (List SyncPoint -> msg) -> Bool -> List ( Int, String ) -> Editor.Model -> Cmd msg
measureSyncPoints toMsg inSplit headingAnchors editor =
    if not inSplit || List.isEmpty headingAnchors then
        Task.perform toMsg (Task.succeed [])

    else
        Process.sleep 50
            |> Task.andThen
                (\_ -> Task.map2 Tuple.pair (Browser.Dom.getElement "preview-container") (Browser.Dom.getViewportOf "preview-container"))
            |> Task.andThen
                (\( container, containerVp ) ->
                    headingAnchors
                        |> List.map
                            (\( line, anchorId ) ->
                                Browser.Dom.getElement anchorId
                                    |> Task.map
                                        (\heading ->
                                            Just
                                                { line = toFloat line
                                                , y = containerVp.viewport.y + heading.element.y - container.element.y
                                                }
                                        )
                                    -- a heading that is not in the DOM is skipped
                                    -- rather than losing the whole mapping
                                    |> Task.onError (\_ -> Task.succeed Nothing)
                            )
                        |> Task.sequence
                        |> Task.map
                            (\measured ->
                                -- the document's own top always maps to the top
                                -- of the preview, so a heading on line 0 (which
                                -- measures at the preview's padding) is dropped
                                { line = 0, y = 0 }
                                    :: List.filter (\point -> point.line > 0) (List.filterMap identity measured)
                                    ++ [ { line = toFloat (Basics.max 1 (Array.length editor.lines - 1))
                                         , y = Basics.max 0 (containerVp.scene.height - containerVp.viewport.height)
                                         }
                                       ]
                            )
                )
            |> Task.attempt (Result.withDefault [] >> toMsg)


{-| The headings, as (source line, anchor id) pairs. Recomputed once per
completed parse, never per scroll event: it rescans the whole document.

The two lists come from the same document in the same order; if they disagree
in length the mapping would be wrong for every heading (a setext heading, say),
so sync is skipped entirely instead.

-}
syncAnchors : String -> List Markdown.OutlineEntry -> List ( Int, String )
syncAnchors content entries =
    let
        lines =
            Markdown.headingLines content
    in
    if List.length lines == List.length entries then
        List.map2 (\line entry -> ( line, entry.id )) lines entries

    else
        []


{-| Scroll to a heading picked in the outline.

The editor is what moves: the outline lists the rendered document, but the
heading's source line is known, and scrolling the editor there carries the
preview with it through the usual sync. Scrolling both directly instead would
race - the preview scroll is computed from the container's current offset,
which sync is moving at the same time, and the result overshoots.

Only a heading whose source line cannot be resolved (see `syncAnchors`) falls
back to scrolling the preview on its own.

-}
scrollToHeadingCmd : msg -> Bool -> List ( Int, String ) -> Editor.Model -> String -> Cmd msg
scrollToHeadingCmd noOp previewOnly headingAnchors editor anchorId =
    if previewOnly then
        scrollPreviewToHeadingCmd noOp anchorId

    else
        case headingAnchors |> List.filter (\( _, id ) -> id == anchorId) |> List.head of
            Just ( line, _ ) ->
                ignoreResult noOp
                    (Browser.Dom.setViewportOf "veditor"
                        0
                        (toFloat (EditorLayout.lineStartRow line editor.layout) * editor.metrics.lineHeight)
                    )

            Nothing ->
                scrollPreviewToHeadingCmd noOp anchorId


{-| Scroll the preview pane so the heading with `anchorId` is at the top.
Computes the heading's offset relative to the scrollable preview container.
-}
scrollPreviewToHeadingCmd : msg -> String -> Cmd msg
scrollPreviewToHeadingCmd noOp anchorId =
    Task.map3
        (\heading container containerVp ->
            -- Heading offset within the container's scrollable content.
            containerVp.viewport.y + heading.element.y - container.element.y
        )
        (Browser.Dom.getElement anchorId)
        (Browser.Dom.getElement "preview-container")
        (Browser.Dom.getViewportOf "preview-container")
        |> Task.andThen (\y -> Browser.Dom.setViewportOf "preview-container" 0 y)
        |> ignoreResult noOp


{-| Run a task purely for its effect.
-}
ignoreResult : msg -> Task.Task x a -> Cmd msg
ignoreResult noOp =
    Task.attempt (\_ -> noOp)

