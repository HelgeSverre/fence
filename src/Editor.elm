module Editor exposing
    ( Model
    , Msg(..)
    , Token
    , init
    , Key(..)
    , caretFollow
    , dragging
    , followRename
    , replaceRanges
    , selectRange
    , gotoLine
    , highlightLine
    , keyDecoder
    , selectedText
    , selection
    , lineTokens
    , markSaved
    , restorePosition
    , reloadContent
    , setContent
    , update
    , view
    )

import Array exposing (Array)
import Dict exposing (Dict)
import EditorLayout
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy
import Json.Decode as D
import Regex
import TextBuffer exposing (Cursor)
import Types exposing (..)
import VirtualEditor


type alias Model =
    { content : String
    , filePath : Maybe FilePath
    , dirtyState : DirtyState
    , revision : Maybe String
    , scrollTop : Float
    , scrollLeft : Float
    , lines : Array String -- the content split by line, for the virtual view
    , maxLineLength : Int
    , layout : EditorLayout.Layout
    , softWrap : Bool
    , wrapColumns : Int
    , affinity : EditorLayout.Affinity
    , desiredColumn : Maybe Int
    , tokenCache : Dict Int CachedTokens
    , metrics : VirtualEditor.Metrics
    , cursor : Cursor
    , anchor : Maybe Cursor -- other end of the selection, when there is one
    , dragging : Bool
    , dragPointer : Maybe { x : Float, y : Float } -- last pointer position, in window coordinates
    , undo : List Snapshot
    , redo : List Snapshot
    , coalesce : Coalesce -- what kind of edit the top undo entry may absorb
    }


type alias Snapshot =
    { lines : Array String, cursor : Cursor }


type Coalesce
    = NoCoalesce
    | Typing
    | Deleting


type Key
    = Left
    | Right
    | Up
    | Down
    | Home
    | End
    | DocStart
    | DocEnd
    | PageUp
    | PageDown
    | WordLeft
    | WordRight
    | Backspace
    | DeleteKey
    | DeleteWordBack
    | DeleteWordForward
    | DeleteToLineStart
    | Enter
    | Tab
    | ShiftTab
    | Escape
    | Char String
    | DuplicateLine
    | MoveLineUp
    | MoveLineDown
    | DeleteLine
    | OpenLineBelow
    | OpenLineAbove
    | Wrap String
    | Link
    | ToggleComment


type Msg
    = ScrollChanged Float Float -- scrollTop scrollLeft
    | MetricsChanged VirtualEditor.Metrics
    | SetSoftWrap Bool
    | KeyPressed Key
    | Select Key -- shift + a movement key extends the selection
    | InsertText String
    | PointerDown { x : Float, y : Float, shift : Bool, clicks : Int }
    | PointerMoved Float Float
    | AutoScrolled
    | PointerUp
    | SelectAll
    | CutSelection
    | Undo
    | Redo


init : Model
init =
    { content = ""
    , filePath = Nothing
    , dirtyState = Clean
    , revision = Nothing
    , scrollTop = 0
    , scrollLeft = 0
    -- one empty line, never a zero-length array: `lines` and `content` must
    -- always describe the same document, and Array.set on an empty array is
    -- silently a no-op, so typing here would do nothing
    , lines = TextBuffer.fromString ""
    , maxLineLength = 0
    , layout = EditorLayout.build 95 (TextBuffer.fromString "")
    , softWrap = True
    , wrapColumns = EditorLayout.columns True 800 8.4
    , affinity = EditorLayout.Downstream
    , desiredColumn = Nothing
    , tokenCache = Dict.empty
    , metrics = VirtualEditor.defaultMetrics
    , cursor = TextBuffer.docStart
    , anchor = Nothing
    , dragging = False
    , dragPointer = Nothing
    , undo = []
    , redo = []
    , coalesce = NoCoalesce
    }


setContent : FilePath -> String -> String -> Bool -> Model -> Model
setContent path content revision dirty model =
    let
        lines =
            TextBuffer.fromString content
    in
    { model
        | content = content
        , filePath = Just path
        , dirtyState =
            if dirty then
                Dirty

            else
                Clean
        , revision = Just revision
        , scrollTop = 0
        , scrollLeft = 0
        , layout = EditorLayout.build model.wrapColumns lines
        , affinity = EditorLayout.Downstream
        , desiredColumn = Nothing
        , tokenCache = Dict.empty
        , lines = lines
        , maxLineLength = longestOf lines
        , cursor = TextBuffer.docStart
        , anchor = Nothing
        , dragging = False
        , dragPointer = Nothing
        , undo = []
        , redo = []
        , coalesce = NoCoalesce
    }
        |> refreshTokens


{-| Apply an actual external change while keeping the user's place. Unlike a
save echo, changed disk contents invalidate the previous undo history.
-}
reloadContent : FilePath -> String -> String -> Model -> Model
reloadContent path content revision model =
    let
        loaded =
            setContent path content revision False model

        clampPosition position =
            if position.line >= Array.length loaded.lines then
                TextBuffer.docEnd loaded.lines

            else
                TextBuffer.clampCursor loaded.lines position

        cursor =
            clampPosition model.cursor

        anchor =
            Maybe.map clampPosition model.anchor

        positioned =
            { loaded
                | cursor = cursor
                , anchor =
                    if anchor == Just cursor then
                        Nothing

                    else
                        anchor
                , affinity =
                    if cursor == model.cursor then
                        model.affinity

                    else
                        EditorLayout.Downstream
                , scrollTop =
                    clamp 0 (Basics.max 0 (toFloat (EditorLayout.rowCount loaded.layout) * model.metrics.lineHeight - model.metrics.viewportHeight)) model.scrollTop
                , scrollLeft =
                    clamp 0 (Basics.max 0 (toFloat (loaded.maxLineLength + 1) * model.metrics.charWidth - model.metrics.viewportWidth)) model.scrollLeft
            }

        oldCaret =
            caretPixels model

        -- Browser scroll offsets round fractional font metrics to CSS pixels.
        wasVisible =
            oldCaret.y >= model.scrollTop - 1
                && oldCaret.y + model.metrics.lineHeight <= model.scrollTop + model.metrics.viewportHeight + 1
                && oldCaret.x >= model.scrollLeft - 1
                && oldCaret.x + model.metrics.charWidth <= model.scrollLeft + model.metrics.viewportWidth + 1
    in
    (case ( cursor /= model.cursor && wasVisible, caretFollow positioned ) of
        ( True, Just target ) ->
            { positioned | scrollTop = target.top, scrollLeft = target.left }

        _ ->
            positioned
    )
        |> refreshTokens


{-| Select a range, which is how a search hit is shown: the caret lands on it
so the usual caret-following scroll brings it into view.
-}
selectRange : ( Cursor, Cursor ) -> Model -> Model
selectRange ( s, e ) model =
    { model | anchor = Just s, cursor = e, affinity = EditorLayout.Downstream, desiredColumn = Nothing, coalesce = NoCoalesce }


{-| Replace several ranges in one undo step. The ranges must be in document
order: they are applied last-first so the earlier ones stay valid.
-}
replaceRanges : List ( Cursor, Cursor ) -> String -> Model -> Model
replaceRanges ranges replacement model =
    if List.isEmpty ranges then
        model

    else
        edit NoCoalesce
            (\cursor lines ->
                List.foldr
                    (\( s, e ) ( acc, _ ) ->
                        let
                            ( cleared, at ) =
                                TextBuffer.deleteRange s e acc
                        in
                        TextBuffer.insert replacement at cleared
                    )
                    ( lines, cursor )
                    ranges
            )
            { model | anchor = Nothing }
            |> refreshTokens


{-| Follow a rename of the open file, so the title bar and the next save
point at the new path.
-}
followRename : FilePath -> FilePath -> Model -> Model
followRename from to model =
    if model.filePath == Just from then
        { model | filePath = Just to }

    else
        case model.filePath of
            Just current ->
                if String.startsWith (from ++ "/") current || String.startsWith (from ++ "\\") current then
                    { model | filePath = Just (to ++ String.dropLeft (String.length from) current) }

                else
                    model

            Nothing ->
                model


restorePosition : Cursor -> Float -> Float -> Model -> Model
restorePosition cursor top left model =
    { model
        | cursor =
            if cursor.line >= Array.length model.lines then
                TextBuffer.docEnd model.lines

            else
                TextBuffer.clampCursor model.lines cursor
        , anchor = Nothing
        , scrollTop = clamp 0 (Basics.max 0 (toFloat (EditorLayout.rowCount model.layout) * model.metrics.lineHeight - model.metrics.viewportHeight)) top
        , scrollLeft =
            if model.softWrap then
                0

            else
                clamp 0 (Basics.max 0 (toFloat (model.maxLineLength + 1) * model.metrics.charWidth - model.metrics.viewportWidth)) left
    }
        |> refreshTokens


{-| Put the caret at the start of a 1-based line, for opening a file at a
search hit. Out-of-range lines clamp to the document.
-}
gotoLine : Int -> Model -> Model
gotoLine line model =
    { model
        | cursor = TextBuffer.clampCursor model.lines { line = line - 1, col = 0 }
        , affinity = EditorLayout.Downstream
        , desiredColumn = Nothing
        , anchor = Nothing
        , coalesce = NoCoalesce
    }


markSaved : String -> String -> Model -> Model
markSaved savedContent revision model =
    { model
        | dirtyState =
            if model.content == savedContent then
                Clean

            else
                Dirty
        , revision = Just revision
    }


update : Msg -> Model -> Model
update msg model =
    updateHelp msg model |> refreshTokens


updateHelp : Msg -> Model -> Model
updateHelp msg model =
    case msg of
        ScrollChanged scrollTop scrollLeft ->
            { model | scrollTop = scrollTop, scrollLeft = scrollLeft }

        MetricsChanged metrics ->
            reflow metrics model.softWrap model

        SetSoftWrap enabled ->
            reflow model.metrics enabled model

        KeyPressed key ->
            keyPressed key model

        Select key ->
            let
                anchored =
                    { model | anchor = Just (Maybe.withDefault model.cursor model.anchor) }

                moved =
                    keyPressed key anchored
            in
            { moved | anchor = anchored.anchor }

        InsertText text ->
            case ( isUrl text, selection model ) of
                -- a URL pasted over words links them, which is the only thing
                -- anyone wants from that gesture
                ( True, Just ( s, e ) ) ->
                    let
                        inner =
                            TextBuffer.sliceRange s e model.lines
                    in
                    let
                        replacement =
                            "[" ++ inner ++ "](" ++ text ++ ")"
                    in
                    replaceRange s e replacement (String.length replacement) 0 model

                _ ->
                    insertText text model

        PointerDown { x, y, shift, clicks } ->
            let
                position =
                    positionAtWindow { x = x, y = y } model

                at =
                    position.cursor

                ( anchor, cursor ) =
                    if shift then
                        ( Just (Maybe.withDefault model.cursor model.anchor), at )

                    else if clicks == 2 then
                        TextBuffer.wordRange at model.lines |> Tuple.mapFirst Just

                    else if clicks >= 3 then
                        TextBuffer.lineRange at model.lines |> Tuple.mapFirst Just

                    else
                        ( Nothing, at )
            in
            { model
                | cursor = cursor
                , anchor = anchor
                , affinity =
                    if clicks == 1 then
                        position.affinity

                    else
                        EditorLayout.Downstream
                , desiredColumn = Nothing
                , dragging = clicks == 1 && not shift
                , coalesce = NoCoalesce
            }

        PointerMoved x y ->
            if model.dragging then
                let
                    at =
                        positionAtWindow { x = x, y = y } model
                in
                { model
                    | anchor = Just (Maybe.withDefault model.cursor model.anchor)
                    , dragPointer = Just { x = x, y = y }
                    , cursor = at.cursor
                    , affinity = at.affinity
                    , desiredColumn = Nothing
                }

            else
                model

        AutoScrolled ->
            case ( model.dragging, model.dragPointer, autoScrollStep model ) of
                ( True, Just pointer, Just ( left, top ) ) ->
                    let
                        scrolled =
                            { model | scrollLeft = left, scrollTop = top }
                    in
                    let
                        at =
                            positionAtWindow pointer scrolled
                    in
                    { scrolled | cursor = at.cursor, affinity = at.affinity, desiredColumn = Nothing }

                _ ->
                    model

        PointerUp ->
            { model
                | dragging = False, dragPointer = Nothing
                , anchor =
                    model.anchor |> Maybe.andThen
                            (\a ->
                                if a == model.cursor then Nothing

                                else
                                    Just a
                            ) }

        SelectAll ->
            { model | anchor = Just TextBuffer.docStart, cursor = TextBuffer.docEnd model.lines, affinity = EditorLayout.Downstream, desiredColumn = Nothing, coalesce = NoCoalesce }

        CutSelection ->
            case selection model of
                Just ( s, e ) ->
                    edit NoCoalesce (\_ lines -> TextBuffer.deleteRange s e lines) { model | anchor = Nothing }

                Nothing ->
                    model

        Undo ->
            case model.undo of
                snapshot :: rest ->
                    restore snapshot { model | undo = rest, redo = { lines = model.lines, cursor = model.cursor } :: model.redo }

                [] ->
                    model

        Redo ->
            case model.redo of
                snapshot :: rest ->
                    restore snapshot { model | redo = rest, undo = { lines = model.lines, cursor = model.cursor } :: model.undo }

                [] ->
                    model


keyPressed : Key -> Model -> Model
keyPressed key model =
    let
        move f =
            { model | cursor = f model.cursor model.lines, anchor = Nothing, affinity = EditorLayout.Downstream, desiredColumn = Nothing, coalesce = NoCoalesce }

        pageRows =
            Basics.max 1 (floor (model.metrics.viewportHeight / model.metrics.lineHeight) - 1)
    in
    case key of
        Left ->
            move TextBuffer.moveLeft

        Right ->
            move TextBuffer.moveRight

        WordLeft ->
            move TextBuffer.wordLeft

        WordRight ->
            move TextBuffer.wordRight

        Up ->
            if model.softWrap then
                moveScreen -1 model

            else
                move (TextBuffer.moveUp 1)

        Down ->
            if model.softWrap then
                moveScreen 1 model

            else
                move (TextBuffer.moveDown 1)

        PageUp ->
            if model.softWrap then
                moveScreen -pageRows model

            else
                move (TextBuffer.moveUp pageRows)

        PageDown ->
            if model.softWrap then
                moveScreen pageRows model

            else
                move (TextBuffer.moveDown pageRows)

        Home ->
            if model.softWrap then
                screenEdge False model

            else
                move (\c _ -> TextBuffer.lineStart c)

        End ->
            if model.softWrap then
                screenEdge True model

            else
                move TextBuffer.lineEnd

        DocStart ->
            move (\_ _ -> TextBuffer.docStart)

        DocEnd ->
            move (\_ lines -> TextBuffer.docEnd lines)

        Char c ->
            edit Typing (TextBuffer.insert c) model

        Enter ->
            continueList model

        DuplicateLine ->
            let
                ( from, to ) =
                    lineSpan model

                shift =
                    to - from + 1
            in
            lineEdit (TextBuffer.duplicateLines from to) (moveCursorLines shift) model

        MoveLineUp ->
            moveSpan -1 model

        MoveLineDown ->
            moveSpan 1 model

        DeleteLine ->
            let
                ( from, to ) =
                    lineSpan model
            in
            lineEdit (TextBuffer.deleteLines from to) (\cursor -> { cursor | line = from }) model
                |> (\m -> { m | anchor = Nothing })

        OpenLineBelow ->
            openLine (model.cursor.line + 1) model

        OpenLineAbove ->
            openLine model.cursor.line model

        Wrap marker ->
            wrap marker model

        Link ->
            case selection model of
                Just ( s, e ) ->
                    let
                        inner =
                            TextBuffer.sliceRange s e model.lines
                    in
                    replaceRange s e ("[" ++ inner ++ "]()") (String.length inner + 3) 0 model

                Nothing ->
                    insertAround "[]()" 1 model

        ToggleComment ->
            let
                ( from, to ) =
                    lineSpan model

                spanned =
                    Array.slice from (to + 1) model.lines |> Array.toList

                uncomment =
                    List.all (\line -> String.isEmpty (String.trim line) || firstMatch commentPattern line /= Nothing) spanned

                toggle index line =
                    if index < from || index > to || String.isEmpty (String.trim line) then
                        line

                    else if uncomment then
                        String.replace "<!--" "" line
                            |> String.replace "-->" ""
                            |> String.trim

                    else
                        "<!-- " ++ line ++ " -->"
            in
            lineEdit (Array.indexedMap toggle) identity model

        Tab ->
            case multiLineSelection model of
                Just ( from, to ) ->
                    editLines (TextBuffer.indentLines from to) model

                Nothing ->
                    edit NoCoalesce (TextBuffer.insert "\t") model

        ShiftTab ->
            case multiLineSelection model of
                Just ( from, to ) ->
                    editLines (TextBuffer.unindentLines from to) model

                Nothing ->
                    edit NoCoalesce TextBuffer.unindentLine model

        Backspace ->
            deletion Deleting TextBuffer.backspace model

        DeleteKey ->
            deletion Deleting TextBuffer.deleteForward model

        DeleteWordBack ->
            deletion NoCoalesce (\cursor lines -> TextBuffer.deleteRange (TextBuffer.wordLeft cursor lines) cursor lines) model

        DeleteWordForward ->
            deletion NoCoalesce (\cursor lines -> TextBuffer.deleteRange cursor (TextBuffer.wordRight cursor lines) lines) model

        DeleteToLineStart ->
            deletion NoCoalesce (\cursor lines -> TextBuffer.deleteRange { cursor | col = 0 } cursor lines) model

        Escape ->
            { model | anchor = Nothing }


{-| A selection spanning more than one line, as (first, last) line indexes. -}
multiLineSelection : Model -> Maybe ( Int, Int )
multiLineSelection model =
    selection model
        |> Maybe.andThen
            (\( s, e ) ->
                if e.line > s.line then
                    Just ( s.line
                        , e.line
                            - (if e.col == 0 then 1

                               else
                                0
                              ) )

                else
                    Nothing
            )


{-| Re-indent whole lines, keeping the selection on them. -}
editLines : (Array String -> Array String) -> Model -> Model
editLines f model =
    let
        lines =
            f model.lines

        lengthOf source index =
            Array.get index source |> Maybe.withDefault "" |> String.length

        -- an indent or unindent shifts everything on that line sideways
        followLine cursor =
            TextBuffer.clampCursor lines { cursor | col = cursor.col + lengthOf lines cursor.line - lengthOf model.lines cursor.line }
    in
    if lines == model.lines then
        model

    else
        { model
            | lines = lines
            , layout = EditorLayout.sync model.wrapColumns 0 model.lines lines model.layout
            , affinity = EditorLayout.Downstream
            , desiredColumn = Nothing
            , content = TextBuffer.toString lines
            , cursor = followLine model.cursor
            , anchor = Maybe.map followLine model.anchor
            , maxLineLength = longestOf lines
            , dirtyState = Dirty
            , undo = { lines = model.lines, cursor = model.cursor } :: List.take undoLimit model.undo
            , redo = []
            , coalesce = NoCoalesce
        }


{-| Where to scroll this frame while a drag is held outside the editor, or
Nothing while the pointer is inside it. Speed grows with the distance out so
a small overshoot creeps and a big one races, and is capped so the document
still passes at a followable rate.
-}
autoScrollStep : Model -> Maybe ( Float, Float )
autoScrollStep model =
    case model.dragPointer of
        Nothing ->
            Nothing

        Just pointer ->
            let
                m =
                    model.metrics

                -- how far outside the viewport the pointer is, per axis
                beyond low high value =
                    if value < low then
                        value - low

                    else if value > high then
                        value - high

                    else
                        0

                speed distance =
                    clamp -autoScrollMaxStep autoScrollMaxStep (distance * autoScrollFactor)

                top =
                    clamp 0 (Basics.max 0 (toFloat (EditorLayout.rowCount model.layout) * m.lineHeight - m.viewportHeight)) (model.scrollTop + speed (beyond m.viewportTop (m.viewportTop + m.viewportHeight) pointer.y))

                left =
                    if model.softWrap then
                        0

                    else
                        Basics.max 0 (model.scrollLeft + speed (beyond m.viewportLeft (m.viewportLeft + m.viewportWidth) pointer.x))
            in
            if top == model.scrollTop && left == model.scrollLeft then
                Nothing

            else
                Just ( left, top )


autoScrollMaxStep : Float
autoScrollMaxStep =
    28


autoScrollFactor : Float
autoScrollFactor =
    0.25


{-| A pointer position in window coordinates as a position in the document.
-}
positionAtWindow : { x : Float, y : Float } -> Model -> EditorLayout.Position
positionAtWindow pointer model =
    let
        x =
            pointer.x - model.metrics.viewportLeft + model.scrollLeft

        y =
            pointer.y - model.metrics.viewportTop + model.scrollTop
    in
    if model.softWrap then
        EditorLayout.positionAt (floor (y / model.metrics.lineHeight)) (round (x / model.metrics.charWidth)) model.layout

    else
        let
            line =
                clamp 0 (Basics.max 0 (Array.length model.lines - 1)) (floor (y / model.metrics.lineHeight))

            text =
                Array.get line model.lines |> Maybe.withDefault ""
        in
        { cursor = { line = line, col = TextBuffer.columnFromVisual text (round (x / model.metrics.charWidth)) }, affinity = EditorLayout.Downstream }


moveScreen : Int -> Model -> Model
moveScreen delta model =
    let
        screen =
            EditorLayout.screenPosition { cursor = model.cursor, affinity = model.affinity } model.layout

        desired =
            Maybe.withDefault screen.cell model.desiredColumn

        at =
            EditorLayout.positionAt (screen.row + delta) desired model.layout
    in
    { model | cursor = at.cursor, affinity = at.affinity, desiredColumn = Just desired, anchor = Nothing, coalesce = NoCoalesce }


screenEdge : Bool -> Model -> Model
screenEdge end model =
    let
        screen =
            EditorLayout.screenPosition { cursor = model.cursor, affinity = model.affinity } model.layout

        fragment =
            EditorLayout.fragmentAt screen.row model.layout

        at =
            EditorLayout.positionAt screen.row
                (if end then
                    fragment.segment.endCell - fragment.segment.startCell

                 else
                    0
                )
                model.layout
    in
    { model | cursor = at.cursor, affinity = at.affinity, desiredColumn = Nothing, anchor = Nothing, coalesce = NoCoalesce }


{-| Preserve the source position at the top across reflow. An off-screen caret
must not pull a reader back to an old editing position during a pane resize.
-}
reflow : VirtualEditor.Metrics -> Bool -> Model -> Model
reflow metrics enabled model =
    let
        width =
            EditorLayout.columns enabled metrics.viewportWidth metrics.charWidth

        changed =
            width /= model.wrapColumns

        layout =
            if changed then
                EditorLayout.build width model.lines

            else
                model.layout

        oldRow =
            model.scrollTop / model.metrics.lineHeight

        atTop =
            EditorLayout.positionAt (floor oldRow) 0 model.layout

        newRow =
            EditorLayout.screenPosition atTop layout

        top =
            (toFloat newRow.row + oldRow - toFloat (floor oldRow)) * metrics.lineHeight

        oldCaret =
            caretPixels model

        visible =
            oldCaret.y >= model.scrollTop && oldCaret.y + model.metrics.lineHeight <= model.scrollTop + model.metrics.viewportHeight

        measured =
            { model
                | metrics = metrics
                , layout = layout
                , softWrap = enabled
                , wrapColumns = width
                , scrollTop = clamp 0 (Basics.max 0 (toFloat (EditorLayout.rowCount layout) * metrics.lineHeight - metrics.viewportHeight)) top
                , scrollLeft =
                    if enabled then
                        0

                    else
                        model.scrollLeft
                , desiredColumn =
                    if changed then
                        Nothing

                    else
                        model.desiredColumn
            }
    in
    if visible then
        case caretFollow measured of
            Just target ->
                { measured | scrollTop = target.top, scrollLeft = target.left }

            Nothing ->
                measured

    else
        measured


caretPixels : Model -> { x : Float, y : Float }
caretPixels model =
    if model.softWrap then
        let
            at =
                EditorLayout.screenPosition { cursor = model.cursor, affinity = model.affinity } model.layout
        in
        { x = toFloat at.cell * model.metrics.charWidth, y = toFloat at.row * model.metrics.lineHeight }

    else
        VirtualEditor.caretPosition model.metrics model.lines model.cursor


{-| The selection in document order, if any text is selected.
-}
selection : Model -> Maybe ( Cursor, Cursor )
selection model =
    model.anchor
        |> Maybe.andThen
            (\a ->
                if a == model.cursor then
                    Nothing

                else
                    Just (TextBuffer.order a model.cursor)
            )


selectedText : Model -> String
selectedText model =
    selection model |> Maybe.map (\( s, e ) -> TextBuffer.sliceRange s e model.lines) |> Maybe.withDefault ""


dragging : Model -> Bool
dragging model =
    model.dragging


{-| Apply a buffer edit, recording an undo snapshot unless it coalesces with
the previous edit of the same kind (a run of typed characters or deletions).
-}
edit : Coalesce -> (Cursor -> Array String -> ( Array String, Cursor )) -> Model -> Model
edit kind op model =
    let
        -- an edit with a selection first removes the selection (for
        -- deletions that is the whole edit)
        ( baseLines, baseCursor, hadSelection ) =
            case selection model of
                Just ( s, e ) ->
                    let
                        ( l, c ) =
                            TextBuffer.deleteRange s e model.lines
                    in
                    ( l, c, True )

                Nothing ->
                    ( model.lines, model.cursor, False )

        ( lines, cursor ) =
            op baseCursor baseLines

        undo =
            if kind /= NoCoalesce && kind == model.coalesce && not hadSelection then
                model.undo

            else
                { lines = model.lines, cursor = model.cursor } :: List.take undoLimit model.undo

        newContent =
            -- ponytail: O(n) join per keystroke (~1ms at 10k lines)
            TextBuffer.toString lines
    in
    if lines == model.lines then
        { model | cursor = cursor, anchor = Nothing, affinity = EditorLayout.Downstream, desiredColumn = Nothing }

    else
        { model
            | lines = lines
            , layout =
                if kind == NoCoalesce then
                    EditorLayout.sync model.wrapColumns 0 model.lines lines model.layout

                else
                    EditorLayout.syncRange model.wrapColumns
                        (Basics.max 0 (baseCursor.line - 1))
                        (Basics.min (Array.length model.lines) (Basics.max model.cursor.line (Maybe.map .line model.anchor |> Maybe.withDefault model.cursor.line) + 2))
                        model.lines
                        lines
                        model.layout
            , affinity = EditorLayout.Downstream
            , desiredColumn = Nothing
            , cursor = cursor
            , anchor = Nothing
            , content = newContent
            , maxLineLength = widestLine model lines newContent
            , dirtyState = Dirty
            , undo = undo
            , redo = []
            , coalesce =
                if hadSelection then
                    NoCoalesce

                else
                    kind
        }


{-| A deletion. Removing a selection is the whole edit; `op` only runs when
there is nothing selected, so Backspace with a selection deletes exactly it
rather than it plus another character.
-}
deletion : Coalesce -> (Cursor -> Array String -> ( Array String, Cursor )) -> Model -> Model
deletion kind op model =
    if selection model == Nothing then
        edit kind op model

    else
        edit kind (\cursor lines -> ( lines, cursor )) model


{-| The longest line, which sets the horizontal scroll width. An insertion can
only widen the edited line, so the old maximum answers it; a deletion may have
removed the widest line, so that case is recomputed.
-}
widestLine : Model -> Array String -> String -> Int
widestLine model lines newContent =
    if String.length newContent < String.length model.content then
        longestOf lines

    else
        Basics.max model.maxLineLength (String.length (Array.get model.cursor.line lines |> Maybe.withDefault ""))


longestOf : Array String -> Int
longestOf =
    Array.foldl (\line widest -> Basics.max widest (String.length line)) 0


restore : Snapshot -> Model -> Model
restore snapshot model =
    { model
        | lines = snapshot.lines
        , layout = EditorLayout.sync model.wrapColumns 0 model.lines snapshot.lines model.layout
        , affinity = EditorLayout.Downstream
        , desiredColumn = Nothing
        , cursor = TextBuffer.clampCursor snapshot.lines snapshot.cursor
        , content = TextBuffer.toString snapshot.lines
        , anchor = Nothing
        , maxLineLength = longestOf snapshot.lines
        , dirtyState = Dirty
        , coalesce = NoCoalesce
    }


undoLimit : Int
undoLimit =
    200


{-| Where to scroll so the caret is visible, or Nothing if it already is.
Decided from the model's own scroll position at the moment the caret moves:
reading the DOM later (Browser.Dom.getViewportOf) raced with the user's own
scrolling and yanked the view back to a stale caret.
-}
caretFollow : Model -> Maybe { left : Float, top : Float }
caretFollow model =
    let
        caret =
            caretPixels model

        m =
            model.metrics

        within lo size lo0 span =
            -- keep [lo, lo + size] inside the window [lo0, lo0 + span]
            if lo < lo0 then
                lo

            else if lo + size > lo0 + span then
                lo + size - span

            else
                lo0

        left =
            if model.softWrap then
                0

            else
                within caret.x m.charWidth model.scrollLeft m.viewportWidth

        top =
            within caret.y m.lineHeight model.scrollTop m.viewportHeight
    in
    if left == model.scrollLeft && top == model.scrollTop then
        Nothing

    else
        Just { left = Basics.max 0 left, top = Basics.max 0 top }


{-| Keys the virtual editor handles itself. Anything it returns Nothing for
bubbles to the application: Cmd+S, the sidebar toggles, and copy/cut/paste,
which the browser and js/virtual-input.js handle.
-}
keyDecoder : D.Decoder ( Msg, Bool )
keyDecoder =
    D.map5
        (\key meta ctrl shift alt -> { key = key, meta = meta, ctrl = ctrl, shift = shift, alt = alt })
        (D.field "key" D.string)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        |> D.andThen
            (\event ->
                case editorAction event of
                    Just msg ->
                        D.succeed ( msg, True )

                    Nothing ->
                        D.fail "not an editing key"
            )


type alias KeyEvent =
    { key : String, meta : Bool, ctrl : Bool, shift : Bool, alt : Bool }


{-| Modifier conventions, chosen to fit both platforms at once: Cmd or Ctrl
plus a letter are the usual shortcuts; for motion and deletion, Cmd is
line-or-document scope (macOS) while Option and Ctrl are word scope (macOS
and Windows/Linux respectively).
-}
editorAction : KeyEvent -> Maybe Msg
editorAction { key, meta, ctrl, shift, alt } =
    let
        shortcut =
            meta || ctrl

        wordScope =
            alt || ctrl

        lineScope =
            meta && not alt

        motion editorKey =
            Just
                (if shift then
                    Select editorKey

                 else
                    KeyPressed editorKey
                )

        press =
            KeyPressed >> Just

        typed =
            if String.length key == 1 && not shortcut && not alt then
                press (Char key)

            else
                -- dead keys, IME and function keys reach us as `input` instead
                Nothing
    in
    case key of
        "z" ->
            if shortcut then
                Just
                    (if shift then
                        Redo

                     else
                        Undo
                    )

            else
                typed

        "a" ->
            if shortcut && not shift then
                Just SelectAll

            else
                typed

        "d" ->
            if shortcut && shift then
                press DuplicateLine

            else
                typed

        "k" ->
            if shortcut && shift then
                press DeleteLine

            else if shortcut then
                press Link

            else
                typed

        "b" ->
            if shortcut && not shift then
                press (Wrap "**")

            else
                typed

        "i" ->
            if shortcut && not shift then
                press (Wrap "*")

            else
                typed

        "e" ->
            if shortcut && not shift then
                press (Wrap "`")

            else
                typed

        "x" ->
            if shortcut && shift then
                press (Wrap "~~")

            else
                typed

        "/" ->
            if shortcut then
                press ToggleComment

            else
                typed

        "ArrowLeft" ->
            motion (scoped wordScope WordLeft lineScope Home Left)

        "ArrowRight" ->
            motion (scoped wordScope WordRight lineScope End Right)

        "ArrowUp" ->
            if alt && not shortcut then
                press MoveLineUp

            else
                motion (scoped False Up lineScope DocStart Up)

        "ArrowDown" ->
            if alt && not shortcut then
                press MoveLineDown

            else
                motion (scoped False Down lineScope DocEnd Down)

        "Home" ->
            motion (scoped False Home shortcut DocStart Home)

        "End" ->
            motion (scoped False End shortcut DocEnd End)

        "PageUp" ->
            motion PageUp

        "PageDown" ->
            motion PageDown

        "Backspace" ->
            press (scoped wordScope DeleteWordBack lineScope DeleteToLineStart Backspace)

        "Delete" ->
            press (scoped wordScope DeleteWordForward False DeleteKey DeleteKey)

        "Enter" ->
            if shortcut then
                press
                    (if shift then
                        OpenLineAbove

                     else
                        OpenLineBelow
                    )

            else
                press Enter

        "Tab" ->
            press
                (if shift then
                    ShiftTab

                 else
                    Tab
                )

        "Escape" ->
            press Escape

        _ ->
            typed


insertText : String -> Model -> Model
insertText text model =
    if String.isEmpty text then
        model

    else
        edit
            (if String.length text == 1 && text /= "\n" && text /= " " then
                Typing

             else
                NoCoalesce
            )
            (TextBuffer.insert text)
            model


{-| Pasted text that should become a link's target rather than plain text. -}
isUrl : String -> Bool
isUrl text =
    let
        trimmed =
            String.trim text
    in
    trimmed
        == text
        && not (String.contains " " trimmed)
        && List.any (\scheme -> String.startsWith scheme trimmed) [ "http://", "https://" ]


{-| Toggle a pair of markers around the selection, or around the caret when
there is none. A selection already wrapped - whether or not the markers are
part of it - is unwrapped, so the shortcut is its own undo.
-}
wrap : String -> Model -> Model
wrap marker model =
    case selection model of
        Nothing ->
            insertAround (marker ++ marker) (String.length marker) model

        Just ( s, e ) ->
            let
                inner =
                    TextBuffer.sliceRange s e model.lines

                width =
                    String.length marker

                outside =
                    TextBuffer.sliceRange (backBy width s model) (forwardBy width e model) model.lines
            in
            if String.length inner >= 2 * width && String.startsWith marker inner && String.endsWith marker inner then
                -- the markers are inside the selection
                let
                    stripped =
                        String.slice width -width inner
                in
                replaceRange s e stripped 0 (String.length stripped) model

            else if String.startsWith marker outside && String.endsWith marker outside && String.length outside == String.length inner + 2 * width then
                -- the selection is the text between the markers
                replaceRange (backBy width s model) (forwardBy width e model) inner 0 (String.length inner) model

            else
                replaceRange s e (marker ++ inner ++ marker) width (String.length inner) model


{-| A column `n` before a cursor, clamped to the line. -}
backBy : Int -> Cursor -> Model -> Cursor
backBy n cursor model =
    TextBuffer.clampCursor model.lines { cursor | col = Basics.max 0 (cursor.col - n) }


forwardBy : Int -> Cursor -> Model -> Cursor
forwardBy n cursor model =
    TextBuffer.clampCursor model.lines { cursor | col = cursor.col + n }


{-| Replace the range `s`..`e` with `text`, then place the caret `offset`
characters into it and select `length` characters from there.
-}
replaceRange : Cursor -> Cursor -> String -> Int -> Int -> Model -> Model
replaceRange s e text offset length model =
    let
        replaced =
            edit NoCoalesce
                (\_ lines ->
                    let
                        ( cleared, at ) =
                            TextBuffer.deleteRange s e lines
                    in
                    TextBuffer.insert text at cleared
                )
                -- the op removes the range itself, so `edit` must not also
                -- delete a selection before running it
                { model | anchor = Nothing }

        start =
            TextBuffer.offsetOf replaced.lines replaced.cursor - String.length text + offset
    in
    { replaced
        | cursor = TextBuffer.cursorAt replaced.lines (start + length)
        , anchor =
            if length == 0 then
                Nothing

            else
                Just (TextBuffer.cursorAt replaced.lines start)
    }


{-| Insert `text` at the caret and put the caret `offset` characters into it. -}
insertAround : String -> Int -> Model -> Model
insertAround text offset model =
    let
        inserted =
            edit NoCoalesce (TextBuffer.insert text) model
    in
    { inserted | cursor = backBy (String.length text - offset) inserted.cursor inserted, anchor = Nothing }


commentPattern : Regex.Regex
commentPattern =
    compile "^\\s*<!--.*-->\\s*$"


{-| The lines a line operation acts on: those the selection touches, or the
one holding the caret. A selection ending in column 0 stops on the line above,
so selecting down to the start of a line does not drag it in.
-}
lineSpan : Model -> ( Int, Int )
lineSpan model =
    case selection model of
        Just ( s, e ) ->
            ( s.line
            , if e.col == 0 && e.line > s.line then
                e.line - 1

              else
                e.line
            )

        Nothing ->
            ( model.cursor.line, model.cursor.line )


moveCursorLines : Int -> Cursor -> Cursor
moveCursorLines delta cursor =
    { cursor | line = cursor.line + delta }


moveSpan : Int -> Model -> Model
moveSpan delta model =
    let
        ( from, to ) =
            lineSpan model
    in
    lineEdit (TextBuffer.moveLines from to delta) (moveCursorLines delta) model


openLine : Int -> Model -> Model
openLine at model =
    lineEdit
        (\lines ->
            Array.append (Array.append (Array.slice 0 at lines) (Array.fromList [ "" ]))
                (Array.slice at (Array.length lines) lines)
        )
        (\_ -> { line = at, col = 0 })
        model


{-| A whole-line edit: no selection is deleted first (the lines themselves are
the target), and the caret and selection are carried by `followCursor`.
-}
lineEdit : (Array String -> Array String) -> (Cursor -> Cursor) -> Model -> Model
lineEdit op followCursor model =
    let
        lines =
            op model.lines
    in
    if lines == model.lines then
        model

    else
        let
            content =
                TextBuffer.toString lines
        in
        { model
            | lines = lines
            , layout = EditorLayout.sync model.wrapColumns 0 model.lines lines model.layout
            , affinity = EditorLayout.Downstream
            , desiredColumn = Nothing
            , content = content
            , cursor = TextBuffer.clampCursor lines (followCursor model.cursor)
            , anchor = Maybe.map (TextBuffer.clampCursor lines << followCursor) model.anchor
            , maxLineLength = longestOf lines
            , dirtyState = Dirty
            , undo = { lines = model.lines, cursor = model.cursor } :: List.take undoLimit model.undo
            , redo = []
            , coalesce = NoCoalesce
        }


{-| Enter inside a list item or blockquote repeats the marker on the next
line; on an item with no content it clears the marker instead, which is how a
list is ended.
-}
continueList : Model -> Model
continueList model =
    let
        line =
            Array.get model.cursor.line model.lines |> Maybe.withDefault ""

        bareNewline =
            edit NoCoalesce (TextBuffer.insert "\n") model
    in
    case listMarker line of
        Just marker ->
            if model.cursor.col < String.length marker.prefix then
                -- the caret is still inside the marker: nothing to repeat
                bareNewline

            else if String.length line == String.length marker.prefix then
                edit NoCoalesce (\cursor lines -> ( Array.set cursor.line "" lines, { line = cursor.line, col = 0 } )) model

            else
                edit NoCoalesce (TextBuffer.insert ("\n" ++ marker.next)) model

        Nothing ->
            bareNewline


{-| The list or quote marker a line opens with: what it spans, and what the
next line has to start with to continue it.
-}
listMarker : String -> Maybe { prefix : String, next : String }
listMarker line =
    case firstMatch bulletPattern line of
        Just prefix ->
            -- a continued task item starts unticked, whatever this one holds
            Just { prefix = prefix, next = String.replace "[x]" "[ ]" (String.replace "[X]" "[ ]" prefix) }

        Nothing ->
            case firstMatch orderedPattern line of
                Just prefix ->
                    -- the digits are the only ones in the prefix (the rest is
                    -- whitespace and the delimiter), so replacing them is safe
                    firstMatch digitsPattern prefix
                        |> Maybe.map
                            (\digits ->
                                { prefix = prefix
                                , next = String.replace digits (increment digits) prefix
                                }
                            )

                Nothing ->
                    firstMatch quotePattern line
                        |> Maybe.map (\prefix -> { prefix = prefix, next = prefix })


increment : String -> String
increment digits =
    String.toInt digits |> Maybe.withDefault 0 |> (+) 1 |> String.fromInt


{-| The text a pattern matches at the start of a string. Whole matches only:
elm/regex reports a group that matched the empty string as no group at all.
-}
firstMatch : Regex.Regex -> String -> Maybe String
firstMatch pattern source =
    Regex.findAtMost 1 pattern source |> List.head |> Maybe.map .match


bulletPattern : Regex.Regex
bulletPattern =
    compile "^[ \t]*[-*+](\\s\\[[ xX]\\])?[ \t]+"


orderedPattern : Regex.Regex
orderedPattern =
    compile "^[ \t]*\\d+[.)][ \t]+"


quotePattern : Regex.Regex
quotePattern =
    compile "^[ \t]*>+[ \t]?"


digitsPattern : Regex.Regex
digitsPattern =
    compile "\\d+"


compile : String -> Regex.Regex
compile source =
    Regex.fromString source |> Maybe.withDefault Regex.never


{-| Pick the word-scope, line-scope or plain key for a keypress.
-}
scoped : Bool -> Key -> Bool -> Key -> Key -> Key
scoped isWord wordKey isLine lineKey plainKey =
    if isWord then
        wordKey

    else if isLine then
        lineKey

    else
        plainKey


view :
    { highlights : List ( Cursor, Cursor )
    , activeHighlight : Maybe ( Cursor, Cursor )
    , status : String -- shown at the right of the pane header
    }
    -> Model
    -> Html Msg
view found model =
    div [ class "editor-pane", attribute "data-testid" "editor-pane" ]
        [ div [ class "pane-header", attribute "data-testid" "editor-header" ]
            [ span [] [ text (headerText model) ]
            , span [ class "pane-header-status", attribute "data-testid" "word-count" ] [ text found.status ]
            ]
        , div [ class "editor-container" ]
            [ VirtualEditor.view
                { onScroll = ScrollChanged
                , highlightLine = highlightLine
                , highlightFragment = viewFragment model.tokenCache
                , layout = model.layout
                , affinity = model.affinity
                , softWrap = model.softWrap
                , keyDecoder = keyDecoder
                , onInput = InsertText
                , onPaste = InsertText
                , onPointerDown = PointerDown
                , onCut = CutSelection
                , cursor = model.cursor
                , selection = selection model
                , highlights = found.highlights
                , activeHighlight = found.activeHighlight
                , selectedText = selectedText model
                , documentPath = Maybe.withDefault "" model.filePath
                , contentLength = String.length model.content
                }
                model.metrics
                model.scrollTop
                model.maxLineLength
                model.lines
            ]
        ]


headerText : Model -> String
headerText model =
    case model.filePath of
        Just path ->
            baseName path
                ++ (if model.dirtyState == Dirty then
                        " *"

                    else
                        ""
                   )

        Nothing ->
            "Editor"



-- SYNTAX HIGHLIGHTING


{-| Only the visible source lines are tokenized. Token offsets let fragments
near the end of a huge paragraph skip earlier syntax runs with binary search.
-}
type alias CachedTokens =
    { source : String, tokens : Array IndexedToken }


type alias IndexedToken =
    { start : Int, end : Int, token : Token }


indexTokens : String -> Array IndexedToken
indexTokens source =
    lineTokens source
        |> List.foldl
            (\token ( offset, acc ) ->
                let
                    end =
                        offset + String.length token.text
                in
                ( end, { start = offset, end = end, token = token } :: acc )
            )
            ( 0, [] )
        |> Tuple.second
        |> List.reverse
        |> Array.fromList


refreshTokens : Model -> Model
refreshTokens model =
    if not model.softWrap then
        { model | tokenCache = Dict.empty }

    else
        let
            ( from, to ) =
                VirtualEditor.visibleRange model.metrics model.scrollTop (EditorLayout.rowCount model.layout)

            add fragment cache =
                if Dict.member fragment.line cache then
                    cache

                else
                    let
                        cached =
                            case Dict.get fragment.line model.tokenCache of
                                Just old ->
                                    if old.source == fragment.text then
                                        old

                                    else
                                        { source = fragment.text, tokens = indexTokens fragment.text }

                                Nothing ->
                                    { source = fragment.text, tokens = indexTokens fragment.text }
                    in
                    Dict.insert fragment.line cached cache
        in
        { model | tokenCache = List.foldl add Dict.empty (EditorLayout.fragments from to model.layout) }


viewFragment : Dict Int CachedTokens -> EditorLayout.Fragment -> Html msg
viewFragment cache fragment =
    let
        tokens =
            case Dict.get fragment.line cache of
                Just cached ->
                    if cached.source == fragment.text then
                        cached.tokens

                    else
                        indexTokens fragment.text

                Nothing ->
                    indexTokens fragment.text
    in
    Html.Lazy.lazy3 fragmentTokens tokens fragment.segment fragment.text


fragmentTokens : Array IndexedToken -> EditorLayout.Segment -> String -> Html msg
fragmentTokens tokens segment source =
    let
        search lo hi =
            if lo >= hi then
                lo

            else
                let
                    mid =
                        (lo + hi) // 2

                    end =
                        Array.get mid tokens |> Maybe.map .end |> Maybe.withDefault 0
                in
                if end <= segment.start then
                    search (mid + 1) hi

                else
                    search lo mid

        collect index cell acc =
            case Array.get index tokens of
                Just indexed ->
                    if indexed.start >= segment.end then
                        List.reverse acc

                    else
                        let
                            part =
                                String.slice (Basics.max segment.start indexed.start) (Basics.min segment.end indexed.end) source

                            expanded =
                                EditorLayout.expandTabs cell part

                            token =
                                indexed.token
                        in
                        collect (index + 1) (cell + List.length (String.toList expanded)) (viewToken { token | text = expanded } :: acc)

                Nothing ->
                    List.reverse acc
    in
    div [ class "editor-line" ] (collect (search 0 (Array.length tokens)) segment.startCell [])


{-| One highlighted run. Concatenating the tokens reproduces the source line.
-}
type alias Token =
    { class : Maybe String, text : String }


plain : String -> Token
plain str =
    { class = Nothing, text = str }


styled : String -> String -> Token
styled cls str =
    { class = Just cls, text = str }


highlightLine : String -> Html msg
highlightLine line =
    div [ class "editor-line" ] (List.map viewToken (lineTokens line))


viewToken : Token -> Html msg
viewToken token =
    case token.class of
        Just cls ->
            span [ class cls ] [ text token.text ]

        Nothing ->
            text token.text


lineTokens : String -> List Token
lineTokens line =
    let
        trimmed =
            String.trimLeft line

        indent =
            String.left (String.length line - String.length trimmed) line

        whole cls =
            [ styled cls line ]

        listItem markerLen =
            plain indent
                :: styled "md-list-marker" (String.left markerLen trimmed)
                :: inlineTokens (String.dropLeft markerLen trimmed)
    in
    if String.startsWith "# " trimmed then
        whole "md-h1"

    else if String.startsWith "## " trimmed then
        whole "md-h2"

    else if String.startsWith "### " trimmed then
        whole "md-h3"

    else if String.startsWith "#### " trimmed then
        whole "md-h4"

    else if String.startsWith "##### " trimmed then
        whole "md-h5"

    else if String.startsWith "###### " trimmed then
        whole "md-h6"

    else if String.startsWith "```" trimmed then
        whole "md-code-fence"

    else if String.startsWith ">" trimmed then
        whole "md-blockquote-marker"

    else if String.startsWith "- " trimmed || String.startsWith "* " trimmed || String.startsWith "+ " trimmed then
        listItem 2

    else if isOrderedListItem trimmed then
        listItem
            (case String.indexes ". " trimmed of
                i :: _ ->
                    i + 2

                [] ->
                    0
            )

    else if String.startsWith "---" trimmed || String.startsWith "***" trimmed || String.startsWith "___" trimmed then
        whole "md-hr"

    else
        inlineTokens line


isOrderedListItem : String -> Bool
isOrderedListItem line =
    case String.toInt (String.left 1 line) of
        Just _ ->
            String.contains ". " (String.left 5 line)

        Nothing ->
            False


{-| Inline elements: bold, italic, links, code spans.
-}
inlineTokens : String -> List Token
inlineTokens line =
    parseInline line []


parseInline : String -> List Token -> List Token
parseInline remaining acc =
    if String.isEmpty remaining then
        List.reverse (mergePlain acc)

    else if String.startsWith "**" remaining then
        case findClosing "**" (String.dropLeft 2 remaining) of
            Just ( inner, rest ) ->
                parseInline rest (styled "md-bold-marker" ("**" ++ inner ++ "**") :: acc)

            Nothing ->
                parseInline (String.dropLeft 2 remaining) (plain "**" :: acc)

    else if String.startsWith "*" remaining then
        case findClosing "*" (String.dropLeft 1 remaining) of
            Just ( inner, rest ) ->
                parseInline rest (styled "md-italic-marker" ("*" ++ inner ++ "*") :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (plain "*" :: acc)

    else if String.startsWith "`" remaining then
        case findClosing "`" (String.dropLeft 1 remaining) of
            Just ( inner, rest ) ->
                parseInline rest (styled "md-code-span" ("`" ++ inner ++ "`") :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (plain "`" :: acc)

    else if String.startsWith "[" remaining then
        case parseLinkMarkdown (String.dropLeft 1 remaining) of
            Just ( linkText, url, rest ) ->
                parseInline rest (styled "md-link" ("[" ++ linkText ++ "](" ++ url ++ ")") :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (plain "[" :: acc)

    else
        let
            n =
                Basics.max 1 (findNextSpecial remaining)
        in
        parseInline (String.dropLeft n remaining) (mergePlain (plain (String.left n remaining) :: acc))


{-| Collapse two adjacent unstyled runs at the head of the (reversed)
accumulator: fewer text nodes in the overlay means less to lay out.
-}
mergePlain : List Token -> List Token
mergePlain acc =
    case acc of
        a :: b :: rest ->
            if a.class == Nothing && b.class == Nothing then
                plain (b.text ++ a.text) :: rest

            else
                acc

        _ ->
            acc


{-| Code-unit index of the next inline delimiter, or the string length.

Two constraints: it must be code-unit based (like `String.left`), never a
`String.toList` position, or a surrogate pair gets split and elm/core's
string folds hang on the lone surrogate; and it must stop at the first hit,
because `String.indexes` scans the whole remainder and turns a long line
with many delimiters quadratic (a 200k-char line took 87s).
-}
findNextSpecial : String -> Int
findNextSpecial str =
    firstIndex nextSpecialRegex str |> Maybe.withDefault (String.length str)


nextSpecialRegex : Regex.Regex
nextSpecialRegex =
    Regex.fromString "[*`\\[]" |> Maybe.withDefault Regex.never


firstIndex : Regex.Regex -> String -> Maybe Int
firstIndex regex str =
    Regex.findAtMost 1 regex str |> List.head |> Maybe.map .index


literal : String -> Regex.Regex
literal delimiter =
    Regex.fromString (escapeRegex delimiter) |> Maybe.withDefault Regex.never


specialRegexChars : Regex.Regex
specialRegexChars =
    Regex.fromString "[.*+?^${}()|\\[\\]\\\\]" |> Maybe.withDefault Regex.never


escapeRegex : String -> String
escapeRegex =
    Regex.replace specialRegexChars (\m -> "\\" ++ m.match)


closingBold : Regex.Regex
closingBold =
    literal "**"


closingItalic : Regex.Regex
closingItalic =
    literal "*"


closingCode : Regex.Regex
closingCode =
    literal "`"


linkMiddle : Regex.Regex
linkMiddle =
    literal "]("


linkEnd : Regex.Regex
linkEnd =
    literal ")"


findClosing : String -> String -> Maybe ( String, String )
findClosing delimiter str =
    let
        regex =
            case delimiter of
                "**" ->
                    closingBold

                "*" ->
                    closingItalic

                _ ->
                    closingCode
    in
    firstIndex regex str
        |> Maybe.map
            (\i ->
                ( String.left i str
                , String.dropLeft (i + String.length delimiter) str
                )
            )


parseLinkMarkdown : String -> Maybe ( String, String, String )
parseLinkMarkdown str =
    firstIndex linkMiddle str
        |> Maybe.andThen
            (\i ->
                let
                    afterBracket =
                        String.dropLeft (i + 2) str
                in
                firstIndex linkEnd afterBracket
                    |> Maybe.map
                        (\j ->
                            ( String.left i str
                            , String.left j afterBracket
                            , String.dropLeft (j + 1) afterBracket
                            )
                        )
            )
