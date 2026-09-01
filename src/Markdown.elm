module Markdown exposing (Cache, OutlineEntry, emptyCache, parse, parseCached, selfCloseVoidTags, splitChunks)

import Dict exposing (Dict)
import Frontmatter
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Lazy
import Markdown.Block as Block
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer exposing (Renderer)
import Parser
import Regex
import SyntaxHighlight
import Yaml


{-| A single heading in the document outline. `id` matches the anchor `id`
emitted on the rendered heading element, so it can be used to scroll to it.
-}
type alias OutlineEntry =
    { level : Int, text : String, id : String }


{-| Parsed blocks keyed by the exact source text of a top-level chunk, so
that re-parsing after an edit only touches the chunk that changed.
-}
type alias Cache =
    Dict String (List Block.Block)


emptyCache : Cache
emptyCache =
    Dict.empty


parse : String -> { frontmatter : Maybe Yaml.Value, html : List (Html msg), outline : List OutlineEntry }
parse input =
    Tuple.second (parseCached emptyCache input)


parseCached : Cache -> String -> ( Cache, { frontmatter : Maybe Yaml.Value, html : List (Html msg), outline : List OutlineEntry } )
parseCached cache input =
    let
        { frontmatter, body } =
            Frontmatter.extract input

        chunks =
            splitChunks body

        parsedChunks =
            List.map
                (\chunk ->
                    case Dict.get chunk cache of
                        Just cached ->
                            Ok cached

                        Nothing ->
                            parseChunk chunk
                )
                chunks

        -- A chunk that fails on its own (e.g. an HTML element split across a
        -- boundary) means the split was unsafe: fall back to one full parse.
        ( newCache, blocks ) =
            case List.foldr (Result.map2 (++)) (Ok []) parsedChunks of
                Ok all ->
                    ( List.map2 Tuple.pair chunks parsedChunks
                        |> List.filterMap (\( chunk, r ) -> Result.toMaybe r |> Maybe.map (Tuple.pair chunk))
                        |> Dict.fromList
                    , all
                    )

                Err _ ->
                    ( emptyCache, parseChunk body |> Result.withDefault [] )

        ids =
            headingIds blocks

        -- Render block by block so each heading's renderer can close over its
        -- unique id (elm-markdown's heading callback has no position info).
        html =
            List.map2
                (\block headingId ->
                    Markdown.Renderer.render { customRenderer | heading = renderHeading headingId } [ block ]
                )
                blocks
                ids
                |> List.foldr (Result.map2 (++)) (Ok [])
                |> Result.withDefault [ pre [] [ text body ] ]
    in
    ( newCache, { frontmatter = frontmatter, html = html, outline = extractOutline blocks ids } )


parseChunk chunk =
    chunk
        |> escapeHtmlAmpersands
        |> selfCloseVoidTags
        |> Markdown.Parser.parse



-- CHUNKING


{-| Split markdown at hard top-level block boundaries: an ATX heading at
column 0, preceded by a blank line, outside any fenced code block. Each chunk
then parses independently and identically to parsing the whole document.

Documents that use link reference definitions or HTML blocks are never split,
since those can legitimately span such boundaries.
-}
splitChunks : String -> List String
splitChunks source =
    if Regex.contains unsplittable source then
        [ source ]

    else
        let
            step line state =
                let
                    fence =
                        fenceOf line
                in
                case state.openFence of
                    Just ( char, len ) ->
                        { state
                            | current = line :: state.current
                            , prevBlank = False
                            , openFence =
                                case fence of
                                    Just ( c, l ) ->
                                        if c == char && l >= len && String.trim line == String.repeat l (String.fromChar c) then
                                            Nothing

                                        else
                                            state.openFence

                                    Nothing ->
                                        state.openFence
                        }

                    Nothing ->
                        if state.prevBlank && Regex.contains atxHeading line && not (List.isEmpty state.current) then
                            let
                                -- Blank lines go with the next chunk: a chunk that
                                -- ends in blank lines can parse differently (e.g.
                                -- an indented code block keeps them at end of input).
                                ( blanks, body ) =
                                    splitWhile (String.trim >> String.isEmpty) state.current
                            in
                            { state
                                | done = String.join "\n" (List.reverse body) :: state.done
                                , current = line :: blanks
                                , prevBlank = False
                                , openFence = fence
                            }

                        else
                            { state
                                | current = line :: state.current
                                , prevBlank = String.isEmpty (String.trim line)
                                , openFence = fence
                            }

            final =
                List.foldl step { done = [], current = [], prevBlank = True, openFence = Nothing } (String.split "\n" source)
        in
        List.reverse (String.join "\n" (List.reverse final.current) :: final.done)


splitWhile : (a -> Bool) -> List a -> ( List a, List a )
splitWhile pred items =
    case items of
        x :: rest ->
            if pred x then
                Tuple.mapFirst ((::) x) (splitWhile pred rest)

            else
                ( [], items )

        [] ->
            ( [], [] )


{-| Opening fence marker (char, length) if this line starts one.
-}
fenceOf : String -> Maybe ( Char, Int )
fenceOf line =
    let
        trimmed =
            String.trimLeft line

        indent =
            String.length line - String.length trimmed

        runOf c =
            String.length trimmed - String.length (dropLeadingChar c trimmed)
    in
    if indent > 3 then
        Nothing

    else if String.startsWith "```" trimmed then
        Just ( '`', runOf '`' )

    else if String.startsWith "~~~" trimmed then
        Just ( '~', runOf '~' )

    else
        Nothing


dropLeadingChar : Char -> String -> String
dropLeadingChar c str =
    case String.uncons str of
        Just ( head, rest ) ->
            if head == c then
                dropLeadingChar c rest

            else
                str

        Nothing ->
            str


atxHeading : Regex.Regex
atxHeading =
    Regex.fromString "^#{1,6}(\\s|$)" |> Maybe.withDefault Regex.never


unsplittable : Regex.Regex
unsplittable =
    Regex.fromStringWith { caseInsensitive = False, multiline = True } "^ {0,3}(<[a-zA-Z!/?]|\\[[^\\]]*\\]:)"
        |> Maybe.withDefault Regex.never


{-| One anchor id per top-level block ("" for non-headings). Repeated heading
text gets a `-1`, `-2`, ... suffix (GitHub style) so ids stay unique and the
outline can scroll to the second "Overview" instead of always the first.
-}
headingIds : List Block.Block -> List String
headingIds blocks =
    blocks
        |> List.foldl
            (\block ( seen, acc ) ->
                case block of
                    Block.Heading _ inlines ->
                        let
                            base =
                                anchorId (Block.extractInlineText inlines)

                            count =
                                Dict.get base seen |> Maybe.withDefault 0

                            unique =
                                if count == 0 then
                                    base

                                else
                                    base ++ "-" ++ String.fromInt count
                        in
                        ( Dict.insert base (count + 1) seen, unique :: acc )

                    _ ->
                        ( seen, "" :: acc )
            )
            ( Dict.empty, [] )
        |> Tuple.second
        |> List.reverse


{-| Walk the parsed block AST and collect every heading into an outline.
-}
extractOutline : List Block.Block -> List String -> List OutlineEntry
extractOutline blocks ids =
    List.map2
        (\block headingId ->
            case block of
                Block.Heading level inlines ->
                    Just
                        { level = Block.headingLevelToInt level
                        , text = Block.extractInlineText inlines
                        , id = headingId
                        }

                _ ->
                    Nothing
        )
        blocks
        ids
        |> List.filterMap identity


{-| Derive an anchor `id` from heading text.
-}
anchorId : String -> String
anchorId rawText =
    rawText
        |> String.toLower
        |> String.replace " " "-"
        |> String.filter (\c -> Char.isAlphaNum c || c == '-')


{-| Escape bare `&` in HTML attribute values that aren't already entities.
The elm-markdown parser is strict about HTML entities, but many markdown
files (especially GitHub READMEs) use raw `&` in URLs within HTML tags.
-}
escapeHtmlAmpersands : String -> String
escapeHtmlAmpersands =
    Regex.replace bareAmpInTag (\_ -> "&amp;")


bareAmpInTag : Regex.Regex
bareAmpInTag =
    Regex.fromString "&(?!#?[a-zA-Z0-9]+;)(?=[^<>]*>)"
        |> Maybe.withDefault Regex.never


{-| Self-close HTML void elements (`<img ...>` -> `<img ... />`).
elm-markdown's HTML parser has no notion of void elements, so an unclosed
`<img>` inside a `<div>` fails with "tag name mismatch" and the whole
document renders blank. Common in GitHub READMEs with centered logos.
-}
selfCloseVoidTags : String -> String
selfCloseVoidTags =
    -- ponytail: also rewrites inside code spans/fences (same as escapeHtmlAmpersands);
    -- skip fenced blocks if that ever matters.
    Regex.replace voidTag
        (\m ->
            case m.submatches of
                [ Just tag, attrs ] ->
                    "<" ++ tag ++ String.trimRight (Maybe.withDefault "" attrs) ++ " />"

                _ ->
                    m.match
        )


voidTag : Regex.Regex
voidTag =
    Regex.fromString "<(img|br|hr|wbr|input)((?:\\s[^<>]*?)?)\\s*/?>"
        |> Maybe.withDefault Regex.never


customRenderer : Renderer (Html msg)
customRenderer =
    { heading = renderHeading ""
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


renderHeading : String -> { level : Block.HeadingLevel, rawText : String, children : List (Html msg) } -> Html msg
renderHeading headingId { level, children } =
    let
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
    tag [ id headingId ] children


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
            -- lazy: highlighting is the most expensive part of a re-parse, and
            -- Html.Lazy compares strings by value, so unchanged code blocks
            -- skip both the highlighter and the virtual-DOM diff.
            Html.Lazy.lazy2 renderHighlightedCodeBlock body (Maybe.withDefault "" language)


type alias Highlighter =
    String -> Result (List Parser.DeadEnd) SyntaxHighlight.HCode


{-| Fenced-code language -> highlighter. Aliases reuse a lexically-close
parser: structure (strings, comments, numbers, brackets) highlights well;
keyword coverage is partial where the languages' vocab differs.
-}
highlighters : Dict String Highlighter
highlighters =
    [ ( [ "elm" ], SyntaxHighlight.elm )
    , ( [ "javascript", "js", "jsx", "mdx" ], SyntaxHighlight.javascript )
    , ( [ "typescript", "ts", "tsx" ], SyntaxHighlight.typescript )
    , ( [ "python", "py" ], SyntaxHighlight.python )
    , ( [ "css", "scss", "less" ], SyntaxHighlight.css )
    , ( [ "json", "jsonc", "json5" ], SyntaxHighlight.json )
    , ( [ "sql" ], SyntaxHighlight.sql )
    , ( [ "xml", "html", "vue" ], SyntaxHighlight.xml )
    , ( [ "go", "golang" ], SyntaxHighlight.go )
    , ( [ "kotlin", "c", "cpp", "c++", "java", "scala", "swift", "groovy" ], SyntaxHighlight.kotlin )
    , ( [ "nix" ], SyntaxHighlight.nix )
    , ( [ "rust", "rs" ], SyntaxHighlight.rust )
    , ( [ "php" ], SyntaxHighlight.php )
    , ( [ "dart" ], SyntaxHighlight.dart )
    , ( [ "fsharp", "fs", "fsx", "ocaml", "ml" ], SyntaxHighlight.fsharp )
    ]
        |> List.concatMap (\( names, fn ) -> List.map (\name -> ( name, fn )) names)
        |> Dict.fromList


renderHighlightedCodeBlock : String -> String -> Html msg
renderHighlightedCodeBlock body languageName =
    let
        language =
            if String.isEmpty languageName then
                Nothing

            else
                Just languageName
    in
    case Dict.get (String.toLower languageName) highlighters of
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
