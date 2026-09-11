module EditorEditingTest exposing (suite)

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
    describe "Editor: editing, undo and reload"
        [ editingSuite, referenceSuite, reloadSuite ]


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
                    |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 400, viewportWidth = 400, viewportTop = 0, viewportLeft = 0 })
                    |> Editor.update (Editor.PointerDown { x = 33, y = 25, shift = False, clicks = 1 })
                    |> .cursor
                    |> Expect.equal { line = 1, col = 3 }
        , test "a never-opened editor is one empty line, so typing works" <|
            \_ ->
                Editor.init
                    |> Editor.update (Editor.KeyPressed (Editor.Char "a"))
                    |> (\m -> ( m.content, m.cursor ))
                    |> Expect.equal ( "a", { line = 0, col = 1 } )
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
        , test "caret follow only scrolls when the caret leaves the viewport, from the model's own scroll position" <|
            \_ ->
                let
                    m =
                        Editor.setContent "/n/a.md" (String.repeat 100 "some text on a line\n") "r" False Editor.init
                            |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 200, viewportWidth = 300, viewportTop = 0, viewportLeft = 0 })
                in
                Expect.all
                    [ \_ -> Editor.caretFollow m |> Expect.equal Nothing
                    , \_ -> Editor.caretFollow (press Editor.DocEnd m) |> Maybe.map .top |> Expect.equal (Just (100 * 20 + 20 - 200))
                    , \_ -> Editor.caretFollow (m |> press Editor.DocEnd |> Editor.update (Editor.ScrollChanged 1900 0)) |> Expect.equal Nothing
                    , \_ -> Editor.caretFollow (Editor.update (Editor.ScrollChanged 900 0) m) |> Maybe.map .top |> Expect.equal (Just 0)
                    , \_ -> Editor.caretFollow (m |> press Editor.End) |> Expect.equal Nothing
                    , \_ ->
                        Editor.setContent "/n/w.md" (String.repeat 50 "x") "r" False Editor.init
                            |> Editor.update (Editor.SetSoftWrap False)
                            |> Editor.update (Editor.MetricsChanged { lineHeight = 20, charWidth = 10, viewportHeight = 200, viewportWidth = 300, viewportTop = 0, viewportLeft = 0 })
                            |> press Editor.End
                            |> Editor.caretFollow
                            |> Maybe.map .left
                            |> Expect.equal (Just (50 * 10 + 10 - 300))
                    ]
                    ()
        , test "Escape clears the selection without moving the caret" <|
            \_ -> opened |> press Editor.Right |> Editor.update (Editor.Select Editor.Right) |> press Editor.Escape |> (\m -> ( Editor.selection m, m.cursor )) |> Expect.equal ( Nothing, { line = 0, col = 2 } )
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


{-| The document as a flat list of characters with a code-point cursor. This
representation cannot express a cursor inside a character, so it is a genuine
oracle for the editor's UTF-16 columns rather than a copy of them.
-}
type alias Ref =
    { chars : List Char, cursor : Int, anchor : Maybe Int }


refApply : Op -> Ref -> Ref
refApply op ref =
    let
        selectionBounds =
            ref.anchor
                |> Maybe.andThen
                    (\a ->
                        if a == ref.cursor then
                            Nothing

                        else
                            Just ( Basics.min a ref.cursor, Basics.max a ref.cursor )
                    )

        withoutSelection =
            case selectionBounds of
                Just ( start, end ) ->
                    { chars = List.take start ref.chars ++ List.drop end ref.chars, cursor = start, anchor = Nothing }

                Nothing ->
                    { ref | anchor = Nothing }

        insertAt text target =
            let
                inserted =
                    String.toList text
            in
            { target
                | chars = List.take target.cursor target.chars ++ inserted ++ List.drop target.cursor target.chars
                , cursor = target.cursor + List.length inserted
            }

        move extend target =
            { ref
                | cursor = target
                , anchor =
                    if extend then
                        Just (Maybe.withDefault ref.cursor ref.anchor)

                    else
                        Nothing
            }

        lineStartOf index =
            List.take index ref.chars
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, char ) -> char == '\n')
                |> List.reverse
                |> List.head
                |> Maybe.map (\( i, _ ) -> i + 1)
                |> Maybe.withDefault 0

        lineEndOf index =
            List.drop index ref.chars
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, char ) -> char == '\n')
                |> List.head
                |> Maybe.map (\( i, _ ) -> index + i)
                |> Maybe.withDefault (List.length ref.chars)
    in
    case op of
        TypeChar text ->
            insertAt text withoutSelection

        PasteOp text ->
            insertAt text withoutSelection

        Newline ->
            insertAt "\n" withoutSelection

        BackspaceOp ->
            if selectionBounds /= Nothing then
                withoutSelection

            else if ref.cursor > 0 then
                { ref | chars = List.take (ref.cursor - 1) ref.chars ++ List.drop ref.cursor ref.chars, cursor = ref.cursor - 1, anchor = Nothing }

            else
                { ref | anchor = Nothing }

        DeleteOp ->
            if selectionBounds /= Nothing then
                withoutSelection

            else
                { ref | chars = List.take ref.cursor ref.chars ++ List.drop (ref.cursor + 1) ref.chars, anchor = Nothing }

        LeftOp extend ->
            move extend (Basics.max 0 (ref.cursor - 1))

        RightOp extend ->
            move extend (Basics.min (List.length ref.chars) (ref.cursor + 1))

        HomeOp extend ->
            move extend (lineStartOf ref.cursor)

        EndOp extend ->
            move extend (lineEndOf ref.cursor)

        SelectAllOp ->
            { ref | anchor = Just 0, cursor = List.length ref.chars }


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
        -- no list markers among these: Enter continues a list, which the
        -- plain character-level reference below deliberately does not model
        [ ( 5, Fuzz.map TypeChar (Fuzz.oneOfValues [ "a", "b", " ", "#", "\t", "é", "😀" ]) )
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
    let
        -- the editor's UTF-16 column expressed as a code-point index, which is
        -- only well defined while the cursor sits on a character boundary
        codePointIndex editor cursor =
            String.left (TextBuffer.offsetOf editor.lines cursor) editor.content
                |> String.foldl (\_ n -> n + 1) 0
    in
    fuzzWith { runs = 300, distribution = noDistribution } (Fuzz.listOfLengthBetween 0 40 opFuzzer) "random edit sequences match a character-level reference model" <|
        \ops ->
            let
                start =
                    "ab\ncd"

                ref =
                    List.foldl refApply { chars = String.toList start, cursor = 0, anchor = Nothing } ops

                editor =
                    List.foldl editorApply (Editor.setContent "/n/a.md" start "r" False Editor.init) ops

                refSelectionStart =
                    ref.anchor
                        |> Maybe.andThen
                            (\a ->
                                if a == ref.cursor then
                                    Nothing

                                else
                                    Just (Basics.min a ref.cursor)
                            )
            in
            Expect.equal
                ( String.fromList ref.chars, ref.cursor, refSelectionStart )
                ( editor.content
                , codePointIndex editor editor.cursor
                , Editor.selection editor |> Maybe.map (\( s, _ ) -> codePointIndex editor s)
                )


reloadSuite : Test
reloadSuite =
    let
        original =
            Editor.setContent "/notes/a.md" (String.repeat 500 "line\n" ++ "x") "r1" False Editor.init

        positioned cursor anchor =
            { original | cursor = cursor, anchor = anchor }

        reload content =
            Editor.reloadContent "/notes/a.md" content "r2"
    in
    describe "reload truncation"
        [ test "a deleted caret line moves to EOF rather than keeping its old column" <|
            \_ ->
                positioned { line = 500, col = 1 } Nothing
                    |> reload (String.repeat 249 "line\n" ++ "a longer final line")
                    |> .cursor |> Expect.equal { line = 249, col = 19 }
        , test "a surviving caret line clamps only its column" <|
            \_ ->
                positioned { line = 0, col = 4 } Nothing
                    |> reload "hi\nlonger final line"
                    |> .cursor |> Expect.equal { line = 0, col = 2 }
        , test "truncating to an empty file clamps caret, selection and scroll" <|
            \_ ->
                let
                    old =
                        positioned { line = 500, col = 1 } (Just { line = 450, col = 2 })

                    result =
                        reload "" { old | scrollTop = 10000, scrollLeft = 100 }
                in
                Expect.equal
                    ( { line = 0, col = 0 }, Nothing, ( 0, 0 ) )
                    ( result.cursor, result.anchor, ( result.scrollTop, result.scrollLeft ) )
        , test "a selection spanning the deletion keeps its surviving anchor" <|
            \_ ->
                positioned { line = 500, col = 1 } (Just { line = 0, col = 2 })
                    |> reload "first\nlast line"
                    |> (\e -> Expect.equal ( { line = 1, col = 9 }, Just { line = 0, col = 2 } ) ( e.cursor, e.anchor ))
        ]
