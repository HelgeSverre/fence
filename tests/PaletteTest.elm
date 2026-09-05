module PaletteTest exposing (suite)

import Expect
import Palette exposing (Mode(..))
import Test exposing (Test, describe, test)


item : String -> Palette.Item
item relative =
    { primary = relative, secondary = relative, path = "/w/" ++ relative, line = Nothing }


files : List Palette.Item
files =
    List.map item [ "readme.md", "docs/plan.md", "docs/deep/planning-notes.md", "notes/todo.md" ]


opened : String -> Palette.Model
opened query =
    Palette.init |> Palette.setResults files |> Palette.open Files |> Palette.setQuery query


names : Palette.Model -> List String
names =
    Palette.results >> List.map .secondary


suite : Test
suite =
    describe "Palette"
        [ test "an empty query lists the files as given" <|
            \_ -> opened "" |> names |> Expect.equal (List.map .secondary files)
        , test "a query keeps only subsequence matches" <|
            \_ -> opened "todo" |> names |> Expect.equal [ "notes/todo.md" ]
        , test "consecutive and segment-start matches rank first" <|
            \_ -> opened "plan" |> names |> Expect.equal [ "docs/plan.md", "docs/deep/planning-notes.md" ]
        , test "a query matching nothing gives nothing" <|
            \_ -> opened "zzz" |> names |> Expect.equal []
        , test "spaces in the query are ignored" <|
            \_ -> opened "doc plan" |> names |> Expect.equal [ "docs/plan.md", "docs/deep/planning-notes.md" ]
        , test "matching ignores case" <|
            \_ -> opened "README" |> names |> Expect.equal [ "readme.md" ]
        , test "scoring rewards a run over scattered letters" <|
            \_ ->
                Expect.equal True
                    (Maybe.withDefault 0 (Palette.matchScore "plan" "plan.md") > Maybe.withDefault 0 (Palette.matchScore "plan" "p-l-a-n.md"))
        , test "the cursor stops at both ends" <|
            \_ ->
                let
                    model =
                        opened ""
                in
                Expect.equal
                    [ Just "readme.md", Just "docs/plan.md", Just "notes/todo.md", Just "readme.md" ]
                    [ Palette.active model |> Maybe.map .secondary
                    , Palette.step 1 model |> Palette.active |> Maybe.map .secondary
                    , Palette.step 9 model |> Palette.active |> Maybe.map .secondary
                    , Palette.step -9 model |> Palette.active |> Maybe.map .secondary
                    ]
        , test "changing the query returns to the first row" <|
            \_ -> opened "" |> Palette.step 2 |> Palette.setQuery "plan" |> .active |> Expect.equal 0
        , test "search mode shows the hits it was given, unranked" <|
            \_ ->
                Palette.init
                    |> Palette.open Search
                    |> Palette.setResults [ item "b.md", item "a.md" ]
                    |> Palette.setQuery "a"
                    |> names
                    |> Expect.equal [ "b.md", "a.md" ]
        , test "closing keeps the file list but drops search hits" <|
            \_ ->
                let
                    afterFiles =
                        opened "" |> Palette.close |> Palette.open Files
                in
                Expect.equal
                    ( 4, 0 )
                    ( List.length (Palette.results afterFiles)
                    , Palette.init
                        |> Palette.open Search
                        |> Palette.setResults [ item "a.md" ]
                        |> Palette.close
                        |> Palette.open Files
                        |> Palette.results
                        |> List.length
                    )
        , test "an open palette reports its mode" <|
            \_ ->
                Expect.equal
                    ( True, Just Search, Nothing )
                    ( Palette.isOpen (Palette.open Search Palette.init)
                    , Palette.mode (Palette.open Search Palette.init)
                    , Palette.mode Palette.init
                    )
        ]
