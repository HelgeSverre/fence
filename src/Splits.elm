module Splits exposing
    ( DragState
    , DragTarget(..)
    , Layout
    , defaultEditorFraction
    , defaultRightSidebarFraction
    , defaultSidebarFraction
    , drag
    , encode
    , endDrag
    , resetFraction
    , startDrag
    , viewDivider
    )

{-| The resizable pane splits: dragging a divider, and the persisted layout
record (`saveSplits` in Electron's state.json). The fractions live on Main's
model; `Layout` names the fields these functions touch.
-}

import Html exposing (Html, div)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (on, onDoubleClick)
import Json.Decode as D
import Json.Encode as E
import Types exposing (KeyBinding, encodeKeyBinding)


type DragTarget
    = DraggingSidebar
    | DraggingEditor
    | DraggingRightSidebar


type alias DragState =
    { target : DragTarget
    , startX : Float
    , startFraction : Float
    }


type alias Layout a =
    { a
        | sidebarFraction : Float
        , editorFraction : Float
        , rightSidebarFraction : Float
        , rightSidebarVisible : Bool
        , windowWidth : Float
        , drag : Maybe DragState
    }


defaultSidebarFraction : Float
defaultSidebarFraction =
    0.17


defaultEditorFraction : Float
defaultEditorFraction =
    0.5


defaultRightSidebarFraction : Float
defaultRightSidebarFraction =
    0.18


startDrag : DragTarget -> Float -> Layout a -> Layout a
startDrag target clientX model =
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
    { model
        | drag =
            Just
                { target = target
                , startX = clientX
                , startFraction = startFraction
                }
    }


{-| The pointer moved to `clientX`; a no-op unless a drag is under way. -}
drag : Float -> Layout a -> Layout a
drag clientX model =
    case model.drag of
        Just d ->
            computeDrag d clientX model

        Nothing ->
            model


endDrag : Layout a -> Layout a
endDrag model =
    { model | drag = Nothing }


{-| Double-clicking a divider puts its split back to the default. -}
resetFraction : DragTarget -> Layout a -> Layout a
resetFraction target model =
    case target of
        DraggingSidebar ->
            { model | sidebarFraction = defaultSidebarFraction }

        DraggingEditor ->
            { model | editorFraction = defaultEditorFraction }

        DraggingRightSidebar ->
            { model | rightSidebarFraction = defaultRightSidebarFraction }


computeDrag : DragState -> Float -> Layout a -> Layout a
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


{-| The fields of the `saveSplits` command; `layoutMode` is the layout's name. -}
encode :
    String
    ->
        { a
            | sidebarFraction : Float
            , editorFraction : Float
            , rightSidebarFraction : Float
            , leftSidebarVisible : Bool
            , rightSidebarVisible : Bool
            , outlineMaxLevel : Int
            , leftToggleKey : KeyBinding
            , rightToggleKey : KeyBinding
            , layoutCycleKey : KeyBinding
        }
    -> List ( String, E.Value )
encode layoutMode model =
    [ ( "sidebarFraction", E.float model.sidebarFraction )
    , ( "editorFraction", E.float model.editorFraction )
    , ( "rightSidebarFraction", E.float model.rightSidebarFraction )
    , ( "leftSidebarVisible", E.bool model.leftSidebarVisible )
    , ( "rightSidebarVisible", E.bool model.rightSidebarVisible )
    , ( "outlineMaxLevel", E.int model.outlineMaxLevel )
    , ( "leftToggleKey", encodeKeyBinding model.leftToggleKey )
    , ( "rightToggleKey", encodeKeyBinding model.rightToggleKey )
    , ( "layoutMode", E.string layoutMode )
    , ( "layoutCycleKey", encodeKeyBinding model.layoutCycleKey )
    ]


viewDivider : (DragTarget -> Float -> msg) -> (DragTarget -> msg) -> DragTarget -> Html msg
viewDivider mouseDown doubleClick target =
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
        , on "mousedown" (D.map (mouseDown target) (D.field "clientX" D.float))
        , onDoubleClick (doubleClick target)
        ]
        []
