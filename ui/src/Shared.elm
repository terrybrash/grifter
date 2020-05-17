module Shared exposing (KeyboardEvent, accent, accent2, background, black, onKeyDown, spacing, userSelectNone, white)

import Browser.Events
import Css exposing (Color, Style, hex, property, rgb)
import Json.Decode
import Json.Decode.Pipeline as D
import Url.Builder exposing (Root(..))



-- CONSTANTS


spacing : Float
spacing =
    14


accent : Color
accent =
    hex "#522ace"


accent2 : Color
accent2 =
    hex "#9744E9"


background : Color
background =
    hex "#212033"


white : Color
white =
    rgb 255 255 255


black : Color
black =
    rgb 0 0 0


userSelectNone : Style
userSelectNone =
    property "user-select" "none"



-- EVENTS


type alias KeyboardEvent =
    { key : String
    , shift : Bool
    , ctrl : Bool
    }


decodeKeyboardEvent : Json.Decode.Decoder KeyboardEvent
decodeKeyboardEvent =
    Json.Decode.succeed KeyboardEvent
        |> D.required "key" Json.Decode.string
        |> D.required "shiftKey" Json.Decode.bool
        |> D.required "ctrlKey" Json.Decode.bool


onKeyDown : (KeyboardEvent -> msg) -> Sub msg
onKeyDown event =
    Browser.Events.onKeyDown (Json.Decode.map event decodeKeyboardEvent)
