module Palette exposing
    ( Item
    , Mode(..)
    , Model
    , Msg(..)
    , OutCmd(..)
    , active
    , close
    , init
    , inputId
    , isOpen
    , matchScore
    , mode
    , open
    , query
    , rank
    , results
    , searchDelay
    , setQuery
    , setResults
    , step
    , update
    , view
    )

{-| The overlay behind quick-open and workspace search: an input, a ranked
list, and a cursor over it. Quick-open ranks a file list held here; search
shows whatever the main process sent back, in the order it found it.
-}

import Html exposing (Html, div, input, span, text)
import Html.Attributes exposing (attribute, class, classList, id, placeholder, spellcheck, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as D
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
    , searchGeneration : Int -- the query the pending debounced search was for
    }


init : Model
init =
    { opened = Nothing, query = "", items = [], active = 0, searchGeneration = 0 }


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



-- MESSAGES


type Msg
    = Open Mode
    | Close
    | QueryChanged String
    | SearchDue Int
    | Step Int
    | Choose (Maybe Item)
    | NoOp


{-| What Main does on the module's behalf: focus, and talking to the main
process.
-}
type OutCmd
    = CmdFocusInput
    | CmdFocusDocument -- give focus back to the editor or preview
    | CmdListFiles FilePath -- the workspace root
    | CmdDebounceSearch Int -- send `SearchDue` with this generation after `searchDelay`
    | CmdSearch FilePath String -- root and query
    | CmdReadFile FilePath (Maybe Int) -- and the line to put the caret on


{-| How long to wait before searching the workspace for what has been typed. -}
searchDelay : Float
searchDelay =
    200


inputId : String
inputId =
    "palette-input"


{-| `root` is the open workspace, if any: there is nothing to list or search
without one.
-}
update : Msg -> Maybe FilePath -> Model -> ( Model, List OutCmd )
update msg root model =
    case msg of
        Open wanted ->
            ( open wanted model
            , CmdFocusInput
                :: (case ( wanted, root ) of
                        -- the list is cheap to rebuild and always current this way
                        ( Files, Just path ) ->
                            [ CmdListFiles path ]

                        _ ->
                            []
                   )
            )

        Close ->
            ( close model, [ CmdFocusDocument ] )

        QueryChanged text ->
            let
                palette =
                    setQuery text model

                generation =
                    model.searchGeneration + 1
            in
            case ( palette.opened, root ) of
                ( Just Search, Just _ ) ->
                    ( { palette | searchGeneration = generation }, [ CmdDebounceSearch generation ] )

                _ ->
                    ( palette, [] )

        SearchDue generation ->
            if generation /= model.searchGeneration then
                ( model, [] )

            else
                case ( root, String.trim model.query ) of
                    ( Just path, text ) ->
                        if text == "" then
                            ( setResults [] model, [] )

                        else
                            ( model, [ CmdSearch path text ] )

                    _ ->
                        ( model, [] )

        Step delta ->
            ( step delta model, [] )

        Choose item ->
            case item of
                Just chosen ->
                    ( close model, [ CmdReadFile chosen.path chosen.line ] )

                Nothing ->
                    ( model, [] )

        NoOp ->
            ( model, [] )



-- VIEW


view : Model -> Html Msg
view palette =
    let
        rows =
            results palette

        placeholderText =
            case mode palette of
                Just Search ->
                    "Search the workspace"

                _ ->
                    "Go to file"

        row index item =
            div
                [ class "palette-row"
                , classList [ ( "active", index == palette.active ) ]
                , attribute "data-testid" "palette-row"
                , attribute "role" "option"
                , attribute "aria-selected"
                    (if index == palette.active then
                        "true"

                     else
                        "false"
                    )
                , onClick (Choose (Just item))
                ]
                [ span [ class "palette-primary" ] [ text item.primary ]
                , span [ class "palette-secondary" ] [ text item.secondary ]
                ]
    in
    div [ class "palette-backdrop", attribute "data-testid" "palette", onClick Close ]
        [ div [ class "palette", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
            [ input
                [ class "palette-input"
                , id inputId
                , attribute "data-testid" "palette-input"
                , attribute "aria-label" placeholderText
                , placeholder placeholderText
                , value (query palette)
                , spellcheck False
                , onInput QueryChanged
                , preventDefaultOn "keydown" (keyDecoder palette)
                ]
                []
            , if List.isEmpty rows then
                div [ class "palette-empty" ] [ text "No results" ]

              else
                div [ class "palette-results", attribute "role" "listbox" ] (List.indexedMap row rows)
            ]
        ]


keyDecoder : Model -> D.Decoder ( Msg, Bool )
keyDecoder palette =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                case key of
                    "ArrowDown" ->
                        D.succeed ( Step 1, True )

                    "ArrowUp" ->
                        D.succeed ( Step -1, True )

                    "Enter" ->
                        D.succeed ( Choose (active palette), True )

                    "Escape" ->
                        D.succeed ( Close, True )

                    _ ->
                        D.fail "not a palette key"
            )


