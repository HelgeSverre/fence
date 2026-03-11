module Editor exposing
    ( Model
    , Msg(..)
    , init
    , update
    , view
    , setContent
    , markClean
    )

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as D
import Types exposing (..)


type alias Model =
    { content : String
    , filePath : Maybe FilePath
    , dirtyState : DirtyState
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
    , scrollTop = 0
    }


setContent : FilePath -> String -> Model -> Model
setContent path content model =
    { model
        | content = content
        , filePath = Just path
        , dirtyState = Clean
        , scrollTop = 0
    }


markClean : Model -> Model
markClean model =
    { model | dirtyState = Clean }


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
    content
        |> String.split "\n"
        |> List.map highlightLine
        |> List.intersperse (text "\n")


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
    let
        delimLen =
            String.length delimiter
    in
    findClosingHelper delimiter delimLen str 0


findClosingHelper : String -> Int -> String -> Int -> Maybe ( String, String )
findClosingHelper delimiter delimLen str pos =
    if pos >= String.length str then
        Nothing
    else if String.slice pos (pos + delimLen) str == delimiter then
        Just
            ( String.left pos str
            , String.dropLeft (pos + delimLen) str
            )
    else
        findClosingHelper delimiter delimLen str (pos + 1)


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


baseName : String -> String
baseName path =
    path
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path
