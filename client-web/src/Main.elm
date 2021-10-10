module Main exposing (main)

import AllGames exposing (Msg(..))
import Backend exposing (Catalog, Game, getCatalog)
import Browser exposing (UrlRequest)
import Browser.Dom exposing (Viewport)
import Browser.Navigation as Nav
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
    = LoadingCatalog { key : Nav.Key, url : Url }
    | LoadingFailed Http.Error
    | NotFound
    | Loaded App


type alias App =
    { key : Nav.Key
    , url : Url
    , page : Page
    , catalog : Catalog
    , allGames : AllGames.Model
    , viewportByUrl : Dict String Viewport
    }


type Page
    = AllGames
    | SingleGame Game


init : flags -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( LoadingCatalog { key = key, url = url }
    , getCatalog GotCatalog
    )



--- UPDATE ---


type Msg
    = GotCatalog (Result Http.Error Catalog)
    | UrlRequested UrlRequest
    | UrlChanged Url
    | KeyDown Shared.KeyboardEvent
    | MsgAllGames AllGames.Msg
    | MsgSingleGame SingleGame.Msg
    | CachedViewport Url Viewport
    | RevivedViewport Float Float
    | ResetViewport


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model of
        Loaded app ->
            updateApp msg app

        LoadingCatalog loading ->
            updateLoading msg loading

        LoadingFailed _ ->
            ( model, Cmd.none )

        NotFound ->
            ( model, Cmd.none )


updateApp : Msg -> App -> ( Model, Cmd Msg )
updateApp msg app =
    case msg of
        UrlRequested (Browser.External _) ->
            ( Loaded app, Cmd.none )

        UrlRequested (Browser.Internal url) ->
            ( Loaded app
            , Task.perform (CachedViewport url) Browser.Dom.getViewport
            )

        CachedViewport url viewport ->
            ( Loaded (cacheViewport app viewport), Nav.pushUrl app.key (Url.toString url) )

        UrlChanged url ->
            case routeFromUrl url of
                Game slug ->
                    case find (\g -> g.slug == slug) app.catalog.games of
                        Just game ->
                            ( Loaded { app | url = url, page = SingleGame game }, reviveViewport app url )

                        Nothing ->
                            ( NotFound, Cmd.none )

                Games ->
                    ( Loaded { app | url = url, page = AllGames }, reviveViewport app url )

                Index ->
                    ( NotFound, Cmd.none )

                Unknown ->
                    ( NotFound, Cmd.none )

        KeyDown event ->
            case app.page of
                AllGames ->
                    update (MsgAllGames (AllGames.KeyDown event)) (Loaded app)

                _ ->
                    ( Loaded app, Cmd.none )

        -- PAGES
        MsgAllGames msg_ ->
            let
                ( newModel, cmd ) =
                    AllGames.update app.catalog msg_ app.allGames
            in
            ( Loaded { app | allGames = newModel }, Cmd.map MsgAllGames cmd )

        MsgSingleGame GoBack ->
            ( Loaded app, Nav.replaceUrl app.key "/games" )

        -- IGNORE
        RevivedViewport _ _ ->
            ( Loaded app, Cmd.none )

        ResetViewport ->
            ( Loaded app, Cmd.none )

        -- IMPOSSIBLE
        GotCatalog _ ->
            ( Loaded app, Cmd.none )


updateLoading : Msg -> { key : Nav.Key, url : Url } -> ( Model, Cmd Msg )
updateLoading msg { key, url } =
    case msg of
        GotCatalog (Ok catalog) ->
            case routeFromUrl url of
                Index ->
                    ( Loaded
                        { key = key
                        , url = url
                        , page = AllGames
                        , allGames = AllGames.init catalog
                        , catalog = catalog
                        , viewportByUrl = Dict.empty
                        }
                    , Nav.replaceUrl key "/games"
                    )

                Games ->
                    ( Loaded
                        { key = key
                        , url = url
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
                                { key = key
                                , url = url
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

        GotCatalog (Err err) ->
            ( LoadingFailed err, Cmd.none )

        _ ->
            ( LoadingCatalog { key = key, url = url }, Cmd.none )



-- VIEWPORT CACHING: Viewports are cached per-url. On URL _request_, we cache
-- the current viewport for later. Subsequently, on URL _change_, we revive the
-- viewport of the newly changed URL.


cacheViewport : App -> Viewport -> App
cacheViewport app viewport =
    { app | viewportByUrl = Dict.insert (Url.toString app.url) viewport app.viewportByUrl }


reviveViewport : App -> Url -> Cmd Msg
reviveViewport app url =
    let
        cachedViewport : Maybe { x : Float, y : Float }
        cachedViewport =
            app.viewportByUrl
                |> Dict.get (Url.toString url)
                |> Maybe.map (\{ viewport } -> { x = viewport.x, y = viewport.y })
    in
    case cachedViewport of
        Just viewport ->
            Task.perform (\_ -> RevivedViewport viewport.x viewport.y) (Browser.Dom.setViewport viewport.x viewport.y)

        Nothing ->
            Task.perform (\_ -> ResetViewport) (Browser.Dom.setViewport 0 0)


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
