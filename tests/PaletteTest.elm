module PaletteTest exposing (suite)

import Expect
import Palette exposing (Mode(..))
import Test exposing (Test, describe, test)


item : String -> Palette.Item
item relative =
    { primary = relative, relative = relative, path = "/w/" ++ relative, line = Nothing }


files : List Palette.Item
files =
    List.map item [ "readme.md", "docs/plan.md", "docs/deep/planning-notes.md", "notes/todo.md" ]


opened : String -> Palette.Model
opened query =
    Palette.init |> Palette.setResults files |> Palette.open Files |> Palette.setQuery query


names : Palette.Model -> List String
names =
    Palette.results >> List.map .relative


suite : Test
suite =
    describe "Palette"
        [ test "an empty query lists the files as given" <|
            \_ -> opened "" |> names |> Expect.equal (List.map .relative files)
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
        , test "a whole occurrence is matched as one run, at a segment start when it has one" <|
            \_ ->
                Expect.equal
                    ( Just [ 9, 10, 11, 12 ], Just [ 0, 1, 2, 3 ] )
                    ( Palette.match "plan" "planning/plan.md" |> Maybe.map Tuple.second
                    , Palette.match "plan" "planning.md" |> Maybe.map Tuple.second
                    )
        , test "a scattered match is the tightest window, not the first letters that fit" <|
            \_ ->
                Palette.match "pln" "people/land/plan.md"
                    |> Maybe.map Tuple.second
                    |> Expect.equal (Just [ 12, 13, 15 ])
        , test "search keys act on the highlighted row" <|
            \_ ->
                let
                    model =
                        opened "" |> Palette.step 1
                in
                Expect.equal
                    ( [ Palette.CmdCopyText "docs/plan.md" ], [ Palette.CmdCopyText "/w/docs/plan.md" ], [ Palette.CmdReadFile "/w/docs/plan.md" Nothing True ] )
                    ( Palette.update Palette.CopyRelativePath (Just "/w") model |> Tuple.second
                    , Palette.update Palette.CopyAbsolutePath (Just "/w") model |> Tuple.second
                    , Palette.update Palette.ChooseAndReveal (Just "/w") model |> Tuple.second
                    )
        , test "settling asks to peek only when the highlighted row changed and peeking is on" <|
            \_ ->
                let
                    ( first, firstCmds ) =
                        Palette.settle True (opened "")

                    ( same, sameCmds ) =
                        Palette.settle True first

                    ( moved, movedCmds ) =
                        Palette.settle True (Palette.step 1 same)
                in
                Expect.equal
                    ( [ Palette.CmdDebouncePeek 1 ], [], ( [ Palette.CmdDebouncePeek 2 ], Just ( "/w/docs/plan.md", Nothing ), [] ) )
                    ( firstCmds, sameCmds, ( movedCmds, moved.peekFor, Palette.settle False (opened "") |> Tuple.second ) )
        , test "the cursor stops at both ends" <|
            \_ ->
                let
                    model =
                        opened ""
                in
                Expect.equal
                    [ Just "readme.md", Just "docs/plan.md", Just "notes/todo.md", Just "readme.md" ]
                    [ Palette.active model |> Maybe.map .relative
                    , Palette.step 1 model |> Palette.active |> Maybe.map .relative
                    , Palette.step 9 model |> Palette.active |> Maybe.map .relative
                    , Palette.step -9 model |> Palette.active |> Maybe.map .relative
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
