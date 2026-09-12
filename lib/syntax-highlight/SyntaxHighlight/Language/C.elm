module SyntaxHighlight.Language.C exposing
    ( Dialect(..)
    , Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A lexer for C and C++. One token stream serves both: `Dialect` only
changes which identifiers count as keywords/types, since the two languages
share punctuation, numbers, strings, comments and preprocessor directives.

Known gaps, acceptable for highlighting real-world headers and sources:
raw string literals (C++11 `R"(...)"`) are not recognized and fall back to
plain identifiers; a preprocessor directive is highlighted as one span from
`#` to the end of its line, without tokenizing macro bodies, arguments or a
line continued with a trailing backslash.
-}

import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (Delimiter, chompIfThenWhile, delimited, escapable, isEscapable, isLineBreak, isSpace, isWhitespace, number, numberExponentialNotation, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type Dialect
    = C
    | Cpp


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Keyword
    | Type
    | LiteralKeyword
    | Preprocessor
    | Operator


toLines : Dialect -> String -> Result (List DeadEnd) (List Line)
toLines dialect =
    Parser.run (toRevTokens dialect)
        >> Result.map (Line.toLines syntaxToStyle)


toRevTokens : Dialect -> Parser (List Token)
toRevTokens dialect =
    loop [] (mainLoop dialect)


mainLoop : Dialect -> List Token -> Parser (Step (List Token) (List Token))
mainLoop dialect revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , preprocessorDirective
            |> map (\s -> Loop (s :: revTokens))
        , stringLiteral
            |> map (\s -> Loop (s ++ revTokens))
        , oneOf
            [ operatorChar
            , groupChar
            , number_
            ]
            |> map (\s -> Loop (s :: revTokens))
        , chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> map (\n -> Loop (identifierToken dialect n :: revTokens))
        , chompIfThenWhile (isLineBreak >> not)
            |> getChompedString
            |> map (\str -> Loop (( T.Normal, str ) :: revTokens))
        , succeed (Done revTokens)
        ]


identifierToken : Dialect -> String -> Token
identifierToken dialect name =
    if isType dialect name then
        ( T.C Type, name )

    else if isLiteralKeyword name then
        ( T.C LiteralKeyword, name )

    else if isKeyword dialect name then
        ( T.C Keyword, name )

    else
        ( T.Normal, name )


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_'



-- Preprocessor: `#include <stdio.h>`, `#define FOO 1`, `#ifdef ...`. Treated
-- as one span to the end of the line; see the module gaps note above.


preprocessorDirective : Parser Token
preprocessorDirective =
    succeed ()
        |. symbol "#"
        |. chompWhile (isLineBreak >> not)
        |> getChompedString
        |> map (\b -> ( T.C Preprocessor, b ))



-- Numbers: decimal/hex/octal/binary integers and floats, with a trailing
-- type suffix (u, U, l, L, f, F, in any combination, e.g. `100ULL`).


number_ : Parser Token
number_ =
    succeed ()
        |. oneOf
            [ backtrackable hexOrBinaryDigits
            , backtrackable numberExponentialNotation
            , number
            ]
        |. chompWhile isNumberSuffixChar
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))


{-| Only the `0x`/`0b` prefixed forms: a bare leading zero (`0`, `0755`,
`0.5`) is an ordinary digit sequence to `Helpers.number`, which already
handles it, decimal point and all.
-}
hexOrBinaryDigits : Parser ()
hexOrBinaryDigits =
    succeed ()
        |. symbol "0"
        |. oneOf
            [ succeed () |. oneOf [ symbol "x", symbol "X" ] |. chompWhile Char.isHexDigit
            , succeed () |. oneOf [ symbol "b", symbol "B" ] |. chompWhile (\c -> c == '0' || c == '1')
            ]


isNumberSuffixChar : Char -> Bool
isNumberSuffixChar c =
    c == 'u' || c == 'U' || c == 'l' || c == 'L' || c == 'f' || c == 'F'



-- String and char literals, with backslash escapes.


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ doubleQuoteString
        , charLiteral
        ]


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ cEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


charLiteral : Parser (List Token)
charLiteral =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ cEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


cEscapable : Parser (List Token)
cEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C LiteralKeyword, b ) ])



-- Comments


comment : Parser (List Token)
comment =
    oneOf
        [ inlineComment
        , multilineComment
        ]


inlineComment : Parser (List Token)
inlineComment =
    symbol "//"
        |> thenChompWhile (not << isLineBreak)
        |> getChompedString
        |> map (\b -> [ ( T.Comment, b ) ])


multilineComment : Parser (List Token)
multilineComment =
    delimited
        { start = "/*"
        , end = "*/"
        , isNestable = False
        , defaultMap = \b -> ( T.Comment, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c)
        }



-- Operators and grouping


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
    Set.fromList [ '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '=', '!', '~', '?', ':', '.' ]


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
    Set.fromList [ '(', ')', '[', ']', '{', '}', ',', ';' ]



-- Helpers


whitespaceOrCommentStep : List Token -> Parser (Step (List Token) (List Token))
whitespaceOrCommentStep revTokens =
    oneOf
        [ chompIfThenWhile isSpace
            |> getChompedString
            |> map (\b -> Loop (( T.Normal, b ) :: revTokens))
        , lineBreakList
            |> map (\ns -> Loop (ns ++ revTokens))
        , comment
            |> map (\ns -> Loop (ns ++ revTokens))
        ]


lineBreakList : Parser (List Token)
lineBreakList =
    symbol "\n"
        |> map (\_ -> [ ( T.LineBreak, "\n" ) ])



-- Reserved words


isKeyword : Dialect -> String -> Bool
isKeyword dialect name =
    Set.member name cKeywords || (dialect == Cpp && Set.member name cppOnlyKeywords)


cKeywords : Set String
cKeywords =
    Set.fromList
        [ "auto"
        , "break"
        , "case"
        , "const"
        , "continue"
        , "default"
        , "do"
        , "else"
        , "enum"
        , "extern"
        , "for"
        , "goto"
        , "if"
        , "inline"
        , "register"
        , "restrict"
        , "return"
        , "sizeof"
        , "static"
        , "struct"
        , "switch"
        , "typedef"
        , "union"
        , "volatile"
        , "while"
        , "_Alignas"
        , "_Alignof"
        , "_Atomic"
        , "_Generic"
        , "_Noreturn"
        , "_Static_assert"
        , "_Thread_local"
        ]


cppOnlyKeywords : Set String
cppOnlyKeywords =
    Set.fromList
        [ "alignas"
        , "alignof"
        , "and"
        , "catch"
        , "class"
        , "constexpr"
        , "const_cast"
        , "decltype"
        , "delete"
        , "dynamic_cast"
        , "explicit"
        , "export"
        , "final"
        , "friend"
        , "mutable"
        , "namespace"
        , "new"
        , "noexcept"
        , "not"
        , "operator"
        , "or"
        , "override"
        , "private"
        , "protected"
        , "public"
        , "reinterpret_cast"
        , "static_assert"
        , "static_cast"
        , "template"
        , "this"
        , "throw"
        , "try"
        , "typeid"
        , "typename"
        , "using"
        , "virtual"
        ]


isType : Dialect -> String -> Bool
isType dialect name =
    Set.member name cTypes || (dialect == Cpp && Set.member name cppOnlyTypes) || String.endsWith "_t" name


cTypes : Set String
cTypes =
    Set.fromList
        [ "void"
        , "char"
        , "short"
        , "int"
        , "long"
        , "float"
        , "double"
        , "signed"
        , "unsigned"
        , "_Bool"
        , "_Complex"
        , "FILE"
        ]


cppOnlyTypes : Set String
cppOnlyTypes =
    Set.fromList [ "bool", "wchar_t" ]


isLiteralKeyword : String -> Bool
isLiteralKeyword name =
    Set.member name literalKeywordSet


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList [ "NULL", "true", "false", "nullptr" ]



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "c-n" )

        String ->
            ( Style2, "c-s" )

        Keyword ->
            ( Style3, "c-k" )

        Type ->
            ( Style4, "c-t" )

        LiteralKeyword ->
            ( Style6, "c-lk" )

        Preprocessor ->
            ( Style3, "c-pp" )

        Operator ->
            ( Style3, "c-o" )
