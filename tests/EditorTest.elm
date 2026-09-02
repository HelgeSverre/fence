module EditorTest exposing (suite)

import Editor
import Json.Decode as D
import Json.Encode as E
import Fuzz
import TextBuffer
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, fuzzWith, noDistribution, test)
import Types exposing (DirtyState(..))


suite : Test
suite =
    describe "Editor"
        [ stateSuite, overlaySuite, progressiveOverlaySuite, editingSuite, selectionSuite, referenceSuite ]


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
                    |> Editor.update (Editor.PointerDown { x = 33, y = 25, shift = False, clicks = 1 })
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
            Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 400, viewportWidth = 400 })

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
                    |> Editor.update (Editor.PointerMove 30 0)
                    |> Editor.update Editor.PointerUp
                    |> (\m -> ( Editor.dragging m, Editor.selectedText m ))
                    |> Expect.equal ( False, "hel" )
        , test "a click without movement leaves no selection" <|
            \_ -> opened |> metrics |> click 1 0 0 False |> Editor.update Editor.PointerUp |> Editor.selection |> Expect.equal Nothing
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



-- REFERENCE MODEL: a plain string with integer offsets, used to fuzz the editor


type Op
    = TypeChar String
    | Newline
    | BackspaceOp
    | DeleteOp
    | LeftOp Bool
    | RightOp Bool
    | HomeOp Bool
    | EndOp Bool
    | SelectAllOp
    | PasteOp String


type alias Ref =
    { text : String, cursor : Int, anchor : Maybe Int }


refApply : Op -> Ref -> Ref
refApply op ref =
    let
        sel =
            ref.anchor |> Maybe.andThen (\a -> if a == ref.cursor then Nothing else Just ( Basics.min a ref.cursor, Basics.max a ref.cursor ))

        deleteSel =
            case sel of
                Just ( s, e ) ->
                    { text = String.left s ref.text ++ String.dropLeft e ref.text, cursor = s, anchor = Nothing }

                Nothing ->
                    { ref | anchor = Nothing }

        insertAt str r =
            { r | text = String.left r.cursor r.text ++ str ++ String.dropLeft r.cursor r.text, cursor = r.cursor + String.length str }

        move extend target =
            { ref | cursor = target, anchor = if extend then Just (Maybe.withDefault ref.cursor ref.anchor) else Nothing }

        lineStartOf i =
            String.left i ref.text |> String.indexes "\n" |> List.reverse |> List.head |> Maybe.map ((+) 1) |> Maybe.withDefault 0

        lineEndOf i =
            String.dropLeft i ref.text |> String.indexes "\n" |> List.head |> Maybe.map ((+) i) |> Maybe.withDefault (String.length ref.text)
    in
    case op of
        TypeChar c ->
            insertAt c deleteSel

        PasteOp str ->
            insertAt str deleteSel

        Newline ->
            insertAt "\n" deleteSel

        BackspaceOp ->
            case sel of
                Just _ ->
                    deleteSel

                Nothing ->
                    if ref.cursor > 0 then
                        { ref | text = String.left (ref.cursor - 1) ref.text ++ String.dropLeft ref.cursor ref.text, cursor = ref.cursor - 1, anchor = Nothing }

                    else
                        { ref | anchor = Nothing }

        DeleteOp ->
            case sel of
                Just _ ->
                    deleteSel

                Nothing ->
                    { ref | text = String.left ref.cursor ref.text ++ String.dropLeft (ref.cursor + 1) ref.text, anchor = Nothing }

        LeftOp extend ->
            move extend (Basics.max 0 (ref.cursor - 1))

        RightOp extend ->
            move extend (Basics.min (String.length ref.text) (ref.cursor + 1))

        HomeOp extend ->
            move extend (lineStartOf ref.cursor)

        EndOp extend ->
            move extend (lineEndOf ref.cursor)

        SelectAllOp ->
            { ref | anchor = Just 0, cursor = String.length ref.text }


editorApply : Op -> Editor.Model -> Editor.Model
editorApply op =
    let
        key extend k =
            Editor.update (if extend then Editor.Select k else Editor.KeyPressed k)
    in
    case op of
        TypeChar c ->
            Editor.update (Editor.KeyPressed (Editor.Char c))

        PasteOp str ->
            Editor.update (Editor.InsertText str)

        Newline ->
            Editor.update (Editor.KeyPressed Editor.Enter)

        BackspaceOp ->
            Editor.update (Editor.KeyPressed Editor.Backspace)

        DeleteOp ->
            Editor.update (Editor.KeyPressed Editor.DeleteKey)

        LeftOp extend ->
            key extend Editor.Left

        RightOp extend ->
            key extend Editor.Right

        HomeOp extend ->
            key extend Editor.Home

        EndOp extend ->
            key extend Editor.End

        SelectAllOp ->
            Editor.update Editor.SelectAll


opFuzzer : Fuzz.Fuzzer Op
opFuzzer =
    Fuzz.frequency
        [ ( 5, Fuzz.map TypeChar (Fuzz.oneOfValues [ "a", "b", " ", "*", "\t", "é", "😀" ]) )
        , ( 2, Fuzz.constant Newline )
        , ( 3, Fuzz.constant BackspaceOp )
        , ( 1, Fuzz.constant DeleteOp )
        , ( 3, Fuzz.map LeftOp Fuzz.bool )
        , ( 3, Fuzz.map RightOp Fuzz.bool )
        , ( 1, Fuzz.map HomeOp Fuzz.bool )
        , ( 1, Fuzz.map EndOp Fuzz.bool )
        , ( 1, Fuzz.constant SelectAllOp )
        , ( 1, Fuzz.map PasteOp (Fuzz.oneOfValues [ "x\ny", "\n\n", "one two" ]) )
        ]


referenceSuite : Test
referenceSuite =
    fuzzWith { runs = 300, distribution = noDistribution } (Fuzz.listOfLengthBetween 0 40 opFuzzer) "random edit sequences match a plain-string reference model" <|
        \ops ->
            let
                start =
                    "ab\ncd"

                ref =
                    List.foldl refApply { text = start, cursor = 0, anchor = Nothing } ops

                editor =
                    List.foldl editorApply (Editor.setContent "/n/a.md" start "r" False Editor.init) ops
            in
            Expect.equal
                ( ref.text, ref.cursor, ref.anchor |> Maybe.andThen (\a -> if a == ref.cursor then Nothing else Just (Basics.min a ref.cursor)) )
                ( editor.content, TextBuffer.offsetOf editor.lines editor.cursor, Editor.selection editor |> Maybe.map (\( s, _ ) -> TextBuffer.offsetOf editor.lines s) )
