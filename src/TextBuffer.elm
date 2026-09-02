module TextBuffer exposing
    ( Cursor
    , backspace
    , clampCursor
    , columnFromVisual
    , deleteForward
    , docEnd
    , docStart
    , fromString
    , insert
    , lineEnd
    , lineStart
    , moveDown
    , moveLeft
    , moveRight
    , moveUp
    , tabWidth
    , toString
    , unindentLine
    , visualColumn
    )

{-| Pure editing operations on a document stored as an array of lines with a
single cursor. Columns are code-unit offsets into the line; `visualColumn`
maps them to rendered cells (tabs expand to `tabWidth`).
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
    in
    { line = line, col = clamp 0 (String.length (lineAt line lines)) cursor.col }



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
        in
        ( Array.set cursor.line (String.left (cursor.col - 1) current ++ String.dropLeft cursor.col current) lines
        , { cursor | col = cursor.col - 1 }
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
        ( Array.set cursor.line (String.left cursor.col current ++ String.dropLeft (cursor.col + 1) current) lines, cursor )

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
        { cursor | col = cursor.col - 1 }

    else if cursor.line > 0 then
        { line = cursor.line - 1, col = String.length (lineAt (cursor.line - 1) lines) }

    else
        cursor


moveRight : Cursor -> Array String -> Cursor
moveRight cursor lines =
    if cursor.col < String.length (lineAt cursor.line lines) then
        { cursor | col = cursor.col + 1 }

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
visual offset (rounding to the nearest boundary). -}
columnFromVisual : String -> Int -> Int
columnFromVisual line target =
    let
        step c ( col, vis, found ) =
            case found of
                Just _ ->
                    ( col, vis, found )

                Nothing ->
                    let
                        width =
                            if c == '\t' then
                                tabWidth - modBy tabWidth vis

                            else
                                1
                    in
                    if vis + width > target then
                        ( col, vis, Just (if target - vis >= (width + 1) // 2 then col + 1 else col) )

                    else
                        ( col + 1, vis + width, Nothing )
    in
    case String.foldl step ( 0, 0, Nothing ) line of
        ( _, _, Just col ) ->
            col

        ( col, _, Nothing ) ->
            col
