module EditorLayout exposing
    ( Affinity(..)
    , Fragment
    , Layout
    , Position
    , Segment
    , build
    , columns
    , expandTabs
    , fragmentAt
    , fragments
    , lineStartRow
    , positionAt
    , replace
    , rowCount
    , screenPosition
    , sourceLine
    , sync
    , syncRange
    , wrapLine
    )

{-| Source offsets never include soft breaks. Leaves contain one source line's
breaks; branches cache line and screen-row counts. Split/join preserve untouched
leaves, so edits do not rebuild a suffix of absolute row offsets.
-}

import Array exposing (Array)
import Regex
import TextBuffer exposing (Cursor)


type Affinity
    = Upstream
    | Downstream


type alias Position =
    { cursor : Cursor, affinity : Affinity }


type alias Segment =
    { start : Int, end : Int, startCell : Int, endCell : Int }


type alias Fragment =
    { line : Int, row : Int, text : String, segment : Segment, last : Bool }


type Layout
    = Empty
    | Leaf String (Array Segment)
    | Branch Int Int Int Layout Layout


columns : Bool -> Float -> Float -> Int
columns enabled width charWidth =
    if enabled then
        max 1 (floor ((width - 2) / max 1 charWidth))

    else
        0


height : Layout -> Int
height tree =
    case tree of
        Empty ->
            0

        Leaf _ _ ->
            1

        Branch h _ _ _ _ ->
            h


lineCount : Layout -> Int
lineCount tree =
    case tree of
        Empty ->
            0

        Leaf _ _ ->
            1

        Branch _ n _ _ _ ->
            n


rowCount : Layout -> Int
rowCount tree =
    case tree of
        Empty ->
            0

        Leaf _ rows ->
            Array.length rows

        Branch _ _ n _ _ ->
            n


node : Layout -> Layout -> Layout
node left right =
    case ( left, right ) of
        ( Empty, _ ) ->
            right

        ( _, Empty ) ->
            left

        _ ->
            Branch (1 + max (height left) (height right)) (lineCount left + lineCount right) (rowCount left + rowCount right) left right


balance : Layout -> Layout -> Layout
balance left right =
    if height left > height right + 1 then
        case left of
            Branch _ _ _ a b ->
                if height a >= height b then
                    node a (node b right)

                else
                    case b of
                        Branch _ _ _ c d ->
                            node (node a c) (node d right)

                        _ ->
                            node left right

            _ ->
                node left right

    else if height right > height left + 1 then
        case right of
            Branch _ _ _ a b ->
                if height b >= height a then
                    node (node left a) b

                else
                    case a of
                        Branch _ _ _ c d ->
                            node (node left c) (node d b)

                        _ ->
                            node left right

            _ ->
                node left right

    else
        node left right


join : Layout -> Layout -> Layout
join left right =
    if height left > height right + 1 then
        case left of
            Branch _ _ _ a b ->
                balance a (join b right)

            _ ->
                node left right

    else if height right > height left + 1 then
        case right of
            Branch _ _ _ a b ->
                balance (join left a) b

            _ ->
                node left right

    else
        node left right


split : Int -> Layout -> ( Layout, Layout )
split count tree =
    if count <= 0 then
        ( Empty, tree )

    else if count >= lineCount tree then
        ( tree, Empty )

    else
        case tree of
            Branch _ _ _ left right ->
                if count < lineCount left then
                    let
                        ( a, b ) =
                            split count left
                    in
                    ( a, join b right )

                else
                    let
                        ( a, b ) =
                            split (count - lineCount left) right
                    in
                    ( join left a, b )

            _ ->
                ( tree, Empty )


build : Int -> Array String -> Layout
build width lines =
    buildRange width lines 0 (Array.length lines)


buildRange : Int -> Array String -> Int -> Int -> Layout
buildRange width lines from to =
    if from >= to then
        Empty

    else if to - from == 1 then
        let
            text =
                Array.get from lines |> Maybe.withDefault ""
        in
        Leaf text (wrapLine width text)

    else
        let
            middle =
                (from + to) // 2
        in
        node (buildRange width lines from middle) (buildRange width lines middle to)


replace : Int -> Int -> Int -> Array String -> Layout -> Layout
replace width from removed inserted tree =
    let
        ( before, rest ) =
            split from tree

        ( _, after ) =
            split removed rest
    in
    join (join before (build width inserted)) after


{-| Find the changed span for bulk operations/undo. Equal strings retain their
break arrays. Ordinary input supplies a known unchanged prefix as a hint.
-}
sync : Int -> Int -> Array String -> Array String -> Layout -> Layout
sync width hint old new tree =
    syncRange width hint (Array.length old) old new tree


{-| The caller supplies the potentially affected source span. Only that span
is compared; typing must not walk the thousands of untouched lines below it.
-}
syncRange : Int -> Int -> Int -> Array String -> Array String -> Layout -> Layout
syncRange width hint oldEnd old new tree =
    let
        oldCount =
            Array.length old

        newCount =
            Array.length new

        newEnd =
            oldEnd + newCount - oldCount

        prefix i =
            if i < min oldEnd newEnd && Array.get i old == Array.get i new then
                prefix (i + 1)

            else
                i

        from =
            prefix (clamp 0 (min oldCount newCount) hint)

        suffix n =
            if n < min oldEnd newEnd - from && Array.get (oldEnd - n - 1) old == Array.get (newEnd - n - 1) new then
                suffix (n + 1)

            else
                n

        kept =
            suffix 0
    in
    if from == oldEnd && from == newEnd then
        tree

    else
        replace width from (oldEnd - from - kept) (Array.slice from (newEnd - kept) new) tree


type alias Wrapping =
    { offset : Int
    , cell : Int
    , start : Int
    , startCell : Int
    , boundary : Int
    , boundaryCell : Int
    , width : TextBuffer.WidthState
    , rows : List Segment
    }


wrapLine : Int -> String -> Array Segment
wrapLine width text =
    if Regex.contains nonAsciiOrTab text then
        wrapCharacters width text

    else
        wrapAscii width text


nonAsciiOrTab : Regex.Regex
nonAsciiOrTab =
    Regex.fromString "[^\\x00-\\x7f]|\\t" |> Maybe.withDefault Regex.never


spaces : Regex.Regex
spaces =
    Regex.fromString " +" |> Maybe.withDefault Regex.never


{-| ASCII prose is the common case. Native substring/regex operations scan a
screen row at a time rather than allocating an Elm record for every character.
Tabs and non-ASCII text use the code-point walker below.
-}
wrapAscii : Int -> String -> Array Segment
wrapAscii width text =
    let
        length =
            String.length text

        walk start acc =
            if width <= 0 || start + width >= length then
                Array.fromList (List.reverse ({ start = start, end = length, startCell = start, endCell = length } :: acc))

            else
                let
                    window =
                        String.slice start (start + width) text

                    boundary =
                        Regex.find spaces window
                            |> List.reverse
                            |> List.head
                            |> Maybe.map (\match -> start + match.index + String.length match.match)
                            |> Maybe.withDefault (start + width)
                in
                walk boundary ({ start = start, end = boundary, startCell = start, endCell = boundary } :: acc)
    in
    walk 0 []


wrapCharacters : Int -> String -> Array Segment
wrapCharacters width text =
    let
        step char state =
            let
                ( cells, nextWidth ) =
                    TextBuffer.advance state.width state.cell char

                units =
                    if Char.toCode char > 0xFFFF then
                        2

                    else
                        1

                ready =
                    makeRoom cells state

                next =
                    { ready | offset = state.offset + units, cell = state.cell + cells, width = nextWidth }
            in
            if char == ' ' || char == '\t' then
                { next | boundary = next.offset, boundaryCell = next.cell }

            else
                next

        makeRoom cells state =
            if width > 0 && state.cell + cells - state.startCell > width && state.offset > state.start then
                let
                    atWord =
                        state.boundary > state.start

                    end =
                        if atWord then
                            state.boundary

                        else
                            state.offset

                    endCell =
                        if atWord then
                            state.boundaryCell

                        else
                            state.cell
                in
                makeRoom cells
                    { state
                        | start = end
                        , startCell = endCell
                        , boundary = end
                        , boundaryCell = endCell
                        , rows = { start = state.start, end = end, startCell = state.startCell, endCell = endCell } :: state.rows
                    }

            else
                state

        result =
            String.foldl step { offset = 0, cell = 0, start = 0, startCell = 0, boundary = 0, boundaryCell = 0, width = TextBuffer.widthStart, rows = [] } text
    in
    Array.fromList (List.reverse ({ start = result.start, end = result.offset, startCell = result.startCell, endCell = result.cell } :: result.rows))


emptySegment : Segment
emptySegment =
    { start = 0, end = 0, startCell = 0, endCell = 0 }


fragmentAt : Int -> Layout -> Fragment
fragmentAt requested tree =
    findRow 0 0 (clamp 0 (max 0 (rowCount tree - 1)) requested) tree


findRow : Int -> Int -> Int -> Layout -> Fragment
findRow line row local tree =
    case tree of
        Branch _ _ _ left right ->
            if local < rowCount left then
                findRow line row local left

            else
                findRow (line + lineCount left) (row + rowCount left) (local - rowCount left) right

        Leaf text segments ->
            { line = line
            , row = row + local
            , text = text
            , segment = Array.get local segments |> Maybe.withDefault emptySegment
            , last = local == Array.length segments - 1
            }

        Empty ->
            { line = 0, row = 0, text = "", segment = emptySegment, last = True }


fragments : Int -> Int -> Layout -> List Fragment
fragments from to tree =
    List.range (max 0 from) (min (rowCount tree) to - 1) |> List.map (\row -> fragmentAt row tree)


lineStartRow : Int -> Layout -> Int
lineStartRow line tree =
    case tree of
        Branch _ _ _ left right ->
            if line < lineCount left then
                lineStartRow line left

            else
                rowCount left + lineStartRow (line - lineCount left) right

        _ ->
            0


lineLeaf : Int -> Layout -> ( String, Array Segment )
lineLeaf line tree =
    case tree of
        Branch _ _ _ left right ->
            if line < lineCount left then
                lineLeaf line left

            else
                lineLeaf (line - lineCount left) right

        Leaf text segments ->
            ( text, segments )

        Empty ->
            ( "", Array.fromList [ emptySegment ] )


screenPosition : Position -> Layout -> { row : Int, cell : Int }
screenPosition position tree =
    let
        ( text, segments ) =
            lineLeaf position.cursor.line tree

        search lo hi =
            if lo >= hi then
                lo

            else
                let
                    mid =
                        (lo + hi + 1) // 2

                    start =
                        Array.get mid segments |> Maybe.map .start |> Maybe.withDefault 0

                    before =
                        start < position.cursor.col || (start == position.cursor.col && position.affinity == Downstream)
                in
                if before then
                    search mid hi

                else
                    search lo (mid - 1)

        index =
            search 0 (Array.length segments - 1)

        segment =
            Array.get index segments |> Maybe.withDefault emptySegment

        part =
            String.slice segment.start position.cursor.col text
    in
    { row = lineStartRow position.cursor.line tree + index
    , cell = cellAfter segment.startCell part - segment.startCell
    }


cellAfter : Int -> String -> Int
cellAfter start text =
    start + TextBuffer.cellsIn start text


positionAt : Int -> Int -> Layout -> Position
positionAt row cell tree =
    let
        fragment =
            fragmentAt row tree

        segment =
            fragment.segment

        target =
            segment.startCell + max 0 cell

        walk chars offset visual state =
            case chars of
                [] ->
                    offset

                char :: rest ->
                    let
                        ( cells, nextState ) =
                            TextBuffer.advance state visual char

                        next =
                            visual + cells

                        units =
                            if Char.toCode char > 0xFFFF then
                                2

                            else
                                1
                    in
                    if toFloat target < toFloat (visual + next) / 2 then
                        offset

                    else
                        walk rest (offset + units) next nextState

        col =
            walk (String.slice segment.start segment.end fragment.text |> String.toList) segment.start segment.startCell TextBuffer.widthStart
    in
    { cursor = { line = fragment.line, col = col }
    , affinity =
        if col == segment.end && not fragment.last then
            Upstream

        else
            Downstream
    }


sourceLine : Float -> Layout -> Float
sourceLine screenRow tree =
    let
        fragment =
            fragmentAt (floor screenRow) tree

        start =
            lineStartRow fragment.line tree

        ( _, segments ) =
            lineLeaf fragment.line tree
    in
    toFloat fragment.line + clamp 0 1 ((screenRow - toFloat start) / toFloat (Array.length segments))


{-| Expand display tabs without changing the source text/clipboard offsets.
-}
expandTabs : Int -> String -> String
expandTabs start text =
    if not (String.contains "\t" text) then
        text

    else
        String.foldl
            (\char ( ( cell, state ), parts ) ->
                let
                    ( size, next ) =
                        TextBuffer.advance state cell char
                in
                ( ( cell + size, next )
                , (if char == '\t' then
                    String.repeat size " "

                   else
                    String.fromChar char
                  )
                    :: parts
                )
            )
            ( ( start, TextBuffer.widthStart ), [] )
            text
            |> Tuple.second
            |> List.reverse
            |> String.concat
