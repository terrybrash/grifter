module Shared exposing
    ( KeyboardEvent
    , black
    , blueDark
    , blueLight
    , fredoka
    , greenDark
    , greenLight
    , gridTemplateColumns
    , inter
    , magentaDark
    , magentaLight
    , onKeyDown
    , pageWidth
    , spacing
    , userSelectNone
    , white
    , yellow100
    , yellow200
    , rgbaFromColor
    )

import Browser.Events
import Css exposing (Color, Style, hex, property, rgb)
import Json.Decode
import Json.Decode.Pipeline as D
import Url.Builder exposing (Root(..))



-- SPACING


spacing : Float
spacing =
    14


pageWidth : Float
pageWidth =
    1300



-- UTILS


userSelectNone : Style
userSelectNone =
    property "user-select" "none"


gridTemplateColumns : Style
gridTemplateColumns =
    property "grid-template-columns" "repeat(12, 1fr)"


rgbaFromColor : Color -> String
rgbaFromColor color =
    "rgba(" ++ String.fromInt color.red ++ ", " ++ String.fromInt color.green ++ ", " ++ String.fromInt color.blue ++ ", " ++ String.fromFloat color.alpha ++ ")"



-- FONTS


fredoka : List String
fredoka =
    [ "Fredoka One", "sans-serif" ]


inter : List String
inter =
    [ "Inter", "sans-serif" ]



-- PALETTE


black : Color
black =
    rgb 0 0 0


white : Color
white =
    rgb 255 255 255


yellow100 : Color
yellow100 =
    hex "fcfbf9"


yellow200 : Color
yellow200 =
    hex "ececeb"


blueLight : Color
blueLight =
    hex "0062de"


blueDark : Color
blueDark =
    hex "#002475"


magentaLight : Color
magentaLight =
    hex "d40074"


magentaDark : Color
magentaDark =
    hex "#541730"


greenLight : Color
greenLight =
    hex "007d38"


greenDark : Color
greenDark =
    hex "#0d3712"



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
