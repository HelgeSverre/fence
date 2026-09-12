module EditorLayoutTest exposing (suite)

import Array
import Editor
import EditorLayout as Layout exposing (Affinity(..))
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz2, test)
import TextBuffer


parts width text =
    Layout.wrapLine width text |> Array.toList |> List.map (\s -> String.slice s.start s.end text)


opened text =
    Editor.init
        |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 200, viewportWidth = 62, viewportTop = 0, viewportLeft = 0 })
        |> Editor.setContent "/wrap.md" text "r" False


press key =
    Editor.update (Editor.KeyPressed key)


scan f initial items =
    List.foldl (\item acc -> f item (List.head acc |> Maybe.withDefault initial) :: acc) [ initial ] items |> List.reverse


suite : Test
suite =
    describe "soft wrap layout"
        [ test "words, spaces, long words, and exact endings" <|
            \_ ->
                Expect.equal
                    [ [ "hello ", "world" ], [ "abcdef", "gh" ], [ "abcdef" ], [ "      ", " " ], [ "" ] ]
                    [ parts 6 "hello world", parts 6 "abcdefgh", parts 6 "abcdef", parts 6 "       ", parts 6 "" ]
        , test "tabs retain logical tab stops and Unicode offsets never split a pair" <|
            \_ ->
                Expect.equal
                    ( [ "abc", "\td" ], [ "a", "😀", "b", "😀", "c" ], " a b" )
                    ( parts 3 "abc\td", parts 2 "a😀b😀c", Layout.expandTabs 1 "\ta\tb" )
        , test "one-column panes make progress even with a two-cell tab" <|
            \_ -> parts 1 "\t😀x" |> Expect.equal [ "\t", "😀", "x" ]
        , fuzz2 (Fuzz.intRange 1 60) (Fuzz.list (Fuzz.oneOfValues [ 'a', ' ', '\t', '😀', 'x' ])) "wrapping preserves every source character and all legal offsets round trip" <|
            \width chars ->
                let
                    text =
                        String.fromList chars

                    tree =
                        Layout.build width (Array.fromList [ text ])

                    offsets =
                        scan (\c n -> n + String.length (String.fromChar c)) 0 chars

                    roundTrip col =
                        let
                            position =
                                { cursor = { line = 0, col = col }, affinity = Downstream }

                            screen =
                                Layout.screenPosition position tree
                        in
                        (Layout.positionAt screen.row screen.cell tree).cursor.col == col
                in
                Expect.equal ( text, True ) ( String.concat (parts width text), List.all roundTrip offsets )
        , test "a wrap boundary has two screen positions at one source offset" <|
            \_ ->
                let
                    tree =
                        Layout.build 6 (Array.fromList [ "hello world" ])

                    at affinity =
                        Layout.screenPosition { cursor = { line = 0, col = 6 }, affinity = affinity } tree
                in
                Expect.equal ( { row = 0, cell = 6 }, { row = 1, cell = 0 } ) ( at Upstream, at Downstream )
        , fuzz2 (Fuzz.intRange 1 40) (Fuzz.list (Fuzz.intRange 0 100)) "tree splice sequences match a full rebuild" <|
            \width edits ->
                let
                    initial =
                        Array.initialize 60 (\i -> String.repeat (modBy 12 i) "word ")

                    step n ( lines, tree, valid ) =
                        let
                            from =
                                modBy (Array.length lines + 1) n

                            removed =
                                min (modBy 4 n) (Array.length lines - from)

                            added =
                                Array.initialize (modBy 5 n) (\i -> String.repeat (i + 1) "changed 😀 ")

                            next =
                                Array.append (Array.append (Array.slice 0 from lines) added) (Array.slice (from + removed) (Array.length lines) lines)

                            indexed =
                                Layout.replace width from removed added tree

                            rebuilt =
                                Layout.build width next

                            rows t =
                                Layout.fragments 0 (Layout.rowCount t) t
                        in
                        ( next, indexed, valid && rows indexed == rows rebuilt )

                    ( _, _, result ) =
                        List.foldl step ( initial, Layout.build width initial, True ) edits
                in
                Expect.equal True result
        , test "Home and End use screen rows; right advances source text at a boundary" <|
            \_ ->
                let
                    end =
                        opened "hello world" |> press Editor.End

                    down =
                        end |> press Editor.Down
                in
                Expect.equal
                    ( Upstream, [ 6, 11, 6, 7 ] )
                    ( end.affinity, [ end.cursor.col, down.cursor.col, (down |> press Editor.Home).cursor.col, (end |> press Editor.Right).cursor.col ] )
        , test "vertical navigation retains its desired column through short rows" <|
            \_ ->
                opened "abcdef\nx\nabcdef"
                    |> press Editor.Right
                    |> press Editor.Right
                    |> press Editor.Right
                    |> press Editor.Down
                    |> press Editor.Down
                    |> .cursor
                    |> Expect.equal { line = 2, col = 3 }
        , test "selection over a soft break contains no synthetic newline and undo restores text/layout" <|
            \_ ->
                let
                    original =
                        opened "hello world"

                    selected =
                        original |> press Editor.End |> Editor.update (Editor.Select Editor.Down)

                    changed =
                        selected |> Editor.update (Editor.InsertText "there")

                    undone =
                        changed |> Editor.update Editor.Undo
                in
                Expect.equal
                    ( [ "world", "hello there", original.content ], Layout.rowCount original.layout )
                    ( [ Editor.selectedText selected, changed.content, undone.content ], Layout.rowCount undone.layout )
        , test "bulk and whole-line operations always refresh the layout" <|
            \_ ->
                let
                    check model =
                        Layout.fragments 0 (Layout.rowCount model.layout) model.layout
                            == Layout.fragments 0 (Layout.rowCount (Layout.build model.wrapColumns model.lines)) (Layout.build model.wrapColumns model.lines)

                    initial =
                        opened "hello world\nsecond paragraph\nend"

                    states =
                        scan Editor.update
                            initial
                            [ Editor.SelectAll
                            , Editor.KeyPressed Editor.Tab
                            , Editor.KeyPressed Editor.ShiftTab
                            , Editor.KeyPressed Editor.DuplicateLine
                            , Editor.KeyPressed Editor.MoveLineDown
                            , Editor.KeyPressed Editor.DeleteLine
                            , Editor.Undo
                            , Editor.Redo
                            , Editor.InsertText "one\ntwo\nthree"
                            , Editor.Undo
                            ]
                in
                Expect.equal True (List.all check states)
        , test "toggling leaves content, cursor, dirty state and undo unchanged" <|
            \_ ->
                let
                    model =
                        opened "hello world" |> press Editor.End

                    off =
                        model |> Editor.update (Editor.SetSoftWrap False)
                in
                Expect.equal ( ( model.content, model.cursor, model.dirtyState ), model.undo, 1 ) ( ( off.content, off.cursor, off.dirtyState ), off.undo, Layout.rowCount off.layout )
        , test "a local edit near the end preserves the untouched prefix and suffix" <|
            \_ ->
                let
                    initial =
                        Editor.setContent "/big.md" (String.repeat 1000 "a line with words\n") "r" False (opened "")
                            |> Editor.gotoLine 990
                            |> press Editor.End

                    edited =
                        initial |> Editor.update (Editor.InsertText "more\ntext") |> press Editor.Backspace

                    rebuilt =
                        Layout.build edited.wrapColumns edited.lines
                in
                Expect.equal
                    (Layout.fragments 0 (Layout.rowCount rebuilt) rebuilt)
                    (Layout.fragments 0 (Layout.rowCount edited.layout) edited.layout)
        , test "a range spanning many lines stays indexed after deletion and undo" <|
            \_ ->
                let
                    initial =
                        opened (String.repeat 100 "a long logical line\n")

                    selected =
                        initial |> Editor.selectRange ( { line = 10, col = 2 }, { line = 80, col = 3 } )

                    edited =
                        selected |> press Editor.Backspace

                    rebuilt =
                        Layout.build edited.wrapColumns edited.lines
                in
                Expect.equal
                    ( Layout.fragments 0 (Layout.rowCount rebuilt) rebuilt, initial.content )
                    ( Layout.fragments 0 (Layout.rowCount edited.layout) edited.layout, (edited |> Editor.update Editor.Undo).content )
        , test "preview lookup interpolates within a wrapped source line" <|
            \_ -> Layout.sourceLine 1 (Layout.build 6 (TextBuffer.fromString "hello world\nend")) |> Expect.within (Expect.Absolute 0.001) 0.5
        ]
