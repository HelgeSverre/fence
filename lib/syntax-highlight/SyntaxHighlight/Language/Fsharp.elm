module SyntaxHighlight.Language.Fsharp exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for test purposes
    , toLines
    , toRevTokens
    )

import Char
import Parser exposing ((|.), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, succeed, symbol)
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
    | Operator
    | Function
    | TypeName
    | Literal


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
        [ space
            |> map (\n -> Loop (n :: revTokens))
        , lineBreak
            |> map (\n -> Loop (n :: revTokens))
        , comment
            -- before operator/punctuation so `(*` and `//` win over `(` and `/`
            |> map (\n -> Loop (n ++ revTokens))
        , stringLiteral
            |> map (\n -> Loop (n ++ revTokens))
        , charOrTypeVar
            -- disambiguates char literals `'c'` from generic type variables `'T`
            |> map (\n -> Loop (n :: revTokens))
        , punctuation
            -- before number so a lone `.` (member access) isn't read as a number
            |> map (\n -> Loop (n :: revTokens))
        , number
            |> map (\n -> Loop (n :: revTokens))
        , operator
            |> map (\n -> Loop (n :: revTokens))
        , chompIfThenWhile isIdentifierChar
            |> getChompedString
            |> andThen (classify revTokens)
            |> map Loop
        , succeed (Done revTokens)
        ]



-- Identifiers / keyword classification


isIdentifierChar : Char -> Bool
isIdentifierChar c =
    not
        (isWhitespace c
            || isOperatorChar c
            || isPunctuationChar c
            || c == '"'
        )


classify : List Token -> String -> Parser (List Token)
classify revTokens s =
    let
        token =
            if isKeyword s then
                ( T.C Keyword, s )

            else if isLiteral s then
                ( T.C Literal, s )

            else if precededByDecl revTokens && startsLower s then
                ( T.C Function, s )

            else if startsUpper s then
                ( T.C TypeName, s )

            else
                -- local value / parameter names fall back to plain text
                ( T.Normal, s )
    in
    succeed (token :: revTokens)


startsUpper : String -> Bool
startsUpper s =
    String.uncons s
        |> Maybe.map (Tuple.first >> Char.isUpper)
        |> Maybe.withDefault False


startsLower : String -> Bool
startsLower s =
    String.uncons s
        |> Maybe.map (Tuple.first >> (\c -> Char.isLower c || c == '_'))
        |> Maybe.withDefault False


{-| True when the most recent significant token is a declaration keyword,
so the identifier being read is a binding name (function/value). Mirrors the
lightweight heuristic in `Elm.lineStartVariable`.
-}
precededByDecl : List Token -> Bool
precededByDecl revTokens =
    case dropBlank revTokens of
        ( T.C Keyword, kw ) :: _ ->
            Set.member kw declStarterSet

        _ ->
            False


dropBlank : List Token -> List Token
dropBlank tokens =
    case tokens of
        (( _, str ) as token) :: rest ->
            if String.trim str == "" then
                dropBlank rest

            else
                token :: rest

        [] ->
            []


declStarterSet : Set String
declStarterSet =
    Set.fromList
        [ "let", "member", "and", "use", "override", "abstract", "inline", "rec", "mutable", "static", "val", "new", "default" ]


isKeyword : String -> Bool
isKeyword s =
    Set.member s keywordSet


keywordSet : Set String
keywordSet =
    Set.fromList
        [ "let", "in", "and", "rec", "mutable", "if", "then", "else", "elif", "match", "with", "when", "function", "fun", "for", "to", "downto", "while", "do", "done", "yield", "return", "use", "try", "finally", "begin", "end", "module", "namespace", "open", "type", "member", "abstract", "override", "default", "interface", "inherit", "static", "new", "val", "class", "struct", "exception", "of", "as", "lazy", "assert", "upcast", "downcast", "base", "internal", "public", "private", "inline", "extern", "void", "delegate", "global", "enum", "not", "or", "params", "sig" ]


isLiteral : String -> Bool
isLiteral s =
    Set.member s literalSet


literalSet : Set String
literalSet =
    Set.fromList [ "true", "false", "null", "unit" ]



-- Operators / punctuation


operator : Parser Token
operator =
    chompIfThenWhile isOperatorChar
        |> getChompedString
        |> map (\b -> ( T.C Operator, b ))


isOperatorChar : Char -> Bool
isOperatorChar c =
    Set.member c operatorCharSet


operatorCharSet : Set Char
operatorCharSet =
    Set.fromList
        [ '|', '<', '>', '-', '=', '+', '*', '/', '%', '&', '^', '!', '?', ':', '@', '~' ]


punctuation : Parser Token
punctuation =
    chompIfThenWhile isPunctuationChar
        |> getChompedString
        |> map (\b -> ( T.Normal, b ))


isPunctuationChar : Char -> Bool
isPunctuationChar c =
    Set.member c punctuationCharSet


punctuationCharSet : Set Char
punctuationCharSet =
    Set.fromList [ '(', ')', '{', '}', '[', ']', ',', ';', '.', '`' ]



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



-- Char literals vs generic type variables


charOrTypeVar : Parser Token
charOrTypeVar =
    oneOf
        [ backtrackable charLiteral
        , typeVar
        ]


charLiteral : Parser Token
charLiteral =
    (getChompedString <|
        succeed ()
            |. symbol "'"
            |. oneOf
                [ backtrackable (symbol "\\" |. chompIf (always True))
                , chompIf (\c -> c /= '\'' && not (isLineBreak c))
                ]
            |. symbol "'"
    )
        |> map (\b -> ( T.C String, b ))


typeVar : Parser Token
typeVar =
    (getChompedString <|
        succeed ()
            |. symbol "'"
            |. chompIf (\c -> Char.isAlpha c || c == '_')
            |. chompWhile (\c -> Char.isAlphaNum c || c == '_')
    )
        |> map (\b -> ( T.C TypeName, b ))



-- Strings


stringLiteral : Parser (List Token)
stringLiteral =
    oneOf
        [ tripleDoubleQuote
        , verbatimString
        , doubleQuote
        ]


stringDelimiter : Delimiter Token
stringDelimiter =
    { start = "\""
    , end = "\""
    , isNestable = False
    , defaultMap = \b -> ( T.C String, b )
    , innerParsers = [ lineBreakList, fsEscapable ]
    , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
    }


doubleQuote : Parser (List Token)
doubleQuote =
    delimited stringDelimiter


tripleDoubleQuote : Parser (List Token)
tripleDoubleQuote =
    delimited
        { stringDelimiter
            | start = "\"\"\""
            , end = "\"\"\""
            , innerParsers = [ lineBreakList ]
            , isNotRelevant = \c -> not (isLineBreak c)
        }


verbatimString : Parser (List Token)
verbatimString =
    delimited
        { stringDelimiter
            | start = "@\""
            , end = "\""
            , innerParsers = [ lineBreakList ]
            , isNotRelevant = \c -> not (isLineBreak c)
        }


fsEscapable : Parser (List Token)
fsEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C Literal, b ) ])



-- Comments


comment : Parser (List Token)
comment =
    oneOf
        [ lineComment
        , blockComment
        ]


lineComment : Parser (List Token)
lineComment =
    symbol "//"
        |> thenChompWhile (not << isLineBreak)
        |> getChompedString
        |> map (\b -> [ ( T.Comment, b ) ])


blockComment : Parser (List Token)
blockComment =
    delimited
        { start = "(*"
        , end = "*)"
        , isNestable = True
        , defaultMap = \b -> ( T.Comment, b )
        , innerParsers = [ lineBreakList ]
        , isNotRelevant = \c -> not (isLineBreak c)
        }



-- Whitespace


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
    symbol "\n"
        |> map (\_ -> [ ( T.LineBreak, "\n" ) ])


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "fs-n" )

        String ->
            ( Style2, "fs-s" )

        Keyword ->
            ( Style3, "fs-k" )

        Operator ->
            ( Style3, "fs-o" )

        Function ->
            ( Style5, "fs-f" )

        TypeName ->
            ( Style6, "fs-t" )

        Literal ->
            ( Style6, "fs-l" )
