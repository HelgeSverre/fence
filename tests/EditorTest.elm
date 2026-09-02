module EditorTest exposing (suite)

import Editor
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)
import Types exposing (DirtyState(..))


suite : Test
suite =
    describe "Editor"
        [ stateSuite, overlaySuite, progressiveOverlaySuite ]


stateSuite : Test
stateSuite =
    describe "state"
        [ test "opened files retain their disk revision" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "hello" "rev-1" False
                    |> (\model ->
                            Expect.equal
                                ( Just "rev-1", Clean )
                                ( model.revision, model.dirtyState )
                       )
        , test "recovered drafts open dirty" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "recovered" "rev-1" True
                    |> .dirtyState
                    |> Expect.equal Dirty
        , test "opening a file resets the scroll position" <|
            \_ ->
                Editor.init
                    |> Editor.update (Editor.ScrollChanged 400)
                    |> Editor.setContent "/notes/a.md" "x" "rev-1" False
                    |> .scrollTop
                    |> Expect.equal 0
        , test "a save acknowledgement does not clean newer edits" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "one" "rev-1" False
                    |> Editor.update (Editor.ContentChanged "two")
                    |> Editor.update (Editor.ContentChanged "three")
                    |> Editor.markSaved "two" "rev-2"
                    |> (\model ->
                            Expect.equal
                                ( Dirty, Just "rev-2", "three" )
                                ( model.dirtyState, model.revision, model.content )
                       )
        , test "a save acknowledgement for the current content cleans the document" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "one" "rev-1" False
                    |> Editor.update (Editor.ContentChanged "two")
                    |> Editor.markSaved "two" "rev-2"
                    |> .dirtyState
                    |> Expect.equal Clean
        ]


{-| The highlight overlay sits behind a transparent textarea, so every line's
tokens must concatenate back to exactly the source line or the caret drifts.
-}
overlaySuite : Test
overlaySuite =
    let
        joined line =
            Editor.lineTokens line |> List.map .text |> String.concat

        classes line =
            Editor.lineTokens line |> List.filterMap .class
    in
    describe "overlay tokens"
        [ fuzz Fuzz.string "tokens always concatenate back to the source line" <|
            \line -> joined line |> Expect.equal line
        , test "tricky markdown lines round-trip" <|
            \_ ->
                [ "# Heading with **bold** and `code`"
                , "  - nested item with [link](https://x.y) and *em*"
                , "1. ordered **item**"
                , "10. two-digit ordered"
                , "> quote with `code`"
                , "```js"
                , "---"
                , "unclosed **bold and *italic and `code"
                , "[not a link"
                , "trailing spaces   "
                , "\ttab\tindented"
                , "***"
                , ""
                , "**"
                , "*"
                , "`"
                , "😀*" -- astral char before a delimiter: used to split the surrogate pair and hang
                , "😀`"
                , "😀["
                , "a😀b*c*"
                ]
                    |> List.map (\line -> ( line, joined line ))
                    |> List.filter (\( a, b ) -> a /= b)
                    |> Expect.equal []
        , test "headings are one styled run" <|
            \_ -> classes "## Title **bold**" |> Expect.equal [ "md-h2" ]
        , test "list items get a marker class and inline highlighting" <|
            \_ -> classes "- item **bold** `code`" |> Expect.equal [ "md-list-marker", "md-bold-marker", "md-code-span" ]
        , test "ordered list markers include the number" <|
            \_ ->
                Editor.lineTokens "12. item"
                    |> List.filter (\t -> t.class == Just "md-list-marker")
                    |> List.map .text
                    |> Expect.equal [ "12. " ]
        , test "links are a single styled run" <|
            \_ -> classes "see [docs](https://x.y/a) now" |> Expect.equal [ "md-link" ]
        , test "a hashtag without a space is not a heading" <|
            \_ -> classes "#hashtag" |> Expect.equal []
        , test "chunksOf splits into fixed-size groups with a short tail" <|
            \_ -> Editor.chunksOf 2 [ 1, 2, 3, 4, 5 ] |> Expect.equal [ [ 1, 2 ], [ 3, 4 ], [ 5 ] ]
        , test "chunksOf of nothing is nothing" <|
            \_ -> Editor.chunksOf 3 ([] |> List.map identity) |> List.length |> Expect.equal 0
        , test "the plain-text fallback threshold is well above typical documents" <|
            \_ -> Editor.maxHighlightedCharacters |> Expect.atLeast 1000000
        ]



progressiveOverlaySuite : Test
progressiveOverlaySuite =
    let
        bigDoc =
            String.repeat 3000 "line\n"

        opened =
            Editor.setContent "/n/big.md" bigDoc "r" False Editor.init
    in
    describe "progressive overlay"
        [ test "small documents highlight everything at once" <|
            \_ -> Editor.setContent "/n/a.md" "# a\nb" "r" False Editor.init |> Editor.overlayPending |> Expect.equal False
        , test "large documents start with a partial overlay" <|
            \_ -> Editor.overlayPending opened |> Expect.equal True
        , test "steps extend the overlay until it covers the document" <|
            \_ ->
                let
                    stepsUntilDone m n =
                        if Editor.overlayPending m && n < 50 then
                            stepsUntilDone (Editor.update Editor.OverlayStep m) (n + 1)

                        else
                            n
                in
                stepsUntilDone opened 0 |> Expect.all [ Expect.atLeast 1, Expect.atMost 3 ]
        , test "typing while the overlay is filling does not restart it" <|
            \_ ->
                opened
                    |> Editor.update Editor.OverlayStep
                    |> Editor.update (Editor.ContentChanged (bigDoc ++ "x"))
                    |> .overlayLines
                    |> Expect.equal (Editor.update Editor.OverlayStep opened).overlayLines
        ]
