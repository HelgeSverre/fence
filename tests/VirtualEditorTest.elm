module VirtualEditorTest exposing (suite)

import Array
import Expect
import Fuzz
import Html
import Json.Decode as D
import Test exposing (Test, describe, fuzz3, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import VirtualEditor


metrics : VirtualEditor.Metrics
metrics =
    { lineHeight = 20, charWidth = 8, viewportHeight = 200, viewportWidth = 400, viewportTop = 0, viewportLeft = 0 }


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
                VirtualEditor.view
                    { onScroll = \_ _ -> ()
                    , highlightLine = Html.text
                    , keyDecoder = D.fail "n/a"
                    , onInput = always ()
                    , onPaste = always ()
                    , onPointerDown = always ()
                    , onCut = ()
                    , cursor = { line = 95, col = 3 }
                    , selection = Just ( { line = 94, col = 2 }, { line = 95, col = 3 } )
                    , selectedText = "ne 94\nlin"
                    , contentLength = 0
                    }
                    metrics
                    2000
                    8
                    lines
                    |> Query.fromHtml
                    |> Expect.all
                        [ Query.findAll [ Selector.class "veditor-row" ] >> Query.count (Expect.equal 30)
                        , Query.find [ Selector.class "veditor-spacer" ] >> Query.has [ Selector.style "height" "200000px" ]
                        , Query.find [ Selector.class "veditor-rows" ] >> Query.has [ Selector.style "top" "1800px" ]
                        , Query.findAll [ Selector.class "veditor-row" ] >> Query.first >> Query.has [ Selector.text "line 90" ]
                        , Query.find [ Selector.class "veditor-caret" ] >> Query.has [ Selector.style "left" "24px", Selector.style "top" "1900px" ]
                        , Query.findAll [ Selector.class "veditor-selection" ] >> Query.count (Expect.equal 2)
                        , Query.findAll [ Selector.class "veditor-selection" ] >> Query.first >> Query.has [ Selector.style "left" "16px", Selector.style "width" "48px" ]
                        ]
        ]
