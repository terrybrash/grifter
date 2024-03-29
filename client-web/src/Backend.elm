module Backend exposing
    ( Catalog
    , Game
    , Genre
    , Graphics(..)
    , Image
    , Multiplayer(..)
    , Theme
    , getCatalog
    )

import Http
import Json.Decode as Decode exposing (Decoder, andThen, int, list, nullable, string)
import Json.Decode.Pipeline exposing (required)
import Set exposing (Set)
import Url exposing (Url)



-- HTTP API


getCatalog : (Result Http.Error Catalog -> msg) -> Cmd msg
getCatalog msg =
    Http.get
        { url = "/api/catalog"
        , expect = Http.expectJson msg decodeCatalog
        }



-- MODELS


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
    , summary : Maybe String
    , genres : Set Int
    , themes : Set Int

    -- Multiplayer
    , hasSinglePlayer : Bool
    , hasCoopCampaign : Bool
    , offlineCoop : Multiplayer
    , offlinePvp : Multiplayer
    , onlineCoop : Multiplayer
    , onlinePvp : Multiplayer

    -- Media
    , cover : Maybe Image
    , screenshots : List Image
    , videos : List String
    , graphics : Graphics

    -- Stores
    , steam : Maybe Url
    , gog : Maybe Url
    , itch : Maybe Url
    , epic : Maybe Url
    , googlePlay : Maybe Url
    , applePhone : Maybe Url
    , applePad : Maybe Url

    -- File info
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
        |> required "summary" (nullable string)
        |> required "genres" (decodeSet int)
        |> required "themes" (decodeSet int)
        -- Multiplayer
        |> required "has_single_player" Decode.bool
        |> required "has_coop_campaign" Decode.bool
        |> required "offline_coop" decodeMultiplayer
        |> required "offline_pvp" decodeMultiplayer
        |> required "online_coop" decodeMultiplayer
        |> required "online_pvp" decodeMultiplayer
        -- Media
        |> required "cover" (nullable decodeImage)
        |> required "screenshots" (list decodeImage)
        |> required "videos" (list string)
        |> required "graphics" decodeGraphics
        -- Stores
        |> required "steam" (nullable decodeUrl)
        |> required "gog" (nullable decodeUrl)
        |> required "itch" (nullable decodeUrl)
        |> required "epic" (nullable decodeUrl)
        |> required "google_play" (nullable decodeUrl)
        |> required "apple_phone" (nullable decodeUrl)
        |> required "apple_pad" (nullable decodeUrl)
        -- File
        |> required "path" string
        |> required "size_bytes" int
        |> required "version" (nullable string)


type alias Image =
    { id : String
    , width : Int
    , height : Int
    }


decodeImage : Decoder Image
decodeImage =
    Decode.succeed Image
        |> required "id" string
        |> required "width" int
        |> required "height" int


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


type Multiplayer
    = None
    | Some
    | Limit Int


decodeMultiplayer : Decoder Multiplayer
decodeMultiplayer =
    Decode.oneOf
        [ Decode.andThen
            (\s ->
                case s of
                    "None" ->
                        Decode.succeed None

                    "Some" ->
                        Decode.succeed Some

                    _ ->
                        Decode.fail "Expected \"None\" or \"Some\""
            )
            string
        , Decode.map Limit (Decode.field "Limited" int)
        ]


type Graphics
    = Pixelated
    | Smooth


decodeGraphics : Decoder Graphics
decodeGraphics =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "Pixelated" ->
                        Decode.succeed Pixelated

                    "Smooth" ->
                        Decode.succeed Smooth

                    other ->
                        Decode.fail ("Invalid value " ++ other ++ " for Graphics")
            )



-- UTILITIES


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
