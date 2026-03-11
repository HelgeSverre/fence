module Frontmatter exposing (extract)

import Yaml


extract : String -> { frontmatter : Maybe Yaml.Value, body : String }
extract input =
    if String.startsWith "---\n" input || String.startsWith "---\u{000D}\n" input then
        let
            afterOpening =
                if String.startsWith "---\u{000D}\n" input then
                    String.dropLeft 5 input

                else
                    String.dropLeft 4 input

            closingIndex =
                findClosing afterOpening
        in
        case closingIndex of
            Just idx ->
                let
                    yamlBlock =
                        String.left idx afterOpening

                    rest =
                        String.dropLeft idx afterOpening
                            |> dropClosingLine

                    parsed =
                        Yaml.parse yamlBlock
                in
                case parsed of
                    Ok value ->
                        { frontmatter = Just value, body = rest }

                    Err _ ->
                        { frontmatter = Nothing, body = input }

            Nothing ->
                { frontmatter = Nothing, body = input }

    else
        { frontmatter = Nothing, body = input }


findClosing : String -> Maybe Int
findClosing content =
    findClosingHelper (String.lines content) 0 0


findClosingHelper : List String -> Int -> Int -> Maybe Int
findClosingHelper lines lineIndex charOffset =
    case lines of
        [] ->
            Nothing

        line :: rest ->
            let
                trimmed =
                    String.trimRight line
            in
            if trimmed == "---" || trimmed == "..." then
                Just charOffset

            else
                findClosingHelper rest (lineIndex + 1) (charOffset + String.length line + 1)


dropClosingLine : String -> String
dropClosingLine s =
    case String.lines s of
        [] ->
            s

        _ :: rest ->
            String.join "\n" rest
