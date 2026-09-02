module VirtualEditor exposing
    ( Metrics
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
import Html exposing (Html, div)
import Html.Attributes exposing (attribute, class, id, style)
import Html.Events exposing (on)
import Json.Decode as D


{-| Measured once per font/size change by js/editor-metrics.js. -}
type alias Metrics =
    { lineHeight : Float
    , charWidth : Float
    , viewportHeight : Float
    }


defaultMetrics : Metrics
defaultMetrics =
    { lineHeight = 22.4, charWidth = 8.4, viewportHeight = 800 }


metricsDecoder : D.Decoder Metrics
metricsDecoder =
    D.map3 Metrics
        (D.field "lineHeight" D.float)
        (D.field "charWidth" D.float)
        (D.field "viewportHeight" D.float)


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


view :
    { onScroll : Float -> msg, highlightLine : String -> Html msg }
    -> Metrics
    -> Float
    -> Int
    -> Array String
    -> Html msg
view config metrics scrollTop maxLineLength lines =
    let
        lineCount =
            Array.length lines

        ( from, to ) =
            visibleRange metrics scrollTop lineCount

        px n =
            String.fromFloat n ++ "px"
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
            , style "min-width" (px (toFloat maxLineLength * metrics.charWidth))
            ]
            [ div
                [ class "veditor-rows"
                , style "top" (px (toFloat from * metrics.lineHeight))
                , style "line-height" (px metrics.lineHeight)
                ]
                (Array.slice from to lines
                    |> Array.toList
                    |> List.map (\line -> div [ class "veditor-row", style "height" (px metrics.lineHeight) ] [ config.highlightLine line ])
                )
            ]
        ]
