module Editor exposing
    ( Model
    , Msg(..)
    , Token
    , chunksOf
    , init
    , lineTokens
    , overlayPending
    , markSaved
    , maxHighlightedCharacters
    , setContent
    , update
    , view
    )

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy
import Json.Decode as D
import Regex
import Types exposing (..)


type alias Model =
    { content : String
    , filePath : Maybe FilePath
    , dirtyState : DirtyState
    , revision : Maybe String
    , scrollTop : Float
    , overlayLines : Maybe Int -- Just n: only the first n lines are highlighted so far
    }


type Msg
    = ContentChanged String
    | ScrollChanged Float
    | OverlayStep


init : Model
init =
    { content = ""
    , filePath = Nothing
    , dirtyState = Clean
    , revision = Nothing
    , scrollTop = 0
    , overlayLines = Nothing
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
            { model | content = content, dirtyState = Dirty }

        ScrollChanged scrollTop ->
            { model | scrollTop = scrollTop }

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


view : Model -> Html Msg
view model =
    div [ class "editor-pane", attribute "data-testid" "editor-pane" ]
        [ div [ class "pane-header", attribute "data-testid" "editor-header" ]
            [ span []
                [ text (headerText model) ]
            ]
        , div
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
