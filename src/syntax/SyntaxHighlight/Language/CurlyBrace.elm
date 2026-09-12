module SyntaxHighlight.Language.CurlyBrace exposing
    ( Dialect(..)
    , Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A lexer for Java, C#, Swift and Scala. They share a lexical core -- `//`
and `/* */` comments, double-quoted strings with backslash escapes, triple
quoted strings, decimal/hex/binary numbers with type suffixes, the same
operator and grouping characters, and identifier-keyword lookup -- so one
token stream serves all four. `Dialect` picks the keyword/type/literal sets
plus the handful of genuinely per-language lexical forms:

  - Java, Swift, Scala: `@Annotation` is one span.
  - C#: `@"verbatim"` and `$"interpolated"` string prefixes, and a bare
    `[Attribute]` (no arguments) is one span.
  - Swift has no `'c'` character literal, so the single quote stays plain.

Known gaps, acceptable for highlighting real-world source: no semantic
analysis, so user-defined type names and function names are plain; Scala's
`s"..."`/`f"..."` interpolator prefix lexes as a plain identifier followed by
an ordinary string; Swift's `\(expr)` interpolation is styled as string
content; a C# attribute with arguments (`[Obsolete("x")]`) falls back to
brackets plus identifiers.

-}

import Parser exposing ((|.), DeadEnd, Parser, Step(..), backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (Delimiter, chompIfThenWhile, delimited, escapable, isEscapable, isLineBreak, isSpace, number, numberExponentialNotation, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type Dialect
    = Java
    | CSharp
    | Swift
    | Scala


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Keyword
    | Type
    | LiteralKeyword
    | Annotation
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
        , stringLiteral dialect
            |> map (\s -> Loop (s ++ revTokens))
        , annotation dialect
            |> map (\s -> Loop (s :: revTokens))
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
    if Set.member name (types dialect) then
        ( T.C Type, name )

    else if Set.member name (literalKeywords dialect) then
        ( T.C LiteralKeyword, name )

    else if Set.member name (keywords dialect) then
        ( T.C Keyword, name )

    else
        ( T.Normal, name )


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_' || c == '$'



-- Annotations and attributes


annotation : Dialect -> Parser Token
annotation dialect =
    case dialect of
        CSharp ->
            csharpAttribute

        _ ->
            succeed ()
                |. symbol "@"
                |. chompWhile isIdentifierNameChar
                |> getChompedString
                |> map (\b -> ( T.C Annotation, b ))


{-| Only the argument-less form, `[Obsolete]`: anything else backtracks and
lexes as brackets plus identifiers, which keeps `[0]` and `[i]` plain.
-}
csharpAttribute : Parser Token
csharpAttribute =
    succeed ()
        |. backtrackable (symbol "[")
        |. backtrackable (chompIf Char.isUpper)
        |. backtrackable (chompWhile isIdentifierNameChar)
        |. symbol "]"
        |> getChompedString
        |> map (\b -> ( T.C Annotation, b ))



-- Numbers: decimal/hex/binary integers and floats, with a trailing type
-- suffix (L, f, d, u, m, ...) and `_` digit separators.


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


hexOrBinaryDigits : Parser ()
hexOrBinaryDigits =
    succeed ()
        |. symbol "0"
        |. oneOf
            [ succeed () |. oneOf [ symbol "x", symbol "X" ] |. chompWhile (\c -> Char.isHexDigit c || c == '_')
            , succeed () |. oneOf [ symbol "b", symbol "B" ] |. chompWhile (\c -> c == '0' || c == '1' || c == '_')
            ]


{-| Digits and `_` are included so `1_000` stays one number. A trailing run of
letters after a number is not valid in any of these languages, so swallowing
it into the number token costs nothing.
-}
isNumberSuffixChar : Char -> Bool
isNumberSuffixChar c =
    Char.isAlpha c || Char.isDigit c || c == '_'



-- Strings


stringLiteral : Dialect -> Parser (List Token)
stringLiteral dialect =
    oneOf
        (tripleQuoteString
            :: (case dialect of
                    CSharp ->
                        [ prefixedString "@\"", prefixedString "$\"", doubleQuoteString ]

                    Swift ->
                        -- Swift has no character literal; `'` is not a delimiter.
                        [ doubleQuoteString ]

                    _ ->
                        [ doubleQuoteString, charLiteral ]
               )
        )


stringDelimiter : Delimiter Token
stringDelimiter =
    { start = "\""
    , end = "\""
    , isNestable = False
    , defaultMap = \b -> ( T.C String, b )
    , innerParsers = [ lineBreakList, stringEscapable ]
    , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
    }


doubleQuoteString : Parser (List Token)
doubleQuoteString =
    delimited stringDelimiter


tripleQuoteString : Parser (List Token)
tripleQuoteString =
    delimited { stringDelimiter | start = "\"\"\"", end = "\"\"\"" }


prefixedString : String -> Parser (List Token)
prefixedString start =
    delimited { stringDelimiter | start = start }


charLiteral : Parser (List Token)
charLiteral =
    delimited { stringDelimiter | start = "'", end = "'" }


stringEscapable : Parser (List Token)
stringEscapable =
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
    chompIf (\c -> Set.member c operatorSet)
        |> getChompedString
        |> map (\s -> ( T.C Operator, s ))


operatorSet : Set Char
operatorSet =
    Set.fromList [ '+', '-', '*', '/', '%', '&', '|', '^', '<', '>', '=', '!', '~', '?', ':', '.' ]


groupChar : Parser Token
groupChar =
    chompIf (\c -> Set.member c groupCharSet)
        |> getChompedString
        |> map (\s -> ( T.Normal, s ))


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


keywords : Dialect -> Set String
keywords dialect =
    case dialect of
        Java ->
            javaKeywords

        CSharp ->
            csharpKeywords

        Swift ->
            swiftKeywords

        Scala ->
            scalaKeywords


types : Dialect -> Set String
types dialect =
    case dialect of
        Java ->
            javaTypes

        CSharp ->
            csharpTypes

        Swift ->
            swiftTypes

        Scala ->
            scalaTypes


literalKeywords : Dialect -> Set String
literalKeywords dialect =
    case dialect of
        Swift ->
            Set.fromList [ "true", "false", "nil" ]

        _ ->
            Set.fromList [ "true", "false", "null" ]


javaKeywords : Set String
javaKeywords =
    Set.fromList
        [ "abstract", "assert", "break", "case", "catch", "class", "continue"
        , "default", "do", "else", "enum", "extends", "final", "finally", "for"
        , "if", "implements", "import", "instanceof", "interface", "native"
        , "new", "package", "permits", "private", "protected", "public"
        , "record", "return", "sealed", "static", "strictfp", "super"
        , "switch", "synchronized", "this", "throw", "throws", "transient"
        , "try", "var", "volatile", "while", "yield"
        ]


javaTypes : Set String
javaTypes =
    Set.fromList
        [ "boolean", "byte", "char", "double", "float", "int", "long", "short"
        , "void", "Integer", "List", "Map", "Optional", "String"
        ]


csharpKeywords : Set String
csharpKeywords =
    Set.fromList
        [ "abstract", "as", "async", "await", "break", "case", "catch", "class"
        , "const", "continue", "default", "do", "else", "finally", "for"
        , "foreach", "get", "if", "in", "init", "interface", "internal", "is"
        , "lock", "namespace", "nameof", "new", "out", "override", "params"
        , "partial", "private", "protected", "public", "readonly", "record"
        , "ref", "required", "return", "sealed", "set", "static", "struct"
        , "switch", "throw", "try", "typeof", "using", "var", "virtual"
        , "while", "yield"
        ]


csharpTypes : Set String
csharpTypes =
    Set.fromList
        [ "bool", "byte", "char", "decimal", "Dictionary", "double", "dynamic"
        , "float", "int", "List", "long", "object", "sbyte", "short", "string"
        , "Task", "uint", "ulong", "ushort", "void"
        ]


swiftKeywords : Set String
swiftKeywords =
    Set.fromList
        [ "actor", "any", "as", "associatedtype", "async", "await", "case"
        , "catch", "class", "convenience", "default", "defer", "deinit", "do"
        , "else", "enum", "extension", "fileprivate", "final", "for", "func"
        , "guard", "if", "import", "in", "init", "inout", "internal", "is"
        , "lazy", "let", "mutating", "nonmutating", "open", "override"
        , "private", "protocol", "public", "repeat", "required", "rethrows"
        , "return", "some", "static", "struct", "subscript", "switch", "throw"
        , "throws", "try", "typealias", "unowned", "var", "weak", "where"
        , "while"
        ]


swiftTypes : Set String
swiftTypes =
    Set.fromList
        [ "Any", "AnyObject", "Array", "Bool", "Character", "Dictionary"
        , "Double", "Float", "Int", "Optional", "Self", "Set", "String", "Void"
        ]


scalaKeywords : Set String
scalaKeywords =
    Set.fromList
        [ "_", "abstract", "case", "catch", "class", "def", "do", "else"
        , "extends", "final", "finally", "for", "forSome", "given", "if"
        , "implicit", "import", "lazy", "match", "new", "object", "override"
        , "package", "private", "protected", "return", "sealed", "then"
        , "throw", "trait", "try", "type", "using", "val", "var", "while"
        , "with", "yield"
        ]


scalaTypes : Set String
scalaTypes =
    Set.fromList
        [ "Any", "AnyRef", "Boolean", "Double", "Float", "Future", "Int"
        , "List", "Long", "Map", "Nothing", "Option", "Seq", "String", "Unit"
        ]



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "cb-n" )

        String ->
            ( Style2, "cb-s" )

        Keyword ->
            ( Style3, "cb-k" )

        Type ->
            ( Style4, "cb-t" )

        Annotation ->
            ( Style5, "cb-a" )

        LiteralKeyword ->
            ( Style6, "cb-lk" )

        Operator ->
            ( Style3, "cb-o" )
