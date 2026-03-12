module FileTree exposing
    ( Model
    , Msg(..)
    , OutCmd(..)
    , init
    , update
    , view
    , handleDirContents
    , handleFolderOpened
    , handleFsEvent
    )

import Browser.Dom
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icon
import Json.Decode as D
import Set exposing (Set)
import Task
import Types exposing (..)


type alias Model =
    { root : Maybe FileEntry
    , rootPath : Maybe FilePath
    , expanded : Set FilePath
    , selected : Maybe FilePath
    , focused : Maybe FilePath
    }


type Msg
    = OpenFolder
    | Toggle FilePath
    | FileSelected FilePath
    | FocusUp
    | FocusDown
    | FocusLeft
    | FocusRight
    | Activate
    | FocusFirst
    | FocusLast
    | FocusedOn (Result Browser.Dom.Error ())


type OutCmd
    = CmdOpenFolder
    | CmdReadDir FilePath
    | CmdReadFile FilePath
    | CmdWatchDir FilePath
    | CmdUnwatchDir FilePath


init : Model
init =
    { root = Nothing
    , rootPath = Nothing
    , expanded = Set.empty
    , selected = Nothing
    , focused = Nothing
    }


update : Msg -> Model -> ( Model, List OutCmd )
update msg model =
    case msg of
        OpenFolder ->
            ( model, [ CmdOpenFolder ] )

        Toggle path ->
            if Set.member path model.expanded then
                ( { model | expanded = Set.remove path model.expanded }
                , [ CmdUnwatchDir path ]
                )
            else
                ( { model | expanded = Set.insert path model.expanded }
                , [ CmdReadDir path, CmdWatchDir path ]
                )

        FileSelected path ->
            ( { model | selected = Just path, focused = Just path }
            , [ CmdReadFile path ]
            )

        FocusUp ->
            let
                paths =
                    visiblePaths model
            in
            case model.focused of
                Nothing ->
                    moveFocusTo (List.head paths) model

                Just current ->
                    moveFocusTo (previousItem current paths) model

        FocusDown ->
            let
                paths =
                    visiblePaths model
            in
            case model.focused of
                Nothing ->
                    moveFocusTo (List.head paths) model

                Just current ->
                    moveFocusTo (nextItem current paths) model

        FocusLeft ->
            case model.focused of
                Nothing ->
                    ( model, [] )

                Just current ->
                    if isDirectory current model && Set.member current model.expanded then
                        -- Collapse expanded directory
                        update (Toggle current) model
                    else
                        -- Move to parent
                        moveFocusTo (parentOf current model) model

        FocusRight ->
            case model.focused of
                Nothing ->
                    ( model, [] )

                Just current ->
                    if isDirectory current model then
                        if Set.member current model.expanded then
                            -- Move to first child
                            let
                                paths =
                                    visiblePaths model
                            in
                            moveFocusTo (nextItem current paths) model
                        else
                            -- Expand collapsed directory
                            update (Toggle current) model
                    else
                        ( model, [] )

        Activate ->
            case model.focused of
                Nothing ->
                    ( model, [] )

                Just current ->
                    if isDirectory current model then
                        update (Toggle current) model
                    else
                        update (FileSelected current) model

        FocusFirst ->
            moveFocusTo (List.head (visiblePaths model)) model

        FocusLast ->
            let
                paths =
                    visiblePaths model
            in
            moveFocusTo (List.head (List.reverse paths)) model

        FocusedOn _ ->
            ( model, [] )


{-| Move focus to the given path. For files, also select and read them.
For directories, just move focus without opening.
-}
moveFocusTo : Maybe FilePath -> Model -> ( Model, List OutCmd )
moveFocusTo maybePath model =
    case maybePath of
        Nothing ->
            ( model, [] )

        Just path ->
            if isDirectory path model then
                ( { model | focused = Just path }, [] )
            else
                ( { model | focused = Just path, selected = Just path }
                , [ CmdReadFile path ]
                )



-- VISIBLE PATHS (flattened tree navigation order)


visiblePaths : Model -> List FilePath
visiblePaths model =
    case model.root of
        Nothing ->
            []

        Just root ->
            flattenEntry model.expanded root


flattenEntry : Set FilePath -> FileEntry -> List FilePath
flattenEntry expanded (FileEntry entry) =
    let
        path =
            entry.path

        isDir =
            entry.fileType == Directory

        isExpanded =
            Set.member path expanded
    in
    path
        :: (if isDir && isExpanded then
                entry.children
                    |> Maybe.withDefault []
                    |> List.filter isMarkdownOrDir
                    |> List.sortWith directoriesFirst
                    |> List.concatMap (flattenEntry expanded)
            else
                []
           )


directoriesFirst : FileEntry -> FileEntry -> Order
directoriesFirst a b =
    case ( fileEntryType a, fileEntryType b ) of
        ( Directory, File ) ->
            LT

        ( File, Directory ) ->
            GT

        _ ->
            compare (String.toLower (fileEntryName a)) (String.toLower (fileEntryName b))



-- NAVIGATION HELPERS


previousItem : FilePath -> List FilePath -> Maybe FilePath
previousItem current paths =
    previousItemHelp Nothing current paths


previousItemHelp : Maybe FilePath -> FilePath -> List FilePath -> Maybe FilePath
previousItemHelp prev current paths =
    case paths of
        [] ->
            Nothing

        x :: rest ->
            if x == current then
                prev
            else
                previousItemHelp (Just x) current rest


nextItem : FilePath -> List FilePath -> Maybe FilePath
nextItem current paths =
    case paths of
        [] ->
            Nothing

        x :: rest ->
            if x == current then
                List.head rest
            else
                nextItem current rest


isDirectory : FilePath -> Model -> Bool
isDirectory path model =
    case model.root of
        Nothing ->
            False

        Just root ->
            findEntryType path root == Just Directory


findEntryType : FilePath -> FileEntry -> Maybe FileType
findEntryType targetPath (FileEntry entry) =
    if entry.path == targetPath then
        Just entry.fileType
    else
        case entry.children of
            Just children ->
                List.filterMap (findEntryType targetPath) children
                    |> List.head

            Nothing ->
                Nothing


parentOf : FilePath -> Model -> Maybe FilePath
parentOf path model =
    let
        paths =
            visiblePaths model

        parent =
            dirName path
    in
    if List.member parent paths then
        Just parent
    else
        Nothing



-- TREE MANIPULATION (unchanged)


handleDirContents : FilePath -> List FileEntry -> Model -> Model
handleDirContents path entries model =
    case model.rootPath of
        Just rp ->
            if path == rp || String.startsWith (rp ++ "/") path then
                { model | root = Maybe.map (insertChildren path entries) model.root }

            else
                freshRoot path entries model

        Nothing ->
            freshRoot path entries model


handleFolderOpened : FilePath -> List FileEntry -> Model -> Model
handleFolderOpened path entries model =
    freshRoot path entries model


freshRoot : FilePath -> List FileEntry -> Model -> Model
freshRoot path entries model =
    let
        rootEntry =
            FileEntry
                { name = baseName path
                , path = path
                , fileType = Directory
                , children = Just entries
                }
    in
    { model
        | root = Just rootEntry
        , rootPath = Just path
        , expanded = Set.singleton path
        , selected = Nothing
        , focused = Nothing
    }


handleFsEvent : String -> FilePath -> Model -> Model
handleFsEvent event path model =
    case model.root of
        Nothing ->
            model

        Just root ->
            case event of
                "add" ->
                    let
                        entry =
                            FileEntry
                                { name = baseName path
                                , path = path
                                , fileType = File
                                , children = Nothing
                                }
                    in
                    { model | root = Just (addChild (dirName path) entry root) }

                "addDir" ->
                    let
                        entry =
                            FileEntry
                                { name = baseName path
                                , path = path
                                , fileType = Directory
                                , children = Just []
                                }
                    in
                    { model | root = Just (addChild (dirName path) entry root) }

                "unlink" ->
                    { model | root = Just (removeChild path root) }

                "unlinkDir" ->
                    { model | root = Just (removeChild path root) }

                _ ->
                    model


insertChildren : FilePath -> List FileEntry -> FileEntry -> FileEntry
insertChildren targetPath entries (FileEntry e) =
    if e.path == targetPath then
        FileEntry { e | children = Just entries }
    else
        case e.children of
            Just children ->
                FileEntry { e | children = Just (List.map (insertChildren targetPath entries) children) }

            Nothing ->
                FileEntry e


addChild : FilePath -> FileEntry -> FileEntry -> FileEntry
addChild parentPath newEntry (FileEntry e) =
    if e.path == parentPath then
        case e.children of
            Just children ->
                if List.any (\c -> fileEntryPath c == fileEntryPath newEntry) children then
                    FileEntry e
                else
                    FileEntry { e | children = Just (sortEntries (newEntry :: children)) }

            Nothing ->
                FileEntry e
    else
        case e.children of
            Just children ->
                FileEntry { e | children = Just (List.map (addChild parentPath newEntry) children) }

            Nothing ->
                FileEntry e


removeChild : FilePath -> FileEntry -> FileEntry
removeChild targetPath (FileEntry e) =
    case e.children of
        Just children ->
            FileEntry
                { e
                    | children =
                        Just
                            (children
                                |> List.filter (\c -> fileEntryPath c /= targetPath)
                                |> List.map (removeChild targetPath)
                            )
                }

        Nothing ->
            FileEntry e


sortEntries : List FileEntry -> List FileEntry
sortEntries entries =
    let
        dirs =
            List.filter (\en -> fileEntryType en == Directory) entries
                |> List.sortBy (\en -> String.toLower (fileEntryName en))

        files =
            List.filter (\en -> fileEntryType en == File) entries
                |> List.sortBy (\en -> String.toLower (fileEntryName en))
    in
    dirs ++ files


baseName : String -> String
baseName path =
    path
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path


dirName : String -> String
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



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "sidebar" ]
        [ div [ class "sidebar-header" ]
            [ span [ class "sidebar-title" ] [ text "Workspace" ]
            , button [ class "open-folder-btn", onClick OpenFolder ] [ Icon.folderPlus 16 ]
            ]
        , div [ class "sidebar-content" ]
            [ case model.root of
                Nothing ->
                    text ""

                Just root ->
                    ul
                        [ class "file-tree"
                        , attribute "role" "tree"
                        , attribute "aria-label" "File tree"
                        , preventDefaultOn "keydown" (treeKeyDecoder model)
                        ]
                        [ viewEntry model 0 root ]
            ]
        ]


treeKeyDecoder : Model -> D.Decoder ( Msg, Bool )
treeKeyDecoder _ =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                case key of
                    "ArrowUp" ->
                        D.succeed ( FocusUp, True )

                    "ArrowDown" ->
                        D.succeed ( FocusDown, True )

                    "ArrowLeft" ->
                        D.succeed ( FocusLeft, True )

                    "ArrowRight" ->
                        D.succeed ( FocusRight, True )

                    "Enter" ->
                        D.succeed ( Activate, True )

                    " " ->
                        D.succeed ( Activate, True )

                    "Home" ->
                        D.succeed ( FocusFirst, True )

                    "End" ->
                        D.succeed ( FocusLast, True )

                    _ ->
                        D.fail "not a tree key"
            )


treeItemId : FilePath -> String
treeItemId path =
    "tree-item-" ++ String.replace "/" "-" path


viewEntry : Model -> Int -> FileEntry -> Html Msg
viewEntry model depth entry =
    let
        entryPath =
            fileEntryPath entry

        entryName =
            fileEntryName entry

        isExpanded =
            Set.member entryPath model.expanded

        isSelected =
            model.selected == Just entryPath

        isFocused =
            model.focused == Just entryPath

        indent =
            style "padding-left" (String.fromInt (12 + depth * 16) ++ "px")

        isDir =
            fileEntryType entry == Directory
    in
    case fileEntryType entry of
        Directory ->
            li
                [ attribute "role" "treeitem"
                , attribute "aria-expanded"
                    (if isExpanded then
                        "true"
                     else
                        "false"
                    )
                , attribute "aria-selected"
                    (if isSelected then
                        "true"
                     else
                        "false"
                    )
                ]
                [ div
                    [ class "file-tree-item"
                    , classList
                        [ ( "selected", isSelected )
                        ]
                    , id (treeItemId entryPath)
                    , tabindex
                        (if isFocused then
                            0
                         else
                            -1
                        )
                    , indent
                    , onClick (Toggle entryPath)
                    ]
                    [ span [ class "icon" ]
                        [ if isExpanded then
                            Icon.chevronDown 16
                          else
                            Icon.chevronRight 16
                        ]
                    , span [ class "name" ] [ text entryName ]
                    ]
                , if isExpanded then
                    case fileEntryChildren entry of
                        Just children ->
                            ul
                                [ class "file-tree-children"
                                , attribute "role" "group"
                                ]
                                (children
                                    |> List.filter isMarkdownOrDir
                                    |> List.sortWith directoriesFirst
                                    |> List.map (viewEntry model (depth + 1))
                                )

                        Nothing ->
                            text ""
                  else
                    text ""
                ]

        File ->
            li
                [ attribute "role" "treeitem"
                , attribute "aria-selected"
                    (if isSelected then
                        "true"
                     else
                        "false"
                    )
                ]
                [ div
                    [ class "file-tree-item"
                    , classList
                        [ ( "selected", isSelected )
                        ]
                    , id (treeItemId entryPath)
                    , tabindex
                        (if isFocused then
                            0
                         else
                            -1
                        )
                    , indent
                    , onClick (FileSelected entryPath)
                    ]
                    [ span [ class "icon" ] [ Icon.fileText 16 ]
                    , span [ class "name" ] [ text entryName ]
                    ]
                ]


isMarkdownOrDir : FileEntry -> Bool
isMarkdownOrDir entry =
    case fileEntryType entry of
        Directory ->
            True

        File ->
            let
                name =
                    String.toLower (fileEntryName entry)
            in
            String.endsWith ".md" name
                || String.endsWith ".markdown" name
