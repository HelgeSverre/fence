module FileTreeTest exposing (suite)

import Expect
import FileTree
import Set
import Test exposing (Test, describe, test)
import Types exposing (FileEntry(..), FileType(..), fileEntryChildren, fileEntryPath)


file : String -> FileEntry
file path =
    FileEntry
        { name =
            path
                |> String.split "/"
                |> List.reverse
                |> List.head
                |> Maybe.withDefault path
        , path = path
        , fileType = File
        , children = Nothing
        }


suite : Test
suite =
    describe "File tree state"
        [ test "opening a folder resets selection and expands the root" <|
            \_ ->
                FileTree.handleFolderOpened "/notes" [ file "/notes/a.md" ] FileTree.init
                    |> (\model ->
                            Expect.equal
                                ( Just "/notes", Nothing, Set.singleton "/notes" )
                                ( model.rootPath, model.selected, model.expanded )
                       )
        , test "filesystem additions are inserted once" <|
            \_ ->
                let
                    model =
                        FileTree.handleFolderOpened "/notes" [] FileTree.init
                            |> FileTree.handleFsEvent "add" "/notes/a.md"
                            |> FileTree.handleFsEvent "add" "/notes/a.md"

                    children =
                        model.root
                            |> Maybe.andThen fileEntryChildren
                            |> Maybe.withDefault []
                in
                Expect.equal [ "/notes/a.md" ] (List.map fileEntryPath children)
        , test "filesystem removals clear the matching entry" <|
            \_ ->
                let
                    model =
                        FileTree.handleFolderOpened "/notes" [ file "/notes/a.md" ] FileTree.init
                            |> FileTree.handleFsEvent "unlink" "/notes/a.md"

                    children =
                        model.root
                            |> Maybe.andThen fileEntryChildren
                            |> Maybe.withDefault []
                in
                Expect.equal [] children
        ]
