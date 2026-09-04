module TextBuffer exposing
    ( Cursor
    , backspace
    , clampCursor
    , columnFromVisual
    , cursorAt
    , deleteForward
    , deleteRange
    , docEnd
    , docStart
    , fromString
    , indentLines
    , insert
    , lineEnd
    , lineRange
    , lineStart
    , moveDown
    , moveLeft
    , moveRight
    , moveUp
    , offsetOf
    , order
    , sliceRange
    , toString
    , unindentLine
    , unindentLines
    , wordLeft
    , wordRight
    , visualColumn
    , wordRange
    )

{-| Pure editing operations on a document stored as an array of lines with a
single cursor.

Columns are UTF-16 code-unit offsets, matching `String.left`/`String.dropLeft`.
A character outside the Basic Multilingual Plane (emoji, rarer CJK, some
symbols) occupies two of them, so every function that produces a column steps
by `charUnits` and never lands between the halves of a surrogate pair. Slicing
there would split the character into two lone surrogates and destroy it.

`visualColumn` maps a column to rendered cells, where a tab expands to
`tabWidth`. Cells assume one column per character; a double-width glyph still
counts as one, so the caret can sit half a glyph off next to wide emoji.
-}

import Array exposing (Array)


type alias Cursor =
    { line : Int, col : Int }


fromString : String -> Array String
fromString content =
    Array.fromList (String.split "\n" content)


toString : Array String -> String
toString lines =
    String.join "\n" (Array.toList lines)


lineAt : Int -> Array String -> String
lineAt i lines =
    Array.get i lines |> Maybe.withDefault ""


clampCursor : Array String -> Cursor -> Cursor
clampCursor lines cursor =
    let
        line =
            clamp 0 (Basics.max 0 (Array.length lines - 1)) cursor.line

        text =
            lineAt line lines
    in
    { line = line, col = snapToBoundary text (clamp 0 (String.length text) cursor.col) }



-- CODE UNITS
--
-- Columns index UTF-16 code units. These four helpers are the only places
-- that know a character can be two units wide; everything else steps through
-- them and so stays on character boundaries.


{-| Code units occupied by a character: two outside the Basic Multilingual
Plane, one otherwise.
-}
charUnits : Char -> Int
charUnits char =
    if Char.toCode char > 0xFFFF then
        2

    else
        1


{-| Units of the character starting at `col`, or 0 at the end of the line.
-}
unitsForward : String -> Int -> Int
unitsForward line col =
    String.dropLeft col line
        |> String.uncons
        |> Maybe.map (Tuple.first >> charUnits)
        |> Maybe.withDefault 0


{-| Units of the character ending at `col`, or 0 at the start of the line.
-}
unitsBackward : String -> Int -> Int
unitsBackward line col =
    if col <= 0 then
        0

    else if isTrailingUnit line (col - 1) then
        2

    else
        1


{-| Is the code unit at `index` the second half of a surrogate pair?
-}
isTrailingUnit : String -> Int -> Bool
isTrailingUnit line index =
    String.slice index (index + 1) line
        |> String.uncons
        |> Maybe.map (\( char, _ ) -> Char.toCode char >= 0xDC00 && Char.toCode char <= 0xDFFF)
        |> Maybe.withDefault False


{-| Move a column off the middle of a surrogate pair, towards the line start.
-}
snapToBoundary : String -> Int -> Int
snapToBoundary line col =
    if col > 0 && isTrailingUnit line col then
        col - 1

    else
        col



-- EDITS


{-| Insert text (may contain newlines) at the cursor. -}
insert : String -> Cursor -> Array String -> ( Array String, Cursor )
insert text cursor lines =
    let
        current =
            lineAt cursor.line lines

        before =
            String.left cursor.col current

        after =
            String.dropLeft cursor.col current
    in
    case String.split "\n" text of
        [ single ] ->
            ( Array.set cursor.line (before ++ single ++ after) lines
            , { cursor | col = cursor.col + String.length single }
            )

        first :: rest ->
            let
                lastInserted =
                    List.reverse rest |> List.head |> Maybe.withDefault ""

                middle =
                    List.take (List.length rest - 1) rest

                newLines =
                    [ before ++ first ] ++ middle ++ [ lastInserted ++ after ]

                ( head, tail ) =
                    splitAround cursor.line lines
            in
            ( Array.append (Array.append head (Array.fromList newLines)) tail
            , { line = cursor.line + List.length rest, col = String.length lastInserted }
            )

        [] ->
            ( lines, cursor )


backspace : Cursor -> Array String -> ( Array String, Cursor )
backspace cursor lines =
    if cursor.col > 0 then
        let
            current =
                lineAt cursor.line lines

            width =
                unitsBackward current cursor.col
        in
        ( Array.set cursor.line (String.left (cursor.col - width) current ++ String.dropLeft cursor.col current) lines
        , { cursor | col = cursor.col - width }
        )

    else if cursor.line > 0 then
        joinWithNext (cursor.line - 1) lines
            |> (\joined -> ( joined, { line = cursor.line - 1, col = String.length (lineAt (cursor.line - 1) lines) } ))

    else
        ( lines, cursor )


deleteForward : Cursor -> Array String -> ( Array String, Cursor )
deleteForward cursor lines =
    let
        current =
            lineAt cursor.line lines
    in
    if cursor.col < String.length current then
        ( Array.set cursor.line (String.left cursor.col current ++ String.dropLeft (cursor.col + unitsForward current cursor.col) current) lines, cursor )

    else if cursor.line < Array.length lines - 1 then
        ( joinWithNext cursor.line lines, cursor )

    else
        ( lines, cursor )


{-| Remove one level of indentation (a tab, or up to `tabWidth` spaces) from
the cursor's line, keeping the cursor on the same character.
-}
unindentLine : Cursor -> Array String -> ( Array String, Cursor )
unindentLine cursor lines =
    let
        current =
            lineAt cursor.line lines

        removed =
            if String.startsWith "\t" current then
                1

            else
                String.length current - String.length (String.trimLeft current) |> Basics.min tabWidth
    in
    ( Array.set cursor.line (String.dropLeft removed current) lines
    , { cursor | col = Basics.max 0 (cursor.col - removed) }
    )


joinWithNext : Int -> Array String -> Array String
joinWithNext i lines =
    let
        ( head, tail ) =
            splitAround i lines
    in
    Array.append (Array.push (lineAt i lines ++ lineAt (i + 1) lines) head) (Array.slice 1 (Array.length tail) tail)


{-| Lines before `i`, and lines after `i` (exclusive of `i`). -}
splitAround : Int -> Array String -> ( Array String, Array String )
splitAround i lines =
    ( Array.slice 0 i lines, Array.slice (i + 1) (Array.length lines) lines )



-- MOVEMENT


moveLeft : Cursor -> Array String -> Cursor
moveLeft cursor lines =
    if cursor.col > 0 then
        { cursor | col = cursor.col - unitsBackward (lineAt cursor.line lines) cursor.col }

    else if cursor.line > 0 then
        { line = cursor.line - 1, col = String.length (lineAt (cursor.line - 1) lines) }

    else
        cursor


moveRight : Cursor -> Array String -> Cursor
moveRight cursor lines =
    if cursor.col < String.length (lineAt cursor.line lines) then
        { cursor | col = cursor.col + unitsForward (lineAt cursor.line lines) cursor.col }

    else if cursor.line < Array.length lines - 1 then
        { line = cursor.line + 1, col = 0 }

    else
        cursor


{-| Up/down keep the visual column, like every editor. -}
moveUp : Int -> Cursor -> Array String -> Cursor
moveUp rows cursor lines =
    moveVertical (Basics.max 0 (cursor.line - rows)) cursor lines


moveDown : Int -> Cursor -> Array String -> Cursor
moveDown rows cursor lines =
    moveVertical (Basics.min (Array.length lines - 1) (cursor.line + rows)) cursor lines


moveVertical : Int -> Cursor -> Array String -> Cursor
moveVertical targetLine cursor lines =
    let
        visual =
            visualColumn (lineAt cursor.line lines) cursor.col
    in
    { line = targetLine, col = columnFromVisual (lineAt targetLine lines) visual }


{-| Start of the previous word, crossing to the previous line at column 0.
Non-word characters before the word are skipped, as on every platform.
-}
wordLeft : Cursor -> Array String -> Cursor
wordLeft cursor lines =
    if cursor.col == 0 then
        if cursor.line > 0 then
            lineEnd { cursor | line = cursor.line - 1 } lines

        else
            cursor

    else
        { cursor | col = wordStartBefore (lineAt cursor.line lines) cursor.col }


{-| End of the next word, crossing to the next line at the end of this one.
-}
wordRight : Cursor -> Array String -> Cursor
wordRight cursor lines =
    let
        line =
            lineAt cursor.line lines
    in
    if cursor.col >= String.length line then
        if cursor.line < Array.length lines - 1 then
            { line = cursor.line + 1, col = 0 }

        else
            cursor

    else
        { cursor | col = wordEndAfter line cursor.col }


wordEndAfter : String -> Int -> Int
wordEndAfter line col =
    case List.filter (\run -> run.end > col) (runsOf line) of
        run :: rest ->
            if run.word then
                run.end

            else
                List.head rest |> Maybe.map .end |> Maybe.withDefault (String.length line)

        [] ->
            String.length line


wordStartBefore : String -> Int -> Int
wordStartBefore line col =
    case List.reverse (List.filter (\run -> run.start < col) (runsOf line)) of
        run :: rest ->
            if run.word then
                run.start

            else
                List.head rest |> Maybe.map .start |> Maybe.withDefault 0

        [] ->
            0


lineStart : Cursor -> Cursor
lineStart cursor =
    { cursor | col = 0 }


lineEnd : Cursor -> Array String -> Cursor
lineEnd cursor lines =
    { cursor | col = String.length (lineAt cursor.line lines) }


docStart : Cursor
docStart =
    { line = 0, col = 0 }


docEnd : Array String -> Cursor
docEnd lines =
    let
        last =
            Basics.max 0 (Array.length lines - 1)
    in
    { line = last, col = String.length (lineAt last lines) }



-- VISUAL COLUMNS


tabWidth : Int
tabWidth =
    2


{-| Rendered cell offset of a code-unit column, with tabs expanding to the
next multiple of `tabWidth` (matches `tab-size: 2`). -}
visualColumn : String -> Int -> Int
visualColumn line col =
    String.left col line
        |> String.foldl
            (\c acc ->
                if c == '\t' then
                    acc + tabWidth - modBy tabWidth acc

                else
                    acc + 1
            )
            0


{-| Inverse of `visualColumn`: the column whose cell is at or just before the
visual offset, rounded to the nearest character boundary.
-}
columnFromVisual : String -> Int -> Int
columnFromVisual line target =
    let
        step char ( col, vis, found ) =
            case found of
                Just _ ->
                    ( col, vis, found )

                Nothing ->
                    let
                        cells =
                            if char == '\t' then
                                tabWidth - modBy tabWidth vis

                            else
                                1

                        units =
                            charUnits char
                    in
                    if vis + cells > target then
                        ( col
                        , vis
                        , Just
                            (if target - vis >= (cells + 1) // 2 then
                                col + units

                             else
                                col
                            )
                        )

                    else
                        ( col + units, vis + cells, Nothing )
    in
    case String.foldl step ( 0, 0, Nothing ) line of
        ( _, _, Just col ) ->
            col

        ( col, _, Nothing ) ->
            col



-- RANGES


{-| The two ends of a selection in document order. -}
order : Cursor -> Cursor -> ( Cursor, Cursor )
order a b =
    if ( a.line, a.col ) <= ( b.line, b.col ) then
        ( a, b )

    else
        ( b, a )


sliceRange : Cursor -> Cursor -> Array String -> String
sliceRange a b lines =
    let
        ( s, e ) =
            order a b
    in
    if s.line == e.line then
        String.slice s.col e.col (lineAt s.line lines)

    else
        String.join "\n"
            (String.dropLeft s.col (lineAt s.line lines)
                :: (Array.slice (s.line + 1) e.line lines |> Array.toList)
                ++ [ String.left e.col (lineAt e.line lines) ]
            )


deleteRange : Cursor -> Cursor -> Array String -> ( Array String, Cursor )
deleteRange a b lines =
    let
        ( s, e ) =
            order a b

        joined =
            String.left s.col (lineAt s.line lines) ++ String.dropLeft e.col (lineAt e.line lines)
    in
    ( Array.append (Array.push joined (Array.slice 0 s.line lines)) (Array.slice (e.line + 1) (Array.length lines) lines), s )


{-| The word (letters, digits, underscore) under the cursor, or the run of
other characters there, for double-click selection.
-}
wordRange : Cursor -> Array String -> ( Cursor, Cursor )
wordRange cursor lines =
    let
        line =
            lineAt cursor.line lines

        containing =
            runsOf line
                |> List.filter (\run -> run.start <= cursor.col && cursor.col < run.end)
                |> List.head
    in
    case containing of
        Just run ->
            ( { cursor | col = run.start }, { cursor | col = run.end } )

        Nothing ->
            -- past the last character: take the run that ends there
            case List.reverse (runsOf line) of
                run :: _ ->
                    ( { cursor | col = run.start }, { cursor | col = run.end } )

                [] ->
                    ( cursor, cursor )


{-| Maximal runs of same-kind characters as column ranges, `word` marking
runs of letters, digits and underscores.
-}
runsOf : String -> List { start : Int, end : Int, word : Bool }
runsOf line =
    let
        isWord char =
            Char.isAlphaNum char || char == '_'

        step char ( col, acc ) =
            let
                next =
                    col + charUnits char

                word =
                    isWord char
            in
            case acc of
                run :: rest ->
                    if run.word == word then
                        ( next, { run | end = next } :: rest )

                    else
                        ( next, { start = col, end = next, word = word } :: acc )

                [] ->
                    ( next, [ { start = col, end = next, word = word } ] )
    in
    String.foldl step ( 0, [] ) line
        |> Tuple.second
        |> List.reverse


{-| The whole line including its line break, for triple-click selection. -}
lineRange : Cursor -> Array String -> ( Cursor, Cursor )
lineRange cursor lines =
    if cursor.line < Array.length lines - 1 then
        ( { line = cursor.line, col = 0 }, { line = cursor.line + 1, col = 0 } )

    else
        ( { line = cursor.line, col = 0 }, lineEnd cursor lines )


indentLines : Int -> Int -> Array String -> Array String
indentLines from to lines =
    Array.indexedMap
        (\i l ->
            if i >= from && i <= to then
                "\t" ++ l

            else
                l
        )
        lines


unindentLines : Int -> Int -> Array String -> Array String
unindentLines from to lines =
    Array.indexedMap
        (\i l ->
            if i >= from && i <= to then
                Tuple.first (unindentLine { line = 0, col = 0 } (Array.fromList [ l ])) |> Array.get 0 |> Maybe.withDefault l

            else
                l
        )
        lines


{-| Code-unit offset of a cursor into `toString lines`. -}
offsetOf : Array String -> Cursor -> Int
offsetOf lines cursor =
    (Array.slice 0 cursor.line lines |> Array.foldl (\l acc -> acc + String.length l + 1) 0) + cursor.col


cursorAt : Array String -> Int -> Cursor
cursorAt lines offset =
    let
        go line remaining =
            let
                len =
                    String.length (lineAt line lines)
            in
            if remaining <= len || line >= Array.length lines - 1 then
                { line = line, col = Basics.min len remaining }

            else
                go (line + 1) (remaining - len - 1)
    in
    go 0 (Basics.max 0 offset)
