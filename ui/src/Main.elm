module Main exposing (main)

import Backend exposing (Catalog, Game, getCatalog)
import Browser exposing (UrlRequest)
import Browser.Navigation
import Html.Styled exposing (Html, node, toUnstyled)
import Html.Styled.Attributes exposing (href, rel)
import Http
import Page.AllGames exposing (Msg(..))
import Page.SingleGame
import Url exposing (Url)
import Url.Builder exposing (Root(..))
import Url.Parser exposing ((</>))


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
    = GotCatalog (Result Http.Error Catalog)
    | ClickedLink UrlRequest
    | ChangedUrl Url
    | MsgAllGames Page.AllGames.Msg


type Page
    = AllGames Page.AllGames.Model
    | SingleGame ( Catalog, Game )
    | Loading
    | LoadingFailed Http.Error
    | NotFound


type alias Model =
    { key : Browser.Navigation.Key
    , page : Page
    , route : Route
    }


init : flags -> Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            routeFromUrl url
    in
    ( { key = key
      , route = route
      , page =
            case route of
                Unknown ->
                    NotFound

                _ ->
                    Loading
      }
    , getCatalog GotCatalog root
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( GotCatalog result, _ ) ->
            case result of
                Ok catalog ->
                    case model.route of
                        Games ->
                            ( { model | page = AllGames (Page.AllGames.init catalog) }, Cmd.none )

                        Game slug ->
                            case find (\g -> g.slug == slug) catalog.games of
                                Just game ->
                                    ( { model | page = SingleGame ( catalog, game ) }, Cmd.none )

                                Nothing ->
                                    ( { model | page = NotFound }, Cmd.none )

                        Unknown ->
                            ( model, Cmd.none )

                Err err ->
                    ( { model | page = LoadingFailed err }, Cmd.none )

        ( MsgAllGames msgAllGames, AllGames modelAllGames ) ->
            let
                ( newModel, cmd ) =
                    Page.AllGames.update msgAllGames modelAllGames
            in
            ( { model | page = AllGames newModel }, Cmd.map MsgAllGames cmd )

        _ ->
            ( model, Cmd.none )



-- case ( msg, model.page ) of
--     ( GotGames result, _ ) ->
--         ( { model | games = games, })
--     ( GotGames (Ok games), Explore exploreModel ) ->
--         let
--             ( newModel, cmd ) =
--                 Page.Explore.update (Page.Explore.GotGames games) exploreModel
--         in
--         ( { model | page = Explore newModel, shared = { games = games, genres = [] } }, Cmd.map ExploreMsg cmd )
--     ( GotGames (Err _), _ ) ->
--         ( model, Cmd.none )
--     ( GotGenres (Ok genres), Explore exploreModel ) ->
--         let
--             ( newModel, cmd ) =
--                 Page.Explore.update (Page.Explore.GotGenres genres) exploreModel
--         in
--         ( { model | page = Explore newModel }, Cmd.map ExploreMsg cmd )
--     ( GotGenres (Err _), _ ) ->
--         ( model, Cmd.none )
--     ( ExploreMsg exploreMsg, Explore exploreModel ) ->
--         let
--             ( newModel, newCmd ) =
--                 Page.Explore.update exploreMsg exploreModel
--         in
--         ( { model | page = Explore newModel }, Cmd.map ExploreMsg newCmd )
--     ( ClickedLink (Browser.Internal url), _ ) ->
--         ( model, Browser.Navigation.pushUrl model.key (Url.toString url) )
--     ( ChangedUrl url, _ ) ->
--         case Debug.log "test" (Url.Parser.parse routeParser url) of
--             Nothing ->
--                 ( model, Cmd.none )
--             Just Games ->
--                 ( { model | page = Explore Page.Explore.init }, Cmd.none )
--             Just (Game slug) ->
--                 case find (\g -> g.slug == slug) model.shared.games of
--                     Just game ->
--                         ( { model | page = Focus game }, Cmd.none )
--                     Nothing ->
--                         ( model, Cmd.none )
--     _ ->
--         ( model, Cmd.none )


find : (a -> Bool) -> List a -> Maybe a
find isGood list =
    List.filter isGood list |> List.head



-- VIEW --


view : Model -> Document Msg
view model =
    case model.page of
        -- ( Loaded catalog, Explore exploreModel ) ->
        --     { title = "Grifter"
        --     , body =
        --         [ linkStylesheet "https://fonts.googleapis.com/css2?family=Manrope&display=swap"
        --         , Page.Explore.view exploreModel |> Html.Styled.map ExploreMsg
        --         ]
        --     }
        -- ( Loaded catalog, Focus game ) ->
        --     { title = "Grifter - " ++ game.name
        --     , body =
        --         [ linkStylesheet "https://fonts.googleapis.com/css2?family=Manrope&display=swap"
        --         , Html.Styled.text game.name
        --         ]
        --     }
        AllGames modelAllGames ->
            { title = "Grifter"
            , body = [ Page.AllGames.view modelAllGames |> Html.Styled.map MsgAllGames ]
            }

        SingleGame ( catalog, game ) ->
            { title = "Grifter - " ++ game.name
            , body = [ Page.SingleGame.view game ]
            }

        LoadingFailed err ->
            { title = "Grifter"
            , body = [ Html.Styled.text "Failed to load data from the server. Try refreshing the page or contacting an admin." ]
            }

        Loading ->
            { title = "Grifter - Loading"
            , body = [ Html.Styled.text "Loading..." ]
            }

        NotFound ->
            { title = "Grifter - 404"
            , body = [ Html.Styled.text "Not found" ]
            }


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


root : Root
root =
    CrossOrigin "http://192.168.1.197:9090"



-- ROUTING


type Route
    = Games
    | Game String
    | Unknown


routeFromUrl : Url -> Route
routeFromUrl url =
    let
        route : Url.Parser.Parser (Route -> a) a
        route =
            Url.Parser.oneOf
                [ Url.Parser.map Games (Url.Parser.s "games")
                , Url.Parser.map Game (Url.Parser.s "games" </> Url.Parser.string)
                ]
    in
    Maybe.withDefault Unknown (Url.Parser.parse route url)
