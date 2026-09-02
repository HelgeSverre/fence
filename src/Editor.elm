module Editor exposing
    ( Model
    , Msg(..)
    , Token
    , chunksOf
    , init
    , Key(..)
    , caretScroll
    , dragging
    , highlightLine
    , keyDecoder
    , selectedText
    , selection
    , lineTokens
    , overlayPending
    , markSaved
    , maxHighlightedCharacters
    , setContent
    , update
    , view
    )

import Array exposing (Array)
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
    , overlayLines : Maybe Int -- Just n: only the first n lines are highlighted so far
    , lines : Array String -- the content split by line, for the virtual view
    , maxLineLength : Int
    , metrics : VirtualEditor.Metrics
    , cursor : Cursor
    , anchor : Maybe Cursor -- other end of the selection, when there is one
    , dragging : Bool
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
    | Backspace
    | DeleteKey
    | Enter
    | Tab
    | ShiftTab
    | Char String


type Msg
    = ContentChanged String
    | ScrollChanged Float
    | OverlayStep
    | MetricsChanged VirtualEditor.Metrics
    | KeyPressed Key
    | Select Key -- shift + a movement key extends the selection
    | InsertText String
    | PointerDown { x : Float, y : Float, shift : Bool, clicks : Int }
    | PointerMove Float Float
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
    , overlayLines = Nothing
    , lines = Array.empty
    , maxLineLength = 0
    , metrics = VirtualEditor.defaultMetrics
    , cursor = TextBuffer.docStart
    , anchor = Nothing
    , dragging = False
    , undo = []
    , redo = []
    , coalesce = NoCoalesce
    }


setContent : FilePath -> String -> String -> Bool -> Model -> Model
setContent path content revision dirty model =
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
        , overlayLines = initialOverlay content
        , lines = splitLines content
        , maxLineLength = longestLine content
        , cursor = TextBuffer.docStart
        , anchor = Nothing
        , dragging = False
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
        ContentChanged content ->
            -- ponytail: re-splits the whole document per keystroke (~ms at 10k
            -- lines); slice 2 of the virtual editor edits lines in place.
            { model | content = content, dirtyState = Dirty, lines = splitLines content, maxLineLength = longestLine content, cursor = TextBuffer.clampCursor (splitLines content) model.cursor }

        ScrollChanged scrollTop ->
            { model | scrollTop = scrollTop }

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

        PointerMove x y ->
            if model.dragging then
                { model | anchor = Just (Maybe.withDefault model.cursor model.anchor), cursor = cursorAtPixel x y model }

            else
                model

        PointerUp ->
            { model | dragging = False, anchor = model.anchor |> Maybe.andThen (\a -> if a == model.cursor then Nothing else Just a) }

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

        OverlayStep ->
            case model.overlayLines of
                Just n ->
                    let
                        next =
                            n + overlayStepLines
                    in
                    { model
                        | overlayLines =
                            if next >= lineCount model.content then
                                Nothing

                            else
                                Just next
                    }

                Nothing ->
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
            edit Deleting TextBuffer.backspace model

        DeleteKey ->
            edit Deleting TextBuffer.deleteForward model


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

        fix c =
            TextBuffer.clampCursor lines { c | col = c.col + (String.length (Array.get c.line lines |> Maybe.withDefault "") - String.length (Array.get c.line model.lines |> Maybe.withDefault "")) }
    in
    if lines == model.lines then
        model

    else
        { model
            | lines = lines
            , content = TextBuffer.toString lines
            , cursor = fix model.cursor
            , anchor = Maybe.map fix model.anchor
            , maxLineLength = Array.foldl (\l m -> Basics.max m (String.length l)) 0 lines
            , dirtyState = Dirty
            , undo = { lines = model.lines, cursor = model.cursor } :: List.take undoLimit model.undo
            , redo = []
            , coalesce = NoCoalesce
        }


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
            if hadSelection && kind == Deleting then
                ( baseLines, baseCursor )

            else
                op baseCursor baseLines

        undo =
            if kind /= NoCoalesce && kind == model.coalesce && not hadSelection then
                model.undo

            else
                { lines = model.lines, cursor = model.cursor } :: List.take undoLimit model.undo
    in
    if lines == model.lines then
        { model | cursor = cursor, anchor = Nothing }

    else
        { model
            | lines = lines
            , cursor = cursor
            , anchor = Nothing
            , content = TextBuffer.toString lines -- ponytail: O(n) join per keystroke (~1ms at 10k lines)
            , maxLineLength = Basics.max model.maxLineLength (String.length (Array.get cursor.line lines |> Maybe.withDefault ""))
            , dirtyState = Dirty
            , undo = undo
            , redo = []
            , coalesce =
                if hadSelection then
                    NoCoalesce

                else
                    kind
        }


restore : Snapshot -> Model -> Model
restore snapshot model =
    { model
        | lines = snapshot.lines
        , cursor = TextBuffer.clampCursor snapshot.lines snapshot.cursor
        , content = TextBuffer.toString snapshot.lines
        , anchor = Nothing
        , maxLineLength = Array.foldl (\l m -> Basics.max m (String.length l)) 0 snapshot.lines
        , dirtyState = Dirty
        , coalesce = NoCoalesce
    }


undoLimit : Int
undoLimit =
    200


{-| Where the virtual editor must scroll so the caret is visible, if it is
not already. -}
caretScroll : Model -> Maybe { left : Float, top : Float }
caretScroll model =
    let
        m =
            model.metrics

        caret =
            VirtualEditor.caretPosition m model.lines model.cursor

        top =
            if caret.y < model.scrollTop then
                Just caret.y

            else if caret.y + m.lineHeight > model.scrollTop + m.viewportHeight - virtualPadding * 2 then
                Just (caret.y + m.lineHeight + virtualPadding * 2 - m.viewportHeight)

            else
                Nothing
    in
    Maybe.map (\t -> { left = 0, top = Basics.max 0 t }) top


virtualPadding : Float
virtualPadding =
    16


{-| Keys the virtual editor handles itself; anything else (Cmd+S, the
sidebar shortcuts) bubbles to the app. -}
keyDecoder : D.Decoder ( Msg, Bool )
keyDecoder =
    D.map5
        (\key meta ctrl shift alt -> { key = key, mod = meta || ctrl, shift = shift, alt = alt })
        (D.field "key" D.string)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        |> D.andThen
            (\{ key, mod, shift, alt } ->
                let
                    handled k =
                        D.succeed ( KeyPressed k, True )

                    movement k =
                        D.succeed
                            ( if shift then
                                Select k

                              else
                                KeyPressed k
                            , True
                            )
                in
                case ( key, mod, shift ) of
                    ( "z", True, False ) ->
                        D.succeed ( Undo, True )

                    ( "z", True, True ) ->
                        D.succeed ( Redo, True )

                    ( "a", True, False ) ->
                        D.succeed ( SelectAll, True )

                    ( "ArrowLeft", True, _ ) ->
                        movement Home

                    ( "ArrowRight", True, _ ) ->
                        movement End

                    ( "ArrowUp", True, _ ) ->
                        movement DocStart

                    ( "ArrowDown", True, _ ) ->
                        movement DocEnd

                    ( "Home", True, _ ) ->
                        movement DocStart

                    ( "End", True, _ ) ->
                        movement DocEnd

                    ( _, True, _ ) ->
                        D.fail "app shortcut"

                    ( "ArrowLeft", _, _ ) ->
                        movement Left

                    ( "ArrowRight", _, _ ) ->
                        movement Right

                    ( "ArrowUp", _, _ ) ->
                        movement Up

                    ( "ArrowDown", _, _ ) ->
                        movement Down

                    ( "Home", _, _ ) ->
                        movement Home

                    ( "End", _, _ ) ->
                        movement End

                    ( "PageUp", _, _ ) ->
                        movement PageUp

                    ( "PageDown", _, _ ) ->
                        movement PageDown

                    ( "Backspace", _, _ ) ->
                        handled Backspace

                    ( "Delete", _, _ ) ->
                        handled DeleteKey

                    ( "Enter", _, _ ) ->
                        handled Enter

                    ( "Tab", _, True ) ->
                        handled ShiftTab

                    ( "Tab", _, False ) ->
                        handled Tab

                    _ ->
                        if String.length key == 1 && not alt then
                            handled (Char key)

                        else
                            -- dead keys, IME, function keys: let the input event handle it
                            D.fail "not an editing key"
            )

{-| A large document paints with the textarea's own text first and builds
the highlight overlay a few thousand lines per frame behind it (see
`overlay-pending` in editor.css), so opening never blocks on laying out
tens of thousands of highlight nodes.
-}
initialOverlay : String -> Maybe Int
initialOverlay content =
    if lineCount content > initialOverlayLines then
        Just initialOverlayLines

    else
        Nothing


overlayPending : Model -> Bool
overlayPending model =
    model.overlayLines /= Nothing


lineCount : String -> Int
lineCount content =
    List.length (String.indexes "\n" content) + 1


initialOverlayLines : Int
initialOverlayLines =
    256


largeDocumentCharacters : Int
largeDocumentCharacters =
    200000


overlayStepLines : Int
overlayStepLines =
    2048


splitLines : String -> Array String
splitLines content =
    Array.fromList (String.split "\n" content)


longestLine : String -> Int
longestLine content =
    String.split "\n" content |> List.map String.length |> List.maximum |> Maybe.withDefault 0


view : { virtual : Bool } -> Model -> Html Msg
view options model =
    div [ class "editor-pane", attribute "data-testid" "editor-pane" ]
        [ div [ class "pane-header", attribute "data-testid" "editor-header" ]
            [ span []
                [ text (headerText model) ]
            ]
        , if options.virtual then
            div [ class "editor-container" ]
                [ VirtualEditor.view
                    { onScroll = ScrollChanged
                    , highlightLine = highlightLine
                    , keyDecoder = keyDecoder
                    , onInput = InsertText
                    , onPaste = InsertText
                    , onPointerDown = PointerDown
                    , onPointerMove = PointerMove
                    , onCut = CutSelection
                    , cursor = model.cursor
                    , selection = selection model
                    , selectedText = selectedText model
                    }
                    model.metrics
                    model.scrollTop
                    model.maxLineLength
                    model.lines
                ]

          else
            div
            [ class "editor-container"
            , classList
                [ ( "overlay-pending", overlayPending model )

                -- shaping ligatures across a huge textarea costs ~100ms per open
                , ( "large-document", String.length model.content > largeDocumentCharacters )
                ]
            ]
            [ pre
                [ class "editor-highlight"
                , attribute "data-testid" "editor-highlight"
                , style "transform" ("translateY(-" ++ String.fromFloat model.scrollTop ++ "px)")
                ]
                [ code [] (highlightMarkdown model.overlayLines model.content) ]
            , textarea
                [ class "editor-textarea"
                , attribute "data-testid" "editor-textarea"
                , spellcheck False
                , placeholder "Open a file to start editing..."
                , value model.content
                , onInput ContentChanged
                , on "scroll"
                    (D.at [ "target", "scrollTop" ] D.float
                        |> D.map ScrollChanged
                    )
                ]
                []
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


highlightMarkdown : Maybe Int -> String -> List (Html msg)
highlightMarkdown limit content =
    if String.length content > maxHighlightedCharacters then
        -- A single text node keeps very large documents responsive. The
        -- textarea remains fully editable; only decorative highlighting is
        -- reduced.
        [ text content ]

    else
        content
            |> String.split "\n"
            |> (case limit of
                    Just n ->
                        List.take n

                    Nothing ->
                        identity
               )
            |> chunksOf linesPerChunk
            -- lazy: a keystroke only re-renders (and re-diffs) the chunk it
            -- touched; Html.Lazy compares the chunk's text by value.
            |> List.map (String.join "\n" >> Html.Lazy.lazy highlightChunk)


{-| Each line is its own block element so a keystroke re-wraps only that
line (see `.editor-line` in editor.css).
-}
highlightChunk : String -> Html msg
highlightChunk chunk =
    div [ class "editor-chunk" ]
        (chunk
            |> String.split "\n"
            |> List.map (Html.Lazy.lazy highlightLine)
        )


linesPerChunk : Int
linesPerChunk =
    64


chunksOf : Int -> List a -> List (List a)
chunksOf n items =
    -- tail-recursive: a 500k-line document is ~8k chunks, past the JS stack
    chunksOfHelp n items []


chunksOfHelp : Int -> List a -> List (List a) -> List (List a)
chunksOfHelp n items acc =
    case items of
        [] ->
            List.reverse acc

        _ ->
            chunksOfHelp n (List.drop n items) (List.take n items :: acc)


maxHighlightedCharacters : Int
maxHighlightedCharacters =
    -- Lines are separate blocks, so per-line highlighting stays cheap far
    -- beyond this; the plain-text fallback is what reflows the whole document.
    1500000


{-| One run of overlay text with an optional highlight class. The overlay
must be character-identical to the textarea, so the concatenated token text
of a line is always the line itself (see EditorTest).
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
