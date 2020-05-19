module Page.SingleGame exposing (view)

import Backend
import Css exposing (..)
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Set
import Shared
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
        , Html.img [ Attr.src "/assets/windows.svg", css [ height (em 1), marginTop (px -2) ] ] []
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
