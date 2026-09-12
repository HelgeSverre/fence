module SyntaxHighlight.Language.Yaml exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A line-oriented lexer for YAML. It recognizes the tokens that carry the
visual structure of a document -- mapping keys, list dashes, document
markers, anchors, tags, quoted strings, block scalar indicators, numbers and
literal keywords -- without building the indentation-sensitive tree a real
YAML parser needs.

Known gaps, acceptable for highlighting: the body of a block scalar
(`key: |`) keeps being lexed as YAML, so a `word:` inside one is styled as a
mapping key; a plain multi-word scalar containing a colon on a line of its
own is likewise read as a key; and complex keys (`? key`) are plain text.

-}

import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, getChompedString, getOffset, getSource, loop, map, oneOf, problem, succeed, symbol)
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
    | Anchor
    | Tag
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
        , if afterSpace revTokens then
            comment |> map (\n -> Loop (n :: revTokens))

          else
            problem "not a comment"
        , if atLineStart revTokens then
            oneOf
                [ documentMarker
                , listDash
                , mappingKey
                ]
                |> map (\ns -> Loop (ns ++ revTokens))

          else
            problem "not at line start"
        , stringLiteral
            |> map (\ns -> Loop (ns ++ revTokens))
        , oneOf
            [ anchorOrAlias
            , tag
            , blockScalarIndicator
            , tilde
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



-- Position helpers: the lexer only needs to know whether it sits at the
-- start of a line (after indentation and an optional list dash) and whether
-- the previous character was whitespace.


atLineStart : List Token -> Bool
atLineStart revTokens =
    case revTokens of
        [] ->
            True

        ( T.LineBreak, _ ) :: _ ->
            True

        ( T.Normal, s ) :: rest ->
            String.trim s == "" && atLineStart rest

        ( T.C Operator, "-" ) :: rest ->
            atLineStart rest

        _ ->
            False


afterSpace : List Token -> Bool
afterSpace revTokens =
    case revTokens of
        [] ->
            True

        ( T.LineBreak, _ ) :: _ ->
            True

        ( T.Normal, s ) :: _ ->
            String.endsWith " " s || String.endsWith "\t" s

        _ ->
            False


{-| Succeeds without consuming when the next character ends a token: a space,
a line break, a comment or the end of input.
-}
followedByBreak : Parser ()
followedByBreak =
    succeed (\offset src -> String.dropLeft offset src |> String.uncons)
        |= getOffset
        |= getSource
        |> andThen
            (\next ->
                case next of
                    Nothing ->
                        succeed ()

                    Just ( c, _ ) ->
                        if isSpace c || isLineBreak c || c == '#' then
                            succeed ()

                        else
                            problem "expected a token boundary"
            )



-- Line-start tokens


documentMarker : Parser (List Token)
documentMarker =
    backtrackable
        (succeed (\b -> [ ( T.C Operator, b ) ])
            |= getChompedString (oneOf [ symbol "---", symbol "..." ])
            |. followedByBreak
        )


listDash : Parser (List Token)
listDash =
    backtrackable
        (succeed (\b -> [ ( T.C Operator, b ) ])
            |= getChompedString (symbol "-")
            |. followedByBreak
        )


{-| `key:` -- everything up to a colon that ends the token. Emitted as two
tokens so the colon keeps the operator style.
-}
mappingKey : Parser (List Token)
mappingKey =
    backtrackable
        (chompIfThenWhile (\c -> c /= ':' && c /= '#' && not (isLineBreak c))
            |> getChompedString
            |> andThen
                (\name ->
                    succeed ()
                        |. symbol ":"
                        |. followedByBreak
                        |> map (\_ -> [ ( T.C Operator, ":" ), ( T.C Key, name ) ])
                )
        )



-- Value tokens


anchorOrAlias : Parser Token
anchorOrAlias =
    backtrackable
        (succeed ()
            |. chompIf (\c -> c == '&' || c == '*')
            |. chompIfThenWhile (\c -> Char.isAlphaNum c || c == '_' || c == '-')
            |> getChompedString
            |> map (\b -> ( T.C Anchor, b ))
        )


tag : Parser Token
tag =
    backtrackable
        (succeed ()
            |. symbol "!"
            |. chompIfThenWhile (\c -> not (isSpace c) && not (isLineBreak c))
            |> getChompedString
            |> map (\b -> ( T.C Tag, b ))
        )


{-| `|`, `>`, with optional chomping indicator and explicit indentation.
-}
blockScalarIndicator : Parser Token
blockScalarIndicator =
    backtrackable
        (succeed (\b -> ( T.C Operator, b ))
            |= getChompedString
                (succeed ()
                    |. chompIf (\c -> c == '|' || c == '>')
                    |. chompWhile (\c -> c == '-' || c == '+' || Char.isDigit c)
                )
            |. followedByBreak
        )


tilde : Parser Token
tilde =
    chompIf (\c -> c == '~')
        |> getChompedString
        |> map (\b -> ( T.C LiteralKeyword, b ))


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
    chompIfThenWhile (\c -> Char.isAlphaNum c || c == '_')
        |> getChompedString
        |> map
            (\b ->
                if Set.member (String.toLower b) literalKeywordSet then
                    ( T.C LiteralKeyword, b )

                else
                    ( T.Normal, b )
            )


literalKeywordSet : Set.Set String
literalKeywordSet =
    Set.fromList [ "true", "false", "null", "yes", "no", "on", "off", "~" ]



-- Strings


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ doubleQuoteString
        , singleQuoteString
        ]


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, stringEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


singleQuoteString : Parser (List Token)
singleQuoteString =
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
            ( Style1, "yaml-n" )

        String ->
            ( Style2, "yaml-s" )

        Escapable ->
            ( Style1, "yaml-e" )

        Key ->
            ( Style5, "yaml-k" )

        Operator ->
            ( Style3, "yaml-o" )

        LiteralKeyword ->
            ( Style6, "yaml-lk" )

        Anchor ->
            ( Style7, "yaml-a" )

        Tag ->
            ( Style4, "yaml-t" )

        Group ->
            ( Style4, "yaml-g" )
