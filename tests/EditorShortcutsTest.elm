module EditorShortcutsTest exposing (suite)

import Array
import Editor
import Json.Decode as D
import Json.Encode as E
import TextBuffer
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, fuzzWith, noDistribution, test)
import Types exposing (DirtyState(..))


suite : Test
suite =
    describe "Editor: keyboard shortcuts"
        [ markdownSuite, lineOpsSuite, continuationSuite ]


markdownSuite : Test
markdownSuite =
    let
        doc source =
            Editor.setContent "/n/a.md" source "r" False Editor.init

        select from to model =
            { model | anchor = Just { line = 0, col = from }, cursor = { line = 0, col = to } }

        run key model =
            Editor.update (Editor.KeyPressed key) model
    in
    describe "markdown shortcuts"
        [ test "wrapping a selection in bold keeps the words selected" <|
            \_ ->
                doc "one two"
                    |> select 0 3
                    |> run (Editor.Wrap "**")
                    |> (\m -> Expect.equal ( "**one** two", Just "one" ) ( m.content, Maybe.map (always (Editor.selectedText m)) (Editor.selection m) ))
        , test "wrapping again unwraps, so the shortcut toggles" <|
            \_ ->
                doc "one two"
                    |> select 0 3
                    |> run (Editor.Wrap "**")
                    |> run (Editor.Wrap "**")
                    |> (\m -> Expect.equal ( "one two", "one" ) ( m.content, Editor.selectedText m ))
        , test "a selection that includes the markers unwraps too" <|
            \_ ->
                doc "**one** two"
                    |> select 0 7
                    |> run (Editor.Wrap "**")
                    |> .content
                    |> Expect.equal "one two"
        , test "with no selection the markers are inserted around the caret" <|
            \_ ->
                doc "ab"
                    |> (\m -> { m | cursor = { line = 0, col = 1 } })
                    |> run (Editor.Wrap "*")
                    |> (\m -> Expect.equal ( "a**b", { line = 0, col = 2 } ) ( m.content, m.cursor ))
        , test "a link wraps the selection and leaves the caret in the URL" <|
            \_ ->
                doc "click here"
                    |> select 0 5
                    |> run Editor.Link
                    |> (\m -> Expect.equal ( "[click]() here", { line = 0, col = 8 } ) ( m.content, m.cursor ))
        , test "commenting wraps whole lines and toggles back" <|
            \_ ->
                let
                    commented =
                        doc "one\ntwo" |> run Editor.ToggleComment
                in
                Expect.equal
                    ( "<!-- one -->\ntwo", "one\ntwo" )
                    ( commented.content, run Editor.ToggleComment commented |> .content )
        , test "commenting a selection covers every line it touches" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | anchor = Just { line = 0, col = 0 }, cursor = { line = 1, col = 1 } })
                    |> run Editor.ToggleComment
                    |> .content
                    |> Expect.equal "<!-- one -->\n<!-- two -->\nthree"
        , test "a blank line is left alone by commenting" <|
            \_ ->
                doc "one\n\ntwo"
                    |> (\m -> { m | anchor = Just { line = 0, col = 0 }, cursor = { line = 2, col = 1 } })
                    |> run Editor.ToggleComment
                    |> .content
                    |> Expect.equal "<!-- one -->\n\n<!-- two -->"
        , test "pasting a URL over a selection makes it a link" <|
            \_ ->
                doc "click here"
                    |> select 0 5
                    |> Editor.update (Editor.InsertText "https://example.com")
                    |> .content
                    |> Expect.equal "[click](https://example.com) here"
        , test "pasting plain text over a selection still replaces it" <|
            \_ ->
                doc "click here"
                    |> select 0 5
                    |> Editor.update (Editor.InsertText "tap")
                    |> .content
                    |> Expect.equal "tap here"
        , test "pasting a URL with no selection inserts it as text" <|
            \_ ->
                doc "x"
                    |> Editor.update (Editor.InsertText "https://example.com")
                    |> .content
                    |> Expect.equal "https://example.comx"
        , test "the markdown shortcuts are bound" <|
            \_ ->
                let
                    event key mods =
                        E.object
                            ([ ( "key", E.string key ), ( "metaKey", E.bool False ), ( "ctrlKey", E.bool False ), ( "shiftKey", E.bool False ), ( "altKey", E.bool False ) ]
                                |> List.map (\( k, v ) -> ( k, if List.member k mods then E.bool True else v ))
                            )

                    bound key mods =
                        D.decodeValue Editor.keyDecoder (event key mods) |> Result.toMaybe |> Maybe.map Tuple.first
                in
                Expect.equal
                    [ Just (Editor.KeyPressed (Editor.Wrap "**"))
                    , Just (Editor.KeyPressed (Editor.Wrap "*"))
                    , Just (Editor.KeyPressed (Editor.Wrap "`"))
                    , Just (Editor.KeyPressed (Editor.Wrap "~~"))
                    , Just (Editor.KeyPressed Editor.Link)
                    , Just (Editor.KeyPressed Editor.ToggleComment)
                    ]
                    [ bound "b" [ "metaKey" ]
                    , bound "i" [ "metaKey" ]
                    , bound "e" [ "metaKey" ]
                    , bound "x" [ "metaKey", "shiftKey" ]
                    , bound "k" [ "metaKey" ]
                    , bound "/" [ "metaKey" ]
                    ]
        ]


lineOpsSuite : Test
lineOpsSuite =
    let
        doc source =
            Editor.setContent "/n/a.md" source "r" False Editor.init

        run key model =
            Editor.update (Editor.KeyPressed key) model

        -- a selection spanning lines `from` to `to`
        spanning from to model =
            { model | anchor = Just { line = from, col = 0 }, cursor = { line = to, col = 1 } }
    in
    describe "line operations"
        [ test "duplicating copies the line below and keeps the caret on it" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 0, col = 2 } })
                    |> run Editor.DuplicateLine
                    |> (\m -> Expect.equal ( "one\none\ntwo", { line = 1, col = 2 } ) ( m.content, m.cursor ))
        , test "duplicate with no selection copies the line and keeps the column" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | cursor = { line = 1, col = 2 } })
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "one\ntwo\ntwo\nthree", { line = 2, col = 2 } ) ( m.content, m.cursor ))
        , test "duplicate works on the first line" <|
            \_ ->
                doc "one\ntwo"
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "one\none\ntwo", { line = 1, col = 0 } ) ( m.content, m.cursor ))
        , test "duplicate on the last line adds no trailing newline" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 1, col = 3 } })
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "one\ntwo\ntwo", { line = 2, col = 3 } ) ( m.content, m.cursor ))
        , test "repeated duplicates stack up with the caret walking down" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 0, col = 1 } })
                    |> run Editor.Duplicate
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "one\none\none\ntwo", { line = 2, col = 1 } ) ( m.content, m.cursor ))
        , test "duplicate on an empty line adds another empty line" <|
            \_ ->
                doc "one\n\ntwo"
                    |> (\m -> { m | cursor = { line = 1, col = 0 } })
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "one\n\n\ntwo", { line = 2, col = 0 } ) ( m.content, m.cursor ))
        , test "duplicate in an empty document still works" <|
            \_ ->
                doc ""
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "\n", { line = 1, col = 0 } ) ( m.content, m.cursor ))
        , test "duplicating an inline selection copies it in place and selects the copy" <|
            \_ ->
                doc "xabcy"
                    |> (\m -> { m | anchor = Just { line = 0, col = 1 }, cursor = { line = 0, col = 4 } })
                    |> run Editor.Duplicate
                    |> (\m ->
                            Expect.equal
                                ( "xabcabcy", Just ( { line = 0, col = 4 }, { line = 0, col = 7 } ), { line = 0, col = 7 } )
                                ( m.content, Editor.selection m, m.cursor )
                       )
        , test "a selection ending at a line end duplicates without a newline" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | anchor = Just { line = 0, col = 0 }, cursor = { line = 0, col = 3 } })
                    |> run Editor.Duplicate
                    |> (\m -> Expect.equal ( "oneone\ntwo", "one" ) ( m.content, Editor.selectedText m ))
        , test "duplicating a multi-line selection copies it verbatim and selects the copy" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | anchor = Just { line = 0, col = 0 }, cursor = { line = 1, col = 3 } })
                    |> run Editor.Duplicate
                    |> (\m ->
                            Expect.equal
                                ( "one\ntwoone\ntwo\nthree", Just ( { line = 1, col = 3 }, { line = 2, col = 3 } ), "one\ntwo" )
                                ( m.content, Editor.selection m, Editor.selectedText m )
                       )
        , test "duplicating a selection is one undo step" <|
            \_ ->
                doc "xabcy"
                    |> (\m -> { m | anchor = Just { line = 0, col = 1 }, cursor = { line = 0, col = 4 } })
                    |> run Editor.Duplicate
                    |> Editor.update Editor.Undo
                    |> (\m -> Expect.equal ( "xabcy", { line = 0, col = 4 } ) ( m.content, m.cursor ))
        , test "duplicating a line is one undo step" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 1, col = 1 } })
                    |> run Editor.Duplicate
                    |> Editor.update Editor.Undo
                    |> (\m -> Expect.equal ( "one\ntwo", { line = 1, col = 1 } ) ( m.content, m.cursor ))
        , test "duplicating a multi-line selection copies every line" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> spanning 0 1
                    |> run Editor.DuplicateLine
                    |> .content
                    |> Expect.equal "one\ntwo\none\ntwo\nthree"
        , test "moving a line down swaps it with the next and follows the caret" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | cursor = { line = 0, col = 1 } })
                    |> run Editor.MoveLineDown
                    |> (\m -> Expect.equal ( "two\none\nthree", { line = 1, col = 1 } ) ( m.content, m.cursor ))
        , test "moving a line up swaps it with the previous one" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | cursor = { line = 2, col = 0 } })
                    |> run Editor.MoveLineUp
                    |> (\m -> Expect.equal ( "one\nthree\ntwo", { line = 1, col = 0 } ) ( m.content, m.cursor ))
        , test "a move at the document edge does nothing" <|
            \_ ->
                Expect.equal
                    ( "one\ntwo", "one\ntwo" )
                    ( doc "one\ntwo" |> run Editor.MoveLineUp |> .content
                    , doc "one\ntwo" |> (\m -> { m | cursor = { line = 1, col = 0 } }) |> run Editor.MoveLineDown |> .content
                    )
        , test "moving a selection carries the whole block and the selection" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> spanning 0 1
                    |> run Editor.MoveLineDown
                    |> (\m -> Expect.equal ( "three\none\ntwo", Just ( { line = 1, col = 0 }, { line = 2, col = 1 } ) ) ( m.content, Editor.selection m ))
        , test "deleting a line removes it and keeps the caret in the document" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> (\m -> { m | cursor = { line = 1, col = 2 } })
                    |> run Editor.DeleteLine
                    |> (\m -> Expect.equal ( "one\nthree", { line = 1, col = 2 } ) ( m.content, m.cursor ))
        , test "deleting the last line leaves an empty document, never a broken one" <|
            \_ ->
                doc "only"
                    |> run Editor.DeleteLine
                    |> (\m -> Expect.equal ( "", 1 ) ( m.content, Array.length m.lines ))
        , test "deleting a selection removes every line it touches" <|
            \_ ->
                doc "one\ntwo\nthree"
                    |> spanning 0 1
                    |> run Editor.DeleteLine
                    |> .content
                    |> Expect.equal "three"
        , test "opening a line below starts it after the current one" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 0, col = 1 } })
                    |> run Editor.OpenLineBelow
                    |> (\m -> Expect.equal ( "one\n\ntwo", { line = 1, col = 0 } ) ( m.content, m.cursor ))
        , test "opening a line above starts it before the current one" <|
            \_ ->
                doc "one\ntwo"
                    |> (\m -> { m | cursor = { line = 1, col = 1 } })
                    |> run Editor.OpenLineAbove
                    |> (\m -> Expect.equal ( "one\n\ntwo", { line = 1, col = 0 } ) ( m.content, m.cursor ))
        , test "the line shortcuts are bound" <|
            \_ ->
                let
                    event key mods =
                        E.object
                            ([ ( "key", E.string key ), ( "metaKey", E.bool False ), ( "ctrlKey", E.bool False ), ( "shiftKey", E.bool False ), ( "altKey", E.bool False ) ]
                                |> List.map (\( k, v ) -> ( k, if List.member k mods then E.bool True else v ))
                            )

                    bound key mods =
                        D.decodeValue Editor.keyDecoder (event key mods) |> Result.toMaybe |> Maybe.map Tuple.first
                in
                Expect.equal
                    [ Just (Editor.KeyPressed Editor.DuplicateLine)
                    , Just (Editor.KeyPressed Editor.Duplicate)
                    , Just (Editor.KeyPressed Editor.Duplicate)
                    , Just (Editor.KeyPressed Editor.DeleteLine)
                    , Just (Editor.KeyPressed Editor.MoveLineUp)
                    , Just (Editor.KeyPressed Editor.MoveLineDown)
                    , Just (Editor.KeyPressed Editor.OpenLineBelow)
                    , Just (Editor.KeyPressed Editor.OpenLineAbove)
                    ]
                    [ bound "d" [ "metaKey", "shiftKey" ]
                    , bound "d" [ "metaKey" ]
                    , bound "d" [ "ctrlKey" ]
                    , bound "k" [ "metaKey", "shiftKey" ]
                    , bound "ArrowUp" [ "altKey" ]
                    , bound "ArrowDown" [ "altKey" ]
                    , bound "Enter" [ "metaKey" ]
                    , bound "Enter" [ "metaKey", "shiftKey" ]
                    ]
        , test "a line operation is one undo step" <|
            \_ ->
                doc "one\ntwo"
                    |> run Editor.DuplicateLine
                    |> Editor.update Editor.Undo
                    |> .content
                    |> Expect.equal "one\ntwo"
        ]


continuationSuite : Test
continuationSuite =
    let
        -- Enter pressed at the end of a one-line document.
        after source =
            Editor.setContent "/n/a.md" source "r" False Editor.init
                |> Editor.update (Editor.KeyPressed Editor.DocEnd)
                |> Editor.update (Editor.KeyPressed Editor.Enter)
                |> .content
    in
    describe "list continuation"
        [ test "a bullet continues with the same marker and indentation" <|
            \_ -> Expect.equal "  - one\n  - " (after "  - one")
        , test "other bullet characters are repeated as typed" <|
            \_ -> Expect.equal ( "* one\n* ", "+ one\n+ " ) ( after "* one", after "+ one" )
        , test "an ordered item increments the number and keeps the delimiter" <|
            \_ -> Expect.equal ( "1. one\n2. ", "3) one\n4) " ) ( after "1. one", after "3) one" )
        , test "a task item continues unchecked, whatever the box held" <|
            \_ -> Expect.equal ( "- [ ] one\n- [ ] ", "- [x] one\n- [ ] " ) ( after "- [ ] one", after "- [x] one" )
        , test "a blockquote continues" <|
            \_ -> Expect.equal "> quoted\n> " (after "> quoted")
        , test "an empty item ends the list instead of continuing it" <|
            \_ ->
                Expect.equal
                    ( "", "", "" )
                    ( after "- ", after "  1. ", after "> " )
        , test "an empty task item ends the list" <|
            \_ -> Expect.equal "" (after "- [ ] ")
        , test "a plain line still inserts a bare newline" <|
            \_ -> Expect.equal ( "hello\n", "  indented\n" ) ( after "hello", after "  indented" )
        , test "a marker is not continued from inside its own prefix" <|
            \_ ->
                Editor.setContent "/n/a.md" "- one" "r" False Editor.init
                    |> Editor.update (Editor.KeyPressed Editor.Right)
                    |> Editor.update (Editor.KeyPressed Editor.Enter)
                    |> .content
                    |> Expect.equal "-\n one"
        , test "a horizontal rule is not a list item" <|
            \_ -> Expect.equal "---\n" (after "---")
        , test "continuing replaces a selection first" <|
            \_ ->
                Editor.setContent "/n/a.md" "- one two" "r" False Editor.init
                    |> Editor.update (Editor.KeyPressed Editor.DocEnd)
                    |> Editor.update (Editor.Select Editor.WordLeft)
                    |> Editor.update (Editor.KeyPressed Editor.Enter)
                    |> .content
                    |> Expect.equal "- one \n- "
        ]
