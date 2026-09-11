module FileTreeTest exposing (suite)

import Expect
import FileTree exposing (EditMode(..), Msg(..), OutCmd(..))
import Set
import Test exposing (Test, describe, test)
import Types exposing (FileEntry(..), FileType(..), fileEntryChildren, fileEntryPath)


file : String -> FileEntry
file path =
    FileEntry { name = Types.baseName path, path = path, fileType = File, children = Nothing }


dir : String -> FileEntry
dir path =
    FileEntry { name = Types.baseName path, path = path, fileType = Directory, children = Nothing }


{-| A workspace with two files and a collapsed subdirectory. -}
workspace : FileTree.Model
workspace =
    FileTree.handleFolderOpened "/notes" [ file "/notes/a.md", dir "/notes/sub", file "/notes/b.md" ] FileTree.init


rootChildren : FileTree.Model -> List String
rootChildren model =
    model.root |> Maybe.andThen fileEntryChildren |> Maybe.withDefault [] |> List.map fileEntryPath


{-| Every loaded path in the tree, depth first. -}
allPaths : FileTree.Model -> List String
allPaths model =
    let
        walk entry =
            fileEntryPath entry :: List.concatMap walk (Maybe.withDefault [] (fileEntryChildren entry))
    in
    Maybe.map walk model.root |> Maybe.withDefault []


suite : Test
suite =
    describe "File tree"
        [ stateSuite, keyboardSuite, fsEventSuite, editingSuite, revealSuite ]


editingSuite : Test
editingSuite =
    let
        run msgs model =
            List.foldl (\msg ( m, _ ) -> FileTree.update msg m) ( model, [] ) msgs

        typed name msgs model =
            run (msgs ++ [ EditNameChanged name, CommitEdit ]) model
    in
    describe "creating, renaming and deleting"
        [ test "a new file is created in the selected directory" <|
            \_ ->
                workspace
                    |> typed "new.md" [ StartEdit CreatingFile (Just "/notes/sub") ]
                    |> Tuple.second
                    |> Expect.equal [ CmdCreateFile "/notes/sub" "new.md" ]
        , test "a new file next to the selected file lands in its directory" <|
            \_ ->
                workspace
                    |> typed "new.md" [ StartEdit CreatingFile (Just "/notes/a.md") ]
                    |> Tuple.second
                    |> Expect.equal [ CmdCreateFile "/notes" "new.md" ]
        , test "with nothing selected a new file lands in the root" <|
            \_ ->
                workspace
                    |> typed "new.md" [ StartEdit CreatingFile Nothing ]
                    |> Tuple.second
                    |> Expect.equal [ CmdCreateFile "/notes" "new.md" ]
        , test "creating expands the target directory so the row is visible" <|
            \_ ->
                workspace
                    |> run [ StartEdit CreatingFile (Just "/notes/sub") ]
                    |> Tuple.first
                    |> .expanded
                    |> Set.member "/notes/sub"
                    |> Expect.equal True
        , test "a new folder emits the directory command" <|
            \_ ->
                workspace
                    |> typed "ideas" [ StartEdit CreatingDir (Just "/notes") ]
                    |> Tuple.second
                    |> Expect.equal [ CmdCreateDir "/notes" "ideas" ]
        , test "renaming sends the new name for the edited path" <|
            \_ ->
                workspace
                    |> typed "renamed.md" [ StartEdit (Renaming "/notes/a.md") (Just "/notes/a.md") ]
                    |> Tuple.second
                    |> Expect.equal [ CmdRename "/notes/a.md" "renamed.md" ]
        , test "renaming starts with the current name in the field" <|
            \_ ->
                workspace
                    |> run [ StartEdit (Renaming "/notes/a.md") (Just "/notes/a.md") ]
                    |> Tuple.first
                    |> .editing
                    |> Maybe.map .name
                    |> Expect.equal (Just "a.md")
        , test "an empty or unchanged name commits nothing" <|
            \_ ->
                Expect.equal
                    ( [], [] )
                    ( workspace |> typed "   " [ StartEdit CreatingFile (Just "/notes") ] |> Tuple.second
                    , workspace |> typed "a.md" [ StartEdit (Renaming "/notes/a.md") (Just "/notes/a.md") ] |> Tuple.second
                    )
        , test "cancelling drops the edit without a command" <|
            \_ ->
                workspace
                    |> run [ StartEdit CreatingFile (Just "/notes"), EditNameChanged "x.md", CancelEdit ]
                    |> (\( model, cmds ) -> Expect.equal ( Nothing, [] ) ( model.editing, cmds ))
        , test "committing clears the edit" <|
            \_ ->
                workspace
                    |> typed "new.md" [ StartEdit CreatingFile (Just "/notes") ]
                    |> Tuple.first
                    |> .editing
                    |> Expect.equal Nothing
        , test "trashing sends the path and needs no name" <|
            \_ ->
                workspace
                    |> FileTree.update (Trash "/notes/a.md")
                    |> Tuple.second
                    |> Expect.equal [ CmdTrash "/notes/a.md" ]
        , test "a rename of the open file moves selection to the new path" <|
            \_ ->
                workspace
                    |> FileTree.select "/notes/a.md"
                    |> FileTree.handleRenamed "/notes/a.md" "/notes/z.md"
                    |> (\m -> Expect.equal ( Just "/notes/z.md", Just "/notes/z.md" ) ( m.selected, m.focused ))
        ]


revealSuite : Test
revealSuite =
    let
        target =
            "/notes/sub/deep/c.md"

        loadSub =
            FileTree.handleDirContents "/notes/sub" [ dir "/notes/sub/deep" ]

        loadDeep =
            FileTree.handleDirContents "/notes/sub/deep" [ file target ]
    in
    describe "revealing a file from outside the tree"
        [ test "reveal expands and watches each collapsed ancestor, reads the first unloaded one, and selects the file" <|
            \_ ->
                FileTree.reveal target workspace
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( [ "/notes", "/notes/sub", "/notes/sub/deep" ]
                                , [ CmdWatchDir "/notes/sub", CmdWatchDir "/notes/sub/deep", CmdReadDir "/notes/sub" ]
                                , ( Just target, Just target, Just target )
                                )
                                ( Set.toList model.expanded
                                , cmds
                                , ( model.selected, model.focused, model.pendingReveal )
                                )
                       )
        , test "each arriving listing reads the next level, and the last one finishes the reveal" <|
            \_ ->
                let
                    ( afterSub, subCmds ) =
                        FileTree.reveal target workspace |> Tuple.first |> loadSub

                    ( afterDeep, deepCmds ) =
                        loadDeep afterSub
                in
                Expect.equal
                    ( ( Just target, [ CmdReadDir "/notes/sub/deep" ] ), ( Nothing, [] ), True )
                    ( ( afterSub.pendingReveal, subCmds ), ( afterDeep.pendingReveal, deepCmds ), List.member target (allPaths afterDeep) )
        , test "reveal into a loaded, open directory emits nothing and is not pending" <|
            \_ ->
                FileTree.update (Toggle "/notes/sub") workspace
                    |> Tuple.first
                    |> FileTree.handleDirContents "/notes/sub" [ file "/notes/sub/c.md" ]
                    |> Tuple.first
                    |> FileTree.reveal "/notes/sub/c.md"
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( [], Nothing, Just "/notes/sub/c.md" )
                                ( cmds, model.pendingReveal, model.selected )
                       )
        , test "reveal of a file outside the workspace only selects it" <|
            \_ ->
                FileTree.reveal "/elsewhere/x.md" workspace
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( workspace.expanded, [], Just "/elsewhere/x.md" )
                                ( model.expanded, cmds, model.selected )
                       )
        , test "re-reading a directory keeps what its subdirectories had loaded" <|
            \_ ->
                workspace
                    |> loadSub
                    |> Tuple.first
                    |> loadDeep
                    |> Tuple.first
                    |> loadSub
                    |> Tuple.first
                    |> allPaths
                    |> List.member target
                    |> Expect.equal True
        , test "opening another folder drops a pending reveal" <|
            \_ ->
                FileTree.reveal target workspace
                    |> Tuple.first
                    |> FileTree.handleFolderOpened "/other" []
                    |> .pendingReveal
                    |> Expect.equal Nothing
        ]


stateSuite : Test
stateSuite =
    describe "state"
        [ test "opening a folder resets selection and expands the root" <|
            \_ ->
                Expect.equal
                    ( Just "/notes", Nothing, Set.singleton "/notes" )
                    ( workspace.rootPath, workspace.selected, workspace.expanded )
        , test "selecting a file reads it, selects it, and focuses it" <|
            \_ ->
                FileTree.update (FileSelected "/notes/a.md") workspace
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( Just "/notes/a.md", Just "/notes/a.md", [ CmdReadFile "/notes/a.md" ] )
                                ( model.selected, model.focused, cmds )
                       )
        , test "expanding a directory reads and watches it, and takes focus" <|
            \_ ->
                FileTree.update (Toggle "/notes/sub") workspace
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( True, Just "/notes/sub", [ CmdReadDir "/notes/sub", CmdWatchDir "/notes/sub" ] )
                                ( Set.member "/notes/sub" model.expanded, model.focused, cmds )
                       )
        , test "collapsing a directory stops watching it" <|
            \_ ->
                FileTree.update (Toggle "/notes/sub") workspace
                    |> Tuple.first
                    |> FileTree.update (Toggle "/notes/sub")
                    |> (\( model, cmds ) ->
                            Expect.equal ( False, [ CmdUnwatchDir "/notes/sub" ] ) ( Set.member "/notes/sub" model.expanded, cmds )
                       )
        , test "directory contents populate the matching entry" <|
            \_ ->
                (FileTree.handleDirContents "/notes/sub" [ file "/notes/sub/c.md" ] workspace |> Tuple.first)
                    |> .root
                    |> Maybe.andThen fileEntryChildren
                    |> Maybe.withDefault []
                    |> List.filter (\e -> fileEntryPath e == "/notes/sub")
                    |> List.head
                    |> Maybe.andThen fileEntryChildren
                    |> Maybe.map (List.map fileEntryPath)
                    |> Expect.equal (Just [ "/notes/sub/c.md" ])
        , test "files opened from outside the tree become selected without a read command" <|
            \_ ->
                FileTree.select "/notes/b.md" workspace
                    |> (\m -> Expect.equal ( Just "/notes/b.md", Just "/notes/b.md" ) ( m.selected, m.focused ))
        , test "the open-folder button only emits the dialog command" <|
            \_ -> FileTree.update OpenFolder workspace |> Tuple.second |> Expect.equal [ CmdOpenFolder ]
        ]


keyboardSuite : Test
keyboardSuite =
    let
        focusedAfter msgs =
            List.foldl (\msg model -> FileTree.update msg model |> Tuple.first) workspace msgs |> .focused
    in
    describe "keyboard navigation"
        [ test "ArrowDown with no focus lands on the root" <|
            \_ -> focusedAfter [ FocusDown ] |> Expect.equal (Just "/notes")
        , test "ArrowDown walks visible rows in display order (directories first)" <|
            \_ -> focusedAfter [ FocusDown, FocusDown, FocusDown ] |> Expect.equal (Just "/notes/a.md")
        , test "ArrowUp from the first row stays put" <|
            \_ -> focusedAfter [ FocusDown, FocusUp ] |> Expect.equal (Just "/notes")
        , test "End and Home jump to the last and first rows" <|
            \_ ->
                Expect.equal
                    ( Just "/notes/b.md", Just "/notes" )
                    ( focusedAfter [ FocusLast ], focusedAfter [ FocusLast, FocusFirst ] )
        , test "ArrowRight on a collapsed directory expands it" <|
            \_ ->
                List.foldl (\msg model -> FileTree.update msg model |> Tuple.first) workspace [ FocusDown, FocusDown ]
                    |> FileTree.update FocusRight
                    |> (\( model, cmds ) ->
                            Expect.equal
                                ( True, [ CmdReadDir "/notes/sub", CmdWatchDir "/notes/sub" ] )
                                ( Set.member "/notes/sub" model.expanded, cmds )
                       )
        , test "ArrowLeft on an expanded directory collapses it" <|
            \_ ->
                List.foldl (\msg model -> FileTree.update msg model |> Tuple.first) workspace [ FocusDown, FocusDown, FocusRight ]
                    |> FileTree.update FocusLeft
                    |> Tuple.first
                    |> .expanded
                    |> Set.member "/notes/sub"
                    |> Expect.equal False
        , test "ArrowDown into a file selects and reads it" <|
            \_ ->
                List.foldl (\msg model -> FileTree.update msg model |> Tuple.first) workspace [ FocusDown, FocusDown ]
                    |> FileTree.update FocusDown
                    |> (\( model, cmds ) -> Expect.equal ( Just "/notes/a.md", [ CmdReadFile "/notes/a.md" ] ) ( model.selected, cmds ))
        , test "Enter on a focused directory toggles it" <|
            \_ ->
                List.foldl (\msg model -> FileTree.update msg model |> Tuple.first) workspace [ FocusDown, FocusDown ]
                    |> FileTree.update Activate
                    |> Tuple.first
                    |> .expanded
                    |> Set.member "/notes/sub"
                    |> Expect.equal True
        ]


fsEventSuite : Test
fsEventSuite =
    describe "filesystem events"
        [ test "additions are inserted once" <|
            \_ ->
                workspace
                    |> FileTree.handleFsEvent "add" "/notes/new.md"
                    |> FileTree.handleFsEvent "add" "/notes/new.md"
                    |> rootChildren
                    |> List.filter ((==) "/notes/new.md")
                    |> Expect.equal [ "/notes/new.md" ]
        , test "removals clear the matching entry" <|
            \_ ->
                workspace
                    |> FileTree.handleFsEvent "unlink" "/notes/a.md"
                    |> rootChildren
                    |> Expect.equal [ "/notes/sub", "/notes/b.md" ]
        , test "removing the selected file clears the selection and focus" <|
            \_ ->
                FileTree.update (FileSelected "/notes/a.md") workspace
                    |> Tuple.first
                    |> FileTree.handleFsEvent "unlink" "/notes/a.md"
                    |> (\m -> Expect.equal ( Nothing, Nothing ) ( m.selected, m.focused ))
        , test "removing a directory clears a selection inside it" <|
            \_ ->
                (FileTree.handleDirContents "/notes/sub" [ file "/notes/sub/c.md" ] workspace |> Tuple.first)
                    |> FileTree.update (FileSelected "/notes/sub/c.md")
                    |> Tuple.first
                    |> FileTree.handleFsEvent "unlinkDir" "/notes/sub"
                    |> .selected
                    |> Expect.equal Nothing
        , test "new directories appear and removed directories vanish" <|
            \_ ->
                workspace
                    |> FileTree.handleFsEvent "addDir" "/notes/docs"
                    |> FileTree.handleFsEvent "unlinkDir" "/notes/sub"
                    |> rootChildren
                    |> List.sort
                    |> Expect.equal [ "/notes/a.md", "/notes/b.md", "/notes/docs" ]
        , test "events for files outside the workspace are ignored" <|
            \_ ->
                workspace
                    |> FileTree.handleFsEvent "add" "/elsewhere/x.md"
                    |> rootChildren
                    |> Expect.equal (rootChildren workspace)
        ]
