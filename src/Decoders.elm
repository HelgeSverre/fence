module Decoders exposing
    ( FileContentPayload
    , dirEntriesDecoder
    , fileContentDecoder
    , fileEntryDecoder
    , fileItemDecoder
    , fileSavedDecoder
    , fileTypeDecoder
    , fsEventDecoder
    , renamedDecoder
    , searchResultsDecoder
    , treeCommandDecoder
    )

{-| Decoders for the payloads the main process sends over `fromElectron`.
-}

import Json.Decode as D
import Palette
import Types exposing (..)


fileEntryDecoder : D.Decoder FileEntry
fileEntryDecoder =
    D.map4
        (\name path ft children ->
            FileEntry
                { name = name
                , path = path
                , fileType = ft
                , children = children
                }
        )
        (D.field "name" D.string)
        (D.field "path" D.string)
        (D.field "fileType" fileTypeDecoder)
        (D.maybe (D.field "children" (D.lazy (\_ -> D.list fileEntryDecoder))))


fileTypeDecoder : D.Decoder FileType
fileTypeDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "directory" ->
                        D.succeed Directory

                    "file" ->
                        D.succeed File

                    _ ->
                        D.fail ("Unknown file type: " ++ s)
            )


dirEntriesDecoder : D.Decoder ( FilePath, List FileEntry )
dirEntriesDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "entries" (D.list fileEntryDecoder))


type alias FileContentPayload =
    { path : FilePath
    , content : String
    , revision : String
    , dirty : Bool
    , line : Maybe Int -- 1-based line to put the caret on, for search results
    }


fileContentDecoder : D.Decoder FileContentPayload
fileContentDecoder =
    D.map5 FileContentPayload
        (D.field "path" D.string)
        (D.field "content" D.string)
        (D.field "revision" D.string)
        (D.field "dirty" D.bool)
        (D.maybe (D.field "line" D.int))


fileSavedDecoder : D.Decoder ( FilePath, String )
fileSavedDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "revision" D.string)


fileItemDecoder : D.Decoder Palette.Item
fileItemDecoder =
    D.map2
        (\path relative -> { primary = baseName path, secondary = relative, path = path, line = Nothing })
        (D.field "path" D.string)
        (D.field "relative" D.string)


searchResultsDecoder : D.Decoder ( String, List Palette.Item )
searchResultsDecoder =
    D.map2 Tuple.pair
        (D.field "query" D.string)
        (D.field "hits"
            (D.list
                (D.map4
                    (\path relative line text ->
                        { primary = String.trim text
                        , secondary = relative ++ ":" ++ String.fromInt line
                        , path = path
                        , line = Just line
                        }
                    )
                    (D.field "path" D.string)
                    (D.field "relative" D.string)
                    (D.field "line" D.int)
                    (D.field "text" D.string)
                )
            )
        )


treeCommandDecoder : D.Decoder ( String, Maybe FilePath )
treeCommandDecoder =
    D.map2 Tuple.pair
        (D.field "command" D.string)
        (D.maybe (D.field "path" D.string))


renamedDecoder : D.Decoder ( FilePath, FilePath )
renamedDecoder =
    D.map2 Tuple.pair
        (D.field "from" D.string)
        (D.field "path" D.string)


fsEventDecoder : D.Decoder ( String, FilePath )
fsEventDecoder =
    D.map2 Tuple.pair
        (D.field "event" D.string)
        (D.field "path" D.string)

