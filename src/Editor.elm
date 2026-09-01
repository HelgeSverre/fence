module Editor exposing
    ( Model
    , Msg(..)
    , init
    , markSaved
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
    div [ class "editor-pane" ]
        [ div [ class "pane-header" ]
            [ span []
                [ text (headerText model) ]
            ]
        , div [ class "editor-container" ]
            [ pre
                [ class "editor-highlight"
                , style "transform" ("translateY(-" ++ String.fromFloat model.scrollTop ++ "px)")
                ]
                [ code [] (highlightMarkdown model.content) ]
            , textarea
                [ class "editor-textarea"
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


highlightLine : String -> Html msg
highlightLine line =
    let
        trimmed =
            String.trimLeft line

        leadingSpaces =
            String.length line - String.length trimmed
    in
    if String.startsWith "# " trimmed then
        span [ class "md-h1" ] [ text line ]

    else if String.startsWith "## " trimmed then
        span [ class "md-h2" ] [ text line ]

    else if String.startsWith "### " trimmed then
        span [ class "md-h3" ] [ text line ]

    else if String.startsWith "#### " trimmed then
        span [ class "md-h4" ] [ text line ]

    else if String.startsWith "##### " trimmed then
        span [ class "md-h5" ] [ text line ]

    else if String.startsWith "###### " trimmed then
        span [ class "md-h6" ] [ text line ]

    else if String.startsWith "```" trimmed then
        span [ class "md-code-fence" ] [ text line ]

    else if String.startsWith ">" trimmed then
        span [ class "md-blockquote-marker" ] [ text line ]

    else if String.startsWith "- " trimmed || String.startsWith "* " trimmed || String.startsWith "+ " trimmed then
        span []
            [ text (String.left leadingSpaces line)
            , span [ class "md-list-marker" ] [ text (String.left 2 trimmed) ]
            , highlightInline (String.dropLeft 2 trimmed)
            ]

    else if isOrderedListItem trimmed then
        let
            markerEnd =
                case String.indexes ". " trimmed of
                    i :: _ ->
                        i + 2

                    [] ->
                        0
        in
        span []
            [ text (String.left leadingSpaces line)
            , span [ class "md-list-marker" ] [ text (String.left markerEnd trimmed) ]
            , highlightInline (String.dropLeft markerEnd trimmed)
            ]

    else if String.startsWith "---" trimmed || String.startsWith "***" trimmed || String.startsWith "___" trimmed then
        span [ class "md-hr" ] [ text line ]

    else
        highlightInline line


isOrderedListItem : String -> Bool
isOrderedListItem line =
    case String.toInt (String.left 1 line) of
        Just _ ->
            String.contains ". " (String.left 5 line)

        Nothing ->
            False


highlightInline : String -> Html msg
highlightInline line =
    -- Highlight inline elements: bold, italic, links, code spans
    let
        parts =
            parseInline line []
    in
    span [] parts


parseInline : String -> List (Html msg) -> List (Html msg)
parseInline remaining acc =
    if String.isEmpty remaining then
        List.reverse acc

    else if String.startsWith "**" remaining then
        case findClosing "**" (String.dropLeft 2 remaining) of
            Just ( inner, rest ) ->
                parseInline rest
                    (span [ class "md-bold-marker" ] [ text ("**" ++ inner ++ "**") ] :: acc)

            Nothing ->
                parseInline (String.dropLeft 2 remaining) (text "**" :: acc)

    else if String.startsWith "*" remaining then
        case findClosing "*" (String.dropLeft 1 remaining) of
            Just ( inner, rest ) ->
                parseInline rest
                    (span [ class "md-italic-marker" ] [ text ("*" ++ inner ++ "*") ] :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (text "*" :: acc)

    else if String.startsWith "`" remaining then
        case findClosing "`" (String.dropLeft 1 remaining) of
            Just ( inner, rest ) ->
                parseInline rest
                    (span [ class "md-code-span" ] [ text ("`" ++ inner ++ "`") ] :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (text "`" :: acc)

    else if String.startsWith "[" remaining then
        case parseLinkMarkdown (String.dropLeft 1 remaining) of
            Just ( linkText, url, rest ) ->
                parseInline rest
                    (span [ class "md-link" ] [ text ("[" ++ linkText ++ "](" ++ url ++ ")") ] :: acc)

            Nothing ->
                parseInline (String.dropLeft 1 remaining) (text "[" :: acc)

    else
        let
            nextSpecial =
                findNextSpecial remaining

            ( plain, rest ) =
                case nextSpecial of
                    0 ->
                        ( String.left 1 remaining, String.dropLeft 1 remaining )

                    n ->
                        ( String.left n remaining, String.dropLeft n remaining )
        in
        parseInline rest (text plain :: acc)


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
