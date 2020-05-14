module Page.SingleGame exposing (view)

import Backend
import Css exposing (..)
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Url


view : Backend.Game -> Html msg
view game =
    let
        style =
            [ property "display" "grid"
            , property "grid-template-columns" "300px auto"
            , property "grid-gap" "20px"
            , padding (px 20)
            ]
    in
    Html.div [ css style ]
        [ viewHeader game
        , viewInfo game
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


viewInfo : Backend.Game -> Html msg
viewInfo game =
    Html.div [ css [ property "grid-row" "2" ] ]
        [ case game.cover of
            Just cover ->
                Html.img [ Attr.src (Url.toString cover), css [ display block, width (pct 100) ] ] []

            Nothing ->
                Html.div [] []
        , case game.summary of
            Just summary ->
                Html.p [] [ Html.text summary ]

            Nothing ->
                Html.p [] [ Html.text "No summary!" ]
        ]


viewMedia : Backend.Game -> Html msg
viewMedia game =
    Html.div
        [ css
            [ property "display" "grid"
            , property "grid-row" "2"
            , property "grid-template-columns" "repeat(3, 1fr)"
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

            -- , Attr.width 560
            -- , Attr.height 315
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
