module Main exposing (main)

import AllGames exposing (Msg(..))
import Backend exposing (Catalog, Game, getCatalog)
import Browser exposing (UrlRequest)
import Browser.Navigation
import Css.Reset as Reset
import Html.Styled exposing (Html, node, toUnstyled)
import Html.Styled.Attributes exposing (href, rel)
import Http
import Shared
import SingleGame exposing (Msg(..))
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
        , onUrlChange = ChangedUrl
        , onUrlRequest = ClickedLink
        }


type Msg
    = GotCatalog (Result Http.Error Catalog)
    | ClickedLink UrlRequest
    | ChangedUrl Url
    | KeyDown Shared.KeyboardEvent
    | MsgAllGames AllGames.Msg
    | MsgSingleGame SingleGame.Msg


type Page
    = AllGames
    | SingleGame Game


type Model
    = Loading { key : Browser.Navigation.Key, route : Route }
    | LoadingFailed Http.Error
    | NotFound
    | Loaded
        { key : Browser.Navigation.Key
        , route : Route
        , page : Page
        , catalog : Catalog
        , allGames : AllGames.Model
        }


init : flags -> Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            routeFromUrl url
    in
    case route of
        Unknown ->
            ( NotFound, Cmd.none )

        Index ->
            ( Loading { key = key, route = route }
            , Cmd.batch
                [ getCatalog GotCatalog
                , Browser.Navigation.replaceUrl key "games"
                ]
            )

        _ ->
            ( Loading { key = key, route = route }, getCatalog GotCatalog )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model ) of
        ( GotCatalog (Ok catalog), Loading loading ) ->
            case loading.route of
                Games ->
                    ( Loaded
                        { key = loading.key
                        , route = loading.route
                        , page = AllGames
                        , allGames = AllGames.init catalog
                        , catalog = catalog
                        }
                    , Cmd.none
                    )

                Game slug ->
                    case find (\g -> g.slug == slug) catalog.games of
                        Just game ->
                            ( Loaded
                                { key = loading.key
                                , route = loading.route
                                , page = SingleGame game
                                , allGames = AllGames.init catalog
                                , catalog = catalog
                                }
                            , Cmd.none
                            )

                        Nothing ->
                            ( NotFound, Cmd.none )

                Index ->
                    update msg (Loading { loading | route = Games })

                Unknown ->
                    ( NotFound, Cmd.none )

        ( GotCatalog (Err err), Loading _ ) ->
            ( LoadingFailed err, Cmd.none )

        ( MsgAllGames msg_, Loaded loaded ) ->
            let
                ( newModel, cmd ) =
                    AllGames.update loaded.catalog msg_ loaded.allGames
            in
            ( Loaded { loaded | allGames = newModel }, Cmd.map MsgAllGames cmd )

        ( MsgSingleGame GoBack, Loaded loaded ) ->
            ( model, Browser.Navigation.back loaded.key 1 )

        ( ClickedLink (Browser.Internal url), Loaded loaded ) ->
            ( model, Browser.Navigation.pushUrl loaded.key (Url.toString url) )

        ( ChangedUrl url, Loaded loaded ) ->
            case routeFromUrl url of
                Game slug ->
                    case find (\g -> g.slug == slug) loaded.catalog.games of
                        Just game ->
                            ( Loaded { loaded | page = SingleGame game }, Cmd.none )

                        Nothing ->
                            ( NotFound, Cmd.none )

                Games ->
                    ( Loaded { loaded | page = AllGames }, Cmd.none )

                Index ->
                    ( Loaded { loaded | page = AllGames }, Browser.Navigation.replaceUrl loaded.key "games" )

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



-- VIEW


view : Model -> Document Msg
view model =
    case model of
        Loading _ ->
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
                    , body =
                        [ Reset.meyerV2
                        , AllGames.view loaded.catalog loaded.allGames |> Html.Styled.map MsgAllGames
                        ]
                    }

                SingleGame game ->
                    { title = game.name ++ " - " ++ "Grifter"
                    , body =
                        [ Reset.meyerV2
                        , SingleGame.view loaded.catalog game |> Html.Styled.map MsgSingleGame
                        ]
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



-- ROUTING


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
