module Preview exposing (view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Yaml


view : Maybe Yaml.Value -> List (Html msg) -> Html msg
view frontmatter renderedHtml =
    div [ class "preview-pane" ]
        [ div [ class "pane-header" ]
            [ span [] [ text "Preview" ] ]
        , div [ id "preview-container", class "preview-container" ]
            [ div [ class "preview-content" ]
                (if List.isEmpty renderedHtml then
                    [ welcomeView ]

                 else
                    viewFrontmatter frontmatter ++ renderedHtml
                )
            ]
        ]


viewFrontmatter : Maybe Yaml.Value -> List (Html msg)
viewFrontmatter maybeFm =
    case maybeFm of
        Just (Yaml.Object_ fields) ->
            [ details [ class "frontmatter" ]
                [ summary []
                    [ text ("Metadata (" ++ String.fromInt (List.length fields) ++ " fields)") ]
                , dl [ class "frontmatter-grid" ]
                    (List.concatMap viewField fields)
                ]
            ]

        _ ->
            []


viewField : ( String, Yaml.Value ) -> List (Html msg)
viewField ( key, value ) =
    [ dt [] [ text key ]
    , dd [] [ viewValue value ]
    ]


viewValue : Yaml.Value -> Html msg
viewValue value =
    case value of
        Yaml.String_ s ->
            text s

        Yaml.Int_ i ->
            text (String.fromInt i)

        Yaml.Float_ f ->
            text (String.fromFloat f)

        Yaml.Bool_ b ->
            text
                (if b then
                    "true"

                 else
                    "false"
                )

        Yaml.Null_ ->
            span [ class "fm-null" ] [ text "null" ]

        Yaml.List_ items ->
            span []
                (items
                    |> List.map
                        (\item ->
                            case item of
                                Yaml.String_ s ->
                                    span [ class "fm-tag" ] [ text s ]

                                _ ->
                                    span [ class "fm-tag" ] [ viewValue item ]
                        )
                )

        Yaml.Object_ fields ->
            dl [ class "frontmatter-grid" ]
                (List.concatMap viewField fields)


welcomeView : Html msg
welcomeView =
    div [ class "welcome" ]
        [ h1 [ class "welcome-title" ] [ text "Fence" ]
        , p [ class "welcome-subtitle" ] [ text "A split-view markdown editor" ]
        , div [ class "welcome-hints" ]
            [ p [] [ text "Open a folder to browse your markdown files" ]
            , p [] [ text "Click a .md file in the sidebar to start editing" ]
            , ul []
                [ li [] [ kbd [] [ text "Cmd+S" ], text " Save" ]
                ]
            ]
        ]
