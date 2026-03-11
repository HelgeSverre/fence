module Yaml exposing
    ( Value(..)
    , parse
    , get
    , toString
    , toList
    , toObject
    )

import Parser exposing (..)


type Value
    = String_ String
    | Int_ Int
    | Float_ Float
    | Bool_ Bool
    | Null_
    | List_ (List Value)
    | Object_ (List ( String, Value ))



-- PUBLIC API


parse : String -> Result String Value
parse input =
    let
        trimmed =
            String.trim input
    in
    if String.isEmpty trimmed then
        Ok Null_

    else
        case Parser.run (yamlDocument |. end) trimmed of
            Ok val ->
                Ok val

            Err deadEnds ->
                Err (deadEndsToString deadEnds)


get : String -> Value -> Maybe Value
get key val =
    case val of
        Object_ fields ->
            fields
                |> List.filter (\( k, _ ) -> k == key)
                |> List.head
                |> Maybe.map Tuple.second

        _ ->
            Nothing


toString : Value -> Maybe String
toString val =
    case val of
        String_ s ->
            Just s

        _ ->
            Nothing


toList : Value -> Maybe (List Value)
toList val =
    case val of
        List_ items ->
            Just items

        _ ->
            Nothing


toObject : Value -> Maybe (List ( String, Value ))
toObject val =
    case val of
        Object_ fields ->
            Just fields

        _ ->
            Nothing



-- PARSER


yamlDocument : Parser Value
yamlDocument =
    succeed identity
        |. spaces
        |= lazy (\_ -> yamlValue 0)
        |. spaces


yamlValue : Int -> Parser Value
yamlValue indent =
    oneOf
        [ flowList
        , flowObject
        , literalBlock
        , foldedBlock
        , lazy (\_ -> blockList indent)
        , backtrackable (lazy (\_ -> blockMapping indent))
        , scalarValue
        ]


spaces : Parser ()
spaces =
    chompWhile (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\u{000D}')


inlineSpaces : Parser ()
inlineSpaces =
    chompWhile (\c -> c == ' ' || c == '\t')


optionalComment : Parser ()
optionalComment =
    oneOf
        [ succeed ()
            |. inlineSpaces
            |. symbol "#"
            |. chompWhile (\c -> c /= '\n')
        , succeed ()
        ]



-- SCALARS


scalarValue : Parser Value
scalarValue =
    oneOf
        [ nullValue
        , boolValue
        , doubleQuotedString
        , singleQuotedString
        , numberValue
        , unquotedString
        ]


nullValue : Parser Value
nullValue =
    oneOf
        [ keyword "null" |> map (\_ -> Null_)
        , symbol "~" |> map (\_ -> Null_)
        ]


boolValue : Parser Value
boolValue =
    oneOf
        [ keyword "true" |> map (\_ -> Bool_ True)
        , keyword "false" |> map (\_ -> Bool_ False)
        , keyword "yes" |> map (\_ -> Bool_ True)
        , keyword "no" |> map (\_ -> Bool_ False)
        ]


numberValue : Parser Value
numberValue =
    backtrackable <|
        (getChompedString (chompWhile (\c -> Char.isDigit c || c == '-' || c == '.' || c == '+' || c == 'e' || c == 'E'))
            |> andThen
                (\s ->
                    if String.isEmpty s || s == "-" || s == "." then
                        problem "not a number"

                    else
                        case String.toInt s of
                            Just i ->
                                succeed (Int_ i)

                            Nothing ->
                                case String.toFloat s of
                                    Just f ->
                                        succeed (Float_ f)

                                    Nothing ->
                                        problem "not a number"
                )
        )


doubleQuotedString : Parser Value
doubleQuotedString =
    succeed String_
        |. symbol "\""
        |= (getChompedString (chompWhile (\c -> c /= '"')) |> map unescapeDoubleQuoted)
        |. symbol "\""


unescapeDoubleQuoted : String -> String
unescapeDoubleQuoted s =
    s
        |> String.replace "\\n" "\n"
        |> String.replace "\\t" "\t"
        |> String.replace "\\\"" "\""
        |> String.replace "\\\\" "\\"


singleQuotedString : Parser Value
singleQuotedString =
    succeed String_
        |. symbol "'"
        |= getChompedString (chompWhile (\c -> c /= '\''))
        |. symbol "'"


unquotedString : Parser Value
unquotedString =
    getChompedString
        (chompIf (\c -> not (isSpecialStart c) && c /= '\n' && c /= '\u{000D}')
            |. chompWhile (\c -> c /= '\n' && c /= '\u{000D}' && c /= '#')
        )
        |> andThen
            (\s ->
                let
                    trimmed =
                        String.trimRight s
                in
                if String.isEmpty trimmed then
                    problem "empty string"

                else
                    succeed (String_ trimmed)
            )


isSpecialStart : Char -> Bool
isSpecialStart c =
    c == '{' || c == '[' || c == '|' || c == '>' || c == '#'



-- FLOW COLLECTIONS


flowList : Parser Value
flowList =
    succeed List_
        |. symbol "["
        |. spaces
        |= flowListItems
        |. spaces
        |. symbol "]"


flowListItems : Parser (List Value)
flowListItems =
    oneOf
        [ succeed (::)
            |= lazy (\_ -> flowValue)
            |= flowListTail
        , succeed []
        ]


flowListTail : Parser (List Value)
flowListTail =
    oneOf
        [ succeed (::)
            |. spaces
            |. symbol ","
            |. spaces
            |= lazy (\_ -> flowValue)
            |= lazy (\_ -> flowListTail)
        , succeed []
        ]


flowObject : Parser Value
flowObject =
    succeed Object_
        |. symbol "{"
        |. spaces
        |= flowObjectItems
        |. spaces
        |. symbol "}"


flowObjectItems : Parser (List ( String, Value ))
flowObjectItems =
    oneOf
        [ succeed (::)
            |= lazy (\_ -> flowKeyValue)
            |= flowObjectTail
        , succeed []
        ]


flowObjectTail : Parser (List ( String, Value ))
flowObjectTail =
    oneOf
        [ succeed (::)
            |. spaces
            |. symbol ","
            |. spaces
            |= lazy (\_ -> flowKeyValue)
            |= lazy (\_ -> flowObjectTail)
        , succeed []
        ]


flowKeyValue : Parser ( String, Value )
flowKeyValue =
    succeed Tuple.pair
        |= flowKey
        |. spaces
        |. symbol ":"
        |. spaces
        |= lazy (\_ -> flowValue)


flowKey : Parser String
flowKey =
    oneOf
        [ succeed identity
            |. symbol "\""
            |= getChompedString (chompWhile (\c -> c /= '"'))
            |. symbol "\""
        , succeed identity
            |. symbol "'"
            |= getChompedString (chompWhile (\c -> c /= '\''))
            |. symbol "'"
        , getChompedString (chompWhile (\c -> c /= ':' && c /= ',' && c /= '}' && c /= '\n' && c /= ' '))
        ]


flowValue : Parser Value
flowValue =
    oneOf
        [ lazy (\_ -> flowList)
        , lazy (\_ -> flowObject)
        , nullValue
        , boolValue
        , doubleQuotedString
        , singleQuotedString
        , numberValue
        , flowUnquotedString
        ]


flowUnquotedString : Parser Value
flowUnquotedString =
    getChompedString (chompWhile (\c -> c /= ',' && c /= ']' && c /= '}' && c /= '\n' && c /= '#'))
        |> andThen
            (\s ->
                let
                    trimmed =
                        String.trim s
                in
                if String.isEmpty trimmed then
                    problem "empty flow value"

                else
                    succeed (String_ trimmed)
            )



-- BLOCK LIST


blockList : Int -> Parser Value
blockList indent =
    succeed List_
        |= (blockListItem indent
                |> andThen
                    (\first ->
                        loop [ first ] (blockListHelper indent)
                    )
           )


blockListItem : Int -> Parser Value
blockListItem indent =
    succeed identity
        |. checkIndent indent
        |. symbol "- "
        |= lazy (\_ -> blockListItemValue (indent + 2))


blockListItemValue : Int -> Parser Value
blockListItemValue indent =
    oneOf
        [ flowList
        , flowObject
        , backtrackable (lazy (\_ -> blockMapping indent))
        , lazy (\_ -> blockList indent)
        , inlineValueThenNewline
        ]


blockListHelper : Int -> List Value -> Parser (Step (List Value) (List Value))
blockListHelper indent items =
    oneOf
        [ succeed (\item -> Loop (item :: items))
            |. spacesNewlines
            |= blockListItem indent
        , succeed ()
            |> map (\_ -> Done (List.reverse items))
        ]



-- BLOCK MAPPING


blockMapping : Int -> Parser Value
blockMapping indent =
    succeed Object_
        |= (blockMappingPair indent
                |> andThen
                    (\first ->
                        loop [ first ] (blockMappingHelper indent)
                    )
           )


blockMappingPair : Int -> Parser ( String, Value )
blockMappingPair indent =
    succeed Tuple.pair
        |. checkIndent indent
        |= mappingKey
        |. symbol ":"
        |= lazy (\_ -> mappingValue (indent + 2))


mappingKey : Parser String
mappingKey =
    oneOf
        [ succeed identity
            |. symbol "\""
            |= getChompedString (chompWhile (\c -> c /= '"'))
            |. symbol "\""
        , succeed identity
            |. symbol "'"
            |= getChompedString (chompWhile (\c -> c /= '\''))
            |. symbol "'"
        , getChompedString (chompWhile (\c -> c /= ':' && c /= '\n'))
            |> map String.trimRight
        ]


mappingValue : Int -> Parser Value
mappingValue indent =
    oneOf
        [ -- Inline value on same line
          succeed identity
            |. symbol " "
            |. inlineSpaces
            |= oneOf
                [ flowList
                , flowObject
                , literalBlock
                , foldedBlock
                , inlineValueThenNewline
                ]
        , -- Value on next line(s) at deeper indent
          succeed identity
            |. optionalComment
            |. newlineAndSpaces
            |= lazy (\_ -> yamlValue indent)
        ]


inlineValueThenNewline : Parser Value
inlineValueThenNewline =
    succeed identity
        |= scalarValue
        |. optionalComment


blockMappingHelper : Int -> List ( String, Value ) -> Parser (Step (List ( String, Value )) (List ( String, Value )))
blockMappingHelper indent pairs =
    oneOf
        [ succeed (\pair -> Loop (pair :: pairs))
            |. spacesNewlines
            |= blockMappingPair indent
        , succeed ()
            |> map (\_ -> Done (List.reverse pairs))
        ]



-- MULTILINE STRINGS


literalBlock : Parser Value
literalBlock =
    succeed identity
        |. symbol "|"
        |. chompWhile (\c -> c == ' ' || c == '\t')
        |. oneOf [ symbol "\n", end ]
        |= (getOffset
                |> andThen
                    (\_ ->
                        getChompedString (chompWhile (\c -> c /= '\n'))
                            |> andThen
                                (\firstLine ->
                                    let
                                        blockIndent =
                                            countLeadingSpaces firstLine
                                    in
                                    loop [ String.trimLeft firstLine ] (literalBlockHelper blockIndent)
                                )
                    )
           )
        |> map (\lines -> String_ (String.join "\n" lines))


literalBlockHelper : Int -> List String -> Parser (Step (List String) (List String))
literalBlockHelper indent lines =
    oneOf
        [ succeed identity
            |. symbol "\n"
            |= getChompedString (chompWhile (\c -> c /= '\n'))
            |> andThen
                (\line ->
                    if String.isEmpty (String.trim line) then
                        succeed (Loop (lines ++ [ "" ]))

                    else if countLeadingSpaces line >= indent then
                        succeed (Loop (lines ++ [ String.dropLeft indent line ]))

                    else
                        succeed (Done lines)
                )
        , succeed (Done lines)
        ]


foldedBlock : Parser Value
foldedBlock =
    succeed identity
        |. symbol ">"
        |. chompWhile (\c -> c == ' ' || c == '\t')
        |. oneOf [ symbol "\n", end ]
        |= (getChompedString (chompWhile (\c -> c /= '\n'))
                |> andThen
                    (\firstLine ->
                        let
                            blockIndent =
                                countLeadingSpaces firstLine
                        in
                        loop [ String.trimLeft firstLine ] (literalBlockHelper blockIndent)
                    )
           )
        |> map (\lines -> String_ (String.join " " (List.filter (not << String.isEmpty) lines)))


countLeadingSpaces : String -> Int
countLeadingSpaces s =
    String.length s - String.length (String.trimLeft s)



-- HELPERS


checkIndent : Int -> Parser ()
checkIndent expectedIndent =
    getCol
        |> andThen
            (\col ->
                if col == expectedIndent + 1 then
                    succeed ()

                else
                    problem ("expected indent " ++ String.fromInt expectedIndent ++ " but got " ++ String.fromInt (col - 1))
            )


spacesNewlines : Parser ()
spacesNewlines =
    chompWhile (\c -> c == ' ' || c == '\n' || c == '\u{000D}' || c == '\t')


newlineAndSpaces : Parser ()
newlineAndSpaces =
    succeed ()
        |. chompIf (\c -> c == '\n' || c == '\u{000D}')
        |. chompWhile (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\u{000D}')


deadEndsToString : List DeadEnd -> String
deadEndsToString deadEnds =
    case deadEnds of
        [] ->
            "unknown parse error"

        first :: _ ->
            "Parse error at row "
                ++ String.fromInt first.row
                ++ ", col "
                ++ String.fromInt first.col
                ++ ": "
                ++ problemToString first.problem


problemToString : Problem -> String
problemToString p =
    case p of
        Expecting s ->
            "expecting " ++ s

        ExpectingInt ->
            "expecting int"

        ExpectingHex ->
            "expecting hex"

        ExpectingOctal ->
            "expecting octal"

        ExpectingBinary ->
            "expecting binary"

        ExpectingFloat ->
            "expecting float"

        ExpectingNumber ->
            "expecting number"

        ExpectingVariable ->
            "expecting variable"

        ExpectingSymbol s ->
            "expecting symbol " ++ s

        ExpectingKeyword s ->
            "expecting keyword " ++ s

        ExpectingEnd ->
            "expecting end"

        UnexpectedChar ->
            "unexpected char"

        Problem s ->
            s

        BadRepeat ->
            "bad repeat"
