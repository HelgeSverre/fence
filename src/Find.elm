module Find exposing
    ( Model
    , activeMatch
    , close
    , count
    , init
    , isOpen
    , matchLimit
    , matches
    , open
    , refresh
    , setActive
    , setCaseSensitive
    , setQuery
    , setReplacement
    , showReplace
    , step
    )

{-| Literal search over the open document. Matching is a plain substring scan
per line, which is a few milliseconds even on a very large file, so there is no
index to keep in step with edits: `refresh` recomputes from the buffer.

Highlights are capped at `matchLimit` - past that the list stops being useful
and every render would pay for it.

-}

import Array exposing (Array)
import TextBuffer exposing (Cursor)


type alias Model =
    { query : String
    , replacement : String
    , caseSensitive : Bool
    , replaceShown : Bool
    , opened : Bool
    , matches : Array ( Cursor, Cursor )
    , active : Int
    }


init : Model
init =
    { query = ""
    , replacement = ""
    , caseSensitive = False
    , replaceShown = False
    , opened = False
    , matches = Array.empty
    , active = 0
    }


{-| Highlighting every match on a huge document costs more than it is worth. -}
matchLimit : Int
matchLimit =
    2000


isOpen : Model -> Bool
isOpen model =
    model.opened


open : Bool -> String -> Array String -> Model -> Model
open withReplace seed lines model =
    refresh lines
        { model
            | opened = True
            , replaceShown = withReplace || model.replaceShown
            , query =
                if seed == "" then
                    model.query

                else
                    seed
        }


close : Model -> Model
close model =
    { model | opened = False, matches = Array.empty }


showReplace : Bool -> Model -> Model
showReplace shown model =
    { model | replaceShown = shown }


setQuery : String -> Array String -> Model -> Model
setQuery query lines model =
    refresh lines { model | query = query, active = 0 }


setReplacement : String -> Model -> Model
setReplacement replacement model =
    { model | replacement = replacement }


setCaseSensitive : Bool -> Array String -> Model -> Model
setCaseSensitive sensitive lines model =
    refresh lines { model | caseSensitive = sensitive }


{-| Recompute the matches against the current buffer, keeping the active one
in range. Call after every edit to the document and every change to the query.
-}
refresh : Array String -> Model -> Model
refresh lines model =
    if not model.opened then
        model

    else
        let
            found =
                matchesIn model.caseSensitive model.query lines
        in
        { model
            | matches = found
            , active =
                if Array.isEmpty found then
                    0

                else
                    clamp 0 (Array.length found - 1) model.active
        }


matches : Model -> Array ( Cursor, Cursor )
matches model =
    model.matches


count : Model -> ( Int, Int )
count model =
    ( if Array.isEmpty model.matches then
        0

      else
        model.active + 1
    , Array.length model.matches
    )


activeMatch : Model -> Maybe ( Cursor, Cursor )
activeMatch model =
    Array.get model.active model.matches


setActive : Int -> Model -> Model
setActive index model =
    { model | active = index }


{-| Move `delta` matches, wrapping at both ends. -}
step : Int -> Model -> Model
step delta model =
    let
        total =
            Array.length model.matches
    in
    if total == 0 then
        model

    else
        { model | active = modBy total (model.active + delta) }


{-| Every occurrence of `query`, in document order.

Case-insensitive matching compares lowercased text. A handful of characters
lowercase to a *longer* string (U+0130 among them), which would shift every
column on that line, so such a line is matched case-sensitively instead of
reporting a highlight in the wrong place.

-}
matchesIn : Bool -> String -> Array String -> Array ( Cursor, Cursor )
matchesIn caseSensitive query lines =
    if query == "" then
        Array.empty

    else
        let
            width =
                String.length query

            needle =
                if caseSensitive then
                    query

                else
                    String.toLower query

            -- prepended and reversed at the end: appending would copy the
            -- whole list once per match
            onLine index line ( found, total ) =
                if total >= matchLimit then
                    ( found, total )

                else
                    let
                        haystack =
                            if caseSensitive then
                                line

                            else
                                let
                                    lowered =
                                        String.toLower line
                                in
                                if String.length lowered == String.length line then
                                    lowered

                                else
                                    line

                        onThisLine =
                            String.indexes needle haystack
                                |> List.map (\col -> ( { line = index, col = col }, { line = index, col = col + width } ))
                    in
                    ( List.foldl (::) found onThisLine, total + List.length onThisLine )
        in
        Array.toIndexedList lines
            |> List.foldl (\( index, line ) acc -> onLine index line acc) ( [], 0 )
            |> Tuple.first
            |> List.reverse
            |> List.take matchLimit
            |> Array.fromList
