module PreferencesTest exposing (suite)

import Expect
import Json.Encode as E
import Preferences exposing (Picker(..), Preferences, PreviewWidth(..))
import Test exposing (Test, describe, test)


custom : Preferences
custom =
    { theme = "nord"
    , editorFont = "Iosevka"
    , uiFont = "Inter"
    , editorFontSize = 16
    , previewFontSize = 18
    , uiFontSize = 12
    , previewWidth = Custom
    , previewMaxWidth = 900
    , showPaneHeaders = False
    , previewUsesEditorFont = True
    , softWrap = False
    , revealInSidebar = False
    }


suite : Test
suite =
    describe "Preferences"
        [ describe "decode"
            [ test "an empty object decodes to the defaults" <|
                \_ ->
                    Preferences.decode (E.object [])
                        |> Expect.equal Preferences.default
            , test "the legacy \"font\" key becomes editorFont" <|
                \_ ->
                    Preferences.decode (E.object [ ( "font", E.string "Hack" ) ])
                        |> .editorFont
                        |> Expect.equal "Hack"
            , test "editorFont wins over the legacy key" <|
                \_ ->
                    Preferences.decode
                        (E.object
                            [ ( "font", E.string "Hack" )
                            , ( "editorFont", E.string "Iosevka" )
                            ]
                        )
                        |> .editorFont
                        |> Expect.equal "Iosevka"
            , test "a mistyped field falls back on its own" <|
                \_ ->
                    Preferences.decode
                        (E.object
                            [ ( "theme", E.int 5 )
                            , ( "uiFont", E.string "Lato" )
                            ]
                        )
                        |> Expect.equal
                            { default | uiFont = "Lato" }
            , test "an empty theme is a real value, not a missing one" <|
                \_ ->
                    Preferences.decode (E.object [ ( "theme", E.string "" ) ])
                        |> .theme
                        |> Expect.equal ""
            , test "decoding clamps out-of-range sizes" <|
                \_ ->
                    Preferences.decode
                        (E.object
                            [ ( "editorFontSize", E.float 100 )
                            , ( "uiFontSize", E.float 30 )
                            , ( "previewMaxWidth", E.int 10 )
                            ]
                        )
                        |> Expect.equal
                            { default
                                | editorFontSize = 32
                                , uiFontSize = 24
                                , previewMaxWidth = 320
                            }
            , test "round-trips through encode" <|
                \_ ->
                    Preferences.decode (E.object (Preferences.encode custom))
                        |> Expect.equal custom
            , test "an unknown previewWidth falls back to full width" <|
                \_ ->
                    Preferences.decode (E.object [ ( "previewWidth", E.string "huge" ) ])
                        |> .previewWidth
                        |> Expect.equal FullWidth
            , test "encode does not emit the legacy \"font\" key" <|
                \_ ->
                    Preferences.encode custom
                        |> List.map Tuple.first
                        |> List.member "font"
                        |> Expect.equal False
            ]
        , describe "clamp"
            [ test "keeps in-range values untouched" <|
                \_ -> Preferences.clamp custom |> Expect.equal custom
            , test "raises a too-small preview width" <|
                \_ ->
                    Preferences.clamp { custom | previewMaxWidth = 10 }
                        |> .previewMaxWidth
                        |> Expect.equal 320
            , test "lowers a too-large preview width" <|
                \_ ->
                    Preferences.clamp { custom | previewMaxWidth = 9999 }
                        |> .previewMaxWidth
                        |> Expect.equal 2000
            , test "lowers a too-large editor font size" <|
                \_ ->
                    Preferences.clamp { custom | editorFontSize = 100 }
                        |> .editorFontSize
                        |> Expect.within (Expect.Absolute 0.001) 32
            , test "lowers a too-large UI font size" <|
                \_ ->
                    Preferences.clamp { custom | uiFontSize = 30 }
                        |> .uiFontSize
                        |> Expect.within (Expect.Absolute 0.001) 24
            ]
        , describe "preview width"
            [ test "each preset maps to its pixel width" <|
                \_ ->
                    [ FullWidth, Narrow, Normal, Wide, Custom ]
                        |> List.map (\w -> Preferences.previewWidthPx { custom | previewWidth = w })
                        |> Expect.equal [ Nothing, Just 560, Just 680, Just 900, Just 900 ]
            , test "every option name round-trips" <|
                \_ ->
                    Preferences.previewWidthOptions
                        |> List.map Tuple.first
                        |> List.map (Preferences.previewWidthName >> Preferences.previewWidthFromName)
                        |> Expect.equal (List.map Tuple.first Preferences.previewWidthOptions)
            ]
        , describe "pickers" <|
            List.map pickerTests [ ThemePicker, EditorFontPicker, UIFontPicker ]
        ]


pickerTests : Picker -> Test
pickerTests picker =
    describe (pickerName picker)
        [ test "select sets the value selected reads back" <|
            \_ ->
                Preferences.default
                    |> Preferences.select picker "x"
                    |> Preferences.selected picker
                    |> Expect.equal "x"
        , test "select leaves the other pickers alone" <|
            \_ ->
                Preferences.select picker "x" custom
                    |> Expect.equal
                        (case picker of
                            ThemePicker ->
                                { custom | theme = "x" }

                            EditorFontPicker ->
                                { custom | editorFont = "x" }

                            UIFontPicker ->
                                { custom | uiFont = "x" }
                        )
        , test "option values are unique" <|
            \_ ->
                let
                    values =
                        List.map Tuple.first (Preferences.options picker)
                in
                List.length values
                    |> Expect.equal (List.length (dedupe values))
        , test "the default value is one of the options" <|
            \_ ->
                Preferences.options picker
                    |> List.map Tuple.first
                    |> List.member (Preferences.selected picker Preferences.default)
                    |> Expect.equal True
        ]


pickerName : Picker -> String
pickerName picker =
    case picker of
        ThemePicker ->
            "ThemePicker"

        EditorFontPicker ->
            "EditorFontPicker"

        UIFontPicker ->
            "UIFontPicker"


dedupe : List String -> List String
dedupe =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []


default : Preferences
default =
    Preferences.default
