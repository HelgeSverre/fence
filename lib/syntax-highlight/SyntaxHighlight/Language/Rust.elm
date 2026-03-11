module SyntaxHighlight.Language.Rust exposing
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
    | Macro
    | Lifetime


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
        , lifetime
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
    if n == "fn" then
        loop (( T.C DeclarationKeyword, n ) :: revTokens) functionDeclarationLoop

    else if isDeclarationKeyword n then
        succeed (( T.C DeclarationKeyword, n ) :: revTokens)

    else if isType n then
        succeed (( T.C Type, n ) :: revTokens)

    else if isKeyword n then
        succeed (( T.C Keyword, n ) :: revTokens)

    else if isLiteralKeyword n then
        succeed (( T.C LiteralKeyword, n ) :: revTokens)

    else if String.endsWith "!" n then
        succeed (( T.C Macro, n ) :: revTokens)

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


argLoop : List Token -> Parser (Step (List Token) (List Token))
argLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , chompIfThenWhile (\c -> not (isCommentChar c || isWhitespace c || c == ',' || c == ')'))
            |> getChompedString
            |> andThen (argParser revTokens)
            |> map Loop
        , chompIfThenWhile (\c -> c == '/' || c == ',')
            |> getChompedString
            |> map (\b -> Loop (( T.Normal, b ) :: revTokens))
        , succeed (Done revTokens)
        ]


argParser : List Token -> String -> Parser (List Token)
argParser revTokens n =
    if isType n then
        succeed (( T.C Type, n ) :: revTokens)

    else
        succeed (( T.C Param, n ) :: revTokens)


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_' || c == '!'



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



-- Lifetime


lifetime : Parser Token
lifetime =
    succeed ()
        |. backtrackable (symbol "'")
        |. chompIfThenWhile (\c -> Char.isAlphaNum c || c == '_')
        |> getChompedString
        |> map (\b -> ( T.C Lifetime, b ))



-- Reserved Words


isKeyword : String -> Bool
isKeyword str =
    Set.member str keywords


keywords : Set String
keywords =
    Set.fromList
        [ "as"
        , "async"
        , "await"
        , "break"
        , "continue"
        , "crate"
        , "dyn"
        , "else"
        , "extern"
        , "for"
        , "if"
        , "in"
        , "let"
        , "loop"
        , "match"
        , "mod"
        , "move"
        , "mut"
        , "pub"
        , "ref"
        , "return"
        , "self"
        , "super"
        , "unsafe"
        , "use"
        , "where"
        , "while"
        , "yield"
        ]


isDeclarationKeyword : String -> Bool
isDeclarationKeyword str =
    Set.member str declarationKeywords


declarationKeywords : Set String
declarationKeywords =
    Set.fromList
        [ "const"
        , "enum"
        , "fn"
        , "impl"
        , "static"
        , "struct"
        , "trait"
        , "type"
        ]


isType : String -> Bool
isType str =
    Set.member str types || (not (String.isEmpty str) && Char.isUpper (Maybe.withDefault ' ' (List.head (String.toList str))))


types : Set String
types =
    Set.fromList
        [ "bool"
        , "char"
        , "f32"
        , "f64"
        , "i8"
        , "i16"
        , "i32"
        , "i64"
        , "i128"
        , "isize"
        , "str"
        , "u8"
        , "u16"
        , "u32"
        , "u64"
        , "u128"
        , "usize"
        ]


isLiteralKeyword : String -> Bool
isLiteralKeyword str =
    Set.member str literalKeywordSet


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList
        [ "true"
        , "false"
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
    Set.fromList [ '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '=', '!', ':', '.', '@', '#', '?' ]


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
        [ doubleQuoteString
        , charLiteral
        ]


charLiteral : Parser (List Token)
charLiteral =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ rsEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, rsEscapable ]
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


rsEscapable : Parser (List Token)
rsEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C LiteralKeyword, b ) ])


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "rs-n" )

        String ->
            ( Style2, "rs-s" )

        Keyword ->
            ( Style3, "rs-k" )

        DeclarationKeyword ->
            ( Style3, "rs-dk" )

        Type ->
            ( Style4, "rs-t" )

        Function ->
            ( Style5, "rs-f" )

        LiteralKeyword ->
            ( Style6, "rs-lk" )

        Operator ->
            ( Style3, "rs-o" )

        Param ->
            ( Style7, "rs-p" )

        Macro ->
            ( Style5, "rs-m" )

        Lifetime ->
            ( Style7, "rs-lt" )
