module Types exposing
    ( DirtyState(..)
    , FileEntry(..)
    , FileType(..)
    , FilePath
    , baseName
    , fileEntryName
    , fileEntryPath
    , fileEntryType
    , fileEntryChildren
    , treeItemId
    )


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


{-| DOM id for a file-tree row. Shared so focus-after-navigation in Main
always targets the id FileTree renders.
-}
treeItemId : FilePath -> String
treeItemId path =
    "tree-item-" ++ String.replace "/" "-" path
