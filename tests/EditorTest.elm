module EditorTest exposing (suite)

import Editor
import Json.Decode as D
import Json.Encode as E
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)
import Types exposing (DirtyState(..))


suite : Test
suite =
    describe "Editor"
        [ stateSuite, overlaySuite, progressiveOverlaySuite, editingSuite ]


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



editingSuite : Test
editingSuite =
    let
        opened =
            Editor.setContent "/n/a.md" "hello\nworld" "r" False Editor.init

        type_ chars m =
            List.foldl (\c -> Editor.update (Editor.KeyPressed (Editor.Char c))) m (String.split "" chars)

        press key =
            Editor.update (Editor.KeyPressed key)

        keyEvent key mods =
            E.object
                ([ ( "key", E.string key ), ( "metaKey", E.bool False ), ( "ctrlKey", E.bool False ), ( "shiftKey", E.bool False ), ( "altKey", E.bool False ) ]
                    |> List.map (\( k, v ) -> ( k, if List.member k mods then E.bool True else v ))
                )

        decode key mods =
            D.decodeValue Editor.keyDecoder (keyEvent key mods) |> Result.toMaybe
    in
    describe "virtual editing"
        [ test "typing inserts at the caret, dirties the document and keeps content and lines in sync" <|
            \_ ->
                opened
                    |> press Editor.End
                    |> type_ "!!"
                    |> (\m -> Expect.equal ( "hello!!\nworld", Dirty, { line = 0, col = 7 } ) ( m.content, m.dirtyState, m.cursor ))
        , test "a run of typed characters is one undo step" <|
            \_ ->
                opened
                    |> type_ "abc"
                    |> Editor.update Editor.Undo
                    |> .content
                    |> Expect.equal "hello\nworld"
        , test "a space ends the run so words undo separately" <|
            \_ ->
                opened
                    |> type_ "ab"
                    |> Editor.update (Editor.InsertText " ")
                    |> type_ "cd"
                    |> Editor.update Editor.Undo
                    |> .content
                    |> Expect.equal "ab hello\nworld"
        , test "undo restores the caret and redo re-applies" <|
            \_ ->
                let
                    edited =
                        opened |> press Editor.Right |> type_ "X"

                    undone =
                        Editor.update Editor.Undo edited
                in
                Expect.equal
                    ( ( "hello\nworld", { line = 0, col = 1 } ), ( "hXello\nworld", { line = 0, col = 2 } ) )
                    ( ( undone.content, undone.cursor ), (Editor.update Editor.Redo undone |> (\m -> ( m.content, m.cursor ))) )
        , test "a new edit clears the redo stack" <|
            \_ ->
                opened |> type_ "a" |> Editor.update Editor.Undo |> type_ "b" |> Editor.update Editor.Redo |> .content |> Expect.equal "bhello\nworld"
        , test "enter, tab and shift-tab" <|
            \_ ->
                opened
                    |> press Editor.End
                    |> press Editor.Enter
                    |> press Editor.Tab
                    |> type_ "x"
                    |> press Editor.ShiftTab
                    |> .content
                    |> Expect.equal "hello\nx\nworld"
        , test "pasted multi-line text lands the caret after it" <|
            \_ -> opened |> Editor.update (Editor.InsertText "1\n22") |> (\m -> ( m.content, m.cursor )) |> Expect.equal ( "1\n22hello\nworld", { line = 1, col = 2 } )
        , test "a pointer press maps pixels to a line and column" <|
            \_ ->
                opened
                    |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 400, viewportWidth = 400 })
                    |> Editor.update (Editor.PointerDown 33 25)
                    |> .cursor
                    |> Expect.equal { line = 1, col = 3 }
        , test "opening a file resets the caret and history" <|
            \_ -> opened |> type_ "zzz" |> Editor.setContent "/n/b.md" "new" "r2" False |> (\m -> ( m.cursor, m.undo )) |> Expect.equal ( { line = 0, col = 0 }, [] )
        , test "the key decoder maps editing keys and lets app shortcuts through" <|
            \_ ->
                [ decode "a" [] |> Maybe.map Tuple.first
                , decode "Enter" [] |> Maybe.map Tuple.first
                , decode "z" [ "metaKey" ] |> Maybe.map Tuple.first
                , decode "z" [ "metaKey", "shiftKey" ] |> Maybe.map Tuple.first
                , decode "s" [ "metaKey" ] |> Maybe.map Tuple.first
                , decode "1" [ "metaKey" ] |> Maybe.map Tuple.first
                , decode "Shift" [] |> Maybe.map Tuple.first
                ]
                    |> Expect.equal [ Just (Editor.KeyPressed (Editor.Char "a")), Just (Editor.KeyPressed Editor.Enter), Just Editor.Undo, Just Editor.Redo, Nothing, Nothing, Nothing ]
        , test "the caret scroll target is only set when the caret leaves the viewport" <|
            \_ ->
                let
                    m =
                        Editor.setContent "/n/a.md" (String.repeat 100 "l\n") "r" False Editor.init
                            |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 200, viewportWidth = 400 })
                in
                ( Editor.caretScroll m, Editor.caretScroll (press Editor.DocEnd m) |> Maybe.map .top ) |> Expect.equal ( Nothing, Just (100 * 20 + 20 + 32 - 200) )
        ]
