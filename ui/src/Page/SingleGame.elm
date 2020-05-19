module Page.SingleGame exposing (view)

import Backend
import Css exposing (..)
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Set
import Shared
import Svg.Styled as Svg
import Svg.Styled.Attributes as SvgAttr
import Url


view : Backend.Catalog -> Backend.Game -> Html msg
view catalog game =
    let
        genres =
            catalog.genres
                |> List.filter (\genre -> Set.member genre.id game.genres)
                |> List.map .name

        multiplayer : List String
        multiplayer =
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
            , Shared.gridTemplateColumns
            , property "grid-template-rows" "min-content"
            , property "grid-gap" "14px 20px"
            , fontFamilies [ "Manrope", "sans-serif" ]
            , padding (px 14)
            , backgroundColor Shared.background
            , color Shared.foreground
            , minHeight (vh 100)
            , boxSizing borderBox
            ]
    in
    Html.div [ css style ]
        [ viewHeader game
        , viewDownload game
        , viewInfo game genres multiplayer
        , viewMedia game
        ]


viewHeader : Backend.Game -> Html msg
viewHeader game =
    Html.div
        [ css
            [ property "grid-row" "1"
            , property "grid-column-start" "1"
            , property "grid-column-end" "3"
            ]
        ]
        [ Html.h1 [] [ Html.text game.name ]
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
            [ Attr.href game.path
            , Attr.download ""
            , css
                [ border3 (px 2) solid Shared.foreground
                , borderRadius (px 3)
                , padding2 (px 12) (px 20)
                , color Shared.foreground
                , textDecoration unset
                , display inlineBlock
                , fontWeight bold
                , boxShadow5 zero (px 1) (px 2) (px 1) (rgba 0 0 0 0.24)
                , marginLeft (px 20)
                ]
            ]
            [ Html.text "Download" ]
        , Html.span [ css [ marginLeft (px 4) ] ] [ Html.text (formatBytes game.sizeBytes) ]
        , Html.div
            [ css [ fill Shared.foreground, marginTop (px -2) ] ]
            [ viewWindowsLogo [ SvgAttr.height "1em" ]
            ]
        ]


formatBytes : Int -> String
formatBytes bytes =
    if bytes > 1000000000 then
        String.fromFloat (toFloat (Basics.round ((toFloat bytes / 1000000000) * 10)) / 10) ++ " GB"

    else
        String.fromInt (Basics.round (toFloat bytes / 1000000)) ++ " MB"


chipMargin : Float
chipMargin =
    3.5


viewInfo : Backend.Game -> List String -> List String -> Html msg
viewInfo game genres multiplayer =
    Html.div [ css [ property "grid-row" "2" ] ]
        [ case game.cover of
            Just cover ->
                Html.img [ Attr.src (Url.toString cover), css [ display block, width (pct 100) ] ] []

            Nothing ->
                Html.div [] []
        , Html.div [ css [ marginTop (em 1), marginBottom (em 1) ] ]
            -- This nested div is necessary to offset the margins between the chips.
            -- We want even spacing between the chips, but don't want spacing on the outside of
            -- the chips container. Hence the negative margin.
            [ Html.div [ css [ displayFlex, flexWrap wrap, margin (px -chipMargin) ] ]
                (List.map (viewChip (hex "#4D4DCA")) genres ++ List.map (viewChip (hex "#7F48D2")) multiplayer)
            ]
        , Html.p [ css [ color Shared.foregroundOffset ] ]
            [ case game.summary of
                Just summary ->
                    Html.text summary

                Nothing ->
                    Html.text "No summary!"
            ]
        ]


viewChip : Color -> String -> Html msg
viewChip color text =
    Html.span
        [ css
            [ backgroundColor color
            ]
        , css
            [ borderRadius (px 3)
            , paddingLeft (px 6)
            , paddingRight (px 6)
            , fontSize (em 0.9)
            , whiteSpace noWrap
            , margin (px chipMargin)
            , Css.color (rgb 255 255 255)
            ]
        ]
        [ Html.text text ]


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


viewScreenshot : Backend.Game -> String -> Html msg
viewScreenshot game screenshot =
    Html.div
        [ css
            [ overflow hidden
            , borderRadius (px 3)
            , displayFlex
            , alignItems center
            , backgroundColor (rgb 0 0 0)
            ]
        ]
        [ Html.img
            [ Attr.src screenshot
            , css
                [ display block
                , width (pct 100)
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
            [ backgroundColor (rgb 0 0 0)
            , paddingTop (pct (9 / 16 * 100))
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
