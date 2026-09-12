module SyntaxHighlight.Language.Php exposing
    ( Syntax(..)
    , syntaxToStyle
    , toLines
    , toRevTokens
    )

import Parser exposing ((|.), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, getChompedString, loop, map, oneOf, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (Delimiter, chompIfThenWhile, delimited, escapable, isEscapable, isLineBreak, isSpace, isWhitespace, thenChompWhile)
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
    | DeclarationKeyword
    | Function
    | LiteralKeyword
    | Variable
    | Operator
    | Param


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
        [ whitespaceOrCommentStep revTokens
        , stringLiteral
            |> map (\s -> Loop (s ++ revTokens))
        , variable
            |> map (\s -> Loop (s :: revTokens))
        , oneOf
            [ operatorChar
            , groupChar
            , number
            ]
            |> map (\s -> Loop (s :: revTokens))
        , chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> andThen (keywordParser revTokens)
            |> map Loop
        , chompIfThenWhile (isLineBreak >> not)
            |> getChompedString
            |> andThen (\str -> succeed (( T.Normal, str ) :: revTokens))
            |> map Loop
        , succeed (Done revTokens)
        ]


keywordParser : List Token -> String -> Parser (List Token)
keywordParser revTokens n =
    if n == "function" then
        loop (( T.C DeclarationKeyword, n ) :: revTokens) functionDeclarationLoop

    else if n == "class" || n == "trait" || n == "interface" || n == "enum" then
        loop (( T.C DeclarationKeyword, n ) :: revTokens) classDeclarationLoop

    else if isDeclarationKeyword n then
        succeed (( T.C DeclarationKeyword, n ) :: revTokens)

    else if isKeyword n then
        succeed (( T.C Keyword, n ) :: revTokens)

    else if isLiteralKeyword n then
        succeed (( T.C LiteralKeyword, n ) :: revTokens)

    else
        succeed (( T.Normal, n ) :: revTokens)


functionDeclarationLoop : List Token -> Parser (Step (List Token) (List Token))
functionDeclarationLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> map (\b -> Loop (( T.C Function, b ) :: revTokens))
        , symbol "("
            |> andThen
                (\_ -> loop (( T.Normal, "(" ) :: revTokens) argLoop)
            |> map Loop
        , succeed (Done revTokens)
        ]


classDeclarationLoop : List Token -> Parser (Step (List Token) (List Token))
classDeclarationLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> map (\b -> Loop (( T.C Function, b ) :: revTokens))
        , succeed (Done revTokens)
        ]


argLoop : List Token -> Parser (Step (List Token) (List Token))
argLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , variable
            |> map (\s -> Loop (s :: revTokens))
        , chompIfThenWhile (\c -> not (isCommentChar c || isWhitespace c || c == ',' || c == ')' || c == '$'))
            |> getChompedString
            |> map (\b -> Loop (( T.C Param, b ) :: revTokens))
        , chompIfThenWhile (\c -> c == '/' || c == ',')
            |> getChompedString
            |> map (\b -> Loop (( T.Normal, b ) :: revTokens))
        , succeed (Done revTokens)
        ]


variable : Parser Token
variable =
    succeed ()
        |. chompIf (\c -> c == '$')
        |. Parser.chompWhile isIdentifierNameChar
        |> getChompedString
        |> map (\b -> ( T.C Variable, b ))


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_' || Char.toCode c > 127



-- Numbers


number : Parser Token
number =
    oneOf
        [ hexNumber
        , binaryNumber
        , octalNumber
        , SyntaxHighlight.Language.Helpers.number
        ]
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))


hexNumber : Parser ()
hexNumber =
    succeed ()
        |. backtrackable (symbol "0x")
        |. chompIfThenWhile Char.isHexDigit


binaryNumber : Parser ()
binaryNumber =
    succeed ()
        |. backtrackable (symbol "0b")
        |. chompIfThenWhile (\c -> c == '0' || c == '1')


octalNumber : Parser ()
octalNumber =
    succeed ()
        |. backtrackable (symbol "0o")
        |. chompIfThenWhile (\c -> Char.toCode c >= 48 && Char.toCode c <= 55)



-- Reserved Words


isKeyword : String -> Bool
isKeyword str =
    Set.member str keywords


keywords : Set String
keywords =
    Set.fromList
        [ "if"
        , "else"
        , "elseif"
        , "while"
        , "for"
        , "foreach"
        , "do"
        , "switch"
        , "case"
        , "break"
        , "continue"
        , "return"
        , "match"
        , "throw"
        , "try"
        , "catch"
        , "finally"
        , "yield"
        , "as"
        , "instanceof"
        , "new"
        , "echo"
        , "print"
        , "include"
        , "require"
        , "include_once"
        , "require_once"
        , "namespace"
        , "use"
        , "extends"
        , "implements"
        , "abstract"
        , "final"
        , "default"
        , "array"
        , "string"
        , "int"
        , "float"
        , "bool"
        , "void"
        , "mixed"
        , "object"
        , "callable"
        , "iterable"
        , "self"
        , "parent"
        , "null"
        ]


isDeclarationKeyword : String -> Bool
isDeclarationKeyword str =
    Set.member str declarationKeywords


declarationKeywords : Set String
declarationKeywords =
    Set.fromList
        [ "function"
        , "class"
        , "trait"
        , "interface"
        , "enum"
        , "const"
        , "var"
        , "public"
        , "private"
        , "protected"
        , "static"
        , "readonly"
        ]


isLiteralKeyword : String -> Bool
isLiteralKeyword str =
    Set.member str literalKeywordSet


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList
        [ "true"
        , "false"
        , "null"
        , "TRUE"
        , "FALSE"
        , "NULL"
        ]


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
    Set.fromList [ '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '=', '!', ':', '.', '?', '@', '~' ]


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



-- String literal


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ singleQuoteString
        , doubleQuoteString
        ]


singleQuoteString : Parser (List Token)
singleQuoteString =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ phpEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, phpEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }



-- Comments


comment : Parser (List Token)
comment =
    oneOf
        [ inlineComment
        , hashComment
        , multilineComment
        ]


inlineComment : Parser (List Token)
inlineComment =
    symbol "//"
        |> thenChompWhile (not << isLineBreak)
        |> getChompedString
        |> map (\b -> [ ( T.Comment, b ) ])


hashComment : Parser (List Token)
hashComment =
    symbol "#"
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


isCommentChar : Char -> Bool
isCommentChar c =
    c == '/' || c == '#'



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


phpEscapable : Parser (List Token)
phpEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C LiteralKeyword, b ) ])


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "php-n" )

        String ->
            ( Style2, "php-s" )

        Keyword ->
            ( Style3, "php-k" )

        DeclarationKeyword ->
            ( Style4, "php-dk" )

        Function ->
            ( Style5, "php-f" )

        LiteralKeyword ->
            ( Style6, "php-lk" )

        Variable ->
            ( Style7, "php-v" )

        Operator ->
            ( Style3, "php-o" )

        Param ->
            ( Style7, "php-p" )
