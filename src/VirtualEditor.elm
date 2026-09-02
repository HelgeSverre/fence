module VirtualEditor exposing
    ( Config
    , Metrics
    , caretPosition
    , defaultMetrics
    , metricsDecoder
    , view
    , visibleRange
    )

{-| A read-only virtualized text view: a spacer the size of the whole document
and only the rows that intersect the viewport (plus overscan) rendered as
real DOM. No wrapping; long lines scroll horizontally. See
docs/plans/2026-09-02-virtualized-editor.md.
-}

import Array exposing (Array)
import Html exposing (Html, div, textarea)
import Html.Attributes exposing (attribute, class, id, spellcheck, style, value)
import Html.Events exposing (on, preventDefaultOn)
import Html.Lazy
import Json.Decode as D
import TextBuffer exposing (Cursor)


{-| Measured once per font/size change by js/editor-metrics.js. -}
type alias Metrics =
    { lineHeight : Float
    , charWidth : Float
    , viewportHeight : Float
    , viewportWidth : Float
    }


defaultMetrics : Metrics
defaultMetrics =
    { lineHeight = 22.4, charWidth = 8.4, viewportHeight = 800, viewportWidth = 800 }


metricsDecoder : D.Decoder Metrics
metricsDecoder =
    D.map4 Metrics
        (D.field "lineHeight" D.float)
        (D.field "charWidth" D.float)
        (D.field "viewportHeight" D.float)
        (D.field "viewportWidth" D.float)


{-| Pixel position of the caret inside the spacer (before padding). -}
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
    { onScroll : Float -> msg
    , highlightLine : String -> Html msg
    , keyDecoder : D.Decoder ( msg, Bool )
    , onInput : String -> msg
    , onPaste : String -> msg
    , onPointerDown : Float -> Float -> msg
    , cursor : Cursor
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
            Array.length lines

        ( from, to ) =
            visibleRange metrics scrollTop lineCount

        px n =
            String.fromFloat n ++ "px"

        caret =
            caretPosition metrics lines config.cursor
    in
    div
        [ class "veditor"
        , id "veditor"
        , attribute "data-testid" "veditor"
        , on "scroll" (D.map config.onScroll (D.at [ "target", "scrollTop" ] D.float))
        ]
        [ div
            [ class "veditor-spacer"
            , style "height" (px (toFloat lineCount * metrics.lineHeight))
            , style "min-width" (px (toFloat (maxLineLength + 1) * metrics.charWidth))

            -- rows have pointer-events: none, so offsets are relative to the spacer
            , preventDefaultOn "mousedown" (D.map2 (\x y -> ( config.onPointerDown x y, True )) (D.field "offsetX" D.float) (D.field "offsetY" D.float))
            ]
            [ div
                [ class "veditor-rows"
                , style "top" (px (toFloat from * metrics.lineHeight))
                , style "line-height" (px metrics.lineHeight)
                ]
                (Array.slice from to lines
                    |> Array.toList
                    -- lazy: only the edited row re-tokenizes and re-diffs
                    |> List.map (\line -> div [ class "veditor-row", style "height" (px metrics.lineHeight) ] [ Html.Lazy.lazy config.highlightLine line ])
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
                ]
                []
            ]
        ]
