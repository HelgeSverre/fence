module SyntaxHighlight.Language.Ruby exposing
    ( Syntax(..)
    , syntaxToStyle
      -- Exposing for tests purpose
    , toLines
    , toRevTokens
    )

{-| A lexer for Ruby.

Regex literals are recognized: a `/` starts one only where an expression can
start (beginning of input, after a keyword, an operator, or after one of
`( [ { , ;`), so `a / b` and `(x + 1) / 2` stay division. A regex never spans a
line break; an unterminated one ends at the end of its line.

Known gaps, acceptable for highlighting ordinary Ruby: heredocs (`<<~SQL`) are
not recognized and their body is highlighted as ordinary code; only the word
array forms `%w %W %i %I` are handled, not the general `%q`/`%Q`/`%r` literals;
operator method names in `def` (`def <=>`) are not styled as the method name;
non-ASCII identifiers fall back to plain text.

-}

import Parser exposing ((|.), (|=), DeadEnd, Parser, Step(..), andThen, backtrackable, chompIf, chompWhile, getChompedString, loop, map, oneOf, problem, succeed, symbol)
import Set exposing (Set)
import SyntaxHighlight.Language.Helpers exposing (chompIfThenWhile, delimited, escapable, isEscapable, isLineBreak, isSpace, isWhitespace, thenChompWhile)
import SyntaxHighlight.Language.Type as T
import SyntaxHighlight.Line exposing (Line)
import SyntaxHighlight.Line.Helpers as Line
import SyntaxHighlight.Style as Style exposing (Required(..))


type alias Token =
    T.Token Syntax


type Syntax
    = Number
    | String
    | Symbol
    | Interpolation
    | Keyword
    | Type
    | Function
    | LiteralKeyword
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
        [ whitespaceOrCommentStep revTokens
        , oneOf
            [ percentArray
            , stringLiteral
            , symbolLiteral
            ]
            |> map (\s -> Loop (s ++ revTokens))
        , if regexAllowed revTokens then
            regexLiteral |> map (\s -> Loop (s ++ revTokens))

          else
            problem "not a regex position"
        , oneOf
            [ variable
            , number_
            , operatorChar
            , groupChar
            ]
            |> map (\s -> Loop (s :: revTokens))
        , identifierStep revTokens
        , chompIfThenWhile (isLineBreak >> not)
            |> getChompedString
            |> map (\str -> Loop (( T.Normal, str ) :: revTokens))
        , succeed (Done revTokens)
        ]



-- Identifiers, constants and `def` declarations


identifierStep : List Token -> Parser (Step (List Token) (List Token))
identifierStep revTokens =
    identifierName
        |> andThen
            (\n ->
                if n == "def" then
                    loop (( T.C Keyword, n ) :: revTokens) defLoop
                        |> map Loop

                else
                    oneOf
                        [ backtrackable (symbol "::")
                            |> map (\_ -> Loop (( T.C Operator, "::" ) :: identifierToken n :: revTokens))

                        -- hash-key shorthand: `name:` (but not `Name::Other`)
                        , backtrackable (symbol ":")
                            |> map (\_ -> Loop (( T.C Symbol, n ++ ":" ) :: revTokens))
                        , succeed (Loop (identifierToken n :: revTokens))
                        ]
            )


{-| After `def`, the method name is a function. A receiver (`def self.run`,
`def Config.load`) is emitted as its own token and the loop continues.
-}
defLoop : List Token -> Parser (Step (List Token) (List Token))
defLoop revTokens =
    oneOf
        [ whitespaceOrCommentStep revTokens
        , methodName
            |> andThen
                (\n ->
                    oneOf
                        [ backtrackable (symbol ".")
                            |> map (\_ -> Loop (( T.C Operator, "." ) :: identifierToken n :: revTokens))
                        , succeed (Done (( T.C Function, n ) :: revTokens))
                        ]
                )
        , succeed (Done revTokens)
        ]


identifierName : Parser String
identifierName =
    succeed ()
        |. chompIf isIdentifierStart
        |. chompWhile isIdentifierNameChar
        -- predicate methods and `defined?`
        |. oneOf [ chompIf (\c -> c == '?'), succeed () ]
        |> getChompedString


{-| Method names may also end in `!` or `=` (`save!`, `name=`).
-}
methodName : Parser String
methodName =
    succeed ()
        |. chompIf isIdentifierStart
        |. chompWhile isIdentifierNameChar
        |. oneOf [ chompIf (\c -> c == '?' || c == '!' || c == '='), succeed () ]
        |> getChompedString


identifierToken : String -> Token
identifierToken name =
    if isLiteralKeyword name then
        ( T.C LiteralKeyword, name )

    else if isKeyword name then
        ( T.C Keyword, name )

    else if isConstant name then
        ( T.C Type, name )

    else
        ( T.Normal, name )


isConstant : String -> Bool
isConstant name =
    case String.uncons name of
        Just ( first, _ ) ->
            Char.isUpper first

        Nothing ->
            False


isIdentifierStart : Char -> Bool
isIdentifierStart c =
    Char.isAlpha c || c == '_'


isIdentifierNameChar : Char -> Bool
isIdentifierNameChar c =
    Char.isAlphaNum c || c == '_'



-- Variables: @ivar, @@cvar, $global


variable : Parser Token
variable =
    succeed ()
        |. oneOf [ symbol "@@", symbol "@", symbol "$" ]
        |. chompWhile isIdentifierNameChar
        |> getChompedString
        |> map (\b -> ( T.C Variable, b ))



-- Numbers: 1_000, 3.14, 1e-9, 0xff, 0b1010, 0o17, 017


number_ : Parser Token
number_ =
    succeed ()
        |. oneOf
            [ backtrackable radixNumber
            , decimalNumber
            ]
        |> getChompedString
        |> map (\b -> ( T.C Number, b ))


radixNumber : Parser ()
radixNumber =
    succeed ()
        |. symbol "0"
        |. oneOf
            [ succeed () |. oneOf [ symbol "x", symbol "X" ] |. chompDigits Char.isHexDigit
            , succeed () |. oneOf [ symbol "b", symbol "B" ] |. chompDigits (\c -> c == '0' || c == '1')
            , succeed () |. oneOf [ symbol "o", symbol "O" ] |. chompDigits Char.isOctDigit
            ]


chompDigits : (Char -> Bool) -> Parser ()
chompDigits isDigitChar =
    succeed ()
        |. chompIf isDigitChar
        |. chompWhile (\c -> isDigitChar c || c == '_')


{-| The fraction needs a digit right after the dot so that `1..5` stays a range
and `1.upto(3)` stays a method call.
-}
decimalNumber : Parser ()
decimalNumber =
    succeed ()
        |. chompDigits Char.isDigit
        |. oneOf
            [ backtrackable (succeed () |. symbol "." |. chompDigits Char.isDigit)
            , succeed ()
            ]
        |. oneOf
            [ backtrackable exponent
            , succeed ()
            ]


exponent : Parser ()
exponent =
    succeed ()
        |. chompIf (\c -> c == 'e' || c == 'E')
        |. oneOf [ chompIf (\c -> c == '+' || c == '-'), succeed () ]
        |. chompDigits Char.isDigit



-- Strings and symbols


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
        , innerParsers = [ lineBreakList, interpolation, rubyEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c || c == '#')
        }


singleQuoteString : Parser (List Token)
singleQuoteString =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , defaultMap = \b -> ( T.C String, b )
        , innerParsers = [ lineBreakList, rubyEscapable ]
        , isNotRelevant = \c -> not (isLineBreak c || isEscapable c)
        }


rubyEscapable : Parser (List Token)
rubyEscapable =
    escapable
        |> getChompedString
        |> map (\b -> [ ( T.C LiteralKeyword, b ) ])


{-| `#{...}` inside a double-quoted string, as one span. Nested braces are not
tracked; the span ends at the first `}` or at the end of the line.
-}
interpolation : Parser (List Token)
interpolation =
    succeed ()
        |. backtrackable (symbol "#{")
        |. chompWhile (\c -> c /= '}' && not (isLineBreak c))
        |. oneOf [ symbol "}", succeed () ]
        |> getChompedString
        |> map (\b -> [ ( T.C Interpolation, b ) ])


{-| `:name`, `:name?`, `:"quoted"`.
-}
symbolLiteral : Parser (List Token)
symbolLiteral =
    succeed identity
        |. backtrackable (symbol ":")
        |= oneOf
            [ doubleQuoteString
            , singleQuoteString
            , methodName |> map (\n -> [ ( T.C Symbol, n ) ])
            ]
        |> map (\toks -> toks ++ [ ( T.C Symbol, ":" ) ])


{-| Word arrays: `%w[a b]`, `%i(a b)`, `%W{...}`, delimited by `[ ( { < | /`.
-}
percentArray : Parser (List Token)
percentArray =
    backtrackable
        (succeed Tuple.pair
            |. symbol "%"
            |= getChompedString (chompIf (\c -> c == 'w' || c == 'W' || c == 'i' || c == 'I'))
            |= getChompedString (chompIf isPercentOpen)
        )
        |> andThen
            (\( letter, open ) ->
                let
                    close =
                        closeFor open
                in
                succeed ()
                    |. chompWhile (\c -> String.fromChar c /= close && not (isLineBreak c))
                    |. oneOf [ symbol close, succeed () ]
                    |> getChompedString
                    |> map (\body -> [ ( T.C String, "%" ++ letter ++ open ++ body ) ])
            )


isPercentOpen : Char -> Bool
isPercentOpen c =
    Set.member c (Set.fromList [ '[', '(', '{', '<', '|', '/' ])


closeFor : String -> String
closeFor open =
    case open of
        "[" ->
            "]"

        "(" ->
            ")"

        "{" ->
            "}"

        "<" ->
            ">"

        _ ->
            open



-- Regex literals


regexLiteral : Parser (List Token)
regexLiteral =
    (succeed ()
        |. symbol "/"
        |. loop () regexStep
        |. chompWhile Char.isLower
    )
        |> getChompedString
        |> map (\b -> [ ( T.C String, b ) ])


regexStep : () -> Parser (Step () ())
regexStep () =
    oneOf
        [ symbol "/" |> map (\_ -> Done ())
        , succeed (Loop ())
            |. backtrackable (symbol "\\")
            |. chompIf (isLineBreak >> not)
        , chompIfThenWhile (\c -> c /= '/' && c /= '\\' && not (isLineBreak c))
            |> map (\_ -> Loop ())

        -- unterminated: stop at the line break or the end of input
        , succeed (Done ())
        ]


{-| A `/` opens a regex only where an expression can start.
-}
regexAllowed : List Token -> Bool
regexAllowed revTokens =
    case dropIgnorable revTokens of
        [] ->
            True

        ( T.Comment, _ ) :: _ ->
            True

        ( T.C Keyword, _ ) :: _ ->
            True

        ( T.C Operator, _ ) :: _ ->
            True

        ( T.Normal, s ) :: _ ->
            Set.member (String.right 1 s) (Set.fromList [ "(", "[", "{", ",", ";" ])

        _ ->
            False


dropIgnorable : List Token -> List Token
dropIgnorable tokens =
    case tokens of
        ( T.LineBreak, _ ) :: rest ->
            dropIgnorable rest

        ( T.Normal, s ) :: rest ->
            if s /= "" && String.all isWhitespace s then
                dropIgnorable rest

            else
                tokens

        _ ->
            tokens



-- Comments


comment : Parser (List Token)
comment =
    oneOf
        [ blockComment
        , inlineComment
        ]


inlineComment : Parser (List Token)
inlineComment =
    symbol "#"
        |> thenChompWhile (not << isLineBreak)
        |> getChompedString
        |> map (\b -> [ ( T.Comment, b ) ])


blockComment : Parser (List Token)
blockComment =
    delimited
        { start = "=begin"
        , end = "=end"
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


isKeyword : String -> Bool
isKeyword name =
    Set.member name keywordSet


keywordSet : Set String
keywordSet =
    Set.fromList
        [ "def"
        , "end"
        , "class"
        , "module"
        , "if"
        , "elsif"
        , "else"
        , "unless"
        , "case"
        , "when"
        , "then"
        , "while"
        , "until"
        , "for"
        , "do"
        , "break"
        , "next"
        , "redo"
        , "retry"
        , "return"
        , "yield"
        , "begin"
        , "rescue"
        , "ensure"
        , "raise"
        , "require"
        , "require_relative"
        , "include"
        , "extend"
        , "attr_accessor"
        , "attr_reader"
        , "attr_writer"
        , "lambda"
        , "proc"
        , "new"
        , "self"
        , "super"
        , "alias"
        , "defined?"
        , "not"
        , "and"
        , "or"
        , "in"
        ]


isLiteralKeyword : String -> Bool
isLiteralKeyword name =
    Set.member name literalKeywordSet


literalKeywordSet : Set String
literalKeywordSet =
    Set.fromList [ "true", "false", "nil", "__FILE__", "__LINE__" ]



-- Styling


syntaxToStyle : Syntax -> ( Style.Required, String )
syntaxToStyle syntax =
    case syntax of
        Number ->
            ( Style1, "rb-n" )

        String ->
            ( Style2, "rb-s" )

        Symbol ->
            ( Style2, "rb-sym" )

        Keyword ->
            ( Style3, "rb-k" )

        Operator ->
            ( Style3, "rb-o" )

        Type ->
            ( Style4, "rb-t" )

        Function ->
            ( Style5, "rb-f" )

        LiteralKeyword ->
            ( Style6, "rb-lk" )

        Variable ->
            ( Style7, "rb-v" )

        Interpolation ->
            ( Style7, "rb-i" )
