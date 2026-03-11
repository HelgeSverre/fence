module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Editor
import FileTree
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icon
import Json.Decode as D
import Json.Encode as E
import Markdown
import Ports
import Preview
import Yaml
import Process
import Task
import Types exposing (..)


type DragTarget
    = DraggingSidebar
    | DraggingEditor


type alias DragState =
    { target : DragTarget
    , startX : Float
    , startFraction : Float
    }


type alias Model =
    { fileTree : FileTree.Model
    , editor : Editor.Model
    , previewHtml : List (Html Msg)
    , frontmatter : Maybe Yaml.Value
    , debounceGeneration : Int
    , theme : String
    , font : String
    , editorFontSize : Float
    , uiFontSize : Float
    , settingsOpen : Bool
    , sidebarFraction : Float
    , editorFraction : Float
    , drag : Maybe DragState
    , windowWidth : Float
    }


type Msg
    = FileTreeMsg FileTree.Msg
    | EditorMsg Editor.Msg
    | FromElectron D.Value
    | KeyDown String Bool Bool
    | DebouncedParse Int
    | ToggleSettings
    | SetTheme String
    | SetFont String
    | SetEditorFontSize Float
    | SetUIFontSize Float
    | CloseSettings
    | DividerMouseDown DragTarget Float
    | DividerMouseMove Float
    | DividerMouseUp
    | DividerDoubleClick DragTarget
    | WindowResized Int Int
    | NoOp


defaultSidebarFraction : Float
defaultSidebarFraction =
    0.17


defaultEditorFraction : Float
defaultEditorFraction =
    0.5


defaultEditorFontSize : Float
defaultEditorFontSize =
    14


defaultUIFontSize : Float
defaultUIFontSize =
    13


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        windowWidth =
            D.decodeValue (D.field "windowWidth" D.float) flagsValue
                |> Result.withDefault 1400

        sidebarFraction =
            D.decodeValue (D.field "sidebarFraction" D.float) flagsValue
                |> Result.withDefault defaultSidebarFraction

        editorFraction =
            D.decodeValue (D.field "editorFraction" D.float) flagsValue
                |> Result.withDefault defaultEditorFraction

        font =
            D.decodeValue (D.field "font" D.string) flagsValue
                |> Result.withDefault ""

        editorFontSize =
            D.decodeValue (D.field "editorFontSize" D.float) flagsValue
                |> Result.withDefault defaultEditorFontSize

        uiFontSize =
            D.decodeValue (D.field "uiFontSize" D.float) flagsValue
                |> Result.withDefault defaultUIFontSize
    in
    ( { fileTree = FileTree.init
      , editor = Editor.init
      , previewHtml = []
      , frontmatter = Nothing
      , debounceGeneration = 0
      , theme = "github-dark"
      , font = font
      , editorFontSize = editorFontSize
      , uiFontSize = uiFontSize
      , settingsOpen = False
      , sidebarFraction = sidebarFraction
      , editorFraction = editorFraction
      , drag = Nothing
      , windowWidth = windowWidth
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        ToggleSettings ->
            ( { model | settingsOpen = not model.settingsOpen }, Cmd.none )

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
                    clamp 8 32 size
            in
            ( { model | editorFontSize = clamped }
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "setFontSize" )
                    , ( "editorFontSize", E.float clamped )
                    ]
                )
            )

        SetUIFontSize size ->
            let
                clamped =
                    clamp 8 24 size
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

        DividerMouseDown target clientX ->
            let
                startFraction =
                    case target of
                        DraggingSidebar ->
                            model.sidebarFraction

                        DraggingEditor ->
                            model.editorFraction
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
            in
            ( newModel, saveSplitsCmd newModel )

        WindowResized w _ ->
            ( { model | windowWidth = toFloat w }, Cmd.none )

        FileTreeMsg subMsg ->
            let
                ( newTree, outCmds ) =
                    FileTree.update subMsg model.fileTree

                focusCmd =
                    case newTree.focused of
                        Just path ->
                            if newTree.focused /= model.fileTree.focused then
                                Browser.Dom.focus (treeItemId path)
                                    |> Task.attempt (\_ -> NoOp)
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
            in
            case subMsg of
                Editor.ContentChanged _ ->
                    let
                        gen =
                            model.debounceGeneration + 1
                    in
                    ( { model
                        | editor = newEditor
                        , debounceGeneration = gen
                      }
                    , Cmd.batch
                        [ Task.perform (\_ -> DebouncedParse gen) (Process.sleep 150)
                        , setTitleCmd newEditor
                        , setDirtyCmd True
                        ]
                    )

                _ ->
                    ( { model | editor = newEditor }, Cmd.none )

        DebouncedParse gen ->
            if gen == model.debounceGeneration then
                let
                    { frontmatter, html } =
                        Markdown.parse model.editor.content
                in
                ( { model | previewHtml = html, frontmatter = frontmatter }
                , Cmd.none
                )

            else
                ( model, Cmd.none )

        KeyDown key metaKey ctrlKey ->
            if key == "s" && (metaKey || ctrlKey) then
                saveFile model
            else if key == "Escape" && model.settingsOpen then
                ( { model | settingsOpen = False }, Cmd.none )
            else
                ( model, Cmd.none )

        FromElectron value ->
            case D.decodeValue (D.field "tag" D.string) value of
                Ok tag ->
                    handlePortMessage tag value model

                Err _ ->
                    ( model, Cmd.none )


saveFile : Model -> ( Model, Cmd Msg )
saveFile model =
    case model.editor.filePath of
        Just path ->
            ( model
            , Ports.toElectron
                (E.object
                    [ ( "tag", E.string "writeFile" )
                    , ( "path", E.string path )
                    , ( "content", E.string model.editor.content )
                    ]
                )
            )

        Nothing ->
            ( model, Cmd.none )


handlePortMessage : String -> D.Value -> Model -> ( Model, Cmd Msg )
handlePortMessage tag value model =
    case tag of
        "folderOpened" ->
            case D.decodeValue dirEntriesDecoder value of
                Ok ( path, entries ) ->
                    ( { model | fileTree = FileTree.handleDirContents path entries model.fileTree }
                    , Cmd.none
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
                Ok ( path, content ) ->
                    let
                        newEditor =
                            Editor.setContent path content model.editor

                        { frontmatter, html } =
                            Markdown.parse content
                    in
                    ( { model
                        | editor = newEditor
                        , previewHtml = html
                        , frontmatter = frontmatter
                      }
                    , Cmd.batch
                        [ setTitleCmd newEditor
                        , setDirtyCmd False
                        ]
                    )

                Err _ ->
                    ( model, Cmd.none )

        "fileSaved" ->
            let
                newEditor =
                    Editor.markClean model.editor
            in
            ( { model | editor = newEditor }
            , Cmd.batch
                [ setTitleCmd newEditor
                , setDirtyCmd False
                ]
            )

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
            let
                ( newModel, saveCmd ) =
                    saveFile model
            in
            ( newModel
            , Cmd.batch
                [ saveCmd
                , -- Close after a small delay to let save complete
                  Task.perform
                    (\_ -> FromElectron (E.object [ ( "tag", E.string "doClose" ) ]))
                    (Process.sleep 200)
                ]
            )

        "doClose" ->
            ( model
            , Ports.toElectron (E.object [ ( "tag", E.string "closeWindow" ) ])
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
                remainingWidth =
                    model.windowWidth * (1 - model.sidebarFraction)

                deltaFraction =
                    if remainingWidth > 0 then
                        (clientX - d.startX) / remainingWidth

                    else
                        0

                newFraction =
                    clamp 0.15 0.85 (d.startFraction + deltaFraction)
            in
            { model | editorFraction = newFraction }


saveSplitsCmd : Model -> Cmd Msg
saveSplitsCmd model =
    Ports.toElectron
        (E.object
            [ ( "tag", E.string "saveSplits" )
            , ( "sidebarFraction", E.float model.sidebarFraction )
            , ( "editorFraction", E.float model.editorFraction )
            ]
        )



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


fileContentDecoder : D.Decoder ( FilePath, String )
fileContentDecoder =
    D.map2 Tuple.pair
        (D.field "path" D.string)
        (D.field "content" D.string)


fsEventDecoder : D.Decoder ( String, FilePath )
fsEventDecoder =
    D.map2 Tuple.pair
        (D.field "event" D.string)
        (D.field "path" D.string)


keyDecoder : D.Decoder Msg
keyDecoder =
    D.map3 KeyDown
        (D.field "key" D.string)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)


treeItemId : String -> String
treeItemId path =
    "tree-item-" ++ String.replace "/" "-" path


baseName : String -> String
baseName path =
    path
        |> String.split "/"
        |> List.filter (not << String.isEmpty)
        |> List.reverse
        |> List.head
        |> Maybe.withDefault path



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.fromElectron FromElectron
        , Browser.Events.onKeyDown keyDecoder
        , Browser.Events.onResize WindowResized
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
        ]



-- VIEW


pct : Float -> String
pct f =
    String.fromFloat (f * 100) ++ "%"


viewDivider : DragTarget -> Html Msg
viewDivider target =
    div
        [ class "divider"
        , on "mousedown" (D.map (DividerMouseDown target) (D.field "clientX" D.float))
        , onDoubleClick (DividerDoubleClick target)
        ]
        []


view : Model -> Html Msg
view model =
    let
        gridColumns =
            pct model.sidebarFraction
                ++ " 2px "
                ++ pct (model.editorFraction * (1 - model.sidebarFraction))
                ++ " 2px 1fr"
    in
    div []
        [ div [ class "app-shell" ]
            [ viewTitleBar model
            , div
                [ class "app-layout"
                , classList [ ( "dragging", model.drag /= Nothing ) ]
                , style "grid-template-columns" gridColumns
                ]
                [ Html.map FileTreeMsg (FileTree.view model.fileTree)
                , viewDivider DraggingSidebar
                , Html.map EditorMsg (Editor.view model.editor)
                , viewDivider DraggingEditor
                , Preview.view model.frontmatter model.previewHtml
                ]
            ]
        ]


viewTitleBar : Model -> Html Msg
viewTitleBar model =
    div [ class "titlebar" ]
        [ div [ class "titlebar-traffic-pad" ] []
        , div [ class "titlebar-title" ]
            [ span [ class "titlebar-app-name" ] [ text "Fence" ]
            , case model.editor.filePath of
                Just path ->
                    span []
                        [ span [ class "titlebar-separator" ] [ text " — " ]
                        , span [ class "titlebar-filename" ]
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
            [ button [ class "settings-btn", onClick ToggleSettings ] [ Icon.settings 16 ]
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
    , ( "resharper-dark", "ReSharper Dark" )
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


viewSettingsDropdown : Model -> Html Msg
viewSettingsDropdown model =
    div []
        [ div [ class "settings-backdrop", onClick CloseSettings ] []
        , div [ class "settings-dropdown" ]
            [ div [ class "settings-dropdown-label" ] [ text "Theme" ]
            , div [] (List.map (viewThemeItem model.theme) themes)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Font" ]
            , div [] (List.map (viewFontItem model.font) fonts)
            , div [ class "settings-dropdown-divider" ] []
            , div [ class "settings-dropdown-label" ] [ text "Size" ]
            , viewStepper "Editor" model.editorFontSize SetEditorFontSize
            , viewStepper "UI" model.uiFontSize SetUIFontSize
            ]
        ]


viewThemeItem : String -> ( String, String ) -> Html Msg
viewThemeItem currentTheme ( themeValue, displayName ) =
    let
        isActive =
            currentTheme == themeValue
    in
    button
        [ class "settings-dropdown-item"
        , classList [ ( "active", isActive ) ]
        , onClick (SetTheme themeValue)
        ]
        [ span [ class "settings-dropdown-item-label" ] [ text displayName ]
        , span [ class "settings-dropdown-check" ]
            [ if isActive then
                Icon.checkmark 14
              else
                text ""
            ]
        ]


viewFontItem : String -> ( String, String ) -> Html Msg
viewFontItem currentFont ( fontValue, displayName ) =
    let
        isActive =
            currentFont == fontValue
    in
    button
        [ class "settings-dropdown-item"
        , classList [ ( "active", isActive ) ]
        , onClick (SetFont fontValue)
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
