module Markdown exposing (parse)

import Frontmatter
import Html exposing (..)
import Html.Attributes exposing (..)
import Markdown.Block as Block
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer exposing (Renderer)
import SyntaxHighlight
import Yaml


parse : String -> { frontmatter : Maybe Yaml.Value, html : List (Html msg) }
parse input =
    let
        { frontmatter, body } =
            Frontmatter.extract input

        html =
            renderMarkdown body
    in
    { frontmatter = frontmatter, html = html }


renderMarkdown : String -> List (Html msg)
renderMarkdown input =
    case
        input
            |> Markdown.Parser.parse
            |> Result.mapError (\_ -> "Parse error")
            |> Result.andThen (Markdown.Renderer.render customRenderer)
    of
        Ok rendered ->
            rendered

        Err _ ->
            [ pre [] [ text input ] ]


customRenderer : Renderer (Html msg)
customRenderer =
    { heading = renderHeading
    , paragraph = p []
    , blockQuote = blockquote [ class "md-blockquote" ]
    , html = Markdown.Html.oneOf []
    , text = text
    , codeSpan = \content -> code [ class "md-code-span" ] [ text content ]
    , strong = \children -> strong [] children
    , emphasis = \children -> em [] children
    , strikethrough = \children -> del [] children
    , hardLineBreak = br [] []
    , link = renderLink
    , image = renderImage
    , unorderedList = renderUnorderedList
    , orderedList = renderOrderedList
    , codeBlock = renderCodeBlock
    , thematicBreak = hr [ class "md-hr" ] []
    , table = table [ class "md-table" ]
    , tableHeader = thead []
    , tableBody = tbody []
    , tableRow = tr []
    , tableCell = renderTableCell td
    , tableHeaderCell = renderTableCell th
    }


renderHeading : { level : Block.HeadingLevel, rawText : String, children : List (Html msg) } -> Html msg
renderHeading { level, rawText, children } =
    let
        anchorId =
            rawText
                |> String.toLower
                |> String.replace " " "-"
                |> String.filter (\c -> Char.isAlphaNum c || c == '-')

        tag =
            case level of
                Block.H1 ->
                    h1

                Block.H2 ->
                    h2

                Block.H3 ->
                    h3

                Block.H4 ->
                    h4

                Block.H5 ->
                    h5

                Block.H6 ->
                    h6
    in
    tag [ id anchorId ] children


renderLink : { title : Maybe String, destination : String } -> List (Html msg) -> Html msg
renderLink link children =
    case link.title of
        Just title_ ->
            a [ href link.destination, title title_ ] children

        Nothing ->
            a [ href link.destination ] children


renderImage : { alt : String, src : String, title : Maybe String } -> Html msg
renderImage imageInfo =
    case imageInfo.title of
        Just title_ ->
            img [ src imageInfo.src, alt imageInfo.alt, title title_ ] []

        Nothing ->
            img [ src imageInfo.src, alt imageInfo.alt ] []


renderUnorderedList : List (Block.ListItem (Html msg)) -> Html msg
renderUnorderedList items =
    ul []
        (items
            |> List.map
                (\(Block.ListItem task children) ->
                    let
                        checkbox =
                            case task of
                                Block.NoTask ->
                                    text ""

                                Block.IncompleteTask ->
                                    input
                                        [ type_ "checkbox"
                                        , disabled True
                                        , checked False
                                        , class "md-task-checkbox"
                                        ]
                                        []

                                Block.CompletedTask ->
                                    input
                                        [ type_ "checkbox"
                                        , disabled True
                                        , checked True
                                        , class "md-task-checkbox"
                                        ]
                                        []

                        taskClass =
                            case task of
                                Block.NoTask ->
                                    []

                                _ ->
                                    [ class "md-task-item" ]
                    in
                    li taskClass (checkbox :: children)
                )
        )


renderOrderedList : Int -> List (List (Html msg)) -> Html msg
renderOrderedList startIndex items =
    ol
        (if startIndex /= 1 then
            [ start startIndex ]
         else
            []
        )
        (List.map (\itemBlocks -> li [] itemBlocks) items)


renderCodeBlock : { body : String, language : Maybe String } -> Html msg
renderCodeBlock { body, language } =
    let
        highlighter =
            case Maybe.map String.toLower language of
                Just "elm" ->
                    Just SyntaxHighlight.elm

                Just "javascript" ->
                    Just SyntaxHighlight.javascript

                Just "js" ->
                    Just SyntaxHighlight.javascript

                Just "python" ->
                    Just SyntaxHighlight.python

                Just "py" ->
                    Just SyntaxHighlight.python

                Just "css" ->
                    Just SyntaxHighlight.css

                Just "json" ->
                    Just SyntaxHighlight.json

                Just "sql" ->
                    Just SyntaxHighlight.sql

                Just "xml" ->
                    Just SyntaxHighlight.xml

                Just "html" ->
                    Just SyntaxHighlight.xml

                Just "go" ->
                    Just SyntaxHighlight.go

                Just "kotlin" ->
                    Just SyntaxHighlight.kotlin

                Just "nix" ->
                    Just SyntaxHighlight.nix

                Just "rust" ->
                    Just SyntaxHighlight.rust

                Just "rs" ->
                    Just SyntaxHighlight.rust

                Just "php" ->
                    Just SyntaxHighlight.php

                Just "typescript" ->
                    Just SyntaxHighlight.typescript

                Just "ts" ->
                    Just SyntaxHighlight.typescript

                Just "tsx" ->
                    Just SyntaxHighlight.typescript

                Just "jsx" ->
                    Just SyntaxHighlight.javascript

                Just "dart" ->
                    Just SyntaxHighlight.dart

                Just "vue" ->
                    Just SyntaxHighlight.xml

                Just "mdx" ->
                    Just SyntaxHighlight.javascript

                Just "golang" ->
                    Just SyntaxHighlight.go

                _ ->
                    Nothing
    in
    case highlighter of
        Just highlight ->
            case highlight body of
                Ok hcode ->
                    div [ class "md-code-block" ]
                        [ SyntaxHighlight.toBlockHtml Nothing hcode ]

                Err _ ->
                    plainCodeBlock language body

        Nothing ->
            plainCodeBlock language body


plainCodeBlock : Maybe String -> String -> Html msg
plainCodeBlock language body =
    let
        langClass =
            case language of
                Just lang ->
                    [ class ("language-" ++ lang) ]

                Nothing ->
                    []
    in
    pre [ class "md-code-block" ]
        [ code langClass [ text body ] ]


renderTableCell : (List (Attribute msg) -> List (Html msg) -> Html msg) -> Maybe Block.Alignment -> List (Html msg) -> Html msg
renderTableCell element maybeAlignment children =
    let
        attrs =
            case maybeAlignment of
                Just Block.AlignLeft ->
                    [ style "text-align" "left" ]

                Just Block.AlignCenter ->
                    [ style "text-align" "center" ]

                Just Block.AlignRight ->
                    [ style "text-align" "right" ]

                Nothing ->
                    []
    in
    element attrs children
