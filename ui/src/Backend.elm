module Backend exposing (Catalog, Game, Genre, Theme, getCatalog)

import Http
import Json.Decode as Decode exposing (Decoder, andThen, int, list, nullable, string)
import Json.Decode.Pipeline exposing (required)
import Set exposing (Set)
import Url exposing (Url)
import Url.Builder exposing (Root)



-- HTTP API --


getCatalog : (Result Http.Error Catalog -> msg) -> Root -> Cmd msg
getCatalog msg root =
    Http.get
        { url = Url.Builder.custom root [ "catalog" ] [] Nothing
        , expect = Http.expectJson msg decodeCatalog
        }



-- MODELS --


type alias Catalog =
    { games : List Game
    , genres : List Genre
    , themes : List Theme
    }


decodeCatalog : Decoder Catalog
decodeCatalog =
    Decode.succeed Catalog
        |> required "games" (list decodeGame)
        |> required "genres" (list decodeGenre)
        |> required "themes" (list decodeTheme)


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
