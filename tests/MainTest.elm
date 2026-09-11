module MainTest exposing (suite)

import Editor
import Expect
import FileTree
import Json.Encode as E
import Main exposing (DragTarget(..), LayoutMode(..), Msg(..))
import Preferences exposing (Picker(..))
import Set
import Settings
import Test exposing (Test, describe, test)
import Types exposing (DirtyState(..), keyBindingLabel, matchesBinding)


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


{-| A workspace at /notes with a collapsed sub directory, as the main process reports it. -}
withWorkspace : Main.Model -> Main.Model
withWorkspace =
    let
        entry name path fileType =
            E.object [ ( "name", E.string name ), ( "path", E.string path ), ( "fileType", E.string fileType ) ]
    in
    step
        (fromElectron "folderOpened"
            [ ( "path", E.string "/notes" )
            , ( "entries", E.list identity [ entry "a.md" "/notes/a.md" "file", entry "sub" "/notes/sub" "directory" ] )
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
        [ layoutModeSuite, initSuite, bindingSuite, dragSuite, layoutSuite, settingsSuite, previewSuite, fileSuite, progressiveSuite, reloadSuite ]


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
                    , \_ -> fresh.preferences.theme |> Expect.equal "github-dark"
                    ]
                    ()
        , test "persisted flags override the defaults" <|
            \_ ->
                let
                    model =
                        withFlags [ ( "theme", E.string "dracula" ), ( "sidebarFraction", E.float 0.3 ), ( "rightSidebarVisible", E.bool True ) ]
                in
                Expect.all
                    [ \_ -> ( model.preferences.theme, model.rightSidebarVisible ) |> Expect.equal ( "dracula", True )
                    , \_ -> model.sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.3
                    ]
                    ()
        , test "a malformed flag falls back to its default instead of failing init" <|
            \_ -> (withFlags [ ( "sidebarFraction", E.string "wide" ) ]).sidebarFraction |> Expect.within (Expect.Absolute 0.0001) 0.17
        , test "soft wrap defaults on and accepts only a persisted Boolean" <|
            \_ ->
                Expect.equal [ True, False, True ]
                    [ fresh.editor.softWrap
                    , (withFlags [ ( "softWrap", E.bool False ) ]).editor.softWrap
                    , (withFlags [ ( "softWrap", E.string "false" ) ]).editor.softWrap
                    ]
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
            \_ -> matchesBinding { cmd1 | key = "a" } "A" True False False False |> Expect.equal True
        , test "every modifier must match exactly" <|
            \_ ->
                [ matchesBinding cmd1 "1" True False False False
                , matchesBinding cmd1 "1" False True False False
                , matchesBinding cmd1 "1" True False True False
                , matchesBinding cmd1 "2" True False False False
                ]
                    |> Expect.equal [ True, False, False, False ]
        , test "labels use the macOS modifier glyphs in the conventional order" <|
            \_ ->
                [ cmd1, { key = "a", meta = False, ctrl = True, shift = True, alt = True } ]
                    |> List.map keyBindingLabel
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
                steps [ SetPreference (\p -> { p | theme = "dracula" }), SetPreference (Preferences.select EditorFontPicker "Hack") ] fresh
                    |> (\m -> Expect.equal ( "dracula", "Hack" ) ( m.preferences.theme, m.preferences.editorFont ))
        , test "a window resize updates the width used for drag maths" <|
            \_ -> (step (WindowResized 800 600) fresh).windowWidth |> Expect.within (Expect.Absolute 0.0001) 800
        ]


settingsSuite : Test
settingsSuite =
    let
        opened =
            step ToggleSettings fresh

        values model =
            List.map Tuple.first (Settings.visibleSettingsOptions model)
    in
    describe "settings pickers"
        [ test "soft wrap updates both the editor and the persisted copy" <|
            \_ ->
                step (SetSoftWrap False) fresh
                    |> (\m -> Expect.equal ( False, False ) ( m.editor.softWrap, m.preferences.softWrap ))
        , test "opening settings leaves every picker collapsed" <|
            \_ -> opened.expandedPicker |> Expect.equal Nothing
        , test "the filter narrows the expanded picker's options" <|
            \_ ->
                opened
                    |> steps [ ExpandPicker (Just EditorFontPicker), PickerFilterChanged "plex" ]
                    |> values
                    |> Expect.equal [ "IBM Plex Mono" ]
        , test "expanding another picker clears the filter" <|
            \_ ->
                opened
                    |> steps [ ExpandPicker (Just EditorFontPicker), PickerFilterChanged "plex", ExpandPicker (Just ThemePicker) ]
                    |> .pickerFilter
                    |> Expect.equal ""
        , test "arrow down then Enter selects the second option" <|
            \_ ->
                opened
                    |> steps [ ExpandPicker (Just ThemePicker), SettingsKeyDown "ArrowDown", SettingsKeyDown "Enter" ]
                    |> (\m -> m.preferences.theme |> Expect.equal "light")
        , test "arrow keys do nothing while no picker is expanded" <|
            \_ -> (step (SettingsKeyDown "ArrowDown") opened).settingsFocus |> Expect.equal 0
        , test "End lands on the last visible option" <|
            \_ ->
                opened
                    |> steps [ ExpandPicker (Just UIFontPicker), PickerFilterChanged "sans", SettingsKeyDown "End" ]
                    |> (\m -> m.settingsFocus |> Expect.equal (List.length (values m) - 1))
        , test "a preference is clamped before it is stored" <|
            \_ ->
                step (SetPreference (\p -> { p | previewMaxWidth = 9999 })) fresh
                    |> (\m -> m.preferences.previewMaxWidth |> Expect.equal 2000)
        , test "choosing a preset keeps the typed custom width" <|
            \_ ->
                steps
                    [ SetPreference (\p -> { p | previewMaxWidth = 500 })
                    , SetPreference (\p -> { p | previewWidth = Preferences.Narrow })
                    ]
                    fresh
                    |> (\m -> Expect.equal ( Preferences.Narrow, 500 ) ( m.preferences.previewWidth, m.preferences.previewMaxWidth ))
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
        , test "opening a nested file reveals it: its folder expands and the reveal waits for the row" <|
            \_ ->
                withWorkspace fresh
                    |> openFile "/notes/sub/c.md" "x"
                    |> .fileTree
                    |> (\tree -> ( Set.member "/notes/sub" tree.expanded, tree.pendingReveal, tree.selected ))
                    |> Expect.equal ( True, Just "/notes/sub/c.md", Just "/notes/sub/c.md" )
        , test "with reveal off an opened file is only selected" <|
            \_ ->
                withWorkspace (withFlags [ ( "revealInSidebar", E.bool False ) ])
                    |> openFile "/notes/sub/c.md" "x"
                    |> .fileTree
                    |> (\tree -> ( Set.member "/notes/sub" tree.expanded, tree.pendingReveal, tree.selected ))
                    |> Expect.equal ( False, Nothing, Just "/notes/sub/c.md" )
        , test "Cmd+S with a file open starts a save of the current content" <|
            \_ ->
                opened
                    |> edit "changed"
                    |> step (keyDown "s" True)
                    |> .savingContent
                    |> Expect.equal (Just "changed")
        , test "Cmd+S on an untitled document starts Save As" <|
            \_ -> (step (keyDown "s" True) fresh).savingContent |> Expect.equal (Just "")
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


layoutModeSuite : Test
layoutModeSuite =
    describe "document layout"
        [ test "defaults and invalid persisted modes fall back to Split" <|
            \_ ->
                Expect.equal ( Split, Split ) ( fresh.layoutMode, (withFlags [ ( "layoutMode", E.string "invalid" ) ]).layoutMode )
        , test "cycle visits all modes without changing split ratio or sidebars" <|
            \_ ->
                let
                    original =
                        withFlags [ ( "editorFraction", E.float 0.65 ), ( "rightSidebarVisible", E.bool True ) ]

                    cycled =
                        steps [ CycleLayout, CycleLayout, CycleLayout ] original
                in
                Expect.equal
                    ( [ PreviewOnly, EditorOnly, Split ], ( original.editorFraction, original.leftSidebarVisible, original.rightSidebarVisible ) )
                    ( List.map (\n -> (steps (List.repeat n CycleLayout) original).layoutMode) [ 1, 2, 3 ], ( cycled.editorFraction, cycled.leftSidebarVisible, cycled.rightSidebarVisible ) )
        , test "the center shortcut cycles the mode" <|
            \_ ->
                fresh |> step (keyDown "2" True) |> .layoutMode |> Expect.equal PreviewOnly
        , test "preview Find stays in preview; Replace reveals Split" <|
            \_ ->
                let
                    preview =
                        fresh |> step (SetLayoutMode PreviewOnly) |> step (OpenFind False)
                in
                Expect.equal ( PreviewOnly, Split ) ( preview.layoutMode, (step (OpenFind True) preview).layoutMode )
        ]


reloadSuite : Test
reloadSuite =
    let
        path =
            "/notes/a.md"

        source =
            String.repeat 500 "original line\n"

        opened =
            openFile path source fresh
                |> step (EditorMsg (Editor.ScrollChanged 7000 0))

        request =
            step (fromElectron "fsEvent" [ ( "event", E.string "change" ), ( "path", E.string path ) ])

        reply id content revision =
            step
                (fromElectron "fileReloaded"
                    [ ( "path", E.string path )
                    , ( "content", E.string content )
                    , ( "revision", E.string revision )
                    , ( "dirty", E.bool False )
                    , ( "reloadId", E.int id )
                    ]
                )
    in
    describe "background file reloads"
        [ test "a genuine external change loads the new content without resetting scroll" <|
            \_ ->
                opened |> request |> reply 1 (source ++ "new line\n") "rev-2"
                    |> (\m -> Expect.equal ( source ++ "new line\n", 7000, Just "rev-2" ) ( m.editor.content, m.editor.scrollTop, m.editor.revision ))
        , test "an unchanged revision preserves the complete editor including undo" <|
            \_ ->
                let
                    saved =
                        opened |> edit (source ++ "edit") |> step (keyDown "s" True)
                            |> step (fromElectron "fileSaved" [ ( "path", E.string path ), ( "revision", E.string "rev-2" ) ])
                            |> step (EditorMsg (Editor.ScrollChanged 7000 0))
                in
                saved |> request |> reply 1 saved.editor.content "rev-2" |> .editor |> Expect.equal saved.editor
        , test "a reload response cannot overwrite an edit made while reading" <|
            \_ ->
                opened |> request |> edit "unsaved" |> reply 1 "external" "rev-2"
                    |> .editor |> .content |> Expect.equal "unsaved"
        , test "a response remains stale even if a later edit has already been saved" <|
            \_ ->
                opened |> request |> edit "new saved text" |> step (keyDown "s" True)
                    |> step (fromElectron "fileSaved" [ ( "path", E.string path ), ( "revision", E.string "rev-3" ) ])
                    |> reply 1 "old disk text" "rev-2"
                    |> .editor |> .content |> Expect.equal "new saved text"
        , test "a response from an earlier visit cannot replace the reopened file" <|
            \_ ->
                opened |> request |> openFile "/notes/b.md" "other" |> openFile path "reopened"
                    |> reply 1 "old visit" "rev-2" |> .editor |> .content |> Expect.equal "reopened"
        , test "a response cannot switch back to a file we left" <|
            \_ ->
                opened |> request |> openFile "/notes/b.md" "other" |> reply 1 "old visit" "rev-2"
                    |> .editor |> .filePath |> Expect.equal (Just "/notes/b.md")
        , test "only the newest outstanding reload response can apply" <|
            \_ ->
                opened |> request |> request |> reply 1 "stale" "rev-2" |> reply 2 "latest" "rev-3"
                    |> .editor |> .content |> Expect.equal "latest"
        , test "a late older response cannot undo a newer reload" <|
            \_ ->
                opened |> request |> request |> reply 2 "latest" "rev-3" |> reply 1 "stale" "rev-2"
                    |> .editor |> .content |> Expect.equal "latest"
        , test "external reloads preserve the caret and selection when they still fit" <|
            \_ ->
                let
                    editor =
                        opened.editor

                    positioned =
                        { opened | editor = { editor | cursor = { line = 300, col = 8 }, anchor = Just { line = 299, col = 4 } } }

                    reloaded =
                        positioned |> request |> reply 1 (source ++ "new line\n") "rev-2"
                in
                Expect.equal
                    ( positioned.editor.cursor, positioned.editor.anchor )
                    ( reloaded.editor.cursor, reloaded.editor.anchor )
        , test "external reloads clamp the caret and selection to shorter content" <|
            \_ ->
                let
                    editor =
                        opened.editor

                    positioned =
                        { opened | editor = { editor | cursor = { line = 300, col = 8 }, anchor = Just { line = 299, col = 4 } } }

                    reloaded =
                        positioned |> request |> reply 1 "short" "rev-2"
                in
                Expect.equal
                    ( { line = 0, col = 5 }, Nothing )
                    ( reloaded.editor.cursor, reloaded.editor.anchor )
        , test "changed content is not discarded even if a reload incorrectly repeats the revision" <|
            \_ ->
                opened |> request |> reply 1 "short" "rev-1"
                    |> .editor |> .content |> String.length |> Expect.equal 5
        , test "shrinking files clamp the virtual viewport" <|
            \_ ->
                opened |> request |> reply 1 "short" "rev-2"
                    |> (\m -> Expect.equal ( "short", 0 ) ( m.editor.content, m.editor.scrollTop ))
        ]
