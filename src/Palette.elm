module Palette exposing
    ( Item
    , Mode(..)
    , Model
    , Msg(..)
    , OutCmd(..)
    , Peek
    , active
    , close
    , init
    , inputId
    , isOpen
    , match
    , matchScore
    , mode
    , open
    , peekDelay
    , query
    , rank
    , results
    , searchDelay
    , setPeek
    , setQuery
    , setResults
    , settle
    , step
    , update
    , view
    )

{-| The overlay behind quick-open and workspace search: an input, a ranked
list, and a cursor over it. Quick-open ranks a file list held here; search
shows whatever the main process sent back, in the order it found it.

A row names the file and shows its folder underneath, with the characters
the query matched picked out. The footer lists the keys that act on the
highlighted row. With the peek pane turned on, the highlighted document is
previewed beside the list.

-}

import Html exposing (Html, div, input, kbd, span, text)
import Html.Attributes exposing (attribute, class, classList, id, placeholder, spellcheck, value)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as D
import Set exposing (Set)
import Types exposing (FilePath, baseName)


type Mode
    = Files
    | Search


type alias Item =
    { primary : String -- what the row is called: a file name, or a matching line
    , relative : String -- where it lives: the path relative to the workspace
    , path : FilePath
    , line : Maybe Int
    }


{-| A look at the highlighted document: `excerpt` starts at `firstLine`
(1-based) and, for a search hit, holds the lines around it.
-}
type alias Peek =
    { path : FilePath
    , line : Maybe Int
    , title : String
    , modified : String
    , words : Int
    , lines : Int
    , firstLine : Int
    , excerpt : List String
    }


type alias Model =
    { opened : Maybe Mode
    , query : String
    , items : List Item -- for Files, everything; for Search, the current hits
    , active : Int
    , searchGeneration : Int -- the query the pending debounced search was for
    , peek : Maybe Peek
    , peekFor : Maybe ( FilePath, Maybe Int ) -- what the last peek was asked for
    , peekGeneration : Int
    }


init : Model
init =
    { opened = Nothing
    , query = ""
    , items = []
    , active = 0
    , searchGeneration = 0
    , peek = Nothing
    , peekFor = Nothing
    , peekGeneration = 0
    }


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
    { model | opened = Just wanted, query = "", active = 0, items = keepFilesFor wanted model, peek = Nothing, peekFor = Nothing }


close : Model -> Model
close model =
    { model | opened = Nothing, query = "", active = 0, items = keepFilesFor Files model, peek = Nothing, peekFor = Nothing }


{-| The file list survives closing and reopening; search hits do not, and
search never starts out showing files as if they were hits.
-}
keepFilesFor : Mode -> Model -> List Item
keepFilesFor wanted model =
    if wanted == Files && model.opened /= Just Search then
        model.items

    else
        []


setResults : List Item -> Model -> Model
setResults items model =
    { model | items = items, active = 0 }


setQuery : String -> Model -> Model
setQuery text model =
    { model | query = text, active = 0 }


{-| A peek that arrived; kept only if it is still for the highlighted row. -}
setPeek : Peek -> Model -> Model
setPeek peek model =
    if Just ( peek.path, peek.line ) == model.peekFor then
        { model | peek = Just peek }

    else
        model


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
            |> List.filterMap (\item -> matchScore text item.relative |> Maybe.map (\score -> ( score, item )))
            |> List.sortBy (\( score, item ) -> ( -score, String.length item.relative ))
            |> List.take resultLimit
            |> List.map Tuple.second


resultLimit : Int
resultLimit =
    50


matchScore : String -> String -> Maybe Int
matchScore text candidate =
    match text candidate |> Maybe.map Tuple.first


{-| How well `candidate` matches `text` and which of its characters did, or
Nothing if it does not match.

Every character of the query must appear in order. A character scores more
when it follows the previous match directly, and more again when it starts a
path segment or a word, so "mdplan" finds "docs/md/plan.md" ahead of a file
that merely contains those letters scattered about.

When the query occurs whole, that run is the match, starting at a segment or
word boundary when one of the occurrences does: "plan" in
"planning/plan.md" lights up the file name, not four letters of the folder.
Otherwise the match is the tightest window that holds the query in order.

-}
match : String -> String -> Maybe ( Int, List Int )
match text candidate =
    let
        needle =
            String.toLower (String.filter (\c -> c /= ' ') text)

        haystack =
            String.toLower candidate
    in
    if needle == "" then
        Just ( 0, [] )

    else
        case String.indexes needle haystack of
            first :: rest ->
                let
                    -- the last such occurrence: nearest the file name
                    start =
                        List.filter (startsSegment haystack) (first :: rest)
                            |> List.reverse
                            |> List.head
                            |> Maybe.withDefault first

                    positions =
                        List.range start (start + String.length needle - 1)
                in
                Just ( scorePositions haystack positions, positions )

            [] ->
                fuzzy (String.toList needle) (String.toList haystack)
                    |> Maybe.map (\positions -> ( scorePositions haystack positions, positions ))


startsSegment : String -> Int -> Bool
startsSegment haystack index =
    index == 0 || List.member (String.slice (index - 1) index haystack) boundaries


boundaries : List String
boundaries =
    [ "/", "-", "_", ".", " " ]


{-| The in-order positions of `needle` in `haystack` that score best, with the
file name's end preferred among equals.

Each candidate is a tight window: a forward scan finds where the query can
first end, a backward scan from there finds the latest start, and a forward
scan from that start picks the positions. The next candidate starts after the
previous one's start. A single forward scan would match "plan" in
"people/land/plan.md" as p-l-a-n across three folders.

-}
fuzzy : List Char -> List Char -> Maybe (List Int)
fuzzy needle haystack =
    let
        forward wanted chars index =
            case wanted of
                [] ->
                    Just []

                w :: ws ->
                    case chars of
                        [] ->
                            Nothing

                        c :: cs ->
                            if c == w then
                                forward ws cs (index + 1) |> Maybe.map ((::) index)

                            else
                                forward wanted cs (index + 1)

        window from =
            forward needle (List.drop from haystack) from
                |> Maybe.andThen
                    (\greedy ->
                        let
                            end =
                                List.foldl Basics.max 0 greedy

                            reversedHead =
                                List.reverse (List.take (end + 1) haystack)
                        in
                        forward (List.reverse needle) reversedHead 0
                            |> Maybe.map (\back -> end - List.foldl Basics.max 0 back)
                            |> Maybe.andThen (\start -> forward needle (List.drop start haystack) start)
                    )

        windows from found =
            case window from of
                Just positions ->
                    case positions of
                        start :: _ ->
                            windows (start + 1) (positions :: found)

                        [] ->
                            found

                Nothing ->
                    found

        haystackString =
            String.fromList haystack
    in
    windows 0 []
        |> List.sortBy (\positions -> ( negate (scorePositions haystackString positions), negate (Maybe.withDefault 0 (List.head positions)) ))
        |> List.head


scorePositions : String -> List Int -> Int
scorePositions haystack positions =
    let
        score position ( previous, total ) =
            ( position
            , total
                + 1
                + (if position == previous + 1 then
                    4

                   else
                    0
                  )
                + (if startsSegment haystack position then
                    3

                   else
                    0
                  )
            )
    in
    List.foldl score ( -2, 0 ) positions |> Tuple.second



-- MESSAGES


type Msg
    = Open Mode
    | Close
    | QueryChanged String
    | SearchDue Int
    | PeekDue Int
    | Step Int
    | Choose (Maybe Item)
    | ChooseActive
    | ChooseAndReveal
    | CopyRelativePath
    | CopyAbsolutePath
    | RevealInFinder
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
    | CmdDebouncePeek Int -- send `PeekDue` with this generation after `peekDelay`
    | CmdPeek FilePath (Maybe Int) -- preview this document, around this line
    | CmdReadFile FilePath (Maybe Int) Bool -- the line to put the caret on, and whether to reveal it in the sidebar regardless of the preference
    | CmdCopyText String
    | CmdRevealPath FilePath -- in the system file manager


{-| How long to wait before searching the workspace for what has been typed. -}
searchDelay : Float
searchDelay =
    200


{-| How long the cursor must rest on a row before its document is peeked at. -}
peekDelay : Float
peekDelay =
    60


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

        PeekDue generation ->
            case ( generation == model.peekGeneration, model.peekFor ) of
                ( True, Just ( path, line ) ) ->
                    ( model, [ CmdPeek path line ] )

                _ ->
                    ( model, [] )

        Step delta ->
            ( step delta model, [] )

        ChooseActive ->
            update (Choose (active model)) root model

        Choose item ->
            case item of
                Just chosen ->
                    ( close model, [ CmdReadFile chosen.path chosen.line False ] )

                Nothing ->
                    ( model, [] )

        ChooseAndReveal ->
            case active model of
                Just chosen ->
                    ( close model, [ CmdReadFile chosen.path chosen.line True ] )

                Nothing ->
                    ( model, [] )

        CopyRelativePath ->
            ( model, withActive model (\item -> CmdCopyText item.relative) )

        CopyAbsolutePath ->
            ( model, withActive model (\item -> CmdCopyText item.path) )

        RevealInFinder ->
            ( model, withActive model (\item -> CmdRevealPath item.path) )

        NoOp ->
            ( model, [] )


withActive : Model -> (Item -> OutCmd) -> List OutCmd
withActive model toCmd =
    active model |> Maybe.map (toCmd >> List.singleton) |> Maybe.withDefault []


{-| Ask for a peek at the highlighted row when it changed since the last one.
Main calls this after every message that could move the cursor or replace the
rows, so the peek follows the highlight wherever it came from.
-}
settle : Bool -> Model -> ( Model, List OutCmd )
settle peekEnabled model =
    let
        wanted =
            if peekEnabled && isOpen model then
                active model |> Maybe.map (\item -> ( item.path, item.line ))

            else
                Nothing
    in
    if wanted == model.peekFor then
        ( model, [] )

    else
        case wanted of
            Nothing ->
                ( { model | peek = Nothing, peekFor = Nothing }, [] )

            Just _ ->
                let
                    generation =
                        model.peekGeneration + 1
                in
                ( { model | peekFor = wanted, peekGeneration = generation }, [ CmdDebouncePeek generation ] )



-- VIEW


view : Bool -> Model -> Html Msg
view peekEnabled palette =
    let
        rows =
            results palette

        currentMode =
            Maybe.withDefault Files (mode palette)

        placeholderText =
            case currentMode of
                Search ->
                    "Search the workspace"

                Files ->
                    "Go to file"

        count =
            case currentMode of
                Files ->
                    String.fromInt (List.length rows) ++ " / " ++ String.fromInt (List.length palette.items)

                Search ->
                    case List.length rows of
                        1 ->
                            "1 hit"

                        n ->
                            String.fromInt n ++ " hits"

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
                (case currentMode of
                    Files ->
                        viewFileRow (query palette) item

                    Search ->
                        viewHitRow (query palette) item
                )
    in
    div [ class "palette-backdrop", attribute "data-testid" "palette", onClick Close ]
        [ div
            [ class "palette"
            , classList [ ( "with-peek", peekEnabled ) ]
            , stopPropagationOn "click" (D.succeed ( NoOp, True ))
            ]
            [ div [ class "palette-head" ]
                [ span [ class "palette-mode", attribute "data-testid" "palette-mode" ]
                    [ text
                        (case currentMode of
                            Files ->
                                "Files"

                            Search ->
                                "Search"
                        )
                    ]
                , input
                    [ class "palette-input"
                    , id inputId
                    , attribute "data-testid" "palette-input"
                    , attribute "aria-label" placeholderText
                    , placeholder placeholderText
                    , value (query palette)
                    , spellcheck False
                    , onInput QueryChanged
                    , preventDefaultOn "keydown" keyDecoder
                    ]
                    []
                , span [ class "palette-count", attribute "data-testid" "palette-count" ] [ text count ]
                ]
            , if List.isEmpty rows then
                div [ class "palette-empty" ] [ text "No results" ]

              else
                div [ class "palette-results", attribute "role" "listbox" ] (List.indexedMap row rows)
            , if peekEnabled then
                viewPeek palette

              else
                text ""
            , viewFooter currentMode
            ]
        ]


{-| The file name, with the extension quieter, and the folder beneath it. -}
viewFileRow : String -> Item -> List (Html Msg)
viewFileRow text_ item =
    let
        matched =
            match text_ item.relative |> Maybe.map (Tuple.second >> Set.fromList) |> Maybe.withDefault Set.empty

        ( folder, name ) =
            splitLast "/" item.relative

        nameStart =
            String.length item.relative - String.length name

        ( stem, extension ) =
            case List.reverse (String.indexes "." name) of
                dot :: _ ->
                    if dot > 0 then
                        ( String.left dot name, String.dropLeft dot name )

                    else
                        ( name, "" )

                [] ->
                    ( name, "" )
    in
    [ span [ class "palette-primary" ]
        [ span [] (highlight matched nameStart stem)
        , span [ class "palette-ext" ] (highlight matched (nameStart + String.length stem) extension)
        ]
    , span [ class "palette-hint" ] [ text "Open ", key "↵" ]
    , viewPath matched folder "" Nothing
    ]


{-| The matching line with the query picked out, and where it is beneath. -}
viewHitRow : String -> Item -> List (Html Msg)
viewHitRow text_ item =
    let
        needle =
            String.trim text_

        ( folder, name ) =
            splitLast "/" item.relative
    in
    [ span [ class "palette-primary palette-line" ] (highlightSubstring needle item.primary)
    , span [ class "palette-hint" ]
        [ text ("Open at line " ++ (item.line |> Maybe.map String.fromInt |> Maybe.withDefault "") ++ " "), key "↵" ]
    , viewPath Set.empty folder name item.line
    ]


{-| `folder/name:line`, where the folder gives way first: its start keeps the
ellipsis so the segments nearest the file stay readable.
-}
viewPath : Set Int -> String -> String -> Maybe Int -> Html Msg
viewPath matched folder name line =
    let
        ( parents, last ) =
            splitLast "/" folder

        tail =
            if name == "" then
                last

            else
                name

        parentsHtml =
            if name == "" then
                highlight matched 0 parents

            else
                [ text (String.join "/" (List.filter (\s -> s /= "") [ parents, last ])) ]

        tailHtml =
            if name == "" then
                highlight matched (String.length folder - String.length last) last

            else
                [ text name ]

        hasHead =
            if name == "" then
                parents /= ""

            else
                folder /= ""
    in
    span [ class "palette-secondary", attribute "data-testid" "palette-path" ]
        (List.concat
            [ if hasHead then
                [ span [ class "palette-path-head" ] parentsHtml, span [ class "palette-sep" ] [ text "/" ] ]

              else
                []
            , if tail == "" && not hasHead then
                [ span [ class "palette-path-tail palette-root" ] [ text "workspace root" ] ]

              else
                [ span [ class "palette-path-tail" ]
                    (tailHtml
                        ++ (case line of
                                Just n ->
                                    [ span [ class "palette-sep" ] [ text ":" ], text (String.fromInt n) ]

                                Nothing ->
                                    []
                           )
                    )
                ]
            ]
        )


splitLast : String -> String -> ( String, String )
splitLast separator s =
    case List.reverse (String.indexes separator s) of
        index :: _ ->
            ( String.left index s, String.dropLeft (index + 1) s )

        [] ->
            ( "", s )


{-| `s` as text with the characters at the matched positions (offset by where
`s` starts in the matched string) marked.
-}
highlight : Set Int -> Int -> String -> List (Html msg)
highlight matched offset s =
    let
        step_ ( index, char ) runs =
            let
                isMatch =
                    Set.member (offset + index) matched
            in
            case runs of
                ( wasMatch, chunk ) :: rest ->
                    if wasMatch == isMatch then
                        ( wasMatch, String.cons char chunk ) :: rest

                    else
                        ( isMatch, String.fromChar char ) :: runs

                [] ->
                    [ ( isMatch, String.fromChar char ) ]
    in
    List.foldl step_ [] (List.indexedMap Tuple.pair (String.toList s))
        |> List.reverse
        |> List.map
            (\( isMatch, chunk ) ->
                if isMatch then
                    Html.mark [ class "palette-match" ] [ text (String.reverse chunk) ]

                else
                    text (String.reverse chunk)
            )


highlightSubstring : String -> String -> List (Html msg)
highlightSubstring needle s =
    case ( needle, String.indexes (String.toLower needle) (String.toLower s) ) of
        ( "", _ ) ->
            [ text s ]

        ( _, index :: _ ) ->
            [ text (String.left index s)
            , Html.mark [ class "palette-match" ] [ text (String.slice index (index + String.length needle) s) ]
            , text (String.dropLeft (index + String.length needle) s)
            ]

        ( _, [] ) ->
            [ text s ]


viewPeek : Model -> Html Msg
viewPeek palette =
    div [ class "palette-peek", attribute "data-testid" "palette-peek" ]
        (case ( palette.peek, active palette ) of
            ( Just peek, Just item ) ->
                let
                    lineClass l =
                        if String.startsWith "#" l then
                            "heading"

                        else if String.startsWith "- " l || String.startsWith "* " l then
                            "list"

                        else if l == "---" then
                            "rule"

                        else
                            ""

                    excerptLine index l =
                        let
                            number =
                                peek.firstLine + index
                        in
                        div
                            [ classList
                                [ ( "palette-peek-line", True )
                                , ( "hit", Just number == peek.line )
                                , ( lineClass l, lineClass l /= "" )
                                ]
                            ]
                            [ text
                                (if l == "" then
                                    " "

                                 else
                                    l
                                )
                            ]
                in
                [ div [ class "palette-peek-title" ] [ text peek.title ]
                , div [ class "palette-peek-path" ] [ text item.relative ]
                , div [ class "palette-peek-meta" ]
                    [ span [] [ text "Modified ", Html.b [] [ text peek.modified ] ]
                    , span [] [ Html.b [] [ text (String.fromInt peek.words) ], text " words" ]
                    , span [] [ Html.b [] [ text (String.fromInt peek.lines) ], text " lines" ]
                    ]
                , div [ class "palette-peek-source" ] (List.indexedMap excerptLine peek.excerpt)
                ]

            ( _, Just item ) ->
                [ div [ class "palette-peek-title" ] [ text (baseName item.path) ]
                , div [ class "palette-peek-path" ] [ text item.relative ]
                ]

            _ ->
                [ div [ class "palette-peek-empty" ] [ text "Nothing to preview" ] ]
        )


viewFooter : Mode -> Html Msg
viewFooter currentMode =
    let
        action keys label =
            span [ class "palette-action" ] (List.map key keys ++ [ text label ])
    in
    div [ class "palette-footer", attribute "data-testid" "palette-footer" ]
        [ action [ "↑↓" ] "Move"
        , action [ "↵" ]
            (case currentMode of
                Files ->
                    "Open"

                Search ->
                    "Open at line"
            )
        , action [ "⌘↵" ] "Open and reveal"
        , action [ "⌘⇧C" ] "Copy path"
        , action [ "⌥⌘C" ] "Copy full path"
        , span [ class "palette-footer-end" ] [ action [ "esc" ] "Close" ]
        ]


key : String -> Html msg
key label =
    kbd [ class "palette-key" ] [ text label ]


keyDecoder : D.Decoder ( Msg, Bool )
keyDecoder =
    D.map5
        (\k meta ctrl shift alt -> { key = k, modifier = meta || ctrl, shift = shift, alt = alt })
        (D.field "key" D.string)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        |> D.andThen
            (\pressed ->
                let
                    chord =
                        ( pressed.key, ( pressed.modifier, pressed.shift, pressed.alt ) )
                in
                case chord of
                    ( "ArrowDown", _ ) ->
                        D.succeed ( Step 1, True )

                    ( "ArrowUp", _ ) ->
                        D.succeed ( Step -1, True )

                    ( "Enter", ( True, _, _ ) ) ->
                        D.succeed ( ChooseAndReveal, True )

                    ( "Enter", _ ) ->
                        D.succeed ( ChooseActive, True )

                    ( "Escape", _ ) ->
                        D.succeed ( Close, True )

                    ( "c", ( True, True, False ) ) ->
                        D.succeed ( CopyRelativePath, True )

                    ( "C", ( True, True, False ) ) ->
                        D.succeed ( CopyRelativePath, True )

                    ( "c", ( True, False, True ) ) ->
                        D.succeed ( CopyAbsolutePath, True )

                    ( "ç", ( True, False, True ) ) ->
                        -- macOS reports Option-C as the character it types
                        D.succeed ( CopyAbsolutePath, True )

                    ( "r", ( True, False, True ) ) ->
                        D.succeed ( RevealInFinder, True )

                    ( "®", ( True, False, True ) ) ->
                        D.succeed ( RevealInFinder, True )

                    _ ->
                        D.fail "not a palette key"
            )
