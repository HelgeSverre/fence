module YamlTest exposing (..)

import Expect
import Frontmatter
import Test exposing (..)
import Yaml exposing (..)


suite : Test
suite =
    describe "YAML Parser"
        [ scalarTests
        , blockMappingTests
        , blockListTests
        , flowCollectionTests
        , multilineStringTests
        , commentTests
        , frontmatterTests
        , edgeCaseTests
        , realWorldFrontmatterTests
        ]


scalarTests : Test
scalarTests =
    describe "Scalars"
        [ test "string" <|
            \_ ->
                parse "hello"
                    |> Expect.equal (Ok (String_ "hello"))
        , test "integer" <|
            \_ ->
                parse "42"
                    |> Expect.equal (Ok (Int_ 42))
        , test "negative integer" <|
            \_ ->
                parse "-7"
                    |> Expect.equal (Ok (Int_ -7))
        , test "float" <|
            \_ ->
                parse "3.14"
                    |> Expect.equal (Ok (Float_ 3.14))
        , test "boolean true" <|
            \_ ->
                parse "true"
                    |> Expect.equal (Ok (Bool_ True))
        , test "boolean false" <|
            \_ ->
                parse "false"
                    |> Expect.equal (Ok (Bool_ False))
        , test "boolean yes" <|
            \_ ->
                parse "yes"
                    |> Expect.equal (Ok (Bool_ True))
        , test "boolean no" <|
            \_ ->
                parse "no"
                    |> Expect.equal (Ok (Bool_ False))
        , test "null" <|
            \_ ->
                parse "null"
                    |> Expect.equal (Ok Null_)
        , test "tilde null" <|
            \_ ->
                parse "~"
                    |> Expect.equal (Ok Null_)
        , test "double-quoted string" <|
            \_ ->
                parse "\"hello world\""
                    |> Expect.equal (Ok (String_ "hello world"))
        , test "double-quoted with escape" <|
            \_ ->
                parse "\"line1\\nline2\""
                    |> Expect.equal (Ok (String_ "line1\nline2"))
        , test "single-quoted string" <|
            \_ ->
                parse "'hello world'"
                    |> Expect.equal (Ok (String_ "hello world"))
        ]


blockMappingTests : Test
blockMappingTests =
    describe "Block mappings"
        [ test "flat mapping" <|
            \_ ->
                parse "name: Alice\nage: 30"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "name", String_ "Alice" )
                                , ( "age", Int_ 30 )
                                ]
                            )
                        )
        , test "nested mapping" <|
            \_ ->
                parse "person:\n  name: Alice\n  age: 30"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "person"
                                  , Object_
                                        [ ( "name", String_ "Alice" )
                                        , ( "age", Int_ 30 )
                                        ]
                                  )
                                ]
                            )
                        )
        , test "deeply nested mapping" <|
            \_ ->
                parse "a:\n  b:\n    c: deep"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "a"
                                  , Object_
                                        [ ( "b"
                                          , Object_
                                                [ ( "c", String_ "deep" ) ]
                                          )
                                        ]
                                  )
                                ]
                            )
                        )
        ]


blockListTests : Test
blockListTests =
    describe "Block lists"
        [ test "simple list" <|
            \_ ->
                parse "- one\n- two\n- three"
                    |> Expect.equal
                        (Ok
                            (List_
                                [ String_ "one"
                                , String_ "two"
                                , String_ "three"
                                ]
                            )
                        )
        , test "list of integers" <|
            \_ ->
                parse "- 1\n- 2\n- 3"
                    |> Expect.equal
                        (Ok
                            (List_
                                [ Int_ 1
                                , Int_ 2
                                , Int_ 3
                                ]
                            )
                        )
        , test "mapping with list value" <|
            \_ ->
                parse "tags:\n  - elm\n  - parser"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "tags"
                                  , List_
                                        [ String_ "elm"
                                        , String_ "parser"
                                        ]
                                  )
                                ]
                            )
                        )
        ]


flowCollectionTests : Test
flowCollectionTests =
    describe "Flow collections"
        [ test "flow list" <|
            \_ ->
                parse "[1, 2, 3]"
                    |> Expect.equal
                        (Ok
                            (List_
                                [ Int_ 1
                                , Int_ 2
                                , Int_ 3
                                ]
                            )
                        )
        , test "flow object" <|
            \_ ->
                parse "{a: 1, b: 2}"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "a", Int_ 1 )
                                , ( "b", Int_ 2 )
                                ]
                            )
                        )
        , test "flow list of strings" <|
            \_ ->
                parse "[hello, world]"
                    |> Expect.equal
                        (Ok
                            (List_
                                [ String_ "hello"
                                , String_ "world"
                                ]
                            )
                        )
        , test "empty flow list" <|
            \_ ->
                parse "[]"
                    |> Expect.equal (Ok (List_ []))
        , test "empty flow object" <|
            \_ ->
                parse "{}"
                    |> Expect.equal (Ok (Object_ []))
        ]


multilineStringTests : Test
multilineStringTests =
    describe "Multi-line strings"
        [ test "literal block" <|
            \_ ->
                parse "|\n  line1\n  line2"
                    |> Expect.equal (Ok (String_ "line1\nline2"))
        , test "folded block" <|
            \_ ->
                parse ">\n  line1\n  line2"
                    |> Expect.equal (Ok (String_ "line1 line2"))
        ]


commentTests : Test
commentTests =
    describe "Comments"
        [ test "inline comment" <|
            \_ ->
                parse "name: Alice # a comment"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "name", String_ "Alice" ) ]
                            )
                        )
        ]


frontmatterTests : Test
frontmatterTests =
    describe "Frontmatter extraction"
        [ test "with frontmatter" <|
            \_ ->
                let
                    input =
                        "---\ntitle: Hello\ntags:\n  - elm\n---\n# Body"

                    result =
                        Frontmatter.extract input
                in
                case result.frontmatter of
                    Just (Object_ fields) ->
                        Expect.equal
                            [ ( "title", String_ "Hello" )
                            , ( "tags", List_ [ String_ "elm" ] )
                            ]
                            fields

                    _ ->
                        Expect.fail "Expected Object_ frontmatter"
        , test "without frontmatter" <|
            \_ ->
                let
                    result =
                        Frontmatter.extract "# Just markdown"
                in
                Expect.equal Nothing result.frontmatter
        , test "body after frontmatter" <|
            \_ ->
                let
                    result =
                        Frontmatter.extract "---\ntitle: Hi\n---\n# Body"
                in
                Expect.equal "# Body" result.body
        , test "dots closing" <|
            \_ ->
                let
                    result =
                        Frontmatter.extract "---\ntitle: Hi\n...\n# Body"
                in
                case result.frontmatter of
                    Just (Object_ _) ->
                        Expect.equal "# Body" result.body

                    _ ->
                        Expect.fail "Expected frontmatter with ... closing"
        ]


edgeCaseTests : Test
edgeCaseTests =
    describe "Edge cases"
        [ test "empty document" <|
            \_ ->
                parse ""
                    |> Expect.equal (Ok Null_)
        , test "colon in value" <|
            \_ ->
                parse "url: http://example.com"
                    |> Expect.equal
                        (Ok
                            (Object_
                                [ ( "url", String_ "http://example.com" ) ]
                            )
                        )
        , test "get helper" <|
            \_ ->
                let
                    obj =
                        Object_ [ ( "name", String_ "Alice" ) ]
                in
                get "name" obj
                    |> Expect.equal (Just (String_ "Alice"))
        , test "toString helper" <|
            \_ ->
                toString (String_ "hello")
                    |> Expect.equal (Just "hello")
        , test "toList helper" <|
            \_ ->
                toList (List_ [ Int_ 1 ])
                    |> Expect.equal (Just [ Int_ 1 ])
        , test "toObject helper" <|
            \_ ->
                toObject (Object_ [ ( "a", Int_ 1 ) ])
                    |> Expect.equal (Just [ ( "a", Int_ 1 ) ])
        ]


realWorldFrontmatterTests : Test
realWorldFrontmatterTests =
    describe "Real-world frontmatter cases"
        [ test "negative float" <|
            \_ ->
                parse "offset: -1.5"
                    |> Expect.equal
                        (Ok (Object_ [ ( "offset", Float_ -1.5 ) ]))
        , test "double-quoted string containing a colon" <|
            \_ ->
                parse "title: \"Hello: World\""
                    |> Expect.equal
                        (Ok (Object_ [ ( "title", String_ "Hello: World" ) ]))
        , test "frontmatter with CRLF line endings" <|
            \_ ->
                let
                    result =
                        Frontmatter.extract "---\r\ntitle: Hi\r\n---\r\n# Body\r\n"
                in
                case result.frontmatter of
                    Just (Object_ fields) ->
                        Expect.equal
                            [ ( "title", String_ "Hi" ) ]
                            fields

                    _ ->
                        Expect.fail "Expected frontmatter to parse with CRLF endings"
        , test "frontmatter with no body" <|
            \_ ->
                let
                    result =
                        Frontmatter.extract "---\ntitle: Hi\n---\n"
                in
                Expect.equal "" (String.trim result.body)
        , test "uppercase True is a string, not a boolean" <|
            \_ ->
                -- Yaml.elm only recognises lowercase true/false/yes/no.
                -- Lock the behavior in so a future change is intentional.
                parse "flag: True"
                    |> Expect.equal
                        (Ok (Object_ [ ( "flag", String_ "True" ) ]))

        -- Known Yaml.elm gaps (parser currently rejects these). Listed here
        -- so the next maintainer can pick them up; not promoted to failing
        -- tests because they aren't quick fixes:
        --   * literal block with strip-chomp: "summary: |-\n  one\n  two"
        --   * list of mappings: "authors:\n  - name: Alice\n    email: a@x"
        ]
