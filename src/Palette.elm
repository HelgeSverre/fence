module Palette exposing
    ( Item
    , Mode(..)
    , Model
    , active
    , close
    , init
    , isOpen
    , matchScore
    , mode
    , open
    , query
    , rank
    , results
    , setQuery
    , setResults
    , step
    )

{-| The overlay behind quick-open and workspace search: an input, a ranked
list, and a cursor over it. Quick-open ranks a file list held here; search
shows whatever the main process sent back, in the order it found it.
-}

import Types exposing (FilePath)


type Mode
    = Files
    | Search


type alias Item =
    { primary : String -- what the row is called: a file name, or a matching line
    , secondary : String -- where it lives: the path relative to the workspace
    , path : FilePath
    , line : Maybe Int
    }


type alias Model =
    { opened : Maybe Mode
    , query : String
    , items : List Item -- for Files, everything; for Search, the current hits
    , active : Int
    }


init : Model
init =
    { opened = Nothing, query = "", items = [], active = 0 }


isOpen : Model -> Bool
isOpen model =
    model.opened /= Nothing


mode : Model -> Maybe Mode
mode model =
    model.opened


query : Model -> String
query model =
    model.query


open : Mode -> Model -> Model
open wanted model =
    { model | opened = Just wanted, query = "", active = 0, items = keepFilesFor wanted model }


close : Model -> Model
close model =
    { model | opened = Nothing, query = "", active = 0, items = keepFilesFor Files model }


{-| The file list survives closing and reopening; search hits do not. -}
keepFilesFor : Mode -> Model -> List Item
keepFilesFor wanted model =
    if wanted == Files && model.opened /= Just Search then
        model.items

    else if wanted == Files then
        []

    else
        model.items


setResults : List Item -> Model -> Model
setResults items model =
    { model | items = items, active = 0 }


setQuery : String -> Model -> Model
setQuery text model =
    { model | query = text, active = 0 }


{-| The rows to show: ranked by the query for files, as given for search. -}
results : Model -> List Item
results model =
    case model.opened of
        Just Files ->
            rank model.query model.items

        _ ->
            model.items


active : Model -> Maybe Item
active model =
    results model |> List.drop model.active |> List.head


{-| Move the cursor, stopping at both ends: wrapping in a long result list
loses the reader's place. -}
step : Int -> Model -> Model
step delta model =
    { model | active = clamp 0 (Basics.max 0 (List.length (results model) - 1)) (model.active + delta) }


{-| Best matches first, capped: nobody reads past the first screen. -}
rank : String -> List Item -> List Item
rank text items =
    if String.trim text == "" then
        List.take resultLimit items

    else
        items
            |> List.filterMap (\item -> matchScore text item.secondary |> Maybe.map (\score -> ( score, item )))
            |> List.sortBy (\( score, item ) -> ( -score, String.length item.secondary ))
            |> List.take resultLimit
            |> List.map Tuple.second


resultLimit : Int
resultLimit =
    50


{-| How well `candidate` matches `text`, or Nothing if it does not.

Every character of the query must appear in order. A character scores more
when it follows the previous match directly, and more again when it starts a
path segment or a word, so "mdplan" finds "docs/md/plan.md" ahead of a file
that merely contains those letters scattered about.

-}
matchScore : String -> String -> Maybe Int
matchScore text candidate =
    let
        needle =
            String.toList (String.toLower (String.filter (\c -> c /= ' ') text))

        haystack =
            String.toList (String.toLower candidate)

        boundaries =
            '/' :: [ '-', '_', '.', ' ' ]

        go remaining rest previousMatched previousChar total =
            case remaining of
                [] ->
                    Just total

                wanted :: laterWanted ->
                    case rest of
                        [] ->
                            Nothing

                        c :: laterRest ->
                            if c == wanted then
                                go laterWanted
                                    laterRest
                                    True
                                    c
                                    (total
                                        + 1
                                        + (if previousMatched then
                                            4

                                           else
                                            0
                                          )
                                        + (if List.member previousChar boundaries then
                                            3

                                           else
                                            0
                                          )
                                    )

                            else
                                go remaining laterRest False c total
    in
    if List.isEmpty needle then
        Just 0

    else
        go needle haystack False '/' 0
