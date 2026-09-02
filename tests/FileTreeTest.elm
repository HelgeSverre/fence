module FileTreeTest exposing (suite)

import Expect
import FileTree exposing (Msg(..), OutCmd(..))
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


suite : Test
suite =
    describe "File tree"
        [ stateSuite, keyboardSuite, fsEventSuite ]


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
                FileTree.handleDirContents "/notes/sub" [ file "/notes/sub/c.md" ] workspace
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
                FileTree.handleDirContents "/notes/sub" [ file "/notes/sub/c.md" ] workspace
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
