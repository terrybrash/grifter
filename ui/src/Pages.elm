module Pages exposing (Pages, count, current, fromList, next, previous)


type Pages i
    = Pages ( List i, i, List i )


fromList : List i -> Maybe (Pages i)
fromList items =
    case items of
        head :: tail ->
            Just (Pages ( [], head, tail ))

        [] ->
            Nothing


count : Pages i -> Int
count (Pages pages) =
    let
        ( prev, _, next_ ) =
            pages
    in
    List.length prev + 1 + List.length next_


current : Pages i -> ( Int, i )
current (Pages pages) =
    let
        ( prev, curr, _ ) =
            pages
    in
    ( List.length prev, curr )


next : Pages i -> Maybe (Pages i)
next (Pages pages) =
    case pages of
        ( prev, curr, next_ :: rest ) ->
            Just (Pages ( curr :: prev, next_, rest ))

        _ ->
            Nothing


previous : Pages i -> Maybe (Pages i)
previous (Pages pages) =
    case pages of
        ( prev :: rest, curr, next_ ) ->
            Just (Pages ( rest, prev, curr :: next_ ))

        _ ->
            Nothing
