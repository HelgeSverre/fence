module TextBufferTest exposing (suite)

import Array
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, fuzz2, test)
import TextBuffer as TB


doc : Array.Array String
doc =
    TB.fromString "alpha\nbeta gamma\n\n\tindented"


at : Int -> Int -> TB.Cursor
at line col =
    { line = line, col = col }


suite : Test
suite =
    describe "TextBuffer"
        [ describe "insert"
            [ test "a character mid-line" <|
                \_ -> TB.insert "X" (at 0 2) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alXpha\nbeta gamma\n\n\tindented", at 0 3 )
            , test "a newline splits the line and moves to the new one" <|
                \_ -> TB.insert "\n" (at 1 4) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alpha\nbeta\n gamma\n\n\tindented", at 2 0 )
            , test "multi-line text lands the cursor after the last inserted line" <|
                \_ -> TB.insert "1\n22\n333" (at 0 5) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alpha1\n22\n333\nbeta gamma\n\n\tindented", at 2 3 )
            , test "into an empty document" <|
                \_ -> TB.insert "hi" (at 0 0) (TB.fromString "") |> Tuple.mapFirst TB.toString |> Expect.equal ( "hi", at 0 2 )
            ]
        , describe "delete"
            [ test "backspace removes the previous character" <|
                \_ -> TB.backspace (at 1 1) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alpha\neta gamma\n\n\tindented", at 1 0 )
            , test "backspace at a line start joins with the previous line" <|
                \_ -> TB.backspace (at 1 0) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alphabeta gamma\n\n\tindented", at 0 5 )
            , test "backspace at the document start is a no-op" <|
                \_ -> TB.backspace (at 0 0) doc |> Tuple.first |> TB.toString |> Expect.equal (TB.toString doc)
            , test "delete forward at a line end joins the next line" <|
                \_ -> TB.deleteForward (at 0 5) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alphabeta gamma\n\n\tindented", at 0 5 )
            , test "delete forward at the document end is a no-op" <|
                \_ -> TB.deleteForward (at 3 9) doc |> Tuple.first |> TB.toString |> Expect.equal (TB.toString doc)
            , test "unindent removes a leading tab and keeps the cursor on its character" <|
                \_ -> TB.unindentLine (at 3 4) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alpha\nbeta gamma\n\nindented", at 3 3 )
            , test "unindent removes up to two leading spaces" <|
                \_ -> TB.unindentLine (at 0 4) (TB.fromString "    four") |> Tuple.mapFirst TB.toString |> Expect.equal ( "  four", at 0 2 )
            ]
        , describe "movement"
            [ test "left wraps to the end of the previous line" <|
                \_ -> TB.moveLeft (at 1 0) doc |> Expect.equal (at 0 5)
            , test "right wraps to the start of the next line" <|
                \_ -> TB.moveRight (at 0 5) doc |> Expect.equal (at 1 0)
            , test "right at the document end stays" <|
                \_ -> TB.moveRight (at 3 9) doc |> Expect.equal (at 3 9)
            , test "down onto a shorter line clamps the column" <|
                \_ -> TB.moveDown 1 (at 1 8) doc |> Expect.equal (at 2 0)
            , test "up keeps the visual column across a tab" <|
                \_ -> TB.moveUp 1 (at 3 2) doc |> Expect.equal (at 2 0)
            , test "down from a tab-indented line lands at the same visual cell" <|
                \_ -> TB.moveDown 1 (at 0 1) (TB.fromString "\tx\nabcdef") |> Expect.equal (at 1 2)
            , test "page moves are clamped to the document" <|
                \_ -> ( TB.moveDown 100 (at 0 0) doc, TB.moveUp 100 (at 3 2) doc ) |> Expect.equal ( at 3 0, at 0 3 )
            , test "line start, line end, document start and end" <|
                \_ ->
                    ( TB.lineStart (at 1 5), TB.lineEnd (at 1 5) doc, ( TB.docStart, TB.docEnd doc ) )
                        |> Expect.equal ( at 1 0, at 1 10, ( at 0 0, at 3 9 ) )
            , test "clampCursor keeps a stale cursor inside the document" <|
                \_ -> TB.clampCursor doc (at 9 9) |> Expect.equal (at 3 9)
            ]
        , describe "visual columns"
            [ test "tabs expand to the next multiple of the tab width" <|
                \_ -> TB.visualColumn "a\tbc\td" 6 |> Expect.equal 7
            , test "columnFromVisual picks the nearest boundary" <|
                \_ -> ( TB.columnFromVisual "\tabc" 1, TB.columnFromVisual "\tabc" 2, TB.columnFromVisual "\tabc" 9 ) |> Expect.equal ( 1, 1, 4 )
            , fuzz2 (Fuzz.listOfLengthBetween 0 12 (Fuzz.oneOfValues [ "a", "\t", "b" ]) |> Fuzz.map String.concat) (Fuzz.intRange 0 12) "columnFromVisual inverts visualColumn at every column" <|
                \line col0 ->
                    let
                        col =
                            clamp 0 (String.length line) col0
                    in
                    TB.columnFromVisual line (TB.visualColumn line col) |> Expect.equal col
            ]
        , describe "ranges"
            [ test "sliceRange within a line and across lines" <|
                \_ -> ( TB.sliceRange (at 0 1) (at 0 4) doc, TB.sliceRange (at 1 5) (at 3 1) doc ) |> Expect.equal ( "lph", "gamma\n\n\t" )
            , test "deleteRange joins the ends and lands the cursor at the start" <|
                \_ -> TB.deleteRange (at 3 1) (at 0 2) doc |> Tuple.mapFirst TB.toString |> Expect.equal ( "alindented", at 0 2 )
            , test "wordRange finds word boundaries and punctuation runs" <|
                \_ -> ( TB.wordRange (at 1 7) doc, TB.wordRange (at 1 4) doc ) |> Expect.equal ( ( at 1 5, at 1 10 ), ( at 1 4, at 1 5 ) )
            , test "lineRange includes the line break except on the last line" <|
                \_ -> ( TB.lineRange (at 0 3) doc, TB.lineRange (at 3 0) doc ) |> Expect.equal ( ( at 0 0, at 1 0 ), ( at 3 0, at 3 9 ) )
            , test "indent and unindent a range of lines" <|
                \_ -> TB.indentLines 0 1 doc |> TB.unindentLines 0 1 |> TB.toString |> Expect.equal (TB.toString doc)
            , fuzz (Fuzz.intRange 0 40) "offsetOf and cursorAt are inverse" <|
                \offset -> TB.offsetOf doc (TB.cursorAt doc offset) |> Expect.equal (Basics.min offset (String.length (TB.toString doc)))
            ]
        , fuzz (Fuzz.listOfLengthBetween 0 30 (Fuzz.oneOfValues [ "a", "b", " ", "\n", "\t" ]) |> Fuzz.map String.concat) "the lines array and the string always agree" <|
            \content -> TB.toString (TB.fromString content) |> Expect.equal content
        ]
