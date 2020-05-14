module Main exposing (main)

import Backend exposing (Game, Genre, getGames, getGenres)
import Browser exposing (UrlRequest)
import Html.Styled.Attributes exposing (rel, href)
import Html.Styled exposing (Html, toUnstyled, node)
import Http
import Page.Explore exposing (Msg(..))
import Shared
import Url exposing (Url)
import Url.Builder exposing (Root(..))


main : Program () Model Msg
main =
    Browser.application
        { view = view >> toUnstyledDocument
        , update = update
        , init = init
        , subscriptions = \_ -> Sub.none
        , onUrlChange = ChangedUrl
        , onUrlRequest = ClickedLink
        }


type Msg
    = GotGames (Result Http.Error (List Game))
    | GotGenres (Result Http.Error (List Genre))
    | ClickedLink UrlRequest
    | ChangedUrl Url
    | ExploreMsg Page.Explore.Msg


type alias Model =
    { shared : Shared.Model
    , page : Page
    }


type Page
    = Explore Page.Explore.Model
    | Focus Game


root : Root
root =
    CrossOrigin "http://192.168.1.197:9090"


init : flags -> url -> key -> ( Model, Cmd Msg )
init _ _ _ =
    ( { shared = { games = [], genres = [] }
      , page = Explore Page.Explore.init
      }
    , Cmd.batch
        [ getGames GotGames root
        , getGenres GotGenres root
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( GotGames (Ok games), Explore exploreModel ) ->
            let
                ( newModel, cmd ) =
                    Page.Explore.update (Page.Explore.GotGames games) exploreModel
            in
            ( { model | page = Explore newModel }, Cmd.map ExploreMsg cmd )

        ( GotGames (Err _), _ ) ->
            ( model, Cmd.none )

        ( GotGenres (Ok genres), Explore exploreModel ) ->
            let
                ( newModel, cmd ) =
                    Page.Explore.update (Page.Explore.GotGenres genres) exploreModel
            in
            ( { model | page = Explore newModel }, Cmd.map ExploreMsg cmd )

        ( GotGenres (Err _), _ ) ->
            ( model, Cmd.none )

        ( ExploreMsg exploreMsg, Explore exploreModel ) ->
            let
                ( newModel, newCmd ) =
                    Page.Explore.update exploreMsg exploreModel
            in
            ( { model | page = Explore newModel }, Cmd.map ExploreMsg newCmd )

        _ ->
            ( model, Cmd.none )


view : Model -> Document Msg
view model =
    case model.page of
        Explore exploreModel ->
            { title = "Grifter"
            , body =
                [ linkStylesheet "https://fonts.googleapis.com/css2?family=Manrope&display=swap"
                , Page.Explore.view exploreModel |> Html.Styled.map ExploreMsg
                ]
            }

        Focus game ->
            { title = "Grifter - " ++ game.name
            , body =
                [ linkStylesheet "https://fonts.googleapis.com/css2?family=Manrope&display=swap"
                , Html.Styled.text game.name
                ]
            }



-- VIEW --


type alias Document msg =
    { title : String
    , body : List (Html msg)
    }


toUnstyledDocument : Document msg -> Browser.Document msg
toUnstyledDocument document =
    { title = document.title
    , body = List.map toUnstyled document.body
    }


linkStylesheet : String -> Html msg
linkStylesheet src =
    node "link" [ rel "stylesheet", href src ] []
