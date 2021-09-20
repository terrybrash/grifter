module AllGames exposing (Model, Msg(..), chunk, init, update, view)

import Backend exposing (Game)
import Browser.Dom
import Css exposing (..)
import Css.Global
import Css.Transitions as Transitions
import Html.Styled exposing (Html, a, button, div, h1, h3, img, input, label, span, text)
import Html.Styled.Attributes as Attr exposing (class, css, href, placeholder, src, type_)
import Html.Styled.Events as Event
import Html.Styled.Keyed as Keyed
import Pagination exposing (Pagination)
import Set exposing (Set)
import Shared exposing (black, fredoka, inter, rgbaFromColor, userSelectNone, white)
import Svg.Styled as S
import Svg.Styled.Attributes as Sa
import Task
import Url.Builder exposing (Root(..))


type Msg
    = NoOp
    | NextPage (Pagination (List Game))
    | PrevPage (Pagination (List Game))
    | Search String
    | KeyDown Shared.KeyboardEvent
    | SearchFocused Bool
    | FilterGenre ( Int, Bool )
      -- Multiplayer
    | FilterSinglePlayer Bool
    | FilterCoopCampaign Bool
    | FilterOfflineCoop Bool
    | FilterOfflinePvp Bool
    | FilterOnlineCoop Bool
    | FilterOnlinePvp Bool
      -- Stores
    | FilterSteam Bool
    | FilterItch Bool
    | FilterGog Bool
    | FilterEpicGames Bool


type alias Model =
    { games : Maybe (Pagination (List Game))
    , search : String
    , normalizedSearch : NormalizedSearch
    , isSearchFocused : Bool
    , mustHaveGenres : Set Int

    -- Multiplayer
    , mustHaveSinglePlayer : Bool
    , mustHaveCoopCampaign : Bool
    , mustHaveOfflineCoop : Bool
    , mustHaveOfflinePvp : Bool
    , mustHaveOnlineCoop : Bool
    , mustHaveOnlinePvp : Bool

    -- Stores
    , mustHaveSteam : Bool
    , mustHaveItch : Bool
    , mustHaveGog : Bool
    , mustHaveEpicGames : Bool
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
        , mustHaveSteam = False
        , mustHaveItch = False
        , mustHaveGog = False
        , mustHaveEpicGames = False
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

        FilterSteam mustHave ->
            ( filterGames catalog { model | mustHaveSteam = mustHave }, Cmd.none )

        FilterGog mustHave ->
            ( filterGames catalog { model | mustHaveGog = mustHave }, Cmd.none )

        FilterItch mustHave ->
            ( filterGames catalog { model | mustHaveItch = mustHave }, Cmd.none )

        FilterEpicGames mustHave ->
            ( filterGames catalog { model | mustHaveEpicGames = mustHave }, Cmd.none )

        KeyDown { key, ctrl } ->
            if not ctrl && not model.isSearchFocused && isSingleAlphaNum key then
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
                |> filterIf model.mustHaveSteam (.steam >> (\u -> u /= Nothing))
                |> filterIf model.mustHaveItch (.itch >> (\u -> u /= Nothing))
                |> filterIf model.mustHaveGog (.gog >> (\u -> u /= Nothing))
                |> filterIf model.mustHaveEpicGames (.epic >> (\u -> u /= Nothing))
    in
    { model | games = Pagination.fromList (chunk gamesPerPage games) }



-- VIEW


view : Backend.Catalog -> Model -> Html Msg
view catalog model =
    div
        [ css
            [ property "display" "grid"
            , property "grid-template-columns" "auto 1fr"
            , position relative
            , color black
            , fontFamilies inter
            , maxWidth (px Shared.pageWidth)
            , marginLeft auto
            , marginRight auto
            ]
        ]
        [ Css.Global.global [ Css.Global.body [ backgroundColor Shared.yellow100, overflowY scroll ] ]
        , div
            [ css
                [ padding (px 30)
                , paddingRight (px 15)
                , property "grid-column" "1"
                , hover [ Css.Global.descendants [ Css.Global.class "checkbox" [ opacity (num 1.0) ] ] ]
                ]
            ]
            [ viewSidebar catalog model ]
        , div
            [ css
                [ padding (px 30)
                , paddingLeft (px 15)
                , property "grid-column" "2"
                , minWidth zero
                ]
            ]
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
            [ backgroundColor transparent
            , border zero
            , color Shared.black
            , borderRadius (px 4)
            , width (px 80)
            , height (px 32)
            , margin2 (px 10) (px 20)
            , display inlineFlex
            , alignItems center
            , justifyContent center
            , cursor pointer
            , userSelectNone
            , hover [ backgroundColor (hex "e7e7e7") ]
            , fontSize unset
            , Css.disabled
                [ opacity (num 0.15)
                , cursor unset
                , hover [ backgroundColor unset ]
                ]
            ]

        attrNext =
            case Pagination.next games of
                Just next ->
                    [ css styleButton, Event.onClick (NextPage next), Attr.title "Next page" ]

                Nothing ->
                    [ css styleButton, Attr.disabled True ]

        attrPrev =
            case Pagination.previous games of
                Just prev ->
                    [ css styleButton, Event.onClick (PrevPage prev), Attr.title "Previous page" ]

                Nothing ->
                    [ css styleButton, Attr.disabled True ]

        ( current, _ ) =
            Pagination.current games

        total =
            Pagination.count games
    in
    div [ css [ margin (px 32), displayFlex, alignItems center, justifyContent center ] ]
        [ button attrPrev [ div [ css [ marginRight (ch 0.5), lineHeight zero ] ] [ viewLeftAngle 13 13 ], text "Back" ]
        , span [ css [ fontWeight (int 300) ] ] [ text ("Page " ++ String.fromInt (current + 1) ++ " of " ++ String.fromInt total) ]
        , button attrNext [ text "Next", div [ css [ marginLeft (ch 0.5), lineHeight zero ] ] [ viewRightAngle 13 13 ] ]
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
            viewFilter (\f -> FilterGenre ( genre.id, f )) Shared.greenLight genre.name isGenreFiltered
    in
    div []
        [ viewSearch model.search
        , viewFilterHeader Shared.blueDark "Mode"
        , div []
            [ viewFilter FilterCoopCampaign Shared.blueLight "Co-op Campaign" model.mustHaveCoopCampaign
            , viewFilter FilterOfflineCoop Shared.blueLight "Offline Co-op" model.mustHaveOfflineCoop
            , viewFilter FilterOfflinePvp Shared.blueLight "Offline PvP" model.mustHaveOfflinePvp
            , viewFilter FilterOnlineCoop Shared.blueLight "Online Co-op" model.mustHaveOnlineCoop
            , viewFilter FilterOnlinePvp Shared.blueLight "Online PvP" model.mustHaveOnlinePvp
            , viewFilter FilterSinglePlayer Shared.blueLight "Single Player" model.mustHaveSinglePlayer
            ]
        , viewFilterHeader Shared.greenDark "Genre"
        , div []
            (List.map viewGenreFilter catalog.genres)
        , viewFilterHeader Shared.magentaDark "Store"
        , div []
            [ viewFilter FilterSteam Shared.magentaLight "Steam" model.mustHaveSteam
            , viewFilter FilterItch Shared.magentaLight "Itch.io" model.mustHaveItch
            , viewFilter FilterGog Shared.magentaLight "GOG" model.mustHaveGog
            , viewFilter FilterEpicGames Shared.magentaLight "Epic Games" model.mustHaveEpicGames
            ]
        ]


viewFilterHeader : Color -> String -> Html msg
viewFilterHeader color_ header =
    h3
        [ css
            [ marginTop (px 45)
            , marginBottom (px 14)
            , display inlineBlock
            , color color_
            ]
        ]
        [ text header ]


viewFilter : (Bool -> Msg) -> Color -> String -> Bool -> Html Msg
viewFilter msg color_ option isEnabled =
    label
        [ css
            [ displayFlex
            , alignItems center
            , cursor pointer
            , whiteSpace noWrap
            , userSelectNone
            , lineHeight (num 1.7)
            , borderRadius roundedSmall
            , position relative
            , fontWeight (int 300)
            ]
        ]
        [ input
            [ type_ "checkbox"
            , Attr.checked isEnabled
            , Event.onCheck msg
            , css
                [ property "appearance" "none"
                , width (px 10)
                , height (px 10)
                , border3 (px 1) solid color_
                , marginRight (px 10)
                , cursor pointer
                , borderRadius (px 3)
                , boxShadow5 zero zero zero (px 0.1) color_
                , display none
                ]
            ]
            []
        , div
            [ class "checkbox"
            , css
                [ position absolute
                , if isEnabled then
                    opacity (num 1.0)

                  else
                    opacity (num 0.15)
                , left zero
                , Transitions.transition [ Transitions.opacity3 250 0 (Transitions.cubicBezier 0 1 1 1) ]
                , textAlign center
                , width (px 30)
                , transform (translateX (pct -100))
                ]
            ]
            [ viewCheckbox color_ isEnabled ]
        , span [ css [ color color_ ] ] [ text option ]
        ]


viewTitle : Html msg
viewTitle =
    h1
        [ css
            [ property "grid-row" "1"
            , property "grid-column" "1"
            , fontFamilies fredoka
            , fontSize (em 4)
            , textAlign center
            , margin2 (px 20) (px 0)
            ]
        ]
        [ text "guji" ]


viewSearch : String -> Html Msg
viewSearch search =
    div [ css [ position relative ] ]
        [ input
            [ Attr.id "search"
            , type_ "search"
            , placeholder "Press any key to search"
            , Event.onFocus (SearchFocused True)
            , Event.onBlur (SearchFocused False)
            , Event.onInput Search
            , Attr.value search
            , css
                [ padding (px 15)
                , paddingLeft (px 45)
                , color black
                , fontSize inherit
                , width (ch 28)
                , backgroundColor (hex "ececeb")
                , border zero
                , borderRadius (px 8)
                , pseudoElement "placeholder"
                    [ color (hex "a2a2a2") ]
                ]
            ]
            []

        -- Icon
        , div
            [ css
                [ position absolute
                , top (pct 50)
                , left (px 15)
                , transform (translateY (pct -50))
                , pointerEvents none
                ]
            ]
            [ viewMagnifyingGlass 16 16 (hex "a2a2a2") ]
        ]



-- GAMES


viewGames : Pagination (List Game) -> Html Msg
viewGames games =
    Keyed.node "div"
        [ css
            [ displayFlex
            , flexDirection column
            ]
        ]
        (games |> Pagination.current |> Tuple.second |> List.map viewKeyedGame)


viewKeyedGame : Game -> ( String, Html Msg )
viewKeyedGame game =
    ( game.name, viewGame game )


viewGame : Game -> Html Msg
viewGame game =
    a
        [ css
            [ displayFlex
            , flexDirection row
            , marginBottom (px 30)
            , position relative
            , height (px 200)
            , overflow hidden
            , borderRadius (px 12)
            , maxWidth (pct 100)
            , property "width" "min-content"
            , hover
                [ Css.Global.descendants
                    [ Css.Global.class "name"
                        [ opacity (num 1.0)
                        , transform none
                        ]
                    ]
                ]
            ]
        , href ("/games/" ++ game.slug)
        ]
        [ div
            [ css
                [ position absolute
                , left (px 10)
                , bottom (px 10)
                , padding2 (px 10) (px 12)
                , backgroundColor (rgba 0 0 0 0.55)
                , color white
                , borderRadius (px 8)
                , property "backdrop-filter" "blur(8px)"
                , opacity zero
                , transform (translateX (px -10))
                , Transitions.transition
                    [ Transitions.opacity3 250 0 (Transitions.cubicBezier 0 1 1 1)
                    , Transitions.transform3 250 0 (Transitions.cubicBezier 0 1 1 1)
                    ]
                ]
            , class "name"
            ]
            [ text game.name ]
        , div
            [ css [ displayFlex ] ]
            (viewScreenshots game ++ [ viewCover game ])
        ]


viewCover : Game -> Html msg
viewCover game =
    case game.cover of
        Just cover ->
            img
                [ src ("/api/image/" ++ cover.id ++ "?size=Thumbnail")
                , Attr.width cover.width
                , Attr.height cover.height
                , css [ height (pct 100), width auto ]
                ]
                []

        Nothing ->
            text ""


viewScreenshots : Game -> List (Html msg)
viewScreenshots game =
    game.screenshots
        |> List.map
            (\image ->
                img
                    [ src ("/api/image/" ++ image.id ++ "?size=Thumbnail")
                    , Attr.width image.width
                    , Attr.height image.height
                    , css
                        [ height (pct 100)
                        , width auto
                        , case game.graphics of
                            Backend.Pixelated ->
                                property "image-rendering" "pixelated"

                            Backend.Smooth ->
                                property "image-rendering" "unset"
                        ]
                    ]
                    []
            )



-- LIST


chunk : Int -> List a -> List (List a)
chunk size items =
    if List.isEmpty items || size == 0 then
        []

    else if List.length items <= size then
        [ List.take size items ]

    else
        List.take size items :: chunk size (List.drop size items)



-- STYLES


rounded =
    px 8


roundedSmall =
    px 5



-- GLOBALS


gamesPerPage : Int
gamesPerPage =
    10



-- SVG
-- viewGamepadIcon : Html msg
-- viewGamepadIcon =
--     S.svg
--         [ Sa.viewBox "0 0 399 238" ]
--         [ S.rect [ Sa.fill "none", Sa.stroke "#000", Sa.strokeWidth "19", Sa.width "380", Sa.height "219", Sa.x "10", Sa.y "10", Sa.rx "109.5" ] []
--         , S.path [ Sa.fill "none", Sa.stroke "#000", Sa.strokeLinecap "round", Sa.strokeWidth "18", Sa.d "M120 79v81" ] []
--         , S.path [ Sa.fill "none", Sa.stroke "#000", Sa.strokeLinecap "round", Sa.strokeWidth "18", Sa.d "M79 119h82" ] []
--         , S.circle [ Sa.cx "14", Sa.cy "14", Sa.r "14", Sa.transform "translate(295 75)" ] []
--         , S.circle [ Sa.cx "14", Sa.cy "14", Sa.r "14", Sa.transform "translate(255 135)" ] []
--         ]


viewCheckbox : Color -> Bool -> Html msg
viewCheckbox col isChecked =
    let
        rgba =
            rgbaFromColor col
    in
    S.svg
        [ Sa.viewBox "0 0 210 210", Sa.width "11", Sa.height "11" ]
        [ if isChecked then
            S.rect [ Sa.width "196", Sa.height "196", Sa.x "7", Sa.y "7", Sa.fill rgba, Sa.stroke rgba, Sa.strokeWidth "20", Sa.rx "60" ] []

          else
            S.rect [ Sa.width "174", Sa.height "174", Sa.x "18", Sa.y "18", Sa.fill "none", Sa.stroke rgba, Sa.strokeWidth "18", Sa.rx "50" ] []
        , if isChecked then
            S.path [ Sa.fill "none", Sa.stroke "#fff", Sa.strokeLinecap "round", Sa.strokeWidth "40", Sa.d "M60 105l30 30M90 135l60-60" ] []

          else
            S.g [] []
        ]


viewMagnifyingGlass : Float -> Float -> Color -> Html msg
viewMagnifyingGlass width height color =
    S.svg
        [ Sa.viewBox "0 0 365 366", Sa.width (String.fromFloat width), Sa.height (String.fromFloat height) ]
        [ S.circle [ Sa.cx "146", Sa.cy "146", Sa.r "129.5", Sa.fill "none", Sa.stroke (rgbaFromColor color), Sa.strokeWidth "33" ] []
        , S.path [ Sa.fill "none", Sa.stroke (rgbaFromColor color), Sa.strokeLinecap "round", Sa.strokeWidth "33", Sa.d "M342 343L241 242" ] []
        ]


viewRightAngle : Float -> Float -> Html msg
viewRightAngle width height =
    S.svg
        [ Sa.viewBox "0 0 146 259", Sa.width (String.fromFloat width), Sa.height (String.fromFloat height) ]
        [ S.path [ Sa.fill "none", Sa.stroke "black", Sa.strokeLinecap "round", Sa.strokeWidth "28", Sa.d "M23 23l101 107" ] []
        , S.path [ Sa.fill "none", Sa.stroke "black", Sa.strokeLinecap "round", Sa.strokeWidth "28", Sa.d "M23 237l101-107" ] []
        ]


viewLeftAngle : Float -> Float -> Html msg
viewLeftAngle width height =
    S.svg
        [ Sa.viewBox "0 0 146 259", Sa.width (String.fromFloat width), Sa.height (String.fromFloat height) ]
        [ S.path [ Sa.fill "none", Sa.stroke "black", Sa.strokeLinecap "round", Sa.strokeWidth "28", Sa.d "M124 237L23 130" ] []
        , S.path [ Sa.fill "none", Sa.stroke "black", Sa.strokeLinecap "round", Sa.strokeWidth "28", Sa.d "M124 23L23 130" ] []
        ]
