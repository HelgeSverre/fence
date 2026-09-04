module MainTest exposing (suite)

import Editor
import Expect
import FileTree
import Json.Encode as E
import Main exposing (DragTarget(..), Msg(..))
import Test exposing (Test, describe, test)
import Types exposing (DirtyState(..))


{-| A fresh app with default settings (no persisted state).
-}
fresh : Main.Model
fresh =
    Tuple.first (Main.init (E.object []))


withFlags : List ( String, E.Value ) -> Main.Model
withFlags flags =
    Tuple.first (Main.init (E.object flags))


step : Msg -> Main.Model -> Main.Model
step msg model =
    Tuple.first (Main.update msg model)


steps : List Msg -> Main.Model -> Main.Model
steps msgs model =
    List.foldl step model msgs


fromElectron : String -> List ( String, E.Value ) -> Msg
fromElectron tag fields =
    FromElectron (E.object (( "tag", E.string tag ) :: fields))


{-| Open a file the way the main process does after a read. -}
openFile : String -> String -> Main.Model -> Main.Model
openFile path content =
    step
        (fromElectron "fileContent"
            [ ( "path", E.string path )
            , ( "content", E.string content )
            , ( "revision", E.string "rev-1" )
            , ( "dirty", E.bool False )
            ]
        )


{-| Replace the document the way a user would: select everything, then type.
-}
edit : String -> Main.Model -> Main.Model
edit content =
    step (EditorMsg Editor.SelectAll) >> step (EditorMsg (Editor.InsertText content))


keyDown : String -> Bool -> Msg
keyDown key meta =
    KeyDown key meta False False False


suite : Test
suite =
    describe "Main"
        [ initSuite, bindingSuite, dragSuite, layoutSuite, previewSuite, fileSuite, progressiveSuite ]


initSuite : Test
initSuite =
    describe "init"
        [ test "defaults when no state is persisted" <|
            \_ ->
                Expect.all
                    [ \_ -> fresh.sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.17
                    , \_ -> fresh.editorFraction |> Expect.within (Expect.Absolute 0.0001) 0.5
                    , \_ -> fresh.rightSidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.18
                    , \_ -> ( fresh.leftSidebarVisible, fresh.rightSidebarVisible, fresh.outlineMaxLevel ) |> Expect.equal ( True, False, 3 )
                    , \_ -> fresh.theme |> Expect.equal "github-dark"
                    ]
                    ()
        , test "persisted flags override the defaults" <|
            \_ ->
                let
                    model =
                        withFlags [ ( "theme", E.string "dracula" ), ( "sidebarFraction", E.float 0.3 ), ( "rightSidebarVisible", E.bool True ) ]
                in
                Expect.all
                    [ \_ -> ( model.theme, model.rightSidebarVisible ) |> Expect.equal ( "dracula", True )
                    , \_ -> model.sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.3
                    ]
                    ()
        , test "a malformed flag falls back to its default instead of failing init" <|
            \_ -> (withFlags [ ( "sidebarFraction", E.string "wide" ) ]).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.17
        , test "previewDelay grows with document size" <|
            \_ ->
                [ String.repeat 10 "x", String.repeat 300000 "x", String.repeat 1100000 "x" ]
                    |> List.map Main.previewDelay
                    |> Expect.equal [ 50, 150, 400 ]
        ]


bindingSuite : Test
bindingSuite =
    let
        cmd1 =
            { key = "1", meta = True, ctrl = False, shift = False, alt = False }
    in
    describe "key bindings"
        [ test "match is case-insensitive on the key" <|
            \_ -> Main.matchesBinding { cmd1 | key = "a" } "A" True False False False |> Expect.equal True
        , test "every modifier must match exactly" <|
            \_ ->
                [ Main.matchesBinding cmd1 "1" True False False False
                , Main.matchesBinding cmd1 "1" False True False False
                , Main.matchesBinding cmd1 "1" True False True False
                , Main.matchesBinding cmd1 "2" True False False False
                ]
                    |> Expect.equal [ True, False, False, False ]
        , test "labels use the macOS modifier glyphs in the conventional order" <|
            \_ ->
                [ cmd1, { key = "a", meta = False, ctrl = True, shift = True, alt = True } ]
                    |> List.map Main.keyBindingLabel
                    |> Expect.equal [ "⌘1", "⌃⌥⇧A" ]
        , test "the default shortcuts toggle the sidebars" <|
            \_ ->
                let
                    model =
                        steps [ keyDown "1" True, keyDown "3" True ] fresh
                in
                Expect.equal ( False, True ) ( model.leftSidebarVisible, model.rightSidebarVisible )
        , test "the shortcut without its modifier does nothing" <|
            \_ -> (step (keyDown "1" False) fresh).leftSidebarVisible |> Expect.equal True
        , test "Escape closes the settings dropdown" <|
            \_ -> steps [ ToggleSettings, keyDown "Escape" False ] fresh |> .settingsOpen |> Expect.equal False
        ]


dragSuite : Test
dragSuite =
    let
        -- windowWidth defaults to 1400, so 140px of travel is 0.1 of the window.
        drag target from to =
            steps [ DividerMouseDown target from, DividerMouseMove to, DividerMouseUp ]
    in
    describe "pane dividers"
        [ test "dragging the sidebar divider moves it by the window fraction travelled" <|
            \_ -> (drag DraggingSidebar 0 140 fresh).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.27
        , test "the sidebar is clamped between 8% and 40%" <|
            \_ ->
                Expect.all
                    [ \_ -> (drag DraggingSidebar 0 -2000 fresh).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.08
                    , \_ -> (drag DraggingSidebar 0 2000 fresh).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.4
                    ]
                    ()
        , test "the editor/preview split is clamped between 15% and 85%" <|
            \_ ->
                Expect.all
                    [ \_ -> (drag DraggingEditor 0 -5000 fresh).editorFraction |> Expect.within (Expect.Absolute 0.0001) 0.15
                    , \_ -> (drag DraggingEditor 0 5000 fresh).editorFraction |> Expect.within (Expect.Absolute 0.0001) 0.85
                    ]
                    ()
        , test "the editor split is measured against the region between the sidebars" <|
            \_ ->
                -- Region is 1400 * (1 - 0.17) = 1162px wide; 116.2px of travel is 0.1 of it.
                (drag DraggingEditor 0 116.2 fresh).editorFraction |> Expect.within (Expect.Absolute 0.0001) 0.6
        , test "dragging the outline divider left widens the outline" <|
            \_ -> (drag DraggingRightSidebar 500 360 fresh).rightSidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.28
        , test "mouse movement without a drag in progress is ignored" <|
            \_ -> (step (DividerMouseMove 900) fresh).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.17
        , test "releasing the mouse ends the drag" <|
            \_ -> (drag DraggingSidebar 0 10 fresh).drag |> Expect.equal Nothing
        , test "double-clicking a divider restores its default" <|
            \_ ->
                drag DraggingSidebar 0 140 fresh
                    |> step (DividerDoubleClick DraggingSidebar)
                    |> .sidebarFraction
                    |> Expect.within (Expect.Absolute 0.0001) 0.17
        ]


layoutSuite : Test
layoutSuite =
    describe "layout settings"
        [ test "outline depth is clamped to H1..H6" <|
            \_ ->
                Expect.equal
                    ( 1, 6 )
                    ( (step (SetOutlineMaxLevel 0) fresh).outlineMaxLevel, (step (SetOutlineMaxLevel 9) fresh).outlineMaxLevel )
        , test "toggling settings opens and closes the dropdown" <|
            \_ ->
                Expect.equal
                    ( True, False )
                    ( (step ToggleSettings fresh).settingsOpen, (steps [ ToggleSettings, CloseSettings ] fresh).settingsOpen )
        , test "theme and font selections are stored" <|
            \_ ->
                steps [ SetTheme "dracula", SetFont "Hack" ] fresh
                    |> (\m -> Expect.equal ( "dracula", "Hack" ) ( m.theme, m.font ))
        , test "a window resize updates the width used for drag maths" <|
            \_ -> (step (WindowResized 800 600) fresh).windowWidth |> Expect.within (Expect.Absolute 0.0001) 800
        ]


previewSuite : Test
previewSuite =
    describe "preview debounce"
        [ test "each edit bumps the debounce generation" <|
            \_ -> (edit "a" fresh |> edit "ab").debounceGeneration |> Expect.equal 2
        , test "a stale parse is discarded" <|
            \_ ->
                let
                    model =
                        fresh |> edit "# One" |> edit "# Two" |> step (DebouncedParse 1)
                in
                List.map .text model.outline |> Expect.equal []
        , test "the current parse updates the outline" <|
            \_ ->
                let
                    model =
                        fresh |> edit "# One" |> edit "# Two" |> step (DebouncedParse 2)
                in
                List.map .text model.outline |> Expect.equal [ "Two" ]
        , test "a debounced parse reuses cached chunks for unchanged sections" <|
            \_ ->
                let
                    model =
                        fresh |> edit "# A\n\nx\n\n# B\n\ny" |> step (DebouncedParse 1) |> edit "# A\n\nx\n\n# B\n\nz" |> step (DebouncedParse 2)
                in
                List.map .text model.outline |> Expect.equal [ "A", "B" ]
        ]


fileSuite : Test
fileSuite =
    let
        opened =
            openFile "/notes/a.md" "# Title\n\ntext" fresh
    in
    describe "file lifecycle"
        [ test "receiving file content loads the editor, outline, and tree selection" <|
            \_ ->
                Expect.equal
                    ( "# Title\n\ntext", [ "Title" ], Just "/notes/a.md" )
                    ( opened.editor.content, List.map .text opened.outline, opened.fileTree.selected )
        , test "opening a file resets any pending close-after-save" <|
            \_ -> opened.closeAfterSave |> Expect.equal False
        , test "Cmd+S with a file open starts a save of the current content" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (keyDown "s" True)
                    |> .savingContent
                    |> Expect.equal (Just "changed")
        , test "Cmd+S with nothing open is a no-op" <|
            \_ -> (step (keyDown "s" True) fresh).savingContent |> Expect.equal Nothing
        , test "a second save while one is in flight is ignored" <|
            \_ ->
                opened
                    |> edit "one"
                    |> step (keyDown "s" True)
                    |> edit "two"
                    |> step (keyDown "s" True)
                    |> .savingContent
                    |> Expect.equal (Just "one")
        , test "a save acknowledgement cleans the document and clears the in-flight marker" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (keyDown "s" True)
                    |> step (fromElectron "fileSaved" [ ( "path", E.string "/notes/a.md" ), ( "revision", E.string "rev-2" ) ])
                    |> (\m -> Expect.equal ( Clean, Nothing, Just "rev-2" ) ( m.editor.dirtyState, m.savingContent, m.editor.revision ))
        , test "a save acknowledgement for a different file is ignored" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (fromElectron "fileSaved" [ ( "path", E.string "/notes/other.md" ), ( "revision", E.string "rev-9" ) ])
                    |> .editor
                    |> .dirtyState
                    |> Expect.equal Dirty
        , test "edits made during a save keep the document dirty after the acknowledgement" <|
            \_ ->
                opened
                    |> edit "one"
                    |> step (keyDown "s" True)
                    |> edit "two"
                    |> step (fromElectron "fileSaved" [ ( "path", E.string "/notes/a.md" ), ( "revision", E.string "rev-2" ) ])
                    |> .editor
                    |> .dirtyState
                    |> Expect.equal Dirty
        , test "closing with unsaved changes saves first and remembers to close" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (fromElectron "saveAndClose" [])
                    |> (\m -> Expect.equal ( True, Just "changed" ) ( m.closeAfterSave, m.savingContent ))
        , test "a completed save-and-close leaves no pending close behind" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (fromElectron "saveAndClose" [])
                    |> step (fromElectron "fileSaved" [ ( "path", E.string "/notes/a.md" ), ( "revision", E.string "rev-2" ) ])
                    |> (\m -> Expect.equal ( False, Nothing, Clean ) ( m.closeAfterSave, m.savingContent, m.editor.dirtyState ))
        , test "cancelling the save dialog abandons the pending close" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (fromElectron "saveAndClose" [])
                    |> step (fromElectron "saveCancelled" [])
                    |> (\m -> Expect.equal ( False, Nothing ) ( m.closeAfterSave, m.savingContent ))
        , test "a write error surfaces a banner and abandons the pending close" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (fromElectron "saveAndClose" [])
                    |> step (fromElectron "error" [ ( "message", E.string "disk full" ) ])
                    |> (\m -> Expect.equal ( Just "disk full", False, Nothing ) ( m.errorMessage, m.closeAfterSave, m.savingContent ))
        , test "dismissing the banner clears it" <|
            \_ ->
                fresh
                    |> step (fromElectron "error" [ ( "message", E.string "oops" ) ])
                    |> step DismissError
                    |> .errorMessage
                    |> Expect.equal Nothing
        , test "an external change to a dirty document does not discard edits" <|
            \_ ->
                opened
                    |> edit "unsaved"
                    |> step (fromElectron "fsEvent" [ ( "event", E.string "change" ), ( "path", E.string "/notes/a.md" ) ])
                    |> .editor
                    |> .content
                    |> Expect.equal "unsaved"
        , test "a malformed port message is ignored" <|
            \_ -> step (FromElectron (E.string "garbage")) opened |> .editor |> .content |> Expect.equal "# Title\n\ntext"
        ]



progressiveSuite : Test
progressiveSuite =
    let
        bigDoc =
            -- 40 sections, ~2000 lines: big enough for the parse to be progressive
            List.range 1 40 |> List.map (\i -> "# Section " ++ String.fromInt i ++ "\n\n" ++ String.repeat 50 "some words on a line\n") |> String.join "\n"

        opened =
            openFile "/notes/big.md" bigDoc fresh

        headings m =
            List.length m.outline
    in
    describe "progressive rendering of a large document"
        [ test "opening renders the first screen and leaves the rest pending" <|
            \_ -> ( headings opened < 40, opened.parseProgress /= Nothing ) |> Expect.equal ( True, True )
        , test "the first animation frame after content only lets it paint" <|
            \_ -> step Frame opened |> headings |> Expect.equal (headings opened)
        , test "the following frame does a parse step" <|
            \_ -> steps [ Frame, Frame ] opened |> headings |> Expect.greaterThan (headings opened)
        , test "frames keep alternating paint and work until everything is rendered" <|
            \_ -> steps (List.repeat 60 Frame) opened |> (\m -> ( headings m, m.parseProgress )) |> Expect.equal ( 40, Nothing )
        , test "a step for a stale generation is ignored" <|
            \_ -> step (ParseStep (opened.debounceGeneration - 1)) opened |> headings |> Expect.equal (headings opened)
        , test "an edit during the fill-in restarts the parse against the cache" <|
            \_ ->
                opened
                    |> steps [ Frame, Frame ]
                    |> edit (bigDoc ++ "\n\n# Extra")
                    |> step (DebouncedParse (opened.debounceGeneration + 1))
                    |> steps (List.repeat 60 Frame)
                    |> headings
                    |> Expect.equal 41
        ]
