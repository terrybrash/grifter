module Page.AllGames exposing (Model, Msg(..), chunk, init, update, view)

import Backend exposing (Game)
import Browser.Dom
import Css exposing (..)
import Html.Styled exposing (Attribute, Html, a, button, div, h1, h3, img, input, label, span, text)
import Html.Styled.Attributes as Attr exposing (checked, css, href, placeholder, rel, src, type_)
import Html.Styled.Events as Event
import Html.Styled.Keyed as Keyed
import Pagination exposing (Pagination)
import Set exposing (Set)
import Shared exposing (userSelectNone)
import Task
import Url
import Url.Builder exposing (Root(..))


type Msg
    = NoOp
    | NextPage (Pagination (List Game))
    | PrevPage (Pagination (List Game))
    | Search String
    | FilterGenre ( Int, Bool )
    | FilterSinglePlayer Bool
    | FilterCoopCampaign Bool
    | FilterOfflineCoop Bool
    | FilterOfflinePvp Bool
    | FilterOnlineCoop Bool
    | FilterOnlinePvp Bool
    | KeyDown Shared.KeyboardEvent
    | SearchFocused Bool


type alias Model =
    { games : Maybe (Pagination (List Game))
    , search : String
    , normalizedSearch : NormalizedSearch
    , isSearchFocused : Bool
    , mustHaveGenres : Set Int
    , mustHaveSinglePlayer : Bool
    , mustHaveCoopCampaign : Bool
    , mustHaveOfflineCoop : Bool
    , mustHaveOfflinePvp : Bool
    , mustHaveOnlineCoop : Bool
    , mustHaveOnlinePvp : Bool
    }


type NormalizedSearch
    = NormalizedSearch String



-- INIT


init : Backend.Catalog -> Model
init catalog =
    filterGames catalog
        { games = Nothing
        , search = ""
        , normalizedSearch = NormalizedSearch ""
        , isSearchFocused = False
        , mustHaveGenres = Set.empty
        , mustHaveSinglePlayer = False
        , mustHaveCoopCampaign = False
        , mustHaveOfflinePvp = False
        , mustHaveOfflineCoop = False
        , mustHaveOnlinePvp = False
        , mustHaveOnlineCoop = False
        }



-- UPDATE


update : Backend.Catalog -> Msg -> Model -> ( Model, Cmd Msg )
update catalog msg model =
    case msg of
        NextPage next ->
            ( { model | games = Just next }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        PrevPage prev ->
            ( { model | games = Just prev }, Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0) )

        Search search ->
            ( filterGames catalog { model | search = search, normalizedSearch = normalizeSearch search }
            , Cmd.none
            )

        FilterGenre ( id, isFiltered ) ->
            let
                mustHaveGenres =
                    if isFiltered then
                        Set.insert id model.mustHaveGenres

                    else
                        Set.remove id model.mustHaveGenres
            in
            ( filterGames catalog { model | mustHaveGenres = mustHaveGenres }, Cmd.none )

        FilterSinglePlayer mustHave ->
            ( filterGames catalog { model | mustHaveSinglePlayer = mustHave }, Cmd.none )

        FilterCoopCampaign mustHave ->
            ( filterGames catalog { model | mustHaveCoopCampaign = mustHave }, Cmd.none )

        FilterOfflineCoop mustHave ->
            ( filterGames catalog { model | mustHaveOfflineCoop = mustHave }, Cmd.none )

        FilterOfflinePvp mustHave ->
            ( filterGames catalog { model | mustHaveOfflinePvp = mustHave }, Cmd.none )

        FilterOnlineCoop mustHave ->
            ( filterGames catalog { model | mustHaveOnlineCoop = mustHave }, Cmd.none )

        FilterOnlinePvp mustHave ->
            ( filterGames catalog { model | mustHaveOnlinePvp = mustHave }, Cmd.none )

        KeyDown { key } ->
            if not model.isSearchFocused && isSingleAlphaNum key then
                ( filterGames catalog { model | search = key }, Task.attempt (\_ -> NoOp) (Browser.Dom.focus "search") )

            else
                ( model, Cmd.none )

        SearchFocused isFocused ->
            ( { model | isSearchFocused = isFocused }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


isSingleAlphaNum : String -> Bool
isSingleAlphaNum key =
    if String.length key > 1 then
        False

    else
        case String.toList key of
            char :: _ ->
                Char.isAlphaNum char

            [] ->
                False


normalizeSearch : String -> NormalizedSearch
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
        >> NormalizedSearch


filterGames : Backend.Catalog -> Model -> Model
filterGames catalog model =
    let
        containsSearch game =
            case model.normalizedSearch of
                NormalizedSearch search ->
                    List.any (String.contains search) game.searchNames

        containsGenres game =
            Set.size (Set.intersect game.genres model.mustHaveGenres) == Set.size model.mustHaveGenres

        filterIf condition isGood =
            if condition then
                List.filter isGood

            else
                identity

        isMultiplayer multiplayer =
            case multiplayer of
                Backend.Some ->
                    True

                Backend.Limit _ ->
                    True

                Backend.None ->
                    False

        games =
            catalog.games
                |> List.filter containsGenres
                |> List.filter containsSearch
                |> filterIf model.mustHaveSinglePlayer .hasSinglePlayer
                |> filterIf model.mustHaveCoopCampaign .hasCoopCampaign
                |> filterIf model.mustHaveOfflineCoop (.offlineCoop >> isMultiplayer)
                |> filterIf model.mustHaveOfflinePvp (.offlinePvp >> isMultiplayer)
                |> filterIf model.mustHaveOnlineCoop (.onlineCoop >> isMultiplayer)
                |> filterIf model.mustHaveOnlinePvp (.onlinePvp >> isMultiplayer)
    in
    { model | games = Pagination.fromList (chunk gamesPerPage games) }



-- VIEW


view : Backend.Catalog -> Model -> Html Msg
view catalog model =
    div
        [ css
            [ displayFlex
            , minHeight (vh 100)
            , backgroundColor Shared.background
            , color (rgb 255 255 255)
            , fontFamilies [ "Manrope", "sans-serif" ]
            ]
        ]
        [ viewSidebar catalog model
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
                    [ css styleButton, Event.onClick (NextPage next) ]

                Nothing ->
                    [ css styleButton, Attr.disabled True ]

        attrPrev =
            case Pagination.previous games of
                Just prev ->
                    [ css styleButton, Event.onClick (PrevPage prev) ]

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



-- SIDEBAR


viewSidebar : Backend.Catalog -> Model -> Html Msg
viewSidebar catalog model =
    let
        viewGenreFilter genre =
            let
                isGenreFiltered =
                    Set.member genre.id model.mustHaveGenres
            in
            viewFilter (\f -> FilterGenre ( genre.id, f )) genre.name isGenreFiltered
    in
    div [ css [ backgroundColor (rgba 0 0 0 0.25), padding (px Shared.spacing) ] ]
        [ viewTitle
        , viewSearch model.search
        , viewFilterGroup
            "Multiplayer"
            [ viewFilter FilterCoopCampaign "Co-op Campaign" model.mustHaveCoopCampaign
            , viewFilter FilterOfflineCoop "Offline Co-op" model.mustHaveOfflineCoop
            , viewFilter FilterOfflinePvp "Offline PvP" model.mustHaveOfflinePvp
            , viewFilter FilterOnlineCoop "Online Co-op" model.mustHaveOnlineCoop
            , viewFilter FilterOnlinePvp "Online PvP" model.mustHaveOnlinePvp
            , viewFilter FilterSinglePlayer "Single Player" model.mustHaveSinglePlayer
            ]
        , viewFilterGroup "Genres" (List.map viewGenreFilter catalog.genres)
        ]


viewTitle : Html msg
viewTitle =
    h1 [] [ text "Grifter" ]


viewSearch : String -> Html Msg
viewSearch search =
    input
        [ Attr.id "search"
        , type_ "search"
        , placeholder "Search..."
        , Event.onFocus (SearchFocused True)
        , Event.onBlur (SearchFocused False)
        , Event.onInput Search
        , Attr.value search
        , css
            [ padding (px 11)
            , border unset
            , backgroundColor Shared.white
            , borderRadius (px 2)
            , color Shared.black
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
            , marginLeft (px -Shared.spacing)
            , marginRight (px -Shared.spacing)
            , paddingLeft (px Shared.spacing)
            , paddingRight (px Shared.spacing)
            ]
    in
    label [ css styleLabel ]
        [ checkbox [ Attr.checked isEnabled, Event.onCheck msg ]
        , text option
        ]


checkbox : List (Attribute msg) -> Html msg
checkbox attributes =
    input
        ([ type_ "checkbox"
         , css
            [ verticalAlign middle
            , property "-webkit-appearance" "none"
            , backgroundColor Shared.black
            , width (px 12)
            , height (px 12)
            , border3 (px 1) solid Shared.white
            , borderRadius (px 2)
            , cursor inherit
            , margin4 (px 0) (px 7) (px 0) (px 0)
            , Css.checked
                [ backgroundColor Shared.white
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
    div [ css [ marginTop (px Shared.spacing), marginBottom (px Shared.spacing) ] ] (text title :: options)



-- GAMES


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
            , color Shared.white
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
        [ href ("/games/" ++ game.slug) --(Url.Builder.custom root [ game.path ] [] Nothing)
        , Attr.title game.name
        , css
            [ width (px 150)
            , height (px 200)
            , position relative
            , marginTop (px Shared.spacing)
            , marginLeft (px Shared.spacing)
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



-- LIST


chunk : Int -> List a -> List (List a)
chunk size items =
    if List.isEmpty items || size == 0 then
        []

    else if List.length items <= size then
        [ List.take size items ]

    else
        List.take size items :: chunk size (List.drop size items)



-- GLOBALS


gamesPerPage : Int
gamesPerPage =
    30
