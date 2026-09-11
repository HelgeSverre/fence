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
    , visibleSettingsOptions
    )

import Array
import Browser
import Browser.Dom
import Browser.Events
import Decoders exposing (..)
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
import Preferences exposing (Picker(..), Preferences, PreviewWidth(..))
import Preview
import PreviewSync exposing (SyncPoint, syncAnchors)
import Process
import Task
import TextBuffer exposing (Cursor)
import Tooltip exposing (Tooltip)
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
    , navigationBusy : Bool
    , pendingExport : Maybe String
    , savingContent : Maybe String
    , reloadGeneration : Int
    , pendingReload : Maybe { id : Int, path : FilePath, editGeneration : Int }
    , preferences : Preferences
    , layoutMode : LayoutMode
    , layoutCycleKey : KeyBinding
    , previewFindCount : ( Int, Int )
    , settingsOpen : Bool
    , settingsFocus : Int
    , expandedPicker : Maybe Picker
    , pickerFilter : String
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
    | SetPreference (Preferences -> Preferences)
    | SetSoftWrap Bool
    | ExpandPicker (Maybe Picker)
    | PickerFilterChanged String
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
    | FindMsg Find.Msg
    | PaletteMsg Palette.Msg
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


defaultWindowWidth : Float
defaultWindowWidth =
    1400


settingsItemId : Int -> String
settingsItemId n =
    "settings-item-" ++ String.fromInt n


pickerSlug : Picker -> String
pickerSlug picker =
    case picker of
        ThemePicker ->
            "theme"

        EditorFontPicker ->
            "editor-font"

        UIFontPicker ->
            "ui-font"


pickerId : Picker -> String
pickerId picker =
    "settings-picker-" ++ pickerSlug picker


pickerSearchId : String
pickerSearchId =
    "settings-picker-search"


{-| The options the arrow keys can reach: the expanded picker's, filtered.
-}
visibleSettingsOptions : Model -> List ( String, String )
visibleSettingsOptions model =
    case model.expandedPicker of
        Nothing ->
            []

        Just picker ->
            let
                needle =
                    String.toLower (String.trim model.pickerFilter)
            in
            List.filter
                (\( _, label ) -> String.contains needle (String.toLower label))
                (Preferences.options picker)


focusSilently : String -> Cmd Msg
focusSilently elementId =
    ignoreResult (Browser.Dom.focus elementId)


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        flag name decoder default =
            D.decodeValue (D.field name decoder) flagsValue
                |> Result.withDefault default

        preferences =
            Preferences.decode flagsValue
    in
    ( { fileTree = FileTree.init
      , editor = Editor.update (Editor.SetSoftWrap preferences.softWrap) Editor.init
      , previewHtml = []
      , parseCache = Markdown.emptyCache
      , parseProgress = Nothing
      , framePainted = False
      , frontmatter = Nothing
      , debounceGeneration = 0
      , recoveryGeneration = 0
      , navigationBusy = False
      , pendingExport = Nothing
      , savingContent = Nothing
      , reloadGeneration = 0
      , pendingReload = Nothing
      , preferences = preferences
      , layoutMode = layoutFromString (flag "layoutMode" D.string "split")
      , layoutCycleKey = flag "layoutCycleKey" keyBindingDecoder { key = "2", meta = True, ctrl = False, shift = False, alt = False }
      , previewFindCount = ( 0, 0 )
      , settingsOpen = False
      , settingsFocus = 0
      , expandedPicker = Nothing
      , pickerFilter = ""
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
            ( { model | settingsOpen = open, settingsFocus = 0, expandedPicker = Nothing, pickerFilter = "" }
            , if open then
                focusSilently (pickerId ThemePicker)

              else
                Cmd.none
            )

        SetPreference change ->
            savePreferences (Preferences.clamp (change model.preferences)) model

        SetSoftWrap enabled ->
            -- Editor owns the behaviour; Preferences carries the persisted copy.
            let
                ( changed, cmd ) =
                    update (EditorMsg (Editor.SetSoftWrap enabled)) model

                prefs =
                    model.preferences
            in
            savePreferences { prefs | softWrap = enabled } changed
                |> Tuple.mapSecond (\saveCmd -> Cmd.batch [ cmd, saveCmd ])

        ExpandPicker picker ->
            ( { model | expandedPicker = picker, pickerFilter = "", settingsFocus = 0 }
            , case picker of
                Just _ ->
                    focusSilently pickerSearchId

                Nothing ->
                    Cmd.none
            )

        PickerFilterChanged text ->
            ( { model | pickerFilter = text, settingsFocus = 0 }, Cmd.none )

        CloseSettings ->
            ( { model | settingsOpen = False }, Cmd.none )

        SettingsFocused idx ->
            ( { model | settingsFocus = idx }, Cmd.none )

        SettingsKeyDown key ->
            let
                visible =
                    visibleSettingsOptions model

                itemCount =
                    List.length visible

                focus =
                    model.settingsFocus

                moveFocus newFocus =
                    ( { model | settingsFocus = newFocus }
                    , focusSilently (settingsItemId newFocus)
                    )

                activateFocused =
                    Maybe.map2
                        (\picker ( optionValue, _ ) ->
                            update (SetPreference (Preferences.select picker optionValue)) model
                        )
                        model.expandedPicker
                        (List.head (List.drop focus visible))
                        |> Maybe.withDefault ( model, Cmd.none )
            in
            if key == "Escape" then
                ( { model | settingsOpen = False }, Cmd.none )

            else if itemCount == 0 then
                ( model, Cmd.none )

            else
                case key of
                    "ArrowDown" ->
                        moveFocus (Basics.min (itemCount - 1) (focus + 1))

                    "ArrowUp" ->
                        moveFocus (Basics.max 0 (focus - 1))

                    "Enter" ->
                        activateFocused

                    " " ->
                        activateFocused

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
            , Cmd.batch [ layoutCmd, focusSilently Find.inputId, previewFindCmd 0 newModel ]
            )

        FindMsg subMsg ->
            let
                ( find, outCmds ) =
                    Find.update subMsg (model.layoutMode == PreviewOnly) model.editor.lines model.find
            in
            List.foldl runFindCmd ( { model | find = find }, Cmd.none ) outCmds

        PaletteMsg subMsg ->
            let
                ( palette, outCmds ) =
                    Palette.update subMsg model.fileTree.rootPath model.palette
            in
            ( { model | palette = palette }
            , Cmd.batch (List.map (runPaletteCmd model) outCmds)
            )

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
            if model.navigationBusy && (case subMsg of
                Editor.MetricsChanged _ -> False
                Editor.ScrollChanged _ _ -> False
                _ -> True
            ) then
                ( model, Cmd.none )

            else
                updateEditor subMsg model

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
                    if String.toLower key == "s" && (metaKey || ctrlKey) then
                        saveFileAs shiftKey model

                    else if key == "Escape" && model.settingsOpen then
                        ( { model | settingsOpen = False }, Cmd.none )

                    else if key == "f" && (metaKey || ctrlKey) && shiftKey then
                        update (PaletteMsg (Palette.Open Palette.Search)) model

                    else if key == "f" && (metaKey || ctrlKey) then
                        update (OpenFind altKey) model

                    else if key == "p" && (metaKey || ctrlKey) then
                        update (PaletteMsg (Palette.Open Palette.Files)) model

                    else if key == "Escape" && Palette.isOpen model.palette then
                        update (PaletteMsg Palette.Close) model

                    else if key == "[" && (metaKey || ctrlKey) then
                        update (NavigateHistory 1) model

                    else if key == "]" && (metaKey || ctrlKey) then
                        update (NavigateHistory -1) model

                    else if key == "g" && (metaKey || ctrlKey) && Find.isOpen model.find then
                        update
                            (FindMsg
                                (Find.Step
                                    (if shiftKey then
                                        -1

                                     else
                                        1
                                    )
                                )
                            )
                            model

                    else if key == "Escape" && Find.isOpen model.find then
                        update (FindMsg Find.Close) model

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


{-| Show the active match: select it in the editor and scroll it into view.
Focus stays in the find field, so Enter keeps stepping through matches.
-}
updateEditor : Editor.Msg -> Model -> ( Model, Cmd Msg )
updateEditor subMsg model =
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
            , sessionCmd newEditor
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
            , sessionCmd newEditor
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



{-| Where focus goes when an overlay closes: the visible document pane. -}
documentFocusId : Model -> String
documentFocusId model =
    if model.layoutMode == PreviewOnly then
        "preview-container"

    else
        "veditor-input"


runPaletteCmd : Model -> Palette.OutCmd -> Cmd Msg
runPaletteCmd model outCmd =
    case outCmd of
        Palette.CmdFocusInput ->
            focusSilently Palette.inputId

        Palette.CmdFocusDocument ->
            focusSilently (documentFocusId model)

        Palette.CmdListFiles root ->
            command "listFiles" [ ( "path", E.string root ) ]

        Palette.CmdDebounceSearch generation ->
            Task.perform (\_ -> PaletteMsg (Palette.SearchDue generation)) (Process.sleep Palette.searchDelay)

        Palette.CmdSearch root text ->
            command "searchWorkspace" [ ( "path", E.string root ), ( "query", E.string text ) ]

        Palette.CmdReadFile path line ->
            command "readFile"
                (( "path", E.string path )
                    :: (case line of
                            Just n ->
                                [ ( "line", E.int n ) ]

                            Nothing ->
                                []
                       )
                )


runFindCmd : Find.OutCmd -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
runFindCmd outCmd ( model, cmd ) =
    Tuple.mapSecond (\next -> Cmd.batch [ cmd, next ]) <|
        case outCmd of
            Find.CmdFocusDocument ->
                ( model, focusSilently (documentFocusId model) )

            Find.CmdPreviewFind delta ->
                ( model, previewFindCmd delta model )

            Find.CmdGoToActive ->
                goToActive model

            Find.CmdReplace ranges ->
                applyReplacement ranges model


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
            Markdown.begin previous { path = model.editor.filePath, version = model.debounceGeneration } model.editor.content
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
    ( if complete then
        { parsed | pendingExport = Nothing }

      else
        parsed
    , if complete then
        Cmd.batch
            [ measureSyncPoints parsed
            , case parsed.pendingExport of
                Just format ->
                    command "exportDocument"
                        [ ( "format", E.string format )
                        , ( "path", E.string (Maybe.withDefault "" parsed.editor.filePath) )
                        , ( "generation", E.int parsed.debounceGeneration )
                        , ( "title", E.string (Maybe.map baseName parsed.editor.filePath |> Maybe.withDefault "document") )
                        , ( "base", E.string (Maybe.map (\p -> "file://" ++ dirName p ++ "/") parsed.editor.filePath |> Maybe.withDefault "") )
                        ]

                Nothing ->
                    Cmd.none
            ]

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
saveFile =
    saveFileAs False


saveFileAs : Bool -> Model -> ( Model, Cmd Msg )
saveFileAs saveAs model =
    case ( model.editor.filePath, model.savingContent ) of
        ( path, Nothing ) ->
            ( { model | savingContent = Just model.editor.content, pendingReload = Nothing }
            , command "writeFile"
                [ ( "path", path |> Maybe.map E.string |> Maybe.withDefault E.null )
                , ( "saveAs", E.bool saveAs )
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
                    let
                        ( tree, treeCmds ) =
                            FileTree.handleDirContents path entries model.fileTree
                    in
                    ( { model | fileTree = tree }
                    , Cmd.batch
                        [ outCmdsToPortCmds treeCmds
                        , case ( model.fileTree.pendingReveal, tree.pendingReveal ) of
                            ( Just target, Nothing ) ->
                                revealScrollCmd target

                            _ ->
                                Cmd.none
                        ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "navigationCancelled" ->
            ( { model
                | navigating = False
                , historyPos = List.indexedMap Tuple.pair model.history |> List.filter (\( _, path ) -> Just path == model.editor.filePath) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault model.historyPos
                , fileTree = Maybe.map (\path -> FileTree.select path model.fileTree) model.editor.filePath |> Maybe.withDefault model.fileTree
              }
            , Cmd.none
            )

        "navigationBusy" ->
            ( { model | navigationBusy = D.decodeValue (D.field "busy" D.bool) value |> Result.withDefault False }, Cmd.none )

        "requestDocumentState" ->
            ( model
            , command "documentState"
                (( "id", D.decodeValue (D.field "id" D.int) value |> Result.withDefault 0 |> E.int )
                    :: ( "content", E.string model.editor.content )
                    :: ( "dirty", E.bool (model.editor.dirtyState == Dirty) )
                    :: ( "revision", model.editor.revision |> Maybe.map E.string |> Maybe.withDefault E.null )
                    :: sessionFields model.editor
                )
            )

        "documentClosed" ->
            let
                empty =
                    Editor.setContent "" "" "" False model.editor

                editor =
                    { empty | filePath = Nothing, revision = Nothing }
            in
            startParse Markdown.emptyCache
                { model | editor = editor, savingContent = Nothing, pendingReload = Nothing, history = [], historyPos = 0, pendingExport = Nothing, debounceGeneration = model.debounceGeneration + 1 }
                |> (\( updated, cmd ) -> ( updated, Cmd.batch [ cmd, setDirtyCmd False, setTitleCmd editor, sessionCmd editor ] ))

        "restoreSession" ->
            case D.decodeValue (D.map4 (\line col top left -> ( { line = line, col = col }, top, left )) (D.field "line" D.int) (D.field "col" D.int) (D.field "top" D.float) (D.field "left" D.float)) value of
                Ok ( cursor, top, left ) ->
                    let
                        editor =
                            Editor.restorePosition cursor top left model.editor
                    in
                    ( { model | editor = editor }
                    , Cmd.batch [ sessionCmd editor, ignoreResult (Browser.Dom.setViewportOf "veditor" editor.scrollLeft editor.scrollTop) ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "fileSavedAs" ->
            case D.decodeValue fileContentDecoder value of
                Ok file ->
                    if D.decodeValue (D.field "originalPath" (D.nullable D.string)) value /= Ok model.editor.filePath then
                        ( model, Cmd.none )

                    else
                        let
                            old =
                                model.editor

                            editor =
                                { old | filePath = Just file.path }
                        in
                        handlePortMessage "fileSaved" value
                            { model
                                | editor = editor
                                , savingContent = Just file.content
                                , fileTree = FileTree.select file.path model.fileTree
                                , history = file.path :: List.filter ((/=) file.path) model.history |> List.take historyLimit
                                , historyPos = 0
                            }

                Err _ ->
                    ( model, Cmd.none )

        "saveRequested" ->
            saveFile model

        "saveAsRequested" ->
            saveFileAs True model

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

                        ( tree, treeCmds ) =
                            if model.preferences.revealInSidebar then
                                FileTree.reveal file.path model.fileTree

                            else
                                ( FileTree.select file.path model.fileTree, [] )

                        ( parsedModel, parseCmd ) =
                            startParse Markdown.emptyCache
                                { model
                                    | editor = newEditor
                                    , fileTree = tree
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
                        , sessionCmd newEditor
                        , setDirtyCmd file.dirty
                        , parseCmd
                        , outCmdsToPortCmds treeCmds
                        , if model.preferences.revealInSidebar then
                            revealScrollCmd file.path

                          else
                            Cmd.none

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
                            D.decodeValue (D.field "content" D.string) value
                                |> Result.withDefault (Maybe.withDefault model.editor.content model.savingContent)

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
                            , sessionCmd newEditor
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
            case D.decodeValue (D.field "format" D.string) value of
                Ok format ->
                    startParse model.parseCache { model | pendingExport = Just format }

                Err _ ->
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
                    , Cmd.batch [ setTitleCmd (Editor.followRename from to model.editor), sessionCmd (Editor.followRename from to model.editor) ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "saveAndClose" ->
            let
                ( newModel, saveCmd ) =
                    saveFile model
            in
            ( { newModel | closeAfterSave = True }, saveCmd )

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


sessionFields : Editor.Model -> List ( String, E.Value )
sessionFields editor =
    [ ( "path", editor.filePath |> Maybe.map E.string |> Maybe.withDefault E.null )
    , ( "line", E.int editor.cursor.line )
    , ( "col", E.int editor.cursor.col )
    , ( "top", E.float editor.scrollTop )
    , ( "left", E.float editor.scrollLeft )
    ]


sessionCmd : Editor.Model -> Cmd Msg
sessionCmd editor =
    command "saveSession" (sessionFields editor)


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


{-| Bring a tree row into the sidebar's viewport without focusing it. Rows
already in view stay put; a row that is not rendered yet is a no-op.
-}
revealScrollCmd : FilePath -> Cmd Msg
revealScrollCmd path =
    Task.map3
        (\row pane viewport ->
            let
                rowTop =
                    row.element.y - pane.element.y

                rowBottom =
                    rowTop + row.element.height
            in
            if rowTop >= 0 && rowBottom <= viewport.viewport.height then
                Nothing

            else
                Just (Basics.max 0 (viewport.viewport.y + rowTop - (viewport.viewport.height - row.element.height) / 2))
        )
        (Browser.Dom.getElement (treeItemId path))
        (Browser.Dom.getElement "sidebar-content")
        (Browser.Dom.getViewportOf "sidebar-content")
        |> Task.andThen
            (\target ->
                case target of
                    Just y ->
                        Browser.Dom.setViewportOf "sidebar-content" 0 y

                    Nothing ->
                        Task.succeed ()
            )
        |> ignoreResult


{-| Run a task purely for its effect.
-}
ignoreResult : Task.Task x a -> Cmd Msg
ignoreResult =
    Task.attempt (\_ -> NoOp)


savePreferences : Preferences -> Model -> ( Model, Cmd Msg )
savePreferences prefs model =
    ( { model | preferences = prefs }, command "setPreferences" (Preferences.encode prefs) )


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



-- PREVIEW SYNC (see PreviewSync.elm)


syncPreview : Editor.Model -> Model -> Cmd Msg
syncPreview editor model =
    PreviewSync.syncPreview NoOp (model.layoutMode == Split) model.syncPoints editor


measureSyncPoints : Model -> Cmd Msg
measureSyncPoints model =
    PreviewSync.measureSyncPoints SyncPointsMeasured (model.layoutMode == Split) model.headingAnchors model.editor


scrollToHeadingCmd : String -> Model -> Cmd Msg
scrollToHeadingCmd anchorId model =
    PreviewSync.scrollToHeadingCmd NoOp (model.layoutMode == PreviewOnly) model.headingAnchors model.editor anchorId


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

        prefs =
            model.preferences
    in
    div []
        [ div
            ([ class "app-shell"
             , attribute "aria-busy"
                (if model.navigationBusy then
                    "true"

                 else
                    "false"
                )
             , classList
                [ ( "navigation-busy", model.navigationBusy )
                , ( "hide-pane-headers", not prefs.showPaneHeaders )
                , ( "preview-mono", prefs.previewUsesEditorFont )
                ]
             ]
                ++ (case Preferences.previewWidthPx prefs of
                        Just px ->
                            -- Elm's `style` cannot set a CSS custom property.
                            [ attribute "style" ("--preview-max-width: " ++ String.fromInt px ++ "px") ]

                        Nothing ->
                            []
                   )
            )
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
            Html.map PaletteMsg (Palette.view model.palette)

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
            Html.map FindMsg (Find.view (Find.count model.find) model.find)

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
         , attribute "data-render-generation" (String.fromInt model.debounceGeneration)
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
            Html.map FindMsg (Find.view model.previewFindCount model.find)

          else
            text ""
        ]


viewLayoutSelector : Model -> Html Msg
viewLayoutSelector model =
    let
        segment mode label body icon =
            button
                ([ class "icon-button layout-segment"
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
                    ++ Tooltip.host (tipName mode)
                )
                [ icon 16
                , Tooltip.view (tipName mode)
                    { heading = label
                    , body = body
                    , shortcut = Just (keyBindingLabel model.layoutCycleKey)
                    }
                ]

        tipName mode =
            "layout-" ++ layoutName mode
    in
    div [ class "layout-selector", attribute "role" "radiogroup", attribute "aria-label" "Document layout" ]
        [ segment EditorOnly "Editor only" "Hide the preview and give the editor the full width." Icon.editorLayout
        , segment Split "Editor and preview" "Editor on the left, live preview on the right." Icon.splitLayout
        , segment PreviewOnly "Preview only" "Hide the editor and show only the rendered document." Icon.previewLayout
        ]


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
            , button
                ([ class "icon-button open-folder-btn"
                 , attribute "data-testid" "open-folder-button"
                 , attribute "aria-label" "Open folder"
                 , onClick (FileTreeMsg FileTree.OpenFolder)
                 ]
                    ++ Tooltip.host "open-folder"
                )
                [ Icon.folderPlus 16
                , Tooltip.view "open-folder"
                    { heading = "Open folder"
                    , body = "Choose a folder as the workspace; its Markdown files fill the sidebar."
                    , shortcut = Nothing
                    }
                ]
            , button
                ([ class "icon-button settings-btn", attribute "data-testid" "settings-button", onClick ToggleSettings ]
                    ++ Tooltip.host "settings"
                )
                [ Icon.settings 16
                , Tooltip.view "settings"
                    { heading = "Settings"
                    , body = "Theme, fonts, preview width, layout and shortcuts."
                    , shortcut = Nothing
                    }
                ]
            , if model.settingsOpen then
                viewSettingsDropdown model

              else
                text ""
            ]
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


{-| From the filter box: down steps into the list, Enter takes the first hit.
-}
searchKeyDecoder : D.Decoder ( Msg, Bool )
searchKeyDecoder =
    D.field "key" D.string
        |> D.map
            (\key ->
                case key of
                    "ArrowDown" ->
                        ( SettingsKeyDown "Home", True )

                    "Enter" ->
                        ( SettingsKeyDown "Enter", True )

                    "Escape" ->
                        ( CloseSettings, True )

                    _ ->
                        ( NoOp, False )
            )


viewSettingsDropdown : Model -> Html Msg
viewSettingsDropdown model =
    let
        prefs =
            model.preferences

        toggle field on =
            SetPreference (field on)

        tip heading body =
            { heading = heading, body = body, shortcut = Nothing }

        fontSize tooltip label testId max size field =
            viewStepper
                { label = label
                , value = size
                , min = Preferences.fontSizeMin
                , max = max
                , step = 1
                , format = formatSize
                , toMsg = \v -> SetPreference (field v)
                , testId = testId
                , tooltip = tooltip
                }
    in
    div [ class "settings-layer" ]
        [ div [ class "settings-backdrop", onClick CloseSettings ] []
        , div
            [ class "settings-dropdown"
            , attribute "data-testid" "settings-dropdown"
            , attribute "role" "listbox"
            , attribute "aria-label" "Settings"
            ]
            [ viewPicker model ThemePicker "Theme" (tip "Theme" "Colour scheme for the editor, preview and chrome. Default: GitHub Dark.")
            , viewPicker model EditorFontPicker "Editor font" (tip "Editor font" "Monospace face for the editor, and for the preview when \"Use editor font\" is on. Default: system monospace.")
            , viewPicker model UIFontPicker "UI font" (tip "UI font" "Face for the file tree, pane headings, settings and palette. Default: system UI.")
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font Size" ]
            , fontSize (tip "Editor font size" "Text size in the editor, in pixels (8–32). Default: 14.") "Editor" "editor-font-size-input" Preferences.fontSizeMax prefs.editorFontSize (\v p -> { p | editorFontSize = v })
            , fontSize (tip "Preview font size" "Base size of preview text; headings scale from it (8–32). Default: 14.") "Preview" "preview-font-size-input" Preferences.fontSizeMax prefs.previewFontSize (\v p -> { p | previewFontSize = v })
            , fontSize (tip "UI font size" "Size of file tree, headings and settings text (8–24). Default: 13.") "UI" "ui-font-size-input" Preferences.uiFontSizeMax prefs.uiFontSize (\v p -> { p | uiFontSize = v })
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Preview" ]
            , viewSegmentedRow (tip "Preview width" "Caps and centres the preview column so lines wrap sooner. Narrow 560 px, Normal 680 px, Wide 900 px; Full uses the whole pane. Default: Full.") "Width" "preview-width" Preferences.previewWidthOptions prefs.previewWidth (\w -> SetPreference (\p -> { p | previewWidth = w }))
            , if prefs.previewWidth == Custom then
                viewStepper
                    { label = "Custom width"
                    , value = toFloat prefs.previewMaxWidth
                    , min = toFloat Preferences.previewWidthMin
                    , max = toFloat Preferences.previewWidthMax
                    , step = 10
                    , format = round >> String.fromInt
                    , toMsg = \v -> SetPreference (\p -> { p | previewMaxWidth = round v })
                    , testId = "preview-width-input"
                    , tooltip = tip "Custom width" "Preview column width in pixels (320–2000). Applies only while Width is Custom."
                    }

              else
                text ""
            , viewToggleRow (tip "Use editor font in preview" "Render the preview in the editor's monospace font instead of the UI font. Default: off.") "Use editor font" "preview-mono-toggle" prefs.previewUsesEditorFont (toggle (\on p -> { p | previewUsesEditorFont = on }))
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Layout" ]
            , viewToggleRow (tip "Pane headings" "Show the title strip above the file tree, editor, preview and outline. Default: on.") "Show pane headings" "pane-headers-toggle" prefs.showPaneHeaders (toggle (\on p -> { p | showPaneHeaders = on }))
            , viewToggleRow (tip "Soft wrap" "Wrap long lines at the editor's edge instead of scrolling sideways. Default: on.") "Soft wrap" "soft-wrap-toggle" model.editor.softWrap SetSoftWrap
            , viewToggleRow (tip "Reveal open file" "When a file opens from the palette, a link, history or the command line, expand the sidebar to it and select it. Default: on.") "Reveal open file" "reveal-in-sidebar-toggle" prefs.revealInSidebar (toggle (\on p -> { p | revealInSidebar = on }))
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Outline" ]
            , viewOutlineLevelStepper model.outlineMaxLevel
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Shortcuts" ]
            , viewRebindRow (tip "Toggle left sidebar" "Shortcut that shows or hides the file tree. Click, then press the new combination.") model.leftToggleKey RebindLeft model.rebinding
            , viewRebindRow (tip "Cycle layout" "Shortcut that steps through Editor, Split and Preview. Click, then press the new combination.") model.layoutCycleKey RebindLayout model.rebinding
            , viewRebindRow (tip "Toggle right sidebar" "Shortcut that shows or hides the outline. Click, then press the new combination.") model.rightToggleKey RebindRight model.rebinding
            ]
        ]


{-| A collapsible list of options: only one picker is open at a time, and only
its options take part in the keyboard walk.
-}
viewPicker : Model -> Picker -> String -> Tooltip -> Html Msg
viewPicker model picker title tip =
    let
        current =
            Preferences.selected picker model.preferences

        expanded =
            model.expandedPicker == Just picker

        currentLabel =
            Preferences.options picker
                |> List.filter (\( optionValue, _ ) -> optionValue == current)
                |> List.head
                |> Maybe.map Tuple.second
                |> Maybe.withDefault current

        visible =
            visibleSettingsOptions model

        {- The tab stop is where the arrows are, or the selected option so the
           list can be tabbed into at all.
        -}
        tabbable =
            if model.settingsFocus < List.length visible then
                model.settingsFocus

            else
                indexOfValue current visible |> Maybe.withDefault 0
    in
    div [ class "settings-picker" ]
        [ button
            ([ class "settings-picker-header"
             , id (pickerId picker)
             , attribute "data-testid" (pickerId picker)
             , attribute "aria-expanded"
                (if expanded then
                    "true"

                 else
                    "false"
                )
             , onClick
                (ExpandPicker
                    (if expanded then
                        Nothing

                     else
                        Just picker
                    )
                )
             ]
            )
            [ span (Tooltip.host (pickerId picker)) [ text title, Tooltip.view (pickerId picker) tip ]
            , span [ class "settings-picker-value" ] [ text currentLabel ]
            , span [ class "settings-picker-chevron" ] [ Icon.chevronRight 14 ]
            ]
        , if expanded then
            div [ class "settings-picker-body" ]
                [ input
                    [ type_ "text"
                    , class "settings-picker-search"
                    , id pickerSearchId
                    , attribute "data-testid" pickerSearchId
                    , placeholder "Filter…"
                    , value model.pickerFilter
                    , onInput PickerFilterChanged
                    , preventDefaultOn "keydown" searchKeyDecoder
                    , attribute "aria-label" (title ++ " filter")
                    ]
                    []
                , div [ class "settings-dropdown-list", tabindex -1 ]
                    (List.indexedMap (viewOption picker current tabbable) visible)
                ]

          else
            text ""
        ]


viewOption : Picker -> String -> Int -> Int -> ( String, String ) -> Html Msg
viewOption picker activeValue tabbable idx ( optionValue, displayName ) =
    let
        isActive =
            activeValue == optionValue
    in
    button
        [ class "settings-dropdown-item"
        , classList [ ( "active", isActive ) ]
        , attribute "data-testid"
            ("settings-option-"
                ++ pickerSlug picker
                ++ "-"
                ++ (if String.isEmpty optionValue then
                        "default"

                    else
                        optionValue
                   )
            )
        , id (settingsItemId idx)
        , tabindex
            (if tabbable == idx then
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
        , onClick (SetPreference (Preferences.select picker optionValue))
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


viewToggleRow : Tooltip -> String -> String -> Bool -> (Bool -> Msg) -> Html Msg
viewToggleRow tip rowLabel testId on toMsg =
    label [ class "settings-dropdown-row" ]
        [ viewRowLabel rowLabel testId tip
        , input [ type_ "checkbox", checked on, onCheck toMsg, attribute "data-testid" testId ] []
        ]


{-| A row's label text, which is also where its tooltip lives: hovering the
control itself should not explain it.
-}
viewRowLabel : String -> String -> Tooltip -> Html Msg
viewRowLabel rowLabel name tip =
    span (class "settings-dropdown-row-label" :: Tooltip.host name)
        [ text rowLabel, Tooltip.view name tip ]


{-| A settings row whose control is a group of text segments, one checked.
-}
viewSegmentedRow : Tooltip -> String -> String -> List ( a, String ) -> a -> (a -> Msg) -> Html Msg
viewSegmentedRow tip rowLabel idPrefix items current toMsg =
    div [ class "settings-dropdown-row" ]
        [ viewRowLabel rowLabel idPrefix tip
        , div
            [ class "segmented"
            , attribute "role" "radiogroup"
            , attribute "aria-label" rowLabel
            ]
            (List.map
                (\( value_, label_ ) ->
                    button
                        [ class "segment"
                        , attribute "role" "radio"
                        , attribute "aria-checked"
                            (if value_ == current then
                                "true"

                             else
                                "false"
                            )
                        , attribute "data-testid" (idPrefix ++ "-" ++ String.toLower label_)
                        , onClick (toMsg value_)
                        ]
                        [ text label_ ]
                )
                items
            )
        ]


{-| Integer +/- stepper for the maximum heading level shown in the outline.
-}
viewOutlineLevelStepper : Int -> Html Msg
viewOutlineLevelStepper level =
    div [ class "settings-dropdown-row" ]
        [ viewRowLabel "Max depth"
            "outline-depth"
            { heading = "Outline depth"
            , body = "Deepest heading level listed in the outline: H1 shows only top-level headings, H6 shows all. Default: H3."
            , shortcut = Nothing
            }
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
viewRebindRow : Tooltip -> KeyBinding -> RebindTarget -> Maybe RebindTarget -> Html Msg
viewRebindRow tip binding target rebinding =
    let
        isCapturing =
            rebinding == Just target

        name =
            case target of
                RebindLeft ->
                    "rebind-left"

                RebindLayout ->
                    "rebind-layout"

                RebindRight ->
                    "rebind-right"
    in
    div [ class "settings-dropdown-row" ]
        [ viewRowLabel tip.heading name { tip | shortcut = Just (keyBindingLabel binding) }
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


type alias Stepper =
    { label : String
    , value : Float
    , min : Float
    , max : Float
    , step : Float
    , format : Float -> String
    , toMsg : Float -> Msg
    , testId : String
    , tooltip : Tooltip
    }


viewStepper : Stepper -> Html Msg
viewStepper stepper =
    div [ class "settings-dropdown-row" ]
        [ viewRowLabel stepper.label stepper.testId stepper.tooltip
        , div [ class "stepper" ]
            [ button
                [ class "stepper-btn"
                , onClick (stepper.toMsg (stepper.value - stepper.step))
                ]
                [ text "−" ]
            , input
                [ type_ "number"
                , class "stepper-input"
                , attribute "data-testid" stepper.testId

                -- "any" so typed decimals survive; the buttons move by `step`.
                , Html.Attributes.step "any"
                , Html.Attributes.min (stepper.format stepper.min)
                , Html.Attributes.max (stepper.format stepper.max)
                , value (stepper.format stepper.value)
                , onInput (\typed -> stepper.toMsg (Maybe.withDefault stepper.value (String.toFloat typed)))
                ]
                []
            , button
                [ class "stepper-btn"
                , onClick (stepper.toMsg (stepper.value + stepper.step))
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
