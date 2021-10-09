module Main exposing (main)

import AllGames exposing (Msg(..))
import Backend exposing (Catalog, Game, getCatalog)
import Browser exposing (UrlRequest)
import Browser.Dom exposing (Viewport)
import Browser.Navigation
import Dict exposing (Dict)
import Html.Styled exposing (Html, toUnstyled)
import Http
import Shared
import SingleGame exposing (Msg(..))
import Task
import Url exposing (Url)
import Url.Builder exposing (Root(..))
import Url.Parser exposing ((</>))


main : Program () Model Msg
main =
    Browser.application
        { view = view >> toUnstyledDocument
        , update = update
        , init = init
        , subscriptions = \_ -> Shared.onKeyDown KeyDown
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }



--- INIT ---


type Model
    = LoadingCatalog { key : Browser.Navigation.Key, url : Url }
    | LoadingFailed Http.Error
    | NotFound
    | Loaded
        { key : Browser.Navigation.Key
        , url : Url
        , page : Page
        , catalog : Catalog
        , allGames : AllGames.Model
        , viewportByUrl : Dict String Viewport
        }


type Page
    = AllGames
    | SingleGame Game


init : flags -> Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    ( LoadingCatalog { key = key, url = url }, getCatalog GotCatalog )



--- UPDATE ---


type Msg
    = GotCatalog (Result Http.Error Catalog)
    | UrlRequested UrlRequest
    | UrlChanged Url
    | KeyDown Shared.KeyboardEvent
    | MsgAllGames AllGames.Msg
    | MsgSingleGame SingleGame.Msg
    | MovedViewport Float Float
    | CachedViewport UrlRequest Viewport


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model ) of
        ( GotCatalog (Ok catalog), LoadingCatalog loading ) ->
            case routeFromUrl loading.url of
                Index ->
                    ( model, Browser.Navigation.replaceUrl loading.key "/games" )

                Games ->
                    ( Loaded
                        { key = loading.key
                        , url = loading.url
                        , page = AllGames
                        , allGames = AllGames.init catalog
                        , catalog = catalog
                        , viewportByUrl = Dict.empty
                        }
                    , Cmd.none
                    )

                Game slug ->
                    case find (\g -> g.slug == slug) catalog.games of
                        Just game ->
                            ( Loaded
                                { key = loading.key
                                , url = loading.url
                                , page = SingleGame game
                                , allGames = AllGames.init catalog
                                , catalog = catalog
                                , viewportByUrl = Dict.empty
                                }
                            , Cmd.none
                            )

                        Nothing ->
                            ( NotFound, Cmd.none )

                Unknown ->
                    ( NotFound, Cmd.none )

        ( GotCatalog (Err err), LoadingCatalog _ ) ->
            ( LoadingFailed err, Cmd.none )

        ( MsgAllGames msg_, Loaded loaded ) ->
            let
                ( newModel, cmd ) =
                    AllGames.update loaded.catalog msg_ loaded.allGames
            in
            ( Loaded { loaded | allGames = newModel }, Cmd.map MsgAllGames cmd )

        ( MsgSingleGame GoBack, Loaded loaded ) ->
            ( model, Browser.Navigation.replaceUrl loaded.key "/games" )

        ( UrlRequested (Browser.Internal url), Loaded _ ) ->
            ( model
            , Task.perform (CachedViewport (Browser.Internal url)) Browser.Dom.getViewport
            )

        ( CachedViewport (Browser.Internal url) viewport, Loaded loaded ) ->
            ( Loaded { loaded | viewportByUrl = Dict.insert (Url.toString loaded.url) viewport loaded.viewportByUrl }
            , Browser.Navigation.pushUrl loaded.key (Url.toString url)
            )

        ( UrlChanged url, Loaded loaded ) ->
            let
                ( x, y ) =
                    loaded.viewportByUrl
                        |> Dict.get (Url.toString url)
                        |> Maybe.map (\viewport -> ( viewport.viewport.x, viewport.viewport.y ))
                        |> Maybe.withDefault ( 0, 0 )
            in
            case routeFromUrl url of
                Game slug ->
                    case find (\g -> g.slug == slug) loaded.catalog.games of
                        Just game ->
                            ( Loaded { loaded | page = SingleGame game }
                            , Task.perform (\_ -> MovedViewport x y) (Browser.Dom.setViewport x y)
                            )

                        Nothing ->
                            ( NotFound, Cmd.none )

                Games ->
                    ( Loaded { loaded | page = AllGames }
                    , Task.perform (\_ -> MovedViewport x y) (Browser.Dom.setViewport x y)
                    )

                Index ->
                    ( Loaded { loaded | page = AllGames }
                    , Browser.Navigation.replaceUrl loaded.key "/games"
                    )

                Unknown ->
                    ( NotFound, Cmd.none )

        ( KeyDown event, Loaded loaded ) ->
            case loaded.page of
                AllGames ->
                    update (MsgAllGames (AllGames.KeyDown event)) model

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


find : (a -> Bool) -> List a -> Maybe a
find isGood list =
    List.filter isGood list |> List.head



--- VIEW ---


view : Model -> Document Msg
view model =
    case model of
        LoadingCatalog _ ->
            { title = "Grifter"
            , body = []
            }

        NotFound ->
            { title = "Grifter - 404"
            , body = [ Html.Styled.text "Not found" ]
            }

        LoadingFailed _ ->
            { title = "Grifter - 500"
            , body = [ Html.Styled.text "Failed to load data from the server. Try refreshing the page or contacting an admin." ]
            }

        Loaded loaded ->
            case loaded.page of
                AllGames ->
                    { title = "Grifter"
                    , body = [ AllGames.view loaded.catalog loaded.allGames |> Html.Styled.map MsgAllGames ]
                    }

                SingleGame game ->
                    { title = game.name ++ " - " ++ "Grifter"
                    , body = [ SingleGame.view loaded.catalog game |> Html.Styled.map MsgSingleGame ]
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



--- ROUTING ---


type Route
    = Index
    | Games
    | Game String
    | Unknown


routeFromUrl : Url -> Route
routeFromUrl url =
    let
        route : Url.Parser.Parser (Route -> a) a
        route =
            Url.Parser.oneOf
                [ Url.Parser.map Index Url.Parser.top
                , Url.Parser.map Games (Url.Parser.s "games")
                , Url.Parser.map Game (Url.Parser.s "games" </> Url.Parser.string)
                ]
    in
    Maybe.withDefault Unknown (Url.Parser.parse route url)
