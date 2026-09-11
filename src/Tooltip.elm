module Tooltip exposing (Tooltip, host, view)

{-| Hover and focus tooltips drawn by CSS (`.tip` in main.css). The popup is a
child of its host and anchored to it, so it escapes the settings dropdown's
overflow clip. `name` must be unique per host: it becomes the anchor name and
the id that `aria-describedby` points at.
-}

import Html exposing (Attribute, Html, kbd, span, strong, text)
import Html.Attributes exposing (attribute, class, id, style)


type alias Tooltip =
    { heading : String
    , body : String
    , shortcut : Maybe String
    }


host : String -> List (Attribute msg)
host name =
    [ class "tip-host"
    , style "anchor-name" (anchorName name)
    , attribute "aria-describedby" (tipId name)
    ]


view : String -> Tooltip -> Html msg
view name tip =
    span
        [ class "tip"
        , id (tipId name)
        , attribute "role" "tooltip"
        , style "position-anchor" (anchorName name)
        ]
        (strong [ class "tip-heading" ] [ text tip.heading ]
            :: span [] [ text tip.body ]
            :: (case tip.shortcut of
                    Just keys ->
                        [ kbd [] [ text keys ] ]

                    Nothing ->
                        []
               )
        )


tipId : String -> String
tipId name =
    "tip-" ++ name


anchorName : String -> String
anchorName name =
    "--tip-" ++ name
