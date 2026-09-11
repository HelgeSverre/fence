module Preferences exposing
    ( Preferences, Picker(..), PreviewWidth(..), default, decode, encode, clamp, select, selected, options
    , fontSizeMin, fontSizeMax, uiFontSizeMax, previewWidthMin, previewWidthMax
    , previewWidthPx, previewWidthOptions, previewWidthName, previewWidthFromName
    )

{-| Appearance settings: one record, persisted flat in state.json.
-}

import Json.Decode as D
import Json.Encode as E


type alias Preferences =
    { theme : String
    , editorFont : String
    , uiFont : String
    , editorFontSize : Float
    , previewFontSize : Float
    , uiFontSize : Float
    , previewWidth : PreviewWidth
    , previewMaxWidth : Int
    , showPaneHeaders : Bool
    , previewUsesEditorFont : Bool
    , softWrap : Bool
    , revealInSidebar : Bool
    }


type Picker
    = ThemePicker
    | EditorFontPicker
    | UIFontPicker


type PreviewWidth
    = FullWidth
    | Narrow
    | Normal
    | Wide
    | Custom


default : Preferences
default =
    { theme = "github-dark"
    , editorFont = ""
    , uiFont = ""
    , editorFontSize = 14
    , previewFontSize = 14
    , uiFontSize = 13
    , previewWidth = FullWidth
    , previewMaxWidth = 680
    , showPaneHeaders = True
    , previewUsesEditorFont = False
    , softWrap = True
    , revealInSidebar = True
    }


fontSizeMin : Float
fontSizeMin =
    8


fontSizeMax : Float
fontSizeMax =
    32


uiFontSizeMax : Float
uiFontSizeMax =
    24


previewWidthMin : Int
previewWidthMin =
    320


previewWidthMax : Int
previewWidthMax =
    2000



-- PREVIEW WIDTH


{-| The max width the preview column gets, or Nothing for the full pane.
`previewMaxWidth` is only read for `Custom`.
-}
previewWidthPx : Preferences -> Maybe Int
previewWidthPx prefs =
    case prefs.previewWidth of
        FullWidth ->
            Nothing

        Narrow ->
            Just 560

        Normal ->
            Just 680

        Wide ->
            Just 900

        Custom ->
            Just prefs.previewMaxWidth


{-| Display order; the lowercased labels double as test id slugs.
-}
previewWidthOptions : List ( PreviewWidth, String )
previewWidthOptions =
    [ ( FullWidth, "Full" )
    , ( Narrow, "Narrow" )
    , ( Normal, "Normal" )
    , ( Wide, "Wide" )
    , ( Custom, "Custom" )
    ]


previewWidthName : PreviewWidth -> String
previewWidthName width =
    case width of
        FullWidth ->
            "full"

        Narrow ->
            "narrow"

        Normal ->
            "normal"

        Wide ->
            "wide"

        Custom ->
            "custom"


previewWidthFromName : String -> PreviewWidth
previewWidthFromName name =
    previewWidthOptions
        |> List.filter (\( width, _ ) -> previewWidthName width == name)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault FullWidth



-- DECODE


{-| Never fails: each field falls back to its default independently.
-}
decode : D.Value -> Preferences
decode value =
    D.decodeValue decoder value
        |> Result.withDefault default
        |> clamp


decoder : D.Decoder Preferences
decoder =
    let
        field name fieldDecoder fallback =
            D.oneOf [ D.field name fieldDecoder, D.succeed fallback ]
    in
    D.map8 Preferences
        (field "theme" D.string default.theme)
        (D.oneOf
            [ D.field "editorFont" D.string
            , D.field "font" D.string
            , D.succeed default.editorFont
            ]
        )
        (field "uiFont" D.string default.uiFont)
        (field "editorFontSize" D.float default.editorFontSize)
        (field "previewFontSize" D.float default.previewFontSize)
        (field "uiFontSize" D.float default.uiFontSize)
        (field "previewWidth" (D.map previewWidthFromName D.string) default.previewWidth)
        (field "previewMaxWidth" D.int default.previewMaxWidth)
        |> andMap (field "showPaneHeaders" D.bool default.showPaneHeaders)
        |> andMap (field "previewUsesEditorFont" D.bool default.previewUsesEditorFont)
        |> andMap (field "softWrap" D.bool default.softWrap)
        |> andMap (field "revealInSidebar" D.bool default.revealInSidebar)


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


encode : Preferences -> List ( String, E.Value )
encode prefs =
    [ ( "theme", E.string prefs.theme )
    , ( "editorFont", E.string prefs.editorFont )
    , ( "uiFont", E.string prefs.uiFont )
    , ( "editorFontSize", E.float prefs.editorFontSize )
    , ( "previewFontSize", E.float prefs.previewFontSize )
    , ( "uiFontSize", E.float prefs.uiFontSize )
    , ( "previewWidth", E.string (previewWidthName prefs.previewWidth) )
    , ( "previewMaxWidth", E.int prefs.previewMaxWidth )
    , ( "showPaneHeaders", E.bool prefs.showPaneHeaders )
    , ( "previewUsesEditorFont", E.bool prefs.previewUsesEditorFont )
    , ( "softWrap", E.bool prefs.softWrap )
    , ( "revealInSidebar", E.bool prefs.revealInSidebar )
    ]


clamp : Preferences -> Preferences
clamp prefs =
    { prefs
        | editorFontSize = Basics.clamp fontSizeMin fontSizeMax prefs.editorFontSize
        , previewFontSize = Basics.clamp fontSizeMin fontSizeMax prefs.previewFontSize
        , uiFontSize = Basics.clamp fontSizeMin uiFontSizeMax prefs.uiFontSize
        , previewMaxWidth = Basics.clamp previewWidthMin previewWidthMax prefs.previewMaxWidth
    }



-- PICKERS


select : Picker -> String -> Preferences -> Preferences
select picker value prefs =
    case picker of
        ThemePicker ->
            { prefs | theme = value }

        EditorFontPicker ->
            { prefs | editorFont = value }

        UIFontPicker ->
            { prefs | uiFont = value }


selected : Picker -> Preferences -> String
selected picker prefs =
    case picker of
        ThemePicker ->
            prefs.theme

        EditorFontPicker ->
            prefs.editorFont

        UIFontPicker ->
            prefs.uiFont


options : Picker -> List ( String, String )
options picker =
    case picker of
        ThemePicker ->
            themes

        EditorFontPicker ->
            monoFonts

        UIFontPicker ->
            uiFonts


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


monoFonts : List ( String, String )
monoFonts =
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


{-| Values match the @font-face family names bundled in static/fonts.
-}
uiFonts : List ( String, String )
uiFonts =
    [ ( "", "System UI" )
    , ( "Inter", "Inter" )
    , ( "Helvetica Neue", "Helvetica Neue" )
    , ( "Open Sans", "Open Sans" )
    , ( "Noto Sans", "Noto Sans" )
    , ( "Roboto", "Roboto" )
    , ( "Source Sans 3", "Source Sans 3" )
    , ( "IBM Plex Sans", "IBM Plex Sans" )
    , ( "Lato", "Lato" )
    , ( "Nunito Sans", "Nunito Sans" )
    , ( "Work Sans", "Work Sans" )
    , ( "Fira Sans", "Fira Sans" )
    , ( "DM Sans", "DM Sans" )
    , ( "Atkinson Hyperlegible", "Atkinson Hyperlegible" )
    ]
