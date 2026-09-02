module VirtualEditorTest exposing (suite)

import Array
import Expect
import Fuzz
import Html
import Test exposing (Test, describe, fuzz3, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import VirtualEditor


metrics : VirtualEditor.Metrics
metrics =
    { lineHeight = 20, charWidth = 8, viewportHeight = 200 }


suite : Test
suite =
    describe "VirtualEditor"
        [ test "the first screen renders the visible rows plus overscan" <|
            \_ -> VirtualEditor.visibleRange metrics 0 10000 |> Expect.equal ( 0, 30 )
        , test "scrolling moves the window and keeps overscan above" <|
            \_ -> VirtualEditor.visibleRange metrics 2000 10000 |> Expect.equal ( 90, 120 )
        , test "the window is clamped to the document" <|
            \_ -> VirtualEditor.visibleRange metrics 199900 10000 |> Expect.equal ( 9985, 10000 )
        , test "an empty document renders nothing" <|
            \_ -> VirtualEditor.visibleRange metrics 0 0 |> Expect.equal ( 0, 0 )
        , fuzz3 (Fuzz.floatRange 0 1000000) (Fuzz.intRange 0 50000) (Fuzz.floatRange 100 2000) "the window always covers the viewport and stays inside the document" <|
            \scrollTop lineCount viewport ->
                let
                    m =
                        { metrics | viewportHeight = viewport }

                    ( from, to ) =
                        VirtualEditor.visibleRange m scrollTop lineCount

                    firstVisible =
                        clamp 0 lineCount (floor (scrollTop / m.lineHeight))
                in
                Expect.all
                    [ \_ -> from |> Expect.atLeast 0
                    , \_ -> to |> Expect.atMost lineCount
                    , \_ -> from |> Expect.atMost to
                    , \_ -> from |> Expect.atMost firstVisible
                    , \_ -> to - from |> Expect.atMost (ceiling (viewport / m.lineHeight) + 20)
                    ]
                    ()
        , test "the view renders only the window's rows over a full-height spacer" <|
            \_ ->
                let
                    lines =
                        Array.initialize 10000 (\i -> "line " ++ String.fromInt i)
                in
                VirtualEditor.view { onScroll = always (), highlightLine = Html.text } metrics 2000 8 lines
                    |> Query.fromHtml
                    |> Expect.all
                        [ Query.findAll [ Selector.class "veditor-row" ] >> Query.count (Expect.equal 30)
                        , Query.find [ Selector.class "veditor-spacer" ] >> Query.has [ Selector.style "height" "200000px" ]
                        , Query.find [ Selector.class "veditor-rows" ] >> Query.has [ Selector.style "top" "1800px" ]
                        , Query.findAll [ Selector.class "veditor-row" ] >> Query.first >> Query.has [ Selector.text "line 90" ]
                        ]
        ]
