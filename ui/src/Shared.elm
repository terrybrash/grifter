module Shared exposing
    ( KeyboardEvent
    , background
    , backgroundOffset
    , foreground
    , foregroundOffset
    , gridTemplateColumns
    , onKeyDown
    , spacing
    , userSelectNone
    )

import Browser.Events
import Css exposing (Color, Style, hex, property, rgb)
import Json.Decode
import Json.Decode.Pipeline as D
import Url.Builder exposing (Root(..))


spacing : Float
spacing =
    14


userSelectNone : Style
userSelectNone =
    property "user-select" "none"


gridTemplateColumns : Style
gridTemplateColumns =
    property "grid-template-columns" "250px 1000px"



-- THEME


type Theme
    = Light
    | Dark


theme =
    Light


background : Color
background =
    case theme of
        Light ->
            rgb 221 221 221

        Dark ->
            hex "#212033"


backgroundOffset : Color
backgroundOffset =
    case theme of
        Light ->
            rgb 255 255 255

        Dark ->
            rgb 20 13 35


foreground : Color
foreground =
    case theme of
        Light ->
            rgb 0 0 0

        Dark ->
            rgb 255 255 255


foregroundOffset : Color
foregroundOffset =
    case theme of
        Dark ->
            hex "#8483A1"

        Light ->
            hex "#666666"



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
