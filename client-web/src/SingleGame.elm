module SingleGame exposing (Msg(..), view)

import Backend
import Css exposing (..)
import Css.Global
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Html.Styled.Events as Event
import Set
import Shared exposing (inter, rgbaFromColor)
import Svg.Styled as Svg
import Svg.Styled.Attributes as SvgAttr
import Url exposing (Url)


type Msg
    = GoBack


view : Backend.Catalog -> Backend.Game -> Html Msg
view catalog game =
    let
        genres : List String
        genres =
            catalog.genres
                |> List.filter (\genre -> Set.member genre.id game.genres)
                |> List.map .name

        stores : List ( String, Url )
        stores =
            List.filterMap identity
                [ Maybe.map (\url -> ( "Steam", url )) game.steam
                , Maybe.map (\url -> ( "GOG", url )) game.gog
                , Maybe.map (\url -> ( "Itch.io", url )) game.itch
                , Maybe.map (\url -> ( "Epic Games", url )) game.epic
                , Maybe.map (\url -> ( "Google Play", url )) game.googlePlay
                , Maybe.map (\url -> ( "Apple iPhone", url )) game.applePhone
                , Maybe.map (\url -> ( "Apple iPad", url )) game.applePad
                , Maybe.map (\url -> ( "IGDB", url )) (Url.fromString ("https://www.igdb.com/games/" ++ game.slug))
                ]

        modes : List String
        modes =
            List.filterMap identity
                [ if game.hasSinglePlayer then
                    Just "Single Player"

                  else
                    Nothing
                , if game.hasCoopCampaign then
                    Just "Co-op Campaign"

                  else
                    Nothing
                , case game.offlineCoop of
                    Backend.Some ->
                        Just "Offline Co-op"

                    Backend.Limit max ->
                        Just ("Offline " ++ String.fromInt max ++ "-Player Co-op")

                    Backend.None ->
                        Nothing
                , case game.onlineCoop of
                    Backend.Some ->
                        Just "Online Co-op"

                    Backend.Limit max ->
                        Just ("Online " ++ String.fromInt max ++ "-Player Co-op")

                    Backend.None ->
                        Nothing
                , case game.offlinePvp of
                    Backend.Some ->
                        Just "Offline PvP"

                    Backend.Limit max ->
                        Just ("Offline " ++ String.fromInt max ++ "-Player PvP")

                    Backend.None ->
                        Nothing
                , case game.onlinePvp of
                    Backend.Some ->
                        Just "Online PvP"

                    Backend.Limit max ->
                        Just ("Online " ++ String.fromInt max ++ "-Player PvP")

                    Backend.None ->
                        Nothing
                ]

        style =
            [ property "display" "grid"
            , property "grid-template-columns" "235px 1fr"
            , property "grid-template-rows" "min-content"
            , property "grid-gap" "30px 12px"
            , fontFamilies inter
            , padding (px 30)
            , maxWidth (px Shared.pageWidth)
            , marginLeft auto
            , marginRight auto
            , color Shared.black
            , minHeight (vh 100)
            , boxSizing borderBox
            ]
    in
    Html.div [ css style ]
        [ Css.Global.global [ Css.Global.body [ backgroundColor Shared.yellow100 ] ]
        , viewHeader game
        , viewDownload game
        , viewInfo game genres modes stores
        , viewMedia game
        ]


viewHeader : Backend.Game -> Html Msg
viewHeader game =
    Html.div
        [ css
            [ property "grid-row" "1"
            , property "grid-column-start" "1"
            , property "grid-column-end" "3"
            , displayFlex
            , alignItems center
            , fontSize (em 1.7)
            , fontWeight (int 600)
            ]
        ]
        [ Html.div
            [ css
                [ padding2 (px 5) (px 10)
                , borderRadius (px 4)
                , marginRight (px 10)
                , marginLeft (px -10) -- align the arrow with the cover art
                , hover [ backgroundColor (rgb 237 237 237) ]
                , cursor pointer
                ]
            , Event.onClick GoBack
            ]
            [ viewBackArrow 20 20 "black" ]
        , Html.h1 [] [ Html.text game.name ]
        ]


viewDownload : Backend.Game -> Html msg
viewDownload game =
    Html.div
        [ css
            [ property "grid-column" "2"
            , property "grid-row" "1"
            , displayFlex
            , alignItems center
            , flexDirection rowReverse
            ]
        ]
        [ Html.a
            [ Attr.href ("/api/download/" ++ game.slug)
            , Attr.download ""
            , css
                [ border3 (px 2) solid Shared.black
                , borderRadius (px 8)
                , padding2 (px 12) (px 20)
                , color Shared.black
                , textDecoration unset
                , display inlineFlex
                , alignItems center
                , fontWeight (int 500)
                , boxShadow5 zero (px 1) (px 2) (px 1) (rgba 0 0 0 0.24)
                , marginLeft (px 20)
                ]
            ]
            [ Html.div [ css [ marginRight (ch 0.4), lineHeight zero ] ] [ viewWindowsLogo [ SvgAttr.height "1em" ] ]
            , Html.text "Download"
            ]
        , Html.span [ css [ marginLeft (px 4) ] ] [ Html.text (formatBytes game.sizeBytes) ]
        ]


formatBytes : Int -> String
formatBytes bytes =
    let
        gigabyte =
            1000000000
    in
    if bytes >= gigabyte then
        String.fromFloat (toFloat (Basics.round ((toFloat bytes / gigabyte) * 10)) / 10) ++ " GB"

    else
        String.fromInt (Basics.round (toFloat bytes / 1000000)) ++ " MB"


viewInfo : Backend.Game -> List String -> List String -> List ( String, Url ) -> Html msg
viewInfo game genres modes stores =
    Html.div [ css [ property "grid-row" "2", lineHeight (num 1.7) ] ]
        [ -- Cover art
          case game.cover of
            Just cover ->
                Html.img
                    [ Attr.src ("/api/image/" ++ cover.id ++ "?size=Original")
                    , Attr.width cover.width
                    , Attr.height cover.height
                    , css [ display block, width (pct 100), height auto, marginBottom (em 1) ]
                    ]
                    []

            Nothing ->
                Html.text ""
        , Html.div [ css [ marginBottom (em 1) ] ]
            [ Html.div [] (List.map (\text -> Html.div [ css [ color Shared.blueLight ] ] [ Html.text text ]) modes)
            , Html.div [] (List.map (\text -> Html.div [ css [ color Shared.greenLight ] ] [ Html.text text ]) genres)
            , Html.div []
                (List.map
                    (\( text, url ) ->
                        Html.a
                            [ css [ display block, color Shared.magentaLight, textDecoration none, hover [ textDecoration underline ] ]
                            , Attr.href (Url.toString url)
                            , Attr.target "_blank"
                            , Attr.rel "noreferrer"
                            ]
                            [ Html.text text
                            , Html.span [ css [ marginLeft (px 3) ] ] [ viewArrowUpRight 9 9 Shared.magentaLight ]
                            ]
                    )
                    stores
                )
            ]

        -- Summary
        , Html.p [ css [ color (hsl 0 0 0.32), marginBottom (em 1), fontWeight (int 300) ] ]
            [ case game.summary of
                Just summary ->
                    Html.text summary

                Nothing ->
                    Html.text "No summary!"
            ]
        ]


viewMedia : Backend.Game -> Html msg
viewMedia game =
    Html.div
        [ css
            [ property "display" "grid"
            , property "grid-row" "2"
            , property "grid-template-columns" "repeat(2, 1fr)"
            , property "grid-gap" "10px"
            , property "height" "min-content"
            ]
        ]
        (List.map viewVideo game.videos
            ++ List.map (viewScreenshot game) game.screenshots
        )


viewScreenshot : Backend.Game -> Backend.Image -> Html msg
viewScreenshot game screenshot =
    Html.div
        [ css
            [ overflow hidden
            , borderRadius (px 3)
            , displayFlex
            , alignItems center
            ]
        ]
        [ Html.img
            [ Attr.src ("/api/image/" ++ screenshot.id ++ "?size=Original")
            , Attr.width screenshot.width
            , Attr.height screenshot.height
            , css
                [ display block
                , width (pct 100)
                , height auto
                , case game.graphics of
                    Backend.Pixelated ->
                        property "image-rendering" "pixelated"

                    Backend.Smooth ->
                        property "image-rendering" "unset"
                ]
            ]
            []
        ]


viewVideo : String -> Html msg
viewVideo video =
    Html.div
        [ css
            [ paddingTop (pct (9 / 16 * 100))
            , position relative
            , overflow hidden
            , borderRadius (px 3)
            ]
        ]
        [ Html.iframe
            [ Attr.src video
            , Attr.attribute "frameborder" "0"
            , Attr.attribute "allowfullscreen" ""
            , css
                [ width (pct 100)
                , height (pct 100)
                , position absolute
                , top zero
                , left zero
                ]
            ]
            []
        ]


viewWindowsLogo : List (Svg.Attribute msg) -> Html msg
viewWindowsLogo attributes =
    Svg.svg
        (attributes ++ [ SvgAttr.viewBox "0 0 174 153" ])
        [ Svg.path [ SvgAttr.d "m170.41 21.125c-32.996 13.642-48.861 5.973-63.16-3.65l-16.278 56.462c14.285 9.678 31.531 17.635 63.188 3.463z" ] []
        , Svg.path [ SvgAttr.d "m63.142 134.63c-14.331-9.645-29.91-17.578-62.984-3.902l16.195-56.568c33.081-13.678 48.973-5.938 63.29 3.766l-16.501 56.703z" ] []
        , Svg.path [ SvgAttr.d "m82.393 67.715c-8.628-5.81-17.907-11.233-31.085-11.333-8.695-.067-19.045 2.403-32.184 7.836l16.283-56.422c33.059-13.669 48.938-5.933 63.245 3.764z" ] []
        , Svg.path [ SvgAttr.d "m88.227 83.369c14.313 9.637 30.212 17.313 63.243 3.66l-16.281 56.234c-33.037 13.664-48.903 5.926-63.201-3.77z" ] []
        ]


viewBackArrow : Float -> Float -> String -> Html msg
viewBackArrow width height color =
    Svg.svg
        [ SvgAttr.viewBox "0 0 430 286", SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height) ]
        [ Svg.path [ SvgAttr.stroke color, SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "52", SvgAttr.d "M37 141h367" ] []
        , Svg.path [ SvgAttr.stroke color, SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "52", SvgAttr.d "M145 249L37 141" ] []
        , Svg.path [ SvgAttr.stroke color, SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "52", SvgAttr.d "M37 141L141 37" ] []
        ]


viewArrowUpRight : Float -> Float -> Color -> Html msg
viewArrowUpRight width height color =
    Svg.svg
        [ SvgAttr.viewBox "0 0 238 238", SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height) ]
        [ Svg.path [ SvgAttr.fill "none", SvgAttr.stroke (rgbaFromColor color), SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "33", SvgAttr.d "M45 23h169" ] []
        , Svg.path [ SvgAttr.fill "none", SvgAttr.stroke (rgbaFromColor color), SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "33", SvgAttr.d "M214 192V23" ] []
        , Svg.path [ SvgAttr.fill "none", SvgAttr.stroke (rgbaFromColor color), SvgAttr.strokeLinecap "round", SvgAttr.strokeWidth "33", SvgAttr.d "M23 214L214 23" ] []
        ]
