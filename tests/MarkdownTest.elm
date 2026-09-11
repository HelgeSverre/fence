module MarkdownTest exposing (suite)

import Expect
import Dict
import Markdown
import Markdown.Block as Block
import Markdown.Parser
import Html
import Html.Attributes
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "Markdown" [ selfCloseSuite, headingIdSuite, chunkSuite, renderSuite, progressSuite, headingLineSuite, fencedSourceSuite ]


headingLineSuite : Test
headingLineSuite =
    describe "heading source lines"
        [ test "reports the line of every heading, counting from zero" <|
            \_ -> Markdown.headingLines "# One\n\ntext\n\n## Two\n" |> Expect.equal [ 0, 4 ]
        , test "headings inside fenced code are not headings" <|
            \_ -> Markdown.headingLines "# One\n\n```\n# not a heading\n```\n\n## Two\n" |> Expect.equal [ 0, 6 ]
        , test "frontmatter shifts the lines it reports" <|
            \_ -> Markdown.headingLines "---\ntitle: x\n---\n# One\n\n## Two\n" |> Expect.equal [ 3, 5 ]
        , test "a document with no headings has no lines" <|
            \_ -> Markdown.headingLines "just text\n" |> Expect.equal []
        , test "the lines line up one-for-one with the outline" <|
            \_ ->
                let
                    source =
                        "---\nk: v\n---\n# One\n\n## Two\n\n```\n### fenced\n```\n\n### Three\n"
                in
                Expect.equal
                    (List.length (Markdown.parse source).outline)
                    (List.length (Markdown.headingLines source))
        ]


selfCloseSuite : Test
selfCloseSuite =
    describe "Markdown document parsing"
        [ test "extracts an ordered heading outline" <|
            \_ ->
                Markdown.parse "# Title\n\n## Details\n\nText"
                    |> .outline
                    |> Expect.equal
                        [ { level = 1, text = "Title", id = "title" }
                        , { level = 2, text = "Details", id = "details" }
                        ]
        , test "does not include frontmatter headings in the outline" <|
            \_ ->
                Markdown.parse "---\ntitle: '# Metadata'\n---\n# Body"
                    |> .outline
                    |> Expect.equal [ { level = 1, text = "Body", id = "body" } ]
        , test "normalizes heading anchors" <|
            \_ ->
                Markdown.parse "## Hello, Elm!"
                    |> .outline
                    |> Expect.equal [ { level = 2, text = "Hello, Elm!", id = "hello-elm" } ]
        ]


headingIdSuite : Test
headingIdSuite =
    describe "heading ids"
        [ test "repeated headings get unique, GitHub-style suffixes" <|
            \_ ->
                (Markdown.parse "# Added\n\ntext\n\n## Added\n\n# Fixed\n\n# Added\n").outline
                    |> List.map .id
                    |> Expect.equal [ "added", "added-1", "fixed", "added-2" ]
        ]



chunkSuite : Test
chunkSuite =
    let
        docs =
            [ ( "headings and fences with # inside", "# A\n\ntext\n\n```sh\n# not a heading\n```\n\n## B\n\n- list\n\n# C\n\n~~~\n# still code\n~~~\n\n# D\n" )
            , ( "longer closing fence rule", "# A\n\n````md\n```\n# inside\n```\n````\n\n# B\n" )
            , ( "heading without preceding blank stays in chunk", "# A\nline\n# B\n\n# C\n" )
            , ( "html block disables splitting", "<div align=\"center\">\n\n# Title\n\n</div>\n\n# Next\n" )
            , ( "reference links disable splitting", "# A\n\nsee [x]\n\n# B\n\n[x]: https://example.com\n" )
            , ( "no headings", "just\n\ntext\n" )
            ]
    in
    describe "chunked parsing"
        (List.map
            (\( name, doc ) ->
                test name <|
                    \_ ->
                        let
                            chunked =
                                Markdown.splitChunks doc
                                    |> List.map Markdown.Parser.parse
                                    |> List.foldr (Result.map2 (++)) (Ok [])
                        in
                        Expect.equal (Markdown.Parser.parse doc) chunked
            )
            docs
            ++ [ test "html doc is a single chunk" <|
                    \_ -> Markdown.splitChunks "<div>\n\n# T\n\n</div>" |> List.length |> Expect.equal 1
               , test "leading blank lines never produce an empty chunk" <|
                    \_ -> Markdown.splitChunks "\n\n# A\n\nx" |> Expect.equal [ "\n\n# A\n\nx" ]
               , test "splits at blank-line-preceded headings" <|
                    \_ -> Markdown.splitChunks "# A\n\nx\n\n# B\n\ny" |> Expect.equal [ "# A\n\nx", "\n# B\n\ny" ]
               , test "indented code before a heading: chunked drops trailing blanks (whole-doc elm-markdown keeps them)" <|
                    \_ ->
                        ( Markdown.splitChunks "# A\n\n    # code\n\n# B\n" |> List.map Markdown.Parser.parse |> List.foldr (Result.map2 (++)) (Ok [])
                        , Markdown.Parser.parse "# A\n\n    # code\n\n# B\n"
                        )
                            |> Expect.equal
                                ( Ok [ Block.Heading Block.H1 [ Block.Text "A" ], Block.CodeBlock { body = "# code", language = Nothing }, Block.Heading Block.H1 [ Block.Text "B" ] ]
                                , Ok [ Block.Heading Block.H1 [ Block.Text "A" ], Block.CodeBlock { body = "# code\n\n", language = Nothing }, Block.Heading Block.H1 [ Block.Text "B" ] ]
                                )
               , test "cache is reused and pruned" <|
                    \_ ->
                        let
                            ( c1, _ ) =
                                Markdown.parseCached Markdown.emptyCache "# A\n\nx\n\n# B\n\ny"

                            ( c2, r2 ) =
                                Markdown.parseCached c1 "# A\n\nx\n\n# B\n\nchanged"
                        in
                        Expect.all
                            [ \_ -> Dict.size c1 |> Expect.equal 2
                            , \_ -> Dict.member "# A\n\nx" c2 |> Expect.equal True
                            , \_ -> Dict.member "\n# B\n\ny" c2 |> Expect.equal False
                            , \_ -> List.map .text r2.outline |> Expect.equal [ "A", "B" ]
                            ]
                            ()
               ]
        )



renderSuite : Test
renderSuite =
    let
        render src =
            Query.fromHtml (Html.div [] (Markdown.parse src).html)
    in
    describe "rendered HTML"
        [ test "headings carry their anchor id" <|
            \_ -> render "## Hello World\n" |> Query.find [ Selector.tag "h2" ] |> Query.has [ Selector.id "hello-world" ]
        , test "fenced code with a known language is highlighted" <|
            \_ -> render "```js\nconst x = 1;\n```\n" |> Query.findAll [ Selector.class "md-code-block" ] |> Query.count (Expect.equal 1)
        , test "fenced code with an unknown language falls back to a plain block tagged with the language" <|
            \_ -> render "```brainfuck\n+++\n```\n" |> Query.find [ Selector.tag "code" ] |> Query.has [ Selector.class "language-brainfuck", Selector.text "+++" ]
        , test "mermaid fences supply source to the renderer" <|
            \_ -> render "```mermaid\ngraph TD\n```\n" |> Query.find [ Selector.class "mermaid" ] |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-source" "graph TD\n") ]
        , test "frontmatter is stripped from the rendered body and returned separately" <|
            \_ ->
                let
                    result =
                        Markdown.parse "---\ntitle: T\n---\n# Body\n"
                in
                Expect.all
                    [ \_ -> result.frontmatter |> Expect.notEqual Nothing
                    , \_ -> Query.fromHtml (Html.div [] result.html) |> Query.findAll [ Selector.tag "hr" ] |> Query.count (Expect.equal 0)
                    , \_ -> List.map .text result.outline |> Expect.equal [ "Body" ]
                    ]
                    ()
        , test "the outline records heading levels" <|
            \_ -> (Markdown.parse "# A\n\n### C\n\n## B\n").outline |> List.map .level |> Expect.equal [ 1, 3, 2 ]
        , test "a README with an unclosed <img> inside a <div> still renders" <|
            \_ -> render "<div align=\"center\">\n\n<img src=\"x.png\" alt=\"logo\">\n\n# Title\n\n</div>\n" |> Query.find [ Selector.tag "h1" ] |> Query.has [ Selector.text "Title" ]
        , test "a numeric comparison on a list continuation line renders as text" <|
            \_ ->
                render "# Performance\n\n1. A keystroke costs\n   <2ms of layout (trace).\n\n# Next\n"
                    |> Query.find [ Selector.tag "li" ]
                    |> Query.has [ Selector.text "<2ms of layout (trace)." ]
        , test "comparison recovery preserves headings and following sections" <|
            \_ ->
                (Markdown.parse "# Performance\n\n<2ms\n\n# Next\n").outline
                    |> List.map .text
                    |> Expect.equal [ "Performance", "Next" ]
        , test "comparison recovery leaves code contents intact" <|
            \_ ->
                let
                    result =
                        render "# Performance\n\n<2ms\n\n```text\n<3ms\n```\n\n~~~text\n<4ms\n~~~\n\n    <5ms\n\n`<6ms`\n"
                in
                Expect.all
                    [ \_ -> result |> Query.findAll [ Selector.tag "code" ] |> Query.count (Expect.equal 4)
                    , \_ -> result |> Query.findAll [ Selector.tag "code" ] |> Query.each (Query.hasNot [ Selector.text "\\<" ])
                    , \_ -> result |> Query.has [ Selector.text "<3ms", Selector.text "<4ms", Selector.text "<5ms", Selector.text "<6ms" ]
                    ]
                    ()
        , test "unrecoverable HTML parsing displays the source rather than an empty preview" <|
            \_ ->
                render "# Keep me\n\n<div>unclosed\n"
                    |> Query.find [ Selector.tag "pre" ]
                    |> Query.has [ Selector.text "# Keep me\n\n<div>unclosed\n" ]
        , test "parse recovery terminates with an isolated low surrogate" <|
            \_ ->
                Markdown.parse "\nb👩‍💻]\u{2028}~🌈Zk\n\u{000D}\u{DE00}"
                    |> .html
                    |> List.isEmpty
                    |> Expect.equal False
        , test "comparison recovery preserves a tilde fence nested in a list" <|
            \_ ->
                render "<2ms\n\n- ~~~text\n  <3ms\n  ~~~\n"
                    |> Query.find [ Selector.tag "code" ]
                    |> Query.hasNot [ Selector.text "\\<" ]
        , test "unsupported multiline code spans fall back without inserting escapes into code" <|
            \_ ->
                render "<2ms\n\n`multiline\n<6ms`\n"
                    |> Query.find [ Selector.tag "pre" ]
                    |> Query.has [ Selector.text "<2ms\n\n`multiline\n<6ms`\n" ]
        ]



progressSuite : Test
progressSuite =
    let
        doc =
            List.range 1 6 |> List.map (\i -> "# H" ++ String.fromInt i ++ "\n\n" ++ String.repeat 50 "word ") |> String.join "\n\n"

        ( fresh, _ ) =
            Markdown.begin Markdown.emptyCache Nothing doc

        runToEnd p =
            if Markdown.isComplete p then
                p

            else
                runToEnd (Markdown.step 1000000 p)
    in
    describe "progressive parsing"
        [ test "a small budget still makes progress on exactly one chunk" <|
            \_ -> Markdown.step 1 fresh |> Markdown.htmlChunks |> List.length |> Expect.equal 1
        , test "a budget covering several chunks parses several" <|
            \_ -> Markdown.step 600 fresh |> Markdown.htmlChunks |> List.length |> Expect.equal 3
        , test "steps complete the document in order with all headings" <|
            \_ -> runToEnd fresh |> Markdown.outline |> List.map .text |> Expect.equal [ "H1", "H2", "H3", "H4", "H5", "H6" ]
        , test "cached chunks are free: an edit to one chunk finishes in one small step" <|
            \_ ->
                let
                    cache =
                        Markdown.cache (runToEnd fresh)

                    ( again, _ ) =
                        Markdown.begin cache Nothing (doc ++ " edited")
                in
                Markdown.step 1 again |> Markdown.isComplete |> Expect.equal True
        , test "unchanged chunks keep the identical rendered value across a re-parse" <|
            \_ ->
                let
                    first =
                        runToEnd fresh

                    ( again, _ ) =
                        Markdown.begin (Markdown.cache first) Nothing (doc ++ " edited")
                in
                List.map2 (\a b -> a == b) (Markdown.htmlChunks first) (Markdown.htmlChunks (runToEnd again))
                    |> Expect.equal [ True, True, True, True, True, False ]
        , test "a duplicate heading inserted earlier re-renders later chunks with new ids" <|
            \_ ->
                let
                    first =
                        runToEnd fresh

                    ( again, _ ) =
                        Markdown.begin (Markdown.cache first) Nothing ("# H3\n\nintro\n\n" ++ doc)
                in
                runToEnd again |> Markdown.outline |> List.map .id |> Expect.equal [ "h3", "h1", "h2", "h3-1", "h4", "h5", "h6" ]
        , test "an HTML document that cannot be split renders as one chunk" <|
            \_ ->
                Markdown.begin Markdown.emptyCache Nothing "<div>\n\n# A\n\n# B\n\n</div>"
                    |> Tuple.first
                    |> runToEnd
                    |> Markdown.htmlChunks
                    |> List.length
                    |> Expect.equal 1
        , test "parseCached equals running all steps" <|
            \_ ->
                Tuple.second (Markdown.parseCached Markdown.emptyCache doc)
                    |> .outline
                    |> Expect.equal (Markdown.outline (runToEnd fresh))
        ]


fencedSourceSuite : Test
fencedSourceSuite =
    let
        body =
            "graph LR\nA & B --> C\nD[\"<img src='a&b'>\"]\n"

        check source =
            Query.fromHtml (Html.div [] (Markdown.parse source).html)
                |> Query.find [ Selector.class "mermaid" ]
                |> Query.has [ Selector.attribute (Html.Attributes.attribute "data-source" body) ]
    in
    describe "fenced source preservation"
        [ test "backtick fences preserve operators and literal HTML" <|
            \_ -> check ("```mermaid\n" ++ body ++ "```\n")
        , test "tilde fences preserve operators and literal HTML" <|
            \_ -> check ("~~~mermaid\n" ++ body ++ "~~~\n")
        , test "unclosed fences preserve source through end of file" <|
            \_ -> check ("```mermaid\n" ++ body)
        , test "blockquote fences preserve source" <|
            \_ -> check ("> ```mermaid\n> " ++ String.replace "\n" "\n> " body ++ "```\n")
        , test "list fences preserve source" <|
            \_ -> check ("- ```mermaid\n  " ++ String.replace "\n" "\n  " body ++ "```\n")
        , test "shorter fences and mismatched markers do not end a code block" <|
            \_ ->
                let
                    literal =
                        "```\n~~~\n<img src='a&b'>\n"
                in
                Query.fromHtml (Html.div [] (Markdown.parse ("````text\n" ++ literal ++ "````\n")).html)
                    |> Query.find [ Selector.tag "code" ]
                    |> Query.has [ Selector.text literal ]
        , test "quoted and deeply indented fence-looking lines stay inside top-level code" <|
            \_ ->
                let
                    literal =
                        "> ```\n<img src='a&b'>\n    ```\n<img src='c&d'>\n"
                in
                Query.fromHtml (Html.div [] (Markdown.parse ("```text\n" ++ literal ++ "```\n")).html)
                    |> Query.find [ Selector.tag "code" ]
                    |> Query.has [ Selector.text literal ]
        , test "HTML outside fences still normalizes multiline attributes" <|
            \_ ->
                Query.fromHtml (Html.div [] (Markdown.parse ("```mermaid\n" ++ body ++ "```\n\n<div>\n<img\n src=\"https://example.com/?a=1&b=2\">\n\n# After\n\n</div>\n")).html)
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.text "After" ]
        ]
