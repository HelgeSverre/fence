module FrontmatterTest exposing (suite)

import Expect
import Frontmatter
import Test exposing (Test, describe, test)
import Yaml exposing (Value(..))


suite : Test
suite =
    describe "Frontmatter.extract"
        [ test "splits a YAML block from the body" <|
            \_ ->
                Frontmatter.extract "---\ntitle: Hi\n---\n# Body\n"
                    |> Expect.equal { frontmatter = Just (Object_ [ ( "title", String_ "Hi" ) ]), body = "# Body\n" }
        , test "accepts CRLF after the opening fence" <|
            \_ ->
                Frontmatter.extract "---\u{000D}\ntitle: Hi\n---\nbody"
                    |> .frontmatter
                    |> Expect.equal (Just (Object_ [ ( "title", String_ "Hi" ) ]))
        , test "accepts the YAML document-end marker as the closing line" <|
            \_ ->
                Frontmatter.extract "---\ntitle: Hi\n...\nbody"
                    |> Expect.equal { frontmatter = Just (Object_ [ ( "title", String_ "Hi" ) ]), body = "body" }
        , test "documents without a leading fence are untouched" <|
            \_ ->
                Frontmatter.extract "# Just markdown\n\n---\n"
                    |> Expect.equal { frontmatter = Nothing, body = "# Just markdown\n\n---\n" }
        , test "an unclosed fence is treated as a thematic break, not frontmatter" <|
            \_ ->
                Frontmatter.extract "---\ntitle: Hi\nno closing"
                    |> Expect.equal { frontmatter = Nothing, body = "---\ntitle: Hi\nno closing" }
        , test "invalid YAML leaves the whole document as the body" <|
            \_ ->
                Frontmatter.extract "---\n[1, 2\n---\nbody"
                    |> Expect.equal { frontmatter = Nothing, body = "---\n[1, 2\n---\nbody" }
        , test "an indented --- inside a literal block does not close the frontmatter" <|
            \_ ->
                Frontmatter.extract "---\ndesc: |\n  ---\n  still yaml\n---\nbody"
                    |> .body
                    |> Expect.equal "body"
        ]
