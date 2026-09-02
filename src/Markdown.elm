module Markdown exposing
    ( Cache
    , OutlineEntry
    , Progress
    , begin
    , cache
    , emptyCache
    , htmlChunks
    , isComplete
    , outline
    , parse
    , parseCached
    , selfCloseVoidTags
    , splitChunks
    , step
    )

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


{-| Per-chunk cache keyed by the exact source text of a top-level chunk.
Holds the parsed blocks and, once rendered, the HTML together with the
heading ids it was rendered with, so an unchanged chunk costs nothing to
re-parse and keeps the same `Html` value (which lets `Html.Lazy` skip it).
-}
type alias Cache msg =
    Dict String (Entry msg)


type alias Entry msg =
    { blocks : List Block.Block
    , rendered : Maybe { ids : List String, html : List (Html msg), outline : List OutlineEntry }
    }


emptyCache : Cache msg
emptyCache =
    Dict.empty


{-| A document being parsed chunk by chunk. `begin` splits it, `step` parses
and renders the next chunks within a character budget, so a large document
can paint its first screen at once and fill in over a few animation frames.
-}
type Progress msg
    = Progress
        { pending : List String
        , body : String
        , lookup : Cache msg
        , built : Cache msg
        , seen : Dict String Int
        , chunksRev : List (List (Html msg))
        , outlineRev : List OutlineEntry
        }


begin : Cache msg -> String -> ( Progress msg, Maybe Yaml.Value )
begin previous input =
    let
        { frontmatter, body } =
            Frontmatter.extract input
    in
    ( Progress
        { pending = splitChunks body
        , body = body
        , lookup = previous
        , built = emptyCache
        , seen = Dict.empty
        , chunksRev = []
        , outlineRev = []
        }
    , frontmatter
    )


isComplete : Progress msg -> Bool
isComplete (Progress p) =
    List.isEmpty p.pending


{-| Rendered chunks so far, in document order. Each inner list keeps its
identity across steps and edits unless its chunk changed.
-}
htmlChunks : Progress msg -> List (List (Html msg))
htmlChunks (Progress p) =
    List.reverse p.chunksRev


outline : Progress msg -> List OutlineEntry
outline (Progress p) =
    List.reverse p.outlineRev


cache : Progress msg -> Cache msg
cache (Progress p) =
    p.built


{-| Parse and render pending chunks until roughly `budget` characters of
*uncached* source have been processed (cached chunks are nearly free, so a
small edit to a large document still finishes in a single step). Always
makes progress on at least one chunk.
-}
step : Int -> Progress msg -> Progress msg
step budget (Progress p) =
    case p.pending of
        [] ->
            Progress p

        chunk :: rest ->
            let
                cached =
                    Dict.get chunk p.lookup

                cost =
                    case cached of
                        Just _ ->
                            0

                        Nothing ->
                            String.length chunk

                parsed =
                    case cached of
                        Just entry ->
                            Ok entry

                        Nothing ->
                            parseChunk chunk |> Result.map (\blocks -> { blocks = blocks, rendered = Nothing })
            in
            case parsed of
                Err _ ->
                    -- A chunk that fails on its own (e.g. an HTML element split
                    -- across a boundary) means the split was unsafe: fall back
                    -- to rendering the whole document as a single chunk.
                    wholeDocument (Progress p)

                Ok entry ->
                    let
                        ( seen, ids ) =
                            assignIds p.seen entry.blocks

                        rendered =
                            case entry.rendered of
                                Just r ->
                                    if r.ids == ids then
                                        r

                                    else
                                        renderChunk chunk entry.blocks ids

                                Nothing ->
                                    renderChunk chunk entry.blocks ids

                        next =
                            Progress
                                { p
                                    | pending = rest
                                    , built = Dict.insert chunk { entry | rendered = Just rendered } p.built
                                    , seen = seen
                                    , chunksRev = rendered.html :: p.chunksRev
                                    , outlineRev = List.reverse rendered.outline ++ p.outlineRev
                                }
                    in
                    if budget - cost > 0 && not (List.isEmpty rest) then
                        step (budget - cost) next

                    else
                        next


wholeDocument : Progress msg -> Progress msg
wholeDocument (Progress p) =
    let
        blocks =
            parseChunk p.body |> Result.withDefault []

        ( _, ids ) =
            assignIds Dict.empty blocks

        rendered =
            renderChunk p.body blocks ids
    in
    Progress
        { p
            | pending = []
            , built = emptyCache
            , chunksRev = [ rendered.html ]
            , outlineRev = List.reverse rendered.outline
        }


renderChunk : String -> List Block.Block -> List String -> { ids : List String, html : List (Html msg), outline : List OutlineEntry }
renderChunk source blocks ids =
    { ids = ids
    , html =
        -- Render block by block so each heading's renderer can close over its
        -- unique id (elm-markdown's heading callback has no position info).
        List.map2
            (\block headingId ->
                Markdown.Renderer.render { customRenderer | heading = renderHeading headingId } [ block ]
            )
            blocks
            ids
            |> List.foldr (Result.map2 (++)) (Ok [])
            |> Result.withDefault [ pre [] [ text source ] ]
    , outline = extractOutline blocks ids
    }


{-| Whole-document convenience used by tests and small documents: run steps
to completion and flatten the chunks.
-}
parse : String -> { frontmatter : Maybe Yaml.Value, html : List (Html msg), outline : List OutlineEntry }
parse input =
    Tuple.second (parseCached emptyCache input)


parseCached : Cache msg -> String -> ( Cache msg, { frontmatter : Maybe Yaml.Value, html : List (Html msg), outline : List OutlineEntry } )
parseCached previous input =
    let
        ( progress, frontmatter ) =
            begin previous input

        finished =
            runToEnd progress
    in
    ( cache finished, { frontmatter = frontmatter, html = List.concat (htmlChunks finished), outline = outline finished } )


runToEnd : Progress msg -> Progress msg
runToEnd progress =
    if isComplete progress then
        progress

    else
        runToEnd (step 1000000 progress)


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
            splitLine line state =
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
                                | done =
                                    -- only blank lines so far: nothing to emit yet
                                    if List.isEmpty body then
                                        state.done

                                    else
                                        String.join "\n" (List.reverse body) :: state.done
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
                List.foldl splitLine { done = [], current = [], prevBlank = True, openFence = Nothing } (String.split "\n" source)
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


{-| One anchor id per block ("" for non-headings), continuing from the
heading counts seen so far. Repeated heading text gets a `-1`, `-2`, ...
suffix (GitHub style) so ids stay unique across the whole document.
-}
assignIds : Dict String Int -> List Block.Block -> ( Dict String Int, List String )
assignIds seen0 blocks =
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
            ( seen0, [] )
        |> Tuple.mapSecond List.reverse


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
