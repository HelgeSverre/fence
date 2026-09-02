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
            , test "line count matches the source" <|
                \_ ->
                    SH.javascript "a\nb\nc"
                        |> Result.map (SH.toCustom { noOperation = always (), highlight = always (), addition = always (), deletion = always (), default = always (), comment = always (), style1 = always (), style2 = always (), style3 = always (), style4 = always (), style5 = always (), style6 = always (), style7 = always () } >> List.length)
                        |> Expect.equal (Ok 3)
            ]
        ]
