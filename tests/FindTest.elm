module FindTest exposing (suite)

import Array
import Expect
import Find
import Test exposing (Test, describe, test)
import TextBuffer


doc : String -> Array.Array String
doc =
    TextBuffer.fromString


opened : String -> String -> Find.Model
opened source query =
    Find.init
        |> Find.open False "" (doc source)
        |> Find.setQuery query (doc source)


ranges : Find.Model -> List ( ( Int, Int ), ( Int, Int ) )
ranges model =
    Find.matches model
        |> Array.toList
        |> List.map (\( s, e ) -> ( ( s.line, s.col ), ( e.line, e.col ) ))


suite : Test
suite =
    describe "Find"
        [ test "finds every occurrence in document order" <|
            \_ ->
                opened "one two\nthree one" "one"
                    |> ranges
                    |> Expect.equal [ ( ( 0, 0 ), ( 0, 3 ) ), ( ( 1, 6 ), ( 1, 9 ) ) ]
        , test "overlapping-free repeats on one line are all found" <|
            \_ -> opened "aaa" "a" |> ranges |> Expect.equal [ ( ( 0, 0 ), ( 0, 1 ) ), ( ( 0, 1 ), ( 0, 2 ) ), ( ( 0, 2 ), ( 0, 3 ) ) ]
        , test "matching ignores case by default" <|
            \_ -> opened "Hello hello" "HELLO" |> ranges |> List.length |> Expect.equal 2
        , test "case sensitivity can be turned on" <|
            \_ ->
                opened "Hello hello" "hello"
                    |> Find.setCaseSensitive True (doc "Hello hello")
                    |> ranges
                    |> Expect.equal [ ( ( 0, 6 ), ( 0, 11 ) ) ]
        , test "a line whose lowercase is longer is matched case-sensitively, never at a shifted column" <|
            \_ ->
                -- U+0130 lowercases to two characters
                opened "İx x" "x"
                    |> ranges
                    |> Expect.equal [ ( ( 0, 1 ), ( 0, 2 ) ), ( ( 0, 3 ), ( 0, 4 ) ) ]
        , test "an empty query matches nothing" <|
            \_ -> opened "one" "" |> ranges |> Expect.equal []
        , test "the match list is capped" <|
            \_ ->
                opened (String.repeat (Find.matchLimit + 50) "x") "x"
                    |> Find.matches
                    |> Array.length
                    |> Expect.equal Find.matchLimit
        , test "stepping wraps at both ends" <|
            \_ ->
                let
                    model =
                        opened "a a a" "a"
                in
                Expect.equal
                    [ 1, 2, 3, 1, 3 ]
                    [ Find.count model |> Tuple.first
                    , Find.step 1 model |> Find.count |> Tuple.first
                    , Find.step 2 model |> Find.count |> Tuple.first
                    , Find.step 3 model |> Find.count |> Tuple.first
                    , Find.step -1 model |> Find.count |> Tuple.first
                    ]
        , test "the count is zero of zero with no matches" <|
            \_ -> opened "one" "zzz" |> Find.count |> Expect.equal ( 0, 0 )
        , test "the active match is the one navigation lands on" <|
            \_ ->
                opened "one one" "one"
                    |> Find.step 1
                    |> Find.activeMatch
                    |> Maybe.map (\( s, _ ) -> s.col)
                    |> Expect.equal (Just 4)
        , test "refreshing after an edit re-finds and keeps the active match in range" <|
            \_ ->
                opened "one one one" "one"
                    |> Find.step 2
                    |> Find.refresh (doc "one")
                    |> (\m -> Expect.equal ( 1, 1 ) (Find.count m))
        , test "a closed find does no work and holds no matches" <|
            \_ ->
                opened "one" "one"
                    |> Find.close
                    |> (\m -> Expect.equal ( True, ( 0, 0 ) ) ( Find.isOpen m == False, Find.count m ))
        , test "opening seeds the query from the selection, and keeps the old one when empty" <|
            \_ ->
                let
                    seeded =
                        Find.init |> Find.open False "two" (doc "one two")
                in
                Expect.equal
                    ( "two", "two" )
                    ( seeded.query, Find.open False "" (doc "one two") seeded |> .query )
        ]
