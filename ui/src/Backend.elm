module Backend exposing (Game, Genre, Theme, getGames, getGenres, getThemes)

import Http
import Json.Decode as Decode exposing (Decoder, andThen, int, list, nullable, string)
import Json.Decode.Pipeline exposing (required)
import Set exposing (Set)
import Url exposing (Url)
import Url.Builder exposing (Root)



-- HTTP API --


getGames : (Result Http.Error (List Game) -> msg) -> Root -> Cmd msg
getGames msg root =
    Http.get
        { url = Url.Builder.custom root [ "games" ] [] Nothing
        , expect = Http.expectJson msg (list decodeGame)
        }


getThemes : (Result Http.Error (List Theme) -> msg) -> Root -> Cmd msg
getThemes msg root =
    Http.get
        { url = Url.Builder.custom root [ "themes" ] [] Nothing
        , expect = Http.expectJson msg (list decodeTheme)
        }


getGenres : (Result Http.Error (List Genre) -> msg) -> Root -> Cmd msg
getGenres msg root =
    Http.get
        { url = Url.Builder.custom root [ "genres" ] [] Nothing
        , expect = Http.expectJson msg (list decodeGenre)
        }



-- MODELS --


type alias Game =
    { name : String
    , slug : String
    , searchNames : List String
    , cover : Maybe Url
    , genres : Set Int
    , themes : Set Int
    , gameModes : List Int
    , players : Int
    , path : String
    , sizeBytes : Int
    , version : Maybe String
    }


decodeGame : Decoder Game
decodeGame =
    Decode.succeed Game
        |> required "name" string
        |> required "slug" string
        |> required "search_names" (list string)
        |> required "cover" (nullable decodeUrl)
        |> required "genres" (decodeSet int)
        |> required "themes" (decodeSet int)
        |> required "game_modes" (list int)
        |> required "max_players_offline" int
        |> required "path" string
        |> required "size_bytes" int
        |> required "version" (nullable string)


type alias Theme =
    { id : Int
    , name : String
    , slug : String
    }


decodeTheme : Decoder Theme
decodeTheme =
    Decode.succeed Theme
        |> required "id" int
        |> required "name" string
        |> required "slug" string


type alias Genre =
    { id : Int
    , name : String
    , slug : String
    }


decodeGenre : Decoder Genre
decodeGenre =
    Decode.succeed Genre
        |> required "id" int
        |> required "name" string
        |> required "slug" string



-- UTILITIES --


decodeUrl : Decoder Url
decodeUrl =
    let
        urlFromString =
            Url.fromString
                >> Maybe.map Decode.succeed
                >> Maybe.withDefault (Decode.fail "failed to parse url")
    in
    string |> andThen urlFromString


decodeSet : Decoder comparable -> Decoder (Set comparable)
decodeSet decoder =
    Decode.map Set.fromList (list decoder)
