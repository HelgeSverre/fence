module Types exposing
    ( DirtyState(..)
    , FileEntry(..)
    , FileType(..)
    , FilePath
    , fileEntryName
    , fileEntryPath
    , fileEntryType
    , fileEntryChildren
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
