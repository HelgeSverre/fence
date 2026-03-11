port module Ports exposing (fromElectron, toElectron)

import Json.Decode as D
import Json.Encode as E


port toElectron : E.Value -> Cmd msg


port fromElectron : (D.Value -> msg) -> Sub msg
