module SyntaxHighlight.Language.Dart exposing
    ( Syntax(..)
    , syntaxToStyle
    , toLines
    , toRevTokens
    )

import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, getChompedString, loop, map, oneOf, succeed, symbol)
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
    | Type
    | Function
    | LiteralKeyword
    | Operator
    | Param
    | Annotation


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
        , annotation
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
    if n == "class" || n == "abstract" || n == "mixin" || n == "extension" then
        loop (( T.C DeclarationKeyword, n ) :: revTokens) classDeclarationLoop

    else if isDeclarationKeyword n then
        succeed (( T.C DeclarationKeyword, n ) :: revTokens)

    else if isType n then
        succeed (( T.C Type, n ) :: revTokens)

    else if isKeyword n then
        succeed (( T.C Keyword, n ) :: revTokens)

    else if isLiteralKeyword n then
        succeed (( T.C LiteralKeyword, n ) :: revTokens)

    else
        loop [] (functionEvalLoop n revTokens)


functionEvalLoop : String -> List Token -> List Token -> Parser (Step (List Token) (List Token))
functionEvalLoop identifier revTokens thisRevToken =
    oneOf
        [ whitespaceOrCommentStep thisRevToken
        , symbol "("
            |> map
                (\_ -> Done ((( T.Normal, "(" ) :: thisRevToken) ++ (( T.C Function, identifier ) :: revTokens)))
        , thisRevToken
            ++ (( T.Normal, identifier ) :: revTokens)
            |> Done
            |> succeed
        ]


classDeclarationLoop : List Token -> Parser (Step (List Token) (List Token))
classDeclarationLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , chompIfThenWhile isIdentifierNameChar
            |> getChompedString
            |> andThen
                (\n ->
                    if n == "extends" || n == "implements" || n == "with" || n == "on" then
                        succeed (Loop (( T.C Keyword, n ) :: revTokens))

                    else
                        succeed (Loop (( T.C Type, n ) :: revTokens))
                )
        , succeed (Done revTokens)
        ]


annotation : Parser Token
annotation =
    succeed ()
        |. chompIf (\c -> c == '@')
        |. Parser.chompWhile isIdentifierNameChar
        |> getChompedString
        |> map (\b -> ( T.C Annotation, b ))


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_'



-- Numbers


number : Parser Token
number =
    oneOf
        [ hexNumber
        , SyntaxHighlight.Language.Helpers.number
        ]
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))


hexNumber : Parser ()
hexNumber =
    succeed ()
        |. backtrackable (symbol "0x")
        |. chompIfThenWhile Char.isHexDigit



-- Reserved Words


isKeyword : String -> Bool
isKeyword str =
    Set.member str keywords


keywords : Set String
keywords =
    Set.fromList
        [ "if"
        , "else"
        , "for"
        , "while"
        , "do"
        , "switch"
        , "case"
        , "break"
        , "continue"
        , "return"
        , "throw"
        , "try"
        , "catch"
        , "finally"
        , "assert"
        , "in"
        , "is"
        , "as"
        , "new"
        , "rethrow"
        , "with"
        , "on"
        , "show"
        , "hide"
        , "deferred"
        , "export"
        , "part"
        , "library"
        , "import"
        , "extends"
        , "implements"
        , "default"
        , "await"
        , "async"
        , "yield"
        , "get"
        , "set"
        , "operator"
        , "factory"
        , "required"
        ]


isDeclarationKeyword : String -> Bool
isDeclarationKeyword str =
    Set.member str declarationKeywords


declarationKeywords : Set String
declarationKeywords =
    Set.fromList
        [ "class"
        , "abstract"
        , "mixin"
        , "extension"
        , "enum"
        , "typedef"
        , "var"
        , "final"
        , "const"
        , "late"
        , "static"
        , "void"
        , "sync"
        ]


isType : String -> Bool
isType str =
    Set.member str types


types : Set String
types =
    Set.fromList
        [ "int"
        , "double"
        , "num"
        , "String"
        , "bool"
        , "List"
        , "Map"
        , "Set"
        , "Future"
        , "Stream"
        , "Iterable"
        , "dynamic"
        , "Object"
        , "Function"
        , "Null"
        , "Never"
        , "Type"
        , "void"
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
        , "this"
        , "super"
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
    Set.fromList [ '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '=', '!', ':', '.', '?', '~' ]


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
        , innerParsers = [ lineBreakList, dartEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, dartEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }



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
        , isNestable = True
        , defaultMap = \b -> ( T.Comment, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c)
        }


isCommentChar : Char -> Bool
isCommentChar c =
    c == '/'



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


dartEscapable : Parser (List Token)
dartEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C LiteralKeyword, b ) ])


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "dart-n" )

        String ->
            ( Style2, "dart-s" )

        Keyword ->
            ( Style3, "dart-k" )

        DeclarationKeyword ->
            ( Style3, "dart-dk" )

        Type ->
            ( Style4, "dart-t" )

        Function ->
            ( Style5, "dart-f" )

        LiteralKeyword ->
            ( Style6, "dart-lk" )

        Operator ->
            ( Style3, "dart-o" )

        Param ->
            ( Style7, "dart-p" )

        Annotation ->
            ( Style5, "dart-a" )
