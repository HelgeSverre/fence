module Types exposing
    ( DirtyState(..)
    , FileEntry(..)
    , FileType(..)
    , FilePath
    , KeyBinding
    , baseName
    , dirName
    , encodeKeyBinding
    , fileEntryName
    , fileEntryPath
    , fileEntryType
    , fileEntryChildren
    , keyBindingDecoder
    , keyBindingLabel
    , matchesBinding
    , treeEditInputId
    , treeItemId
    )

import Json.Decode as D
import Json.Encode as E


type alias FilePath =
    String


type FileType
    = File
    | Directory


type DirtyState
    = Clean
    | Dirty


type FileEntry
    = FileEntry
        { name : String
        , path : FilePath
        , fileType : FileType
        , children : Maybe (List FileEntry)
        }


fileEntryName : FileEntry -> String
fileEntryName (FileEntry e) =
    e.name


fileEntryPath : FileEntry -> FilePath
fileEntryPath (FileEntry e) =
    e.path


fileEntryType : FileEntry -> FileType
fileEntryType (FileEntry e) =
    e.fileType


fileEntryChildren : FileEntry -> Maybe (List FileEntry)
fileEntryChildren (FileEntry e) =
    e.children


baseName : FilePath -> String
baseName path =
    path
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path


{-| The directory holding a path: what the file tree keys its entries by, and
the base a document's relative links resolve against. Absolute, no trailing
slash, and "/" for a path at the root.
-}
dirName : FilePath -> FilePath
dirName path =
    let
        parts =
            String.split "/" path
                |> List.filter (not << String.isEmpty)
    in
    case List.reverse parts of
        _ :: rest ->
            "/" ++ String.join "/" (List.reverse rest)

        [] ->
            "/"


{-| DOM id for a file-tree row. Shared so focus-after-navigation in Main
always targets the id FileTree renders.
-}
treeItemId : FilePath -> String
treeItemId path =
    "tree-item-" ++ String.replace "/" "-" path


{-| DOM id of the tree's inline name field, so Main can focus it when an
edit starts.
-}
treeEditInputId : String
treeEditInputId =
    "tree-edit-input"


{-| A keyboard shortcut. `key` is the `event.key` value (e.g. "1"); the
booleans capture which modifiers must be held.
-}
type alias KeyBinding =
    { key : String
    , meta : Bool
    , ctrl : Bool
    , shift : Bool
    , alt : Bool
    }


keyBindingDecoder : D.Decoder KeyBinding
keyBindingDecoder =
    D.map5 KeyBinding
        (D.field "key" D.string)
        (D.field "meta" D.bool)
        (D.field "ctrl" D.bool)
        (D.field "shift" D.bool)
        (D.field "alt" D.bool)


encodeKeyBinding : KeyBinding -> E.Value
encodeKeyBinding binding =
    E.object
        [ ( "key", E.string binding.key )
        , ( "meta", E.bool binding.meta )
        , ( "ctrl", E.bool binding.ctrl )
        , ( "shift", E.bool binding.shift )
        , ( "alt", E.bool binding.alt )
        ]


{-| Does an actual keydown (key + modifier flags) match a configured binding?
-}
matchesBinding : KeyBinding -> String -> Bool -> Bool -> Bool -> Bool -> Bool
matchesBinding binding key meta ctrl shift alt =
    (String.toLower binding.key == String.toLower key)
        && (binding.meta == meta)
        && (binding.ctrl == ctrl)
        && (binding.shift == shift)
        && (binding.alt == alt)


{-| Human-readable label for a binding, e.g. "⌘1" or "⇧⌥A".
-}
keyBindingLabel : KeyBinding -> String
keyBindingLabel binding =
    let
        mods =
            [ ( binding.ctrl, "⌃" )
            , ( binding.alt, "⌥" )
            , ( binding.shift, "⇧" )
            , ( binding.meta, "⌘" )
            ]
                |> List.filter Tuple.first
                |> List.map Tuple.second
                |> String.concat

        keyLabel =
            if String.length binding.key == 1 then
                String.toUpper binding.key

            else
                binding.key
    in
    mods ++ keyLabel

