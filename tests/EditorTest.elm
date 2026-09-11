module EditorTest exposing (suite)

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
    describe "Editor: cursor, selection and state"
        [ stateSuite, overlaySuite, selectionSuite ]


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
                    |> Editor.update (Editor.ScrollChanged 400 0)
                    |> Editor.setContent "/notes/a.md" "x" "rev-1" False
                    |> .scrollTop
                    |> Expect.equal 0
        , test "a save acknowledgement does not clean newer edits" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "one" "rev-1" False
                    |> Editor.update (Editor.KeyPressed Editor.DocEnd)
                    |> Editor.update (Editor.InsertText "-two")
                    |> Editor.update (Editor.InsertText "-three")
                    |> Editor.markSaved "one-two" "rev-2"
                    |> (\model ->
                            Expect.equal
                                ( Dirty, Just "rev-2", "one-two-three" )
                                ( model.dirtyState, model.revision, model.content )
                       )
        , test "a save acknowledgement for the current content cleans the document" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "one" "rev-1" False
                    |> Editor.update (Editor.KeyPressed Editor.DocEnd)
                    |> Editor.update (Editor.InsertText "-two")
                    |> Editor.markSaved "one-two" "rev-2"
                    |> .dirtyState
                    |> Expect.equal Clean
        ]


{-| Every line's tokens must concatenate back to exactly the source line, or
the rendered row would not match the document.
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
        ]


selectionSuite : Test
selectionSuite =
    let
        opened =
            Editor.setContent "/n/a.md" "hello world\nsecond line\nthird" "r" False Editor.init

        press key =
            Editor.update (Editor.KeyPressed key)

        select key =
            Editor.update (Editor.Select key)

        type_ chars m =
            List.foldl (\c -> Editor.update (Editor.KeyPressed (Editor.Char c))) m (String.split "" chars)

        metrics =
            Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 400, viewportWidth = 400, viewportTop = 0, viewportLeft = 0 })

        click clicks x y shift =
            Editor.update (Editor.PointerDown { x = x, y = y, shift = shift, clicks = clicks })
    in
    describe "selection"
        [ test "shift+right extends and the selected text is exposed" <|
            \_ -> opened |> select Editor.Right |> select Editor.Right |> Editor.selectedText |> Expect.equal "he"
        , test "a plain movement clears the selection" <|
            \_ -> opened |> select Editor.Right |> press Editor.Left |> Editor.selection |> Expect.equal Nothing
        , test "typing replaces the selection in one undo step" <|
            \_ ->
                let
                    m =
                        opened |> select Editor.End |> type_ "X"
                in
                ( m.content, Editor.update Editor.Undo m |> .content ) |> Expect.equal ( "X\nsecond line\nthird", "hello world\nsecond line\nthird" )
        , test "backspace with a selection deletes only the selection" <|
            \_ -> opened |> select Editor.Right |> select Editor.Right |> press Editor.Backspace |> .content |> Expect.equal "llo world\nsecond line\nthird"
        , test "select all then delete empties the document" <|
            \_ -> opened |> Editor.update Editor.SelectAll |> press Editor.DeleteKey |> .content |> Expect.equal ""
        , test "a multi-line selection spanning lines is sliced with line breaks" <|
            \_ -> opened |> press Editor.End |> select Editor.Down |> Editor.selectedText |> Expect.equal "\nsecond line"
        , test "Tab on a multi-line selection indents those lines and keeps them selected" <|
            \_ ->
                let
                    m =
                        opened |> select Editor.Down |> press Editor.Tab
                in
                -- a selection ending at column 0 of the next line does not include that line
                ( m.content, Editor.selection m |> Maybe.map (\( s, e ) -> ( s.line, e.line )) ) |> Expect.equal ( "\thello world\nsecond line\nthird", Just ( 0, 1 ) )
        , test "Shift+Tab on a multi-line selection unindents" <|
            \_ -> opened |> select Editor.Down |> press Editor.Tab |> press Editor.ShiftTab |> .content |> Expect.equal "hello world\nsecond line\nthird"
        , test "cut removes the selection" <|
            \_ -> opened |> select Editor.Right |> Editor.update Editor.CutSelection |> .content |> Expect.equal "ello world\nsecond line\nthird"
        , test "double-click selects the word under the pointer" <|
            \_ -> opened |> metrics |> click 2 75 10 False |> Editor.selectedText |> Expect.equal "world"
        , test "triple-click selects the whole line including its break" <|
            \_ -> opened |> metrics |> click 3 20 10 False |> Editor.selectedText |> Expect.equal "hello world\n"
        , test "shift-click extends from the caret" <|
            \_ -> opened |> metrics |> click 1 0 0 False |> click 1 50 30 True |> Editor.selectedText |> Expect.equal "hello world\nsecon"
        , test "dragging selects and releasing keeps the selection" <|
            \_ ->
                opened
                    |> metrics
                    |> click 1 0 0 False
                    |> Editor.update (Editor.PointerMoved 30 0)
                    |> Editor.update Editor.PointerUp
                    |> (\m -> ( Editor.dragging m, Editor.selectedText m ))
                    |> Expect.equal ( False, "hel" )
        , describe "a drag held outside the editor keeps scrolling"
            (let
                dragging =
                    Editor.setContent "/n/a.md" (String.repeat 300 "a line of text\n") "r" False Editor.init
                        |> metrics
                        |> click 1 0 0 False

                afterFrame pointerY model =
                    model
                        |> Editor.update (Editor.PointerMoved 0 pointerY)
                        |> Editor.update Editor.AutoScrolled
             in
             -- the viewport spans y 0..400 in window coordinates
             [ test "a pointer inside the editor does not scroll" <|
                \_ -> afterFrame 100 dragging |> .scrollTop |> Expect.within (Expect.Absolute 0.01) 0
             , test "just past the bottom edge creeps" <|
                \_ -> afterFrame 440 dragging |> .scrollTop |> Expect.within (Expect.Absolute 0.01) 10
             , test "far past the edge races, but no faster than the cap" <|
                \_ -> afterFrame 5000 dragging |> .scrollTop |> Expect.within (Expect.Absolute 0.01) 28
             , test "each frame scrolls again while the pointer is held there" <|
                \_ ->
                    dragging
                        |> afterFrame 440
                        |> Editor.update Editor.AutoScrolled
                        |> Editor.update Editor.AutoScrolled
                        |> .scrollTop
                        |> Expect.within (Expect.Absolute 0.01) 30
             , test "above the top edge scrolls back, and stops at the start" <|
                \_ ->
                    Expect.all
                        [ \_ -> dragging |> Editor.update (Editor.ScrollChanged 100 0) |> afterFrame -40 |> .scrollTop |> Expect.within (Expect.Absolute 0.01) 90
                        , \_ -> afterFrame -40 dragging |> .scrollTop |> Expect.within (Expect.Absolute 0.01) 0
                        ]
                        ()
             , test "the selection grows to the newly revealed text" <|
                \_ ->
                    let
                        scrolled =
                            List.foldl (\_ m -> Editor.update Editor.AutoScrolled m) (Editor.update (Editor.PointerMoved 0 5000) dragging) (List.range 1 20)
                    in
                    Expect.all
                        [ \_ -> scrolled.scrollTop |> Expect.atLeast 500
                        , \_ -> scrolled.cursor.line |> Expect.atLeast 25
                        , \_ -> String.length (Editor.selectedText scrolled) |> Expect.atLeast 300
                        ]
                        ()
             , test "releasing the mouse stops the scrolling" <|
                \_ ->
                    dragging
                        |> Editor.update (Editor.PointerMoved 0 5000)
                        |> Editor.update Editor.PointerUp
                        |> Editor.update Editor.AutoScrolled
                        |> .scrollTop
                        |> Expect.within (Expect.Absolute 0.01) 0
             ]
            )
        , test "a click without movement leaves no selection" <|
            \_ -> opened |> metrics |> click 1 0 0 False |> Editor.update Editor.PointerUp |> Editor.selection |> Expect.equal Nothing
        , test "word motion moves and selects by word" <|
            \_ ->
                let
                    m =
                        Editor.setContent "/n/a.md" "alpha beta gamma" "r" False Editor.init
                in
                Expect.all
                    [ \_ -> press Editor.WordRight m |> .cursor |> Expect.equal { line = 0, col = 5 }
                    , \_ -> m |> press Editor.WordRight |> press Editor.WordRight |> press Editor.WordLeft |> .cursor |> Expect.equal { line = 0, col = 6 }
                    , \_ -> m |> select Editor.WordRight |> Editor.selectedText |> Expect.equal "alpha"
                    ]
                    ()
        , test "word and line deletion" <|
            \_ ->
                let
                    m =
                        Editor.setContent "/n/a.md" "alpha beta gamma" "r" False Editor.init |> press Editor.End
                in
                Expect.all
                    [ \_ -> press Editor.DeleteWordBack m |> .content |> Expect.equal "alpha beta "
                    , \_ -> press Editor.DeleteToLineStart m |> .content |> Expect.equal ""
                    , \_ -> Editor.setContent "/n/a.md" "alpha beta" "r" False Editor.init |> press Editor.DeleteWordForward |> .content |> Expect.equal " beta"
                    , \_ -> m |> press Editor.DeleteWordBack |> press Editor.DeleteWordBack |> Editor.update Editor.Undo |> .content |> Expect.equal "alpha beta "
                    ]
                    ()
        , test "deleting with a selection removes exactly the selection" <|
            \_ ->
                Editor.setContent "/n/a.md" "alpha beta" "r" False Editor.init
                    |> select Editor.WordRight
                    |> press Editor.DeleteWordBack
                    |> .content
                    |> Expect.equal " beta"
        , test "the key decoder maps modifier scopes to word, line and character motion" <|
            \_ ->
                let
                    ev key mods =
                        E.object ([ ( "key", E.string key ), ( "metaKey", E.bool False ), ( "ctrlKey", E.bool False ), ( "shiftKey", E.bool False ), ( "altKey", E.bool False ) ] |> List.map (\( k, v ) -> ( k, if List.member k mods then E.bool True else v )))

                    decoded key mods =
                        D.decodeValue Editor.keyDecoder (ev key mods) |> Result.toMaybe |> Maybe.map Tuple.first
                in
                Expect.equal
                    [ Just (Editor.KeyPressed Editor.Left)
                    , Just (Editor.KeyPressed Editor.WordLeft)
                    , Just (Editor.KeyPressed Editor.WordLeft)
                    , Just (Editor.KeyPressed Editor.Home)
                    , Just (Editor.Select Editor.WordRight)
                    , Just (Editor.KeyPressed Editor.DeleteWordBack)
                    , Just (Editor.KeyPressed Editor.DeleteToLineStart)
                    , Just (Editor.KeyPressed Editor.DeleteWordForward)
                    ]
                    [ decoded "ArrowLeft" []
                    , decoded "ArrowLeft" [ "altKey" ]
                    , decoded "ArrowLeft" [ "ctrlKey" ]
                    , decoded "ArrowLeft" [ "metaKey" ]
                    , decoded "ArrowRight" [ "altKey", "shiftKey" ]
                    , decoded "Backspace" [ "altKey" ]
                    , decoded "Backspace" [ "metaKey" ]
                    , decoded "Delete" [ "altKey" ]
                    ]
        , test "the key decoder turns shift+movement into Select and Cmd+A into SelectAll" <|
            \_ ->
                let
                    ev key mods =
                        E.object ([ ( "key", E.string key ), ( "metaKey", E.bool False ), ( "ctrlKey", E.bool False ), ( "shiftKey", E.bool False ), ( "altKey", E.bool False ) ] |> List.map (\( k, v ) -> ( k, if List.member k mods then E.bool True else v )))
                in
                [ D.decodeValue Editor.keyDecoder (ev "ArrowRight" [ "shiftKey" ]) |> Result.toMaybe |> Maybe.map Tuple.first
                , D.decodeValue Editor.keyDecoder (ev "a" [ "metaKey" ]) |> Result.toMaybe |> Maybe.map Tuple.first
                , D.decodeValue Editor.keyDecoder (ev "c" [ "metaKey" ]) |> Result.toMaybe |> Maybe.map Tuple.first
                ]
                    |> Expect.equal [ Just (Editor.Select Editor.Right), Just Editor.SelectAll, Nothing ]
        ]
