module Editor exposing
    ( Model
    , Msg(..)
    , Token
    , init
    , Key(..)
    , caretFollow
    , dragging
    , highlightLine
    , keyDecoder
    , selectedText
    , selection
    , lineTokens
    , markSaved
    , setContent
    , update
    , view
    )

import Array exposing (Array)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
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


type Msg
    = ScrollChanged Float Float -- scrollTop scrollLeft
    | MetricsChanged VirtualEditor.Metrics
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
    case msg of
        ScrollChanged scrollTop scrollLeft ->
            { model | scrollTop = scrollTop, scrollLeft = scrollLeft }

        MetricsChanged metrics ->
            { model | metrics = metrics }

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

        PointerDown { x, y, shift, clicks } ->
            let
                at =
                    cursorAtPixel x y model

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
            { model | cursor = cursor, anchor = anchor, dragging = clicks == 1 && not shift, coalesce = NoCoalesce }

        PointerMoved x y ->
            if model.dragging then
                { model
                    | anchor = Just (Maybe.withDefault model.cursor model.anchor)
                    , dragPointer = Just { x = x, y = y }
                    , cursor = cursorAtWindow { x = x, y = y } model
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
                    { scrolled | cursor = cursorAtWindow pointer scrolled }

                _ ->
                    model

        PointerUp ->
            { model | dragging = False, dragPointer = Nothing, anchor = model.anchor |> Maybe.andThen (\a -> if a == model.cursor then Nothing else Just a) }

        SelectAll ->
            { model | anchor = Just TextBuffer.docStart, cursor = TextBuffer.docEnd model.lines, coalesce = NoCoalesce }

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
            { model | cursor = f model.cursor model.lines, anchor = Nothing, coalesce = NoCoalesce }

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
            move (TextBuffer.moveUp 1)

        Down ->
            move (TextBuffer.moveDown 1)

        PageUp ->
            move (TextBuffer.moveUp pageRows)

        PageDown ->
            move (TextBuffer.moveDown pageRows)

        Home ->
            move (\c _ -> TextBuffer.lineStart c)

        End ->
            move TextBuffer.lineEnd

        DocStart ->
            move (\_ _ -> TextBuffer.docStart)

        DocEnd ->
            move (\_ lines -> TextBuffer.docEnd lines)

        Char c ->
            edit Typing (TextBuffer.insert c) model

        Enter ->
            edit NoCoalesce (TextBuffer.insert "\n") model

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
                    Just ( s.line, e.line - (if e.col == 0 then 1 else 0) )

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
                    Basics.max 0 (model.scrollTop + speed (beyond m.viewportTop (m.viewportTop + m.viewportHeight) pointer.y))

                left =
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
cursorAtWindow : { x : Float, y : Float } -> Model -> Cursor
cursorAtWindow pointer model =
    cursorAtPixel
        (pointer.x - model.metrics.viewportLeft + model.scrollLeft)
        (pointer.y - model.metrics.viewportTop + model.scrollTop)
        model


cursorAtPixel : Float -> Float -> Model -> Cursor
cursorAtPixel x y model =
    let
        line =
            clamp 0 (Basics.max 0 (Array.length model.lines - 1)) (floor (y / model.metrics.lineHeight))

        text =
            Array.get line model.lines |> Maybe.withDefault ""
    in
    { line = line, col = TextBuffer.columnFromVisual text (round (x / model.metrics.charWidth)) }


{-| The selection in document order, if any text is selected. -}
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
        { model | cursor = cursor, anchor = Nothing }

    else
        { model
            | lines = lines
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
            VirtualEditor.caretPosition model.metrics model.lines model.cursor

        m =
            model.metrics

        pad =
            16

        within lo size lo0 span =
            -- keep [lo, lo + size] inside the window [lo0, lo0 + span]
            if lo < lo0 then
                lo

            else if lo + size > lo0 + span then
                lo + size - span

            else
                lo0

        left =
            within caret.x (m.charWidth + pad * 2) model.scrollLeft m.viewportWidth

        top =
            within caret.y (m.lineHeight + pad * 2) model.scrollTop m.viewportHeight
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

        "ArrowLeft" ->
            motion (scoped wordScope WordLeft lineScope Home Left)

        "ArrowRight" ->
            motion (scoped wordScope WordRight lineScope End Right)

        "ArrowUp" ->
            motion (scoped False Up lineScope DocStart Up)

        "ArrowDown" ->
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


view : Model -> Html Msg
view model =
    div [ class "editor-pane", attribute "data-testid" "editor-pane" ]
        [ div [ class "pane-header", attribute "data-testid" "editor-header" ]
            [ span []
                [ text (headerText model) ]
            ]
        , div [ class "editor-container" ]
            [ VirtualEditor.view
                { onScroll = ScrollChanged
                , highlightLine = highlightLine
                , keyDecoder = keyDecoder
                , onInput = InsertText
                , onPaste = InsertText
                , onPointerDown = PointerDown
                , onCut = CutSelection
                , cursor = model.cursor
                , selection = selection model
                , selectedText = selectedText model
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


{-| One run of highlighted text with an optional class. The concatenated
token text of a line is always the line itself (see EditorTest).
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
