module Settings exposing
    ( Msg(..)
    , RebindTarget(..)
    , State
    , pickerId
    , pickerSearchId
    , settingsItemId
    , view
    , visibleSettingsOptions
    )

{-| The settings dropdown: pickers, steppers, toggles and shortcut rebinding.
The state it reads still lives on Main's model (`State` names the fields), and
Main maps `Msg` onto its own messages; only the view and its DOM ids are here.
-}

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Icon
import Json.Decode as D
import Preferences exposing (Picker(..), Preferences, PreviewWidth(..))
import Tooltip exposing (Tooltip)
import Types exposing (KeyBinding, keyBindingLabel)


type Msg
    = SetPreference (Preferences -> Preferences)
    | SetSoftWrap Bool
    | ExpandPicker (Maybe Picker)
    | PickerFilterChanged String
    | CloseSettings
    | SettingsKeyDown String
    | SettingsFocused Int
    | SetOutlineMaxLevel Int
    | StartRebind RebindTarget
    | NoOp


{-| The fields of Main's model the dropdown reads. -}
type alias State a =
    { a
        | preferences : Preferences
        , expandedPicker : Maybe Picker
        , pickerFilter : String
        , settingsFocus : Int
        , outlineMaxLevel : Int
        , leftToggleKey : KeyBinding
        , rightToggleKey : KeyBinding
        , layoutCycleKey : KeyBinding
        , rebinding : Maybe RebindTarget
    }


{-| Which sidebar toggle is being rebound while in capture mode.
-}
type RebindTarget
    = RebindLeft
    | RebindRight
    | RebindLayout


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
visibleSettingsOptions : { a | expandedPicker : Maybe Picker, pickerFilter : String } -> List ( String, String )
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


view : Bool -> State a -> Html Msg
view softWrap model =
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
            , viewToggleRow (tip "Soft wrap" "Wrap long lines at the editor's edge instead of scrolling sideways. Default: on.") "Soft wrap" "soft-wrap-toggle" softWrap SetSoftWrap
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
viewPicker : State a -> Picker -> String -> Tooltip -> Html Msg
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


