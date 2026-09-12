module SyntaxHighlight.Language.Bash exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A lexer for shell scripts (bash/sh/zsh).

Covers `#` comments (the `#!` shebang is just a comment), single-quoted
strings (literal, no escapes, per shell semantics), double-quoted strings
with `\` escapes and `$var` / `${...}` / `$(...)` interpolation highlighted
as variables, backtick command substitution, variables and the special
parameters (`$1`, `$@`, `$?`, `$#`), keywords, common builtins, numbers and
operators/redirections.

Known gaps, acceptable for highlighting real-world scripts:

  - Heredocs (`<<EOF ... EOF`) are not tracked. The body is lexed as ordinary
    shell code, so it may pick up stray keyword/variable colouring. Doing it
    properly needs the delimiter carried through parser state, which is more
    machinery than the payoff justifies here.
  - The contents of `${...}`, `$(...)` and backticks are one span, not
    recursively lexed.
  - `#` directly after a word character is literal text (correct for
    `foo#bar`), but `#` after any other character starts a comment.

-}

import Parser exposing ((|.), DeadEnd, Parser, Step(..), backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (Delimiter, chompIfThenWhile, delimited, isLineBreak, isSpace, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Keyword
    | Builtin
    | LiteralKeyword
    | Variable
    | Escape
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
            [ operatorChar
            , groupChar
            , number_
            ]
            |> map (\s -> Loop (s :: revTokens))
        , word
            |> getChompedString
            |> map (\n -> Loop (identifierToken n :: revTokens))

        -- Anything else (`/`, `.`, `,`, ...) is plain text. One char at a
        -- time: paths and globs mix these with words constantly.
        , chompIf (isLineBreak >> not)
            |> getChompedString
            |> map (\s -> Loop (( T.Normal, s ) :: revTokens))
        , succeed (Done revTokens)
        ]


identifierToken : String -> Token
identifierToken name =
    if isLiteralKeyword name then
        ( T.C LiteralKeyword, name )

    else if isKeyword name then
        ( T.C Keyword, name )

    else if isBuiltin name then
        ( T.C Builtin, name )

    else
        ( T.Normal, name )


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



-- Comments


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
        [ singleQuoteString
        , doubleQuoteString
        ]


{-| Single quotes are literal in the shell: no escapes, no interpolation.
-}
singleQuoteString : Parser (List Token)
singleQuoteString =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = isLineBreak >> not
        }


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ escapeSequence, variable, lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c || c == '\\' || c == '$' || c == '`')
        }


escapeSequence : Parser (List Token)
escapeSequence =
    succeed ()
        |. backtrackable (symbol "\\")
        |. chompIf (always True)
        |> getChompedString
        |> map (\b -> [ ( T.C Escape, b ) ])



-- Variables and substitutions


variable : Parser (List Token)
variable =
    oneOf
        [ braceVariable
        , commandSubstitution
        , backtickSubstitution
        , simpleVariable
        ]


braceVariable : Parser (List Token)
braceVariable =
    delimited
        { start = "${"
        , end = "}"
        , isNestable = False
        , defaultMap = \b -> ( T.C Variable, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = isLineBreak >> not
        }


commandSubstitution : Parser (List Token)
commandSubstitution =
    delimited
        { start = "$("
        , end = ")"
        , isNestable = True
        , defaultMap = \b -> ( T.C Variable, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = isLineBreak >> not
        }


backtickSubstitution : Parser (List Token)
backtickSubstitution =
    delimited
        { start = "`"
        , end = "`"
        , isNestable = False
        , defaultMap = \b -> ( T.C Variable, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = isLineBreak >> not
        }


{-| `$FOO`, `$1` and the special parameters. A bare `$` is not a variable and
backtracks out, leaving the `$` to be lexed as plain text.
-}
simpleVariable : Parser (List Token)
simpleVariable =
    succeed ()
        |. backtrackable (symbol "$")
        |. oneOf
            [ chompIfThenWhile isIdentifierNameChar
            , chompIf isSpecialParamChar
            ]
        |> getChompedString
        |> map (\b -> [ ( T.C Variable, b ) ])


isSpecialParamChar : Char -> Bool
isSpecialParamChar c =
    Set.member c specialParamSet


specialParamSet : Set Char
specialParamSet =
    Set.fromList [ '@', '*', '#', '?', '-', '$', '!' ]



-- Numbers: plain digit runs. No leading `.`, which is the `source` builtin
-- and a path component far more often than it is a number.


number_ : Parser Token
number_ =
    succeed ()
        |. chompIf Char.isDigit
        |. chompWhile (\c -> Char.isDigit c || c == '.')
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))



-- Operators and redirections


operatorChar : Parser Token
operatorChar =
    chompIf isOperator
        |> getChompedString
        |> map (\s -> ( T.C Operator, s ))


isOperator : Char -> Bool
isOperator c =
    Set.member c operatorSet


operatorSet : Set Char
operatorSet =
    Set.fromList [ '|', '&', ';', '<', '>', '=', '!', '+', '-', '*', '%', '~' ]


groupChar : Parser Token
groupChar =
    chompIf isGroupChar
        |> getChompedString
        |> map (\s -> ( T.Normal, s ))


isGroupChar : Char -> Bool
isGroupChar c =
    Set.member c groupCharSet


groupCharSet : Set Char
groupCharSet =
    Set.fromList [ '(', ')', '[', ']', '{', '}' ]


lineBreakList : Parser (List Token)
lineBreakList =
    symbol "\n"
        |> map (\_ -> [ ( T.LineBreak, "\n" ) ])



-- Reserved words


isKeyword : String -> Bool
isKeyword name =
    Set.member name keywords


keywords : Set String
keywords =
    Set.fromList
        [ "if"
        , "then"
        , "elif"
        , "else"
        , "fi"
        , "for"
        , "while"
        , "until"
        , "do"
        , "done"
        , "case"
        , "esac"
        , "function"
        , "in"
        , "select"
        , "time"
        , "coproc"
        ]


isBuiltin : String -> Bool
isBuiltin name =
    Set.member name builtins


builtins : Set String
builtins =
    Set.fromList
        [ "echo"
        , "cd"
        , "export"
        , "local"
        , "return"
        , "exit"
        , "source"
        , "set"
        , "unset"
        , "read"
        , "shift"
        , "trap"
        , "eval"
        , "exec"
        , "printf"
        , "test"
        ]


isLiteralKeyword : String -> Bool
isLiteralKeyword name =
    Set.member name literalKeywordSet


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList [ "true", "false" ]



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "sh-n" )

        String ->
            ( Style2, "sh-s" )

        Keyword ->
            ( Style3, "sh-k" )

        Builtin ->
            ( Style5, "sh-b" )

        LiteralKeyword ->
            ( Style6, "sh-lk" )

        Variable ->
            ( Style7, "sh-v" )

        Escape ->
            ( Style6, "sh-e" )

        Operator ->
            ( Style3, "sh-o" )
