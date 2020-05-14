module Pages.Explore exposing (Model, Msg(..), chunk, init, update, view)

import Backend exposing (Game, Genre)
import Browser.Dom
import Css exposing (..)
import Html.Styled exposing (Html, Attribute, div, h3, span, text, button, h1, input, label, img, a)
import Html.Styled.Attributes as Attr exposing (checked, css, href, placeholder, rel, src, type_)
import Html.Styled.Events exposing (onCheck, onClick, onInput)
import Html.Styled.Keyed as Keyed
import Pagination exposing (Pagination)
import Set exposing (Set)
import Task
import Url
import Url.Builder exposing (Root(..))


type alias Model =
    { allGames : List Game
    , allGenres : List Genre
    , games : Maybe (Pagination (List Game))
    , search : String
    , filteredGenres : Set Int
    , game : Maybe Game
    }


type Msg
    = NoOp
    | GotGames (List Game)
    | GotGenres (List Genre)
    | NextPage (Pagination (List Game))
    | PrevPage (Pagination (List Game))
    | Search String
    | FilterGenre ( Int, Bool )



-- INIT --


init : Model
init =
    { allGames = []
    , allGenres = []
    , games = Nothing
    , search = ""
    , filteredGenres = Set.empty
    , game = Nothing
    }



-- UPDATE --


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotGames games ->
            ( { model | allGames = games, games = Pagination.fromList (chunk gamesPerPage games), search = "" }, Cmd.none )

        GotGenres genres ->
            ( { model | allGenres = genres, filteredGenres = Set.empty }, Cmd.none )

        NextPage next ->
            ( { model | games = Just next }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        PrevPage prev ->
            ( { model | games = Just prev }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        Search rawSearch ->
            let
                search =
                    normalizeSearch rawSearch

                games =
                    filterGames search model.filteredGenres model.allGames
            in
            ( { model | games = Pagination.fromList (chunk gamesPerPage games), search = search }, Cmd.none )

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
            ( { model | games = Pagination.fromList (chunk gamesPerPage games), filteredGenres = filteredGenres }, Cmd.none )

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
        [ viewSidebar model.allGenres model.filteredGenres
        , div [ css [ flexGrow (int 1) ] ]
            (case model.games of
                Just games ->
                    [ viewGames games, viewPaginator games ]

                Nothing ->
                    [ h3 [] [ text "No games here!" ] ]
            )
        ]


viewPaginator : Pagination (List Game) -> Html Msg
viewPaginator games =
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

        attrNext =
            case Pagination.next games of
                Just next ->
                    [ css styleButton, onClick (NextPage next) ]

                Nothing ->
                    [ css styleButton, Attr.disabled True ]

        attrPrev =
            case Pagination.previous games of
                Just prev ->
                    [ css styleButton, onClick (PrevPage prev) ]

                Nothing ->
                    [ css styleButton, Attr.disabled True ]

        ( current, _ ) =
            Pagination.current games

        total =
            Pagination.count games
    in
    div [ css [ textAlign center ] ]
        [ button attrPrev [ text "❮" ]
        , span [] [ text ("Page " ++ String.fromInt (current + 1) ++ "/" ++ String.fromInt total) ]
        , button attrNext [ text "❯" ]
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
            [ displayFlex
            , alignItems center
            , cursor pointer
            , whiteSpace noWrap
            , userSelectNone
            , lineHeight (num 1.7)

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
         , css
            [ verticalAlign middle
            , property "-webkit-appearance" "none"
            , backgroundColor black
            , width (px 12)
            , height (px 12)
            , border3 (px 1) solid white
            , borderRadius (px 2)
            , cursor inherit
            , margin4 (px 0) (px 7) (px 0) (px 0)
            , Css.checked
                [ backgroundColor white
                , border unset
                , marginLeft (px 10)
                ]
            ]
         ]
            ++ attributes
        )
        []


viewFilterGroup : String -> List (Html msg) -> Html msg
viewFilterGroup title options =
    div [ css [ marginTop (px spacing), marginBottom (px spacing) ] ] (text title :: options)



-- GAMES --


viewGames : Pagination (List Game) -> Html Msg
viewGames games =
    Keyed.node "div"
        [ css
            [ displayFlex
            , flexWrap wrap
            , property "align-content" "flex-start"
            ]
        ]
        (games |> Pagination.current |> Tuple.second |> List.map viewKeyedGame)


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
            , boxShadow5 (px 0) (px 2) (px 1) (px 0) (rgba 0 0 0 0.3)
            ]
        ]
        [ div [ css styleHighlight ] []
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



-- LIST --


chunk : Int -> List a -> List (List a)
chunk size items =
    if List.isEmpty items || size == 0 then
        []

    else if List.length items <= size then
        [ List.take size items ]

    else
        List.take size items :: chunk size (List.drop size items)



-- GLOBALS --


gamesPerPage : Int
gamesPerPage =
    30


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


root : Root
root =
    CrossOrigin "http://192.168.1.197:9090"
