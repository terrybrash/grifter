module Shared exposing (Model)

import Backend exposing (Game, Genre)


type alias Model =
    { games : List Game
    , genres : List Genre
    }
