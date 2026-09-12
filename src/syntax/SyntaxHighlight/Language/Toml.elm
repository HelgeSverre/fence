module SyntaxHighlight.Language.Toml exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A line-oriented lexer for TOML (and, closely enough, INI): comments,
table headers, keys before `=`, the four string forms, booleans, numbers in
every base, RFC3339 dates and times, arrays and inline tables.

Known gaps, acceptable for highlighting: a key is taken to be everything
before the `=` on a line that starts one, so a dotted or quoted key is a
single span rather than separate parts; a date is matched by shape, not
validated; and a value continued over several lines (a multi-line array)
loses the key position, so its elements are lexed as ordinary values.

-}

import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, problem, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (chompIfThenWhile, delimited, escapable, isEscapable, isLineBreak, isSpace, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Escapable
    | Key
    | Operator
    | LiteralKeyword
    | TableHeader
    | Group


toLines : String -> Result (List DeadEnd) (List Line)
toLines =
    Parser.run toRevTokens
        >> Result.map (Line.toLines syntaxToStyle)


toRevTokens : Parser (List Token)
toRevTokens =
    loop [] mainLoop


mainLoop : List Token -> Parser (Step (List Token) (List Token))
mainLoop revTokens =
    oneOf
        [ lineBreak
            |> map (\n -> Loop (n :: revTokens))
        , space
            |> map (\n -> Loop (n :: revTokens))
        , comment
            |> map (\n -> Loop (n :: revTokens))
        , if atLineStart revTokens then
            tableHeader |> map (\n -> Loop (n :: revTokens))

          else
            problem "not at line start"
        , if expectsKey revTokens then
            key |> map (\ns -> Loop (ns ++ revTokens))

          else
            problem "not at a key position"
        , stringLiteral
            |> map (\ns -> Loop (ns ++ revTokens))
        , oneOf
            [ dateOrTime
            , number_
            , groupChar
            , word
            ]
            |> map (\n -> Loop (n :: revTokens))
        , chompIf (always True)
            |> getChompedString
            |> map (\b -> Loop (( T.Normal, b ) :: revTokens))
        , succeed (Done revTokens)
        ]



-- Position helpers


atLineStart : List Token -> Bool
atLineStart revTokens =
    case revTokens of
        [] ->
            True

        ( T.LineBreak, _ ) :: _ ->
            True

        ( T.Normal, s ) :: rest ->
            String.trim s == "" && atLineStart rest

        _ ->
            False


{-| A key can start a line, or follow `{` or `,` inside an inline table.
-}
expectsKey : List Token -> Bool
expectsKey revTokens =
    case revTokens of
        ( T.C Group, "{" ) :: _ ->
            True

        ( T.C Group, "," ) :: _ ->
            True

        ( T.Normal, s ) :: rest ->
            String.trim s == "" && expectsKey rest

        _ ->
            atLineStart revTokens



-- Line-start tokens


{-| `[table]` and `[[array.of.tables]]`, as one span up to the closing
brackets or the end of the line.
-}
tableHeader : Parser Token
tableHeader =
    succeed (\b -> ( T.C TableHeader, b ))
        |= getChompedString
            (succeed ()
                |. symbol "["
                |. chompWhile (\c -> c /= ']' && not (isLineBreak c))
                |. chompWhile (\c -> c == ']')
            )


{-| Everything before the `=` that starts a value: a bare, dotted or quoted
key. Emitted as two tokens so the `=` keeps the operator style.
-}
key : Parser (List Token)
key =
    backtrackable
        (chompIfThenWhile (\c -> c /= '=' && c /= '#' && c /= '[' && c /= '{' && not (isLineBreak c))
            |> getChompedString
            |> andThen
                (\name ->
                    symbol "="
                        |> map (\_ -> [ ( T.C Operator, "=" ), ( T.C Key, name ) ])
                )
        )



-- Values


{-| RFC3339 dates and times, matched by shape: `1979-05-27`, optionally with
a time and offset, or a bare `07:32:00.999`.
-}
dateOrTime : Parser Token
dateOrTime =
    backtrackable
        (succeed (\b -> ( T.C Number, b ))
            |= getChompedString
                (oneOf
                    [ succeed ()
                        |. digits 4
                        |. symbol "-"
                        |. digits 2
                        |. symbol "-"
                        |. digits 2
                        |. chompWhile isDateTailChar
                    , succeed ()
                        |. digits 2
                        |. symbol ":"
                        |. digits 2
                        |. chompWhile isDateTailChar
                    ]
                )
        )


digits : Int -> Parser ()
digits count =
    List.repeat count (chompIf Char.isDigit)
        |> List.foldl (\p acc -> acc |. p) (succeed ())


isDateTailChar : Char -> Bool
isDateTailChar c =
    Char.isDigit c || c == ':' || c == '.' || c == '+' || c == '-' || c == 'T' || c == 't' || c == 'Z' || c == 'z'


number_ : Parser Token
number_ =
    backtrackable
        (succeed ()
            |. oneOf [ symbol "-", symbol "+", succeed () ]
            |. chompIf Char.isDigit
            |. chompWhile isNumberBodyChar
            |> getChompedString
            |> andThen exponentSign
            |> map (\b -> ( T.C Number, b ))
        )


{-| An `e`/`E` at the end of what was chomped may carry a signed exponent;
anywhere else a `+`/`-` ends the number.
-}
exponentSign : String -> Parser String
exponentSign chomped =
    if String.endsWith "e" (String.toLower chomped) then
        oneOf
            [ backtrackable
                (succeed ()
                    |. oneOf [ symbol "-", symbol "+" ]
                    |. chompIf Char.isDigit
                    |. chompWhile Char.isDigit
                    |> getChompedString
                )
            , succeed ""
            ]
            |> map (\rest -> chomped ++ rest)

    else
        succeed chomped


isNumberBodyChar : Char -> Bool
isNumberBodyChar c =
    Char.isHexDigit c || c == '.' || c == '_' || c == 'x' || c == 'o'


groupChar : Parser Token
groupChar =
    chompIf (\c -> c == '{' || c == '}' || c == '[' || c == ']' || c == ',')
        |> getChompedString
        |> map (\b -> ( T.C Group, b ))


word : Parser Token
word =
    chompIfThenWhile (\c -> Char.isAlphaNum c || c == '_' || c == '-')
        |> getChompedString
        |> map
            (\b ->
                if Set.member b literalKeywordSet then
                    ( T.C LiteralKeyword, b )

                else
                    ( T.Normal, b )
            )


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList [ "true", "false", "inf", "nan" ]



-- Strings


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ multilineBasicString
        , multilineLiteralString
        , basicString
        , literalString
        ]


multilineBasicString : Parser (List Token)
multilineBasicString =
    delimited
        { start = "\"\"\""
        , end = "\"\"\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, stringEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


multilineLiteralString : Parser (List Token)
multilineLiteralString =
    delimited
        { start = "'''"
        , end = "'''"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c)
        }


basicString : Parser (List Token)
basicString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, stringEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


literalString : Parser (List Token)
literalString =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c)
        }


stringEscapable : Parser (List Token)
stringEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C Escapable, b ) ])



-- Whitespace and comments


space : Parser Token
space =
    chompIfThenWhile isSpace
        |> getChompedString
        |> map (\b -> ( T.Normal, b ))


lineBreak : Parser Token
lineBreak =
    symbol "\n"
        |> map (\_ -> ( T.LineBreak, "\n" ))


lineBreakList : Parser (List Token)
lineBreakList =
    lineBreak |> map List.singleton


comment : Parser Token
comment =
    symbol "#"
        |> thenChompWhile (not << isLineBreak)
        |> getChompedString
        |> map (\b -> ( T.Comment, b ))



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "toml-n" )

        String ->
            ( Style2, "toml-s" )

        Escapable ->
            ( Style1, "toml-e" )

        Key ->
            ( Style5, "toml-k" )

        Operator ->
            ( Style3, "toml-o" )

        LiteralKeyword ->
            ( Style6, "toml-lk" )

        TableHeader ->
            ( Style4, "toml-th" )

        Group ->
            ( Style4, "toml-g" )
