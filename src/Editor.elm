module Editor exposing
    ( Model
    , Msg(..)
    , Token
    , chunksOf
    , init
    , lineTokens
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
import Types exposing (..)


type alias Model =
    { content : String
    , filePath : Maybe FilePath
    , dirtyState : DirtyState
    , revision : Maybe String
    , scrollTop : Float
    }


type Msg
    = ContentChanged String
    | ScrollChanged Float


init : Model
init =
    { content = ""
    , filePath = Nothing
    , dirtyState = Clean
    , revision = Nothing
    , scrollTop = 0
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


view : Model -> Html Msg
view model =
    div [ class "editor-pane", attribute "data-testid" "editor-pane" ]
        [ div [ class "pane-header", attribute "data-testid" "editor-header" ]
            [ span []
                [ text (headerText model) ]
            ]
        , div [ class "editor-container" ]
            [ pre
                [ class "editor-highlight"
                , attribute "data-testid" "editor-highlight"
                , style "transform" ("translateY(-" ++ String.fromFloat model.scrollTop ++ "px)")
                ]
                [ code [] (highlightMarkdown model.content) ]
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


highlightMarkdown : String -> List (Html msg)
highlightMarkdown content =
    if String.length content > maxHighlightedCharacters then
        -- A single text node keeps very large documents responsive. The
        -- textarea remains fully editable; only decorative highlighting is
        -- reduced.
        [ text content ]

    else
        content
            |> String.split "\n"
            |> chunksOf linesPerChunk
            -- lazy: a keystroke only re-renders (and re-diffs) the chunk it
            -- touched; Html.Lazy compares the chunk's text by value.
            |> List.map (String.join "\n" >> Html.Lazy.lazy highlightChunk)


{-| Each line is its own block element so the browser can skip layout for
lines that are off-screen (see `.editor-line` in editor.css).
-}
highlightChunk : String -> Html msg
highlightChunk chunk =
    div [ class "editor-chunk" ]
        (chunk
            |> String.split "\n"
            |> List.map (\line -> div [ class "editor-line" ] [ Html.Lazy.lazy highlightLine line ])
        )


linesPerChunk : Int
linesPerChunk =
    64


chunksOf : Int -> List a -> List (List a)
chunksOf n items =
    case items of
        [] ->
            []

        _ ->
            List.take n items :: chunksOf n (List.drop n items)


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
    span [] (List.map viewToken (lineTokens line))


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
        List.reverse acc

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
        parseInline (String.dropLeft n remaining) (plain (String.left n remaining) :: acc)


findNextSpecial : String -> Int
findNextSpecial str =
    let
        chars =
            String.toList str

        helper index cs =
            case cs of
                [] ->
                    String.length str

                c :: _ ->
                    if c == '*' || c == '`' || c == '[' then
                        if index == 0 then
                            0

                        else
                            index

                    else
                        helper (index + 1) (List.drop 1 cs)
    in
    helper 0 chars


findClosing : String -> String -> Maybe ( String, String )
findClosing delimiter str =
    case String.indexes delimiter str of
        i :: _ ->
            Just
                ( String.left i str
                , String.dropLeft (i + String.length delimiter) str
                )

        [] ->
            Nothing


parseLinkMarkdown : String -> Maybe ( String, String, String )
parseLinkMarkdown str =
    case String.indexes "](" str of
        i :: _ ->
            let
                linkText =
                    String.left i str

                afterBracket =
                    String.dropLeft (i + 2) str
            in
            case String.indexes ")" afterBracket of
                j :: _ ->
                    Just
                        ( linkText
                        , String.left j afterBracket
                        , String.dropLeft (j + 1) afterBracket
                        )

                [] ->
                    Nothing

        [] ->
            Nothing
