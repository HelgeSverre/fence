module Main exposing
    ( DragTarget(..)
    , KeyBinding
    , Model
    , Msg(..)
    , init
    , keyBindingLabel
    , main
    , matchesBinding
    , previewDelay
    , update
    )

import Browser
import Browser.Dom
import Browser.Events
import Editor
import FileTree
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Lazy
import Icon
import Json.Decode as D
import Json.Encode as E
import Markdown
import Ports
import Preview
import Process
import Task
import Types exposing (..)
import VirtualEditor
import Yaml


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
    , theme : String
    , font : String
    , editorFontSize : Float
    , previewFontSize : Float
    , uiFontSize : Float
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
    , virtualEditor : Bool -- experimental read-only virtualized editor
    , leftToggleKey : KeyBinding
    , rightToggleKey : KeyBinding
    , rebinding : Maybe RebindTarget
    , errorMessage : Maybe String
    , closeAfterSave : Bool
    }


type Msg
    = FileTreeMsg FileTree.Msg
    | EditorMsg Editor.Msg
    | FromElectron D.Value
    | KeyDown String Bool Bool Bool Bool
    | DebouncedParse Int
    | ParseStep Int
    | Frame
    | RecoveryDraftDue Int
    | ToggleSettings
    | SetTheme String
    | SetFont String
    | SetEditorFontSize Float
    | SetPreviewFontSize Float
    | SetUIFontSize Float
    | CloseSettings
    | SettingsKeyDown String
    | DividerMouseDown DragTarget Float
    | DividerMouseMove Float
    | DividerMouseUp
    | DividerDoubleClick DragTarget
    | WindowResized Int Int
    | ToggleLeftSidebar
    | ToggleRightSidebar
    | SetOutlineMaxLevel Int
    | ToggleVirtualEditor
    | ScrollToHeading String
    | StartRebind RebindTarget
    | DismissError
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
    Task.attempt (\_ -> NoOp) (Browser.Dom.focus elementId)


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        flag name decoder default =
            D.decodeValue (D.field name decoder) flagsValue
                |> Result.withDefault default
    in
    ( { fileTree = FileTree.init
      , editor = Editor.init
      , previewHtml = []
      , parseCache = Markdown.emptyCache
      , parseProgress = Nothing
      , framePainted = False
      , frontmatter = Nothing
      , debounceGeneration = 0
      , recoveryGeneration = 0
      , savingContent = Nothing
      , theme = flag "theme" D.string "github-dark"
      , font = flag "font" D.string ""
      , editorFontSize = flag "editorFontSize" D.float defaultEditorFontSize
      , previewFontSize = flag "previewFontSize" D.float defaultPreviewFontSize
      , uiFontSize = flag "uiFontSize" D.float defaultUIFontSize
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
      , virtualEditor = flag "virtualEditor" D.bool False
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

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
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setTheme" )
                    , ( "theme", E.string themeValue )
                    ]
                )
            )

        SetFont fontValue ->
            ( { model | font = fontValue }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setFont" )
                    , ( "font", E.string fontValue )
                    ]
                )
            )

        SetEditorFontSize size ->
            let
                clamped =
                    clamp editorFontMin editorFontMax size
            in
            ( { model | editorFontSize = clamped }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setFontSize" )
                    , ( "editorFontSize", E.float clamped )
                    ]
                )
            )

        SetPreviewFontSize size ->
            let
                clamped =
                    clamp editorFontMin editorFontMax size
            in
            ( { model | previewFontSize = clamped }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setFontSize" )
                    , ( "previewFontSize", E.float clamped )
                    ]
                )
            )

        SetUIFontSize size ->
            let
                clamped =
                    clamp uiFontMin uiFontMax size
            in
            ( { model | uiFontSize = clamped }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setFontSize" )
                    , ( "uiFontSize", E.float clamped )
                    ]
                )
            )

        CloseSettings ->
            ( { model | settingsOpen = False }, Cmd.none )

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

        ToggleVirtualEditor ->
            let
                newModel =
                    { model | virtualEditor = not model.virtualEditor }
            in
            ( newModel, saveSplitsCmd newModel )

        ScrollToHeading anchorId ->
            ( model, scrollToHeadingCmd anchorId )

        StartRebind target ->
            ( { model | rebinding = Just target }, Cmd.none )

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

                -- keep the caret on screen and the hidden input focused
                virtualCmds =
                    if model.virtualEditor then
                        Cmd.batch
                            [ case ( newEditor.cursor /= model.editor.cursor, Editor.caretScroll newEditor ) of
                                ( True, Just target ) ->
                                    Task.attempt (\_ -> NoOp) (Browser.Dom.setViewportOf "veditor" target.left target.top)

                                _ ->
                                    Cmd.none
                            , case subMsg of
                                Editor.PointerDown _ ->
                                    focusSilently "veditor-input"

                                _ ->
                                    Cmd.none
                            ]

                    else
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
                  }
                , Cmd.batch
                    [ Task.perform (\_ -> DebouncedParse gen) (Process.sleep (previewDelay newEditor.content))
                    , Task.perform (\_ -> RecoveryDraftDue recoveryGen) (Process.sleep 1000)
                    , setTitleCmd newEditor
                    , setDirtyCmd True
                    , virtualCmds
                    ]
                )

            else
                case subMsg of
                    Editor.OverlayStep ->
                        ( { model | editor = newEditor, framePainted = False }, Cmd.none )

                    _ ->
                        ( { model | editor = newEditor }, virtualCmds )

        DebouncedParse gen ->
            if gen == model.debounceGeneration then
                startParse model.parseCache model

            else
                ( model, Cmd.none )

        Frame ->
            if model.framePainted then
                let
                    ( afterParse, _ ) =
                        update (ParseStep model.debounceGeneration) model

                    ( afterOverlay, _ ) =
                        update (EditorMsg Editor.OverlayStep) afterParse
                in
                ( { afterOverlay | framePainted = False }, Cmd.none )

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
                        in
                        ( newModel, saveSplitsCmd newModel )

                Nothing ->
                    if key == "s" && (metaKey || ctrlKey) then
                        saveFile model

                    else if key == "Escape" && model.settingsOpen then
                        ( { model | settingsOpen = False }, Cmd.none )

                    else if matchesBinding model.leftToggleKey key metaKey ctrlKey shiftKey altKey then
                        update ToggleLeftSidebar model

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
    continueParse firstParseBudget progress { model | frontmatter = frontmatter }


continueParse : Int -> Markdown.Progress Msg -> Model -> ( Model, Cmd Msg )
continueParse budget progress model =
    let
        stepped =
            Markdown.step budget progress

        complete =
            Markdown.isComplete stepped
    in
    ( { model
        | previewHtml = Markdown.htmlChunks stepped
        , outline = Markdown.outline stepped
        , parseCache = Markdown.cache stepped
        , parseProgress =
            if complete then
                Nothing

            else
                Just stepped
        , framePainted = False
      }
    , Cmd.none
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
            ( { model | savingContent = Just model.editor.content }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "writeFile" )
                    , ( "path", E.string path )
                    , ( "content", E.string model.editor.content )
                    , ( "expectedRevision"
                      , model.editor.revision
                            |> Maybe.map E.string
                            |> Maybe.withDefault E.null
                      )
                    ]
                )
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
                      }
                    , Cmd.batch
                        [ setTitleCmd newEditor
                        , setDirtyCmd file.dirty
                        , parseCmd
                        ]
                    )

                Err _ ->
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
                    in
                    ( { model | fileTree = newTree }
                    , if shouldReload then
                        Ports.toElectron
                            (E.object
                                [ ( "tag", E.string "readFile" )
                                , ( "path", E.string path )
                                ]
                            )

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

        "editorMetrics" ->
            case D.decodeValue VirtualEditor.metricsDecoder value of
                Ok metrics ->
                    ( { model | editor = Editor.update (Editor.MetricsChanged metrics) model.editor }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        "toggleSettings" ->
            update ToggleSettings model

        "triggerOpenFolder" ->
            ( model
            , Ports.toElectron (E.object [ ( "tag", E.string "openFolder" ) ])
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
    Ports.toElectron
        (E.object
            [ ( "tag", E.string "setTitle" )
            , ( "title", E.string title )
            ]
        )


setDirtyCmd : Bool -> Cmd Msg
setDirtyCmd dirty =
    Ports.toElectron
        (E.object
            [ ( "tag", E.string "setDirty" )
            , ( "dirty", E.bool dirty )
            ]
        )


closeWindowCmd : Cmd Msg
closeWindowCmd =
    Ports.toElectron (E.object [ ( "tag", E.string "closeWindow" ) ])


saveRecoveryDraftCmd : Editor.Model -> Cmd Msg
saveRecoveryDraftCmd editor =
    case editor.filePath of
        Just path ->
            Ports.toElectron
                (E.object
                    [ ( "tag", E.string "saveRecoveryDraft" )
                    , ( "path", E.string path )
                    , ( "content", E.string editor.content )
                    , ( "revision"
                      , editor.revision
                            |> Maybe.map E.string
                            |> Maybe.withDefault E.null
                      )
                    ]
                )

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


saveSplitsCmd : Model -> Cmd Msg
saveSplitsCmd model =
    Ports.toElectron
        (E.object
            [ ( "tag", E.string "saveSplits" )
            , ( "sidebarFraction", E.float model.sidebarFraction )
            , ( "editorFraction", E.float model.editorFraction )
            , ( "rightSidebarFraction", E.float model.rightSidebarFraction )
            , ( "leftSidebarVisible", E.bool model.leftSidebarVisible )
            , ( "rightSidebarVisible", E.bool model.rightSidebarVisible )
            , ( "outlineMaxLevel", E.int model.outlineMaxLevel )
            , ( "virtualEditor", E.bool model.virtualEditor )
            , ( "leftToggleKey", encodeKeyBinding model.leftToggleKey )
            , ( "rightToggleKey", encodeKeyBinding model.rightToggleKey )
            ]
        )


{-| Scroll the preview pane so the heading with `anchorId` is at the top.
Computes the heading's offset relative to the scrollable preview container.
-}
scrollToHeadingCmd : String -> Cmd Msg
scrollToHeadingCmd anchorId =
    Task.map3
        (\heading container containerVp ->
            -- Heading offset within the container's scrollable content.
            containerVp.viewport.y + heading.element.y - container.element.y
        )
        (Browser.Dom.getElement anchorId)
        (Browser.Dom.getElement "preview-container")
        (Browser.Dom.getViewportOf "preview-container")
        |> Task.andThen (\y -> Browser.Dom.setViewportOf "preview-container" 0 y)
        |> Task.attempt (\_ -> NoOp)


{-| Is this `event.key` value a bare modifier key (no real character)?
-}
isModifierKey : String -> Bool
isModifierKey key =
    List.member key [ "Meta", "Control", "Shift", "Alt", "CapsLock" ]



-- PORT COMMAND HELPERS


outCmdsToPortCmds : List FileTree.OutCmd -> Cmd Msg
outCmdsToPortCmds cmds =
    cmds
        |> List.filterMap outCmdToValue
        |> List.map Ports.toElectron
        |> Cmd.batch


outCmdToValue : FileTree.OutCmd -> Maybe E.Value
outCmdToValue cmd =
    case cmd of
        FileTree.CmdOpenFolder ->
            Just <| E.object [ ( "tag", E.string "openFolder" ) ]

        FileTree.CmdReadDir path ->
            Just <|
                E.object
                    [ ( "tag", E.string "readDir" )
                    , ( "path", E.string path )
                    ]

        FileTree.CmdReadFile path ->
            Just <|
                E.object
                    [ ( "tag", E.string "readFile" )
                    , ( "path", E.string path )
                    ]

        FileTree.CmdWatchDir path ->
            Just <|
                E.object
                    [ ( "tag", E.string "watchDir" )
                    , ( "path", E.string path )
                    ]

        FileTree.CmdUnwatchDir path ->
            Just <|
                E.object
                    [ ( "tag", E.string "unwatchDir" )
                    , ( "path", E.string path )
                    ]



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
    }


fileContentDecoder : D.Decoder FileContentPayload
fileContentDecoder =
    D.map4 FileContentPayload
        (D.field "path" D.string)
        (D.field "content" D.string)
        (D.field "revision" D.string)
        (D.field "dirty" D.bool)


fileSavedDecoder : D.Decoder ( FilePath, String )
fileSavedDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "revision" D.string)


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
        , Browser.Events.onKeyDown keyDecoder
        , Browser.Events.onResize WindowResized
        , -- Background parse/overlay steps run one per painted frame, so a
          -- large document paints its first screen before the rest fills in.
          if model.parseProgress /= Nothing || Editor.overlayPending model.editor then
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
        , if Editor.dragging model.editor then
            Browser.Events.onMouseUp (D.succeed (EditorMsg Editor.PointerUp))

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

        -- Each section is a (grid-track-size, element) pair so the
        -- template columns always match the rendered children exactly.
        -- lazy: keeps typing from rebuilding the tree/preview virtual DOM
        -- when their inputs haven't changed.
        leftSection =
            if model.leftSidebarVisible then
                [ ( pct model.sidebarFraction, Html.map FileTreeMsg (Html.Lazy.lazy FileTree.view model.fileTree) )
                , ( "2px", viewDivider DraggingSidebar )
                ]

            else
                []

        middleSection =
            [ ( pct editorTrack, Html.map EditorMsg (Editor.view { virtual = model.virtualEditor } model.editor) )
            , ( "2px", viewDivider DraggingEditor )
            , ( "1fr", Html.Lazy.lazy2 Preview.view model.frontmatter model.previewHtml )
            ]

        rightSection =
            if model.rightSidebarVisible then
                [ ( "2px", viewDivider DraggingRightSidebar )
                , ( pct model.rightSidebarFraction, viewOutline model )
                ]

            else
                []

        sections =
            leftSection ++ middleSection ++ rightSection

        gridColumns =
            String.join " " (List.map Tuple.first sections)
    in
    div []
        [ div [ class "app-shell" ]
            [ viewTitleBar model
            , div
                [ class "app-layout"
                , classList [ ( "dragging", model.drag /= Nothing ) ]
                , style "grid-template-columns" gridColumns
                ]
                (List.map Tuple.second sections)
            ]
        , case model.errorMessage of
            Just message ->
                div [ class "error-banner", attribute "data-testid" "error-banner", onClick DismissError, title "Click to dismiss" ]
                    [ text message ]

            Nothing ->
                text ""
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
            [ button [ class "settings-btn", attribute "data-testid" "settings-button", onClick ToggleSettings ] [ Icon.settings 16 ]
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
    in
    div []
        [ div [ class "settings-backdrop", onClick CloseSettings ] []
        , div
            [ class "settings-dropdown"
            , attribute "data-testid" "settings-dropdown"
            , attribute "role" "listbox"
            , attribute "aria-label" "Settings"
            ]
            [ div [ class "settings-dropdown-label" ] [ text "Theme" ]
            , div [] (List.indexedMap (\i item -> viewSettingsItem model SetTheme model.theme (themeOffset + i) item) themes)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font" ]
            , div [] (List.indexedMap (\i item -> viewSettingsItem model SetFont model.font (fontOffset + i) item) fonts)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font Size" ]
            , viewStepper "Editor" model.editorFontSize SetEditorFontSize
            , viewStepper "Preview" model.previewFontSize SetPreviewFontSize
            , viewStepper "UI" model.uiFontSize SetUIFontSize
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Outline" ]
            , viewOutlineLevelStepper model.outlineMaxLevel
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Shortcuts" ]
            , viewRebindRow "Toggle left sidebar" model.leftToggleKey RebindLeft model.rebinding
            , viewRebindRow "Toggle right sidebar" model.rightToggleKey RebindRight model.rebinding
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Experimental" ]
            , div [ class "settings-dropdown-row" ]
                [ span [ class "settings-dropdown-row-label" ] [ text "Virtual editor (read-only)" ]
                , button
                    [ class "rebind-btn"
                    , classList [ ( "capturing", model.virtualEditor ) ]
                    , attribute "data-testid" "toggle-virtual-editor"
                    , onClick ToggleVirtualEditor
                    ]
                    [ text
                        (if model.virtualEditor then
                            "On"

                         else
                            "Off"
                        )
                    ]
                ]
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


{-| One selectable row in the settings listbox. Used for both the theme and
font lists; only the active value and the click message differ.
-}
viewSettingsItem : Model -> (String -> Msg) -> String -> Int -> ( String, String ) -> Html Msg
viewSettingsItem model toMsg activeValue idx ( itemValue, displayName ) =
    let
        isActive =
            activeValue == itemValue

        isFocused =
            model.settingsFocus == idx
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
