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
        , test "treeItemId is a stable DOM id derived from the path" <|
            \_ -> Types.treeItemId "/notes/a.md" |> Expect.equal "tree-item--notes-a.md"
        ]
