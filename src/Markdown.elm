module Markdown exposing (parse)

import Frontmatter
import Html exposing (..)
import Html.Attributes exposing (..)
import Markdown.Block as Block
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer exposing (Renderer)
import Regex
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
            |> escapeHtmlAmpersands
            |> Markdown.Parser.parse
            |> Result.mapError (\_ -> "Parse error")
            |> Result.andThen (Markdown.Renderer.render customRenderer)
    of
        Ok rendered ->
            rendered

        Err _ ->
            [ pre [] [ text input ] ]


{-| Escape bare `&` in HTML attribute values that aren't already entities.
The elm-markdown parser is strict about HTML entities, but many markdown
files (especially GitHub READMEs) use raw `&` in URLs within HTML tags.
-}
escapeHtmlAmpersands : String -> String
escapeHtmlAmpersands input =
    case Regex.fromString "&(?!#?[a-zA-Z0-9]+;)(?=[^<>]*>)" of
        Just bareAmpInTag ->
            Regex.replace bareAmpInTag (\_ -> "&amp;") input

        Nothing ->
            input


customRenderer : Renderer (Html msg)
customRenderer =
    { heading = renderHeading
    , paragraph = p []
    , blockQuote = blockquote [ class "md-blockquote" ]
    , html =
        Markdown.Html.oneOf
            [ -- Block elements with align attribute
              htmlTagWithAlign "p" Html.p
            , htmlTagWithAlign "h1" h1
            , htmlTagWithAlign "h2" h2
            , htmlTagWithAlign "h3" h3
            , htmlTagWithAlign "h4" h4
            , htmlTagWithAlign "h5" h5
            , htmlTagWithAlign "h6" h6
            , htmlTagWithAlign "div" div

            -- Container with class
            , htmlTagWithClass "span" span
            , htmlTagWithClass "section" (Html.node "section")

            -- Images
            , Markdown.Html.tag "img"
                (\srcAttr altAttr widthAttr heightAttr _ ->
                    img
                        (List.filterMap identity
                            [ Maybe.map src srcAttr
                            , Maybe.map alt altAttr
                            , Maybe.map (\w -> attribute "width" w) widthAttr
                            , Maybe.map (\h -> attribute "height" h) heightAttr
                            ]
                        )
                        []
                )
                |> Markdown.Html.withOptionalAttribute "src"
                |> Markdown.Html.withOptionalAttribute "alt"
                |> Markdown.Html.withOptionalAttribute "width"
                |> Markdown.Html.withOptionalAttribute "height"

            -- Links
            , Markdown.Html.tag "a"
                (\hrefAttr titleAttr children ->
                    a
                        (List.filterMap identity
                            [ Maybe.map href hrefAttr
                            , Maybe.map title titleAttr
                            ]
                        )
                        children
                )
                |> Markdown.Html.withOptionalAttribute "href"
                |> Markdown.Html.withOptionalAttribute "title"

            -- Void elements
            , Markdown.Html.tag "br" (\_ -> br [] [])
            , Markdown.Html.tag "hr" (\_ -> hr [] [])
            , Markdown.Html.tag "wbr" (\_ -> Html.node "wbr" [] [])

            -- Collapsible sections
            , Markdown.Html.tag "details"
                (\openAttr children ->
                    details
                        (case openAttr of
                            Just _ ->
                                [ attribute "open" "" ]

                            Nothing ->
                                []
                        )
                        children
                )
                |> Markdown.Html.withOptionalAttribute "open"
            , Markdown.Html.tag "summary"
                (\children -> summary [] children)

            -- Inline formatting
            , simpleHtmlTag "strong" (strong [])
            , simpleHtmlTag "b" (Html.node "b" [])
            , simpleHtmlTag "em" (em [])
            , simpleHtmlTag "i" (Html.node "i" [])
            , simpleHtmlTag "del" (del [])
            , simpleHtmlTag "s" (Html.node "s" [])
            , simpleHtmlTag "strike" (Html.node "s" [])
            , simpleHtmlTag "u" (Html.node "u" [])
            , simpleHtmlTag "ins" (Html.node "ins" [])
            , simpleHtmlTag "small" (Html.node "small" [])
            , simpleHtmlTag "sup" (sup [])
            , simpleHtmlTag "sub" (sub [])
            , simpleHtmlTag "kbd" (Html.node "kbd" [])
            , simpleHtmlTag "mark" (Html.node "mark" [])
            , simpleHtmlTag "abbr" (Html.node "abbr" [])
            , simpleHtmlTag "cite" (Html.node "cite" [])
            , simpleHtmlTag "q" (Html.node "q" [])

            -- Lists (raw HTML)
            , simpleHtmlTag "ul" (ul [])
            , simpleHtmlTag "ol" (ol [])
            , simpleHtmlTag "li" (li [])

            -- Tables (raw HTML)
            , simpleHtmlTag "table" (table [ class "md-table" ])
            , simpleHtmlTag "thead" (thead [])
            , simpleHtmlTag "tbody" (tbody [])
            , simpleHtmlTag "tr" (tr [])
            , simpleHtmlTag "th" (th [])
            , simpleHtmlTag "td" (td [])

            -- Definition lists
            , simpleHtmlTag "dl" (Html.node "dl" [])
            , simpleHtmlTag "dt" (Html.node "dt" [])
            , simpleHtmlTag "dd" (Html.node "dd" [])

            -- Semantic / structural
            , simpleHtmlTag "blockquote" (blockquote [ class "md-blockquote" ])
            , simpleHtmlTag "figure" (Html.node "figure" [])
            , simpleHtmlTag "figcaption" (Html.node "figcaption" [])
            , simpleHtmlTag "aside" (Html.node "aside" [])
            , simpleHtmlTag "nav" (Html.node "nav" [])
            , simpleHtmlTag "header" (Html.node "header" [])
            , simpleHtmlTag "footer" (Html.node "footer" [])

            -- Preformatted / code (raw HTML)
            , simpleHtmlTag "pre" (pre [ class "md-code-block" ])
            , simpleHtmlTag "code" (code [])
            ]
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
    case Maybe.map String.toLower language of
        Just "mermaid" ->
            Html.pre [ class "mermaid" ] [ text body ]

        _ ->
            renderHighlightedCodeBlock body language


renderHighlightedCodeBlock : String -> Maybe String -> Html msg
renderHighlightedCodeBlock body language =
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

                Just "fsharp" ->
                    Just SyntaxHighlight.fsharp

                Just "fs" ->
                    Just SyntaxHighlight.fsharp

                Just "fsx" ->
                    Just SyntaxHighlight.fsharp

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



-- HTML tag handler helpers


{-| Simple pass-through handler for an HTML tag with no special attributes.
-}
simpleHtmlTag : String -> (List (Html msg) -> Html msg) -> Markdown.Html.Renderer (List (Html msg) -> Html msg)
simpleHtmlTag tagName viewFn =
    Markdown.Html.tag tagName (\children -> viewFn children)


{-| Handler for block elements that support an optional `align` attribute.
-}
htmlTagWithAlign : String -> (List (Attribute msg) -> List (Html msg) -> Html msg) -> Markdown.Html.Renderer (List (Html msg) -> Html msg)
htmlTagWithAlign tagName viewFn =
    Markdown.Html.tag tagName
        (\align children ->
            viewFn
                (case align of
                    Just a ->
                        [ attribute "align" a ]

                    Nothing ->
                        []
                )
                children
        )
        |> Markdown.Html.withOptionalAttribute "align"


{-| Handler for elements that support an optional `class` attribute.
-}
htmlTagWithClass : String -> (List (Attribute msg) -> List (Html msg) -> Html msg) -> Markdown.Html.Renderer (List (Html msg) -> Html msg)
htmlTagWithClass tagName viewFn =
    Markdown.Html.tag tagName
        (\classAttr children ->
            viewFn
                (case classAttr of
                    Just c ->
                        [ class c ]

                    Nothing ->
                        []
                )
                children
        )
        |> Markdown.Html.withOptionalAttribute "class"
