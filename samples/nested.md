# Nested list stress test

Manual QA fixture for deeply nested lists: how the preview renders them
(indentation, markers, spacing, depth) and how the editor handles a big
document (scrolling, virtualization, soft wrap).

Open this file in Fence and walk the sections top to bottom. Each `##`
section isolates one failure mode, so when something looks wrong you can
name the section rather than the whole file.

| Section | What it tests | Correct rendering looks like |
| --- | --- | --- |
| 1. Depth ladder | Unordered nesting, 1-16 levels | Each level indents one step further; every item's text matches its own depth |
| 2. Ordered depth ladder | `1.` vs `1)`, custom start, alternating types | Numbers continue per list, start values respected, types alternate cleanly |
| 3. Mixed content in deep items | Paragraph, code, quote, table, image inside deep items | Blocks stay aligned under their parent item, not flushed to the left margin |
| 4. Task list nesting | GFM checkboxes several levels deep | Checkboxes render as boxes at every depth, checked state preserved |
| 5. Wide and shallow | 600 flat siblings | One long list, no indentation drift, smooth scrolling |
| 6. Long leaf text | Multi-hundred-word single lines | Text soft-wraps inside the item's indent in the preview; editor scrolls horizontally |
| 7. Ragged / malformed | Bad indentation on purpose | Something reasonable; the point is that it must not crash or blank the preview |
| 8. Bulk | Repetitive varied nesting | Same as the sections above, only a lot of it |

Known-good expectations: bullet markers cycle through a small set and repeat
at greater depths, indentation is uniform per level, and no section should
leave the preview blank or the editor unable to scroll to the end of the file.

## 1. Depth ladder

A single unordered list nested one level at a time. Every item states its own
depth, so the first item whose text and visual indent disagree is the break point.

- level 1
  - level 2
    - level 3
      - level 4
        - level 5
          - level 6
            - level 7
              - level 8
                - level 9
                  - level 10
                    - level 11
                      - level 12
                        - level 13
                          - level 14
                            - level 15
                              - level 16 (deepest)

Same ladder again, with a sibling at every level so marker cycling is visible
side by side:

- level 1 first child
- level 1 second child (sibling at the same depth)
  - level 2 first child
  - level 2 second child (sibling at the same depth)
    - level 3 first child
    - level 3 second child (sibling at the same depth)
      - level 4 first child
      - level 4 second child (sibling at the same depth)
        - level 5 first child
        - level 5 second child (sibling at the same depth)
          - level 6 first child
          - level 6 second child (sibling at the same depth)
            - level 7 first child
            - level 7 second child (sibling at the same depth)
              - level 8 first child
              - level 8 second child (sibling at the same depth)
                - level 9 first child
                - level 9 second child (sibling at the same depth)
                  - level 10 first child
                  - level 10 second child (sibling at the same depth)
                    - level 11 first child
                    - level 11 second child (sibling at the same depth)
                      - level 12 first child
                      - level 12 second child (sibling at the same depth)
                        - level 13 first child
                        - level 13 second child (sibling at the same depth)
                          - level 14 first child
                          - level 14 second child (sibling at the same depth)
                            - level 15 first child
                            - level 15 second child (sibling at the same depth)
                              - level 16 first child
                              - level 16 second child (sibling at the same depth)

Ladder with alternating bullet characters (`-`, `*`, `+`) per level; all three
are the same list type and should render identically:

- level 1 written with `-`
  * level 2 written with `*`
    + level 3 written with `+`
      - level 4 written with `-`
        * level 5 written with `*`
          + level 6 written with `+`
            - level 7 written with `-`
              * level 8 written with `*`
                + level 9 written with `+`
                  - level 10 written with `-`
                    * level 11 written with `*`
                      + level 12 written with `+`

## 2. Ordered depth ladder

Ordered nesting to 12 levels using `1.` throughout. Each level restarts at 1.

1. level 1
   1. level 2
      1. level 3
         1. level 4
            1. level 5
               1. level 6
                  1. level 7
                     1. level 8
                        1. level 9
                           1. level 10
                              1. level 11
                                 1. level 12

Ordered nesting using the `)` delimiter instead:

1) level 1 with a paren delimiter
   1) level 2 with a paren delimiter
      1) level 3 with a paren delimiter
         1) level 4 with a paren delimiter
            1) level 5 with a paren delimiter
               1) level 6 with a paren delimiter
                  1) level 7 with a paren delimiter
                     1) level 8 with a paren delimiter
                        1) level 9 with a paren delimiter
                           1) level 10 with a paren delimiter
                              1) level 11 with a paren delimiter
                                 1) level 12 with a paren delimiter

Mixed delimiters per level (`.` on odd levels, `)` on even). Per CommonMark a
change of delimiter starts a new list, so nesting must still hold:

1. level 1
   1) level 2
      1. level 3
         1) level 4
            1. level 5
               1) level 6
                  1. level 7
                     1) level 8
                        1. level 9
                           1) level 10
                              1. level 11
                                 1) level 12

Lists that do not start at 1. The start attribute should be honoured at every depth:

7. level 1, this list starts at 7
8. level 1, continues at 8
    42. level 2, this list starts at 42
    43. level 2, continues at 43
        100. level 3, this list starts at 100
        101. level 3, continues at 101
            3. level 4, this list starts at 3
            4. level 4, continues at 4
                999. level 5, this list starts at 999
                1000. level 5, continues at 1000
                    12. level 6, this list starts at 12
                    13. level 6, continues at 13
                        5. level 7, this list starts at 5
                        6. level 7, continues at 6
                            80. level 8, this list starts at 80
                            81. level 8, continues at 81
                                21. level 9, this list starts at 21
                                22. level 9, continues at 22
                                    60. level 10, this list starts at 60
                                    61. level 10, continues at 61
                                        1000. level 11, this list starts at 1000
                                        1001. level 11, continues at 1001
                                            4. level 12, this list starts at 4
                                            5. level 12, continues at 5

Alternating ordered and unordered at each level, 14 deep:

1. level 1 (ordered)
   - level 2 (unordered)
      1. level 3 (ordered)
         - level 4 (unordered)
            1. level 5 (ordered)
               - level 6 (unordered)
                  1. level 7 (ordered)
                     - level 8 (unordered)
                        1. level 9 (ordered)
                           - level 10 (unordered)
                              1. level 11 (ordered)
                                 - level 12 (unordered)
                                    1. level 13 (ordered)
                                       - level 14 (unordered)

Ordered siblings with multi-digit numbers, to check that wide markers do not
shift the text column:

8. level 1 item 8
9. level 1 item 9
10. level 1 item 10
11. level 1 item 11
100. level 1 item 100
101. level 1 item 101
    8. level 2 item 8
    9. level 2 item 9
    10. level 2 item 10
    11. level 2 item 11
    100. level 2 item 100
    101. level 2 item 101
        8. level 3 item 8
        9. level 3 item 9
        10. level 3 item 10
        11. level 3 item 11
        100. level 3 item 100
        101. level 3 item 101
            8. level 4 item 8
            9. level 4 item 9
            10. level 4 item 10
            11. level 4 item 11
            100. level 4 item 100
            101. level 4 item 101
                8. level 5 item 8
                9. level 5 item 9
                10. level 5 item 10
                11. level 5 item 11
                100. level 5 item 100
                101. level 5 item 101
                    8. level 6 item 8
                    9. level 6 item 9
                    10. level 6 item 10
                    11. level 6 item 11
                    100. level 6 item 100
                    101. level 6 item 101

## 3. Mixed content in deep items

Deeply nested items carrying extra block content. Continuation blocks are
indented to the item's content column. If a renderer breaks, these blocks
escape to the left margin or terminate the list early.

### Depth 3 with block content

- level 1
  - level 2
    - level 3

      A continuation paragraph attached to the level 3 item. Renderer debounce ancestor chunk marker continuation pane scroll sibling scroll preview heading depth continuation renderer paragraph virtualization caret nesting preview cycling heading editor buffer pane heading virtualization soft descendant parser.

      ```elm
      renderAt : Int -> Html msg
      renderAt depth =
          Html.li [] [ Html.text ("level " ++ String.fromInt depth) ]
      ```

      > A blockquote inside the level 3 item.
      > Second quote line, same item. Continuation buffer descendant bullet caret wrap fence parser buffer wrap descendant document.

      | Column A | Column B | Column C |
      | --- | :-: | ---: |
      | depth 3 row 1 | centered | 111 |
      | depth 3 row 2 | centered | 222 |
      | depth 3 row 3 | centered | 333 |

      ![Placeholder image at depth 3](../screenshot.png)

      - child of the block-heavy item, at level 4
        - grandchild, level 5

      Final trailing paragraph of the level 3 item. Heading buffer checkbox fence renderer cycling fence descendant debounce anchor virtualization soft soft wrap continuation virtualization ancestor debounce generation virtualization.

### Depth 6 with block content

- level 1
  - level 2
    - level 3
      - level 4
        - level 5
          - level 6

            A continuation paragraph attached to the level 6 item. Scroll sibling sibling reflow wrap scroll ancestor generation document cycling virtualization continuation ancestor paragraph editor ordinal buffer chunk caret reflow wrap editor document ancestor reflow leaf heading cycling blockquote pane.

            ```elm
            renderAt : Int -> Html msg
            renderAt depth =
                Html.li [] [ Html.text ("level " ++ String.fromInt depth) ]
            ```

            > A blockquote inside the level 6 item.
            > Second quote line, same item. Paragraph cadence parser caret virtualization cadence bullet renderer preview continuation heading buffer.

            | Column A | Column B | Column C |
            | --- | :-: | ---: |
            | depth 6 row 1 | centered | 111 |
            | depth 6 row 2 | centered | 222 |
            | depth 6 row 3 | centered | 333 |

            ![Placeholder image at depth 6](../screenshot.png)

            - child of the block-heavy item, at level 7
              - grandchild, level 8

            Final trailing paragraph of the level 6 item. Cadence cadence parser nesting fence blockquote pane ordinal scroll leaf ancestor renderer sibling marker anchor scroll ancestor wrap renderer scroll.

### Depth 9 with block content

- level 1
  - level 2
    - level 3
      - level 4
        - level 5
          - level 6
            - level 7
              - level 8
                - level 9

                  A continuation paragraph attached to the level 9 item. Continuation renderer editor descendant reflow blockquote scroll descendant editor viewport virtualization pane table preview bullet sibling blockquote leaf budget blockquote soft blockquote generation sibling paragraph checkbox descendant paragraph table scroll.

                  ```elm
                  renderAt : Int -> Html msg
                  renderAt depth =
                      Html.li [] [ Html.text ("level " ++ String.fromInt depth) ]
                  ```

                  > A blockquote inside the level 9 item.
                  > Second quote line, same item. Heading table reflow document bullet debounce marker heading checkbox fence leaf reflow.

                  | Column A | Column B | Column C |
                  | --- | :-: | ---: |
                  | depth 9 row 1 | centered | 111 |
                  | depth 9 row 2 | centered | 222 |
                  | depth 9 row 3 | centered | 333 |

                  ![Placeholder image at depth 9](../screenshot.png)

                  - child of the block-heavy item, at level 10
                    - grandchild, level 11

                  Final trailing paragraph of the level 9 item. Blockquote continuation table parser virtualization cadence parser virtualization heading cadence ancestor cycling nesting preview fence marker debounce ordinal blockquote depth.

### Depth 12 with block content

- level 1
  - level 2
    - level 3
      - level 4
        - level 5
          - level 6
            - level 7
              - level 8
                - level 9
                  - level 10
                    - level 11
                      - level 12

                        A continuation paragraph attached to the level 12 item. Marker cadence wrap budget nesting nesting cadence marker checkbox table checkbox ancestor marker document document bullet checkbox budget debounce budget caret wrap budget budget nesting virtualization checkbox cadence descendant wrap.

                        ```elm
                        renderAt : Int -> Html msg
                        renderAt depth =
                            Html.li [] [ Html.text ("level " ++ String.fromInt depth) ]
                        ```

                        > A blockquote inside the level 12 item.
                        > Second quote line, same item. Leaf scroll cycling scroll reflow depth paragraph caret ordinal cycling scroll preview.

                        | Column A | Column B | Column C |
                        | --- | :-: | ---: |
                        | depth 12 row 1 | centered | 111 |
                        | depth 12 row 2 | centered | 222 |
                        | depth 12 row 3 | centered | 333 |

                        ![Placeholder image at depth 12](../screenshot.png)

                        - child of the block-heavy item, at level 13
                          - grandchild, level 14

                        Final trailing paragraph of the level 12 item. Reflow budget chunk depth editor document ancestor debounce renderer virtualization marker viewport blockquote marker ordinal wrap ordinal heading sibling paragraph.

### Loose versus tight at depth

The first sublist below is tight (no blank lines), the second is loose (blank
lines between items). Loose items should get paragraph spacing, tight ones should not.

- tight level 1
  - tight level 2
    - tight level 3
      - tight level 4
        - tight level 5

- loose level 1

  - loose level 2

    - loose level 3

      - loose level 4

      - loose level 4 sibling

## 4. Task list nesting

GFM checkboxes nested deep, mixed checked and unchecked, some with sub-paragraphs.

- [ ] level 1 task (open)
  - [ ] level 2 task (open)

    Notes for the level 2 task. Table ordinal preview heading cadence ancestor nesting table ancestor nesting wrap indentation bullet ancestor cycling bullet cadence cadence.

  - [ ] level 2 sibling task
    - [x] level 3 task (done)
      - [ ] level 4 task (open)
        - [ ] level 5 task (open)

          Notes for the level 5 task. Descendant bullet buffer blockquote paragraph parser pane scroll anchor sibling parser renderer checkbox heading reflow indentation pane fence.

        - [x] level 5 sibling task
          - [x] level 6 task (done)
            - [ ] level 7 task (open)
              - [ ] level 8 task (open)

                Notes for the level 8 task. Viewport budget virtualization marker ordinal soft continuation checkbox caret sibling fence cadence paragraph editor marker checkbox continuation heading.

              - [ ] level 8 sibling task
                - [x] level 9 task (done)
                  - [ ] level 10 task (open)

A checklist tree with mixed leaf states under each branch:

- [x] branch 1
  - [ ] branch 1 subtask 1
    - [ ] branch 1.1.1 leaf
    - [x] branch 1.1.2 leaf
      - [ ] branch 1.1.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [x] branch 1 subtask 2
    - [ ] branch 1.2.1 leaf
    - [x] branch 1.2.2 leaf
      - [ ] branch 1.2.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [ ] branch 1 subtask 3
    - [ ] branch 1.3.1 leaf
    - [x] branch 1.3.2 leaf
      - [ ] branch 1.3.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
- [ ] branch 2
  - [ ] branch 2 subtask 1
    - [x] branch 2.1.1 leaf
    - [ ] branch 2.1.2 leaf
      - [ ] branch 2.1.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [x] branch 2 subtask 2
    - [x] branch 2.2.1 leaf
    - [ ] branch 2.2.2 leaf
      - [ ] branch 2.2.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [ ] branch 2 subtask 3
    - [x] branch 2.3.1 leaf
    - [ ] branch 2.3.2 leaf
      - [ ] branch 2.3.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
- [x] branch 3
  - [ ] branch 3 subtask 1
    - [ ] branch 3.1.1 leaf
    - [x] branch 3.1.2 leaf
      - [ ] branch 3.1.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [x] branch 3 subtask 2
    - [ ] branch 3.2.1 leaf
    - [x] branch 3.2.2 leaf
      - [ ] branch 3.2.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [ ] branch 3 subtask 3
    - [ ] branch 3.3.1 leaf
    - [x] branch 3.3.2 leaf
      - [ ] branch 3.3.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
- [ ] branch 4
  - [ ] branch 4 subtask 1
    - [x] branch 4.1.1 leaf
    - [ ] branch 4.1.2 leaf
      - [ ] branch 4.1.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [x] branch 4 subtask 2
    - [x] branch 4.2.1 leaf
    - [ ] branch 4.2.2 leaf
      - [ ] branch 4.2.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked
  - [ ] branch 4 subtask 3
    - [x] branch 4.3.1 leaf
    - [ ] branch 4.3.2 leaf
      - [ ] branch 4.3.2 deep leaf, level 4
        - [x] level 5 checked
          - [ ] level 6 unchecked

Checkbox-like text that is *not* a task item (should render literally):

- \[x] escaped bracket, not a checkbox
- [ x ] spaces inside the brackets
  - [] empty brackets

## 5. Wide and shallow

600 flat siblings, no nesting. Contrast with the deep sections: this stresses
list length and editor scrolling rather than indentation.

- sibling 1 of 600 — renderer sibling
- sibling 2 of 600 — wrap debounce
- sibling 3 of 600 — virtualization nesting
- sibling 4 of 600 — soft buffer
- sibling 5 of 600 — scroll anchor
- sibling 6 of 600 — indentation debounce
- sibling 7 of 600 — depth generation
- sibling 8 of 600 — soft reflow
- sibling 9 of 600 — chunk sibling
- sibling 10 of 600 — soft fence
- sibling 11 of 600 — continuation ancestor
- sibling 12 of 600 — heading leaf
- sibling 13 of 600 — fence pane
- sibling 14 of 600 — table continuation
- sibling 15 of 600 — sibling heading
- sibling 16 of 600 — sibling table
- sibling 17 of 600 — pane bullet
- sibling 18 of 600 — cycling checkbox
- sibling 19 of 600 — virtualization descendant
- sibling 20 of 600 — virtualization checkbox
- sibling 21 of 600 — virtualization leaf
- sibling 22 of 600 — blockquote ancestor
- sibling 23 of 600 — wrap virtualization
- sibling 24 of 600 — editor parser
- sibling 25 of 600 — blockquote marker
- sibling 26 of 600 — continuation pane
- sibling 27 of 600 — editor scroll
- sibling 28 of 600 — nesting debounce
- sibling 29 of 600 — depth descendant
- sibling 30 of 600 — debounce heading
- sibling 31 of 600 — editor wrap
- sibling 32 of 600 — reflow cadence
- sibling 33 of 600 — depth fence
- sibling 34 of 600 — sibling parser
- sibling 35 of 600 — wrap caret
- sibling 36 of 600 — caret indentation
- sibling 37 of 600 — soft soft
- sibling 38 of 600 — blockquote budget
- sibling 39 of 600 — sibling debounce
- sibling 40 of 600 — soft table
- sibling 41 of 600 — ancestor fence
- sibling 42 of 600 — ordinal soft
- sibling 43 of 600 — reflow sibling
- sibling 44 of 600 — chunk nesting
- sibling 45 of 600 — budget descendant
- sibling 46 of 600 — buffer fence
- sibling 47 of 600 — document budget
- sibling 48 of 600 — parser fence
- sibling 49 of 600 — marker cadence
- sibling 50 of 600 — soft renderer
- sibling 51 of 600 — buffer cadence
- sibling 52 of 600 — viewport renderer
- sibling 53 of 600 — renderer editor
- sibling 54 of 600 — generation reflow
- sibling 55 of 600 — table descendant
- sibling 56 of 600 — pane nesting
- sibling 57 of 600 — ancestor budget
- sibling 58 of 600 — scroll budget
- sibling 59 of 600 — checkbox ordinal
- sibling 60 of 600 — buffer editor
- sibling 61 of 600 — blockquote renderer
- sibling 62 of 600 — chunk continuation
- sibling 63 of 600 — ancestor soft
- sibling 64 of 600 — wrap depth
- sibling 65 of 600 — marker reflow
- sibling 66 of 600 — soft parser
- sibling 67 of 600 — continuation chunk
- sibling 68 of 600 — chunk sibling
- sibling 69 of 600 — budget chunk
- sibling 70 of 600 — virtualization viewport
- sibling 71 of 600 — descendant caret
- sibling 72 of 600 — blockquote ordinal
- sibling 73 of 600 — reflow wrap
- sibling 74 of 600 — ancestor leaf
- sibling 75 of 600 — leaf fence
- sibling 76 of 600 — fence scroll
- sibling 77 of 600 — blockquote cycling
- sibling 78 of 600 — bullet blockquote
- sibling 79 of 600 — leaf renderer
- sibling 80 of 600 — continuation editor
- sibling 81 of 600 — descendant renderer
- sibling 82 of 600 — reflow debounce
- sibling 83 of 600 — cycling generation
- sibling 84 of 600 — depth wrap
- sibling 85 of 600 — document reflow
- sibling 86 of 600 — blockquote continuation
- sibling 87 of 600 — editor anchor
- sibling 88 of 600 — debounce generation
- sibling 89 of 600 — table leaf
- sibling 90 of 600 — preview descendant
- sibling 91 of 600 — fence caret
- sibling 92 of 600 — renderer marker
- sibling 93 of 600 — table viewport
- sibling 94 of 600 — nesting pane
- sibling 95 of 600 — debounce viewport
- sibling 96 of 600 — debounce table
- sibling 97 of 600 — debounce renderer
- sibling 98 of 600 — bullet anchor
- sibling 99 of 600 — virtualization soft
- sibling 100 of 600 — blockquote ordinal
- sibling 101 of 600 — chunk soft
- sibling 102 of 600 — virtualization virtualization
- sibling 103 of 600 — viewport nesting
- sibling 104 of 600 — debounce buffer
- sibling 105 of 600 — marker bullet
- sibling 106 of 600 — marker cadence
- sibling 107 of 600 — heading chunk
- sibling 108 of 600 — nesting heading
- sibling 109 of 600 — anchor continuation
- sibling 110 of 600 — editor scroll
- sibling 111 of 600 — parser soft
- sibling 112 of 600 — parser table
- sibling 113 of 600 — depth wrap
- sibling 114 of 600 — descendant reflow
- sibling 115 of 600 — generation fence
- sibling 116 of 600 — budget continuation
- sibling 117 of 600 — ancestor virtualization
- sibling 118 of 600 — sibling anchor
- sibling 119 of 600 — caret pane
- sibling 120 of 600 — buffer chunk
- sibling 121 of 600 — virtualization virtualization
- sibling 122 of 600 — cadence descendant
- sibling 123 of 600 — leaf chunk
- sibling 124 of 600 — cadence bullet
- sibling 125 of 600 — descendant scroll
- sibling 126 of 600 — bullet document
- sibling 127 of 600 — fence marker
- sibling 128 of 600 — nesting pane
- sibling 129 of 600 — chunk continuation
- sibling 130 of 600 — pane anchor
- sibling 131 of 600 — nesting scroll
- sibling 132 of 600 — virtualization blockquote
- sibling 133 of 600 — reflow preview
- sibling 134 of 600 — viewport buffer
- sibling 135 of 600 — descendant marker
- sibling 136 of 600 — checkbox descendant
- sibling 137 of 600 — descendant virtualization
- sibling 138 of 600 — fence leaf
- sibling 139 of 600 — pane indentation
- sibling 140 of 600 — preview bullet
- sibling 141 of 600 — scroll sibling
- sibling 142 of 600 — scroll chunk
- sibling 143 of 600 — preview sibling
- sibling 144 of 600 — leaf leaf
- sibling 145 of 600 — indentation wrap
- sibling 146 of 600 — fence cycling
- sibling 147 of 600 — depth fence
- sibling 148 of 600 — indentation generation
- sibling 149 of 600 — renderer ancestor
- sibling 150 of 600 — ancestor caret
- sibling 151 of 600 — indentation heading
- sibling 152 of 600 — buffer virtualization
- sibling 153 of 600 — renderer caret
- sibling 154 of 600 — soft soft
- sibling 155 of 600 — indentation continuation
- sibling 156 of 600 — leaf paragraph
- sibling 157 of 600 — anchor soft
- sibling 158 of 600 — nesting sibling
- sibling 159 of 600 — reflow editor
- sibling 160 of 600 — paragraph nesting
- sibling 161 of 600 — cycling renderer
- sibling 162 of 600 — document parser
- sibling 163 of 600 — caret chunk
- sibling 164 of 600 — continuation ancestor
- sibling 165 of 600 — wrap reflow
- sibling 166 of 600 — generation scroll
- sibling 167 of 600 — ordinal paragraph
- sibling 168 of 600 — buffer marker
- sibling 169 of 600 — checkbox editor
- sibling 170 of 600 — document cycling
- sibling 171 of 600 — debounce table
- sibling 172 of 600 — nesting nesting
- sibling 173 of 600 — virtualization scroll
- sibling 174 of 600 — ancestor viewport
- sibling 175 of 600 — cycling continuation
- sibling 176 of 600 — document heading
- sibling 177 of 600 — paragraph descendant
- sibling 178 of 600 — ancestor viewport
- sibling 179 of 600 — depth marker
- sibling 180 of 600 — renderer scroll
- sibling 181 of 600 — leaf scroll
- sibling 182 of 600 — debounce marker
- sibling 183 of 600 — ordinal anchor
- sibling 184 of 600 — heading blockquote
- sibling 185 of 600 — ancestor preview
- sibling 186 of 600 — viewport document
- sibling 187 of 600 — indentation caret
- sibling 188 of 600 — chunk editor
- sibling 189 of 600 — checkbox wrap
- sibling 190 of 600 — renderer chunk
- sibling 191 of 600 — virtualization preview
- sibling 192 of 600 — cycling table
- sibling 193 of 600 — leaf blockquote
- sibling 194 of 600 — caret blockquote
- sibling 195 of 600 — continuation continuation
- sibling 196 of 600 — preview descendant
- sibling 197 of 600 — scroll chunk
- sibling 198 of 600 — ancestor generation
- sibling 199 of 600 — fence viewport
- sibling 200 of 600 — heading paragraph
- sibling 201 of 600 — heading renderer
- sibling 202 of 600 — caret parser
- sibling 203 of 600 — generation viewport
- sibling 204 of 600 — soft anchor
- sibling 205 of 600 — debounce pane
- sibling 206 of 600 — document wrap
- sibling 207 of 600 — buffer bullet
- sibling 208 of 600 — generation caret
- sibling 209 of 600 — paragraph preview
- sibling 210 of 600 — depth depth
- sibling 211 of 600 — editor cycling
- sibling 212 of 600 — leaf parser
- sibling 213 of 600 — indentation cadence
- sibling 214 of 600 — indentation caret
- sibling 215 of 600 — reflow depth
- sibling 216 of 600 — indentation fence
- sibling 217 of 600 — parser sibling
- sibling 218 of 600 — leaf virtualization
- sibling 219 of 600 — cycling preview
- sibling 220 of 600 — cycling caret
- sibling 221 of 600 — wrap blockquote
- sibling 222 of 600 — wrap continuation
- sibling 223 of 600 — wrap renderer
- sibling 224 of 600 — preview buffer
- sibling 225 of 600 — checkbox sibling
- sibling 226 of 600 — blockquote debounce
- sibling 227 of 600 — caret nesting
- sibling 228 of 600 — preview heading
- sibling 229 of 600 — document cadence
- sibling 230 of 600 — scroll scroll
- sibling 231 of 600 — pane checkbox
- sibling 232 of 600 — bullet indentation
- sibling 233 of 600 — depth heading
- sibling 234 of 600 — indentation descendant
- sibling 235 of 600 — budget continuation
- sibling 236 of 600 — nesting blockquote
- sibling 237 of 600 — descendant blockquote
- sibling 238 of 600 — ancestor reflow
- sibling 239 of 600 — blockquote budget
- sibling 240 of 600 — nesting checkbox
- sibling 241 of 600 — document caret
- sibling 242 of 600 — heading renderer
- sibling 243 of 600 — continuation ordinal
- sibling 244 of 600 — depth cycling
- sibling 245 of 600 — document marker
- sibling 246 of 600 — caret cycling
- sibling 247 of 600 — cadence indentation
- sibling 248 of 600 — depth soft
- sibling 249 of 600 — chunk table
- sibling 250 of 600 — wrap continuation
- sibling 251 of 600 — bullet renderer
- sibling 252 of 600 — indentation editor
- sibling 253 of 600 — buffer continuation
- sibling 254 of 600 — caret fence
- sibling 255 of 600 — indentation nesting
- sibling 256 of 600 — reflow cycling
- sibling 257 of 600 — nesting caret
- sibling 258 of 600 — virtualization wrap
- sibling 259 of 600 — descendant anchor
- sibling 260 of 600 — fence nesting
- sibling 261 of 600 — cadence cycling
- sibling 262 of 600 — soft cycling
- sibling 263 of 600 — continuation heading
- sibling 264 of 600 — parser anchor
- sibling 265 of 600 — fence debounce
- sibling 266 of 600 — checkbox continuation
- sibling 267 of 600 — continuation budget
- sibling 268 of 600 — marker generation
- sibling 269 of 600 — cycling editor
- sibling 270 of 600 — nesting document
- sibling 271 of 600 — cycling checkbox
- sibling 272 of 600 — heading ancestor
- sibling 273 of 600 — indentation viewport
- sibling 274 of 600 — table indentation
- sibling 275 of 600 — nesting preview
- sibling 276 of 600 — document editor
- sibling 277 of 600 — viewport virtualization
- sibling 278 of 600 — budget blockquote
- sibling 279 of 600 — depth descendant
- sibling 280 of 600 — blockquote heading
- sibling 281 of 600 — leaf table
- sibling 282 of 600 — buffer blockquote
- sibling 283 of 600 — parser reflow
- sibling 284 of 600 — indentation cycling
- sibling 285 of 600 — debounce pane
- sibling 286 of 600 — wrap sibling
- sibling 287 of 600 — blockquote scroll
- sibling 288 of 600 — chunk paragraph
- sibling 289 of 600 — soft budget
- sibling 290 of 600 — caret descendant
- sibling 291 of 600 — pane preview
- sibling 292 of 600 — editor editor
- sibling 293 of 600 — leaf preview
- sibling 294 of 600 — fence continuation
- sibling 295 of 600 — viewport cycling
- sibling 296 of 600 — heading anchor
- sibling 297 of 600 — document buffer
- sibling 298 of 600 — wrap preview
- sibling 299 of 600 — cadence descendant
- sibling 300 of 600 — ancestor viewport
- sibling 301 of 600 — indentation checkbox
- sibling 302 of 600 — viewport descendant
- sibling 303 of 600 — renderer cycling
- sibling 304 of 600 — paragraph blockquote
- sibling 305 of 600 — editor indentation
- sibling 306 of 600 — scroll ancestor
- sibling 307 of 600 — table viewport
- sibling 308 of 600 — ordinal reflow
- sibling 309 of 600 — pane ancestor
- sibling 310 of 600 — debounce anchor
- sibling 311 of 600 — fence marker
- sibling 312 of 600 — anchor blockquote
- sibling 313 of 600 — cadence nesting
- sibling 314 of 600 — blockquote leaf
- sibling 315 of 600 — viewport fence
- sibling 316 of 600 — reflow budget
- sibling 317 of 600 — continuation viewport
- sibling 318 of 600 — reflow blockquote
- sibling 319 of 600 — anchor indentation
- sibling 320 of 600 — indentation cycling
- sibling 321 of 600 — scroll viewport
- sibling 322 of 600 — generation blockquote
- sibling 323 of 600 — marker virtualization
- sibling 324 of 600 — soft nesting
- sibling 325 of 600 — table debounce
- sibling 326 of 600 — renderer budget
- sibling 327 of 600 — heading parser
- sibling 328 of 600 — cadence parser
- sibling 329 of 600 — buffer soft
- sibling 330 of 600 — soft scroll
- sibling 331 of 600 — ancestor debounce
- sibling 332 of 600 — preview continuation
- sibling 333 of 600 — checkbox virtualization
- sibling 334 of 600 — editor table
- sibling 335 of 600 — anchor debounce
- sibling 336 of 600 — reflow budget
- sibling 337 of 600 — scroll chunk
- sibling 338 of 600 — paragraph wrap
- sibling 339 of 600 — document reflow
- sibling 340 of 600 — parser budget
- sibling 341 of 600 — checkbox sibling
- sibling 342 of 600 — depth preview
- sibling 343 of 600 — depth depth
- sibling 344 of 600 — fence descendant
- sibling 345 of 600 — nesting reflow
- sibling 346 of 600 — viewport depth
- sibling 347 of 600 — document heading
- sibling 348 of 600 — pane buffer
- sibling 349 of 600 — table soft
- sibling 350 of 600 — anchor checkbox
- sibling 351 of 600 — cadence leaf
- sibling 352 of 600 — reflow paragraph
- sibling 353 of 600 — ordinal virtualization
- sibling 354 of 600 — caret leaf
- sibling 355 of 600 — pane reflow
- sibling 356 of 600 — bullet scroll
- sibling 357 of 600 — anchor anchor
- sibling 358 of 600 — budget ancestor
- sibling 359 of 600 — document editor
- sibling 360 of 600 — indentation budget
- sibling 361 of 600 — chunk cadence
- sibling 362 of 600 — soft parser
- sibling 363 of 600 — descendant anchor
- sibling 364 of 600 — document viewport
- sibling 365 of 600 — document viewport
- sibling 366 of 600 — renderer generation
- sibling 367 of 600 — renderer generation
- sibling 368 of 600 — viewport viewport
- sibling 369 of 600 — heading cadence
- sibling 370 of 600 — scroll depth
- sibling 371 of 600 — nesting soft
- sibling 372 of 600 — parser preview
- sibling 373 of 600 — fence blockquote
- sibling 374 of 600 — indentation renderer
- sibling 375 of 600 — buffer bullet
- sibling 376 of 600 — nesting document
- sibling 377 of 600 — scroll wrap
- sibling 378 of 600 — preview blockquote
- sibling 379 of 600 — nesting bullet
- sibling 380 of 600 — marker editor
- sibling 381 of 600 — nesting blockquote
- sibling 382 of 600 — wrap scroll
- sibling 383 of 600 — parser cadence
- sibling 384 of 600 — indentation budget
- sibling 385 of 600 — parser editor
- sibling 386 of 600 — heading caret
- sibling 387 of 600 — bullet soft
- sibling 388 of 600 — continuation chunk
- sibling 389 of 600 — buffer caret
- sibling 390 of 600 — document depth
- sibling 391 of 600 — generation heading
- sibling 392 of 600 — descendant fence
- sibling 393 of 600 — sibling ancestor
- sibling 394 of 600 — wrap chunk
- sibling 395 of 600 — chunk buffer
- sibling 396 of 600 — heading scroll
- sibling 397 of 600 — checkbox table
- sibling 398 of 600 — parser ancestor
- sibling 399 of 600 — chunk blockquote
- sibling 400 of 600 — checkbox heading
- sibling 401 of 600 — wrap fence
- sibling 402 of 600 — checkbox nesting
- sibling 403 of 600 — cadence generation
- sibling 404 of 600 — marker renderer
- sibling 405 of 600 — descendant pane
- sibling 406 of 600 — ordinal buffer
- sibling 407 of 600 — budget reflow
- sibling 408 of 600 — chunk anchor
- sibling 409 of 600 — blockquote scroll
- sibling 410 of 600 — depth leaf
- sibling 411 of 600 — paragraph buffer
- sibling 412 of 600 — wrap caret
- sibling 413 of 600 — scroll cadence
- sibling 414 of 600 — soft marker
- sibling 415 of 600 — indentation chunk
- sibling 416 of 600 — checkbox nesting
- sibling 417 of 600 — checkbox ordinal
- sibling 418 of 600 — viewport ordinal
- sibling 419 of 600 — nesting virtualization
- sibling 420 of 600 — anchor descendant
- sibling 421 of 600 — table viewport
- sibling 422 of 600 — wrap pane
- sibling 423 of 600 — marker ancestor
- sibling 424 of 600 — checkbox depth
- sibling 425 of 600 — descendant depth
- sibling 426 of 600 — reflow ordinal
- sibling 427 of 600 — nesting scroll
- sibling 428 of 600 — ancestor renderer
- sibling 429 of 600 — depth cycling
- sibling 430 of 600 — bullet continuation
- sibling 431 of 600 — ordinal renderer
- sibling 432 of 600 — caret cadence
- sibling 433 of 600 — table indentation
- sibling 434 of 600 — parser ancestor
- sibling 435 of 600 — scroll viewport
- sibling 436 of 600 — pane indentation
- sibling 437 of 600 — anchor descendant
- sibling 438 of 600 — ordinal viewport
- sibling 439 of 600 — sibling blockquote
- sibling 440 of 600 — chunk ordinal
- sibling 441 of 600 — budget editor
- sibling 442 of 600 — nesting scroll
- sibling 443 of 600 — parser blockquote
- sibling 444 of 600 — anchor pane
- sibling 445 of 600 — table ancestor
- sibling 446 of 600 — ancestor caret
- sibling 447 of 600 — bullet heading
- sibling 448 of 600 — document marker
- sibling 449 of 600 — viewport fence
- sibling 450 of 600 — depth nesting
- sibling 451 of 600 — table marker
- sibling 452 of 600 — budget bullet
- sibling 453 of 600 — cycling buffer
- sibling 454 of 600 — indentation generation
- sibling 455 of 600 — bullet nesting
- sibling 456 of 600 — fence table
- sibling 457 of 600 — ancestor cycling
- sibling 458 of 600 — document document
- sibling 459 of 600 — leaf buffer
- sibling 460 of 600 — wrap checkbox
- sibling 461 of 600 — marker continuation
- sibling 462 of 600 — chunk nesting
- sibling 463 of 600 — leaf document
- sibling 464 of 600 — debounce nesting
- sibling 465 of 600 — buffer nesting
- sibling 466 of 600 — reflow caret
- sibling 467 of 600 — sibling bullet
- sibling 468 of 600 — editor wrap
- sibling 469 of 600 — bullet buffer
- sibling 470 of 600 — caret ancestor
- sibling 471 of 600 — soft ancestor
- sibling 472 of 600 — cycling debounce
- sibling 473 of 600 — reflow pane
- sibling 474 of 600 — continuation bullet
- sibling 475 of 600 — caret wrap
- sibling 476 of 600 — document anchor
- sibling 477 of 600 — heading nesting
- sibling 478 of 600 — checkbox blockquote
- sibling 479 of 600 — blockquote chunk
- sibling 480 of 600 — debounce budget
- sibling 481 of 600 — cadence document
- sibling 482 of 600 — renderer anchor
- sibling 483 of 600 — depth ancestor
- sibling 484 of 600 — marker cadence
- sibling 485 of 600 — chunk heading
- sibling 486 of 600 — sibling viewport
- sibling 487 of 600 — chunk scroll
- sibling 488 of 600 — descendant paragraph
- sibling 489 of 600 — budget paragraph
- sibling 490 of 600 — buffer depth
- sibling 491 of 600 — cadence paragraph
- sibling 492 of 600 — editor blockquote
- sibling 493 of 600 — renderer continuation
- sibling 494 of 600 — nesting blockquote
- sibling 495 of 600 — heading parser
- sibling 496 of 600 — sibling cadence
- sibling 497 of 600 — buffer renderer
- sibling 498 of 600 — virtualization generation
- sibling 499 of 600 — continuation anchor
- sibling 500 of 600 — cadence preview
- sibling 501 of 600 — scroll indentation
- sibling 502 of 600 — sibling checkbox
- sibling 503 of 600 — chunk buffer
- sibling 504 of 600 — marker soft
- sibling 505 of 600 — table continuation
- sibling 506 of 600 — ordinal table
- sibling 507 of 600 — bullet buffer
- sibling 508 of 600 — soft paragraph
- sibling 509 of 600 — continuation table
- sibling 510 of 600 — soft nesting
- sibling 511 of 600 — debounce fence
- sibling 512 of 600 — buffer preview
- sibling 513 of 600 — depth sibling
- sibling 514 of 600 — marker pane
- sibling 515 of 600 — chunk ordinal
- sibling 516 of 600 — ordinal paragraph
- sibling 517 of 600 — leaf cadence
- sibling 518 of 600 — virtualization wrap
- sibling 519 of 600 — fence anchor
- sibling 520 of 600 — cycling ordinal
- sibling 521 of 600 — anchor ordinal
- sibling 522 of 600 — reflow nesting
- sibling 523 of 600 — debounce caret
- sibling 524 of 600 — indentation table
- sibling 525 of 600 — heading marker
- sibling 526 of 600 — chunk paragraph
- sibling 527 of 600 — debounce debounce
- sibling 528 of 600 — anchor scroll
- sibling 529 of 600 — continuation anchor
- sibling 530 of 600 — cycling wrap
- sibling 531 of 600 — virtualization sibling
- sibling 532 of 600 — wrap paragraph
- sibling 533 of 600 — caret descendant
- sibling 534 of 600 — caret parser
- sibling 535 of 600 — cadence budget
- sibling 536 of 600 — marker wrap
- sibling 537 of 600 — ancestor indentation
- sibling 538 of 600 — heading heading
- sibling 539 of 600 — bullet soft
- sibling 540 of 600 — generation heading
- sibling 541 of 600 — pane paragraph
- sibling 542 of 600 — heading cycling
- sibling 543 of 600 — continuation generation
- sibling 544 of 600 — editor wrap
- sibling 545 of 600 — parser marker
- sibling 546 of 600 — reflow generation
- sibling 547 of 600 — budget document
- sibling 548 of 600 — budget bullet
- sibling 549 of 600 — blockquote wrap
- sibling 550 of 600 — sibling document
- sibling 551 of 600 — ordinal chunk
- sibling 552 of 600 — debounce document
- sibling 553 of 600 — leaf viewport
- sibling 554 of 600 — paragraph sibling
- sibling 555 of 600 — ancestor budget
- sibling 556 of 600 — heading caret
- sibling 557 of 600 — reflow blockquote
- sibling 558 of 600 — buffer fence
- sibling 559 of 600 — generation cycling
- sibling 560 of 600 — scroll descendant
- sibling 561 of 600 — ancestor sibling
- sibling 562 of 600 — scroll blockquote
- sibling 563 of 600 — document document
- sibling 564 of 600 — cycling continuation
- sibling 565 of 600 — leaf table
- sibling 566 of 600 — paragraph ordinal
- sibling 567 of 600 — ordinal heading
- sibling 568 of 600 — parser leaf
- sibling 569 of 600 — buffer cadence
- sibling 570 of 600 — anchor soft
- sibling 571 of 600 — marker wrap
- sibling 572 of 600 — budget generation
- sibling 573 of 600 — heading buffer
- sibling 574 of 600 — depth leaf
- sibling 575 of 600 — anchor leaf
- sibling 576 of 600 — generation virtualization
- sibling 577 of 600 — nesting heading
- sibling 578 of 600 — anchor heading
- sibling 579 of 600 — preview continuation
- sibling 580 of 600 — budget heading
- sibling 581 of 600 — wrap table
- sibling 582 of 600 — document cadence
- sibling 583 of 600 — viewport leaf
- sibling 584 of 600 — scroll cycling
- sibling 585 of 600 — descendant chunk
- sibling 586 of 600 — anchor anchor
- sibling 587 of 600 — document descendant
- sibling 588 of 600 — ancestor cycling
- sibling 589 of 600 — cycling ancestor
- sibling 590 of 600 — continuation virtualization
- sibling 591 of 600 — budget reflow
- sibling 592 of 600 — wrap paragraph
- sibling 593 of 600 — soft budget
- sibling 594 of 600 — preview pane
- sibling 595 of 600 — ancestor budget
- sibling 596 of 600 — document sibling
- sibling 597 of 600 — wrap cadence
- sibling 598 of 600 — fence indentation
- sibling 599 of 600 — preview marker
- sibling 600 of 600 — depth marker

300 flat ordered siblings:

1. ordered sibling 1 of 300
2. ordered sibling 2 of 300
3. ordered sibling 3 of 300
4. ordered sibling 4 of 300
5. ordered sibling 5 of 300
6. ordered sibling 6 of 300
7. ordered sibling 7 of 300
8. ordered sibling 8 of 300
9. ordered sibling 9 of 300
10. ordered sibling 10 of 300
11. ordered sibling 11 of 300
12. ordered sibling 12 of 300
13. ordered sibling 13 of 300
14. ordered sibling 14 of 300
15. ordered sibling 15 of 300
16. ordered sibling 16 of 300
17. ordered sibling 17 of 300
18. ordered sibling 18 of 300
19. ordered sibling 19 of 300
20. ordered sibling 20 of 300
21. ordered sibling 21 of 300
22. ordered sibling 22 of 300
23. ordered sibling 23 of 300
24. ordered sibling 24 of 300
25. ordered sibling 25 of 300
26. ordered sibling 26 of 300
27. ordered sibling 27 of 300
28. ordered sibling 28 of 300
29. ordered sibling 29 of 300
30. ordered sibling 30 of 300
31. ordered sibling 31 of 300
32. ordered sibling 32 of 300
33. ordered sibling 33 of 300
34. ordered sibling 34 of 300
35. ordered sibling 35 of 300
36. ordered sibling 36 of 300
37. ordered sibling 37 of 300
38. ordered sibling 38 of 300
39. ordered sibling 39 of 300
40. ordered sibling 40 of 300
41. ordered sibling 41 of 300
42. ordered sibling 42 of 300
43. ordered sibling 43 of 300
44. ordered sibling 44 of 300
45. ordered sibling 45 of 300
46. ordered sibling 46 of 300
47. ordered sibling 47 of 300
48. ordered sibling 48 of 300
49. ordered sibling 49 of 300
50. ordered sibling 50 of 300
51. ordered sibling 51 of 300
52. ordered sibling 52 of 300
53. ordered sibling 53 of 300
54. ordered sibling 54 of 300
55. ordered sibling 55 of 300
56. ordered sibling 56 of 300
57. ordered sibling 57 of 300
58. ordered sibling 58 of 300
59. ordered sibling 59 of 300
60. ordered sibling 60 of 300
61. ordered sibling 61 of 300
62. ordered sibling 62 of 300
63. ordered sibling 63 of 300
64. ordered sibling 64 of 300
65. ordered sibling 65 of 300
66. ordered sibling 66 of 300
67. ordered sibling 67 of 300
68. ordered sibling 68 of 300
69. ordered sibling 69 of 300
70. ordered sibling 70 of 300
71. ordered sibling 71 of 300
72. ordered sibling 72 of 300
73. ordered sibling 73 of 300
74. ordered sibling 74 of 300
75. ordered sibling 75 of 300
76. ordered sibling 76 of 300
77. ordered sibling 77 of 300
78. ordered sibling 78 of 300
79. ordered sibling 79 of 300
80. ordered sibling 80 of 300
81. ordered sibling 81 of 300
82. ordered sibling 82 of 300
83. ordered sibling 83 of 300
84. ordered sibling 84 of 300
85. ordered sibling 85 of 300
86. ordered sibling 86 of 300
87. ordered sibling 87 of 300
88. ordered sibling 88 of 300
89. ordered sibling 89 of 300
90. ordered sibling 90 of 300
91. ordered sibling 91 of 300
92. ordered sibling 92 of 300
93. ordered sibling 93 of 300
94. ordered sibling 94 of 300
95. ordered sibling 95 of 300
96. ordered sibling 96 of 300
97. ordered sibling 97 of 300
98. ordered sibling 98 of 300
99. ordered sibling 99 of 300
100. ordered sibling 100 of 300
101. ordered sibling 101 of 300
102. ordered sibling 102 of 300
103. ordered sibling 103 of 300
104. ordered sibling 104 of 300
105. ordered sibling 105 of 300
106. ordered sibling 106 of 300
107. ordered sibling 107 of 300
108. ordered sibling 108 of 300
109. ordered sibling 109 of 300
110. ordered sibling 110 of 300
111. ordered sibling 111 of 300
112. ordered sibling 112 of 300
113. ordered sibling 113 of 300
114. ordered sibling 114 of 300
115. ordered sibling 115 of 300
116. ordered sibling 116 of 300
117. ordered sibling 117 of 300
118. ordered sibling 118 of 300
119. ordered sibling 119 of 300
120. ordered sibling 120 of 300
121. ordered sibling 121 of 300
122. ordered sibling 122 of 300
123. ordered sibling 123 of 300
124. ordered sibling 124 of 300
125. ordered sibling 125 of 300
126. ordered sibling 126 of 300
127. ordered sibling 127 of 300
128. ordered sibling 128 of 300
129. ordered sibling 129 of 300
130. ordered sibling 130 of 300
131. ordered sibling 131 of 300
132. ordered sibling 132 of 300
133. ordered sibling 133 of 300
134. ordered sibling 134 of 300
135. ordered sibling 135 of 300
136. ordered sibling 136 of 300
137. ordered sibling 137 of 300
138. ordered sibling 138 of 300
139. ordered sibling 139 of 300
140. ordered sibling 140 of 300
141. ordered sibling 141 of 300
142. ordered sibling 142 of 300
143. ordered sibling 143 of 300
144. ordered sibling 144 of 300
145. ordered sibling 145 of 300
146. ordered sibling 146 of 300
147. ordered sibling 147 of 300
148. ordered sibling 148 of 300
149. ordered sibling 149 of 300
150. ordered sibling 150 of 300
151. ordered sibling 151 of 300
152. ordered sibling 152 of 300
153. ordered sibling 153 of 300
154. ordered sibling 154 of 300
155. ordered sibling 155 of 300
156. ordered sibling 156 of 300
157. ordered sibling 157 of 300
158. ordered sibling 158 of 300
159. ordered sibling 159 of 300
160. ordered sibling 160 of 300
161. ordered sibling 161 of 300
162. ordered sibling 162 of 300
163. ordered sibling 163 of 300
164. ordered sibling 164 of 300
165. ordered sibling 165 of 300
166. ordered sibling 166 of 300
167. ordered sibling 167 of 300
168. ordered sibling 168 of 300
169. ordered sibling 169 of 300
170. ordered sibling 170 of 300
171. ordered sibling 171 of 300
172. ordered sibling 172 of 300
173. ordered sibling 173 of 300
174. ordered sibling 174 of 300
175. ordered sibling 175 of 300
176. ordered sibling 176 of 300
177. ordered sibling 177 of 300
178. ordered sibling 178 of 300
179. ordered sibling 179 of 300
180. ordered sibling 180 of 300
181. ordered sibling 181 of 300
182. ordered sibling 182 of 300
183. ordered sibling 183 of 300
184. ordered sibling 184 of 300
185. ordered sibling 185 of 300
186. ordered sibling 186 of 300
187. ordered sibling 187 of 300
188. ordered sibling 188 of 300
189. ordered sibling 189 of 300
190. ordered sibling 190 of 300
191. ordered sibling 191 of 300
192. ordered sibling 192 of 300
193. ordered sibling 193 of 300
194. ordered sibling 194 of 300
195. ordered sibling 195 of 300
196. ordered sibling 196 of 300
197. ordered sibling 197 of 300
198. ordered sibling 198 of 300
199. ordered sibling 199 of 300
200. ordered sibling 200 of 300
201. ordered sibling 201 of 300
202. ordered sibling 202 of 300
203. ordered sibling 203 of 300
204. ordered sibling 204 of 300
205. ordered sibling 205 of 300
206. ordered sibling 206 of 300
207. ordered sibling 207 of 300
208. ordered sibling 208 of 300
209. ordered sibling 209 of 300
210. ordered sibling 210 of 300
211. ordered sibling 211 of 300
212. ordered sibling 212 of 300
213. ordered sibling 213 of 300
214. ordered sibling 214 of 300
215. ordered sibling 215 of 300
216. ordered sibling 216 of 300
217. ordered sibling 217 of 300
218. ordered sibling 218 of 300
219. ordered sibling 219 of 300
220. ordered sibling 220 of 300
221. ordered sibling 221 of 300
222. ordered sibling 222 of 300
223. ordered sibling 223 of 300
224. ordered sibling 224 of 300
225. ordered sibling 225 of 300
226. ordered sibling 226 of 300
227. ordered sibling 227 of 300
228. ordered sibling 228 of 300
229. ordered sibling 229 of 300
230. ordered sibling 230 of 300
231. ordered sibling 231 of 300
232. ordered sibling 232 of 300
233. ordered sibling 233 of 300
234. ordered sibling 234 of 300
235. ordered sibling 235 of 300
236. ordered sibling 236 of 300
237. ordered sibling 237 of 300
238. ordered sibling 238 of 300
239. ordered sibling 239 of 300
240. ordered sibling 240 of 300
241. ordered sibling 241 of 300
242. ordered sibling 242 of 300
243. ordered sibling 243 of 300
244. ordered sibling 244 of 300
245. ordered sibling 245 of 300
246. ordered sibling 246 of 300
247. ordered sibling 247 of 300
248. ordered sibling 248 of 300
249. ordered sibling 249 of 300
250. ordered sibling 250 of 300
251. ordered sibling 251 of 300
252. ordered sibling 252 of 300
253. ordered sibling 253 of 300
254. ordered sibling 254 of 300
255. ordered sibling 255 of 300
256. ordered sibling 256 of 300
257. ordered sibling 257 of 300
258. ordered sibling 258 of 300
259. ordered sibling 259 of 300
260. ordered sibling 260 of 300
261. ordered sibling 261 of 300
262. ordered sibling 262 of 300
263. ordered sibling 263 of 300
264. ordered sibling 264 of 300
265. ordered sibling 265 of 300
266. ordered sibling 266 of 300
267. ordered sibling 267 of 300
268. ordered sibling 268 of 300
269. ordered sibling 269 of 300
270. ordered sibling 270 of 300
271. ordered sibling 271 of 300
272. ordered sibling 272 of 300
273. ordered sibling 273 of 300
274. ordered sibling 274 of 300
275. ordered sibling 275 of 300
276. ordered sibling 276 of 300
277. ordered sibling 277 of 300
278. ordered sibling 278 of 300
279. ordered sibling 279 of 300
280. ordered sibling 280 of 300
281. ordered sibling 281 of 300
282. ordered sibling 282 of 300
283. ordered sibling 283 of 300
284. ordered sibling 284 of 300
285. ordered sibling 285 of 300
286. ordered sibling 286 of 300
287. ordered sibling 287 of 300
288. ordered sibling 288 of 300
289. ordered sibling 289 of 300
290. ordered sibling 290 of 300
291. ordered sibling 291 of 300
292. ordered sibling 292 of 300
293. ordered sibling 293 of 300
294. ordered sibling 294 of 300
295. ordered sibling 295 of 300
296. ordered sibling 296 of 300
297. ordered sibling 297 of 300
298. ordered sibling 298 of 300
299. ordered sibling 299 of 300
300. ordered sibling 300 of 300

## 6. Long leaf text

Single-line items with several hundred words each, at increasing depth. No hard
wraps: the preview must soft-wrap inside the item's indent, and the editor must
scroll horizontally without corrupting the virtualized rows.

- LONG LEAF AT LEVEL 1: Cadence caret bullet blockquote sibling fence cadence heading viewport wrap heading renderer pane table descendant heading budget paragraph leaf heading indentation caret cadence soft marker preview ancestor anchor reflow bullet heading wrap indentation blockquote caret continuation virtualization reflow heading editor debounce parser continuation caret paragraph checkbox parser ancestor descendant blockquote renderer ordinal ancestor depth blockquote pane generation ancestor anchor sibling heading generation depth scroll reflow continuation checkbox generation budget debounce scroll ancestor fence wrap continuation leaf bullet debounce cadence chunk sibling leaf indentation cadence virtualization cycling table sibling wrap preview chunk virtualization cycling nesting generation document continuation heading chunk continuation nesting paragraph cadence document editor bullet cadence fence blockquote depth budget preview viewport editor soft document heading soft marker marker table document document leaf wrap marker document preview table generation renderer soft table soft table reflow paragraph heading chunk renderer pane virtualization scroll sibling document budget editor soft buffer bullet checkbox paragraph depth viewport ancestor scroll ancestor reflow heading debounce parser budget document buffer checkbox pane ancestor cadence scroll viewport pane scroll viewport buffer fence budget continuation nesting leaf fence renderer table preview virtualization generation generation sibling chunk scroll scroll nesting reflow indentation wrap virtualization indentation document ordinal parser reflow anchor renderer depth depth depth marker soft parser generation cycling reflow debounce virtualization continuation generation checkbox chunk fence editor leaf editor ordinal cycling checkbox buffer parser wrap caret blockquote scroll indentation heading scroll debounce ancestor nesting checkbox leaf heading checkbox continuation bullet anchor budget marker fence debounce renderer caret marker renderer cycling anchor fence scroll bullet document caret anchor virtualization cycling fence virtualization soft table generation marker table scroll marker continuation cadence sibling cycling depth descendant soft virtualization debounce table reflow pane wrap budget pane checkbox wrap debounce cycling indentation marker wrap continuation cadence heading document viewport cadence anchor reflow parser document scroll ancestor table debounce sibling ancestor viewport soft wrap ancestor descendant fence cadence wrap cadence wrap document generation caret paragraph sibling nesting nesting editor scroll chunk budget ancestor preview cadence wrap chunk editor anchor cycling chunk buffer paragraph ancestor paragraph table leaf descendant wrap cycling wrap preview ordinal cycling table buffer caret leaf depth scroll soft viewport bullet depth bullet budget fence renderer parser heading table ordinal chunk blockquote budget document nesting checkbox preview nesting cycling heading pane indentation cadence soft renderer generation chunk leaf preview editor preview generation buffer buffer descendant depth debounce ordinal pane virtualization viewport heading scroll ancestor heading soft table checkbox editor ordinal budget caret chunk document budget viewport fence renderer pane virtualization indentation debounce wrap cadence table anchor preview cycling preview document scroll cycling sibling chunk viewport continuation continuation ordinal indentation descendant paragraph preview continuation ancestor heading indentation descendant debounce debounce checkbox anchor.

- level 1 ancestor of a long leaf
  - level 2 ancestor of a long leaf
    - level 3 ancestor of a long leaf
      - LONG LEAF AT LEVEL 4: Budget budget cadence bullet wrap indentation bullet caret marker ancestor soft renderer caret sibling anchor heading budget virtualization cycling sibling reflow document scroll continuation descendant document heading pane indentation viewport sibling virtualization bullet viewport preview blockquote descendant table nesting document document nesting bullet buffer checkbox viewport budget chunk anchor paragraph document viewport cadence viewport depth descendant preview soft preview bullet nesting cycling blockquote viewport ordinal pane table soft paragraph editor sibling reflow wrap blockquote caret cycling paragraph pane checkbox viewport caret indentation generation renderer marker fence caret editor heading table viewport descendant generation caret debounce blockquote indentation preview leaf wrap leaf continuation preview preview blockquote fence chunk marker fence fence sibling marker wrap ordinal pane editor leaf virtualization chunk generation budget preview heading sibling generation leaf parser anchor blockquote wrap descendant fence marker checkbox budget table paragraph buffer caret paragraph anchor chunk sibling reflow pane buffer debounce indentation ordinal pane parser fence heading paragraph marker nesting pane depth generation renderer indentation table parser cadence continuation virtualization ancestor nesting sibling fence preview depth cadence paragraph anchor descendant ordinal renderer cycling preview caret anchor editor anchor soft debounce fence paragraph budget blockquote ancestor parser fence table paragraph wrap continuation preview reflow anchor checkbox depth buffer indentation depth document nesting indentation table checkbox chunk marker virtualization indentation cadence buffer sibling soft fence cadence chunk sibling scroll heading caret reflow heading marker soft renderer chunk sibling blockquote preview cadence pane continuation paragraph budget leaf ancestor blockquote cadence bullet buffer indentation anchor bullet blockquote parser heading debounce cycling caret document pane preview indentation fence virtualization generation debounce editor parser debounce viewport table cadence buffer caret sibling sibling descendant debounce cycling generation generation heading generation bullet descendant pane caret buffer caret chunk pane table document caret editor pane renderer preview marker indentation preview blockquote chunk paragraph editor descendant reflow indentation checkbox sibling bullet scroll chunk generation debounce parser cadence checkbox continuation parser virtualization editor descendant viewport cycling leaf fence checkbox anchor scroll reflow viewport cycling debounce cadence debounce buffer anchor chunk editor editor anchor cadence blockquote paragraph checkbox wrap scroll editor continuation ancestor sibling caret ordinal continuation editor fence descendant pane pane renderer paragraph reflow cadence virtualization ancestor soft viewport leaf budget fence cadence checkbox generation generation renderer marker leaf blockquote renderer sibling buffer depth soft table cadence ancestor fence depth editor leaf preview scroll viewport preview document virtualization wrap budget chunk blockquote cadence marker table descendant anchor generation preview ancestor viewport debounce document sibling soft depth heading cadence indentation blockquote marker wrap document blockquote scroll indentation wrap indentation wrap caret cycling document document bullet heading cycling nesting cycling paragraph anchor depth wrap chunk anchor sibling fence anchor paragraph document document chunk renderer paragraph document fence.

- level 1 ancestor of a long leaf
  - level 2 ancestor of a long leaf
    - level 3 ancestor of a long leaf
      - level 4 ancestor of a long leaf
        - level 5 ancestor of a long leaf
          - level 6 ancestor of a long leaf
            - level 7 ancestor of a long leaf
              - LONG LEAF AT LEVEL 8: Heading cadence virtualization sibling reflow bullet fence reflow ancestor renderer descendant virtualization editor ancestor soft generation preview chunk caret reflow fence nesting ordinal preview table caret indentation paragraph cadence anchor document continuation caret cycling buffer pane continuation ordinal leaf paragraph paragraph ordinal checkbox wrap virtualization marker leaf blockquote continuation fence nesting chunk cycling marker generation heading document ancestor paragraph anchor ancestor descendant wrap heading marker table checkbox generation fence wrap depth viewport debounce leaf sibling ordinal descendant virtualization pane heading renderer descendant paragraph buffer heading blockquote descendant chunk document descendant leaf nesting nesting continuation debounce virtualization checkbox descendant table heading depth blockquote heading depth renderer chunk budget cycling parser editor marker checkbox sibling preview wrap fence fence caret continuation paragraph wrap cadence viewport chunk table anchor editor depth heading soft fence document ordinal pane table depth buffer generation marker debounce preview editor nesting preview renderer heading soft marker cycling parser wrap renderer table generation checkbox renderer depth sibling chunk debounce checkbox virtualization chunk editor scroll virtualization marker fence generation budget descendant cadence indentation generation chunk editor editor viewport leaf generation viewport ancestor renderer depth preview caret anchor table indentation viewport wrap descendant ancestor debounce ordinal document pane marker leaf preview indentation generation chunk preview preview viewport caret virtualization document leaf chunk depth table soft parser reflow cycling budget descendant depth blockquote ancestor fence continuation parser generation reflow marker budget chunk preview descendant leaf fence blockquote reflow ordinal cycling ancestor fence ancestor ancestor pane ancestor chunk bullet pane cycling document generation leaf anchor debounce wrap preview preview chunk marker continuation paragraph cadence ordinal marker leaf sibling fence soft anchor cycling table anchor fence continuation renderer marker blockquote bullet anchor document renderer pane viewport heading anchor paragraph reflow anchor checkbox cycling budget caret sibling wrap ancestor pane sibling reflow cadence ancestor debounce indentation reflow document scroll anchor renderer chunk wrap soft fence ancestor blockquote ordinal editor paragraph sibling sibling budget descendant soft bullet pane scroll ancestor scroll table caret indentation bullet table document budget buffer leaf scroll descendant budget cycling preview ancestor virtualization sibling paragraph blockquote parser bullet parser table sibling budget virtualization reflow wrap bullet sibling viewport heading continuation blockquote virtualization viewport buffer generation table marker sibling debounce budget pane cadence anchor chunk ordinal ordinal preview document cadence virtualization sibling descendant ancestor parser fence ordinal indentation leaf bullet continuation paragraph fence virtualization checkbox continuation chunk continuation ancestor scroll nesting document document editor caret budget fence preview reflow marker budget virtualization ordinal reflow ancestor editor checkbox ordinal ordinal ancestor leaf pane leaf ancestor blockquote ordinal indentation preview soft blockquote ancestor pane parser indentation generation debounce indentation reflow caret wrap generation parser editor checkbox virtualization indentation buffer viewport bullet continuation fence parser table.

- level 1 ancestor of a long leaf
  - level 2 ancestor of a long leaf
    - level 3 ancestor of a long leaf
      - level 4 ancestor of a long leaf
        - level 5 ancestor of a long leaf
          - level 6 ancestor of a long leaf
            - level 7 ancestor of a long leaf
              - level 8 ancestor of a long leaf
                - level 9 ancestor of a long leaf
                  - level 10 ancestor of a long leaf
                    - level 11 ancestor of a long leaf
                      - LONG LEAF AT LEVEL 12: Editor paragraph pane parser marker table descendant cadence descendant preview marker soft paragraph leaf chunk reflow soft chunk renderer buffer scroll reflow ordinal anchor soft table continuation blockquote viewport editor nesting table depth reflow ancestor cycling depth generation leaf marker renderer chunk leaf indentation table bullet soft descendant ancestor sibling caret generation anchor generation preview fence marker scroll reflow leaf paragraph ancestor budget viewport preview depth ordinal table checkbox virtualization indentation nesting anchor debounce descendant chunk debounce bullet cycling paragraph virtualization soft anchor continuation debounce fence fence leaf continuation leaf viewport table blockquote virtualization sibling table pane checkbox bullet parser wrap viewport ancestor wrap pane continuation buffer renderer buffer chunk buffer reflow ancestor ancestor blockquote virtualization renderer caret fence chunk buffer cadence debounce indentation paragraph virtualization generation reflow descendant virtualization indentation ordinal caret budget reflow pane continuation budget depth bullet paragraph document nesting scroll nesting marker editor ancestor ordinal blockquote leaf scroll marker sibling checkbox sibling editor ordinal cycling preview renderer sibling continuation nesting checkbox reflow buffer editor depth renderer checkbox generation caret nesting chunk cadence soft scroll chunk budget budget pane cadence scroll soft bullet fence checkbox viewport editor reflow document marker sibling indentation blockquote nesting depth debounce indentation debounce fence editor generation table renderer soft chunk descendant depth scroll indentation continuation descendant buffer wrap marker caret anchor soft pane generation table cycling wrap table nesting continuation soft anchor nesting leaf wrap virtualization descendant budget reflow soft table preview chunk cadence marker heading generation caret ancestor document table indentation parser ordinal leaf debounce virtualization table leaf continuation renderer continuation descendant pane pane paragraph buffer wrap caret bullet virtualization virtualization sibling wrap fence ordinal anchor ancestor editor caret renderer blockquote ancestor heading parser caret cadence budget editor depth renderer debounce scroll indentation table bullet paragraph anchor checkbox preview cadence document nesting scroll generation soft chunk blockquote buffer cadence ancestor editor wrap debounce reflow depth debounce parser marker bullet virtualization wrap anchor indentation sibling cadence document blockquote preview descendant sibling cycling leaf nesting generation nesting renderer nesting budget paragraph ordinal anchor cadence table renderer ordinal nesting continuation leaf bullet checkbox soft descendant renderer continuation cadence ordinal chunk sibling cycling blockquote cycling renderer depth nesting marker descendant document pane document nesting scroll checkbox generation ordinal ancestor paragraph preview chunk paragraph budget table debounce checkbox viewport depth chunk leaf checkbox budget wrap continuation parser nesting preview cadence budget table continuation leaf indentation buffer checkbox budget scroll soft parser caret nesting wrap table generation soft bullet bullet ordinal indentation blockquote reflow viewport paragraph descendant editor depth ordinal indentation continuation reflow paragraph nesting preview ancestor nesting checkbox nesting editor caret soft reflow document viewport chunk caret cycling heading indentation wrap nesting heading heading descendant editor.

Two long siblings at the same depth, to check spacing between wrapped items:

- level 1 parent
  - Parser cycling heading cadence blockquote editor virtualization blockquote bullet soft fence chunk nesting cadence indentation buffer checkbox soft soft document parser fence editor editor anchor caret generation generation leaf continuation viewport editor reflow editor descendant soft anchor ordinal chunk wrap anchor editor scroll pane nesting marker ancestor pane renderer continuation ancestor paragraph document document caret ordinal virtualization chunk soft indentation indentation paragraph parser leaf pane table soft bullet reflow viewport heading editor chunk caret indentation buffer virtualization paragraph chunk depth nesting virtualization checkbox parser budget renderer soft continuation document depth chunk blockquote leaf cycling blockquote ordinal heading budget generation parser renderer generation heading blockquote editor parser table wrap buffer table budget nesting cadence parser continuation cadence marker depth sibling cadence reflow anchor ancestor debounce marker sibling virtualization caret descendant bullet table soft viewport budget blockquote cycling virtualization table checkbox checkbox table renderer fence descendant anchor debounce ordinal pane virtualization soft budget scroll caret anchor blockquote caret marker continuation soft fence ancestor buffer buffer reflow ancestor blockquote parser chunk marker chunk document marker soft bullet viewport sibling paragraph soft wrap caret table ordinal fence heading ancestor blockquote renderer ordinal depth buffer ordinal document parser cycling reflow document viewport paragraph viewport chunk checkbox indentation blockquote virtualization renderer renderer document reflow debounce leaf indentation buffer buffer generation ordinal buffer virtualization generation pane fence ordinal editor cadence depth caret document indentation virtualization editor ordinal bullet checkbox debounce debounce leaf preview paragraph ancestor generation ordinal wrap blockquote ordinal continuation anchor paragraph caret debounce pane anchor preview generation ordinal ancestor marker generation caret budget document ordinal budget reflow pane budget parser caret reflow indentation virtualization reflow ancestor anchor ancestor cycling bullet soft editor reflow editor viewport parser scroll marker leaf virtualization checkbox scroll editor editor document virtualization bullet ancestor caret preview descendant virtualization sibling caret heading blockquote caret fence continuation viewport descendant renderer descendant table nesting continuation generation wrap soft editor descendant anchor ancestor soft renderer.
  - Cadence caret leaf buffer depth continuation paragraph marker editor nesting viewport paragraph scroll paragraph ancestor ancestor buffer leaf paragraph reflow checkbox bullet budget generation fence buffer ordinal buffer heading leaf descendant anchor descendant paragraph reflow ancestor buffer debounce cycling bullet reflow leaf preview scroll table ordinal heading generation ancestor generation generation preview table virtualization ancestor descendant heading continuation parser descendant cadence descendant continuation table soft scroll heading table viewport heading cadence cycling bullet budget cycling scroll marker sibling continuation descendant fence parser paragraph document reflow fence editor caret table chunk heading fence sibling heading reflow renderer pane scroll blockquote buffer descendant anchor soft leaf fence wrap soft marker viewport parser scroll wrap debounce anchor blockquote depth anchor virtualization cadence buffer parser document anchor blockquote pane viewport ordinal descendant nesting anchor descendant paragraph depth debounce cycling scroll buffer preview wrap cadence soft bullet marker pane indentation fence fence buffer sibling pane wrap document buffer viewport caret ordinal blockquote marker descendant checkbox blockquote parser caret editor indentation parser chunk marker editor chunk ordinal paragraph marker reflow checkbox cadence blockquote virtualization marker renderer cadence pane generation continuation nesting marker preview debounce bullet blockquote budget editor depth anchor editor marker soft generation pane paragraph debounce virtualization marker depth viewport chunk ancestor document nesting reflow blockquote bullet continuation paragraph leaf parser scroll budget virtualization nesting generation leaf buffer editor renderer caret reflow sibling buffer viewport nesting table heading virtualization parser marker pane buffer checkbox blockquote debounce checkbox cycling chunk ancestor debounce checkbox marker paragraph descendant ancestor wrap indentation marker preview renderer editor pane caret preview anchor reflow scroll wrap cycling cycling preview reflow anchor caret table viewport paragraph parser document debounce cadence budget scroll fence soft reflow parser preview cycling indentation budget anchor caret descendant cadence cadence editor cycling cadence sibling virtualization heading nesting heading checkbox cycling parser preview parser paragraph ancestor wrap heading leaf checkbox editor ancestor indentation marker continuation indentation marker table budget.

A long item with a long continuation paragraph:

- level 1
  - level 2 item: Marker heading preview editor cadence renderer virtualization bullet wrap editor buffer budget table descendant bullet continuation blockquote editor heading wrap budget preview renderer caret depth depth caret reflow viewport ordinal ordinal caret sibling preview ordinal nesting soft paragraph preview preview renderer generation sibling caret chunk soft table chunk cadence pane bullet checkbox virtualization virtualization marker cycling checkbox checkbox generation virtualization budget nesting marker generation sibling continuation table wrap virtualization pane heading blockquote blockquote parser bullet sibling wrap soft viewport cycling anchor caret bullet buffer paragraph heading debounce budget sibling budget reflow ancestor leaf parser debounce anchor wrap ordinal ancestor reflow sibling document debounce fence sibling virtualization preview document preview marker marker renderer pane anchor fence viewport soft chunk checkbox paragraph renderer table paragraph ordinal sibling cycling continuation descendant wrap marker heading paragraph ordinal virtualization wrap viewport continuation sibling fence cadence paragraph chunk editor blockquote cadence anchor pane wrap parser table renderer heading buffer anchor depth marker generation editor buffer continuation budget bullet generation fence table anchor caret ancestor wrap heading ancestor wrap depth budget paragraph cadence editor wrap cadence soft budget continuation parser ancestor buffer depth leaf buffer chunk generation renderer editor checkbox editor table leaf ancestor preview cycling budget.

    Table fence wrap viewport marker renderer marker descendant depth indentation wrap virtualization continuation paragraph pane soft cycling virtualization indentation budget continuation marker pane viewport nesting heading nesting wrap cycling marker preview budget budget depth chunk bullet renderer marker preview bullet depth bullet cadence fence ancestor caret pane paragraph preview budget scroll cycling editor document editor scroll editor chunk debounce reflow cadence preview editor wrap parser marker table cycling buffer budget preview generation chunk table debounce budget reflow scroll viewport document cadence marker document debounce buffer wrap ancestor heading blockquote debounce generation indentation paragraph debounce cadence buffer bullet anchor wrap chunk pane sibling generation budget parser table generation pane ancestor indentation marker preview nesting cycling wrap wrap anchor continuation debounce reflow cycling continuation scroll cycling viewport table pane nesting blockquote viewport bullet anchor blockquote anchor virtualization indentation continuation generation nesting sibling marker viewport document soft depth parser preview budget parser document parser wrap document cycling caret renderer bullet leaf viewport preview sibling ancestor marker preview heading viewport table indentation checkbox continuation document chunk pane debounce ancestor caret checkbox caret pane nesting ancestor generation buffer blockquote preview document virtualization sibling reflow chunk descendant ordinal viewport viewport editor sibling blockquote checkbox virtualization preview ancestor renderer leaf descendant checkbox depth bullet fence checkbox renderer buffer document checkbox caret ancestor anchor soft caret bullet document preview preview preview debounce document editor viewport descendant chunk anchor bullet checkbox editor debounce caret debounce leaf cycling viewport editor document budget heading descendant checkbox editor caret paragraph blockquote heading cadence nesting ancestor paragraph viewport checkbox sibling heading sibling anchor sibling leaf document marker ordinal paragraph renderer descendant renderer heading editor editor buffer virtualization cycling generation renderer leaf descendant reflow.

## 7. Ragged / malformed nesting (intentional)

**Everything in this section is deliberately malformed.** Do not fix it. The
requirement is only that the preview stays rendered and the editor stays usable;
exact output may differ from other renderers.

### 7.1 Inconsistent indent widths (2, 3, 4 spaces)

- level 1
  - two-space child
     - three-space grandchild under a two-space parent
    - four-space item, less indented than its predecessor
       - five-space item
  - back to two spaces

### 7.2 Tabs mixed with spaces

- level 1 with spaces below
	- tab-indented child
	  - tab plus two spaces
  	- two spaces plus tab
		- two tabs
        - eight spaces, visually the same as two tabs

### 7.3 Skipped levels

- level 1
      - jumps straight to what looks like level 4
  - drops back to level 2
            - jumps to what looks like level 7
- level 1 again

### 7.4 Under-indented continuation paragraph

- level 1
  - level 2 item

 This continuation paragraph is indented by one space, less than the item's
content column. It is ambiguous whether it belongs to the item or ends the list.

  - another level 2 item

### 7.5 List interrupted by a heading, then resumed

- level 1 before the heading
  - level 2 before the heading

#### An interrupting heading inside the list

- level 1 after the heading (numbering and nesting restart here)
  - level 2 after the heading

### 7.6 Ordered list with broken numbering

1. first
1. also written as 1
5. jumps to 5
3. back to 3
   7. nested starting at 7
   2. then 2

### 7.7 Blank lines and stray markers

- level 1


  - level 2 after two blank lines
-
- item after an empty marker
  -   extra spaces after the marker
-no space after the marker, so not a list item at all

## 8. Bulk

Repetitive but structurally varied nesting, to make the document genuinely large
and force chunked parsing across many top-level sections. Each block below
repeats a different shape.

### Bulk block 1

Block 1: Cadence budget viewport anchor document indentation marker buffer cycling blockquote reflow nesting ordinal generation continuation descendant depth pane soft editor virtualization virtualization.

- block 1 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 1 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 1 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 2

Block 2: Fence paragraph checkbox blockquote sibling debounce sibling sibling soft blockquote nesting anchor scroll debounce bullet paragraph descendant heading soft scroll anchor sibling.

1. block 2 alternating level 1
   - block 2 alternating level 2
      1. block 2 alternating level 3
         - block 2 alternating level 4
            1. block 2 alternating level 5
               - block 2 alternating level 6
                  1. block 2 alternating level 7
                     - block 2 alternating level 8

                       Continuation paragraph at the bottom of block 2. Document chunk preview heading leaf editor heading marker viewport viewport renderer ordinal scroll fence renderer depth.

### Bulk block 3

Block 3: Viewport pane buffer checkbox ordinal viewport generation caret pane sibling blockquote wrap debounce sibling indentation budget cadence ancestor cadence fence cycling cadence.

- [x] block 3 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 3 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 3 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 3 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 4

Block 4: Debounce wrap parser soft soft parser leaf debounce parser cadence sibling virtualization leaf anchor reflow paragraph virtualization bullet ordinal anchor fence budget.

- block 4 item with blocks
  - nested item

    ```json
    { "block": 4, "depth": 2, "note": "indentation" }
    ```

    > quoted note for block 4

    | key | value |
    | --- | --- |
    | block | 4 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 5

Block 5: Budget nesting caret chunk budget caret descendant cycling buffer cadence renderer reflow document preview checkbox budget blockquote heading scroll descendant ancestor continuation.

- block 5 straight ladder, level 1
  - block 5 straight ladder, level 2
    - block 5 straight ladder, level 3
      - block 5 straight ladder, level 4
        - block 5 straight ladder, level 5
          - block 5 straight ladder, level 6
            - block 5 straight ladder, level 7
              - block 5 straight ladder, level 8
                - block 5 straight ladder, level 9
                  - block 5 straight ladder, level 10

### Bulk block 6

Block 6: Continuation virtualization generation leaf debounce anchor blockquote cadence buffer pane pane descendant editor ancestor wrap reflow editor descendant fence leaf generation checkbox.

- block 6 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 6 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 6 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 7

Block 7: Virtualization paragraph depth fence parser debounce continuation document viewport descendant reflow pane cycling continuation viewport generation scroll ancestor ancestor soft fence indentation.

1. block 7 alternating level 1
   - block 7 alternating level 2
      1. block 7 alternating level 3
         - block 7 alternating level 4
            1. block 7 alternating level 5
               - block 7 alternating level 6
                  1. block 7 alternating level 7
                     - block 7 alternating level 8

                       Continuation paragraph at the bottom of block 7. Cadence descendant virtualization viewport generation buffer cadence indentation bullet caret parser virtualization pane renderer virtualization sibling.

Long line inside block 7: Fence parser soft marker paragraph pane budget cadence cadence ordinal fence chunk cadence editor indentation ordinal nesting fence paragraph marker anchor heading renderer depth wrap budget bullet marker document debounce debounce indentation heading depth soft table table renderer checkbox bullet document paragraph viewport anchor leaf blockquote leaf paragraph cadence debounce bullet soft wrap viewport editor continuation renderer preview anchor buffer virtualization cadence descendant table viewport blockquote anchor generation cycling checkbox descendant viewport anchor budget anchor preview nesting depth fence document marker ordinal descendant cadence soft checkbox paragraph depth editor debounce parser renderer virtualization blockquote table generation editor wrap blockquote soft parser pane marker scroll document renderer table cycling reflow fence pane document renderer reflow cycling bullet caret buffer generation chunk buffer scroll pane leaf table debounce buffer cadence paragraph chunk preview scroll paragraph scroll reflow renderer fence virtualization preview scroll buffer buffer wrap indentation soft soft nesting blockquote viewport marker debounce leaf table budget renderer blockquote reflow viewport anchor descendant.

### Bulk block 8

Block 8: Virtualization viewport leaf editor generation heading depth scroll pane generation ancestor ordinal bullet ancestor sibling caret continuation marker renderer bullet wrap bullet.

- [x] block 8 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 8 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 8 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 8 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 9

Block 9: Marker scroll anchor bullet budget virtualization sibling scroll renderer blockquote blockquote viewport ordinal renderer pane preview soft indentation checkbox paragraph ancestor cycling.

- block 9 item with blocks
  - nested item

    ```json
    { "block": 9, "depth": 2, "note": "nesting" }
    ```

    > quoted note for block 9

    | key | value |
    | --- | --- |
    | block | 9 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 10

Block 10: Depth buffer checkbox budget soft table renderer nesting descendant generation heading sibling heading reflow sibling bullet table heading anchor paragraph leaf caret.

- block 10 straight ladder, level 1
  - block 10 straight ladder, level 2
    - block 10 straight ladder, level 3
      - block 10 straight ladder, level 4
        - block 10 straight ladder, level 5
          - block 10 straight ladder, level 6
            - block 10 straight ladder, level 7
              - block 10 straight ladder, level 8
                - block 10 straight ladder, level 9
                  - block 10 straight ladder, level 10

### Bulk block 11

Block 11: Paragraph buffer debounce marker descendant preview viewport indentation caret continuation cycling document pane reflow checkbox virtualization document table generation indentation buffer preview.

- block 11 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 11 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 11 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 12

Block 12: Checkbox continuation renderer budget anchor reflow generation descendant budget editor sibling nesting ancestor budget viewport viewport continuation soft cadence virtualization cycling table.

1. block 12 alternating level 1
   - block 12 alternating level 2
      1. block 12 alternating level 3
         - block 12 alternating level 4
            1. block 12 alternating level 5
               - block 12 alternating level 6
                  1. block 12 alternating level 7
                     - block 12 alternating level 8

                       Continuation paragraph at the bottom of block 12. Scroll caret sibling generation wrap marker continuation document ancestor chunk marker nesting fence blockquote buffer wrap.

### Bulk block 13

Block 13: Cadence marker preview checkbox soft descendant debounce marker leaf bullet continuation fence sibling heading bullet descendant cycling continuation continuation parser paragraph leaf.

- [x] block 13 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 13 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 13 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 13 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 14

Block 14: Reflow debounce wrap ordinal descendant viewport indentation paragraph debounce anchor pane table sibling heading ordinal sibling preview caret bullet parser editor leaf.

- block 14 item with blocks
  - nested item

    ```json
    { "block": 14, "depth": 2, "note": "bullet" }
    ```

    > quoted note for block 14

    | key | value |
    | --- | --- |
    | block | 14 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

Long line inside block 14: Parser anchor continuation generation indentation leaf cadence blockquote editor document cadence cadence cadence anchor parser preview virtualization viewport viewport reflow sibling viewport cycling bullet editor bullet paragraph buffer parser chunk reflow renderer cycling generation wrap descendant anchor nesting anchor descendant descendant leaf renderer reflow ordinal nesting reflow marker cycling cadence anchor generation blockquote checkbox continuation checkbox descendant continuation preview paragraph marker checkbox scroll bullet sibling buffer bullet document indentation descendant editor anchor leaf nesting checkbox checkbox pane preview table reflow budget ancestor pane nesting parser depth buffer debounce debounce cycling document editor checkbox nesting descendant marker heading indentation bullet sibling ancestor sibling document budget indentation debounce cycling budget continuation cycling caret wrap debounce cadence nesting blockquote budget reflow preview parser reflow scroll bullet indentation nesting depth cadence viewport debounce parser leaf caret caret marker sibling nesting budget bullet bullet fence blockquote buffer pane renderer caret nesting ordinal document ordinal anchor reflow heading renderer bullet leaf descendant cadence reflow virtualization ordinal.

### Bulk block 15

Block 15: Checkbox chunk document descendant pane reflow parser cadence chunk preview cadence depth reflow sibling scroll preview budget soft viewport marker descendant chunk.

- block 15 straight ladder, level 1
  - block 15 straight ladder, level 2
    - block 15 straight ladder, level 3
      - block 15 straight ladder, level 4
        - block 15 straight ladder, level 5
          - block 15 straight ladder, level 6
            - block 15 straight ladder, level 7
              - block 15 straight ladder, level 8
                - block 15 straight ladder, level 9
                  - block 15 straight ladder, level 10

### Bulk block 16

Block 16: Sibling editor caret parser debounce marker editor wrap soft parser caret editor nesting blockquote descendant editor sibling buffer blockquote pane pane leaf.

- block 16 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 16 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 16 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 17

Block 17: Nesting ordinal continuation descendant chunk pane cycling preview depth virtualization cadence table checkbox virtualization fence ancestor cycling paragraph scroll leaf table leaf.

1. block 17 alternating level 1
   - block 17 alternating level 2
      1. block 17 alternating level 3
         - block 17 alternating level 4
            1. block 17 alternating level 5
               - block 17 alternating level 6
                  1. block 17 alternating level 7
                     - block 17 alternating level 8

                       Continuation paragraph at the bottom of block 17. Editor virtualization indentation descendant table bullet indentation virtualization ordinal virtualization paragraph fence preview parser ordinal leaf.

### Bulk block 18

Block 18: Wrap nesting viewport virtualization paragraph checkbox scroll caret debounce virtualization wrap caret bullet preview descendant heading wrap renderer indentation nesting cadence preview.

- [x] block 18 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 18 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 18 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 18 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 19

Block 19: Buffer blockquote document preview blockquote table ordinal heading preview viewport preview soft parser anchor soft caret cadence blockquote caret caret continuation blockquote.

- block 19 item with blocks
  - nested item

    ```json
    { "block": 19, "depth": 2, "note": "budget" }
    ```

    > quoted note for block 19

    | key | value |
    | --- | --- |
    | block | 19 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 20

Block 20: Scroll parser wrap document ordinal renderer indentation nesting sibling continuation blockquote editor heading buffer debounce paragraph virtualization indentation cycling depth buffer chunk.

- block 20 straight ladder, level 1
  - block 20 straight ladder, level 2
    - block 20 straight ladder, level 3
      - block 20 straight ladder, level 4
        - block 20 straight ladder, level 5
          - block 20 straight ladder, level 6
            - block 20 straight ladder, level 7
              - block 20 straight ladder, level 8
                - block 20 straight ladder, level 9
                  - block 20 straight ladder, level 10

### Bulk block 21

Block 21: Document viewport viewport sibling leaf ordinal heading continuation chunk renderer buffer chunk ancestor ordinal nesting preview viewport cycling chunk reflow virtualization virtualization.

- block 21 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 21 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 21 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

Long line inside block 21: Budget ancestor marker editor sibling wrap viewport fence heading bullet continuation depth sibling debounce renderer table caret viewport indentation indentation marker renderer ordinal ordinal depth fence nesting viewport bullet debounce checkbox fence heading blockquote soft editor leaf document renderer wrap preview generation heading table fence soft depth descendant reflow marker cadence leaf marker reflow depth heading descendant pane soft parser fence descendant sibling buffer checkbox scroll budget table cycling buffer virtualization parser caret marker soft virtualization continuation parser parser sibling budget caret pane ordinal heading sibling heading budget ordinal editor blockquote document cycling descendant bullet wrap editor scroll cadence sibling document debounce editor sibling table reflow chunk debounce scroll marker cycling buffer ancestor fence anchor pane reflow buffer marker chunk marker anchor soft fence bullet preview ordinal reflow caret preview wrap indentation continuation soft ancestor bullet fence cycling blockquote buffer nesting depth continuation generation marker leaf viewport table parser parser debounce bullet editor virtualization pane paragraph marker virtualization fence bullet.

### Bulk block 22

Block 22: Nesting checkbox caret debounce descendant editor preview cadence buffer editor cycling generation fence bullet pane cycling parser ancestor descendant marker preview checkbox.

1. block 22 alternating level 1
   - block 22 alternating level 2
      1. block 22 alternating level 3
         - block 22 alternating level 4
            1. block 22 alternating level 5
               - block 22 alternating level 6
                  1. block 22 alternating level 7
                     - block 22 alternating level 8

                       Continuation paragraph at the bottom of block 22. Leaf marker debounce descendant buffer descendant caret wrap debounce renderer marker checkbox generation leaf wrap continuation.

### Bulk block 23

Block 23: Scroll generation ancestor renderer pane document continuation scroll debounce document table leaf chunk cadence virtualization document generation chunk wrap fence soft reflow.

- [x] block 23 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 23 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 23 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 23 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 24

Block 24: Caret wrap leaf depth fence cycling buffer fence table budget buffer debounce heading debounce wrap blockquote parser checkbox reflow reflow budget viewport.

- block 24 item with blocks
  - nested item

    ```json
    { "block": 24, "depth": 2, "note": "bullet" }
    ```

    > quoted note for block 24

    | key | value |
    | --- | --- |
    | block | 24 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 25

Block 25: Sibling depth indentation soft wrap document heading chunk nesting scroll ancestor cadence paragraph bullet ancestor anchor wrap soft cycling table viewport editor.

- block 25 straight ladder, level 1
  - block 25 straight ladder, level 2
    - block 25 straight ladder, level 3
      - block 25 straight ladder, level 4
        - block 25 straight ladder, level 5
          - block 25 straight ladder, level 6
            - block 25 straight ladder, level 7
              - block 25 straight ladder, level 8
                - block 25 straight ladder, level 9
                  - block 25 straight ladder, level 10

### Bulk block 26

Block 26: Sibling depth fence cycling continuation renderer preview cycling renderer ancestor renderer chunk wrap cycling soft continuation caret virtualization depth nesting wrap indentation.

- block 26 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 26 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 26 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 27

Block 27: Blockquote scroll debounce buffer virtualization nesting continuation debounce budget depth indentation renderer generation renderer editor checkbox debounce reflow reflow cadence nesting virtualization.

1. block 27 alternating level 1
   - block 27 alternating level 2
      1. block 27 alternating level 3
         - block 27 alternating level 4
            1. block 27 alternating level 5
               - block 27 alternating level 6
                  1. block 27 alternating level 7
                     - block 27 alternating level 8

                       Continuation paragraph at the bottom of block 27. Ordinal cadence sibling fence ancestor budget debounce depth leaf reflow virtualization ordinal soft chunk scroll anchor.

### Bulk block 28

Block 28: Blockquote indentation continuation pane preview heading caret anchor document generation scroll ancestor marker scroll caret caret depth renderer renderer virtualization heading chunk.

- [x] block 28 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 28 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 28 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 28 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

Long line inside block 28: Virtualization heading checkbox ordinal caret fence cadence depth fence generation ancestor cycling cadence cadence buffer marker bullet scroll leaf marker soft fence soft heading checkbox cycling generation depth depth heading paragraph leaf sibling checkbox virtualization ordinal table document checkbox bullet checkbox depth continuation continuation ancestor marker leaf descendant chunk table soft preview ordinal reflow renderer soft reflow checkbox budget paragraph generation table fence paragraph parser sibling continuation generation marker debounce scroll blockquote virtualization nesting bullet soft buffer document indentation indentation cycling continuation blockquote budget fence marker wrap parser marker pane pane scroll reflow depth virtualization heading wrap chunk renderer blockquote descendant editor preview renderer paragraph parser pane buffer fence viewport blockquote ordinal paragraph reflow cadence heading nesting renderer preview generation budget leaf wrap pane checkbox ordinal chunk heading nesting nesting preview buffer ancestor bullet sibling buffer viewport heading checkbox buffer parser budget renderer generation preview chunk soft table viewport reflow scroll cycling pane wrap continuation indentation marker marker pane buffer.

### Bulk block 29

Block 29: Table soft pane reflow marker table editor generation reflow virtualization document descendant blockquote viewport cycling ancestor cycling pane preview nesting indentation pane.

- block 29 item with blocks
  - nested item

    ```json
    { "block": 29, "depth": 2, "note": "renderer" }
    ```

    > quoted note for block 29

    | key | value |
    | --- | --- |
    | block | 29 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 30

Block 30: Viewport debounce sibling virtualization depth descendant parser cadence fence ancestor generation debounce indentation paragraph indentation wrap buffer descendant table nesting debounce descendant.

- block 30 straight ladder, level 1
  - block 30 straight ladder, level 2
    - block 30 straight ladder, level 3
      - block 30 straight ladder, level 4
        - block 30 straight ladder, level 5
          - block 30 straight ladder, level 6
            - block 30 straight ladder, level 7
              - block 30 straight ladder, level 8
                - block 30 straight ladder, level 9
                  - block 30 straight ladder, level 10

### Bulk block 31

Block 31: Checkbox sibling blockquote anchor document virtualization sibling marker reflow generation soft soft cadence editor debounce renderer buffer checkbox virtualization editor parser continuation.

- block 31 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 31 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 31 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 32

Block 32: Continuation virtualization sibling ordinal preview sibling chunk continuation scroll ancestor renderer blockquote continuation document viewport scroll fence buffer generation heading ordinal renderer.

1. block 32 alternating level 1
   - block 32 alternating level 2
      1. block 32 alternating level 3
         - block 32 alternating level 4
            1. block 32 alternating level 5
               - block 32 alternating level 6
                  1. block 32 alternating level 7
                     - block 32 alternating level 8

                       Continuation paragraph at the bottom of block 32. Bullet indentation marker depth cycling virtualization depth sibling caret ordinal generation continuation debounce generation paragraph soft.

### Bulk block 33

Block 33: Checkbox ordinal nesting chunk ancestor chunk table depth continuation cadence table table table preview caret editor virtualization cadence paragraph cadence anchor preview.

- [x] block 33 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 33 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 33 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 33 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 34

Block 34: Heading budget depth table document budget table budget blockquote nesting scroll marker indentation renderer cycling cycling paragraph generation soft cycling leaf reflow.

- block 34 item with blocks
  - nested item

    ```json
    { "block": 34, "depth": 2, "note": "depth" }
    ```

    > quoted note for block 34

    | key | value |
    | --- | --- |
    | block | 34 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 35

Block 35: Indentation preview descendant indentation nesting blockquote bullet buffer indentation ordinal nesting cycling sibling checkbox heading scroll cycling leaf checkbox document paragraph marker.

- block 35 straight ladder, level 1
  - block 35 straight ladder, level 2
    - block 35 straight ladder, level 3
      - block 35 straight ladder, level 4
        - block 35 straight ladder, level 5
          - block 35 straight ladder, level 6
            - block 35 straight ladder, level 7
              - block 35 straight ladder, level 8
                - block 35 straight ladder, level 9
                  - block 35 straight ladder, level 10

Long line inside block 35: Buffer marker virtualization cycling parser editor debounce editor debounce ancestor heading soft renderer chunk ordinal reflow depth debounce continuation reflow bullet depth chunk marker fence scroll cadence heading ordinal marker indentation indentation debounce fence pane preview ancestor continuation viewport editor nesting document indentation anchor bullet buffer document cadence nesting nesting anchor blockquote blockquote document blockquote chunk reflow indentation parser viewport bullet document blockquote soft marker cycling paragraph ancestor ancestor ancestor ancestor document pane checkbox scroll ordinal checkbox generation ordinal bullet bullet viewport cycling soft leaf wrap soft continuation editor buffer continuation wrap ordinal checkbox wrap descendant preview chunk continuation pane generation ordinal checkbox bullet leaf cycling reflow wrap leaf editor depth parser marker depth checkbox parser heading debounce debounce marker continuation fence wrap paragraph paragraph caret nesting checkbox document pane blockquote debounce depth debounce continuation chunk leaf pane ordinal cycling renderer table soft parser viewport virtualization soft cadence marker soft parser document cadence indentation scroll reflow chunk sibling fence document.

### Bulk block 36

Block 36: Preview leaf cadence bullet budget debounce budget depth renderer leaf viewport chunk ancestor fence pane renderer descendant fence depth cycling blockquote paragraph.

- block 36 branch 1
  - branch 1.1
    - branch 1.1.1
      - branch 1.1.1 leaf, level 4
    - branch 1.1.2
      - branch 1.1.2 leaf, level 4
  - branch 1.2
    - branch 1.2.1
      - branch 1.2.1 leaf, level 4
    - branch 1.2.2
      - branch 1.2.2 leaf, level 4
  - branch 1.3
    - branch 1.3.1
      - branch 1.3.1 leaf, level 4
    - branch 1.3.2
      - branch 1.3.2 leaf, level 4
- block 36 branch 2
  - branch 2.1
    - branch 2.1.1
      - branch 2.1.1 leaf, level 4
    - branch 2.1.2
      - branch 2.1.2 leaf, level 4
  - branch 2.2
    - branch 2.2.1
      - branch 2.2.1 leaf, level 4
    - branch 2.2.2
      - branch 2.2.2 leaf, level 4
  - branch 2.3
    - branch 2.3.1
      - branch 2.3.1 leaf, level 4
    - branch 2.3.2
      - branch 2.3.2 leaf, level 4
- block 36 branch 3
  - branch 3.1
    - branch 3.1.1
      - branch 3.1.1 leaf, level 4
    - branch 3.1.2
      - branch 3.1.2 leaf, level 4
  - branch 3.2
    - branch 3.2.1
      - branch 3.2.1 leaf, level 4
    - branch 3.2.2
      - branch 3.2.2 leaf, level 4
  - branch 3.3
    - branch 3.3.1
      - branch 3.3.1 leaf, level 4
    - branch 3.3.2
      - branch 3.3.2 leaf, level 4

### Bulk block 37

Block 37: Bullet reflow cadence parser chunk descendant descendant cadence parser table scroll nesting reflow fence scroll indentation continuation document nesting anchor fence checkbox.

1. block 37 alternating level 1
   - block 37 alternating level 2
      1. block 37 alternating level 3
         - block 37 alternating level 4
            1. block 37 alternating level 5
               - block 37 alternating level 6
                  1. block 37 alternating level 7
                     - block 37 alternating level 8

                       Continuation paragraph at the bottom of block 37. Renderer cycling ordinal depth document table debounce leaf leaf parser depth heading renderer indentation leaf marker.

### Bulk block 38

Block 38: Ancestor soft reflow marker pane bullet depth document budget leaf wrap cycling heading paragraph wrap soft editor depth debounce descendant soft bullet.

- [x] block 38 task 1
  - [ ] task 1 subtask
    - [ ] task 1 sub-subtask
      - [ ] task 1 level 4
- [ ] block 38 task 2
  - [ ] task 2 subtask
    - [x] task 2 sub-subtask
      - [ ] task 2 level 4
- [x] block 38 task 3
  - [ ] task 3 subtask
    - [ ] task 3 sub-subtask
      - [ ] task 3 level 4
- [ ] block 38 task 4
  - [ ] task 4 subtask
    - [ ] task 4 sub-subtask
      - [ ] task 4 level 4

### Bulk block 39

Block 39: Viewport ordinal cycling virtualization parser cadence renderer document descendant anchor cycling document paragraph reflow marker soft wrap cadence checkbox wrap debounce checkbox.

- block 39 item with blocks
  - nested item

    ```json
    { "block": 39, "depth": 2, "note": "reflow" }
    ```

    > quoted note for block 39

    | key | value |
    | --- | --- |
    | block | 39 |
    | shape | 4 |

    - deeper item, level 3
      - deeper still, level 4
        - level 5

### Bulk block 40

Block 40: Heading wrap ordinal wrap heading scroll document scroll cycling budget document marker continuation buffer fence document budget soft cycling parser reflow generation.

- block 40 straight ladder, level 1
  - block 40 straight ladder, level 2
    - block 40 straight ladder, level 3
      - block 40 straight ladder, level 4
        - block 40 straight ladder, level 5
          - block 40 straight ladder, level 6
            - block 40 straight ladder, level 7
              - block 40 straight ladder, level 8
                - block 40 straight ladder, level 9
                  - block 40 straight ladder, level 10

## End

End of the nested list stress test. Maximum nesting depth reached: 16.
If you scrolled here in the editor without a stall or a blank preview, both the
chunked parser and the virtualized editor survived the document.

