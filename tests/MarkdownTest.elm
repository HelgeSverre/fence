module MarkdownTest exposing (suite)

import Expect
import Dict
import Markdown
import Markdown.Block as Block
import Markdown.Parser
import Html
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "Markdown" [ selfCloseSuite, headingIdSuite, chunkSuite, renderSuite ]


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
        , test "mermaid fences become a pre.mermaid for the renderer" <|
            \_ -> render "```mermaid\ngraph TD\n```\n" |> Query.find [ Selector.tag "pre" ] |> Query.has [ Selector.class "mermaid", Selector.text "graph TD" ]
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
        ]
