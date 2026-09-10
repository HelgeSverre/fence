module Main exposing
    ( DragTarget(..)
    , KeyBinding
    , LayoutMode(..)
    , Model
    , Msg(..)
    , init
    , keyBindingLabel
    , main
    , matchesBinding
    , previewDelay
    , update
    )

import Array
import Browser
import Browser.Dom
import Browser.Events
import Editor
import EditorLayout
import FileTree
import Find
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Html.Lazy
import Icon
import Json.Decode as D
import Json.Encode as E
import Markdown
import Palette
import Ports
import Preview
import Process
import Task
import TextBuffer exposing (Cursor)
import Types exposing (..)
import VirtualEditor
import Yaml


type LayoutMode
    = EditorOnly
    | Split
    | PreviewOnly


layoutName : LayoutMode -> String
layoutName mode =
    case mode of
        EditorOnly ->
            "editor"

        Split ->
            "split"

        PreviewOnly ->
            "preview"


layoutFromString : String -> LayoutMode
layoutFromString name =
    case name of
        "editor" ->
            EditorOnly

        "preview" ->
            PreviewOnly

        _ ->
            Split


nextLayout : LayoutMode -> LayoutMode
nextLayout mode =
    case mode of
        EditorOnly ->
            Split

        Split ->
            PreviewOnly

        PreviewOnly ->
            EditorOnly


type DragTarget
    = DraggingSidebar
    | DraggingEditor
    | DraggingRightSidebar


type alias DragState =
    { target : DragTarget
    , startX : Float
    , startFraction : Float
    }


{-| A keyboard shortcut. `key` is the `event.key` value (e.g. "1"); the
booleans capture which modifiers must be held.
-}
type alias KeyBinding =
    { key : String
    , meta : Bool
    , ctrl : Bool
    , shift : Bool
    , alt : Bool
    }


{-| Which sidebar toggle is being rebound while in capture mode.
-}
type RebindTarget
    = RebindLeft
    | RebindRight
    | RebindLayout


type alias Model =
    { fileTree : FileTree.Model
    , editor : Editor.Model
    , previewHtml : List (List (Html Msg))
    , parseCache : Markdown.Cache Msg
    , parseProgress : Maybe (Markdown.Progress Msg)
    , framePainted : Bool -- a frame has painted since the last background step
    , frontmatter : Maybe Yaml.Value
    , debounceGeneration : Int
    , recoveryGeneration : Int
    , savingContent : Maybe String
    , reloadGeneration : Int
    , pendingReload : Maybe { id : Int, path : FilePath, editGeneration : Int }
    , theme : String
    , font : String
    , editorFontSize : Float
    , previewFontSize : Float
    , uiFontSize : Float
    , layoutMode : LayoutMode
    , layoutCycleKey : KeyBinding
    , previewFindCount : ( Int, Int )
    , settingsOpen : Bool
    , settingsFocus : Int
    , sidebarFraction : Float
    , editorFraction : Float
    , drag : Maybe DragState
    , windowWidth : Float
    , outline : List Markdown.OutlineEntry
    , leftSidebarVisible : Bool
    , rightSidebarVisible : Bool
    , rightSidebarFraction : Float
    , outlineMaxLevel : Int
    , leftToggleKey : KeyBinding
    , rightToggleKey : KeyBinding
    , rebinding : Maybe RebindTarget
    , errorMessage : Maybe String
    , closeAfterSave : Bool
    , find : Find.Model
    , palette : Palette.Model
    , searchGeneration : Int

    -- recently opened files, newest first, with a cursor for back/forward
    , history : List FilePath
    , historyPos : Int
    , navigating : Bool -- this open came from the history, so do not record it
    , counts : Counts

    -- the (source line, anchor id) pairs the preview's scroll is mapped
    -- through, and the measured pair the editor is currently between
    , headingAnchors : List ( Int, String )
    , syncPoints : List SyncPoint
    }


type alias Counts =
    { words : Int, characters : Int, lines : Int }


type Msg
    = FileTreeMsg FileTree.Msg
    | EditorMsg Editor.Msg
    | FromElectron D.Value
    | MetricsMeasured D.Value
    | KeyDown String Bool Bool Bool Bool
    | DebouncedParse Int
    | ParseStep Int
    | Frame
    | RecoveryDraftDue Int
    | ToggleSettings
    | SetLayoutMode LayoutMode
    | CycleLayout
    | SetTheme String
    | SetFont String
    | SetSoftWrap Bool
    | SetEditorFontSize Float
    | SetPreviewFontSize Float
    | SetUIFontSize Float
    | CloseSettings
    | SettingsKeyDown String
    | SettingsFocused Int
    | DividerMouseDown DragTarget Float
    | DividerMouseMove Float
    | DividerMouseUp
    | DividerDoubleClick DragTarget
    | WindowResized Int Int
    | ToggleLeftSidebar
    | ToggleRightSidebar
    | SetOutlineMaxLevel Int
    | ScrollToHeading String
    | StartRebind RebindTarget
    | DismissError
    | OpenFind Bool
    | CloseFind
    | FindQueryChanged String
    | FindReplacementChanged String
    | FindStep Int
    | FindToggleCase
    | ReplaceActive
    | ReplaceAll
    | OpenPalette Palette.Mode
    | ClosePalette
    | PaletteQueryChanged String
    | PaletteStep Int
    | PaletteChoose (Maybe Palette.Item)
    | SearchDue Int
    | NavigateHistory Int
    | SyncPointsMeasured (List SyncPoint)
    | NoOp


defaultSidebarFraction : Float
defaultSidebarFraction =
    0.17


defaultEditorFraction : Float
defaultEditorFraction =
    0.5


defaultRightSidebarFraction : Float
defaultRightSidebarFraction =
    0.18


defaultOutlineMaxLevel : Int
defaultOutlineMaxLevel =
    3


outlineMinLevel : Int
outlineMinLevel =
    1


outlineMaxLevelLimit : Int
outlineMaxLevelLimit =
    6


defaultLeftToggleKey : KeyBinding
defaultLeftToggleKey =
    { key = "1", meta = True, ctrl = False, shift = False, alt = False }


defaultRightToggleKey : KeyBinding
defaultRightToggleKey =
    { key = "3", meta = True, ctrl = False, shift = False, alt = False }


keyBindingDecoder : D.Decoder KeyBinding
keyBindingDecoder =
    D.map5 KeyBinding
        (D.field "key" D.string)
        (D.field "meta" D.bool)
        (D.field "ctrl" D.bool)
        (D.field "shift" D.bool)
        (D.field "alt" D.bool)


encodeKeyBinding : KeyBinding -> E.Value
encodeKeyBinding binding =
    E.object
        [ ( "key", E.string binding.key )
        , ( "meta", E.bool binding.meta )
        , ( "ctrl", E.bool binding.ctrl )
        , ( "shift", E.bool binding.shift )
        , ( "alt", E.bool binding.alt )
        ]


{-| Does an actual keydown (key + modifier flags) match a configured binding?
-}
matchesBinding : KeyBinding -> String -> Bool -> Bool -> Bool -> Bool -> Bool
matchesBinding binding key meta ctrl shift alt =
    (String.toLower binding.key == String.toLower key)
        && (binding.meta == meta)
        && (binding.ctrl == ctrl)
        && (binding.shift == shift)
        && (binding.alt == alt)


{-| Human-readable label for a binding, e.g. "⌘1" or "⇧⌥A".
-}
keyBindingLabel : KeyBinding -> String
keyBindingLabel binding =
    let
        mods =
            [ ( binding.ctrl, "⌃" )
            , ( binding.alt, "⌥" )
            , ( binding.shift, "⇧" )
            , ( binding.meta, "⌘" )
            ]
                |> List.filter Tuple.first
                |> List.map Tuple.second
                |> String.concat

        keyLabel =
            if String.length binding.key == 1 then
                String.toUpper binding.key

            else
                binding.key
    in
    mods ++ keyLabel


defaultEditorFontSize : Float
defaultEditorFontSize =
    14


defaultPreviewFontSize : Float
defaultPreviewFontSize =
    14


defaultUIFontSize : Float
defaultUIFontSize =
    13


defaultWindowWidth : Float
defaultWindowWidth =
    1400


editorFontMin : Float
editorFontMin =
    8


editorFontMax : Float
editorFontMax =
    32


uiFontMin : Float
uiFontMin =
    8


uiFontMax : Float
uiFontMax =
    24


settingsItemId : Int -> String
settingsItemId n =
    "settings-item-" ++ String.fromInt n


focusSilently : String -> Cmd Msg
focusSilently elementId =
    ignoreResult (Browser.Dom.focus elementId)


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        flag name decoder default =
            D.decodeValue (D.field name decoder) flagsValue
                |> Result.withDefault default
    in
    ( { fileTree = FileTree.init
      , editor = Editor.update (Editor.SetSoftWrap (flag "softWrap" D.bool True)) Editor.init
      , previewHtml = []
      , parseCache = Markdown.emptyCache
      , parseProgress = Nothing
      , framePainted = False
      , frontmatter = Nothing
      , debounceGeneration = 0
      , recoveryGeneration = 0
      , savingContent = Nothing
      , reloadGeneration = 0
      , pendingReload = Nothing
      , theme = flag "theme" D.string "github-dark"
      , font = flag "font" D.string ""
      , editorFontSize = flag "editorFontSize" D.float defaultEditorFontSize
      , previewFontSize = flag "previewFontSize" D.float defaultPreviewFontSize
      , uiFontSize = flag "uiFontSize" D.float defaultUIFontSize
      , layoutMode = layoutFromString (flag "layoutMode" D.string "split")
      , layoutCycleKey = flag "layoutCycleKey" keyBindingDecoder { key = "2", meta = True, ctrl = False, shift = False, alt = False }
      , previewFindCount = ( 0, 0 )
      , settingsOpen = False
      , settingsFocus = 0
      , sidebarFraction = flag "sidebarFraction" D.float defaultSidebarFraction
      , editorFraction = flag "editorFraction" D.float defaultEditorFraction
      , drag = Nothing
      , windowWidth = flag "windowWidth" D.float defaultWindowWidth
      , outline = []
      , leftSidebarVisible = flag "leftSidebarVisible" D.bool True
      , rightSidebarVisible = flag "rightSidebarVisible" D.bool False
      , rightSidebarFraction = flag "rightSidebarFraction" D.float defaultRightSidebarFraction
      , outlineMaxLevel =
            flag "outlineMaxLevel" D.int defaultOutlineMaxLevel
                |> clamp outlineMinLevel outlineMaxLevelLimit
      , leftToggleKey = flag "leftToggleKey" keyBindingDecoder defaultLeftToggleKey
      , rightToggleKey = flag "rightToggleKey" keyBindingDecoder defaultRightToggleKey
      , rebinding = Nothing
      , errorMessage = Nothing
      , closeAfterSave = False
      , find = Find.init
      , palette = Palette.init
      , searchGeneration = 0
      , history = []
      , historyPos = 0
      , navigating = False
      , counts = emptyCounts
      , headingAnchors = []
      , syncPoints = []
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        CycleLayout ->
            update (SetLayoutMode (nextLayout model.layoutMode)) model

        SetLayoutMode mode ->
            if mode == model.layoutMode then
                ( model, Cmd.none )

            else
                let
                    newModel =
                        { model
                            | layoutMode = mode
                            , drag = Nothing
                            , settingsOpen = False
                            , syncPoints = []
                            , previewFindCount = ( 0, 0 )
                            , find =
                                if mode == PreviewOnly then
                                    Find.showReplace False model.find

                                else
                                    Find.refresh model.editor.lines model.find
                        }
                in
                ( newModel
                , Cmd.batch
                    [ saveSplitsCmd newModel
                    , command "layoutChanged"
                        [ ( "mode", E.string (layoutName mode) )
                        ]
                    , previewFindCmd 0 newModel
                    , measureSyncPoints newModel
                    ]
                )

        ToggleSettings ->
            let
                open =
                    not model.settingsOpen
            in
            ( { model | settingsOpen = open, settingsFocus = 0 }
            , if open then
                focusSilently (settingsItemId 0)

              else
                Cmd.none
            )

        SetTheme themeValue ->
            ( { model | theme = themeValue }
            , command "setTheme" [ ( "theme", E.string themeValue ) ]
            )

        SetFont fontValue ->
            ( { model | font = fontValue }
            , command "setFont" [ ( "font", E.string fontValue ) ]
            )

        SetSoftWrap enabled ->
            let
                ( changed, cmd ) =
                    update (EditorMsg (Editor.SetSoftWrap enabled)) model
            in
            ( changed, Cmd.batch [ cmd, command "setSoftWrap" [ ( "softWrap", E.bool enabled ) ] ] )

        SetEditorFontSize size ->
            let
                clamped =
                    clamp editorFontMin editorFontMax size
            in
            ( { model | editorFontSize = clamped }
            , command "setFontSize" [ ( "editorFontSize", E.float clamped ) ]
            )

        SetPreviewFontSize size ->
            let
                clamped =
                    clamp editorFontMin editorFontMax size
            in
            ( { model | previewFontSize = clamped }
            , command "setFontSize" [ ( "previewFontSize", E.float clamped ) ]
            )

        SetUIFontSize size ->
            let
                clamped =
                    clamp uiFontMin uiFontMax size
            in
            ( { model | uiFontSize = clamped }
            , command "setFontSize" [ ( "uiFontSize", E.float clamped ) ]
            )

        CloseSettings ->
            ( { model | settingsOpen = False }, Cmd.none )

        SettingsFocused idx ->
            ( { model | settingsFocus = idx }, Cmd.none )

        SettingsKeyDown key ->
            let
                itemCount =
                    List.length themes + List.length fonts

                focus =
                    model.settingsFocus

                moveFocus newFocus =
                    ( { model | settingsFocus = newFocus }
                    , focusSilently (settingsItemId newFocus)
                    )

                activateFocused =
                    let
                        allItems =
                            List.map Tuple.first themes ++ List.map Tuple.first fonts
                    in
                    case List.head (List.drop focus allItems) of
                        Just val ->
                            if focus < List.length themes then
                                update (SetTheme val) model

                            else
                                update (SetFont val) model

                        Nothing ->
                            ( model, Cmd.none )
            in
            case key of
                "ArrowDown" ->
                    moveFocus (Basics.min (itemCount - 1) (focus + 1))

                "ArrowUp" ->
                    moveFocus (Basics.max 0 (focus - 1))

                "Enter" ->
                    activateFocused

                " " ->
                    activateFocused

                "Escape" ->
                    ( { model | settingsOpen = False }, Cmd.none )

                "Home" ->
                    moveFocus 0

                "End" ->
                    moveFocus (itemCount - 1)

                _ ->
                    ( model, Cmd.none )

        DividerMouseDown target clientX ->
            let
                startFraction =
                    case target of
                        DraggingSidebar ->
                            model.sidebarFraction

                        DraggingEditor ->
                            model.editorFraction

                        DraggingRightSidebar ->
                            model.rightSidebarFraction
            in
            ( { model
                | drag =
                    Just
                        { target = target
                        , startX = clientX
                        , startFraction = startFraction
                        }
              }
            , Cmd.none
            )

        DividerMouseMove clientX ->
            case model.drag of
                Just d ->
                    let
                        updatedModel =
                            computeDrag d clientX model
                    in
                    ( updatedModel, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        DividerMouseUp ->
            ( { model | drag = Nothing }
            , saveSplitsCmd model
            )

        DividerDoubleClick target ->
            let
                newModel =
                    case target of
                        DraggingSidebar ->
                            { model | sidebarFraction = defaultSidebarFraction }

                        DraggingEditor ->
                            { model | editorFraction = defaultEditorFraction }

                        DraggingRightSidebar ->
                            { model | rightSidebarFraction = defaultRightSidebarFraction }
            in
            ( newModel, saveSplitsCmd newModel )

        WindowResized w _ ->
            ( { model | windowWidth = toFloat w }, Cmd.none )

        ToggleLeftSidebar ->
            let
                newModel =
                    { model | leftSidebarVisible = not model.leftSidebarVisible }
            in
            ( newModel, saveSplitsCmd newModel )

        ToggleRightSidebar ->
            let
                newModel =
                    { model | rightSidebarVisible = not model.rightSidebarVisible }
            in
            ( newModel, saveSplitsCmd newModel )

        SetOutlineMaxLevel level ->
            let
                newModel =
                    { model | outlineMaxLevel = clamp outlineMinLevel outlineMaxLevelLimit level }
            in
            ( newModel, saveSplitsCmd newModel )

        ScrollToHeading anchorId ->
            ( model, scrollToHeadingCmd anchorId model )

        StartRebind target ->
            ( { model | rebinding = Just target }, Cmd.none )

        OpenFind withReplace ->
            let
                ( visibleModel, layoutCmd ) =
                    if withReplace && model.layoutMode == PreviewOnly then
                        update (SetLayoutMode Split) model

                    else
                        ( model, Cmd.none )

                seed =
                    if model.layoutMode == PreviewOnly || String.contains "\n" (Editor.selectedText model.editor) then
                        ""

                    else
                        Editor.selectedText model.editor

                newModel =
                    { visibleModel | find = Find.open withReplace seed model.editor.lines visibleModel.find }
            in
            ( newModel
            , Cmd.batch [ layoutCmd, focusSilently findInputId, previewFindCmd 0 newModel ]
            )

        CloseFind ->
            let
                newModel =
                    { model | find = Find.close model.find }
            in
            ( newModel
            , Cmd.batch
                [ focusSilently
                    (if model.layoutMode == PreviewOnly then
                        "preview-container"

                     else
                        "veditor-input"
                    )
                , previewFindCmd 0 newModel
                ]
            )

        FindQueryChanged query ->
            let
                newModel =
                    { model | find = Find.setQuery query model.editor.lines model.find }
            in
            if model.layoutMode == PreviewOnly then
                ( newModel, previewFindCmd 0 newModel )

            else
                goToActive newModel

        FindReplacementChanged replacement ->
            ( { model | find = Find.setReplacement replacement model.find }, Cmd.none )

        FindStep delta ->
            if model.layoutMode == PreviewOnly then
                ( model, previewFindCmd delta model )

            else
                goToActive { model | find = Find.step delta model.find }

        FindToggleCase ->
            let
                newModel =
                    { model | find = Find.setCaseSensitive (not model.find.caseSensitive) model.editor.lines model.find }
            in
            if model.layoutMode == PreviewOnly then
                ( newModel, previewFindCmd 0 newModel )

            else
                goToActive newModel

        ReplaceActive ->
            case Find.activeMatch model.find of
                Just range ->
                    applyReplacement [ range ] model

                Nothing ->
                    ( model, Cmd.none )

        ReplaceAll ->
            applyReplacement (Array.toList (Find.matches model.find)) model

        OpenPalette wanted ->
            ( { model | palette = Palette.open wanted model.palette }
            , Cmd.batch
                [ focusSilently paletteInputId
                , case ( wanted, model.fileTree.rootPath ) of
                    -- the list is cheap to rebuild and always current this way
                    ( Palette.Files, Just root ) ->
                        command "listFiles" [ ( "path", E.string root ) ]

                    _ ->
                        Cmd.none
                ]
            )

        ClosePalette ->
            ( { model | palette = Palette.close model.palette }
            , focusSilently
                (if model.layoutMode == PreviewOnly then
                    "preview-container"

                 else
                    "veditor-input"
                )
            )

        PaletteQueryChanged text ->
            let
                palette =
                    Palette.setQuery text model.palette

                generation =
                    model.searchGeneration + 1
            in
            case ( Palette.mode palette, model.fileTree.rootPath ) of
                ( Just Palette.Search, Just _ ) ->
                    ( { model | palette = palette, searchGeneration = generation }
                    , Task.perform (\_ -> SearchDue generation) (Process.sleep searchDelay)
                    )

                _ ->
                    ( { model | palette = palette }, Cmd.none )

        SearchDue generation ->
            if generation /= model.searchGeneration then
                ( model, Cmd.none )

            else
                case ( model.fileTree.rootPath, String.trim (Palette.query model.palette) ) of
                    ( Just root, text ) ->
                        if text == "" then
                            ( { model | palette = Palette.setResults [] model.palette }, Cmd.none )

                        else
                            ( model
                            , command "searchWorkspace"
                                [ ( "path", E.string root ), ( "query", E.string text ) ]
                            )

                    _ ->
                        ( model, Cmd.none )

        PaletteStep delta ->
            ( { model | palette = Palette.step delta model.palette }, Cmd.none )

        PaletteChoose item ->
            case item of
                Just chosen ->
                    ( { model | palette = Palette.close model.palette }
                    , command "readFile"
                        (( "path", E.string chosen.path )
                            :: (case chosen.line of
                                    Just line ->
                                        [ ( "line", E.int line ) ]

                                    Nothing ->
                                        []
                               )
                        )
                    )

                Nothing ->
                    ( model, Cmd.none )

        SyncPointsMeasured points ->
            -- re-sync straight away: the editor may have been scrolled while
            -- the measurement was pending, and an edit that changed the
            -- rendered heights leaves the preview where the old map put it
            let
                measured =
                    { model | syncPoints = points }
            in
            ( measured, syncPreview measured.editor measured )

        NavigateHistory delta ->
            let
                target =
                    model.historyPos + delta
            in
            case List.drop target model.history |> List.head of
                Just path ->
                    if target < 0 then
                        ( model, Cmd.none )

                    else
                        ( { model | historyPos = target, navigating = True }
                        , command "readFile" [ ( "path", E.string path ) ]
                        )

                Nothing ->
                    ( model, Cmd.none )

        DismissError ->
            ( { model | errorMessage = Nothing }, Cmd.none )

        FileTreeMsg subMsg ->
            let
                ( newTree, outCmds ) =
                    FileTree.update subMsg model.fileTree

                focusCmd =
                    case newTree.focused of
                        Just path ->
                            if newTree.focused /= model.fileTree.focused then
                                focusSilently (treeItemId path)

                            else
                                Cmd.none

                        Nothing ->
                            Cmd.none
            in
            ( { model | fileTree = newTree }
            , Cmd.batch [ outCmdsToPortCmds outCmds, focusCmd ]
            )

        EditorMsg subMsg ->
            let
                newEditor =
                    Editor.update subMsg model.editor

                -- an auto-scrolling drag sets the offsets itself; the caret is
                -- meant to be at the edge, so it must not be followed as well
                scrollDuringDrag =
                    ignoreResult (Browser.Dom.setViewportOf "veditor" newEditor.scrollLeft newEditor.scrollTop)

                -- Keep the caret on screen after it moves, except during a
                -- drag: there the caret sits at the edge on purpose and the
                -- auto-scroll owns the offsets. Chromium also emits a
                -- mousemove after every scroll, so following the caret here
                -- would fight the drag frame by frame.
                followCaret =
                    case ( (newEditor.cursor /= model.editor.cursor || newEditor.affinity /= model.editor.affinity || newEditor.content /= model.editor.content) && not (Editor.dragging newEditor), Editor.caretFollow newEditor ) of
                        ( True, Just target ) ->
                            ignoreResult (Browser.Dom.setViewportOf "veditor" target.left target.top)

                        _ ->
                            Cmd.none
            in
            if newEditor.content /= model.editor.content then
                let
                    gen =
                        model.debounceGeneration + 1

                    recoveryGen =
                        model.recoveryGeneration + 1
                in
                ( { model
                    | editor = newEditor
                    , debounceGeneration = gen
                    , recoveryGeneration = recoveryGen
                    , pendingReload = Nothing
                  }
                , Cmd.batch
                    [ Task.perform (\_ -> DebouncedParse gen) (Process.sleep (previewDelay newEditor.content))
                    , Task.perform (\_ -> RecoveryDraftDue recoveryGen) (Process.sleep 1000)
                    , setTitleCmd newEditor
                    , setDirtyCmd True
                    , followCaret
                    ]
                )

            else if subMsg == Editor.AutoScrolled then
                -- a frame that scrolled nothing (the drag ended, or the pointer
                -- came back inside) must not push a stale offset at the DOM
                ( { model | editor = newEditor }
                , if ( newEditor.scrollTop, newEditor.scrollLeft ) /= ( model.editor.scrollTop, model.editor.scrollLeft ) then
                    scrollDuringDrag

                  else
                    Cmd.none
                )

            else
                ( { model | editor = newEditor }
                , Cmd.batch
                    [ followCaret
                    , syncPreview newEditor model
                    , case subMsg of
                        Editor.SetSoftWrap _ ->
                            scrollDuringDrag

                        Editor.MetricsChanged _ ->
                            if ( newEditor.scrollTop, newEditor.scrollLeft ) /= ( model.editor.scrollTop, model.editor.scrollLeft ) then
                                scrollDuringDrag

                            else
                                Cmd.none

                        _ ->
                            Cmd.none
                    ]
                )

        DebouncedParse gen ->
            if gen == model.debounceGeneration then
                -- the search shares the edit debounce: rescanning a large
                -- document on every keystroke is not worth a live count
                startParse model.parseCache { model | find = Find.refresh model.editor.lines model.find }

            else
                ( model, Cmd.none )

        Frame ->
            if model.framePainted then
                let
                    ( afterParse, _ ) =
                        update (ParseStep model.debounceGeneration) model
                in
                ( { afterParse | framePainted = False }, Cmd.none )

            else
                ( { model | framePainted = True }, Cmd.none )

        ParseStep gen ->
            case model.parseProgress of
                Just progress ->
                    if gen == model.debounceGeneration then
                        continueParse parseStepBudget progress model

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        RecoveryDraftDue gen ->
            if gen == model.recoveryGeneration && model.editor.dirtyState == Dirty then
                ( model, saveRecoveryDraftCmd model.editor )

            else
                ( model, Cmd.none )

        KeyDown key metaKey ctrlKey shiftKey altKey ->
            case model.rebinding of
                Just target ->
                    if key == "Escape" then
                        ( { model | rebinding = Nothing }, Cmd.none )

                    else if isModifierKey key || not (metaKey || ctrlKey || altKey) then
                        -- Wait for a non-modifier key held with at least one
                        -- modifier, so a stray bare keypress can't clobber the
                        -- binding (and plain typing stays harmless).
                        ( model, Cmd.none )

                    else
                        let
                            binding =
                                { key = key
                                , meta = metaKey
                                , ctrl = ctrlKey
                                , shift = shiftKey
                                , alt = altKey
                                }

                            newModel =
                                case target of
                                    RebindLeft ->
                                        { model | leftToggleKey = binding, rebinding = Nothing }

                                    RebindRight ->
                                        { model | rightToggleKey = binding, rebinding = Nothing }

                                    RebindLayout ->
                                        { model | layoutCycleKey = binding, rebinding = Nothing }
                        in
                        ( newModel, saveSplitsCmd newModel )

                Nothing ->
                    if key == "s" && (metaKey || ctrlKey) then
                        saveFile model

                    else if key == "Escape" && model.settingsOpen then
                        ( { model | settingsOpen = False }, Cmd.none )

                    else if key == "f" && (metaKey || ctrlKey) && shiftKey then
                        update (OpenPalette Palette.Search) model

                    else if key == "f" && (metaKey || ctrlKey) then
                        update (OpenFind altKey) model

                    else if key == "p" && (metaKey || ctrlKey) then
                        update (OpenPalette Palette.Files) model

                    else if key == "Escape" && Palette.isOpen model.palette then
                        update ClosePalette model

                    else if key == "[" && (metaKey || ctrlKey) then
                        update (NavigateHistory 1) model

                    else if key == "]" && (metaKey || ctrlKey) then
                        update (NavigateHistory -1) model

                    else if key == "g" && (metaKey || ctrlKey) && Find.isOpen model.find then
                        update
                            (FindStep
                                (if shiftKey then
                                    -1

                                 else
                                    1
                                )
                            )
                            model

                    else if key == "Escape" && Find.isOpen model.find then
                        update CloseFind model

                    else if matchesBinding model.leftToggleKey key metaKey ctrlKey shiftKey altKey then
                        update ToggleLeftSidebar model

                    else if matchesBinding model.layoutCycleKey key metaKey ctrlKey shiftKey altKey then
                        update CycleLayout model

                    else if matchesBinding model.rightToggleKey key metaKey ctrlKey shiftKey altKey then
                        update ToggleRightSidebar model

                    else
                        ( model, Cmd.none )

        FromElectron value ->
            case D.decodeValue (D.field "tag" D.string) value of
                Ok tag ->
                    handlePortMessage tag value model

                Err _ ->
                    ( model, Cmd.none )

        MetricsMeasured value ->
            case D.decodeValue VirtualEditor.metricsDecoder value of
                Ok metrics ->
                    -- js/editor-metrics.js remeasures on any pane resize and on
                    -- every font change, so this is also where the preview's
                    -- rendered positions are known to have moved
                    let
                        ( measured, scrollCmd ) =
                            update (EditorMsg (Editor.MetricsChanged metrics)) model
                    in
                    ( measured, Cmd.batch [ scrollCmd, measureSyncPoints measured ] )

                Err _ ->
                    ( model, Cmd.none )


emptyCounts : Counts
emptyCounts =
    { words = 0, characters = 0, lines = 0 }


{-| Words, characters and lines, counted once per debounced parse rather than
per keystroke: `String.words` over a large document is not free.
-}
countsFor : String -> Counts
countsFor content =
    { words = List.length (String.words content)
    , characters = String.length content
    , lines = List.length (String.lines content)
    }


{-| The directory part of a path, for resolving a document's relative links. -}
dirName : FilePath -> String
dirName path =
    String.split "/" path |> List.reverse |> List.drop 1 |> List.reverse |> String.join "/"


{-| How many recently opened files back/forward can reach. -}
historyLimit : Int
historyLimit =
    50


paletteInputId : String
paletteInputId =
    "palette-input"


{-| How long to wait before searching the workspace for what has been typed. -}
searchDelay : Float
searchDelay =
    200


{-| Show the active match: select it in the editor and scroll it into view.
Focus stays in the find field, so Enter keeps stepping through matches.
-}
goToActive : Model -> ( Model, Cmd Msg )
goToActive model =
    case Find.activeMatch model.find of
        Just range ->
            let
                editor =
                    Editor.selectRange range model.editor
            in
            ( { model | editor = editor }
            , case Editor.caretFollow editor of
                Just target ->
                    ignoreResult (Browser.Dom.setViewportOf "veditor" target.left target.top)

                Nothing ->
                    Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Replace the given matches and re-run the search over the result. -}
applyReplacement : List ( Cursor, Cursor ) -> Model -> ( Model, Cmd Msg )
applyReplacement ranges model =
    let
        edited =
            Editor.replaceRanges ranges model.find.replacement model.editor

        gen =
            model.debounceGeneration + 1
    in
    ( { model
        | editor = edited
        , find = Find.refresh edited.lines model.find
        , debounceGeneration = gen
        , recoveryGeneration = model.recoveryGeneration + 1
      }
    , Cmd.batch
        [ Task.perform (\_ -> DebouncedParse gen) (Process.sleep (previewDelay edited.content))
        , Task.perform (\_ -> RecoveryDraftDue (model.recoveryGeneration + 1)) (Process.sleep 1000)
        , setDirtyCmd (edited.dirtyState == Dirty)
        , setTitleCmd edited
        ]
    )


{-| Begin a progressive parse of the editor content: the first step is
small so the first screen paints at once; the rest continues in
`ParseStep`s between frames. An edit to an already-parsed document reuses
the cache, so it usually completes in this first step.
-}
startParse : Markdown.Cache Msg -> Model -> ( Model, Cmd Msg )
startParse previous model =
    let
        ( progress, frontmatter ) =
            Markdown.begin previous model.editor.content
    in
    continueParse firstParseBudget progress { model | frontmatter = frontmatter, counts = countsFor model.editor.content }


continueParse : Int -> Markdown.Progress Msg -> Model -> ( Model, Cmd Msg )
continueParse budget progress model =
    let
        stepped =
            Markdown.step budget progress

        complete =
            Markdown.isComplete stepped
    in
    let
        parsed =
            { model
                | previewHtml = Markdown.htmlChunks stepped
                , outline = Markdown.outline stepped
                , headingAnchors =
                    if complete then
                        syncAnchors model.editor.content (Markdown.outline stepped)

                    else
                        model.headingAnchors
                , parseCache = Markdown.cache stepped
                , parseProgress =
                    if complete then
                        Nothing

                    else
                        Just stepped
                , framePainted = False
            }
    in
    ( parsed
      -- the rendered document just changed, so every heading may have moved
    , if complete then
        measureSyncPoints parsed

      else
        Cmd.none
    )


{-| Characters of uncached source parsed before the first paint. -}
firstParseBudget : Int
firstParseBudget =
    15000


{-| Characters of uncached source per follow-up step (~60-90ms of work). -}
parseStepBudget : Int
parseStepBudget =
    60000


previewDelay : String -> Float
previewDelay content =
    -- Re-parsing is chunk-cached, so an update costs ~20-50ms even for very
    -- large documents; the debounce only needs to coalesce fast typing.
    if String.length content > 1000000 then
        400

    else if String.length content > 250000 then
        150

    else
        50


saveFile : Model -> ( Model, Cmd Msg )
saveFile model =
    case ( model.editor.filePath, model.savingContent ) of
        ( Just path, Nothing ) ->
            ( { model | savingContent = Just model.editor.content, pendingReload = Nothing }
            , command "writeFile"
                [ ( "path", E.string path )
                , ( "content", E.string model.editor.content )
                , ( "expectedRevision", model.editor.revision |> Maybe.map E.string |> Maybe.withDefault E.null )
                ]
            )

        _ ->
            ( model, Cmd.none )


handlePortMessage : String -> D.Value -> Model -> ( Model, Cmd Msg )
handlePortMessage tag value model =
    case tag of
        "folderOpened" ->
            case D.decodeValue dirEntriesDecoder value of
                Ok ( path, entries ) ->
                    ( { model | fileTree = FileTree.handleFolderOpened path entries model.fileTree }
                      -- The root starts expanded, so watch it like Toggle would.
                    , outCmdsToPortCmds [ FileTree.CmdWatchDir path ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "dirContents" ->
            case D.decodeValue dirEntriesDecoder value of
                Ok ( path, entries ) ->
                    ( { model | fileTree = FileTree.handleDirContents path entries model.fileTree }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        "fileContent" ->
            case D.decodeValue fileContentDecoder value of
                Ok file ->
                    let
                        newEditor =
                            Editor.setContent file.path file.content file.revision file.dirty model.editor
                                |> (case file.line of
                                        Just line ->
                                            Editor.gotoLine line

                                        Nothing ->
                                            identity
                                   )

                        gen =
                            model.debounceGeneration + 1

                        ( parsedModel, parseCmd ) =
                            startParse Markdown.emptyCache
                                { model
                                    | editor = newEditor
                                    , fileTree = FileTree.select file.path model.fileTree
                                    , debounceGeneration = gen
                                }
                    in
                    ( { parsedModel
                        | closeAfterSave = False
                        , savingContent = Nothing
                        , pendingReload = Nothing
                        , history =
                            if model.navigating then
                                model.history

                            else
                                file.path :: List.filter ((/=) file.path) model.history |> List.take historyLimit
                        , historyPos =
                            if model.navigating then
                                model.historyPos

                            else
                                0
                        , navigating = False
                      }
                    , Cmd.batch
                        [ setTitleCmd newEditor
                        , setDirtyCmd file.dirty
                        , parseCmd

                        -- Match the browser viewport to the new virtual rows,
                        -- including ordinary file opens while scrolled down.
                        , case ( file.line, Editor.caretFollow newEditor ) of
                            ( Just _, Just target ) ->
                                ignoreResult (Browser.Dom.setViewportOf "veditor" target.left target.top)

                            _ ->
                                ignoreResult (Browser.Dom.setViewportOf "veditor" newEditor.scrollLeft newEditor.scrollTop)
                        ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "fileReloaded" ->
            case ( model.pendingReload, D.decodeValue (D.map2 Tuple.pair (D.field "reloadId" D.int) fileContentDecoder) value ) of
                ( Just pending, Ok ( reloadId, file ) ) ->
                    if reloadId /= pending.id then
                        ( model, Cmd.none )

                    else
                        let
                            settled =
                                { model | pendingReload = Nothing }
                        in
                        if file.path /= pending.path || model.editor.filePath /= Just file.path || pending.editGeneration /= model.debounceGeneration || model.editor.dirtyState /= Clean || model.savingContent /= Nothing then
                            ( settled, Cmd.none )

                        else if model.editor.revision == Just file.revision && model.editor.content == file.content then
                            -- The watcher can report our own save after its acknowledgement.
                            -- Keep scroll, selection, undo and pending preview work intact.
                            ( settled, Cmd.none )

                        else
                            let
                                newEditor =
                                    Editor.reloadContent file.path file.content file.revision model.editor

                                ( parsed, parseCmd ) =
                                    startParse model.parseCache
                                        { settled
                                            | editor = newEditor
                                            , debounceGeneration = model.debounceGeneration + 1
                                        }
                            in
                            ( parsed
                            , Cmd.batch
                                [ parseCmd
                                , ignoreResult (Browser.Dom.setViewportOf "veditor" newEditor.scrollLeft newEditor.scrollTop)
                                ]
                            )

                _ ->
                    ( model, Cmd.none )

        "fileSaved" ->
            case D.decodeValue fileSavedDecoder value of
                Ok ( path, revision ) ->
                    let
                        savedContent =
                            Maybe.withDefault model.editor.content model.savingContent

                        newEditor =
                            if model.editor.filePath == Just path then
                                Editor.markSaved savedContent revision model.editor

                            else
                                model.editor

                        updatedModel =
                            { model | editor = newEditor, savingContent = Nothing }
                    in
                    if model.closeAfterSave && newEditor.dirtyState == Dirty then
                        let
                            ( resaveModel, resaveCmd ) =
                                saveFile updatedModel
                        in
                        ( { resaveModel | closeAfterSave = True }, resaveCmd )

                    else
                        -- The pending close is consumed here; leaving it set
                        -- would turn the next ordinary save into a close.
                        ( { updatedModel | closeAfterSave = False }
                        , Cmd.batch
                            [ setTitleCmd newEditor
                            , setDirtyCmd (newEditor.dirtyState == Dirty)
                            , if model.closeAfterSave then
                                closeWindowCmd

                              else
                                Cmd.none
                            ]
                        )

                Err _ ->
                    ( model, Cmd.none )

        "fsEvent" ->
            case D.decodeValue fsEventDecoder value of
                Ok ( event, path ) ->
                    let
                        newTree =
                            FileTree.handleFsEvent event path model.fileTree

                        -- If the currently open file changed externally and is clean, reload it
                        shouldReload =
                            event
                                == "change"
                                && model.editor.filePath
                                == Just path
                                && model.editor.dirtyState
                                == Clean
                                && model.savingContent == Nothing

                        reloadId =
                            model.reloadGeneration + 1
                    in
                    ( { model
                        | fileTree = newTree
                        , reloadGeneration =
                            if shouldReload then
                                reloadId

                            else
                                model.reloadGeneration
                        , pendingReload =
                            if shouldReload then
                                Just { id = reloadId, path = path, editGeneration = model.debounceGeneration }

                            else
                                model.pendingReload
                      }
                    , if shouldReload then
                        command "readFile" [ ( "path", E.string path ), ( "reloadId", E.int reloadId ) ]

                      else
                        Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        "exportRequested" ->
            case ( D.decodeValue (D.field "format" D.string) value, model.editor.filePath ) of
                ( Ok format, path ) ->
                    ( model
                    , command "exportDocument"
                        [ ( "format", E.string format )
                        , ( "title", E.string (Maybe.map baseName path |> Maybe.withDefault "document") )

                        -- so relative image sources resolve in the export
                        , ( "base", E.string (Maybe.map (\p -> "file://" ++ dirName p ++ "/") path |> Maybe.withDefault "") )
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        "attachmentSaved" ->
            case D.decodeValue (D.field "relative" D.string) value of
                Ok relative ->
                    update (EditorMsg (Editor.InsertText ("![](" ++ relative ++ ")"))) model

                Err _ ->
                    ( model, Cmd.none )

        "fileList" ->
            case D.decodeValue (D.field "files" (D.list fileItemDecoder)) value of
                Ok items ->
                    ( { model | palette = Palette.setResults items model.palette }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        "searchResults" ->
            case D.decodeValue searchResultsDecoder value of
                Ok ( query, hits ) ->
                    -- a slower search that finished after the query moved on
                    -- must not replace what is on screen now
                    if String.trim (Palette.query model.palette) == query then
                        ( { model | palette = Palette.setResults hits model.palette }, Cmd.none )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        "treeCommand" ->
            case D.decodeValue treeCommandDecoder value of
                Ok ( name, path ) ->
                    let
                        ( newTree, outCmds ) =
                            FileTree.startCommand name path model.fileTree
                    in
                    ( { model | fileTree = newTree }, outCmdsToPortCmds outCmds )

                Err _ ->
                    ( model, Cmd.none )

        "renamed" ->
            case D.decodeValue renamedDecoder value of
                Ok ( from, to ) ->
                    ( { model
                        | fileTree = FileTree.handleRenamed from to model.fileTree
                        , editor = Editor.followRename from to model.editor
                      }
                    , if model.editor.filePath == Just from then
                        setTitleCmd (Editor.followRename from to model.editor)

                      else
                        Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        "saveAndClose" ->
            -- Close happens when "fileSaved" comes back, so a slow write
            -- can't lose data. An "error" cancels the pending close.
            case model.editor.filePath of
                Just _ ->
                    let
                        ( newModel, saveCmd ) =
                            saveFile model
                    in
                    ( { newModel | closeAfterSave = True }, saveCmd )

                Nothing ->
                    ( model, closeWindowCmd )

        "saveCancelled" ->
            ( { model | closeAfterSave = False, savingContent = Nothing }
            , Cmd.none
            )

        "previewFindResult" ->
            if model.layoutMode == PreviewOnly && Find.isOpen model.find && (D.decodeValue (D.field "query" D.string) value == Ok model.find.query) && (D.decodeValue (D.field "caseSensitive" D.bool) value == Ok model.find.caseSensitive) then
                case D.decodeValue (D.map2 Tuple.pair (D.field "current" D.int) (D.field "total" D.int)) value of
                    Ok counts ->
                        ( { model | previewFindCount = counts }, Cmd.none )

                    Err _ ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        "toggleSettings" ->
            update ToggleSettings model

        "triggerOpenFolder" ->
            ( model
            , command "openFolder" []
            )

        "error" ->
            ( { model
                | errorMessage =
                    D.decodeValue (D.field "message" D.string) value
                        |> Result.toMaybe
                , closeAfterSave = False
                , savingContent = Nothing
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )



-- TITLE AND DIRTY STATE


setTitleCmd : Editor.Model -> Cmd Msg
setTitleCmd editor =
    let
        title =
            case editor.filePath of
                Just path ->
                    "Fence — "
                        ++ baseName path
                        ++ (if editor.dirtyState == Dirty then
                                " *"

                            else
                                ""
                           )

                Nothing ->
                    "Fence"
    in
    command "setTitle" [ ( "title", E.string title ) ]


setDirtyCmd : Bool -> Cmd Msg
setDirtyCmd dirty =
    command "setDirty" [ ( "dirty", E.bool dirty ) ]


closeWindowCmd : Cmd Msg
closeWindowCmd =
    command "closeWindow" []


saveRecoveryDraftCmd : Editor.Model -> Cmd Msg
saveRecoveryDraftCmd editor =
    case editor.filePath of
        Just path ->
            command "saveRecoveryDraft"
                [ ( "path", E.string path )
                , ( "content", E.string editor.content )
                , ( "revision", editor.revision |> Maybe.map E.string |> Maybe.withDefault E.null )
                ]

        Nothing ->
            Cmd.none



-- SPLIT HELPERS


computeDrag : DragState -> Float -> Model -> Model
computeDrag d clientX model =
    case d.target of
        DraggingSidebar ->
            let
                deltaFraction =
                    (clientX - d.startX) / model.windowWidth

                newFraction =
                    clamp 0.08 0.4 (d.startFraction + deltaFraction)
            in
            { model | sidebarFraction = newFraction }

        DraggingEditor ->
            let
                rightFraction =
                    if model.rightSidebarVisible then
                        model.rightSidebarFraction

                    else
                        0

                -- editorFraction is a fraction of the editor/preview region,
                -- i.e. the window minus both sidebars.
                remainingWidth =
                    model.windowWidth * (1 - model.sidebarFraction - rightFraction)

                deltaFraction =
                    if remainingWidth > 0 then
                        (clientX - d.startX) / remainingWidth

                    else
                        0

                newFraction =
                    clamp 0.15 0.85 (d.startFraction + deltaFraction)
            in
            { model | editorFraction = newFraction }

        DraggingRightSidebar ->
            let
                -- The handle sits on the sidebar's left edge, so dragging
                -- left (negative delta) widens the right sidebar.
                deltaFraction =
                    (clientX - d.startX) / model.windowWidth

                newFraction =
                    clamp 0.08 0.4 (d.startFraction - deltaFraction)
            in
            { model | rightSidebarFraction = newFraction }


{-| A message to the main process: a tag naming the command, plus its fields.
-}
command : String -> List ( String, E.Value ) -> Cmd Msg
command tag fields =
    Ports.toElectron (E.object (( "tag", E.string tag ) :: fields))


{-| Run a task purely for its effect.
-}
ignoreResult : Task.Task x a -> Cmd Msg
ignoreResult =
    Task.attempt (\_ -> NoOp)


saveSplitsCmd : Model -> Cmd Msg
saveSplitsCmd model =
    command "saveSplits"
        [ ( "sidebarFraction", E.float model.sidebarFraction )
        , ( "editorFraction", E.float model.editorFraction )
        , ( "rightSidebarFraction", E.float model.rightSidebarFraction )
        , ( "leftSidebarVisible", E.bool model.leftSidebarVisible )
        , ( "rightSidebarVisible", E.bool model.rightSidebarVisible )
        , ( "outlineMaxLevel", E.int model.outlineMaxLevel )
        , ( "leftToggleKey", encodeKeyBinding model.leftToggleKey )
        , ( "rightToggleKey", encodeKeyBinding model.rightToggleKey )
        , ( "layoutMode", E.string (layoutName model.layoutMode) )
        , ( "layoutCycleKey", encodeKeyBinding model.layoutCycleKey )
        ]


{-| Keep the preview following the editor's scroll position.

Mapping source lines to rendered pixels exactly would need a position for
every block; headings are the anchors we already have, so the editor's top
line is placed between the two headings that bracket it, and the preview is
scrolled to the matching point between their rendered positions.

Two things keep it smooth. The top line is fractional, so the preview moves
with the editor rather than once per line. And every heading's pixel position
is measured in one pass whenever the preview's layout changes, never while
scrolling: a `getElement` between the editor's own row updates would force a
synchronous layout of the whole page on every scroll event, which is exactly
what this editor exists to avoid. Scrolling is then pure arithmetic and a
single scroll write.

Only the editor drives this: mapping the preview's DOM back to source would
need the same data in reverse, for much less gain.

-}
type alias SyncPoint =
    { line : Float, y : Float }


syncPreview : Editor.Model -> Model -> Cmd Msg
syncPreview editor model =
    let
        topLine =
            if editor.softWrap then
                EditorLayout.sourceLine (editor.scrollTop / Basics.max 1 editor.metrics.lineHeight) editor.layout

            else
                editor.scrollTop / Basics.max 1 editor.metrics.lineHeight
    in
    if model.layoutMode /= Split || Editor.dragging editor then
        Cmd.none

    else
        case bracketing topLine model.syncPoints of
            Just ( from, to ) ->
                scrollPreviewTo (interpolate from to topLine)

            Nothing ->
                Cmd.none


{-| The measured points bracketing a line.
-}
bracketing : Float -> List SyncPoint -> Maybe ( SyncPoint, SyncPoint )
bracketing topLine points =
    case points of
        first :: second :: rest ->
            if topLine < second.line || List.isEmpty rest then
                Just ( first, second )

            else
                bracketing topLine (second :: rest)

        _ ->
            Nothing


interpolate : SyncPoint -> SyncPoint -> Float -> Float
interpolate from to topLine =
    let
        span =
            to.line - from.line
    in
    if span <= 0 then
        from.y

    else
        from.y + clamp 0 1 ((topLine - from.line) / span) * (to.y - from.y)


scrollPreviewTo : Float -> Cmd Msg
scrollPreviewTo y =
    ignoreResult (Browser.Dom.setViewportOf "preview-container" 0 y)


{-| Measure where every heading sits in the rendered preview, plus the two
ends of the document. One pass, off the scrolling path: consecutive reads with
no writes between them share a single layout.

The wait is not decoration. Elm applies a view on the animation frame after
the update that produced it, so reading the DOM in the same update would
measure the *previous* render - and right after a parse that is a preview
without the headings in it.

-}
measureSyncPoints : Model -> Cmd Msg
measureSyncPoints model =
    if model.layoutMode /= Split || List.isEmpty model.headingAnchors then
        Task.perform SyncPointsMeasured (Task.succeed [])

    else
        Process.sleep 50
            |> Task.andThen
                (\_ -> Task.map2 Tuple.pair (Browser.Dom.getElement "preview-container") (Browser.Dom.getViewportOf "preview-container"))
            |> Task.andThen
                (\( container, containerVp ) ->
                    model.headingAnchors
                        |> List.map
                            (\( line, anchorId ) ->
                                Browser.Dom.getElement anchorId
                                    |> Task.map
                                        (\heading ->
                                            Just
                                                { line = toFloat line
                                                , y = containerVp.viewport.y + heading.element.y - container.element.y
                                                }
                                        )
                                    -- a heading that is not in the DOM is skipped
                                    -- rather than losing the whole mapping
                                    |> Task.onError (\_ -> Task.succeed Nothing)
                            )
                        |> Task.sequence
                        |> Task.map
                            (\measured ->
                                -- the document's own top always maps to the top
                                -- of the preview, so a heading on line 0 (which
                                -- measures at the preview's padding) is dropped
                                { line = 0, y = 0 }
                                    :: List.filter (\point -> point.line > 0) (List.filterMap identity measured)
                                    ++ [ { line = toFloat (Basics.max 1 (Array.length model.editor.lines - 1))
                                         , y = Basics.max 0 (containerVp.scene.height - containerVp.viewport.height)
                                         }
                                       ]
                            )
                )
            |> Task.attempt (Result.withDefault [] >> SyncPointsMeasured)


{-| The headings, as (source line, anchor id) pairs. Recomputed once per
completed parse, never per scroll event: it rescans the whole document.

The two lists come from the same document in the same order; if they disagree
in length the mapping would be wrong for every heading (a setext heading, say),
so sync is skipped entirely instead.

-}
syncAnchors : String -> List Markdown.OutlineEntry -> List ( Int, String )
syncAnchors content entries =
    let
        lines =
            Markdown.headingLines content
    in
    if List.length lines == List.length entries then
        List.map2 (\line entry -> ( line, entry.id )) lines entries

    else
        []


{-| Scroll to a heading picked in the outline.

The editor is what moves: the outline lists the rendered document, but the
heading's source line is known, and scrolling the editor there carries the
preview with it through the usual sync. Scrolling both directly instead would
race - the preview scroll is computed from the container's current offset,
which sync is moving at the same time, and the result overshoots.

Only a heading whose source line cannot be resolved (see `syncAnchors`) falls
back to scrolling the preview on its own.

-}
scrollToHeadingCmd : String -> Model -> Cmd Msg
scrollToHeadingCmd anchorId model =
    if model.layoutMode == PreviewOnly then
        scrollPreviewToHeadingCmd anchorId

    else
        case model.headingAnchors |> List.filter (\( _, id ) -> id == anchorId) |> List.head of
            Just ( line, _ ) ->
                ignoreResult
                    (Browser.Dom.setViewportOf "veditor"
                        0
                        (toFloat (EditorLayout.lineStartRow line model.editor.layout) * model.editor.metrics.lineHeight)
                    )

            Nothing ->
                scrollPreviewToHeadingCmd anchorId


{-| Scroll the preview pane so the heading with `anchorId` is at the top.
Computes the heading's offset relative to the scrollable preview container.
-}
scrollPreviewToHeadingCmd : String -> Cmd Msg
scrollPreviewToHeadingCmd anchorId =
    Task.map3
        (\heading container containerVp ->
            -- Heading offset within the container's scrollable content.
            containerVp.viewport.y + heading.element.y - container.element.y
        )
        (Browser.Dom.getElement anchorId)
        (Browser.Dom.getElement "preview-container")
        (Browser.Dom.getViewportOf "preview-container")
        |> Task.andThen (\y -> Browser.Dom.setViewportOf "preview-container" 0 y)
        |> ignoreResult


{-| Is this `event.key` value a bare modifier key (no real character)?
-}
isModifierKey : String -> Bool
isModifierKey key =
    List.member key [ "Meta", "Control", "Shift", "Alt", "CapsLock" ]



-- PORT COMMAND HELPERS


outCmdsToPortCmds : List FileTree.OutCmd -> Cmd Msg
outCmdsToPortCmds cmds =
    Cmd.batch (List.map outCmdToCommand cmds)


outCmdToCommand : FileTree.OutCmd -> Cmd Msg
outCmdToCommand cmd =
    let
        forPath tag path =
            command tag [ ( "path", E.string path ) ]
    in
    case cmd of
        FileTree.CmdOpenFolder ->
            command "openFolder" []

        FileTree.CmdReadDir path ->
            forPath "readDir" path

        FileTree.CmdReadFile path ->
            forPath "readFile" path

        FileTree.CmdWatchDir path ->
            forPath "watchDir" path

        FileTree.CmdUnwatchDir path ->
            forPath "unwatchDir" path

        FileTree.CmdCreateFile dir name ->
            command "createFile" [ ( "dir", E.string dir ), ( "name", E.string name ) ]

        FileTree.CmdCreateDir dir name ->
            command "createDir" [ ( "dir", E.string dir ), ( "name", E.string name ) ]

        FileTree.CmdRename path name ->
            command "renamePath" [ ( "path", E.string path ), ( "name", E.string name ) ]

        FileTree.CmdTrash path ->
            forPath "trashPath" path

        FileTree.CmdFocusEditInput ->
            focusSilently treeEditInputId



-- DECODERS


fileEntryDecoder : D.Decoder FileEntry
fileEntryDecoder =
    D.map4
        (\name path ft children ->
            FileEntry
                { name = name
                , path = path
                , fileType = ft
                , children = children
                }
        )
        (D.field "name" D.string)
        (D.field "path" D.string)
        (D.field "fileType" fileTypeDecoder)
        (D.maybe (D.field "children" (D.lazy (\_ -> D.list fileEntryDecoder))))


fileTypeDecoder : D.Decoder FileType
fileTypeDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "directory" ->
                        D.succeed Directory

                    "file" ->
                        D.succeed File

                    _ ->
                        D.fail ("Unknown file type: " ++ s)
            )


dirEntriesDecoder : D.Decoder ( FilePath, List FileEntry )
dirEntriesDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "entries" (D.list fileEntryDecoder))


type alias FileContentPayload =
    { path : FilePath
    , content : String
    , revision : String
    , dirty : Bool
    , line : Maybe Int -- 1-based line to put the caret on, for search results
    }


fileContentDecoder : D.Decoder FileContentPayload
fileContentDecoder =
    D.map5 FileContentPayload
        (D.field "path" D.string)
        (D.field "content" D.string)
        (D.field "revision" D.string)
        (D.field "dirty" D.bool)
        (D.maybe (D.field "line" D.int))


fileSavedDecoder : D.Decoder ( FilePath, String )
fileSavedDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "revision" D.string)


fileItemDecoder : D.Decoder Palette.Item
fileItemDecoder =
    D.map2
        (\path relative -> { primary = baseName path, secondary = relative, path = path, line = Nothing })
        (D.field "path" D.string)
        (D.field "relative" D.string)


searchResultsDecoder : D.Decoder ( String, List Palette.Item )
searchResultsDecoder =
    D.map2 Tuple.pair
        (D.field "query" D.string)
        (D.field "hits"
            (D.list
                (D.map4
                    (\path relative line text ->
                        { primary = String.trim text
                        , secondary = relative ++ ":" ++ String.fromInt line
                        , path = path
                        , line = Just line
                        }
                    )
                    (D.field "path" D.string)
                    (D.field "relative" D.string)
                    (D.field "line" D.int)
                    (D.field "text" D.string)
                )
            )
        )


treeCommandDecoder : D.Decoder ( String, Maybe FilePath )
treeCommandDecoder =
    D.map2 Tuple.pair
        (D.field "command" D.string)
        (D.maybe (D.field "path" D.string))


renamedDecoder : D.Decoder ( FilePath, FilePath )
renamedDecoder =
    D.map2 Tuple.pair
        (D.field "from" D.string)
        (D.field "path" D.string)


fsEventDecoder : D.Decoder ( String, FilePath )
fsEventDecoder =
    D.map2 Tuple.pair
        (D.field "event" D.string)
        (D.field "path" D.string)


keyDecoder : D.Decoder Msg
keyDecoder =
    D.map5 KeyDown
        (D.field "key" D.string)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.fromElectron FromElectron
        , Ports.editorMetrics MetricsMeasured
        , Browser.Events.onKeyDown keyDecoder
        , Browser.Events.onResize WindowResized
        , -- Background parse steps run one per painted frame, so a large
          -- document paints its first screen before the rest fills in.
          if model.parseProgress /= Nothing then
            Browser.Events.onAnimationFrame (\_ -> Frame)

          else
            Sub.none
        , case model.drag of
            Just _ ->
                Sub.batch
                    [ Browser.Events.onMouseMove
                        (D.map DividerMouseMove (D.field "clientX" D.float))
                    , Browser.Events.onMouseUp
                        (D.succeed DividerMouseUp)
                    ]

            Nothing ->
                Sub.none
        , -- A drag continues outside the editor, so it is followed on the
          -- document, and each frame may scroll further while it is held
          -- past an edge.
          if Editor.dragging model.editor then
            Sub.batch
                [ Browser.Events.onMouseMove
                    (D.map2 (\x y -> EditorMsg (Editor.PointerMoved x y))
                        (D.field "clientX" D.float)
                        (D.field "clientY" D.float)
                    )
                , Browser.Events.onMouseUp (D.succeed (EditorMsg Editor.PointerUp))
                , Browser.Events.onAnimationFrame (\_ -> EditorMsg Editor.AutoScrolled)
                ]

          else
            Sub.none
        ]



-- VIEW


pct : Float -> String
pct f =
    String.fromFloat (f * 100) ++ "%"


viewDivider : DragTarget -> Html Msg
viewDivider target =
    div
        [ class "divider"
        , attribute "data-testid"
            (case target of
                DraggingSidebar ->
                    "divider-sidebar"

                DraggingEditor ->
                    "divider-editor"

                DraggingRightSidebar ->
                    "divider-outline"
            )
        , on "mousedown" (D.map (DividerMouseDown target) (D.field "clientX" D.float))
        , onDoubleClick (DividerDoubleClick target)
        ]
        []


view : Model -> Html Msg
view model =
    let
        leftFraction =
            if model.leftSidebarVisible then
                model.sidebarFraction

            else
                0

        rightFraction =
            if model.rightSidebarVisible then
                model.rightSidebarFraction

            else
                0

        -- Editor/preview share whatever the sidebars leave behind.
        middleRegion =
            Basics.max 0 (1 - leftFraction - rightFraction)

        editorTrack =
            model.editorFraction * middleRegion

        -- Keyed cells preserve pane DOM when sidebars or modes change. Even
        -- a hidden pane keeps its cell, so grid columns match the children.
        -- lazy: keeps typing from rebuilding the tree/preview virtual DOM
        -- when their inputs haven't changed.
        leftSection =
            if model.leftSidebarVisible then
                [ ( "sidebar", ( pct model.sidebarFraction, Html.map FileTreeMsg (Html.Lazy.lazy FileTree.view model.fileTree) ) )
                , ( "sidebar-divider", ( "2px", viewDivider DraggingSidebar ) )
                ]

            else
                []

        middleSection =
            [ ( "editor"
              , ( if model.layoutMode == Split then
                    pct editorTrack

                  else if model.layoutMode == EditorOnly then
                    "1fr"

                  else
                    "0px"
                , viewEditorPane model
                )
              )
            , ( "editor-divider"
              , ( if model.layoutMode == Split then
                    "2px"

                  else
                    "0px"
                , if model.layoutMode == Split then
                    viewDivider DraggingEditor

                  else
                    text ""
                )
              )
            , ( "preview"
              , ( if model.layoutMode == EditorOnly then
                    "0px"

                  else
                    "1fr"
                , viewPreviewPane model
                )
              )
            ]

        rightSection =
            if model.rightSidebarVisible then
                [ ( "outline-divider", ( "2px", viewDivider DraggingRightSidebar ) )
                , ( "outline", ( pct model.rightSidebarFraction, viewOutline model ) )
                ]

            else
                []

        sections =
            leftSection ++ middleSection ++ rightSection

        gridColumns =
            String.join " " (List.map (Tuple.second >> Tuple.first) sections)
    in
    div []
        [ div [ class "app-shell" ]
            [ viewTitleBar model
            , Html.Keyed.node "div"
                [ class "app-layout"
                , attribute "data-layout" (layoutName model.layoutMode)
                , classList [ ( "dragging", model.drag /= Nothing ) ]
                , style "grid-template-columns" gridColumns
                ]
                (List.map (Tuple.mapSecond (\( _, pane ) -> div [ class "layout-cell" ] [ pane ])) sections)
            ]
        , if Palette.isOpen model.palette then
            viewPalette model.palette

          else
            text ""
        , case model.errorMessage of
            Just message ->
                div [ class "error-banner", attribute "data-testid" "error-banner", onClick DismissError, title "Click to dismiss" ]
                    [ text message ]

            Nothing ->
                text ""
        ]


{-| The editor, with the find bar layered over it when it is open. -}
viewEditorPane : Model -> Html Msg
viewEditorPane model =
    div
        [ class "editor-pane-wrap"
        , style "display"
            (if model.layoutMode == PreviewOnly then
                "none"

             else
                "flex"
            )
        ]
        [ Html.map EditorMsg
            (Editor.view
                { highlights =
                    if Find.isOpen model.find then
                        Array.toList (Find.matches model.find)

                    else
                        []
                , activeHighlight =
                    if Find.isOpen model.find then
                        Find.activeMatch model.find

                    else
                        Nothing
                , status = countsLabel model.counts
                }
                model.editor
            )
        , if Find.isOpen model.find && model.layoutMode /= PreviewOnly then
            viewFindBar (Find.count model.find) model.find

          else
            text ""
        ]


previewFindCmd : Int -> Model -> Cmd Msg
previewFindCmd delta model =
    command "previewFind"
        [ ( "opened", E.bool (model.layoutMode == PreviewOnly && Find.isOpen model.find) )
        , ( "query", E.string model.find.query )
        , ( "caseSensitive", E.bool model.find.caseSensitive )
        , ( "delta", E.int delta )
        , ( "limit", E.int Find.matchLimit )
        ]


viewPreviewPane : Model -> Html Msg
viewPreviewPane model =
    div
        ([ class "preview-pane-wrap"
         , classList [ ( "pane-offscreen", model.layoutMode == EditorOnly ) ]
         ]
            ++ (if model.layoutMode == EditorOnly then
                    [ attribute "inert" "", attribute "aria-hidden" "true", style "width" (String.fromFloat (model.windowWidth * model.editorFraction) ++ "px") ]

                else
                    []
               )
        )
        [ Html.Lazy.lazy3 Preview.view model.editor.filePath model.frontmatter model.previewHtml
        , if model.layoutMode == PreviewOnly && Find.isOpen model.find then
            viewFindBar model.previewFindCount model.find

          else
            text ""
        ]


viewLayoutSelector : Model -> Html Msg
viewLayoutSelector model =
    let
        segment mode label icon =
            button
                [ class "icon-button layout-segment"
                , id ("layout-" ++ layoutName mode)
                , attribute "data-testid" ("layout-" ++ layoutName mode)
                , attribute "role" "radio"
                , attribute "aria-label" label
                , attribute "aria-checked"
                    (if model.layoutMode == mode then
                        "true"

                     else
                        "false"
                    )
                , tabindex
                    (if model.layoutMode == mode then
                        0

                     else
                        -1
                    )
                , title (label ++ " · Cycle layout " ++ keyBindingLabel model.layoutCycleKey)
                , onClick (SetLayoutMode mode)
                , preventDefaultOn "keydown"
                    (D.field "key" D.string
                        |> D.map
                            (\key ->
                                case key of
                                    "ArrowRight" ->
                                        ( SetLayoutMode (nextLayout mode), True )

                                    "ArrowLeft" ->
                                        ( SetLayoutMode (nextLayout (nextLayout mode)), True )

                                    "Home" ->
                                        ( SetLayoutMode EditorOnly, True )

                                    "End" ->
                                        ( SetLayoutMode PreviewOnly, True )

                                    _ ->
                                        ( NoOp, False )
                            )
                    )
                ]
                [ icon 16 ]
    in
    div [ class "layout-selector", attribute "role" "radiogroup", attribute "aria-label" "Document layout" ]
        [ segment EditorOnly "Editor only" Icon.editorLayout
        , segment Split "Editor and preview" Icon.splitLayout
        , segment PreviewOnly "Preview only" Icon.previewLayout
        ]


viewPalette : Palette.Model -> Html Msg
viewPalette palette =
    let
        rows =
            Palette.results palette

        placeholderText =
            case Palette.mode palette of
                Just Palette.Search ->
                    "Search the workspace"

                _ ->
                    "Go to file"

        row index item =
            div
                [ class "palette-row"
                , classList [ ( "active", index == palette.active ) ]
                , attribute "data-testid" "palette-row"
                , attribute "role" "option"
                , attribute "aria-selected"
                    (if index == palette.active then
                        "true"

                     else
                        "false"
                    )
                , onClick (PaletteChoose (Just item))
                ]
                [ span [ class "palette-primary" ] [ text item.primary ]
                , span [ class "palette-secondary" ] [ text item.secondary ]
                ]
    in
    div [ class "palette-backdrop", attribute "data-testid" "palette", onClick ClosePalette ]
        [ div [ class "palette", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
            [ input
                [ class "palette-input"
                , id paletteInputId
                , attribute "data-testid" "palette-input"
                , attribute "aria-label" placeholderText
                , placeholder placeholderText
                , value (Palette.query palette)
                , spellcheck False
                , onInput PaletteQueryChanged
                , preventDefaultOn "keydown" (paletteKeyDecoder palette)
                ]
                []
            , if List.isEmpty rows then
                div [ class "palette-empty" ] [ text "No results" ]

              else
                div [ class "palette-results", attribute "role" "listbox" ] (List.indexedMap row rows)
            ]
        ]


paletteKeyDecoder : Palette.Model -> D.Decoder ( Msg, Bool )
paletteKeyDecoder palette =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                case key of
                    "ArrowDown" ->
                        D.succeed ( PaletteStep 1, True )

                    "ArrowUp" ->
                        D.succeed ( PaletteStep -1, True )

                    "Enter" ->
                        D.succeed ( PaletteChoose (Palette.active palette), True )

                    "Escape" ->
                        D.succeed ( ClosePalette, True )

                    _ ->
                        D.fail "not a palette key"
            )


findInputId : String
findInputId =
    "find-input"


viewFindBar : ( Int, Int ) -> Find.Model -> Html Msg
viewFindBar counts find =
    let
        ( current, total ) =
            counts

        countLabel =
            if find.query == "" then
                ""

            else if total == 0 then
                "No results"

            else
                String.fromInt current
                    ++ " of "
                    ++ String.fromInt total
                    ++ (if total >= Find.matchLimit then
                            "+"

                        else
                            ""
                       )

        stepButton label delta =
            button
                [ class "find-button"
                , attribute "aria-label" label
                , title label
                , disabled (total == 0)
                , onClick (FindStep delta)
                ]
                [ text
                    (if delta < 0 then
                        "↑"

                     else
                        "↓"
                    )
                ]
    in
    div [ class "find-bar", attribute "data-testid" "find-bar" ]
        [ div [ class "find-row" ]
            [ input
                [ class "find-input"
                , id findInputId
                , attribute "data-testid" "find-input"
                , attribute "aria-label" "Find"
                , placeholder "Find"
                , value find.query
                , spellcheck False
                , onInput FindQueryChanged
                , preventDefaultOn "keydown" (findKeyDecoder False)
                ]
                []
            , span [ class "find-count", attribute "data-testid" "find-count" ] [ text countLabel ]
            , button
                [ class "find-button"
                , classList [ ( "on", find.caseSensitive ) ]
                , attribute "aria-label" "Match case"
                , attribute "aria-pressed"
                    (if find.caseSensitive then
                        "true"

                     else
                        "false"
                    )
                , title "Match case"
                , onClick FindToggleCase
                ]
                [ text "Aa" ]
            , stepButton "Previous match" -1
            , stepButton "Next match" 1
            , button [ class "find-button", attribute "aria-label" "Close find", title "Close", onClick CloseFind ] [ text "×" ]
            ]
        , if find.replaceShown then
            div [ class "find-row" ]
                [ input
                    [ class "find-input"
                    , attribute "data-testid" "replace-input"
                    , attribute "aria-label" "Replace with"
                    , placeholder "Replace"
                    , value find.replacement
                    , spellcheck False
                    , onInput FindReplacementChanged
                    , preventDefaultOn "keydown" (findKeyDecoder True)
                    ]
                    []
                , button
                    [ class "find-button wide"
                    , attribute "data-testid" "replace-one"
                    , disabled (total == 0)
                    , onClick ReplaceActive
                    ]
                    [ text "Replace" ]
                , button
                    [ class "find-button wide"
                    , attribute "data-testid" "replace-all"
                    , disabled (total == 0)
                    , onClick ReplaceAll
                    ]
                    [ text "All" ]
                ]

          else
            text ""
        ]


{-| Keys inside the find fields. Enter steps through matches (or replaces, in
the replacement field) and Escape closes; everything else is ordinary typing.
-}
findKeyDecoder : Bool -> D.Decoder ( Msg, Bool )
findKeyDecoder inReplacement =
    D.map2 Tuple.pair (D.field "key" D.string) (D.field "shiftKey" D.bool)
        |> D.andThen
            (\( key, shift ) ->
                case key of
                    "Enter" ->
                        D.succeed
                            ( if inReplacement then
                                ReplaceActive

                              else
                                FindStep
                                    (if shift then
                                        -1

                                     else
                                        1
                                    )
                            , True
                            )

                    "Escape" ->
                        D.succeed ( CloseFind, True )

                    _ ->
                        D.fail "not a find key"
            )


{-| The right sidebar: a clickable outline of the document's headings,
filtered to the configured maximum depth.
-}
viewOutline : Model -> Html Msg
viewOutline model =
    let
        entries =
            List.filter (\e -> e.level <= model.outlineMaxLevel) model.outline
    in
    div [ class "outline-pane", attribute "data-testid" "outline-pane" ]
        [ div [ class "pane-header" ]
            [ span [] [ text "Outline" ] ]
        , div [ class "outline-content" ]
            (if List.isEmpty entries then
                [ div [ class "outline-empty", attribute "data-testid" "outline-empty" ] [ text "No headings" ] ]

             else
                List.map viewOutlineEntry entries
            )
        ]


{-| Word, line and character counts, shown in the editor's pane header. -}
countsLabel : Counts -> String
countsLabel counts =
    let
        plural n word =
            String.fromInt n
                ++ " "
                ++ word
                ++ (if n == 1 then
                        ""

                    else
                        "s"
                   )
    in
    String.join " · " [ plural counts.words "word", plural counts.lines "line", plural counts.characters "character" ]


viewOutlineEntry : Markdown.OutlineEntry -> Html Msg
viewOutlineEntry entry =
    button
        [ class "outline-entry"
        , attribute "data-testid" "outline-entry"
        , attribute "data-heading-id" entry.id
        , class ("outline-level-" ++ String.fromInt entry.level)
        , onClick (ScrollToHeading entry.id)
        ]
        [ text entry.text ]


viewTitleBar : Model -> Html Msg
viewTitleBar model =
    div [ class "titlebar", attribute "data-testid" "titlebar" ]
        [ div [ class "titlebar-traffic-pad" ] []
        , div [ class "titlebar-title" ]
            [ span [ class "titlebar-app-name" ] [ text "Fence" ]
            , case model.editor.filePath of
                Just path ->
                    span []
                        [ span [ class "titlebar-separator" ] [ text " — " ]
                        , span [ class "titlebar-filename", attribute "data-testid" "titlebar-filename" ]
                            [ text
                                (baseName path
                                    ++ (if model.editor.dirtyState == Dirty then
                                            " *"

                                        else
                                            ""
                                       )
                                )
                            ]
                        ]

                Nothing ->
                    text ""
            ]
        , div [ class "titlebar-actions" ]
            [ viewLayoutSelector model
            , button [ class "icon-button settings-btn", attribute "data-testid" "settings-button", onClick ToggleSettings ] [ Icon.settings 16 ]
            , if model.settingsOpen then
                viewSettingsDropdown model

              else
                text ""
            ]
        ]


themes : List ( String, String )
themes =
    [ ( "", "Catppuccin Mocha" )
    , ( "light", "Catppuccin Latte" )
    , ( "github-dark", "GitHub Dark" )
    , ( "vscode-dark", "VS Code Dark+" )
    , ( "fleet-dark", "Fleet Dark" )
    , ( "dracula", "Dracula" )
    , ( "one-dark", "One Dark Pro" )
    , ( "tokyo-night", "Tokyo Night" )
    , ( "nord", "Nord" )
    ]


fonts : List ( String, String )
fonts =
    [ ( "", "System Default" )
    , ( "JetBrains Mono", "JetBrains Mono" )
    , ( "IBM Plex Mono", "IBM Plex Mono" )
    , ( "Fira Code", "Fira Code" )
    , ( "Hack", "Hack" )
    , ( "Source Code Pro", "Source Code Pro" )
    , ( "Inconsolata", "Inconsolata" )
    , ( "Cascadia Code", "Cascadia Code" )
    , ( "Monaspace Neon", "Monaspace Neon" )
    , ( "Victor Mono", "Victor Mono" )
    , ( "Iosevka", "Iosevka" )
    ]


settingsKeyDecoder : D.Decoder ( Msg, Bool )
settingsKeyDecoder =
    D.field "key" D.string
        |> D.map
            (\key ->
                if List.member key [ "ArrowDown", "ArrowUp", "Enter", " ", "Escape", "Home", "End" ] then
                    ( SettingsKeyDown key, True )

                else
                    ( NoOp, False )
            )


viewSettingsDropdown : Model -> Html Msg
viewSettingsDropdown model =
    let
        themeOffset =
            0

        fontOffset =
            List.length themes

        {- Each list keeps its own tab stop: the option the arrow keys are on
           when they are in that list, otherwise the selected one. A listbox
           whose only tab stop lives in a sibling list cannot be tabbed into.
        -}
        tabbableIn offset items activeValue =
            if model.settingsFocus >= offset && model.settingsFocus < offset + List.length items then
                model.settingsFocus

            else
                offset + (indexOfValue activeValue items |> Maybe.withDefault 0)
    in
    div [ class "settings-layer" ]
        [ div [ class "settings-backdrop", onClick CloseSettings ] []
        , div
            [ class "settings-dropdown"
            , attribute "data-testid" "settings-dropdown"
            , attribute "role" "listbox"
            , attribute "aria-label" "Settings"
            ]
            [ div [ class "settings-dropdown-label" ] [ text "Theme" ]
            , div [ class "settings-dropdown-list", tabindex -1 ]
                (List.indexedMap (\i item -> viewSettingsItem model SetTheme model.theme (tabbableIn themeOffset themes model.theme) (themeOffset + i) item) themes)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font" ]
            , div [ class "settings-dropdown-list", tabindex -1 ]
                (List.indexedMap (\i item -> viewSettingsItem model SetFont model.font (tabbableIn fontOffset fonts model.font) (fontOffset + i) item) fonts)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font Size" ]
            , viewStepper "Editor" model.editorFontSize SetEditorFontSize
            , viewStepper "Preview" model.previewFontSize SetPreviewFontSize
            , viewStepper "UI" model.uiFontSize SetUIFontSize
            , label [ class "settings-dropdown-row" ]
                [ span [ class "settings-dropdown-row-label" ] [ text "Soft wrap" ]
                , input [ type_ "checkbox", checked model.editor.softWrap, onCheck SetSoftWrap, attribute "data-testid" "soft-wrap-toggle" ] []
                ]
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Outline" ]
            , viewOutlineLevelStepper model.outlineMaxLevel
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Shortcuts" ]
            , viewRebindRow "Toggle left sidebar" model.leftToggleKey RebindLeft model.rebinding
            , viewRebindRow "Cycle layout" model.layoutCycleKey RebindLayout model.rebinding
            , viewRebindRow "Toggle right sidebar" model.rightToggleKey RebindRight model.rebinding
            ]
        ]


{-| Integer +/- stepper for the maximum heading level shown in the outline.
-}
viewOutlineLevelStepper : Int -> Html Msg
viewOutlineLevelStepper level =
    div [ class "settings-dropdown-row" ]
        [ span [ class "settings-dropdown-row-label" ] [ text "Max depth" ]
        , div [ class "stepper" ]
            [ button
                [ class "stepper-btn"
                , onClick (SetOutlineMaxLevel (level - 1))
                ]
                [ text "−" ]
            , span [ class "stepper-value" ] [ text ("H" ++ String.fromInt level) ]
            , button
                [ class "stepper-btn"
                , onClick (SetOutlineMaxLevel (level + 1))
                ]
                [ text "+" ]
            ]
        ]


{-| A row showing a shortcut's current combo plus a button to rebind it.
While capturing, the button prompts for the next keypress.
-}
viewRebindRow : String -> KeyBinding -> RebindTarget -> Maybe RebindTarget -> Html Msg
viewRebindRow label binding target rebinding =
    let
        isCapturing =
            rebinding == Just target
    in
    div [ class "settings-dropdown-row" ]
        [ span [ class "settings-dropdown-row-label" ] [ text label ]
        , button
            [ class "rebind-btn"
            , classList [ ( "capturing", isCapturing ) ]
            , onClick (StartRebind target)
            ]
            [ text
                (if isCapturing then
                    "Press keys…"

                 else
                    keyBindingLabel binding
                )
            ]
        ]


{-| Where a value sits in one of the settings lists. -}
indexOfValue : String -> List ( String, String ) -> Maybe Int
indexOfValue wanted items =
    items
        |> List.indexedMap (\i ( value, _ ) -> ( i, value ))
        |> List.filter (\( _, value ) -> value == wanted)
        |> List.head
        |> Maybe.map Tuple.first


{-| One selectable row in the settings listbox. Used for both the theme and
font lists; only the active value and the click message differ.
-}
viewSettingsItem : Model -> (String -> Msg) -> String -> Int -> Int -> ( String, String ) -> Html Msg
viewSettingsItem model toMsg activeValue tabbable idx ( itemValue, displayName ) =
    let
        isActive =
            activeValue == itemValue

        isFocused =
            tabbable == idx
    in
    button
        [ class "settings-dropdown-item"
        , classList [ ( "active", isActive ) ]
        , attribute "data-testid"
            ("settings-item-"
                ++ (if String.isEmpty itemValue then
                        "default"

                    else
                        itemValue
                   )
            )
        , id (settingsItemId idx)
        , tabindex
            (if isFocused then
                0

             else
                -1
            )
        , attribute "role" "option"
        , attribute "aria-selected"
            (if isActive then
                "true"

             else
                "false"
            )
        , onClick (toMsg itemValue)
        , onFocus (SettingsFocused idx)
        , preventDefaultOn "keydown" settingsKeyDecoder
        ]
        [ span [ class "settings-dropdown-item-label" ] [ text displayName ]
        , span [ class "settings-dropdown-check" ]
            [ if isActive then
                Icon.checkmark 14

              else
                text ""
            ]
        ]


viewStepper : String -> Float -> (Float -> Msg) -> Html Msg
viewStepper label currentValue toMsg =
    div [ class "settings-dropdown-row" ]
        [ span [ class "settings-dropdown-row-label" ] [ text label ]
        , div [ class "stepper" ]
            [ button
                [ class "stepper-btn"
                , onClick (toMsg (currentValue - 1))
                ]
                [ text "−" ]
            , input
                [ type_ "number"
                , class "stepper-input"
                , Html.Attributes.step "0.1"
                , Html.Attributes.min "8"
                , Html.Attributes.max "32"
                , value (formatSize currentValue)
                , onInput (\s -> toMsg (Maybe.withDefault currentValue (String.toFloat s)))
                ]
                []
            , button
                [ class "stepper-btn"
                , onClick (toMsg (currentValue + 1))
                ]
                [ text "+" ]
            ]
        ]


formatSize : Float -> String
formatSize f =
    let
        rounded =
            toFloat (round (f * 10)) / 10

        str =
            String.fromFloat rounded
    in
    if String.contains "." str then
        str

    else
        str ++ ".0"


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }
