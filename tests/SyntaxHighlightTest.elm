module SyntaxHighlightTest exposing (suite)

import Expect
import Parser
import SyntaxHighlight as SH
import Test exposing (Test, describe, test)


{-| Every highlighter must preserve the source text exactly: the preview
renders the fragments it produces, so a dropped or duplicated character would
corrupt displayed code.
-}
sourceText : SH.HCode -> String
sourceText =
    SH.toCustom
        { noOperation = String.concat
        , highlight = String.concat
        , addition = String.concat
        , deletion = String.concat
        , default = identity
        , comment = identity
        , style1 = identity
        , style2 = identity
        , style3 = identity
        , style4 = identity
        , style5 = identity
        , style6 = identity
        , style7 = identity
        }
        -- line breaks are fragments too, so the lines just concatenate
        >> String.concat


{-| Fragments tagged with their style bucket, for spot-checking classification. -}
tagged : SH.HCode -> List ( String, String )
tagged =
    SH.toCustom
        { noOperation = identity
        , highlight = identity
        , addition = identity
        , deletion = identity
        , default = Tuple.pair "default"
        , comment = Tuple.pair "comment"
        , style1 = Tuple.pair "style1"
        , style2 = Tuple.pair "style2"
        , style3 = Tuple.pair "style3"
        , style4 = Tuple.pair "style4"
        , style5 = Tuple.pair "style5"
        , style6 = Tuple.pair "style6"
        , style7 = Tuple.pair "style7"
        }
        >> List.concat


languages : List ( String, String -> Result (List Parser.DeadEnd) SH.HCode, String )
languages =
    [ ( "elm", SH.elm, "module A exposing (x)\n\n-- comment\nx : Int -> String\nx n =\n    String.fromInt (n * 2) ++ \"!\"\n" )
    , ( "javascript", SH.javascript, "// c\nconst f = (a, b) => `${a}` + 'x' + \"y\";\n/* multi\nline */\nclass K extends L { m() { return [1, 2.5, 0xff]; } }\n" )
    , ( "typescript", SH.typescript, "export const f = (a: number): string[] => [`${a}`];\ninterface I { x?: Map<string, number> }\n" )
    , ( "python", SH.python, "def f(a, b=2):\n    \"\"\"doc\"\"\"\n    # comment\n    return f\"{a}\" * b  # trailing\n@dec\nclass C(B): pass\n" )
    , ( "css", SH.css, ".a > b:hover, #id::before { color: #fff; margin: 1px auto; } /* c */\n@media (max-width: 10px) { a { b: url(x.png) } }\n" )
    , ( "json", SH.json, "{ \"id\": 1, \"name\": \"it\\\"em\", \"tags\": [\"a\", null], \"ok\": true, \"n\": -1.5e3 }\n" )
    , ( "sql", SH.sql, "SELECT id, COUNT(*) AS n FROM users WHERE name LIKE 'a%' -- c\nGROUP BY id HAVING n > 1;\n" )
    , ( "xml", SH.xml, "<!-- c --><div class=\"a\" data-x='1'><br/>text &amp; more</div>\n<?xml version=\"1.0\"?>\n" )
    , ( "go", SH.go, "package main\n\nimport \"fmt\"\n\n// c\nfunc main() { x := []int{1, 2}; fmt.Println(x, `raw`) }\n" )
    , ( "kotlin", SH.kotlin, "fun f(a: Int): String { /* c */ val s = \"x$a\"; return s + 'c' }\n" )
    , ( "nix", SH.nix, "{ pkgs ? import <nixpkgs> {} }: let x = \"a\"; in { inherit x; y = ''multi\n''; } # c\n" )
    , ( "rust", SH.rust, "fn f<'a>(a: &'a str) -> Vec<String> { // c\n    vec![format!(\"{}\", a), 'c'.to_string(), r#\"raw\"#.into()]\n}\n" )
    , ( "php", SH.php, "<?php\n// c\nfunction f(int $a): string { return \"v=$a\" . 'x'; }\n" )
    , ( "dart", SH.dart, "void main() { /* c */ final s = 'a$b'; print(\"${s}\"); }\n" )
    , ( "fsharp", SH.fsharp, "let f (a: int) = // c\n    sprintf \"%d\" a |> printfn \"%s\"\n(* block *)\n" )
    , ( "c", SH.c, "#include <stdio.h>\n// c\ntypedef struct { uint32_t len; } Row;\nint main(void) {\n    /* block */\n    const char *s = \"a\\\"b\";\n    char c = '\\n';\n    return 0x1F + 10ULL;\n}\n" )
    , ( "cpp", SH.cpp, "#include <string>\nnamespace ns {\nclass Widget final : public Base {\npublic:\n    explicit Widget(int n) noexcept : n_(n) {}\nprivate:\n    int n_ = 0;\n};\n}\n" )
    , ( "yaml", SH.yaml, "# comment\n---\nname: fence\nversion: 1.2\ndefaults: &base\n  debug: true\n  ratio: -1.5e3\nprod:\n  <<: *base\n  debug: false\n  empty: ~\n  tag: !!str 7\nlist:\n  - \"quoted\\\"item\"\n  - 'single'\n  - {a: 1, b: [2, 3]}\nblock: |-\n  raw text\n...\n" )
    , ( "toml", SH.toml, "# comment\ntitle = \"a \\\"b\\\" c\"\nliteral = 'raw\\path'\n\n[owner]\nname = \"Tom\"\ndob = 1979-05-27T07:32:00Z\nat = 07:32:00\n\n[database]\nenabled = true\nports = [ 8001, 8002 ]\nsize = 1_000_000\nhex = 0xDEADBEEF\noct = 0o755\nbin = 0b1101\nratio = -3.14e-2\ninline = { x = 1, y = 2 }\nmulti = \"\"\"\nline one\nline two\"\"\"\n\n[[products]]\n\"quoted key\" = 'v'\n" )
    , ( "ruby", SH.ruby, "#!/usr/bin/env ruby\nrequire 'json'\n=begin\nblock comment\n=end\nmodule Fence\n  TAGS = %w[a b]\n  class Doc < Base\n    attr_reader :name\n    def initialize(name, size: 0)\n      @name = name\n      @@count = 0x1F + 1_000 + 2.5e-3\n      $log = nil\n    end\n\n    def self.parse(text)\n      text =~ /\\A#{name}-(\\d+)/i ? :ok : false\n    end\n  end\nend\n" )
    , ( "java", SH.java, "package a.b;\n\nimport java.util.List;\n\n// c\n@Override\npublic final class Box<T> implements Runnable {\n    private static final String S = \"a\\\"b\";\n    /* block */\n    int run(int n) { char c = 'x'; return n * 2 + 0xFFL; }\n    String text = \"\"\"\n        hello\n        \"\"\";\n}\n" )
    , ( "csharp", SH.csharp, "using System;\n\nnamespace N {\n    [Obsolete]\n    public sealed record Box(int N) {\n        // c\n        public async Task<List<string>> Go() => new() { $\"v={N}\", @\"C:\\raw\", \"z\" };\n        private const decimal M = 1_000.5m;\n    }\n}\n" )
    , ( "swift", SH.swift, "import Foundation\n\n// c\n@MainActor\npublic struct Box<T>: Sendable {\n    private var items: [String] = []\n    func go(_ n: Int) async throws -> String? {\n        guard n > 0 else { return nil }\n        /* block */\n        return \"v=\\(n)\" + \"\"\"\n        multi\n        \"\"\"\n    }\n}\n" )
    , ( "scala", SH.scala, "package a.b\n\nimport scala.util.Try\n\n// c\nsealed trait Shape\ncase class Box(n: Int) extends Shape {\n    def go(xs: List[Int]): Option[String] = for { x <- xs } yield s\"v=$x\"\n    val raw = \"\"\"multi\n    line\"\"\"\n    private val m = xs.map(_ * 2L) :: Nil\n}\n" )
    , ( "noLang", SH.noLang, "just some <text> with \"quotes\" and 'ticks' // and slashes\n" )
    ]


edgeCases : List String
edgeCases =
    [ ""
    , "\n"
    , "\n\n\n"
    , "no newline at end"
    , "unterminated \"string"
    , "unterminated /* comment"
    , "tabs\tand   spaces  \n  indented\n"
    , "unicode: æøå 日本語 🎉 \"π\"\n"
    , "very long line " ++ String.repeat 500 "x " ++ "\n"
    ]


suite : Test
suite =
    describe "SyntaxHighlight"
        [ describe "round-trips the source text for every language"
            (List.map
                (\( name, highlight, sample ) ->
                    test name <|
                        \_ ->
                            case highlight sample of
                                Ok hcode ->
                                    sourceText hcode |> Expect.equal sample

                                Err _ ->
                                    Expect.fail "highlighter returned Err on a valid sample"
                )
                languages
            )
        , describe "round-trips edge cases in every language"
            (List.map
                (\( name, highlight, _ ) ->
                    test name <|
                        \_ ->
                            edgeCases
                                |> List.filterMap
                                    (\src ->
                                        case highlight src of
                                            Ok hcode ->
                                                if sourceText hcode == src then
                                                    Nothing

                                                else
                                                    Just ( src, sourceText hcode )

                                            Err _ ->
                                                Just ( src, "<Err>" )
                                    )
                                |> Expect.equal []
                )
                languages
            )
        , describe "classifies tokens"
            [ test "javascript comments and strings are styled, identifiers are not" <|
                \_ ->
                    SH.javascript "const s = \"str\"; // note"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "comment", "// note" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "\"str\"" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    , \_ -> frags |> List.filter (\( k, t ) -> String.contains "s" t && k == "default") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "python keywords are styled" <|
                \_ ->
                    SH.python "def f(): return 1"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> List.filter (\( k, t ) -> (t == "def" || t == "return") && k /= "default")
                        |> List.length
                        |> Expect.equal 2
            , test "elm line comments are one comment fragment" <|
                \_ ->
                    SH.elm "x = 1 -- why"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> List.member ( "comment", "-- why" )
                        |> Expect.equal True
            , test "sql keywords are case-insensitive" <|
                \_ ->
                    SH.sql "select x from t"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> List.filter (\( k, t ) -> List.member t [ "select", "from" ] && k /= "default")
                        |> List.length
                        |> Expect.equal 2
            , test "c keywords, types and preprocessor directives are styled" <|
                \_ ->
                    SH.c "#include <stdio.h>\ntypedef struct { uint32_t len; } Row;"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "style3", "#include <stdio.h>" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> (t == "typedef" || t == "struct") && k /= "default") |> List.length |> Expect.equal 2

                                    -- built-in types and the `_t` typedef convention are recognized...
                                    , \_ -> List.member ( "style4", "uint32_t" ) frags |> Expect.equal True

                                    -- ...but an arbitrary user type name is not (no semantic analysis).
                                    -- Adjacent same-style tokens merge into one fragment, so "Row" shows
                                    -- up inside a larger default-styled run rather than on its own.
                                    , \_ -> frags |> List.filter (\( k, t ) -> String.contains "Row" t && k == "default") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "cpp-only keywords are styled in cpp but not in c" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            SH.cpp "class Widget final {};"
                                |> Result.map tagged
                                |> Result.withDefault []
                                |> List.filter (\( k, t ) -> t == "class" && k /= "default")
                                |> List.isEmpty
                                |> Expect.equal False
                        , \_ ->
                            SH.c "class Widget final {};"
                                |> Result.map tagged
                                |> Result.withDefault []
                                |> List.filter (\( k, t ) -> t == "class" && k /= "default")
                                |> Expect.equal []
                        ]
                        ()
            , test "yaml mapping keys, literals and comments are styled" <|
                \_ ->
                    SH.yaml "name: fence # note\ndebug: true\n"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "comment", "# note" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style5", "name" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style6", "true" ) frags |> Expect.equal True

                                    -- a plain scalar stays default; adjacent default
                                    -- fragments merge, so look inside the run
                                    , \_ -> frags |> List.filter (\( k, t ) -> String.contains "fence" t && k == "default") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "toml table headers, keys and strings are styled" <|
                \_ ->
                    SH.toml "# c\n[owner]\nname = \"Tom\"\nn = 1_000\n"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "comment", "# c" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style4", "[owner]" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style5", "name " ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "\"Tom\"" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    , \_ -> List.member ( "style1", "1_000" ) frags |> Expect.equal True
                                    ]
                                    ()
                           )
            , test "ruby keywords, method names and literals are styled" <|
                \_ ->
                    SH.ruby "def run\n  nil\nend"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> frags |> List.filter (\( k, t ) -> (t == "def" || t == "end") && k == "style3") |> List.length |> Expect.equal 2
                                    , \_ -> List.member ( "style5", "run" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style6", "nil" ) frags |> Expect.equal True
                                    ]
                                    ()
                           )
            , test "ruby symbols and instance variables are styled" <|
                \_ ->
                    SH.ruby "@name = :upcase"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "style7", "@name" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> String.contains "upcase" t && k == "style2") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "ruby division is not a regex literal" <|
                \_ ->
                    SH.ruby "a / b / c"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> List.filter (\( k, _ ) -> k == "style2")
                        |> Expect.equal []
            , test "java keywords, types and annotations are styled" <|
                \_ ->
                    SH.java "@Override\npublic int run() { return null; }"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "style5", "@Override" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style4", "int" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style6", "null" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "public" && k /= "default") |> List.isEmpty |> Expect.equal False

                                    -- no semantic analysis: a user-defined name stays in a default run
                                    , \_ -> frags |> List.filter (\( k, t ) -> String.contains "run" t && k == "default") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "csharp keywords, attributes and interpolated strings are styled" <|
                \_ ->
                    SH.csharp "[Obsolete]\nnamespace N { var s = $\"x\"; }"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "style5", "[Obsolete]" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "namespace" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    , \_ -> List.member ( "style2", "$\"x\"" ) frags |> Expect.equal True
                                    ]
                                    ()
                           )
            , test "swift keywords, types and attributes are styled" <|
                \_ ->
                    SH.swift "@MainActor\nfunc go(n: Int) -> String? { return nil }"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> List.member ( "style5", "@MainActor" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style4", "Int" ) frags |> Expect.equal True
                                    , \_ -> List.member ( "style6", "nil" ) frags |> Expect.equal True
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "func" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    ]
                                    ()
                           )
            , test "scala keywords and types are styled" <|
                \_ ->
                    SH.scala "sealed trait T\ncase class Box(n: Int) { def go: Option[String] = None }"
                        |> Result.map tagged
                        |> Result.withDefault []
                        |> (\frags ->
                                Expect.all
                                    [ \_ -> frags |> List.filter (\( k, t ) -> t == "trait" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    , \_ -> frags |> List.filter (\( k, t ) -> t == "def" && k /= "default") |> List.isEmpty |> Expect.equal False
                                    , \_ -> List.member ( "style4", "Option" ) frags |> Expect.equal True
                                    ]
                                    ()
                           )
            , test "curly-brace dialects disagree on their own keywords" <|
                \_ ->
                    let
                        styledAs keyword highlight source =
                            highlight source
                                |> Result.map tagged
                                |> Result.withDefault []
                                |> List.filter (\( k, t ) -> t == keyword && k /= "default")
                                |> List.isEmpty
                                |> not
                    in
                    Expect.all
                        [ -- `func` is Swift's, not Java's
                          \_ -> styledAs "func" SH.swift "func go() {}" |> Expect.equal True
                        , \_ -> styledAs "func" SH.java "func go() {}" |> Expect.equal False

                        -- `namespace` is C#'s, not Java's
                        , \_ -> styledAs "namespace" SH.csharp "namespace N {}" |> Expect.equal True
                        , \_ -> styledAs "namespace" SH.java "namespace N {}" |> Expect.equal False

                        -- `trait` is Scala's, not C#'s
                        , \_ -> styledAs "trait" SH.scala "trait T" |> Expect.equal True
                        , \_ -> styledAs "trait" SH.csharp "trait T" |> Expect.equal False
                        ]
                        ()
            , test "line count matches the source" <|
                \_ ->
                    SH.javascript "a\nb\nc"
                        |> Result.map (SH.toCustom { noOperation = always (), highlight = always (), addition = always (), deletion = always (), default = always (), comment = always (), style1 = always (), style2 = always (), style3 = always (), style4 = always (), style5 = always (), style6 = always (), style7 = always () } >> List.length)
                        |> Expect.equal (Ok 3)
            ]
        ]
