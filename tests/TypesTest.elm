module TypesTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types


suite : Test
suite =
    describe "Types helpers"
        [ test "baseName returns the last path segment" <|
            \_ -> Types.baseName "/Users/x/notes/a.md" |> Expect.equal "a.md"
        , test "baseName of a bare name is the name" <|
            \_ -> Types.baseName "a.md" |> Expect.equal "a.md"
        , test "dirName is the parent directory, with no trailing slash" <|
            \_ -> Types.dirName "/Users/x/notes/a.md" |> Expect.equal "/Users/x/notes"
        , test "dirName of a path at the root is the root" <|
            \_ -> Types.dirName "/a.md" |> Expect.equal "/"
        , test "dirName ignores a trailing or doubled slash" <|
            \_ -> ( Types.dirName "/w/sub/", Types.dirName "/w//a.md" ) |> Expect.equal ( "/w", "/w" )
        , test "treeItemId is a stable DOM id derived from the path" <|
            \_ -> Types.treeItemId "/notes/a.md" |> Expect.equal "tree-item--notes-a.md"
        ]
