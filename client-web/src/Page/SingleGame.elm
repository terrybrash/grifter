module Page.SingleGame exposing (view)

import Backend
import Css exposing (..)
import Css.Global as Global
import Css.Media exposing (hover)
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Set
import Shared
import Svg.Styled as Svg
import Svg.Styled.Attributes as SvgAttr
import Url exposing (Url)


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
            [ css [ fill Shared.foreground, lineHeight zero, marginTop (px -2) ] ]
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
        [ -- Cover art
          case game.cover of
            Just cover ->
                Html.img [ Attr.src (Url.toString cover), css [ display block, width (pct 100) ] ] []

            Nothing ->
                Html.div [] []

        -- Chips (genres + multiplayer)
        , Html.div [ css [ marginTop (em 1), marginBottom (em 1) ] ]
            -- This nested div is necessary to offset the margins between the chips.
            -- We want even spacing between the chips, but don't want spacing on the outside of
            -- the chips container. Hence the negative margin.
            [ Html.div [ css [ displayFlex, flexWrap wrap, margin (px -chipMargin) ] ]
                (List.map (viewChip (hex "#4D4DCA")) genres ++ List.map (viewChip (hex "#7F48D2")) multiplayer)
            ]

        -- Summary
        , Html.p [ css [ color Shared.foregroundOffset ] ]
            [ case game.summary of
                Just summary ->
                    Html.text summary

                Nothing ->
                    Html.text "No summary!"
            ]

        -- Store links
        , Html.div
            [ css
                [ property "display" "grid"
                , property "grid-auto-flow" "column"
                , property "grid-auto-columns" "min-content"
                , property "grid-gap" "10px"
                ]
            ]
            (List.filterMap identity
                [ game.steam |> Maybe.map (viewStoreLink "Steam" (viewSteamLogo 24 24))
                , game.epic |> Maybe.map (viewStoreLink "Epic Games" (viewEpicGamesLogo 24 24))
                , game.gog |> Maybe.map (viewStoreLink "Gog" (viewGogLogo 24 24))
                , game.itch |> Maybe.map (viewStoreLink "Itch.io" (viewItchLogo 24 24))
                ]
            )
        ]


viewStoreLink : String -> Html msg -> Url -> Html msg
viewStoreLink name logo url =
    Html.div
        [ css
            [ position relative
            , Css.hover [ Global.children [ Global.div [ display block ] ] ]
            ]
        ]
        [ -- Icon
          Html.a
            [ css
                [ backgroundColor (hex "#000")
                , borderRadius (px 4)
                , padding (px 7)
                , cursor pointer
                , displayFlex
                , alignItems center
                ]
            , Attr.href (Url.toString url)
            , Attr.target "_blank"
            ]
            [ logo ]

        -- Tooltip
        , Html.div
            [ css
                [ position absolute
                , bottom (pct 100)
                , transform (translate2 zero (em -0.7))
                , backgroundColor (hex "#000")
                , padding2 (px 6) (px 10) -- need this
                , borderRadius (px 4)
                , pointerEvents none
                , color (hex "#fff")
                , minWidth maxContent
                , property "box-shadow" "0px 4px 11px 2px #0000004f;"
                , before
                    [ property "content" "''"
                    , position absolute
                    , top (pct 100)
                    , border3 (px 10) solid transparent
                    , borderTopColor (hex "#000")
                    ]
                , display none
                ]
            ]
            [ Html.text name ]
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


storeLogoPrimaryColor : String
storeLogoPrimaryColor =
    "#9d9d9d"


viewEpicGamesLogo : Float -> Float -> Html msg
viewEpicGamesLogo width height =
    Svg.svg
        [ SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height), SvgAttr.viewBox "0 0 647.2 751" ]
        [ Svg.defs []
            [ Svg.clipPath [ SvgAttr.id "a", SvgAttr.clipPathUnits "userSpaceOnUse" ]
                [ Svg.path [ SvgAttr.d "M0 790.9h900V0H0z" ]
                    []
                ]
            ]
        , Svg.g [ SvgAttr.clipPath "url(#a)", SvgAttr.transform "matrix(1.33333 0 0 -1.33333 -278 902.6)" ]
            [ Svg.path [ SvgAttr.fill storeLogoPrimaryColor, SvgAttr.fillRule "evenodd", SvgAttr.d "M649.8 677H252.6c-32.2 0-44-12-44-44.2V244.2c0-3.7 0-7 .4-10.2.7-7 .9-13.8 7.4-21.6.7-.8 7.3-5.7 7.3-5.7 3.6-1.8 6-3 10.1-4.7l195.6-82c10.2-4.6 14.4-6.4 21.8-6.3 7.4-.1 11.7 1.7 21.8 6.3l195.6 82c4 1.6 6.5 3 10.1 4.7 0 0 6.7 5 7.3 5.7 6.6 7.8 6.7 14.6 7.4 21.6.4 3.1.5 6.5.5 10.2v388.6c0 32.3-11.9 44.1-44 44.1" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "M623.2 286.2v-1l-.1-1-.2-.8-.3-.9-.2-.8-.2-.9-.4-.8-.4-.7-.3-.8-.5-.8-.4-.7-.5-.7-.5-.7-.5-.6-.6-.7-.6-.5-.7-.6-.6-.6-.7-.5-.7-.4-.8-.6-.8-.4-.8-.4-.8-.4-.9-.4-.9-.4-.9-.2-.8-.3-.8-.3-1-.1-.7-.2-.8-.2-1-.2h-.8l-.8-.2h-1l-1-.1-.8-.1h-5.6l-1 .2h-.8l-1 .1-.9.2-.9.1-.9.2-.9.2-.9.1-.8.2-1 .3-.7.2-1 .2-.8.3-.8.4-1 .2-.7.3-1 .4-.7.3-.8.4-.8.4-.8.4-.8.4-.7.5-.9.4-.7.5-.7.4-.7.6-.7.5-.7.5-.7.6-.7.5-.7.6.6.8.6.6.5.7.6.7.6.6.5.8.6.7.6.6.6.7.5.7.7.7.5.7.5.6.7.7.5.7.6.7.6.7.7-.5.8-.6.7-.5.8-.6.7-.4.8-.5.7-.5.8-.4.7-.4.8-.4.8-.3.8-.4.8-.2.9-.4.8-.3 1-.2.7-.3 1-.2.8-.2 1-.1.9-.1.9-.2h.9l1-.1h2.9l1 .3.7.1.8.2.7.3.7.3.7.6.5.6.4.7.2.8.1 1v1.1l-.4 1-.5.6-.6.6-.7.5-.7.3-.8.4-1 .4-1 .4-.6.2-.7.2-.8.2-.8.2-1 .3-.8.2-1 .2-.9.2-1 .3-.9.2-.9.2-.9.2-.9.3-.8.2-.9.2-.8.3-.8.3-.8.2-1 .4-.8.4-1 .3-.8.4-.8.4-1 .5-.6.4-.8.5-.7.5-.8.4-.6.6-.6.6-.6.6-.6.7-.5.6-.5.6-.4.7-.4.8-.4.7-.3.7-.2.8-.3.7-.2 1-.2.7v1l-.1.8-.1 1v3l.1.8.1.9.2.8.2.8.3.8.1.8.4.8.4.8.3.8.5.8.4.8.5.7.6.8.6.7.6.6.6.7.8.6.6.5.7.5.7.6.7.4.8.5.8.3.8.5.8.3 1 .3.8.4.8.2.7.2.8.2.9.2.8.1.8.2 1 .1.8.1h1l.8.2h3.9l1-.1 1-.1h1.8l.9-.3h1l.9-.2.8-.2.9-.2.8-.2.9-.2.8-.2.8-.3.9-.2.8-.3.8-.3.9-.4.8-.3.8-.4.9-.4.7-.4.8-.4.8-.5.7-.4.8-.6.7-.4.7-.5.7-.6.7-.5-.5-.7-.4-.8-.6-.7-.5-.7-.5-.8-.5-.7-.5-.7-.6-.8-.4-.7-.5-.7-.6-.7-.4-.7-.6-.8-.5-.7-.5-.8-.5-.7-.5-.7-.7.5-.8.5-.7.4-.8.6-.8.3-.7.5-.8.3-.7.4-.8.4-.7.3-.8.3-.7.3-1 .3-.9.3-.9.3-.9.1-.9.2-.9.2h-.9l-.9.2h-2.7l-1-.1-.9-.2-.8-.2-.7-.3-.6-.4-.8-.7-.6-.8-.3-.8-.1-1v-1.3l.5-1 .4-.5.6-.6.8-.5.7-.4.9-.4 1-.3 1-.4.8-.2.7-.2.8-.2.8-.3.9-.2 1-.2 1-.3 1-.3 1-.2.8-.2 1-.3.9-.2.9-.2.9-.3.8-.3.9-.2.8-.3.8-.3 1-.3.8-.5 1-.3.8-.5.8-.4.8-.5.7-.4.8-.6.7-.4.7-.7.7-.6.6-.7.6-.6.6-.7.5-.8.5-.8.4-.8.4-.7.2-.8.3-.8.2-.8.2-1 .1-.8.1-.9.1-1v-2.2zm-62.6-18H509.4V333.5H561.2V318.7H526.5V308H557.6V294.1H526.5V283H561.6V268.2zm-65.2 0H479V307l-.4-.8-.5-.8-.4-.7-.6-.7-.4-.8-.6-.8-.4-.7-.4-.8-.6-.7-.4-.7-.6-.7-.4-.8-.5-.8-.5-.7-.4-.8-.6-.7-.4-.7-.6-.8-.4-.7-.5-.8-.5-.8-.4-.7-.6-.7-.4-.8-.5-.7-.5-.8-.5-.7-.5-.8-.4-.7-.6-.7-.4-.8-.5-.7-.5-.8-.5-.8-.5-.7h-.3l-.6.8-.4.7-.5.8-.5.8-.5.8-.5.7-.5.8-.5.7-.5.8-.4.7-.6.9-.4.7-.6.8-.4.7-.5.8-.5.7-.5.8-.6.7-.4.9-.5.7-.5.8-.5.7-.5.8-.5.7-.4.8-.6.8-.4.8-.6.7-.4.8-.5.7-.5.8-.5.7-.5.8-.5.8V268.2H428V333.5H446.3l.5-.7.4-.8.6-.7.4-.8.5-.8.4-.8.4-.7.6-.8.4-.7.5-.7.4-.8.5-.7.5-.8.4-.8.5-.8.4-.7.6-.7.4-.8.5-.7.4-.8.5-.7.5-.8.4-.8.5-.8.4-.7.5-.7.5-.8.5-.7.4-.8.5-.7.4-.8.5-.8.5-.8.4-.7.5.7.4.8.6.8.4.8.5.7.4.8.5.7.5.8.4.7.5.7.5.8.5.8.4.8.4.7.6.8.4.7.5.8.4.7.5.7.5.8.4.8.5.8.4.7.6.8.4.7.5.7.4.8.6.7.4.8.4.8.5.8.5.7.5.8.4.7H496.3V268.2zm-103.5 27l-.3.8-.4.8-.3.9-.3.8-.3.8-.4.9-.3.8-.3.8-.4.8-.2.8-.4 1-.3.7-.3.8-.4.8-.3.8-.3 1-.4.7-.2.9-.4.8-.3.9-.3.8-.4.8-.3-.8-.3-.8-.4-1-.3-.7-.3-.9-.3-.8-.4-.9-.4-.8-.2-.8-.4-.8-.3-.8-.3-.9-.4-.8-.3-.8-.3-.8-.3-.8-.4-1-.4-.7-.2-.8-.4-.9-.3-.8-.3-.9-.4-.8H392.3zm28-27H402.4l-.4.9-.2.8-.4.8-.3.9-.3.8-.4.8-.3.8-.3.8-.3.8-.4.8-.3.8-.3 1-.4.7-.3.8-.3.8h-25.7l-.3-.8-.3-.8-.3-.8-.4-.9-.2-.8-.4-.8-.3-.8-.3-.8-.4-.8-.3-.8-.3-.8-.4-1-.3-.7-.3-.8-.3-.9h-18.1l.4.9.3.8.4.8.4.9.2.8.4.8.3.8.4.8.4.8.3.9.4.8.3.8.3.8.4.8.3.8.4 1 .3.7.4.8.3.8.4.9.3.8.3.9.4.8.3.8.4.8.3.8.4.8.4.9.2.8.4.8.3.8.4.8.4.8.3 1 .4.7.3.8.3.8.4.8.3.9.4.8.3.9.4.8.3.8.4.8.3.8.3.8.4.9.3.8.4.8.3.8.4.8.4.8.2 1 .4.7.3.8.4.8.4.8.3.8.4 1 .3.7.3.9.4.8.3.8.4.8.3.9.4.8.3.8.4.8.3.8.3.8.4.9.3.8.4.8.4.8.3.8.4.8.2 1 .4.7.3.8.4.9h16.6l.3-.9.3-.8.4-.8.3-.9.3-.8.4-.8.3-.8.4-.8.3-.8.4-.9.4-.8.3-.8.3-.8.3-.8.4-.8.4-1 .3-.7.4-.8.3-.8.4-.9.2-.8.4-.9.4-.8.3-.8.4-.8.3-.8.4-.8.3-.9.3-.8.4-.8.3-.8.4-.8.3-.8.4-1 .4-.7.3-.8.3-.8.3-.8.4-.8.3-.9.4-.8.4-.9.3-.8.4-.8.2-.8.4-.8.4-.9.3-.8.4-.8.3-.8.4-.8.3-.8.3-1 .4-.7.3-.8.4-.8.3-.8.4-.8.4-1 .3-.7.3-.9.3-.8.4-.8.3-.8.4-.9.4-.8.3-.8.4-.8.2-.8.4-.8.4-.9.3-.8.4-.8.3-.8.4-.8.3-.8.3-1 .4-.7.3-.8.4-.9zm-78.2 8.4l-.7-.6-.6-.4-.8-.5-.7-.5-.7-.5-.7-.5-.7-.4-.8-.5-.8-.4-.8-.5-.8-.3-.8-.5-1-.3-.7-.4-1-.3-.7-.4-.8-.3-.8-.2-.8-.3-1-.3-.7-.3-1-.1-.7-.2-1-.2-.8-.2h-.9l-1-.1-.9-.1-1-.1-.8-.1-1-.1h-4.8l-1 .2h-.8l-1 .2h-.8l-1 .2-.8.2-.8.2-.9.2-.8.2-.9.2-.8.3-.8.3-.8.3-.9.4-.8.3-.8.4-.8.3-.8.5-.7.4-.8.5-.7.4-.8.5-.7.5-.7.6-.7.5-.6.5-.6.6-.7.6-.6.5-.6.7-.6.6-.6.6-.5.7-.6.7-.4.7-.5.7-.5.7-.4.7-.5.8-.4.8-.4.8-.3.8-.4.8-.3.8-.3.7-.4.8-.2.8-.2.8-.2 1-.3.7-.1 1-.1.7-.2 1-.1.7v1l-.2.8V303.7l.1.9.1 1 .2.8v1l.2.7.3 1 .2.8.3.8.2 1 .3.7.4 1 .3.7.4.8.3.9.4.8.4.8.5.7.4.7.5.7.4.7.5.8.6.7.5.7.6.6.6.6.5.7.6.6.7.6.6.6.7.6.6.5.7.6.8.4.7.6.7.4.7.5.8.4.8.4.8.5.8.4.8.3 1 .5.6.2 1 .3.7.4.8.1.8.3 1 .2.7.3 1 .1.8.1.9.2h.9l.9.2h.9l.9.2h3.8l1-.1 1-.1h.9l.9-.1 1-.2h.7l1-.3.8-.1.8-.2.8-.2.8-.2.8-.2.8-.2.8-.3.8-.3.8-.3.8-.4.8-.3.8-.5.8-.3.7-.5.8-.4.7-.5.8-.4.7-.6.7-.4.8-.6.7-.5.7-.6.7-.6-.5-.7-.7-.6-.5-.7-.6-.7-.6-.8-.5-.6-.6-.7-.6-.7-.5-.6-.6-.8-.6-.7-.6-.7-.5-.6-.6-.7-.6-.8-.5-.7-.6-.6-.6-.7-.7.5-.7.6-.7.5-.7.5-.7.5-.8.4-.7.5-.8.4-.7.4-.7.3-.7.3-.8.3-.8.2-.8.2-1 .2-.8.2h-.9l-1 .2H312l-.7-.1-1-.2-.7-.2-.8-.3-.8-.2-.8-.4-.8-.3-.8-.5-.7-.4-.7-.5-.6-.5-.6-.6-.7-.5-.5-.6-.6-.7-.6-.7-.4-.6-.5-.7-.4-.8-.4-.7-.4-.8-.3-.9-.3-.8-.3-.9-.2-.8-.2-.9-.1-1-.1-.8-.1-1V299l.2-.8v-.9l.2-.8.2-.8.2-.8.3-.8.2-.7.4-1 .3-.7.5-.9.4-.7.5-.7.5-.7.6-.6.6-.7.5-.6.6-.5.8-.6.7-.5.7-.4.7-.5.8-.4.8-.3.8-.4.9-.2.9-.3.9-.2.9-.2h.9l1-.1h3l1 .1.9.1.9.2.8.2 1 .2.7.2.8.4.8.3.8.4.6.4.7.4V293.2H312.8V306.3H342.5V277z" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "M313 481.2h38.7V511H313v61h40.2v30h-73V386h73.6v30H313z" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "M590 474.7v-48.8c0-8.6-4-12.6-12.2-12.6h-6.2c-8.5 0-12.5 4-12.5 12.6v136.4c0 8.6 4 12.6 12.5 12.6h5.6c8.3 0 12.3-4 12.3-12.6V520h32.2v44.1c0 26.9-12.9 39.8-39.6 39.8h-16c-26.7 0-39.9-13.2-39.9-40V424.3c0-26.8 13.2-40.1 40-40.1h16.2c26.7 0 40 13.3 40 40v50.4z" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "M476 386.1h32.8v216H476z" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "M428.3 506.1c0-8.6-4-12.6-12.3-12.6h-13.5V573H416c8.3 0 12.3-4 12.3-12.7zm-7 96h-51.6V386h32.8v78.4h18.8c26.7 0 39.9 13.3 39.9 40.1V562c0 26.8-13.2 40-40 40" ] []
            , Svg.path [ SvgAttr.fill "#000", SvgAttr.fillRule "evenodd", SvgAttr.d "M357.6 190.9h188.1l-96-31.7z" ] []
            ]
        ]


viewGogLogo : Float -> Float -> Html msg
viewGogLogo width height =
    Svg.svg [ SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height), SvgAttr.preserveAspectRatio "xMidYMid meet", SvgAttr.viewBox "0 0 34 31" ]
        [ Svg.path [ SvgAttr.fill storeLogoPrimaryColor, SvgAttr.d "M31,31H3a3,3,0,0,1-3-3V3A3,3,0,0,1,3,0H31a3,3,0,0,1,3,3V28A3,3,0,0,1,31,31ZM4,24.5A1.5,1.5,0,0,0,5.5,26H11V24H6.5a.5.5,0,0,1-.5-.5v-3a.5.5,0,0,1,.5-.5H11V18H5.5A1.5,1.5,0,0,0,4,19.5Zm8-18A1.5,1.5,0,0,0,10.5,5h-5A1.5,1.5,0,0,0,4,6.5v5A1.5,1.5,0,0,0,5.5,13H9V11H6.5a.5.5,0,0,1-.5-.5v-3A.5.5,0,0,1,6.5,7h3a.5.5,0,0,1,.5.5v6a.5.5,0,0,1-.5.5H4v2h6.5A1.5,1.5,0,0,0,12,14.5Zm0,13v5A1.5,1.5,0,0,0,13.5,26h5A1.5,1.5,0,0,0,20,24.5v-5A1.5,1.5,0,0,0,18.5,18h-5A1.5,1.5,0,0,0,12,19.5Zm9-13A1.5,1.5,0,0,0,19.5,5h-5A1.5,1.5,0,0,0,13,6.5v5A1.5,1.5,0,0,0,14.5,13h5A1.5,1.5,0,0,0,21,11.5Zm9,0A1.5,1.5,0,0,0,28.5,5h-5A1.5,1.5,0,0,0,22,6.5v5A1.5,1.5,0,0,0,23.5,13H27V11H24.5a.5.5,0,0,1-.5-.5v-3a.5.5,0,0,1,.5-.5h3a.5.5,0,0,1,.5.5v6a.5.5,0,0,1-.5.5H22v2h6.5A1.5,1.5,0,0,0,30,14.5ZM30,18H22.5A1.5,1.5,0,0,0,21,19.5V26h2V20.5a.5.5,0,0,1,.5-.5h1v6h2V20H28v6h2ZM18.5,11h-3a.5.5,0,0,1-.5-.5v-3a.5.5,0,0,1,.5-.5h3a.5.5,0,0,1,.5.5v3A.5.5,0,0,1,18.5,11Zm-4,9h3a.5.5,0,0,1,.5.5v3a.5.5,0,0,1-.5.5h-3a.5.5,0,0,1-.5-.5v-3A.5.5,0,0,1,14.5,20Z" ] []
        ]


viewSteamLogo : Float -> Float -> Html msg
viewSteamLogo width height =
    Svg.svg [ SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height), SvgAttr.viewBox "0 0 233 233" ]
        [ Svg.path [ SvgAttr.fill storeLogoPrimaryColor, SvgAttr.d "m4.8911 150.01c14.393 48.01 58.916 82.99 111.61 82.99 64.34 0 116.5-52.16 116.5-116.5 0-64.341-52.16-116.5-116.5-116.5-61.741 0-112.26 48.029-116.25 108.76 7.5391 12.66 10.481 20.49 4.6411 41.25z" ] []
        , Svg.path [ SvgAttr.fill "#000", SvgAttr.d "m110.5 87.322c0 0.196 0 0.392 0.01 0.576l-28.508 41.412c-4.618-0.21-9.252 0.6-13.646 2.41-1.937 0.79-3.752 1.76-5.455 2.88l-62.599-25.77c0.00049 0-1.4485 23.83 4.588 41.59l44.254 18.26c2.222 9.93 9.034 18.64 19.084 22.83 16.443 6.87 35.402-0.96 42.242-17.41 1.78-4.3 2.61-8.81 2.49-13.31l40.79-29.15c0.33 0.01 0.67 0.02 1 0.02 24.41 0 44.25-19.9 44.25-44.338 0-24.44-19.84-44.322-44.25-44.322-24.4 0-44.25 19.882-44.25 44.322zm-6.84 83.918c-5.294 12.71-19.9 18.74-32.596 13.45-5.857-2.44-10.279-6.91-12.83-12.24l14.405 5.97c9.363 3.9 20.105-0.54 23.997-9.9 3.904-9.37-0.525-20.13-9.883-24.03l-14.891-6.17c5.746-2.18 12.278-2.26 18.381 0.28 6.153 2.56 10.927 7.38 13.457 13.54s2.52 12.96-0.04 19.1m51.09-54.38c-16.25 0-29.48-13.25-29.48-29.538 0-16.275 13.23-29.529 29.48-29.529 16.26 0 29.49 13.254 29.49 29.529 0 16.288-13.23 29.538-29.49 29.538m-22.09-29.583c0-12.253 9.92-22.191 22.14-22.191 12.23 0 22.15 9.938 22.15 22.191 0 12.254-9.92 22.183-22.15 22.183-12.22 0-22.14-9.929-22.14-22.183z" ] []
        ]


viewItchLogo : Float -> Float -> Html msg
viewItchLogo width height =
    Svg.svg [ SvgAttr.width (String.fromFloat width), SvgAttr.height (String.fromFloat height), SvgAttr.viewBox "0 0 245.4 220.7" ]
        [ Svg.path [ SvgAttr.d "M31.99 1.365C21.287 7.72.2 31.945 0 38.298v10.516C0 62.144 12.46 73.86 23.773 73.86c13.584 0 24.902-11.258 24.903-24.62 0 13.362 10.93 24.62 24.515 24.62 13.586 0 24.165-11.258 24.165-24.62 0 13.362 11.622 24.62 25.207 24.62h.246c13.586 0 25.208-11.258 25.208-24.62 0 13.362 10.58 24.62 24.164 24.62 13.585 0 24.515-11.258 24.515-24.62 0 13.362 11.32 24.62 24.903 24.62 11.313 0 23.773-11.714 23.773-25.046V38.298c-.2-6.354-21.287-30.58-31.988-36.933C180.118.197 157.056-.005 122.685 0c-34.37.003-81.228.54-90.697 1.365zm65.194 66.217a28.025 28.025 0 0 1-4.78 6.155c-5.128 5.014-12.157 8.122-19.906 8.122a28.482 28.482 0 0 1-19.948-8.126c-1.858-1.82-3.27-3.766-4.563-6.032l-.006.004c-1.292 2.27-3.092 4.215-4.954 6.037a28.5 28.5 0 0 1-19.948 8.12c-.934 0-1.906-.258-2.692-.528-1.092 11.372-1.553 22.24-1.716 30.164l-.002.045c-.02 4.024-.04 7.333-.06 11.93.21 23.86-2.363 77.334 10.52 90.473 19.964 4.655 56.7 6.775 93.555 6.788h.006c36.854-.013 73.59-2.133 93.554-6.788 12.883-13.14 10.31-66.614 10.52-90.474-.022-4.596-.04-7.905-.06-11.93l-.003-.045c-.162-7.926-.623-18.793-1.715-30.165-.786.27-1.757.528-2.692.528a28.5 28.5 0 0 1-19.948-8.12c-1.862-1.822-3.662-3.766-4.955-6.037l-.006-.004c-1.294 2.266-2.705 4.213-4.563 6.032a28.48 28.48 0 0 1-19.947 8.125c-7.748 0-14.778-3.11-19.906-8.123a28.025 28.025 0 0 1-4.78-6.155 27.99 27.99 0 0 1-4.736 6.155 28.49 28.49 0 0 1-19.95 8.124c-.27 0-.54-.012-.81-.02h-.007c-.27.008-.54.02-.813.02a28.49 28.49 0 0 1-19.95-8.123 27.992 27.992 0 0 1-4.736-6.155zm-20.486 26.49l-.002.01h.015c8.113.017 15.32 0 24.25 9.746 7.028-.737 14.372-1.105 21.722-1.094h.006c7.35-.01 14.694.357 21.723 1.094 8.93-9.747 16.137-9.73 24.25-9.746h.014l-.002-.01c3.833 0 19.166 0 29.85 30.007L210 165.244c8.504 30.624-2.723 31.373-16.727 31.4-20.768-.773-32.267-15.855-32.267-30.935-11.496 1.884-24.907 2.826-38.318 2.827h-.006c-13.412 0-26.823-.943-38.318-2.827 0 15.08-11.5 30.162-32.267 30.935-14.004-.027-25.23-.775-16.726-31.4L46.85 124.08C57.534 94.073 72.867 94.073 76.7 94.073zm45.985 23.582v.006c-.02.02-21.863 20.08-25.79 27.215l14.304-.573v12.474c0 .584 5.74.346 11.486.08h.006c5.744.266 11.485.504 11.485-.08v-12.474l14.304.573c-3.928-7.135-25.79-27.215-25.79-27.215v-.006l-.003.002z", SvgAttr.fill storeLogoPrimaryColor ] []
        ]
