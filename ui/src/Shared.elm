module Shared exposing (accent, accent2, black, root, spacing, userSelectNone, white, background)

import Css exposing (Color, Style, hex, property, rgb)
import Url.Builder exposing (Root(..))


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


root : Root
root =
    CrossOrigin "http://192.168.1.197:9090"
