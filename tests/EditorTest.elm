module EditorTest exposing (suite)

import Editor
import Expect
import Test exposing (Test, describe, test)
import Types exposing (DirtyState(..))


suite : Test
suite =
    describe "Editor state"
        [ test "opened files retain their disk revision" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "hello" "rev-1" False
                    |> (\model ->
                            Expect.equal
                                ( Just "rev-1", Clean )
                                ( model.revision, model.dirtyState )
                       )
        , test "recovered drafts open dirty" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "recovered" "rev-1" True
                    |> .dirtyState
                    |> Expect.equal Dirty
        , test "a save acknowledgement does not clean newer edits" <|
            \_ ->
                Editor.init
                    |> Editor.setContent "/notes/a.md" "one" "rev-1" False
                    |> Editor.update (Editor.ContentChanged "two")
                    |> Editor.update (Editor.ContentChanged "three")
                    |> Editor.markSaved "two" "rev-2"
                    |> (\model ->
                            Expect.equal
                                ( Dirty, Just "rev-2", "three" )
                                ( model.dirtyState, model.revision, model.content )
                       )
        ]
