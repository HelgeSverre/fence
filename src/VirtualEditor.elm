module VirtualEditor exposing
    ( Config
    , Metrics
    , caretPosition
    , defaultMetrics
    , metricsDecoder
    , view
    , visibleRange
    )

{-| The editor's view: a spacer the size of the whole document and only the
rows that intersect the viewport (plus overscan) rendered as real DOM, a
caret, selection boxes and a hidden input under the caret for keys, IME and
paste. Soft breaks are supplied by EditorLayout. See
docs/plans/2026-09-02-virtualized-editor.md.
-}

import Array exposing (Array)
import EditorLayout
import Html exposing (Html, div, textarea)
import Html.Attributes exposing (attribute, class, id, spellcheck, style, value)
import Html.Events exposing (on, preventDefaultOn)
import Html.Lazy
import Json.Decode as D
import TextBuffer exposing (Cursor)


{-| Measured once per font/size change by js/editor-metrics.js.
-}
type alias Metrics =
    { lineHeight : Float
    , charWidth : Float
    , viewportHeight : Float
    , viewportWidth : Float

    -- where the document's origin sits on screen, so a pointer position
    -- anywhere in the window can be turned into a document position
    , viewportTop : Float
    , viewportLeft : Float
    }


defaultMetrics : Metrics
defaultMetrics =
    { lineHeight = 22.4, charWidth = 8.4, viewportHeight = 800, viewportWidth = 800, viewportTop = 0, viewportLeft = 0 }


metricsDecoder : D.Decoder Metrics
metricsDecoder =
    D.map6 Metrics
        (D.field "lineHeight" D.float)
        (D.field "charWidth" D.float)
        (D.field "viewportHeight" D.float)
        (D.field "viewportWidth" D.float)
        (D.field "viewportTop" D.float)
        (D.field "viewportLeft" D.float)


{-| Pixel position of the caret inside the spacer (before padding).
-}
caretPosition : Metrics -> Array String -> Cursor -> { x : Float, y : Float }
caretPosition metrics lines cursor =
    let
        line =
            Array.get cursor.line lines |> Maybe.withDefault ""
    in
    { x = toFloat (TextBuffer.visualColumn line cursor.col) * metrics.charWidth
    , y = toFloat cursor.line * metrics.lineHeight
    }


type alias Config msg =
    { onScroll :
        Float
        -> Float
        -> msg -- scrollTop scrollLeft
    , highlightLine : String -> Html msg
    , highlightFragment : EditorLayout.Fragment -> Html msg
    , layout : EditorLayout.Layout
    , affinity : EditorLayout.Affinity
    , softWrap : Bool
    , keyDecoder : D.Decoder ( msg, Bool )
    , onInput : String -> msg
    , onPaste : String -> msg
    , onPointerDown : { x : Float, y : Float, shift : Bool, clicks : Int } -> msg
    , onCut : msg
    , cursor : Cursor
    , selection : Maybe ( Cursor, Cursor )
    , highlights : List ( Cursor, Cursor ) -- search matches, drawn under the text
    , activeHighlight : Maybe ( Cursor, Cursor )
    , selectedText : String
    , documentPath : String -- read by js/virtual-input.js, to place pasted images
    , contentLength : Int -- exposed as data-length so tests can check large documents
    }


{-| Rows to render for a scroll position: the visible ones plus `overscan`
above and below so small scrolls don't wait on a render. Inclusive-exclusive.
-}
visibleRange : Metrics -> Float -> Int -> ( Int, Int )
visibleRange metrics scrollTop lineCount =
    let
        first =
            Basics.max 0 (floor (scrollTop / metrics.lineHeight) - overscan)

        visible =
            ceiling (metrics.viewportHeight / metrics.lineHeight)
    in
    ( Basics.min lineCount first
    , Basics.min lineCount (first + visible + 2 * overscan)
    )


overscan : Int
overscan =
    10


view : Config msg -> Metrics -> Float -> Int -> Array String -> Html msg
view config metrics scrollTop maxLineLength lines =
    let
        lineCount =
            EditorLayout.rowCount config.layout

        ( from, to ) =
            visibleRange metrics scrollTop lineCount

        px n =
            String.fromFloat n ++ "px"

        caret =
            if config.softWrap then
                let
                    at =
                        EditorLayout.screenPosition { cursor = config.cursor, affinity = config.affinity } config.layout
                in
                { x = toFloat at.cell * metrics.charWidth, y = toFloat at.row * metrics.lineHeight }

            else
                caretPosition metrics lines config.cursor

        fragments =
            EditorLayout.fragments from to config.layout
    in
    div
        [ class
            (if config.softWrap then
                "veditor wrapped"

             else
                "veditor"
            )
        , id "veditor"
        , attribute "data-testid" "veditor"
        , attribute "data-wrap"
            (if config.softWrap then
                "true"

             else
                "false"
            )
        , attribute "data-length" (String.fromInt config.contentLength)
        , on "scroll" (D.map2 config.onScroll (D.at [ "target", "scrollTop" ] D.float) (D.at [ "target", "scrollLeft" ] D.float))

        -- on the scroller, not the text: clicking anywhere in the pane -
        -- past the last line, in the padding, right of a short line - places
        -- the caret, the way every other editor behaves. Window coordinates,
        -- so it does not matter which element was actually hit.
        , preventDefaultOn "mousedown"
            (D.map4 (\x y shift clicks -> ( config.onPointerDown { x = x, y = y, shift = shift, clicks = clicks }, True ))
                (D.field "clientX" D.float)
                (D.field "clientY" D.float)
                (D.field "shiftKey" D.bool)
                (D.field "detail" D.int)
            )
        ]
        [ div
            [ class "veditor-spacer"
            , style "height" (px (toFloat lineCount * metrics.lineHeight))
            , style "min-width"
                (if config.softWrap then
                    "0"

                 else
                    px (toFloat (maxLineLength + 1) * metrics.charWidth)
                )
            ]
            [ div [ class "veditor-highlight-layer" ]
                (List.concatMap (rangeRects "veditor-highlight" metrics fragments) config.highlights
                    ++ List.concatMap (rangeRects "veditor-highlight active" metrics fragments) (maybeToList config.activeHighlight)
                )
            , div [ class "veditor-selection-layer" ] (selectionRects config.selection metrics fragments)
            , div
                [ class "veditor-rows"
                , style "top" (px (toFloat from * metrics.lineHeight))
                , style "line-height" (px metrics.lineHeight)
                ]
                (List.map
                    (\fragment ->
                        div
                            [ class "veditor-row"
                            , style "height" (px metrics.lineHeight)
                            , attribute "data-source-line" (String.fromInt fragment.line)
                            , attribute "data-source-start" (String.fromInt fragment.segment.start)
                            , attribute "data-source-end" (String.fromInt fragment.segment.end)
                            , attribute "data-source-text" (String.slice fragment.segment.start fragment.segment.end fragment.text)
                            ]
                            [ if config.softWrap then
                                config.highlightFragment fragment

                              else
                                Html.Lazy.lazy config.highlightLine fragment.text
                            ]
                    )
                    fragments
                )
            , div
                [ class "veditor-caret"
                , attribute "data-testid" "veditor-caret"
                , style "left" (px caret.x)
                , style "top" (px caret.y)
                , style "height" (px metrics.lineHeight)
                ]
                []
            , -- Hidden input under the caret: receives keys, IME composition (so
              -- the candidate window appears in place) and paste. Cleared by
              -- js/virtual-input.js after each committed input.
              textarea
                [ class "veditor-input"
                , id "veditor-input"
                , attribute "data-testid" "veditor-input"
                , style "left" (px caret.x)
                , style "top" (px caret.y)
                , style "height" (px metrics.lineHeight)
                , spellcheck False
                , attribute "autocomplete" "off"
                , attribute "autocorrect" "off"
                , attribute "autocapitalize" "off"
                , attribute "aria-label" "Editor"
                , attribute "data-selection" config.selectedText -- read by js/virtual-input.js for copy/cut
                , attribute "data-path" config.documentPath
                , on "fencecut" (D.succeed config.onCut)
                , preventDefaultOn "keydown" config.keyDecoder
                , on "input"
                    (D.field "isComposing" D.bool
                        |> D.andThen
                            (\composing ->
                                if composing then
                                    D.fail "still composing"

                                else
                                    D.map config.onInput (D.at [ "target", "value" ] D.string)
                            )
                    )
                , on "fencepaste" (D.map config.onPaste (D.field "detail" D.string))

                -- an IME commit arrives as compositionend (its input event is
                -- still flagged composing), carrying the composed text
                , on "compositionend" (D.map config.onInput (D.field "data" D.string))
                ]
                []
            ]
        ]


maybeToList : Maybe a -> List a
maybeToList maybe =
    case maybe of
        Just value ->
            [ value ]

        Nothing ->
            []


{-| One highlight box per visible selected row; rows ending inside the
selection get an extra cell for the line break.
-}
selectionRects : Maybe ( Cursor, Cursor ) -> Metrics -> List EditorLayout.Fragment -> List (Html msg)
selectionRects maybeSelection metrics fragments =
    maybeSelection |> Maybe.map (rangeRects "veditor-selection" metrics fragments) |> Maybe.withDefault []


rangeRects : String -> Metrics -> List EditorLayout.Fragment -> ( Cursor, Cursor ) -> List (Html msg)
rangeRects cls metrics fragments ( s, e ) =
    fragments
        |> List.filterMap
            (\fragment ->
                let
                    segment =
                        fragment.segment

                    start =
                        if fragment.line == s.line then
                            max segment.start s.col

                        else
                            segment.start

                    end =
                        if fragment.line == e.line then
                            min segment.end e.col

                        else
                            segment.end

                    newline =
                        fragment.last && fragment.line < e.line

                    cells col =
                        -- Scan only this fragment, even near the end of a huge paragraph.
                        EditorLayout.expandTabs segment.startCell (String.slice segment.start col fragment.text)
                            |> String.toList
                            |> List.length

                    startCell =
                        cells start

                    endCell =
                        cells end
                            + (if newline then
                                1

                               else
                                0
                              )

                    px n =
                        String.fromFloat n ++ "px"
                in
                if fragment.line < s.line || fragment.line > e.line || end < start || endCell <= startCell then
                    Nothing

                else
                    Just
                        (div
                            [ class cls
                            , style "left" (px (toFloat startCell * metrics.charWidth))
                            , style "top" (px (toFloat fragment.row * metrics.lineHeight))
                            , style "width" (px (toFloat (endCell - startCell) * metrics.charWidth))
                            , style "height" (px metrics.lineHeight)
                            ]
                            []
                        )
            )
