port module Ports exposing (editorMetrics, fromElectron, toElectron)

import Json.Decode as D
import Json.Encode as E


port toElectron : E.Value -> Cmd msg


port fromElectron : (D.Value -> msg) -> Sub msg


{-| Editor font metrics measured in the renderer (js/editor-metrics.js). Not
IPC: it is a separate port so `fromElectron` stays exactly what the main
process sent.
-}
port editorMetrics : (D.Value -> msg) -> Sub msg
