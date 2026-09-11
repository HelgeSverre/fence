module FileTree exposing
    ( EditMode(..)
    , Model
    , Msg(..)
    , OutCmd(..)
    , handleDirContents
    , handleFolderOpened
    , handleFsEvent
    , handleRenamed
    , init
    , reveal
    , select
    , startCommand
    , update
    , view
    )

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

    -- an in-place text field in the tree: the only way a name is entered,
    -- since Electron has no input dialog
    , editing : Maybe Edit

    -- a file revealed from outside the tree, held until its own directory's
    -- contents arrive and the row exists to scroll to
    , pendingReveal : Maybe FilePath
    }


type alias Edit =
    { mode : EditMode
    , parent : FilePath -- the directory the name will land in
    , name : String
    }


type EditMode
    = CreatingFile
    | CreatingDir
    | Renaming FilePath


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
    | StartEdit EditMode (Maybe FilePath)
    | EditNameChanged String
    | CommitEdit
    | CancelEdit
    | Trash FilePath
    | NoOp


type OutCmd
    = CmdOpenFolder
    | CmdReadDir FilePath
    | CmdReadFile FilePath
    | CmdWatchDir FilePath
    | CmdUnwatchDir FilePath
    | CmdCreateFile FilePath String
    | CmdCreateDir FilePath String
    | CmdRename FilePath String
    | CmdTrash FilePath
    | CmdFocusEditInput


init : Model
init =
    { root = Nothing
    , rootPath = Nothing
    , expanded = Set.empty
    , selected = Nothing
    , focused = Nothing
    , editing = Nothing
    , pendingReveal = Nothing
    }


update : Msg -> Model -> ( Model, List OutCmd )
update msg model =
    case msg of
        OpenFolder ->
            ( model, [ CmdOpenFolder ] )

        Toggle path ->
            -- Clicking a directory also moves keyboard focus there, so arrow
            -- keys continue from the clicked row instead of the top of the tree.
            if Set.member path model.expanded then
                ( { model | expanded = Set.remove path model.expanded, focused = Just path }
                , [ CmdUnwatchDir path ]
                )

            else
                ( { model | expanded = Set.insert path model.expanded, focused = Just path }
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

        StartEdit mode target ->
            case editParent mode target model of
                Nothing ->
                    ( model, [] )

                Just parent ->
                    let
                        -- the new row is rendered among the parent's children,
                        -- so the parent has to be expanded for it to be seen
                        needsContents =
                            not (Set.member parent model.expanded)
                    in
                    ( { model
                        | editing = Just { mode = mode, parent = parent, name = initialName mode }
                        , expanded = Set.insert parent model.expanded
                      }
                    , CmdFocusEditInput
                        :: (if needsContents then
                                [ CmdReadDir parent, CmdWatchDir parent ]

                            else
                                []
                           )
                    )

        EditNameChanged name ->
            ( { model | editing = Maybe.map (\edit -> { edit | name = name }) model.editing }, [] )

        CancelEdit ->
            ( { model | editing = Nothing }, [] )

        CommitEdit ->
            case model.editing of
                Nothing ->
                    ( model, [] )

                Just edit ->
                    ( { model | editing = Nothing }, commitCmds edit )

        Trash path ->
            ( model, [ CmdTrash path ] )

        NoOp ->
            ( model, [] )


{-| The command a finished edit produces. A blank name, or a rename that
changes nothing, is a no-op rather than an error from the main process.
-}
commitCmds : Edit -> List OutCmd
commitCmds edit =
    let
        name =
            String.trim edit.name
    in
    if name == "" then
        []

    else
        case edit.mode of
            CreatingFile ->
                [ CmdCreateFile edit.parent name ]

            CreatingDir ->
                [ CmdCreateDir edit.parent name ]

            Renaming path ->
                if name == baseName path then
                    []

                else
                    [ CmdRename path name ]


initialName : EditMode -> String
initialName mode =
    case mode of
        Renaming path ->
            baseName path

        _ ->
            ""


{-| Where a new name belongs: for a rename, the edited entry's own directory;
for a creation, the given directory, the given file's directory, or - with no
target - whatever is selected, falling back to the workspace root.
-}
editParent : EditMode -> Maybe FilePath -> Model -> Maybe FilePath
editParent mode target model =
    case mode of
        Renaming path ->
            Just (dirName path)

        _ ->
            case target |> orElse model.selected |> orElse model.focused of
                Just path ->
                    if isDirectory path model then
                        Just path

                    else
                        Just (dirName path)

                Nothing ->
                    model.rootPath


orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback primary =
    case primary of
        Just _ ->
            primary

        Nothing ->
            fallback


{-| A completed rename: follow it with the selection so the title bar and the
next save point at the new path. The tree itself is refreshed by chokidar.
-}
handleRenamed : FilePath -> FilePath -> Model -> Model
handleRenamed from to model =
    let
        follow path =
            if path == from then
                to

            else if String.startsWith (from ++ "/") path || String.startsWith (from ++ "\\") path then
                to ++ String.dropLeft (String.length from) path

            else
                path
    in
    { model
        | selected = Maybe.map follow model.selected
        , focused = Maybe.map follow model.focused
    }


{-| A command from the application menu or the tree's context menu.
-}
startCommand : String -> Maybe FilePath -> Model -> ( Model, List OutCmd )
startCommand name path model =
    case name of
        "newFile" ->
            update (StartEdit CreatingFile path) model

        "newFolder" ->
            update (StartEdit CreatingDir path) model

        "rename" ->
            case path of
                Just target ->
                    update (StartEdit (Renaming target) path) model

                Nothing ->
                    ( model, [] )

        "trash" ->
            case path of
                Just target ->
                    update (Trash target) model

                Nothing ->
                    ( model, [] )

        _ ->
            ( model, [] )


{-| Drop selection/focus that pointed at a path that no longer exists
(the path itself, or anything inside a removed directory).
-}
forget : FilePath -> Model -> Model
forget path model =
    let
        gone p =
            p == path || String.startsWith (path ++ "/") p

        clear =
            Maybe.andThen
                (\p ->
                    if gone p then
                        Nothing

                    else
                        Just p
                )
    in
    { model | selected = clear model.selected, focused = clear model.focused }


{-| Mark a file as the open one without reading it, for files opened from
outside the tree (CLI argument, Finder, "Open With").
-}
select : FilePath -> Model -> Model
select path model =
    { model | selected = Just path, focused = Just path }


{-| Select a file opened from outside the tree and expand every directory
above it. Listings load one level at a time, parent before child, because a
child's listing has nowhere to go until its parent's has arrived;
`pendingReveal` keeps the target until the chain completes, so Main can scroll
the row into view once it exists. Files outside the workspace are only
selected.
-}
reveal : FilePath -> Model -> ( Model, List OutCmd )
reveal path model =
    case model.rootPath of
        Just root ->
            if String.startsWith (root ++ "/") path then
                let
                    collapsed =
                        ancestorsWithin root path
                            |> List.filter (\dir -> not (Set.member dir model.expanded))

                    ( revealed, reads ) =
                        continueReveal path
                            { model
                                | selected = Just path
                                , focused = Just path
                                , expanded = List.foldl Set.insert model.expanded collapsed
                            }
                in
                ( revealed, List.map CmdWatchDir collapsed ++ reads )

            else
                ( select path model, [] )

        Nothing ->
            ( select path model, [] )


{-| Read the next unloaded directory on the way to a revealed file, or finish
the reveal when every ancestor is loaded.
-}
continueReveal : FilePath -> Model -> ( Model, List OutCmd )
continueReveal target model =
    let
        unloaded =
            case model.rootPath of
                Just root ->
                    ancestorsWithin root target
                        |> List.filter (\dir -> not (isLoaded dir model))
                        |> List.head

                Nothing ->
                    Nothing
    in
    case unloaded of
        Just dir ->
            ( { model | pendingReveal = Just target }, [ CmdReadDir dir ] )

        Nothing ->
            ( { model | pendingReveal = Nothing }, [] )


{-| The directories from the root down to the file's own directory, root first.
-}
ancestorsWithin : FilePath -> FilePath -> List FilePath
ancestorsWithin root path =
    dirName path
        |> String.dropLeft (String.length root)
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.foldl
            (\segment acc ->
                case acc of
                    parent :: _ ->
                        (parent ++ "/" ++ segment) :: acc

                    [] ->
                        acc
            )
            [ root ]
        |> List.reverse


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


{-| Whether a directory's listing has arrived. -}
isLoaded : FilePath -> Model -> Bool
isLoaded path model =
    let
        loaded (FileEntry entry) =
            if entry.path == path then
                entry.children /= Nothing

            else
                Maybe.withDefault [] entry.children |> List.any loaded
    in
    Maybe.map loaded model.root |> Maybe.withDefault False


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


handleDirContents : FilePath -> List FileEntry -> Model -> ( Model, List OutCmd )
handleDirContents path entries model =
    case model.rootPath of
        Just rp ->
            if path == rp || String.startsWith (rp ++ "/") path then
                let
                    loaded =
                        { model | root = Maybe.map (insertChildren path entries) model.root }
                in
                case model.pendingReveal of
                    Just target ->
                        continueReveal target loaded

                    Nothing ->
                        ( loaded, [] )

            else
                ( freshRoot path entries model, [] )

        Nothing ->
            ( freshRoot path entries model, [] )


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
        , editing = Nothing
        , pendingReveal = Nothing
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
                    forget path { model | root = Just (removeChild path root) }

                "unlinkDir" ->
                    forget path { model | root = Just (removeChild path root) }

                _ ->
                    model


insertChildren : FilePath -> List FileEntry -> FileEntry -> FileEntry
insertChildren targetPath entries (FileEntry e) =
    if e.path == targetPath then
        FileEntry { e | children = Just (List.map (keepLoaded (Maybe.withDefault [] e.children)) entries) }

    else
        case e.children of
            Just children ->
                FileEntry { e | children = Just (List.map (insertChildren targetPath entries) children) }

            Nothing ->
                FileEntry e


{-| A directory read again keeps whatever its subdirectories had already
loaded; directory reads finish in any order, so a parent's listing may land
after a child's.
-}
keepLoaded : List FileEntry -> FileEntry -> FileEntry
keepLoaded previous (FileEntry entry) =
    case ( entry.children, List.filter (\old -> fileEntryPath old == entry.path) previous ) of
        ( Nothing, (FileEntry old) :: _ ) ->
            FileEntry { entry | children = old.children }

        _ ->
            FileEntry entry


addChild : FilePath -> FileEntry -> FileEntry -> FileEntry
addChild parentPath newEntry (FileEntry e) =
    if e.path == parentPath then
        case e.children of
            Just children ->
                if List.any (\c -> fileEntryPath c == fileEntryPath newEntry) children then
                    FileEntry e

                else
                    FileEntry { e | children = Just (List.sortWith directoriesFirst (newEntry :: children)) }

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
    div [ class "sidebar", attribute "data-testid" "sidebar" ]
        [ div [ class "sidebar-header" ]
            [ span [ class "sidebar-title" ] [ text "Workspace" ] ]
        , div [ class "sidebar-content", id "sidebar-content" ]
            [ case model.root of
                Nothing ->
                    text ""

                Just root ->
                    ul
                        [ class "file-tree"
                        , attribute "data-testid" "file-tree"
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
                    , attribute "data-path" entryPath
                    , attribute "data-testid" "tree-dir"
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
                    , viewName model entryPath entryName
                    ]
                , if isExpanded then
                    case fileEntryChildren entry of
                        Just children ->
                            ul
                                [ class "file-tree-children"
                                , attribute "role" "group"
                                ]
                                (viewCreateRow model entryPath (depth + 1)
                                    ++ (children
                                            |> List.filter isMarkdownOrDir
                                            |> List.sortWith directoriesFirst
                                            |> List.map (viewEntry model (depth + 1))
                                       )
                                )

                        Nothing ->
                            ul [ class "file-tree-children", attribute "role" "group" ]
                                (viewCreateRow model entryPath (depth + 1))

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
                    , attribute "data-path" entryPath
                    , attribute "data-testid" "tree-file"
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
                    , viewName model entryPath entryName
                    ]
                ]


{-| An entry's label, or the rename field when this entry is being renamed. -}
viewName : Model -> FilePath -> String -> Html Msg
viewName model entryPath entryName =
    if renamingPath model == Just entryPath then
        nameInput model

    else
        span [ class "name" ] [ text entryName ]


{-| The row for a file or folder being created, rendered inside its parent. -}
viewCreateRow : Model -> FilePath -> Int -> List (Html Msg)
viewCreateRow model parent depth =
    case model.editing of
        Just edit ->
            if edit.parent == parent && creating edit.mode then
                [ li [ attribute "role" "treeitem" ]
                    [ div
                        [ class "file-tree-item editing"
                        , attribute "data-testid" "tree-new-row"
                        , style "padding-left" (String.fromInt (12 + depth * 16) ++ "px")
                        ]
                        [ span [ class "icon" ]
                            [ if edit.mode == CreatingDir then
                                Icon.chevronRight 16

                              else
                                Icon.fileText 16
                            ]
                        , nameInput model
                        ]
                    ]
                ]

            else
                []

        Nothing ->
            []


creating : EditMode -> Bool
creating mode =
    case mode of
        Renaming _ ->
            False

        _ ->
            True


renamingPath : Model -> Maybe FilePath
renamingPath model =
    case Maybe.map .mode model.editing of
        Just (Renaming path) ->
            Just path

        _ ->
            Nothing


nameInput : Model -> Html Msg
nameInput model =
    input
        [ class "tree-name-input"
        , id treeEditInputId
        , attribute "data-testid" "tree-name-input"
        , attribute "aria-label" "Name"
        , value (Maybe.map .name model.editing |> Maybe.withDefault "")
        , spellcheck False
        , attribute "autocomplete" "off"
        , onInput EditNameChanged
        , onBlur CommitEdit
        , Html.Events.custom "keydown" nameKeyDecoder

        -- a click inside the field must not reach the row underneath, which
        -- would select another file and tear the field down mid-edit
        , stopPropagationOn "click" (D.succeed ( NoOp, True ))
        ]
        []


{-| Keys typed in the name field. Every key stops propagating: the tree's own
handler treats Enter as "open the focused row" and the arrows as navigation,
which would fight the field the whole time it is open.
-}
nameKeyDecoder : D.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
nameKeyDecoder =
    D.field "key" D.string
        |> D.map
            (\key ->
                case key of
                    "Enter" ->
                        { message = CommitEdit, stopPropagation = True, preventDefault = True }

                    "Escape" ->
                        { message = CancelEdit, stopPropagation = True, preventDefault = True }

                    _ ->
                        { message = NoOp, stopPropagation = True, preventDefault = False }
            )


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
            -- keep in sync with MARKDOWN_EXTENSIONS in electron/fs-ops.js
            List.any (\ext -> String.endsWith ext name) [ ".md", ".markdown", ".mdown", ".mkd" ]
