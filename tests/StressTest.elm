module StressTest exposing (suite)

{-| Property and volume tests. Every parser in the app must terminate on
arbitrary input, preserve text where it promises to, and survive inputs far
larger than any real document without blowing the stack.
-}

import Editor
import Expect
import FileTree exposing (Msg(..))
import Frontmatter
import Fuzz exposing (Fuzzer)
import Json.Encode as E
import Main
import Markdown
import Markdown.Parser
import Parser
import SyntaxHighlight as SH
import Test exposing (Test, describe, fuzz, fuzzWith, noDistribution, test)
import Types exposing (FileEntry(..), FileType(..))
import Yaml


suite : Test
suite =
    describe "Stress"
        [ terminationSuite, markdownPropertySuite, highlighterFuzzSuite, mainFuzzSuite, volumeSuite ]



-- FUZZERS


{-| Strings drawn from characters that matter to every parser here, mixed
with astral-plane characters (surrogate pairs) and odd whitespace.
-}
nastyString : Fuzzer String
nastyString =
    Fuzz.listOfLengthBetween 0 24
        (Fuzz.frequency
            [ ( 6, Fuzz.oneOfValues [ "*", "`", "[", "]", "(", ")", "#", "-", ".", ":", "|", ">", "\"", "'", "\\", "{", "}", "<", "/", "&", "_", "~", "!", "=", "," ] )
            , ( 3, Fuzz.oneOfValues [ " ", "\n", "\t", "\u{000D}", "\u{00A0}", "\u{2028}" ] )
            , ( 3, Fuzz.oneOfValues [ "a", "b", "1", "0", "æ", "日", "😀", "👩\u{200D}💻", "\u{D83D}", "\u{DE00}" ] )
            , ( 1, Fuzz.string )
            ]
        )
        |> Fuzz.map String.concat


markdownLine : Fuzzer String
markdownLine =
    Fuzz.oneOfValues
        [ ""
        , "# Heading"
        , "## Sub *em* **strong**"
        , "### Third"
        , "#hashtag not heading"
        , "plain paragraph text with `code` and [link](https://x.y)"
        , "- list item"
        , "  - nested item"
        , "1. ordered"
        , "> quoted"
        , "```js"
        , "```"
        , "~~~"
        , "````"
        , "const x = 1; // inside fence maybe"
        , "| a | b |"
        , "|---|---|"
        , "| 1 | 2 |"
        , "---"
        , "***"
        , "Setext"
        , "====="
        , "text ending with two spaces  "
        , "![img](a.png)"
        , "<br>"
        , "😀 emoji *line*"
        ]


{-| Markdown built from realistic lines. Excludes indented code blocks and
column-0 HTML blocks, whose elm-markdown quirks are documented in
MarkdownTest rather than being equivalence-preserving under chunking.
-}
markdownDoc : Fuzzer String
markdownDoc =
    Fuzz.listOfLengthBetween 0 40 markdownLine |> Fuzz.map (String.join "\n")



-- TERMINATION AND TEXT PRESERVATION


terminationSuite : Test
terminationSuite =
    describe "every parser terminates on hostile input"
        [ fuzz nastyString "Yaml.parse" <|
            \src ->
                case Yaml.parse src of
                    Ok _ ->
                        Expect.pass

                    Err _ ->
                        Expect.pass
        , fuzz nastyString "Frontmatter.extract never loses the body" <|
            \src ->
                let
                    result =
                        Frontmatter.extract src
                in
                case result.frontmatter of
                    Nothing ->
                        result.body |> Expect.equal src

                    Just _ ->
                        String.length result.body |> Expect.atMost (String.length src)
        , fuzz nastyString "Markdown.parse" <|
            \src -> (Markdown.parse src).outline |> List.length |> Expect.atLeast 0
        , fuzz nastyString "Editor.lineTokens round-trips" <|
            \src -> Editor.lineTokens src |> List.map .text |> String.concat |> Expect.equal src
        , fuzz nastyString "selfCloseVoidTags only ever adds characters" <|
            \src -> String.length (Markdown.selfCloseVoidTags src) |> Expect.atLeast (String.length src)
        ]



-- CHUNKED PARSING


markdownPropertySuite : Test
markdownPropertySuite =
    describe "chunked parsing"
        [ fuzz markdownDoc "chunks concatenate back to the document" <|
            \doc -> Markdown.splitChunks doc |> String.join "\n" |> Expect.equal doc
        , fuzz markdownDoc "chunked parse equals whole-document parse" <|
            \doc ->
                Markdown.splitChunks doc
                    |> List.map Markdown.Parser.parse
                    |> List.foldr (Result.map2 (++)) (Ok [])
                    |> Expect.equal (Markdown.Parser.parse doc)
        , fuzz markdownDoc "the cache never changes the result" <|
            \doc ->
                let
                    ( cache, first ) =
                        Markdown.parseCached Markdown.emptyCache doc

                    -- a second edit somewhere, then back to the original
                    ( cache2, _ ) =
                        Markdown.parseCached cache (doc ++ "\n\n# Extra")

                    ( _, again ) =
                        Markdown.parseCached cache2 doc
                in
                again.outline |> Expect.equal first.outline
        , fuzz nastyString "splitChunks preserves hostile input too" <|
            \src -> Markdown.splitChunks src |> String.join "\n" |> Expect.equal src
        ]



-- SYNTAX HIGHLIGHTERS


highlighters : List ( String, String -> Result (List Parser.DeadEnd) SH.HCode )
highlighters =
    [ ( "elm", SH.elm ), ( "javascript", SH.javascript ), ( "typescript", SH.typescript ), ( "python", SH.python )
    , ( "css", SH.css ), ( "json", SH.json ), ( "sql", SH.sql ), ( "xml", SH.xml ), ( "go", SH.go ), ( "kotlin", SH.kotlin )
    , ( "nix", SH.nix ), ( "rust", SH.rust ), ( "php", SH.php ), ( "dart", SH.dart ), ( "fsharp", SH.fsharp ), ( "noLang", SH.noLang )
    ]


sourceText : SH.HCode -> String
sourceText =
    SH.toCustom
        { noOperation = String.concat, highlight = String.concat, addition = String.concat, deletion = String.concat
        , default = identity, comment = identity, style1 = identity, style2 = identity, style3 = identity
        , style4 = identity, style5 = identity, style6 = identity, style7 = identity
        }
        >> String.concat


highlighterFuzzSuite : Test
highlighterFuzzSuite =
    describe "highlighters round-trip hostile input"
        (List.map
            (\( name, highlight ) ->
                fuzzWith { runs = 40, distribution = noDistribution } nastyString name <|
                    \src ->
                        case highlight src of
                            Ok hcode ->
                                sourceText hcode |> Expect.equal src

                            Err _ ->
                                -- Falling back to a plain block is acceptable; hanging is not.
                                Expect.pass
            )
            highlighters
        )



-- MAIN UPDATE INVARIANTS


mainMsg : Fuzzer Main.Msg
mainMsg =
    Fuzz.oneOf
        [ Fuzz.map (Main.DividerMouseDown Main.DraggingSidebar) (Fuzz.floatRange -100 3000)
        , Fuzz.map (Main.DividerMouseDown Main.DraggingEditor) (Fuzz.floatRange -100 3000)
        , Fuzz.map (Main.DividerMouseDown Main.DraggingRightSidebar) (Fuzz.floatRange -100 3000)
        , Fuzz.map Main.DividerMouseMove (Fuzz.floatRange -5000 5000)
        , Fuzz.constant Main.DividerMouseUp
        , Fuzz.map Main.DividerDoubleClick (Fuzz.oneOfValues [ Main.DraggingSidebar, Main.DraggingEditor, Main.DraggingRightSidebar ])
        , Fuzz.map2 Main.WindowResized (Fuzz.intRange 0 5000) (Fuzz.intRange 0 5000)
        , Fuzz.constant Main.ToggleLeftSidebar
        , Fuzz.constant Main.ToggleRightSidebar
        , Fuzz.map Main.SetOutlineMaxLevel (Fuzz.intRange -5 12)
        , Fuzz.constant Main.ToggleSettings
        , Fuzz.constant Main.CloseSettings
        , Fuzz.map (\s -> Main.EditorMsg (Editor.ContentChanged s)) markdownDoc
        , Fuzz.map Main.DebouncedParse (Fuzz.intRange 0 5)
        , Fuzz.map (\k -> Main.KeyDown k True False False False) (Fuzz.oneOfValues [ "1", "3", "s", "Escape", "x" ])
        , Fuzz.map Main.SetTheme (Fuzz.oneOfValues [ "", "light", "dracula" ])
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "saveAndClose" ) ]))
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "saveCancelled" ) ]))
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "error" ), ( "message", E.string "boom" ) ]))
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "fileContent" ), ( "path", E.string "/w/a.md" ), ( "content", E.string "# A\n\n😀*" ), ( "revision", E.string "r" ), ( "dirty", E.bool False ) ]))
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "fileSaved" ), ( "path", E.string "/w/a.md" ), ( "revision", E.string "r2" ) ]))
        , Fuzz.constant (Main.FromElectron (E.object [ ( "tag", E.string "fsEvent" ), ( "event", E.string "change" ), ( "path", E.string "/w/a.md" ) ]))
        , Fuzz.constant (Main.FromElectron (E.string "garbage"))
        , Fuzz.constant Main.DismissError
        , Fuzz.constant Main.NoOp
        ]


mainFuzzSuite : Test
mainFuzzSuite =
    fuzzWith { runs = 60, distribution = noDistribution } (Fuzz.listOfLengthBetween 0 30 mainMsg) "random message sequences keep Main's invariants" <|
        \msgs ->
            let
                model =
                    List.foldl (\msg m -> Tuple.first (Main.update msg m)) (Tuple.first (Main.init (E.object []))) msgs
            in
            Expect.all
                [ \m -> m.sidebarFraction |> Expect.all [ Expect.atLeast 0.08, Expect.atMost 0.4 ]
                , \m -> m.rightSidebarFraction |> Expect.all [ Expect.atLeast 0.08, Expect.atMost 0.4 ]
                , \m -> m.editorFraction |> Expect.all [ Expect.atLeast 0.15, Expect.atMost 0.85 ]
                , \m -> m.outlineMaxLevel |> Expect.all [ Expect.atLeast 1, Expect.atMost 6 ]
                , \m -> m.debounceGeneration |> Expect.atLeast 0
                , \m ->
                    -- a pending close is only ever kept alongside an in-flight save
                    if m.closeAfterSave then
                        m.savingContent |> Expect.notEqual Nothing

                    else
                        Expect.pass
                ]
                model



-- VOLUME


volumeSuite : Test
volumeSuite =
    let
        bigDoc =
            List.range 1 20000
                |> List.map (\i -> "## Section " ++ String.fromInt i ++ "\n\ntext **" ++ String.fromInt i ++ "** `c`\n\n- a\n- b\n\n")
                |> String.concat

        manyFiles =
            List.range 1 5000 |> List.map (\i -> FileEntry { name = "f" ++ String.fromInt i ++ ".md", path = "/w/f" ++ String.fromInt i ++ ".md", fileType = File, children = Nothing })
    in
    describe "large inputs do not overflow the stack"
        [ test "lineTokens on a 200k-character line full of delimiters" <|
            \_ ->
                let
                    line =
                        String.repeat 20000 "**a** `b` [c](d) "
                in
                Editor.lineTokens line |> List.map .text |> String.concat |> Expect.equal line
        , test "Markdown.parse on a 1.2MB document with 20k headings" <|
            \_ -> (Markdown.parse bigDoc).outline |> List.length |> Expect.equal 20000
        , test "splitChunks on 20k headings yields 20k chunks that round-trip" <|
            \_ ->
                let
                    chunks =
                        Markdown.splitChunks bigDoc
                in
                ( List.length chunks, String.join "\n" chunks == bigDoc ) |> Expect.equal ( 20000, True )
        , test "Yaml.parse on a mapping with 5k keys and nested lists" <|
            \_ ->
                List.range 1 5000
                    |> List.map (\i -> "k" ++ String.fromInt i ++ ":\n  - a\n  - b" ++ String.fromInt i)
                    |> String.join "\n"
                    |> Yaml.parse
                    |> Result.map (\v -> case v of
                                            Yaml.Object_ fields -> List.length fields
                                            _ -> -1)
                    |> Expect.equal (Ok 5000)
        , test "Frontmatter.extract on a 100k-line document without frontmatter" <|
            \_ ->
                let
                    doc =
                        String.repeat 100000 "line\n"
                in
                (Frontmatter.extract doc).body |> String.length |> Expect.equal (String.length doc)
        , test "file tree keyboard navigation across 5k files" <|
            \_ ->
                FileTree.handleFolderOpened "/w" manyFiles FileTree.init
                    |> (\m -> List.foldl (\msg model -> Tuple.first (FileTree.update msg model)) m [ FocusLast, FocusUp, FocusUp, FocusFirst, FocusDown ])
                    |> .focused
                    |> Expect.equal (Just "/w/f1.md")
        , test "5k filesystem additions" <|
            \_ ->
                List.foldl (\i m -> FileTree.handleFsEvent "add" ("/w/n" ++ String.fromInt i ++ ".md") m) (FileTree.handleFolderOpened "/w" [] FileTree.init) (List.range 1 5000)
                    |> .root
                    |> Maybe.andThen Types.fileEntryChildren
                    |> Maybe.map List.length
                    |> Expect.equal (Just 5000)
        , test "highlighting a 5k-line javascript block" <|
            \_ ->
                let
                    src =
                        String.repeat 5000 "const x = f(\"s\", 1.5) // c\n"
                in
                SH.javascript src |> Result.map sourceText |> Expect.equal (Ok src)
        ]
