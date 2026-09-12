module SyntaxHighlight.Language.Dockerfile exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A lexer for Dockerfiles.

Line-oriented and deliberately shallow: the instruction keyword at the start
of a line (case-insensitive), `AS` in `FROM ... AS name`, `--flag=` options,
`#` comments, quoted strings, `$VAR` / `${VAR}` references, numbers and the
trailing `\` line continuation.

The body of `RUN` is not lexed as shell — a Dockerfile's shell fragments are
usually short and the instruction colouring carries the structure.

-}

import Parser exposing ((|.), DeadEnd, Parser, Step(..), backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (chompIfThenWhile, delimited, isLineBreak, isSpace, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Instruction
    | Keyword
    | Flag
    | Variable
    | Operator


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
        [ chompIfThenWhile isSpace
            |> getChompedString
            |> map (\b -> Loop (( T.Normal, b ) :: revTokens))
        , lineBreakList
            |> map (\ns -> Loop (ns ++ revTokens))
        , comment
            |> map (\ns -> Loop (ns ++ revTokens))
        , stringLiteral
            |> map (\ns -> Loop (ns ++ revTokens))
        , variable
            |> map (\ns -> Loop (ns ++ revTokens))
        , oneOf
            [ flag
            , continuation
            , number_
            ]
            |> map (\s -> Loop (s :: revTokens))
        , word
            |> getChompedString
            |> map (\n -> Loop (identifierToken revTokens n :: revTokens))
        , chompIf (isLineBreak >> not)
            |> getChompedString
            |> map (\s -> Loop (( T.Normal, s ) :: revTokens))
        , succeed (Done revTokens)
        ]


identifierToken : List Token -> String -> Token
identifierToken revTokens name =
    if atLineStart revTokens && isInstruction (String.toUpper name) then
        ( T.C Instruction, name )

    else if String.toUpper name == "AS" then
        ( T.C Keyword, name )

    else
        ( T.Normal, name )


{-| True when only whitespace precedes on the current line.
-}
atLineStart : List Token -> Bool
atLineStart revTokens =
    case revTokens of
        [] ->
            True

        ( T.LineBreak, _ ) :: _ ->
            True

        ( T.Normal, text ) :: rest ->
            String.all isSpace text && atLineStart rest

        _ ->
            False


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_'


{-| A word swallows any `#` that continues it, so `foo#bar` stays one plain
word instead of starting a comment at the `#`.
-}
word : Parser ()
word =
    succeed ()
        |. chompIf isIdentifierNameChar
        |. chompWhile (\c -> isIdentifierNameChar c || c == '#')



-- Comments (and the `# syntax=` parser directive, same shape)


comment : Parser (List Token)
comment =
    symbol "#"
        |> thenChompWhile (isLineBreak >> not)
        |> getChompedString
        |> map (\b -> [ ( T.Comment, b ) ])



-- Strings


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ quoted "\""
        , quoted "'"
        ]


quoted : String -> Parser (List Token)
quoted q =
    delimited
        { start = q
        , end = q
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ escapeSequence, variable, lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c || c == '\\' || c == '$')
        }


escapeSequence : Parser (List Token)
escapeSequence =
    succeed ()
        |. backtrackable (symbol "\\")
        |. chompIf (isLineBreak >> not)
        |> getChompedString
        |> map (\b -> [ ( T.C Operator, b ) ])



-- Variables


variable : Parser (List Token)
variable =
    oneOf
        [ delimited
            { start = "${"
            , end = "}"
            , isNestable = False
            , defaultMap = \b -> ( T.C Variable, b )
            , innerParsers = [ lineBreakList ]
            , isNotRelevant = isLineBreak >> not
            }
        , succeed ()
            |. backtrackable (symbol "$")
            |. chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> map (\b -> [ ( T.C Variable, b ) ])
        ]



-- `--from=builder`, `--chown=x:y`, `--platform=...`


flag : Parser Token
flag =
    succeed ()
        |. backtrackable (symbol "--")
        |. chompIfThenWhile (\c -> isIdentifierNameChar c || c == '-')
        |. chompWhile (\c -> c == '=')
        |> getChompedString
        |> map (\b -> ( T.C Flag, b ))


{-| A lone backslash: line continuation, or an escape outside a string.
-}
continuation : Parser Token
continuation =
    symbol "\\"
        |> getChompedString
        |> map (\b -> ( T.C Operator, b ))


number_ : Parser Token
number_ =
    succeed ()
        |. chompIf Char.isDigit
        |. chompWhile (\c -> Char.isDigit c || c == '.')
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))


lineBreakList : Parser (List Token)
lineBreakList =
    symbol "\n"
        |> map (\_ -> [ ( T.LineBreak, "\n" ) ])



-- Instructions


isInstruction : String -> Bool
isInstruction name =
    Set.member name instructions


instructions : Set String
instructions =
    Set.fromList
        [ "FROM"
        , "RUN"
        , "CMD"
        , "LABEL"
        , "MAINTAINER"
        , "EXPOSE"
        , "ENV"
        , "ADD"
        , "COPY"
        , "ENTRYPOINT"
        , "VOLUME"
        , "USER"
        , "WORKDIR"
        , "ARG"
        , "ONBUILD"
        , "STOPSIGNAL"
        , "HEALTHCHECK"
        , "SHELL"
        ]



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "df-n" )

        String ->
            ( Style2, "df-s" )

        Instruction ->
            ( Style3, "df-i" )

        Keyword ->
            ( Style3, "df-k" )

        Flag ->
            ( Style5, "df-f" )

        Variable ->
            ( Style7, "df-v" )

        Operator ->
            ( Style3, "df-o" )
