module Main exposing (..)

import Backend exposing (Game, Genre, getGames, getGenres)
import Browser
import Browser.Dom
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (checked, css, href, placeholder, rel, src, type_)
import Html.Styled.Events exposing (onCheck, onClick, onInput)
import Html.Styled.Keyed as Keyed
import Http
import Set exposing (Set)
import Task
import Url
import Url.Builder exposing (Root(..))


main : Program () Model Msg
main =
    Browser.element
        { view = view >> toUnstyled
        , update = update
        , init = init
        , subscriptions = \_ -> Sub.none
        }


type alias Model =
    { allGames : List Game
    , games : List Game
    , genres : List Genre
    , page : Int
    , pageCount : Int
    , gamesPerPage : Int
    , search : String
    , filteredGenres : Set Int
    , filterPlayers : List String
    }


type Msg
    = NoOp
    | GotGames (Result Http.Error (List Game))
    | GotGenres (Result Http.Error (List Genre))
    | NextPage
    | PrevPage
    | Search String
    | FilterGenre ( Int, Bool )


root =
    CrossOrigin "http://192.168.1.197:8000"


init : flags -> ( Model, Cmd Msg )
init _ =
    ( { allGames = []
      , games = []
      , genres = []
      , page = 0
      , pageCount = 0
      , gamesPerPage = 30
      , search = ""
      , filteredGenres = Set.empty
      , filterPlayers = []
      }
    , Cmd.batch
        [ getGames GotGames root
        , getGenres GotGenres root
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        pageCount games =
            ceiling (toFloat (List.length games) / toFloat model.gamesPerPage)
    in
    case msg of
        GotGames (Ok games) ->
            ( { model
                | allGames = games
                , games = games
                , pageCount = pageCount games
                , page = 0
                , search = ""
              }
            , Cmd.none
            )

        GotGenres (Ok genres) ->
            ( { model | genres = genres }, Cmd.none )

        GotGenres (Err _) ->
            ( model, Cmd.none )

        GotGames (Err _) ->
            ( model, Cmd.none )

        NextPage ->
            ( { model | page = model.page + 1 }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        PrevPage ->
            ( { model | page = model.page - 1 }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        Search rawSearch ->
            let
                search =
                    normalizeSearch rawSearch

                games =
                    filterGames search model.filteredGenres model.allGames
            in
            ( { model | games = games, pageCount = pageCount games, page = 0, search = search }, Cmd.none )

        FilterGenre ( id, isFiltered ) ->
            let
                filteredGenres =
                    if isFiltered then
                        Set.insert id model.filteredGenres

                    else
                        Set.remove id model.filteredGenres

                games =
                    filterGames model.search filteredGenres model.allGames
            in
            ( { model | games = games, pageCount = pageCount games, page = 0, filteredGenres = filteredGenres }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


normalizeSearch : String -> String
normalizeSearch =
    let
        isSearchable char =
            Char.isAlphaNum char || char == ' '

        removeConsecutiveSpaces : Char -> String -> String
        removeConsecutiveSpaces char str =
            if char == ' ' && String.endsWith " " str then
                str

            else
                str ++ String.fromChar char
    in
    String.toLower
        >> String.filter isSearchable
        >> String.trim
        >> String.foldl removeConsecutiveSpaces ""


filterGames : String -> Set Int -> List Game -> List Game
filterGames search genres games =
    let
        containsSearch game =
            List.any (String.contains search) game.searchNames

        containsGenres game =
            Set.size (Set.intersect game.genres genres) == Set.size genres
    in
    games
        |> List.filter containsGenres
        |> List.filter containsSearch



-- VIEW --


view : Model -> Html Msg
view model =
    div
        [ css
            [ displayFlex
            , minHeight (vh 100)
            , backgroundColor (hex "#212033")
            , color (rgb 255 255 255)
            , fontFamilies [ "Manrope", "sans-serif" ]
            ]
        ]
        [ linkStylesheet "https://fonts.googleapis.com/css2?family=Manrope&display=swap"
        , viewSidebar model.genres model.filteredGenres
        , div [ css [ flexGrow (int 1) ] ]
            [ viewGames model.page model.gamesPerPage model.games
            , viewPagination model.page model.pageCount
            ]
        ]


viewPagination : Int -> Int -> Html Msg
viewPagination page pageCount =
    let
        styleButton =
            [ backgroundColor (rgba 0 0 0 0)
            , color (rgb 255 255 255)
            , border3 (px 1.5) solid (rgb 255 255 255)
            , borderRadius (px 2)
            , width (px 32)
            , height (px 32)
            , margin (px 10)
            , cursor pointer
            , userSelectNone
            , Css.disabled [ opacity (num 0.15), cursor unset ]
            ]
    in
    div [ css [ textAlign center ] ]
        [ button [ onClick PrevPage, css styleButton, Attr.disabled (page <= 0) ] [ text "❮" ]
        , span [] [ text ("Page " ++ String.fromInt (page + 1) ++ "/" ++ String.fromInt pageCount) ]
        , button [ onClick NextPage, css styleButton, Attr.disabled (page + 1 >= pageCount) ] [ text "❯" ]
        ]



-- SIDEBAR --


viewSidebar : List Genre -> Set Int -> Html Msg
viewSidebar genres filteredGenres =
    let
        viewGenreFilter genre =
            let
                isGenreFiltered =
                    Set.member genre.id filteredGenres
            in
            viewFilter (\f -> FilterGenre ( genre.id, f )) genre.name isGenreFiltered
    in
    div [ css [ backgroundColor (rgba 0 0 0 0.25), padding (px spacing) ] ]
        [ viewTitle
        , viewSearch

        -- , viewFilterGroup "Players" [ "Single Player", "2–4 Players Online", "2–4 Players Local", "5–16 Players Online", "5–16 Players Local" ]
        -- , viewFilterGroup "Input" [ "Mouse & Keyboard", "Gamepad" ]
        , viewFilterGroup "Genres" (List.map viewGenreFilter genres)
        ]


viewTitle : Html msg
viewTitle =
    h1 [] [ text "Grifter" ]


viewSearch : Html Msg
viewSearch =
    input
        [ type_ "search"
        , placeholder "Search..."
        , onInput Search
        , css
            [ padding (px 11)
            , border unset
            , backgroundColor white
            , borderRadius (px 2)
            , color black
            , fontSize inherit
            ]
        ]
        []


viewFilter : (Bool -> Msg) -> String -> Bool -> Html Msg
viewFilter msg option isEnabled =
    let
        styleLabel =
            [ display block
            , cursor pointer
            , hover [ backgroundColor accent ]
            , lineHeight (num 1.5)

            -- Stretch the label across the entire sidebar.
            , marginLeft (px -spacing)
            , marginRight (px -spacing)
            , paddingLeft (px spacing)
            , paddingRight (px spacing)
            ]
    in
    label [ css styleLabel ]
        [ checkbox [ Attr.checked isEnabled, onCheck msg ]
        , text option
        ]


checkbox : List (Attribute msg) -> Html msg
checkbox attributes =
    input
        ([ type_ "checkbox"
         , css [ verticalAlign middle ]
         ]
            ++ attributes
        )
        []


viewFilterGroup : String -> List (Html msg) -> Html msg
viewFilterGroup title options =
    div [ css [ marginTop (px spacing), marginBottom (px spacing) ] ] (text title :: options)



-- GAMES --


paginate : Int -> Int -> List item -> List item
paginate page itemsPerPage =
    List.drop (itemsPerPage * page) >> List.take itemsPerPage


viewGames : Int -> Int -> List Game -> Html Msg
viewGames page gamesPerPage games =
    Keyed.node "div"
        [ css
            [ displayFlex
            , flexWrap wrap
            , property "align-content" "flex-start"
            ]
        ]
        (games |> paginate page gamesPerPage |> List.map viewKeyedGame)


viewKeyedGame : Game -> ( String, Html Msg )
viewKeyedGame game =
    ( game.name, viewGame game )


viewGame : Game -> Html Msg
viewGame game =
    let
        styleTitle =
            [ position absolute
            , bottom (px 0)
            , width (pct 100)
            , padding4 (px 10) (px 7) (px 5) (px 7)
            , boxSizing borderBox
            ]

        styleShadow =
            [ position absolute
            , width (pct 100)
            , height (pct 100)
            , boxSizing borderBox
            , border3 (px 1) solid (rgb 0 0 0)
            , borderTop unset
            , borderLeft unset
            , opacity (num 0.3)
            , property "mix-blend-mode" "darken"
            , borderRadius (px 2)
            ]

        styleHighlight =
            [ position absolute
            , width (pct 100)
            , height (pct 100)
            , border3 (px 1) solid (rgb 255 255 255)
            , borderBottom unset
            , borderRight unset
            , boxSizing borderBox
            , opacity (num 0.14)
            , property "mix-blend-mode" "luminosity"
            , borderRadius (px 2)
            ]
    in
    a
        [ href (Url.Builder.custom root [ game.path ] [] Nothing)
        , css
            [ width (px 150)
            , height (px 200)
            , position relative
            , marginTop (px spacing)
            , marginLeft (px spacing)
            , cursor pointer
            , borderRadius (px 2)
            , overflow hidden
            , backgroundColor (hex "#4c3b71")
            ]
        ]
        [ div [ css styleHighlight ] []
        , div [ css styleShadow ] []
        , case game.cover of
            Just cover ->
                img
                    [ src (Url.toString cover)
                    , css
                        [ width (pct 100)
                        , height (pct 100)
                        , property "object-fit" "cover"
                        ]
                    ]
                    []

            Nothing ->
                span [ css styleTitle ] [ text game.name ]
        ]



-- GLOBALS --


spacing : Float
spacing =
    14


accent : Color
accent =
    hex "#522ace"


accent2 : Color
accent2 =
    hex "#9744E9"


white : Color
white =
    rgb 255 255 255


black : Color
black =
    rgb 0 0 0


userSelectNone : Style
userSelectNone =
    property "user-select" "none"


linkStylesheet : String -> Html msg
linkStylesheet src =
    node "link" [ rel "stylesheet", href src ] []
