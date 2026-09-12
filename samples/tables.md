---
title: Table rendering and alignment QA
purpose: manual QA for GFM tables, column alignment and monospace cell width
---

# Table torture test

Open this file with the editor and preview side by side. Tables are the one
GFM block where the raw text is supposed to look like the rendered output, so
both panes carry signal: the preview shows whether alignment and overflow
work, and the editor shows whether the monospace cell model agrees with the
font it is drawing with.

What to look for:

- **Alignment** — a `:--` column hugs the left edge, `--:` the right, `:-:`
  centres. A column with no colons follows the renderer's default (left, in
  GFM). Cells of differing length in the same column make this visible.
- **Overflow** — a 40-column table must scroll inside its own container. If
  it stretches the page, pushes the preview's right edge off screen, or makes
  the whole document scroll sideways, that is the bug.
- **Progressive rendering** — the 2,000-row table should paint its first
  screen quickly and fill in; it should never block the editor or leave the
  preview blank.
- **Column width negotiation** — section 5 puts a 400-character unbroken
  string next to a two-character cell. Something has to give; nothing should
  overlap or get clipped without a scrollbar.
- **Cell width drift** — section 8 is the most useful signal in this file.
  Those tables are hand-padded so every column is the same visual width in a
  monospace context. If the `|` characters wander in the editor pane, the
  editor's cell model disagrees with the font.
- **Malformed input** — sections 6 and 10 must never crash the preview or
  blank the pane. Degrading to plain paragraphs is a fine outcome.

| Section | What it tests | Correct rendering looks like |
| --- | --- | --- |
| 1. Basics | Pipes, delimiter rows, degenerate shapes | Every variant renders as a real `<table>` |
| 2. Alignment | `:--`, `:-:`, `--:`, default | Cell text sits where the colons say |
| 3. Many columns | 10, 20 and 40 columns | Table scrolls horizontally, page layout intact |
| 4. Very long tables | ~500 and ~2,000 rows | Smooth scroll, fast first paint, no blank pane |
| 5. Wide cells | 400-char strings, long URLs, prose | Sane column widths, no clipping or overlap |
| 6. Uneven / ragged | Too few, too many, empty cells | Missing cells blank, extra cells dropped |
| 7. Inline content | Emphasis, code, links, `<br>`, escaped pipes | Inline markup renders inside cells |
| 8. Emoji and multibyte | Emoji, CJK, combining marks, RTL, full-width | Columns stay put in both panes |
| 9. Nested and adjacent | Lists, quotes, `<details>`, touching blocks | Each table stays its own table |
| 10. Not tables | Pipes that must stay prose or code | No `<table>` element at all |

---

## 1. Basics

Every table in this section should render as a table. They differ only in
surface syntax: outer pipes, delimiter length, and how few rows or columns a
table can get away with.

### 1.1 Plain table with outer pipes

| Name | Role | Location |
| --- | --- | --- |
| Ada Lovelace | Analyst | London |
| Grace Hopper | Rear Admiral | Arlington |
| Alan Turing | Cryptanalyst | Bletchley Park |

### 1.2 The same table without outer pipes

Leading and trailing pipes are optional in GFM. This should render
identically to 1.1.

Name | Role | Location
--- | --- | ---
Ada Lovelace | Analyst | London
Grace Hopper | Rear Admiral | Arlington
Alan Turing | Cryptanalyst | Bletchley Park

### 1.3 Mixed — outer pipes on some rows only

Rows may disagree about outer pipes. All four rows belong to one table.

| Column A | Column B |
--- | ---
| leading and trailing | leading and trailing |
no pipes at all | no pipes at all
| leading only | trailing only |

### 1.4 Minimal delimiter rows

One dash per column is the legal minimum.

| A | B | C |
|-|-|-|
| one | two | three |

With colons, still one dash:

| left | centre | right |
|:-|:-:|-:|
| a | b | c |
| a much longer cell | a much longer cell | a much longer cell |

Long runs of dashes — cosmetic only, same result:

| A | B | C |
| ------------------------------ | ------------------------------ | ------------------------------ |
| one | two | three |

Absurdly long runs, mixed with short ones in the same delimiter row:

| A | B | C |
| - | ---------------------------------------------------------------------------------------------- | --- |
| short delimiter | very long delimiter | medium delimiter |

Delimiter cells padded with extra spaces:

|   A   |   B   |
|   ---   |   :---:   |
| padded | delimiter |

### 1.5 Single-column table

| Only column |
| --- |
| first row |
| second row |
| third row |

The same, without outer pipes — this one is ambiguous in some parsers because
a row with no pipe at all is just a paragraph. With a leading pipe on the
delimiter row it should still be a table:

| Only column
| ---
| first row
| second row

### 1.6 Single-row table

One header, one body row.

| Key | Value |
| --- | --- |
| the only row | the only value |

### 1.7 Header-only table, no body rows

A header plus a delimiter row and nothing else is a valid table with an empty
`<tbody>`. It should render as a lone header row, not as a paragraph.

| Header one | Header two | Header three |
| --- | --- | --- |

Single-column header-only table:

| Lonely header |
| --- |

### 1.8 One column, one row, header only

The smallest table that can exist.

| x |
| - |

---

## 2. Alignment

Each table mixes short and long cells in the same column so the alignment is
actually visible. A column whose cells are all the same length proves nothing.

### 2.1 Default alignment (no colons)

GFM leaves these to the renderer's default, which is left in every common
implementation.

| Item | Description | Count |
| --- | --- | --- |
| a | x | 1 |
| a considerably longer item name | a description that runs on for a while | 1000000 |
| mid | medium length text | 42 |

### 2.2 Left aligned

| Item | Description | Count |
| :--- | :--- | :--- |
| a | x | 1 |
| a considerably longer item name | a description that runs on for a while | 1000000 |
| mid | medium length text | 42 |

### 2.3 Centre aligned

| Item | Description | Count |
| :---: | :---: | :---: |
| a | x | 1 |
| a considerably longer item name | a description that runs on for a while | 1000000 |
| mid | medium length text | 42 |

### 2.4 Right aligned

| Item | Description | Count |
| ---: | ---: | ---: |
| a | x | 1 |
| a considerably longer item name | a description that runs on for a while | 1000000 |
| mid | medium length text | 42 |

### 2.5 Every column a different alignment

Left, centre, right, default — in that order. The header cells should follow
the same alignment as the body cells.

| left | centre | right | default |
| :--- | :---: | ---: | --- |
| L | C | R | D |
| left aligned long cell | centre aligned long cell | right aligned long cell | default aligned long cell |
| ~ | ~~ | ~~~ | ~~~~ |
| 1 | 22 | 333 | 4444 |
| 99999999 | 8888888 | 777777 | 66666 |

### 2.6 Alignment is the only difference

All four columns hold identical content. If the columns look the same, the
delimiter row's colons are being ignored.

| same | same | same | same |
| :--- | :---: | ---: | --- |
| short | short | short | short |
| a noticeably longer cell | a noticeably longer cell | a noticeably longer cell | a noticeably longer cell |
| mid length | mid length | mid length | mid length |
| x | x | x | x |

### 2.7 Numeric column, right aligned

The common real-world case: right-aligned numbers should line up on their
last digit.

| Metric | Value | Delta |
| :--- | ---: | ---: |
| requests | 1 | +0 |
| errors | 27 | -3 |
| bytes in | 1048576 | +65536 |
| bytes out | 12 | -1 |
| p99 latency (ms) | 1843.25 | +0.75 |
| uptime (s) | 9007199254740991 | +1 |

### 2.8 Alignment with empty cells

An empty cell should not change the column's alignment for the cells around it.

| left | centre | right |
| :--- | :---: | ---: |
| filled | | filled |
| | filled | |
| a long left cell | a long centre cell | a long right cell |

---

## 3. Many columns

These exist to break horizontal layout. In every case the table itself should
get a horizontal scrollbar; the preview pane and the app window should not.
Check that the file tree and the editor stay where they are.

### 3.1 Ten columns

Ten narrow columns. Probably still fits in a wide window.

| c01 | c02 | c03 | c04 | c05 | c06 | c07 | c08 | c09 | c10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1.1 | r1.2 | r1.3 | r1.4 | r1.5 | r1.6 | r1.7 | r1.8 | r1.9 | r1.10 |
| r2.1 | r2.2 | r2.3 | r2.4 | r2.5 | r2.6 | r2.7 | r2.8 | r2.9 | r2.10 |
| r3.1 | r3.2 | r3.3 | r3.4 | r3.5 | r3.6 | r3.7 | r3.8 | r3.9 | r3.10 |
| r4.1 | r4.2 | r4.3 | r4.4 | r4.5 | r4.6 | r4.7 | r4.8 | r4.9 | r4.10 |
| r5.1 | r5.2 | r5.3 | r5.4 | r5.5 | r5.6 | r5.7 | r5.8 | r5.9 | r5.10 |

### 3.2 Twenty columns

Twenty columns will not fit. The table must scroll on its own.

| c01 | c02 | c03 | c04 | c05 | c06 | c07 | c08 | c09 | c10 | c11 | c12 | c13 | c14 | c15 | c16 | c17 | c18 | c19 | c20 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1.1 | r1.2 | r1.3 | r1.4 | r1.5 | r1.6 | r1.7 | r1.8 | r1.9 | r1.10 | r1.11 | r1.12 | r1.13 | r1.14 | r1.15 | r1.16 | r1.17 | r1.18 | r1.19 | r1.20 |
| r2.1 | r2.2 | r2.3 | r2.4 | r2.5 | r2.6 | r2.7 | r2.8 | r2.9 | r2.10 | r2.11 | r2.12 | r2.13 | r2.14 | r2.15 | r2.16 | r2.17 | r2.18 | r2.19 | r2.20 |
| r3.1 | r3.2 | r3.3 | r3.4 | r3.5 | r3.6 | r3.7 | r3.8 | r3.9 | r3.10 | r3.11 | r3.12 | r3.13 | r3.14 | r3.15 | r3.16 | r3.17 | r3.18 | r3.19 | r3.20 |
| r4.1 | r4.2 | r4.3 | r4.4 | r4.5 | r4.6 | r4.7 | r4.8 | r4.9 | r4.10 | r4.11 | r4.12 | r4.13 | r4.14 | r4.15 | r4.16 | r4.17 | r4.18 | r4.19 | r4.20 |
| r5.1 | r5.2 | r5.3 | r5.4 | r5.5 | r5.6 | r5.7 | r5.8 | r5.9 | r5.10 | r5.11 | r5.12 | r5.13 | r5.14 | r5.15 | r5.16 | r5.17 | r5.18 | r5.19 | r5.20 |

### 3.3 Forty columns

Forty columns, and the last column is far off screen. Scroll the table all the way right and confirm `c40` is reachable and the header scrolls with the body.

| c01 | c02 | c03 | c04 | c05 | c06 | c07 | c08 | c09 | c10 | c11 | c12 | c13 | c14 | c15 | c16 | c17 | c18 | c19 | c20 | c21 | c22 | c23 | c24 | c25 | c26 | c27 | c28 | c29 | c30 | c31 | c32 | c33 | c34 | c35 | c36 | c37 | c38 | c39 | c40 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1.1 | r1.2 | r1.3 | r1.4 | r1.5 | r1.6 | r1.7 | r1.8 | r1.9 | r1.10 | r1.11 | r1.12 | r1.13 | r1.14 | r1.15 | r1.16 | r1.17 | r1.18 | r1.19 | r1.20 | r1.21 | r1.22 | r1.23 | r1.24 | r1.25 | r1.26 | r1.27 | r1.28 | r1.29 | r1.30 | r1.31 | r1.32 | r1.33 | r1.34 | r1.35 | r1.36 | r1.37 | r1.38 | r1.39 | r1.40 |
| r2.1 | r2.2 | r2.3 | r2.4 | r2.5 | r2.6 | r2.7 | r2.8 | r2.9 | r2.10 | r2.11 | r2.12 | r2.13 | r2.14 | r2.15 | r2.16 | r2.17 | r2.18 | r2.19 | r2.20 | r2.21 | r2.22 | r2.23 | r2.24 | r2.25 | r2.26 | r2.27 | r2.28 | r2.29 | r2.30 | r2.31 | r2.32 | r2.33 | r2.34 | r2.35 | r2.36 | r2.37 | r2.38 | r2.39 | r2.40 |
| r3.1 | r3.2 | r3.3 | r3.4 | r3.5 | r3.6 | r3.7 | r3.8 | r3.9 | r3.10 | r3.11 | r3.12 | r3.13 | r3.14 | r3.15 | r3.16 | r3.17 | r3.18 | r3.19 | r3.20 | r3.21 | r3.22 | r3.23 | r3.24 | r3.25 | r3.26 | r3.27 | r3.28 | r3.29 | r3.30 | r3.31 | r3.32 | r3.33 | r3.34 | r3.35 | r3.36 | r3.37 | r3.38 | r3.39 | r3.40 |
| r4.1 | r4.2 | r4.3 | r4.4 | r4.5 | r4.6 | r4.7 | r4.8 | r4.9 | r4.10 | r4.11 | r4.12 | r4.13 | r4.14 | r4.15 | r4.16 | r4.17 | r4.18 | r4.19 | r4.20 | r4.21 | r4.22 | r4.23 | r4.24 | r4.25 | r4.26 | r4.27 | r4.28 | r4.29 | r4.30 | r4.31 | r4.32 | r4.33 | r4.34 | r4.35 | r4.36 | r4.37 | r4.38 | r4.39 | r4.40 |
| r5.1 | r5.2 | r5.3 | r5.4 | r5.5 | r5.6 | r5.7 | r5.8 | r5.9 | r5.10 | r5.11 | r5.12 | r5.13 | r5.14 | r5.15 | r5.16 | r5.17 | r5.18 | r5.19 | r5.20 | r5.21 | r5.22 | r5.23 | r5.24 | r5.25 | r5.26 | r5.27 | r5.28 | r5.29 | r5.30 | r5.31 | r5.32 | r5.33 | r5.34 | r5.35 | r5.36 | r5.37 | r5.38 | r5.39 | r5.40 |

### 3.4 Forty columns with mixed alignment

The same shape, cycling left / centre / right / default across the columns,
with cells of varying length so the alignment survives the scroll.

| c01 | c02 | c03 | c04 | c05 | c06 | c07 | c08 | c09 | c10 | c11 | c12 | c13 | c14 | c15 | c16 | c17 | c18 | c19 | c20 | c21 | c22 | c23 | c24 | c25 | c26 | c27 | c28 | c29 | c30 | c31 | c32 | c33 | c34 | c35 | c36 | c37 | c38 | c39 | c40 |
| :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- | :--- | :---: | ---: | --- |
| x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 |
| ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here |
| 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell |
| 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x |
| a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab |
| medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 | ab | x | medium cell | a rather long cell here | 7 | 42424242 |

### 3.5 Wide columns and many of them

Twenty columns, each holding a full sentence. This is the worst case for
width negotiation combined with overflow.

| Column number 1 | Column number 2 | Column number 3 | Column number 4 | Column number 5 | Column number 6 | Column number 7 | Column number 8 | Column number 9 | Column number 10 | Column number 11 | Column number 12 | Column number 13 | Column number 14 | Column number 15 | Column number 16 | Column number 17 | Column number 18 | Column number 19 | Column number 20 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Row 1 cell 1 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 2 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 3 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 4 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 5 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 6 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 7 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 8 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 9 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 10 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 11 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 12 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 13 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 14 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 15 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 16 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 17 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 18 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 19 contains a complete sentence of prose so the column has something to negotiate over. | Row 1 cell 20 contains a complete sentence of prose so the column has something to negotiate over. |
| Row 2 cell 1 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 2 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 3 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 4 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 5 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 6 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 7 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 8 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 9 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 10 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 11 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 12 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 13 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 14 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 15 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 16 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 17 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 18 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 19 contains a complete sentence of prose so the column has something to negotiate over. | Row 2 cell 20 contains a complete sentence of prose so the column has something to negotiate over. |
| Row 3 cell 1 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 2 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 3 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 4 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 5 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 6 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 7 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 8 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 9 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 10 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 11 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 12 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 13 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 14 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 15 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 16 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 17 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 18 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 19 contains a complete sentence of prose so the column has something to negotiate over. | Row 3 cell 20 contains a complete sentence of prose so the column has something to negotiate over. |
| Row 4 cell 1 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 2 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 3 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 4 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 5 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 6 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 7 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 8 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 9 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 10 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 11 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 12 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 13 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 14 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 15 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 16 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 17 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 18 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 19 contains a complete sentence of prose so the column has something to negotiate over. | Row 4 cell 20 contains a complete sentence of prose so the column has something to negotiate over. |

---

## 4. Very long tables

Scroll these end to end. The header should stay a header, rows should not
shimmer or reflow as you scroll, and the last row should be reachable. If the
preview uses progressive rendering, the first screen should paint well before
the last row exists.

### 4.1 Roughly 500 rows

Five columns, 500 rows of synthetic run log. Content varies per row so a
rendering bug that duplicates or drops rows is visible.

| # | Service | Region | Status | Note |
| ---: | :--- | :--- | :---: | :--- |
| 1 | gateway | us-west-2 | retrying | DNS lookup retried twice |
| 2 | scheduler | af-south-1 | pending | backpressure from the upstream shard |
| 3 | renderer | eu-west-2 | warning | no change since the previous sweep |
| 4 | watcher | ap-south-1 | cancelled | config reloaded from disk |
| 5 | compactor | ap-northeast-3 | skipped | clock skew corrected against NTP |
| 6 | uploader | us-east-1 | error | disk watermark crossed, trimmed oldest segments |
| 7 | notifier | sa-east-1 | ok | queue drained without incident |
| 8 | reaper | eu-north-1 | retrying | certificate rotated |
| 9 | shipper | us-west-2 | pending | cold start took longer than the budget |
| 10 | resolver | af-south-1 | warning | manual intervention requested by the operator |
| 11 | cache | eu-west-2 | cancelled | leader election completed |
| 12 | indexer | ap-south-1 | skipped | restarted after a failed health check |
| 13 | gateway | ap-northeast-3 | error | DNS lookup retried twice |
| 14 | scheduler | us-east-1 | ok | backpressure from the upstream shard |
| 15 | renderer | sa-east-1 | retrying | no change since the previous sweep |
| 16 | watcher | eu-north-1 | pending | config reloaded from disk |
| 17 | compactor | us-west-2 | warning | clock skew corrected against NTP |
| 18 | uploader | af-south-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 19 | notifier | eu-west-2 | skipped | queue drained without incident |
| 20 | reaper | ap-south-1 | error | certificate rotated |
| 21 | shipper | ap-northeast-3 | ok | cold start took longer than the budget |
| 22 | resolver | us-east-1 | retrying | manual intervention requested by the operator |
| 23 | cache | sa-east-1 | pending | leader election completed |
| 24 | indexer | eu-north-1 | warning | restarted after a failed health check |
| 25 | gateway | us-west-2 | cancelled | DNS lookup retried twice |
| 26 | scheduler | af-south-1 | skipped | backpressure from the upstream shard |
| 27 | renderer | eu-west-2 | error | no change since the previous sweep |
| 28 | watcher | ap-south-1 | ok | config reloaded from disk |
| 29 | compactor | ap-northeast-3 | retrying | clock skew corrected against NTP |
| 30 | uploader | us-east-1 | pending | disk watermark crossed, trimmed oldest segments |
| 31 | notifier | sa-east-1 | warning | queue drained without incident |
| 32 | reaper | eu-north-1 | cancelled | certificate rotated |
| 33 | shipper | us-west-2 | skipped | cold start took longer than the budget |
| 34 | resolver | af-south-1 | error | manual intervention requested by the operator |
| 35 | cache | eu-west-2 | ok | leader election completed |
| 36 | indexer | ap-south-1 | retrying | restarted after a failed health check |
| 37 | gateway | ap-northeast-3 | pending | DNS lookup retried twice |
| 38 | scheduler | us-east-1 | warning | backpressure from the upstream shard |
| 39 | renderer | sa-east-1 | cancelled | no change since the previous sweep |
| 40 | watcher | eu-north-1 | skipped | config reloaded from disk |
| 41 | compactor | us-west-2 | error | clock skew corrected against NTP |
| 42 | uploader | af-south-1 | ok | disk watermark crossed, trimmed oldest segments |
| 43 | notifier | eu-west-2 | retrying | queue drained without incident |
| 44 | reaper | ap-south-1 | pending | certificate rotated |
| 45 | shipper | ap-northeast-3 | warning | cold start took longer than the budget |
| 46 | resolver | us-east-1 | cancelled | manual intervention requested by the operator |
| 47 | cache | sa-east-1 | skipped | leader election completed |
| 48 | indexer | eu-north-1 | error | restarted after a failed health check |
| 49 | gateway | us-west-2 | ok | DNS lookup retried twice |
| 50 | scheduler | af-south-1 | retrying | backpressure from the upstream shard |
| 51 | renderer | eu-west-2 | pending | no change since the previous sweep |
| 52 | watcher | ap-south-1 | warning | config reloaded from disk |
| 53 | compactor | ap-northeast-3 | cancelled | clock skew corrected against NTP |
| 54 | uploader | us-east-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 55 | notifier | sa-east-1 | error | queue drained without incident |
| 56 | reaper | eu-north-1 | ok | certificate rotated |
| 57 | shipper | us-west-2 | retrying | cold start took longer than the budget |
| 58 | resolver | af-south-1 | pending | manual intervention requested by the operator |
| 59 | cache | eu-west-2 | warning | leader election completed |
| 60 | indexer | ap-south-1 | cancelled | restarted after a failed health check |
| 61 | gateway | ap-northeast-3 | skipped | DNS lookup retried twice |
| 62 | scheduler | us-east-1 | error | backpressure from the upstream shard |
| 63 | renderer | sa-east-1 | ok | no change since the previous sweep |
| 64 | watcher | eu-north-1 | retrying | config reloaded from disk |
| 65 | compactor | us-west-2 | pending | clock skew corrected against NTP |
| 66 | uploader | af-south-1 | warning | disk watermark crossed, trimmed oldest segments |
| 67 | notifier | eu-west-2 | cancelled | queue drained without incident |
| 68 | reaper | ap-south-1 | skipped | certificate rotated |
| 69 | shipper | ap-northeast-3 | error | cold start took longer than the budget |
| 70 | resolver | us-east-1 | ok | manual intervention requested by the operator |
| 71 | cache | sa-east-1 | retrying | leader election completed |
| 72 | indexer | eu-north-1 | pending | restarted after a failed health check |
| 73 | gateway | us-west-2 | warning | DNS lookup retried twice |
| 74 | scheduler | af-south-1 | cancelled | backpressure from the upstream shard |
| 75 | renderer | eu-west-2 | skipped | no change since the previous sweep |
| 76 | watcher | ap-south-1 | error | config reloaded from disk |
| 77 | compactor | ap-northeast-3 | ok | clock skew corrected against NTP |
| 78 | uploader | us-east-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 79 | notifier | sa-east-1 | pending | queue drained without incident |
| 80 | reaper | eu-north-1 | warning | certificate rotated |
| 81 | shipper | us-west-2 | cancelled | cold start took longer than the budget |
| 82 | resolver | af-south-1 | skipped | manual intervention requested by the operator |
| 83 | cache | eu-west-2 | error | leader election completed |
| 84 | indexer | ap-south-1 | ok | restarted after a failed health check |
| 85 | gateway | ap-northeast-3 | retrying | DNS lookup retried twice |
| 86 | scheduler | us-east-1 | pending | backpressure from the upstream shard |
| 87 | renderer | sa-east-1 | warning | no change since the previous sweep |
| 88 | watcher | eu-north-1 | cancelled | config reloaded from disk |
| 89 | compactor | us-west-2 | skipped | clock skew corrected against NTP |
| 90 | uploader | af-south-1 | error | disk watermark crossed, trimmed oldest segments |
| 91 | notifier | eu-west-2 | ok | queue drained without incident |
| 92 | reaper | ap-south-1 | retrying | certificate rotated |
| 93 | shipper | ap-northeast-3 | pending | cold start took longer than the budget |
| 94 | resolver | us-east-1 | warning | manual intervention requested by the operator |
| 95 | cache | sa-east-1 | cancelled | leader election completed |
| 96 | indexer | eu-north-1 | skipped | restarted after a failed health check |
| 97 | gateway | us-west-2 | error | DNS lookup retried twice |
| 98 | scheduler | af-south-1 | ok | backpressure from the upstream shard |
| 99 | renderer | eu-west-2 | retrying | no change since the previous sweep |
| 100 | watcher | ap-south-1 | pending | config reloaded from disk |
| 101 | compactor | ap-northeast-3 | warning | clock skew corrected against NTP |
| 102 | uploader | us-east-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 103 | notifier | sa-east-1 | skipped | queue drained without incident |
| 104 | reaper | eu-north-1 | error | certificate rotated |
| 105 | shipper | us-west-2 | ok | cold start took longer than the budget |
| 106 | resolver | af-south-1 | retrying | manual intervention requested by the operator |
| 107 | cache | eu-west-2 | pending | leader election completed |
| 108 | indexer | ap-south-1 | warning | restarted after a failed health check |
| 109 | gateway | ap-northeast-3 | cancelled | DNS lookup retried twice |
| 110 | scheduler | us-east-1 | skipped | backpressure from the upstream shard |
| 111 | renderer | sa-east-1 | error | no change since the previous sweep |
| 112 | watcher | eu-north-1 | ok | config reloaded from disk |
| 113 | compactor | us-west-2 | retrying | clock skew corrected against NTP |
| 114 | uploader | af-south-1 | pending | disk watermark crossed, trimmed oldest segments |
| 115 | notifier | eu-west-2 | warning | queue drained without incident |
| 116 | reaper | ap-south-1 | cancelled | certificate rotated |
| 117 | shipper | ap-northeast-3 | skipped | cold start took longer than the budget |
| 118 | resolver | us-east-1 | error | manual intervention requested by the operator |
| 119 | cache | sa-east-1 | ok | leader election completed |
| 120 | indexer | eu-north-1 | retrying | restarted after a failed health check |
| 121 | gateway | us-west-2 | pending | DNS lookup retried twice |
| 122 | scheduler | af-south-1 | warning | backpressure from the upstream shard |
| 123 | renderer | eu-west-2 | cancelled | no change since the previous sweep |
| 124 | watcher | ap-south-1 | skipped | config reloaded from disk |
| 125 | compactor | ap-northeast-3 | error | clock skew corrected against NTP |
| 126 | uploader | us-east-1 | ok | disk watermark crossed, trimmed oldest segments |
| 127 | notifier | sa-east-1 | retrying | queue drained without incident |
| 128 | reaper | eu-north-1 | pending | certificate rotated |
| 129 | shipper | us-west-2 | warning | cold start took longer than the budget |
| 130 | resolver | af-south-1 | cancelled | manual intervention requested by the operator |
| 131 | cache | eu-west-2 | skipped | leader election completed |
| 132 | indexer | ap-south-1 | error | restarted after a failed health check |
| 133 | gateway | ap-northeast-3 | ok | DNS lookup retried twice |
| 134 | scheduler | us-east-1 | retrying | backpressure from the upstream shard |
| 135 | renderer | sa-east-1 | pending | no change since the previous sweep |
| 136 | watcher | eu-north-1 | warning | config reloaded from disk |
| 137 | compactor | us-west-2 | cancelled | clock skew corrected against NTP |
| 138 | uploader | af-south-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 139 | notifier | eu-west-2 | error | queue drained without incident |
| 140 | reaper | ap-south-1 | ok | certificate rotated |
| 141 | shipper | ap-northeast-3 | retrying | cold start took longer than the budget |
| 142 | resolver | us-east-1 | pending | manual intervention requested by the operator |
| 143 | cache | sa-east-1 | warning | leader election completed |
| 144 | indexer | eu-north-1 | cancelled | restarted after a failed health check |
| 145 | gateway | us-west-2 | skipped | DNS lookup retried twice |
| 146 | scheduler | af-south-1 | error | backpressure from the upstream shard |
| 147 | renderer | eu-west-2 | ok | no change since the previous sweep |
| 148 | watcher | ap-south-1 | retrying | config reloaded from disk |
| 149 | compactor | ap-northeast-3 | pending | clock skew corrected against NTP |
| 150 | uploader | us-east-1 | warning | disk watermark crossed, trimmed oldest segments |
| 151 | notifier | sa-east-1 | cancelled | queue drained without incident |
| 152 | reaper | eu-north-1 | skipped | certificate rotated |
| 153 | shipper | us-west-2 | error | cold start took longer than the budget |
| 154 | resolver | af-south-1 | ok | manual intervention requested by the operator |
| 155 | cache | eu-west-2 | retrying | leader election completed |
| 156 | indexer | ap-south-1 | pending | restarted after a failed health check |
| 157 | gateway | ap-northeast-3 | warning | DNS lookup retried twice |
| 158 | scheduler | us-east-1 | cancelled | backpressure from the upstream shard |
| 159 | renderer | sa-east-1 | skipped | no change since the previous sweep |
| 160 | watcher | eu-north-1 | error | config reloaded from disk |
| 161 | compactor | us-west-2 | ok | clock skew corrected against NTP |
| 162 | uploader | af-south-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 163 | notifier | eu-west-2 | pending | queue drained without incident |
| 164 | reaper | ap-south-1 | warning | certificate rotated |
| 165 | shipper | ap-northeast-3 | cancelled | cold start took longer than the budget |
| 166 | resolver | us-east-1 | skipped | manual intervention requested by the operator |
| 167 | cache | sa-east-1 | error | leader election completed |
| 168 | indexer | eu-north-1 | ok | restarted after a failed health check |
| 169 | gateway | us-west-2 | retrying | DNS lookup retried twice |
| 170 | scheduler | af-south-1 | pending | backpressure from the upstream shard |
| 171 | renderer | eu-west-2 | warning | no change since the previous sweep |
| 172 | watcher | ap-south-1 | cancelled | config reloaded from disk |
| 173 | compactor | ap-northeast-3 | skipped | clock skew corrected against NTP |
| 174 | uploader | us-east-1 | error | disk watermark crossed, trimmed oldest segments |
| 175 | notifier | sa-east-1 | ok | queue drained without incident |
| 176 | reaper | eu-north-1 | retrying | certificate rotated |
| 177 | shipper | us-west-2 | pending | cold start took longer than the budget |
| 178 | resolver | af-south-1 | warning | manual intervention requested by the operator |
| 179 | cache | eu-west-2 | cancelled | leader election completed |
| 180 | indexer | ap-south-1 | skipped | restarted after a failed health check |
| 181 | gateway | ap-northeast-3 | error | DNS lookup retried twice |
| 182 | scheduler | us-east-1 | ok | backpressure from the upstream shard |
| 183 | renderer | sa-east-1 | retrying | no change since the previous sweep |
| 184 | watcher | eu-north-1 | pending | config reloaded from disk |
| 185 | compactor | us-west-2 | warning | clock skew corrected against NTP |
| 186 | uploader | af-south-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 187 | notifier | eu-west-2 | skipped | queue drained without incident |
| 188 | reaper | ap-south-1 | error | certificate rotated |
| 189 | shipper | ap-northeast-3 | ok | cold start took longer than the budget |
| 190 | resolver | us-east-1 | retrying | manual intervention requested by the operator |
| 191 | cache | sa-east-1 | pending | leader election completed |
| 192 | indexer | eu-north-1 | warning | restarted after a failed health check |
| 193 | gateway | us-west-2 | cancelled | DNS lookup retried twice |
| 194 | scheduler | af-south-1 | skipped | backpressure from the upstream shard |
| 195 | renderer | eu-west-2 | error | no change since the previous sweep |
| 196 | watcher | ap-south-1 | ok | config reloaded from disk |
| 197 | compactor | ap-northeast-3 | retrying | clock skew corrected against NTP |
| 198 | uploader | us-east-1 | pending | disk watermark crossed, trimmed oldest segments |
| 199 | notifier | sa-east-1 | warning | queue drained without incident |
| 200 | reaper | eu-north-1 | cancelled | certificate rotated |
| 201 | shipper | us-west-2 | skipped | cold start took longer than the budget |
| 202 | resolver | af-south-1 | error | manual intervention requested by the operator |
| 203 | cache | eu-west-2 | ok | leader election completed |
| 204 | indexer | ap-south-1 | retrying | restarted after a failed health check |
| 205 | gateway | ap-northeast-3 | pending | DNS lookup retried twice |
| 206 | scheduler | us-east-1 | warning | backpressure from the upstream shard |
| 207 | renderer | sa-east-1 | cancelled | no change since the previous sweep |
| 208 | watcher | eu-north-1 | skipped | config reloaded from disk |
| 209 | compactor | us-west-2 | error | clock skew corrected against NTP |
| 210 | uploader | af-south-1 | ok | disk watermark crossed, trimmed oldest segments |
| 211 | notifier | eu-west-2 | retrying | queue drained without incident |
| 212 | reaper | ap-south-1 | pending | certificate rotated |
| 213 | shipper | ap-northeast-3 | warning | cold start took longer than the budget |
| 214 | resolver | us-east-1 | cancelled | manual intervention requested by the operator |
| 215 | cache | sa-east-1 | skipped | leader election completed |
| 216 | indexer | eu-north-1 | error | restarted after a failed health check |
| 217 | gateway | us-west-2 | ok | DNS lookup retried twice |
| 218 | scheduler | af-south-1 | retrying | backpressure from the upstream shard |
| 219 | renderer | eu-west-2 | pending | no change since the previous sweep |
| 220 | watcher | ap-south-1 | warning | config reloaded from disk |
| 221 | compactor | ap-northeast-3 | cancelled | clock skew corrected against NTP |
| 222 | uploader | us-east-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 223 | notifier | sa-east-1 | error | queue drained without incident |
| 224 | reaper | eu-north-1 | ok | certificate rotated |
| 225 | shipper | us-west-2 | retrying | cold start took longer than the budget |
| 226 | resolver | af-south-1 | pending | manual intervention requested by the operator |
| 227 | cache | eu-west-2 | warning | leader election completed |
| 228 | indexer | ap-south-1 | cancelled | restarted after a failed health check |
| 229 | gateway | ap-northeast-3 | skipped | DNS lookup retried twice |
| 230 | scheduler | us-east-1 | error | backpressure from the upstream shard |
| 231 | renderer | sa-east-1 | ok | no change since the previous sweep |
| 232 | watcher | eu-north-1 | retrying | config reloaded from disk |
| 233 | compactor | us-west-2 | pending | clock skew corrected against NTP |
| 234 | uploader | af-south-1 | warning | disk watermark crossed, trimmed oldest segments |
| 235 | notifier | eu-west-2 | cancelled | queue drained without incident |
| 236 | reaper | ap-south-1 | skipped | certificate rotated |
| 237 | shipper | ap-northeast-3 | error | cold start took longer than the budget |
| 238 | resolver | us-east-1 | ok | manual intervention requested by the operator |
| 239 | cache | sa-east-1 | retrying | leader election completed |
| 240 | indexer | eu-north-1 | pending | restarted after a failed health check |
| 241 | gateway | us-west-2 | warning | DNS lookup retried twice |
| 242 | scheduler | af-south-1 | cancelled | backpressure from the upstream shard |
| 243 | renderer | eu-west-2 | skipped | no change since the previous sweep |
| 244 | watcher | ap-south-1 | error | config reloaded from disk |
| 245 | compactor | ap-northeast-3 | ok | clock skew corrected against NTP |
| 246 | uploader | us-east-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 247 | notifier | sa-east-1 | pending | queue drained without incident |
| 248 | reaper | eu-north-1 | warning | certificate rotated |
| 249 | shipper | us-west-2 | cancelled | cold start took longer than the budget |
| 250 | resolver | af-south-1 | skipped | manual intervention requested by the operator |
| 251 | cache | eu-west-2 | error | leader election completed |
| 252 | indexer | ap-south-1 | ok | restarted after a failed health check |
| 253 | gateway | ap-northeast-3 | retrying | DNS lookup retried twice |
| 254 | scheduler | us-east-1 | pending | backpressure from the upstream shard |
| 255 | renderer | sa-east-1 | warning | no change since the previous sweep |
| 256 | watcher | eu-north-1 | cancelled | config reloaded from disk |
| 257 | compactor | us-west-2 | skipped | clock skew corrected against NTP |
| 258 | uploader | af-south-1 | error | disk watermark crossed, trimmed oldest segments |
| 259 | notifier | eu-west-2 | ok | queue drained without incident |
| 260 | reaper | ap-south-1 | retrying | certificate rotated |
| 261 | shipper | ap-northeast-3 | pending | cold start took longer than the budget |
| 262 | resolver | us-east-1 | warning | manual intervention requested by the operator |
| 263 | cache | sa-east-1 | cancelled | leader election completed |
| 264 | indexer | eu-north-1 | skipped | restarted after a failed health check |
| 265 | gateway | us-west-2 | error | DNS lookup retried twice |
| 266 | scheduler | af-south-1 | ok | backpressure from the upstream shard |
| 267 | renderer | eu-west-2 | retrying | no change since the previous sweep |
| 268 | watcher | ap-south-1 | pending | config reloaded from disk |
| 269 | compactor | ap-northeast-3 | warning | clock skew corrected against NTP |
| 270 | uploader | us-east-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 271 | notifier | sa-east-1 | skipped | queue drained without incident |
| 272 | reaper | eu-north-1 | error | certificate rotated |
| 273 | shipper | us-west-2 | ok | cold start took longer than the budget |
| 274 | resolver | af-south-1 | retrying | manual intervention requested by the operator |
| 275 | cache | eu-west-2 | pending | leader election completed |
| 276 | indexer | ap-south-1 | warning | restarted after a failed health check |
| 277 | gateway | ap-northeast-3 | cancelled | DNS lookup retried twice |
| 278 | scheduler | us-east-1 | skipped | backpressure from the upstream shard |
| 279 | renderer | sa-east-1 | error | no change since the previous sweep |
| 280 | watcher | eu-north-1 | ok | config reloaded from disk |
| 281 | compactor | us-west-2 | retrying | clock skew corrected against NTP |
| 282 | uploader | af-south-1 | pending | disk watermark crossed, trimmed oldest segments |
| 283 | notifier | eu-west-2 | warning | queue drained without incident |
| 284 | reaper | ap-south-1 | cancelled | certificate rotated |
| 285 | shipper | ap-northeast-3 | skipped | cold start took longer than the budget |
| 286 | resolver | us-east-1 | error | manual intervention requested by the operator |
| 287 | cache | sa-east-1 | ok | leader election completed |
| 288 | indexer | eu-north-1 | retrying | restarted after a failed health check |
| 289 | gateway | us-west-2 | pending | DNS lookup retried twice |
| 290 | scheduler | af-south-1 | warning | backpressure from the upstream shard |
| 291 | renderer | eu-west-2 | cancelled | no change since the previous sweep |
| 292 | watcher | ap-south-1 | skipped | config reloaded from disk |
| 293 | compactor | ap-northeast-3 | error | clock skew corrected against NTP |
| 294 | uploader | us-east-1 | ok | disk watermark crossed, trimmed oldest segments |
| 295 | notifier | sa-east-1 | retrying | queue drained without incident |
| 296 | reaper | eu-north-1 | pending | certificate rotated |
| 297 | shipper | us-west-2 | warning | cold start took longer than the budget |
| 298 | resolver | af-south-1 | cancelled | manual intervention requested by the operator |
| 299 | cache | eu-west-2 | skipped | leader election completed |
| 300 | indexer | ap-south-1 | error | restarted after a failed health check |
| 301 | gateway | ap-northeast-3 | ok | DNS lookup retried twice |
| 302 | scheduler | us-east-1 | retrying | backpressure from the upstream shard |
| 303 | renderer | sa-east-1 | pending | no change since the previous sweep |
| 304 | watcher | eu-north-1 | warning | config reloaded from disk |
| 305 | compactor | us-west-2 | cancelled | clock skew corrected against NTP |
| 306 | uploader | af-south-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 307 | notifier | eu-west-2 | error | queue drained without incident |
| 308 | reaper | ap-south-1 | ok | certificate rotated |
| 309 | shipper | ap-northeast-3 | retrying | cold start took longer than the budget |
| 310 | resolver | us-east-1 | pending | manual intervention requested by the operator |
| 311 | cache | sa-east-1 | warning | leader election completed |
| 312 | indexer | eu-north-1 | cancelled | restarted after a failed health check |
| 313 | gateway | us-west-2 | skipped | DNS lookup retried twice |
| 314 | scheduler | af-south-1 | error | backpressure from the upstream shard |
| 315 | renderer | eu-west-2 | ok | no change since the previous sweep |
| 316 | watcher | ap-south-1 | retrying | config reloaded from disk |
| 317 | compactor | ap-northeast-3 | pending | clock skew corrected against NTP |
| 318 | uploader | us-east-1 | warning | disk watermark crossed, trimmed oldest segments |
| 319 | notifier | sa-east-1 | cancelled | queue drained without incident |
| 320 | reaper | eu-north-1 | skipped | certificate rotated |
| 321 | shipper | us-west-2 | error | cold start took longer than the budget |
| 322 | resolver | af-south-1 | ok | manual intervention requested by the operator |
| 323 | cache | eu-west-2 | retrying | leader election completed |
| 324 | indexer | ap-south-1 | pending | restarted after a failed health check |
| 325 | gateway | ap-northeast-3 | warning | DNS lookup retried twice |
| 326 | scheduler | us-east-1 | cancelled | backpressure from the upstream shard |
| 327 | renderer | sa-east-1 | skipped | no change since the previous sweep |
| 328 | watcher | eu-north-1 | error | config reloaded from disk |
| 329 | compactor | us-west-2 | ok | clock skew corrected against NTP |
| 330 | uploader | af-south-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 331 | notifier | eu-west-2 | pending | queue drained without incident |
| 332 | reaper | ap-south-1 | warning | certificate rotated |
| 333 | shipper | ap-northeast-3 | cancelled | cold start took longer than the budget |
| 334 | resolver | us-east-1 | skipped | manual intervention requested by the operator |
| 335 | cache | sa-east-1 | error | leader election completed |
| 336 | indexer | eu-north-1 | ok | restarted after a failed health check |
| 337 | gateway | us-west-2 | retrying | DNS lookup retried twice |
| 338 | scheduler | af-south-1 | pending | backpressure from the upstream shard |
| 339 | renderer | eu-west-2 | warning | no change since the previous sweep |
| 340 | watcher | ap-south-1 | cancelled | config reloaded from disk |
| 341 | compactor | ap-northeast-3 | skipped | clock skew corrected against NTP |
| 342 | uploader | us-east-1 | error | disk watermark crossed, trimmed oldest segments |
| 343 | notifier | sa-east-1 | ok | queue drained without incident |
| 344 | reaper | eu-north-1 | retrying | certificate rotated |
| 345 | shipper | us-west-2 | pending | cold start took longer than the budget |
| 346 | resolver | af-south-1 | warning | manual intervention requested by the operator |
| 347 | cache | eu-west-2 | cancelled | leader election completed |
| 348 | indexer | ap-south-1 | skipped | restarted after a failed health check |
| 349 | gateway | ap-northeast-3 | error | DNS lookup retried twice |
| 350 | scheduler | us-east-1 | ok | backpressure from the upstream shard |
| 351 | renderer | sa-east-1 | retrying | no change since the previous sweep |
| 352 | watcher | eu-north-1 | pending | config reloaded from disk |
| 353 | compactor | us-west-2 | warning | clock skew corrected against NTP |
| 354 | uploader | af-south-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 355 | notifier | eu-west-2 | skipped | queue drained without incident |
| 356 | reaper | ap-south-1 | error | certificate rotated |
| 357 | shipper | ap-northeast-3 | ok | cold start took longer than the budget |
| 358 | resolver | us-east-1 | retrying | manual intervention requested by the operator |
| 359 | cache | sa-east-1 | pending | leader election completed |
| 360 | indexer | eu-north-1 | warning | restarted after a failed health check |
| 361 | gateway | us-west-2 | cancelled | DNS lookup retried twice |
| 362 | scheduler | af-south-1 | skipped | backpressure from the upstream shard |
| 363 | renderer | eu-west-2 | error | no change since the previous sweep |
| 364 | watcher | ap-south-1 | ok | config reloaded from disk |
| 365 | compactor | ap-northeast-3 | retrying | clock skew corrected against NTP |
| 366 | uploader | us-east-1 | pending | disk watermark crossed, trimmed oldest segments |
| 367 | notifier | sa-east-1 | warning | queue drained without incident |
| 368 | reaper | eu-north-1 | cancelled | certificate rotated |
| 369 | shipper | us-west-2 | skipped | cold start took longer than the budget |
| 370 | resolver | af-south-1 | error | manual intervention requested by the operator |
| 371 | cache | eu-west-2 | ok | leader election completed |
| 372 | indexer | ap-south-1 | retrying | restarted after a failed health check |
| 373 | gateway | ap-northeast-3 | pending | DNS lookup retried twice |
| 374 | scheduler | us-east-1 | warning | backpressure from the upstream shard |
| 375 | renderer | sa-east-1 | cancelled | no change since the previous sweep |
| 376 | watcher | eu-north-1 | skipped | config reloaded from disk |
| 377 | compactor | us-west-2 | error | clock skew corrected against NTP |
| 378 | uploader | af-south-1 | ok | disk watermark crossed, trimmed oldest segments |
| 379 | notifier | eu-west-2 | retrying | queue drained without incident |
| 380 | reaper | ap-south-1 | pending | certificate rotated |
| 381 | shipper | ap-northeast-3 | warning | cold start took longer than the budget |
| 382 | resolver | us-east-1 | cancelled | manual intervention requested by the operator |
| 383 | cache | sa-east-1 | skipped | leader election completed |
| 384 | indexer | eu-north-1 | error | restarted after a failed health check |
| 385 | gateway | us-west-2 | ok | DNS lookup retried twice |
| 386 | scheduler | af-south-1 | retrying | backpressure from the upstream shard |
| 387 | renderer | eu-west-2 | pending | no change since the previous sweep |
| 388 | watcher | ap-south-1 | warning | config reloaded from disk |
| 389 | compactor | ap-northeast-3 | cancelled | clock skew corrected against NTP |
| 390 | uploader | us-east-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 391 | notifier | sa-east-1 | error | queue drained without incident |
| 392 | reaper | eu-north-1 | ok | certificate rotated |
| 393 | shipper | us-west-2 | retrying | cold start took longer than the budget |
| 394 | resolver | af-south-1 | pending | manual intervention requested by the operator |
| 395 | cache | eu-west-2 | warning | leader election completed |
| 396 | indexer | ap-south-1 | cancelled | restarted after a failed health check |
| 397 | gateway | ap-northeast-3 | skipped | DNS lookup retried twice |
| 398 | scheduler | us-east-1 | error | backpressure from the upstream shard |
| 399 | renderer | sa-east-1 | ok | no change since the previous sweep |
| 400 | watcher | eu-north-1 | retrying | config reloaded from disk |
| 401 | compactor | us-west-2 | pending | clock skew corrected against NTP |
| 402 | uploader | af-south-1 | warning | disk watermark crossed, trimmed oldest segments |
| 403 | notifier | eu-west-2 | cancelled | queue drained without incident |
| 404 | reaper | ap-south-1 | skipped | certificate rotated |
| 405 | shipper | ap-northeast-3 | error | cold start took longer than the budget |
| 406 | resolver | us-east-1 | ok | manual intervention requested by the operator |
| 407 | cache | sa-east-1 | retrying | leader election completed |
| 408 | indexer | eu-north-1 | pending | restarted after a failed health check |
| 409 | gateway | us-west-2 | warning | DNS lookup retried twice |
| 410 | scheduler | af-south-1 | cancelled | backpressure from the upstream shard |
| 411 | renderer | eu-west-2 | skipped | no change since the previous sweep |
| 412 | watcher | ap-south-1 | error | config reloaded from disk |
| 413 | compactor | ap-northeast-3 | ok | clock skew corrected against NTP |
| 414 | uploader | us-east-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 415 | notifier | sa-east-1 | pending | queue drained without incident |
| 416 | reaper | eu-north-1 | warning | certificate rotated |
| 417 | shipper | us-west-2 | cancelled | cold start took longer than the budget |
| 418 | resolver | af-south-1 | skipped | manual intervention requested by the operator |
| 419 | cache | eu-west-2 | error | leader election completed |
| 420 | indexer | ap-south-1 | ok | restarted after a failed health check |
| 421 | gateway | ap-northeast-3 | retrying | DNS lookup retried twice |
| 422 | scheduler | us-east-1 | pending | backpressure from the upstream shard |
| 423 | renderer | sa-east-1 | warning | no change since the previous sweep |
| 424 | watcher | eu-north-1 | cancelled | config reloaded from disk |
| 425 | compactor | us-west-2 | skipped | clock skew corrected against NTP |
| 426 | uploader | af-south-1 | error | disk watermark crossed, trimmed oldest segments |
| 427 | notifier | eu-west-2 | ok | queue drained without incident |
| 428 | reaper | ap-south-1 | retrying | certificate rotated |
| 429 | shipper | ap-northeast-3 | pending | cold start took longer than the budget |
| 430 | resolver | us-east-1 | warning | manual intervention requested by the operator |
| 431 | cache | sa-east-1 | cancelled | leader election completed |
| 432 | indexer | eu-north-1 | skipped | restarted after a failed health check |
| 433 | gateway | us-west-2 | error | DNS lookup retried twice |
| 434 | scheduler | af-south-1 | ok | backpressure from the upstream shard |
| 435 | renderer | eu-west-2 | retrying | no change since the previous sweep |
| 436 | watcher | ap-south-1 | pending | config reloaded from disk |
| 437 | compactor | ap-northeast-3 | warning | clock skew corrected against NTP |
| 438 | uploader | us-east-1 | cancelled | disk watermark crossed, trimmed oldest segments |
| 439 | notifier | sa-east-1 | skipped | queue drained without incident |
| 440 | reaper | eu-north-1 | error | certificate rotated |
| 441 | shipper | us-west-2 | ok | cold start took longer than the budget |
| 442 | resolver | af-south-1 | retrying | manual intervention requested by the operator |
| 443 | cache | eu-west-2 | pending | leader election completed |
| 444 | indexer | ap-south-1 | warning | restarted after a failed health check |
| 445 | gateway | ap-northeast-3 | cancelled | DNS lookup retried twice |
| 446 | scheduler | us-east-1 | skipped | backpressure from the upstream shard |
| 447 | renderer | sa-east-1 | error | no change since the previous sweep |
| 448 | watcher | eu-north-1 | ok | config reloaded from disk |
| 449 | compactor | us-west-2 | retrying | clock skew corrected against NTP |
| 450 | uploader | af-south-1 | pending | disk watermark crossed, trimmed oldest segments |
| 451 | notifier | eu-west-2 | warning | queue drained without incident |
| 452 | reaper | ap-south-1 | cancelled | certificate rotated |
| 453 | shipper | ap-northeast-3 | skipped | cold start took longer than the budget |
| 454 | resolver | us-east-1 | error | manual intervention requested by the operator |
| 455 | cache | sa-east-1 | ok | leader election completed |
| 456 | indexer | eu-north-1 | retrying | restarted after a failed health check |
| 457 | gateway | us-west-2 | pending | DNS lookup retried twice |
| 458 | scheduler | af-south-1 | warning | backpressure from the upstream shard |
| 459 | renderer | eu-west-2 | cancelled | no change since the previous sweep |
| 460 | watcher | ap-south-1 | skipped | config reloaded from disk |
| 461 | compactor | ap-northeast-3 | error | clock skew corrected against NTP |
| 462 | uploader | us-east-1 | ok | disk watermark crossed, trimmed oldest segments |
| 463 | notifier | sa-east-1 | retrying | queue drained without incident |
| 464 | reaper | eu-north-1 | pending | certificate rotated |
| 465 | shipper | us-west-2 | warning | cold start took longer than the budget |
| 466 | resolver | af-south-1 | cancelled | manual intervention requested by the operator |
| 467 | cache | eu-west-2 | skipped | leader election completed |
| 468 | indexer | ap-south-1 | error | restarted after a failed health check |
| 469 | gateway | ap-northeast-3 | ok | DNS lookup retried twice |
| 470 | scheduler | us-east-1 | retrying | backpressure from the upstream shard |
| 471 | renderer | sa-east-1 | pending | no change since the previous sweep |
| 472 | watcher | eu-north-1 | warning | config reloaded from disk |
| 473 | compactor | us-west-2 | cancelled | clock skew corrected against NTP |
| 474 | uploader | af-south-1 | skipped | disk watermark crossed, trimmed oldest segments |
| 475 | notifier | eu-west-2 | error | queue drained without incident |
| 476 | reaper | ap-south-1 | ok | certificate rotated |
| 477 | shipper | ap-northeast-3 | retrying | cold start took longer than the budget |
| 478 | resolver | us-east-1 | pending | manual intervention requested by the operator |
| 479 | cache | sa-east-1 | warning | leader election completed |
| 480 | indexer | eu-north-1 | cancelled | restarted after a failed health check |
| 481 | gateway | us-west-2 | skipped | DNS lookup retried twice |
| 482 | scheduler | af-south-1 | error | backpressure from the upstream shard |
| 483 | renderer | eu-west-2 | ok | no change since the previous sweep |
| 484 | watcher | ap-south-1 | retrying | config reloaded from disk |
| 485 | compactor | ap-northeast-3 | pending | clock skew corrected against NTP |
| 486 | uploader | us-east-1 | warning | disk watermark crossed, trimmed oldest segments |
| 487 | notifier | sa-east-1 | cancelled | queue drained without incident |
| 488 | reaper | eu-north-1 | skipped | certificate rotated |
| 489 | shipper | us-west-2 | error | cold start took longer than the budget |
| 490 | resolver | af-south-1 | ok | manual intervention requested by the operator |
| 491 | cache | eu-west-2 | retrying | leader election completed |
| 492 | indexer | ap-south-1 | pending | restarted after a failed health check |
| 493 | gateway | ap-northeast-3 | warning | DNS lookup retried twice |
| 494 | scheduler | us-east-1 | cancelled | backpressure from the upstream shard |
| 495 | renderer | sa-east-1 | skipped | no change since the previous sweep |
| 496 | watcher | eu-north-1 | error | config reloaded from disk |
| 497 | compactor | us-west-2 | ok | clock skew corrected against NTP |
| 498 | uploader | af-south-1 | retrying | disk watermark crossed, trimmed oldest segments |
| 499 | notifier | eu-west-2 | pending | queue drained without incident |
| 500 | reaper | ap-south-1 | warning | certificate rotated |

End of the 500-row table. The row above should read `| 500 |`.

### 4.2 Roughly 2,000 rows

Seven columns, 2,000 rows. This is the progressive-rendering test: the first
screen should appear quickly, typing in the editor should stay responsive
while the rest fills in, and scrolling to the bottom should find row 2000.

| # | Timestamp | Service | Region | Status | Duration (ms) | Note |
| ---: | :--- | :--- | :--- | :---: | ---: | :--- |
| 1 | 2026-03-02T00:01:13Z | cache | sa-east-1 | pending | 37 | leader election completed |
| 2 | 2026-03-03T00:02:26Z | resolver | us-east-1 | cancelled | 74 | manual intervention requested by the operator |
| 3 | 2026-03-04T00:03:39Z | shipper | ap-northeast-3 | error | 111 | cold start took longer than the budget |
| 4 | 2026-03-05T00:04:52Z | reaper | ap-south-1 | retrying | 148 | certificate rotated |
| 5 | 2026-03-06T00:05:05Z | notifier | eu-west-2 | warning | 185 | queue drained without incident |
| 6 | 2026-03-07T00:06:18Z | uploader | af-south-1 | skipped | 222 | disk watermark crossed, trimmed oldest segments |
| 7 | 2026-03-08T00:07:31Z | compactor | us-west-2 | ok | 259 | clock skew corrected against NTP |
| 8 | 2026-03-09T00:08:44Z | watcher | eu-north-1 | pending | 296 | config reloaded from disk |
| 9 | 2026-03-10T00:09:57Z | renderer | sa-east-1 | cancelled | 333 | no change since the previous sweep |
| 10 | 2026-03-11T00:10:10Z | scheduler | us-east-1 | error | 370 | backpressure from the upstream shard |
| 11 | 2026-03-12T00:11:23Z | gateway | ap-northeast-3 | retrying | 407 | DNS lookup retried twice |
| 12 | 2026-03-13T00:12:36Z | indexer | ap-south-1 | warning | 444 | restarted after a failed health check |
| 13 | 2026-03-14T00:13:49Z | cache | eu-west-2 | skipped | 481 | leader election completed |
| 14 | 2026-03-15T00:14:02Z | resolver | af-south-1 | ok | 518 | manual intervention requested by the operator |
| 15 | 2026-03-16T00:15:15Z | shipper | us-west-2 | pending | 555 | cold start took longer than the budget |
| 16 | 2026-03-17T00:16:28Z | reaper | eu-north-1 | cancelled | 592 | certificate rotated |
| 17 | 2026-03-18T00:17:41Z | notifier | sa-east-1 | error | 629 | queue drained without incident |
| 18 | 2026-03-19T00:18:54Z | uploader | us-east-1 | retrying | 666 | disk watermark crossed, trimmed oldest segments |
| 19 | 2026-03-20T00:19:07Z | compactor | ap-northeast-3 | warning | 703 | clock skew corrected against NTP |
| 20 | 2026-03-21T00:20:20Z | watcher | ap-south-1 | skipped | 740 | config reloaded from disk |
| 21 | 2026-03-22T00:21:33Z | renderer | eu-west-2 | ok | 777 | no change since the previous sweep |
| 22 | 2026-03-23T00:22:46Z | scheduler | af-south-1 | pending | 814 | backpressure from the upstream shard |
| 23 | 2026-03-24T00:23:59Z | gateway | us-west-2 | cancelled | 851 | DNS lookup retried twice |
| 24 | 2026-03-25T00:24:12Z | indexer | eu-north-1 | error | 888 | restarted after a failed health check |
| 25 | 2026-03-26T00:25:25Z | cache | sa-east-1 | retrying | 925 | leader election completed |
| 26 | 2026-03-27T00:26:38Z | resolver | us-east-1 | warning | 962 | manual intervention requested by the operator |
| 27 | 2026-03-28T00:27:51Z | shipper | ap-northeast-3 | skipped | 999 | cold start took longer than the budget |
| 28 | 2026-03-01T00:28:04Z | reaper | ap-south-1 | ok | 1036 | certificate rotated |
| 29 | 2026-03-02T00:29:17Z | notifier | eu-west-2 | pending | 1073 | queue drained without incident |
| 30 | 2026-03-03T00:30:30Z | uploader | af-south-1 | cancelled | 1110 | disk watermark crossed, trimmed oldest segments |
| 31 | 2026-03-04T00:31:43Z | compactor | us-west-2 | error | 1147 | clock skew corrected against NTP |
| 32 | 2026-03-05T00:32:56Z | watcher | eu-north-1 | retrying | 1184 | config reloaded from disk |
| 33 | 2026-03-06T00:33:09Z | renderer | sa-east-1 | warning | 1221 | no change since the previous sweep |
| 34 | 2026-03-07T00:34:22Z | scheduler | us-east-1 | skipped | 1258 | backpressure from the upstream shard |
| 35 | 2026-03-08T00:35:35Z | gateway | ap-northeast-3 | ok | 1295 | DNS lookup retried twice |
| 36 | 2026-03-09T00:36:48Z | indexer | ap-south-1 | pending | 1332 | restarted after a failed health check |
| 37 | 2026-03-10T00:37:01Z | cache | eu-west-2 | cancelled | 1369 | leader election completed |
| 38 | 2026-03-11T00:38:14Z | resolver | af-south-1 | error | 1406 | manual intervention requested by the operator |
| 39 | 2026-03-12T00:39:27Z | shipper | us-west-2 | retrying | 1443 | cold start took longer than the budget |
| 40 | 2026-03-13T00:40:40Z | reaper | eu-north-1 | warning | 1480 | certificate rotated |
| 41 | 2026-03-14T00:41:53Z | notifier | sa-east-1 | skipped | 1517 | queue drained without incident |
| 42 | 2026-03-15T00:42:06Z | uploader | us-east-1 | ok | 1554 | disk watermark crossed, trimmed oldest segments |
| 43 | 2026-03-16T00:43:19Z | compactor | ap-northeast-3 | pending | 1591 | clock skew corrected against NTP |
| 44 | 2026-03-17T00:44:32Z | watcher | ap-south-1 | cancelled | 1628 | config reloaded from disk |
| 45 | 2026-03-18T00:45:45Z | renderer | eu-west-2 | error | 1665 | no change since the previous sweep |
| 46 | 2026-03-19T00:46:58Z | scheduler | af-south-1 | retrying | 1702 | backpressure from the upstream shard |
| 47 | 2026-03-20T00:47:11Z | gateway | us-west-2 | warning | 1739 | DNS lookup retried twice |
| 48 | 2026-03-21T00:48:24Z | indexer | eu-north-1 | skipped | 1776 | restarted after a failed health check |
| 49 | 2026-03-22T00:49:37Z | cache | sa-east-1 | ok | 1813 | leader election completed |
| 50 | 2026-03-23T00:50:50Z | resolver | us-east-1 | pending | 1850 | manual intervention requested by the operator |
| 51 | 2026-03-24T00:51:03Z | shipper | ap-northeast-3 | cancelled | 1887 | cold start took longer than the budget |
| 52 | 2026-03-25T00:52:16Z | reaper | ap-south-1 | error | 1924 | certificate rotated |
| 53 | 2026-03-26T00:53:29Z | notifier | eu-west-2 | retrying | 1961 | queue drained without incident |
| 54 | 2026-03-27T00:54:42Z | uploader | af-south-1 | warning | 1998 | disk watermark crossed, trimmed oldest segments |
| 55 | 2026-03-28T00:55:55Z | compactor | us-west-2 | skipped | 2035 | clock skew corrected against NTP |
| 56 | 2026-03-01T00:56:08Z | watcher | eu-north-1 | ok | 2072 | config reloaded from disk |
| 57 | 2026-03-02T00:57:21Z | renderer | sa-east-1 | pending | 2109 | no change since the previous sweep |
| 58 | 2026-03-03T00:58:34Z | scheduler | us-east-1 | cancelled | 2146 | backpressure from the upstream shard |
| 59 | 2026-03-04T00:59:47Z | gateway | ap-northeast-3 | error | 2183 | DNS lookup retried twice |
| 60 | 2026-03-05T01:00:00Z | indexer | ap-south-1 | retrying | 2220 | restarted after a failed health check |
| 61 | 2026-03-06T01:01:13Z | cache | eu-west-2 | warning | 2257 | leader election completed |
| 62 | 2026-03-07T01:02:26Z | resolver | af-south-1 | skipped | 2294 | manual intervention requested by the operator |
| 63 | 2026-03-08T01:03:39Z | shipper | us-west-2 | ok | 2331 | cold start took longer than the budget |
| 64 | 2026-03-09T01:04:52Z | reaper | eu-north-1 | pending | 2368 | certificate rotated |
| 65 | 2026-03-10T01:05:05Z | notifier | sa-east-1 | cancelled | 2405 | queue drained without incident |
| 66 | 2026-03-11T01:06:18Z | uploader | us-east-1 | error | 2442 | disk watermark crossed, trimmed oldest segments |
| 67 | 2026-03-12T01:07:31Z | compactor | ap-northeast-3 | retrying | 2479 | clock skew corrected against NTP |
| 68 | 2026-03-13T01:08:44Z | watcher | ap-south-1 | warning | 2516 | config reloaded from disk |
| 69 | 2026-03-14T01:09:57Z | renderer | eu-west-2 | skipped | 2553 | no change since the previous sweep |
| 70 | 2026-03-15T01:10:10Z | scheduler | af-south-1 | ok | 2590 | backpressure from the upstream shard |
| 71 | 2026-03-16T01:11:23Z | gateway | us-west-2 | pending | 2627 | DNS lookup retried twice |
| 72 | 2026-03-17T01:12:36Z | indexer | eu-north-1 | cancelled | 2664 | restarted after a failed health check |
| 73 | 2026-03-18T01:13:49Z | cache | sa-east-1 | error | 2701 | leader election completed |
| 74 | 2026-03-19T01:14:02Z | resolver | us-east-1 | retrying | 2738 | manual intervention requested by the operator |
| 75 | 2026-03-20T01:15:15Z | shipper | ap-northeast-3 | warning | 2775 | cold start took longer than the budget |
| 76 | 2026-03-21T01:16:28Z | reaper | ap-south-1 | skipped | 2812 | certificate rotated |
| 77 | 2026-03-22T01:17:41Z | notifier | eu-west-2 | ok | 2849 | queue drained without incident |
| 78 | 2026-03-23T01:18:54Z | uploader | af-south-1 | pending | 2886 | disk watermark crossed, trimmed oldest segments |
| 79 | 2026-03-24T01:19:07Z | compactor | us-west-2 | cancelled | 2923 | clock skew corrected against NTP |
| 80 | 2026-03-25T01:20:20Z | watcher | eu-north-1 | error | 2960 | config reloaded from disk |
| 81 | 2026-03-26T01:21:33Z | renderer | sa-east-1 | retrying | 2997 | no change since the previous sweep |
| 82 | 2026-03-27T01:22:46Z | scheduler | us-east-1 | warning | 3034 | backpressure from the upstream shard |
| 83 | 2026-03-28T01:23:59Z | gateway | ap-northeast-3 | skipped | 3071 | DNS lookup retried twice |
| 84 | 2026-03-01T01:24:12Z | indexer | ap-south-1 | ok | 3108 | restarted after a failed health check |
| 85 | 2026-03-02T01:25:25Z | cache | eu-west-2 | pending | 3145 | leader election completed |
| 86 | 2026-03-03T01:26:38Z | resolver | af-south-1 | cancelled | 3182 | manual intervention requested by the operator |
| 87 | 2026-03-04T01:27:51Z | shipper | us-west-2 | error | 3219 | cold start took longer than the budget |
| 88 | 2026-03-05T01:28:04Z | reaper | eu-north-1 | retrying | 3256 | certificate rotated |
| 89 | 2026-03-06T01:29:17Z | notifier | sa-east-1 | warning | 3293 | queue drained without incident |
| 90 | 2026-03-07T01:30:30Z | uploader | us-east-1 | skipped | 3330 | disk watermark crossed, trimmed oldest segments |
| 91 | 2026-03-08T01:31:43Z | compactor | ap-northeast-3 | ok | 3367 | clock skew corrected against NTP |
| 92 | 2026-03-09T01:32:56Z | watcher | ap-south-1 | pending | 3404 | config reloaded from disk |
| 93 | 2026-03-10T01:33:09Z | renderer | eu-west-2 | cancelled | 3441 | no change since the previous sweep |
| 94 | 2026-03-11T01:34:22Z | scheduler | af-south-1 | error | 3478 | backpressure from the upstream shard |
| 95 | 2026-03-12T01:35:35Z | gateway | us-west-2 | retrying | 3515 | DNS lookup retried twice |
| 96 | 2026-03-13T01:36:48Z | indexer | eu-north-1 | warning | 3552 | restarted after a failed health check |
| 97 | 2026-03-14T01:37:01Z | cache | sa-east-1 | skipped | 3589 | leader election completed |
| 98 | 2026-03-15T01:38:14Z | resolver | us-east-1 | ok | 3626 | manual intervention requested by the operator |
| 99 | 2026-03-16T01:39:27Z | shipper | ap-northeast-3 | pending | 3663 | cold start took longer than the budget |
| 100 | 2026-03-17T01:40:40Z | reaper | ap-south-1 | cancelled | 3700 | certificate rotated |
| 101 | 2026-03-18T01:41:53Z | notifier | eu-west-2 | error | 3737 | queue drained without incident |
| 102 | 2026-03-19T01:42:06Z | uploader | af-south-1 | retrying | 3774 | disk watermark crossed, trimmed oldest segments |
| 103 | 2026-03-20T01:43:19Z | compactor | us-west-2 | warning | 3811 | clock skew corrected against NTP |
| 104 | 2026-03-21T01:44:32Z | watcher | eu-north-1 | skipped | 3848 | config reloaded from disk |
| 105 | 2026-03-22T01:45:45Z | renderer | sa-east-1 | ok | 3885 | no change since the previous sweep |
| 106 | 2026-03-23T01:46:58Z | scheduler | us-east-1 | pending | 3922 | backpressure from the upstream shard |
| 107 | 2026-03-24T01:47:11Z | gateway | ap-northeast-3 | cancelled | 3959 | DNS lookup retried twice |
| 108 | 2026-03-25T01:48:24Z | indexer | ap-south-1 | error | 3996 | restarted after a failed health check |
| 109 | 2026-03-26T01:49:37Z | cache | eu-west-2 | retrying | 4033 | leader election completed |
| 110 | 2026-03-27T01:50:50Z | resolver | af-south-1 | warning | 4070 | manual intervention requested by the operator |
| 111 | 2026-03-28T01:51:03Z | shipper | us-west-2 | skipped | 4107 | cold start took longer than the budget |
| 112 | 2026-03-01T01:52:16Z | reaper | eu-north-1 | ok | 4144 | certificate rotated |
| 113 | 2026-03-02T01:53:29Z | notifier | sa-east-1 | pending | 4181 | queue drained without incident |
| 114 | 2026-03-03T01:54:42Z | uploader | us-east-1 | cancelled | 4218 | disk watermark crossed, trimmed oldest segments |
| 115 | 2026-03-04T01:55:55Z | compactor | ap-northeast-3 | error | 4255 | clock skew corrected against NTP |
| 116 | 2026-03-05T01:56:08Z | watcher | ap-south-1 | retrying | 4292 | config reloaded from disk |
| 117 | 2026-03-06T01:57:21Z | renderer | eu-west-2 | warning | 4329 | no change since the previous sweep |
| 118 | 2026-03-07T01:58:34Z | scheduler | af-south-1 | skipped | 4366 | backpressure from the upstream shard |
| 119 | 2026-03-08T01:59:47Z | gateway | us-west-2 | ok | 4403 | DNS lookup retried twice |
| 120 | 2026-03-09T02:00:00Z | indexer | eu-north-1 | pending | 4440 | restarted after a failed health check |
| 121 | 2026-03-10T02:01:13Z | cache | sa-east-1 | cancelled | 4477 | leader election completed |
| 122 | 2026-03-11T02:02:26Z | resolver | us-east-1 | error | 4514 | manual intervention requested by the operator |
| 123 | 2026-03-12T02:03:39Z | shipper | ap-northeast-3 | retrying | 4551 | cold start took longer than the budget |
| 124 | 2026-03-13T02:04:52Z | reaper | ap-south-1 | warning | 4588 | certificate rotated |
| 125 | 2026-03-14T02:05:05Z | notifier | eu-west-2 | skipped | 4625 | queue drained without incident |
| 126 | 2026-03-15T02:06:18Z | uploader | af-south-1 | ok | 4662 | disk watermark crossed, trimmed oldest segments |
| 127 | 2026-03-16T02:07:31Z | compactor | us-west-2 | pending | 4699 | clock skew corrected against NTP |
| 128 | 2026-03-17T02:08:44Z | watcher | eu-north-1 | cancelled | 4736 | config reloaded from disk |
| 129 | 2026-03-18T02:09:57Z | renderer | sa-east-1 | error | 4773 | no change since the previous sweep |
| 130 | 2026-03-19T02:10:10Z | scheduler | us-east-1 | retrying | 4810 | backpressure from the upstream shard |
| 131 | 2026-03-20T02:11:23Z | gateway | ap-northeast-3 | warning | 4847 | DNS lookup retried twice |
| 132 | 2026-03-21T02:12:36Z | indexer | ap-south-1 | skipped | 4884 | restarted after a failed health check |
| 133 | 2026-03-22T02:13:49Z | cache | eu-west-2 | ok | 4921 | leader election completed |
| 134 | 2026-03-23T02:14:02Z | resolver | af-south-1 | pending | 4958 | manual intervention requested by the operator |
| 135 | 2026-03-24T02:15:15Z | shipper | us-west-2 | cancelled | 4995 | cold start took longer than the budget |
| 136 | 2026-03-25T02:16:28Z | reaper | eu-north-1 | error | 5032 | certificate rotated |
| 137 | 2026-03-26T02:17:41Z | notifier | sa-east-1 | retrying | 5069 | queue drained without incident |
| 138 | 2026-03-27T02:18:54Z | uploader | us-east-1 | warning | 5106 | disk watermark crossed, trimmed oldest segments |
| 139 | 2026-03-28T02:19:07Z | compactor | ap-northeast-3 | skipped | 5143 | clock skew corrected against NTP |
| 140 | 2026-03-01T02:20:20Z | watcher | ap-south-1 | ok | 5180 | config reloaded from disk |
| 141 | 2026-03-02T02:21:33Z | renderer | eu-west-2 | pending | 5217 | no change since the previous sweep |
| 142 | 2026-03-03T02:22:46Z | scheduler | af-south-1 | cancelled | 5254 | backpressure from the upstream shard |
| 143 | 2026-03-04T02:23:59Z | gateway | us-west-2 | error | 5291 | DNS lookup retried twice |
| 144 | 2026-03-05T02:24:12Z | indexer | eu-north-1 | retrying | 5328 | restarted after a failed health check |
| 145 | 2026-03-06T02:25:25Z | cache | sa-east-1 | warning | 5365 | leader election completed |
| 146 | 2026-03-07T02:26:38Z | resolver | us-east-1 | skipped | 5402 | manual intervention requested by the operator |
| 147 | 2026-03-08T02:27:51Z | shipper | ap-northeast-3 | ok | 5439 | cold start took longer than the budget |
| 148 | 2026-03-09T02:28:04Z | reaper | ap-south-1 | pending | 5476 | certificate rotated |
| 149 | 2026-03-10T02:29:17Z | notifier | eu-west-2 | cancelled | 5513 | queue drained without incident |
| 150 | 2026-03-11T02:30:30Z | uploader | af-south-1 | error | 5550 | disk watermark crossed, trimmed oldest segments |
| 151 | 2026-03-12T02:31:43Z | compactor | us-west-2 | retrying | 5587 | clock skew corrected against NTP |
| 152 | 2026-03-13T02:32:56Z | watcher | eu-north-1 | warning | 5624 | config reloaded from disk |
| 153 | 2026-03-14T02:33:09Z | renderer | sa-east-1 | skipped | 5661 | no change since the previous sweep |
| 154 | 2026-03-15T02:34:22Z | scheduler | us-east-1 | ok | 5698 | backpressure from the upstream shard |
| 155 | 2026-03-16T02:35:35Z | gateway | ap-northeast-3 | pending | 5735 | DNS lookup retried twice |
| 156 | 2026-03-17T02:36:48Z | indexer | ap-south-1 | cancelled | 5772 | restarted after a failed health check |
| 157 | 2026-03-18T02:37:01Z | cache | eu-west-2 | error | 5809 | leader election completed |
| 158 | 2026-03-19T02:38:14Z | resolver | af-south-1 | retrying | 5846 | manual intervention requested by the operator |
| 159 | 2026-03-20T02:39:27Z | shipper | us-west-2 | warning | 5883 | cold start took longer than the budget |
| 160 | 2026-03-21T02:40:40Z | reaper | eu-north-1 | skipped | 5920 | certificate rotated |
| 161 | 2026-03-22T02:41:53Z | notifier | sa-east-1 | ok | 5957 | queue drained without incident |
| 162 | 2026-03-23T02:42:06Z | uploader | us-east-1 | pending | 5994 | disk watermark crossed, trimmed oldest segments |
| 163 | 2026-03-24T02:43:19Z | compactor | ap-northeast-3 | cancelled | 6031 | clock skew corrected against NTP |
| 164 | 2026-03-25T02:44:32Z | watcher | ap-south-1 | error | 6068 | config reloaded from disk |
| 165 | 2026-03-26T02:45:45Z | renderer | eu-west-2 | retrying | 6105 | no change since the previous sweep |
| 166 | 2026-03-27T02:46:58Z | scheduler | af-south-1 | warning | 6142 | backpressure from the upstream shard |
| 167 | 2026-03-28T02:47:11Z | gateway | us-west-2 | skipped | 6179 | DNS lookup retried twice |
| 168 | 2026-03-01T02:48:24Z | indexer | eu-north-1 | ok | 6216 | restarted after a failed health check |
| 169 | 2026-03-02T02:49:37Z | cache | sa-east-1 | pending | 6253 | leader election completed |
| 170 | 2026-03-03T02:50:50Z | resolver | us-east-1 | cancelled | 6290 | manual intervention requested by the operator |
| 171 | 2026-03-04T02:51:03Z | shipper | ap-northeast-3 | error | 6327 | cold start took longer than the budget |
| 172 | 2026-03-05T02:52:16Z | reaper | ap-south-1 | retrying | 6364 | certificate rotated |
| 173 | 2026-03-06T02:53:29Z | notifier | eu-west-2 | warning | 6401 | queue drained without incident |
| 174 | 2026-03-07T02:54:42Z | uploader | af-south-1 | skipped | 6438 | disk watermark crossed, trimmed oldest segments |
| 175 | 2026-03-08T02:55:55Z | compactor | us-west-2 | ok | 6475 | clock skew corrected against NTP |
| 176 | 2026-03-09T02:56:08Z | watcher | eu-north-1 | pending | 6512 | config reloaded from disk |
| 177 | 2026-03-10T02:57:21Z | renderer | sa-east-1 | cancelled | 6549 | no change since the previous sweep |
| 178 | 2026-03-11T02:58:34Z | scheduler | us-east-1 | error | 6586 | backpressure from the upstream shard |
| 179 | 2026-03-12T02:59:47Z | gateway | ap-northeast-3 | retrying | 6623 | DNS lookup retried twice |
| 180 | 2026-03-13T03:00:00Z | indexer | ap-south-1 | warning | 6660 | restarted after a failed health check |
| 181 | 2026-03-14T03:01:13Z | cache | eu-west-2 | skipped | 6697 | leader election completed |
| 182 | 2026-03-15T03:02:26Z | resolver | af-south-1 | ok | 6734 | manual intervention requested by the operator |
| 183 | 2026-03-16T03:03:39Z | shipper | us-west-2 | pending | 6771 | cold start took longer than the budget |
| 184 | 2026-03-17T03:04:52Z | reaper | eu-north-1 | cancelled | 6808 | certificate rotated |
| 185 | 2026-03-18T03:05:05Z | notifier | sa-east-1 | error | 6845 | queue drained without incident |
| 186 | 2026-03-19T03:06:18Z | uploader | us-east-1 | retrying | 6882 | disk watermark crossed, trimmed oldest segments |
| 187 | 2026-03-20T03:07:31Z | compactor | ap-northeast-3 | warning | 6919 | clock skew corrected against NTP |
| 188 | 2026-03-21T03:08:44Z | watcher | ap-south-1 | skipped | 6956 | config reloaded from disk |
| 189 | 2026-03-22T03:09:57Z | renderer | eu-west-2 | ok | 6993 | no change since the previous sweep |
| 190 | 2026-03-23T03:10:10Z | scheduler | af-south-1 | pending | 7030 | backpressure from the upstream shard |
| 191 | 2026-03-24T03:11:23Z | gateway | us-west-2 | cancelled | 7067 | DNS lookup retried twice |
| 192 | 2026-03-25T03:12:36Z | indexer | eu-north-1 | error | 7104 | restarted after a failed health check |
| 193 | 2026-03-26T03:13:49Z | cache | sa-east-1 | retrying | 7141 | leader election completed |
| 194 | 2026-03-27T03:14:02Z | resolver | us-east-1 | warning | 7178 | manual intervention requested by the operator |
| 195 | 2026-03-28T03:15:15Z | shipper | ap-northeast-3 | skipped | 7215 | cold start took longer than the budget |
| 196 | 2026-03-01T03:16:28Z | reaper | ap-south-1 | ok | 7252 | certificate rotated |
| 197 | 2026-03-02T03:17:41Z | notifier | eu-west-2 | pending | 7289 | queue drained without incident |
| 198 | 2026-03-03T03:18:54Z | uploader | af-south-1 | cancelled | 7326 | disk watermark crossed, trimmed oldest segments |
| 199 | 2026-03-04T03:19:07Z | compactor | us-west-2 | error | 7363 | clock skew corrected against NTP |
| 200 | 2026-03-05T03:20:20Z | watcher | eu-north-1 | retrying | 7400 | config reloaded from disk |
| 201 | 2026-03-06T03:21:33Z | renderer | sa-east-1 | warning | 7437 | no change since the previous sweep |
| 202 | 2026-03-07T03:22:46Z | scheduler | us-east-1 | skipped | 7474 | backpressure from the upstream shard |
| 203 | 2026-03-08T03:23:59Z | gateway | ap-northeast-3 | ok | 7511 | DNS lookup retried twice |
| 204 | 2026-03-09T03:24:12Z | indexer | ap-south-1 | pending | 7548 | restarted after a failed health check |
| 205 | 2026-03-10T03:25:25Z | cache | eu-west-2 | cancelled | 7585 | leader election completed |
| 206 | 2026-03-11T03:26:38Z | resolver | af-south-1 | error | 7622 | manual intervention requested by the operator |
| 207 | 2026-03-12T03:27:51Z | shipper | us-west-2 | retrying | 7659 | cold start took longer than the budget |
| 208 | 2026-03-13T03:28:04Z | reaper | eu-north-1 | warning | 7696 | certificate rotated |
| 209 | 2026-03-14T03:29:17Z | notifier | sa-east-1 | skipped | 7733 | queue drained without incident |
| 210 | 2026-03-15T03:30:30Z | uploader | us-east-1 | ok | 7770 | disk watermark crossed, trimmed oldest segments |
| 211 | 2026-03-16T03:31:43Z | compactor | ap-northeast-3 | pending | 7807 | clock skew corrected against NTP |
| 212 | 2026-03-17T03:32:56Z | watcher | ap-south-1 | cancelled | 7844 | config reloaded from disk |
| 213 | 2026-03-18T03:33:09Z | renderer | eu-west-2 | error | 7881 | no change since the previous sweep |
| 214 | 2026-03-19T03:34:22Z | scheduler | af-south-1 | retrying | 7918 | backpressure from the upstream shard |
| 215 | 2026-03-20T03:35:35Z | gateway | us-west-2 | warning | 7955 | DNS lookup retried twice |
| 216 | 2026-03-21T03:36:48Z | indexer | eu-north-1 | skipped | 7992 | restarted after a failed health check |
| 217 | 2026-03-22T03:37:01Z | cache | sa-east-1 | ok | 8029 | leader election completed |
| 218 | 2026-03-23T03:38:14Z | resolver | us-east-1 | pending | 8066 | manual intervention requested by the operator |
| 219 | 2026-03-24T03:39:27Z | shipper | ap-northeast-3 | cancelled | 8103 | cold start took longer than the budget |
| 220 | 2026-03-25T03:40:40Z | reaper | ap-south-1 | error | 8140 | certificate rotated |
| 221 | 2026-03-26T03:41:53Z | notifier | eu-west-2 | retrying | 8177 | queue drained without incident |
| 222 | 2026-03-27T03:42:06Z | uploader | af-south-1 | warning | 8214 | disk watermark crossed, trimmed oldest segments |
| 223 | 2026-03-28T03:43:19Z | compactor | us-west-2 | skipped | 8251 | clock skew corrected against NTP |
| 224 | 2026-03-01T03:44:32Z | watcher | eu-north-1 | ok | 8288 | config reloaded from disk |
| 225 | 2026-03-02T03:45:45Z | renderer | sa-east-1 | pending | 8325 | no change since the previous sweep |
| 226 | 2026-03-03T03:46:58Z | scheduler | us-east-1 | cancelled | 8362 | backpressure from the upstream shard |
| 227 | 2026-03-04T03:47:11Z | gateway | ap-northeast-3 | error | 8399 | DNS lookup retried twice |
| 228 | 2026-03-05T03:48:24Z | indexer | ap-south-1 | retrying | 8436 | restarted after a failed health check |
| 229 | 2026-03-06T03:49:37Z | cache | eu-west-2 | warning | 8473 | leader election completed |
| 230 | 2026-03-07T03:50:50Z | resolver | af-south-1 | skipped | 8510 | manual intervention requested by the operator |
| 231 | 2026-03-08T03:51:03Z | shipper | us-west-2 | ok | 8547 | cold start took longer than the budget |
| 232 | 2026-03-09T03:52:16Z | reaper | eu-north-1 | pending | 8584 | certificate rotated |
| 233 | 2026-03-10T03:53:29Z | notifier | sa-east-1 | cancelled | 8621 | queue drained without incident |
| 234 | 2026-03-11T03:54:42Z | uploader | us-east-1 | error | 8658 | disk watermark crossed, trimmed oldest segments |
| 235 | 2026-03-12T03:55:55Z | compactor | ap-northeast-3 | retrying | 8695 | clock skew corrected against NTP |
| 236 | 2026-03-13T03:56:08Z | watcher | ap-south-1 | warning | 8732 | config reloaded from disk |
| 237 | 2026-03-14T03:57:21Z | renderer | eu-west-2 | skipped | 8769 | no change since the previous sweep |
| 238 | 2026-03-15T03:58:34Z | scheduler | af-south-1 | ok | 8806 | backpressure from the upstream shard |
| 239 | 2026-03-16T03:59:47Z | gateway | us-west-2 | pending | 8843 | DNS lookup retried twice |
| 240 | 2026-03-17T04:00:00Z | indexer | eu-north-1 | cancelled | 8880 | restarted after a failed health check |
| 241 | 2026-03-18T04:01:13Z | cache | sa-east-1 | error | 8917 | leader election completed |
| 242 | 2026-03-19T04:02:26Z | resolver | us-east-1 | retrying | 8954 | manual intervention requested by the operator |
| 243 | 2026-03-20T04:03:39Z | shipper | ap-northeast-3 | warning | 8991 | cold start took longer than the budget |
| 244 | 2026-03-21T04:04:52Z | reaper | ap-south-1 | skipped | 9028 | certificate rotated |
| 245 | 2026-03-22T04:05:05Z | notifier | eu-west-2 | ok | 9065 | queue drained without incident |
| 246 | 2026-03-23T04:06:18Z | uploader | af-south-1 | pending | 9102 | disk watermark crossed, trimmed oldest segments |
| 247 | 2026-03-24T04:07:31Z | compactor | us-west-2 | cancelled | 9139 | clock skew corrected against NTP |
| 248 | 2026-03-25T04:08:44Z | watcher | eu-north-1 | error | 9176 | config reloaded from disk |
| 249 | 2026-03-26T04:09:57Z | renderer | sa-east-1 | retrying | 9213 | no change since the previous sweep |
| 250 | 2026-03-27T04:10:10Z | scheduler | us-east-1 | warning | 9250 | backpressure from the upstream shard |
| 251 | 2026-03-28T04:11:23Z | gateway | ap-northeast-3 | skipped | 9287 | DNS lookup retried twice |
| 252 | 2026-03-01T04:12:36Z | indexer | ap-south-1 | ok | 9324 | restarted after a failed health check |
| 253 | 2026-03-02T04:13:49Z | cache | eu-west-2 | pending | 9361 | leader election completed |
| 254 | 2026-03-03T04:14:02Z | resolver | af-south-1 | cancelled | 9398 | manual intervention requested by the operator |
| 255 | 2026-03-04T04:15:15Z | shipper | us-west-2 | error | 9435 | cold start took longer than the budget |
| 256 | 2026-03-05T04:16:28Z | reaper | eu-north-1 | retrying | 9472 | certificate rotated |
| 257 | 2026-03-06T04:17:41Z | notifier | sa-east-1 | warning | 9509 | queue drained without incident |
| 258 | 2026-03-07T04:18:54Z | uploader | us-east-1 | skipped | 9546 | disk watermark crossed, trimmed oldest segments |
| 259 | 2026-03-08T04:19:07Z | compactor | ap-northeast-3 | ok | 9583 | clock skew corrected against NTP |
| 260 | 2026-03-09T04:20:20Z | watcher | ap-south-1 | pending | 9620 | config reloaded from disk |
| 261 | 2026-03-10T04:21:33Z | renderer | eu-west-2 | cancelled | 9657 | no change since the previous sweep |
| 262 | 2026-03-11T04:22:46Z | scheduler | af-south-1 | error | 9694 | backpressure from the upstream shard |
| 263 | 2026-03-12T04:23:59Z | gateway | us-west-2 | retrying | 9731 | DNS lookup retried twice |
| 264 | 2026-03-13T04:24:12Z | indexer | eu-north-1 | warning | 9768 | restarted after a failed health check |
| 265 | 2026-03-14T04:25:25Z | cache | sa-east-1 | skipped | 9805 | leader election completed |
| 266 | 2026-03-15T04:26:38Z | resolver | us-east-1 | ok | 9842 | manual intervention requested by the operator |
| 267 | 2026-03-16T04:27:51Z | shipper | ap-northeast-3 | pending | 9879 | cold start took longer than the budget |
| 268 | 2026-03-17T04:28:04Z | reaper | ap-south-1 | cancelled | 9916 | certificate rotated |
| 269 | 2026-03-18T04:29:17Z | notifier | eu-west-2 | error | 9953 | queue drained without incident |
| 270 | 2026-03-19T04:30:30Z | uploader | af-south-1 | retrying | 17 | disk watermark crossed, trimmed oldest segments |
| 271 | 2026-03-20T04:31:43Z | compactor | us-west-2 | warning | 54 | clock skew corrected against NTP |
| 272 | 2026-03-21T04:32:56Z | watcher | eu-north-1 | skipped | 91 | config reloaded from disk |
| 273 | 2026-03-22T04:33:09Z | renderer | sa-east-1 | ok | 128 | no change since the previous sweep |
| 274 | 2026-03-23T04:34:22Z | scheduler | us-east-1 | pending | 165 | backpressure from the upstream shard |
| 275 | 2026-03-24T04:35:35Z | gateway | ap-northeast-3 | cancelled | 202 | DNS lookup retried twice |
| 276 | 2026-03-25T04:36:48Z | indexer | ap-south-1 | error | 239 | restarted after a failed health check |
| 277 | 2026-03-26T04:37:01Z | cache | eu-west-2 | retrying | 276 | leader election completed |
| 278 | 2026-03-27T04:38:14Z | resolver | af-south-1 | warning | 313 | manual intervention requested by the operator |
| 279 | 2026-03-28T04:39:27Z | shipper | us-west-2 | skipped | 350 | cold start took longer than the budget |
| 280 | 2026-03-01T04:40:40Z | reaper | eu-north-1 | ok | 387 | certificate rotated |
| 281 | 2026-03-02T04:41:53Z | notifier | sa-east-1 | pending | 424 | queue drained without incident |
| 282 | 2026-03-03T04:42:06Z | uploader | us-east-1 | cancelled | 461 | disk watermark crossed, trimmed oldest segments |
| 283 | 2026-03-04T04:43:19Z | compactor | ap-northeast-3 | error | 498 | clock skew corrected against NTP |
| 284 | 2026-03-05T04:44:32Z | watcher | ap-south-1 | retrying | 535 | config reloaded from disk |
| 285 | 2026-03-06T04:45:45Z | renderer | eu-west-2 | warning | 572 | no change since the previous sweep |
| 286 | 2026-03-07T04:46:58Z | scheduler | af-south-1 | skipped | 609 | backpressure from the upstream shard |
| 287 | 2026-03-08T04:47:11Z | gateway | us-west-2 | ok | 646 | DNS lookup retried twice |
| 288 | 2026-03-09T04:48:24Z | indexer | eu-north-1 | pending | 683 | restarted after a failed health check |
| 289 | 2026-03-10T04:49:37Z | cache | sa-east-1 | cancelled | 720 | leader election completed |
| 290 | 2026-03-11T04:50:50Z | resolver | us-east-1 | error | 757 | manual intervention requested by the operator |
| 291 | 2026-03-12T04:51:03Z | shipper | ap-northeast-3 | retrying | 794 | cold start took longer than the budget |
| 292 | 2026-03-13T04:52:16Z | reaper | ap-south-1 | warning | 831 | certificate rotated |
| 293 | 2026-03-14T04:53:29Z | notifier | eu-west-2 | skipped | 868 | queue drained without incident |
| 294 | 2026-03-15T04:54:42Z | uploader | af-south-1 | ok | 905 | disk watermark crossed, trimmed oldest segments |
| 295 | 2026-03-16T04:55:55Z | compactor | us-west-2 | pending | 942 | clock skew corrected against NTP |
| 296 | 2026-03-17T04:56:08Z | watcher | eu-north-1 | cancelled | 979 | config reloaded from disk |
| 297 | 2026-03-18T04:57:21Z | renderer | sa-east-1 | error | 1016 | no change since the previous sweep |
| 298 | 2026-03-19T04:58:34Z | scheduler | us-east-1 | retrying | 1053 | backpressure from the upstream shard |
| 299 | 2026-03-20T04:59:47Z | gateway | ap-northeast-3 | warning | 1090 | DNS lookup retried twice |
| 300 | 2026-03-21T05:00:00Z | indexer | ap-south-1 | skipped | 1127 | restarted after a failed health check |
| 301 | 2026-03-22T05:01:13Z | cache | eu-west-2 | ok | 1164 | leader election completed |
| 302 | 2026-03-23T05:02:26Z | resolver | af-south-1 | pending | 1201 | manual intervention requested by the operator |
| 303 | 2026-03-24T05:03:39Z | shipper | us-west-2 | cancelled | 1238 | cold start took longer than the budget |
| 304 | 2026-03-25T05:04:52Z | reaper | eu-north-1 | error | 1275 | certificate rotated |
| 305 | 2026-03-26T05:05:05Z | notifier | sa-east-1 | retrying | 1312 | queue drained without incident |
| 306 | 2026-03-27T05:06:18Z | uploader | us-east-1 | warning | 1349 | disk watermark crossed, trimmed oldest segments |
| 307 | 2026-03-28T05:07:31Z | compactor | ap-northeast-3 | skipped | 1386 | clock skew corrected against NTP |
| 308 | 2026-03-01T05:08:44Z | watcher | ap-south-1 | ok | 1423 | config reloaded from disk |
| 309 | 2026-03-02T05:09:57Z | renderer | eu-west-2 | pending | 1460 | no change since the previous sweep |
| 310 | 2026-03-03T05:10:10Z | scheduler | af-south-1 | cancelled | 1497 | backpressure from the upstream shard |
| 311 | 2026-03-04T05:11:23Z | gateway | us-west-2 | error | 1534 | DNS lookup retried twice |
| 312 | 2026-03-05T05:12:36Z | indexer | eu-north-1 | retrying | 1571 | restarted after a failed health check |
| 313 | 2026-03-06T05:13:49Z | cache | sa-east-1 | warning | 1608 | leader election completed |
| 314 | 2026-03-07T05:14:02Z | resolver | us-east-1 | skipped | 1645 | manual intervention requested by the operator |
| 315 | 2026-03-08T05:15:15Z | shipper | ap-northeast-3 | ok | 1682 | cold start took longer than the budget |
| 316 | 2026-03-09T05:16:28Z | reaper | ap-south-1 | pending | 1719 | certificate rotated |
| 317 | 2026-03-10T05:17:41Z | notifier | eu-west-2 | cancelled | 1756 | queue drained without incident |
| 318 | 2026-03-11T05:18:54Z | uploader | af-south-1 | error | 1793 | disk watermark crossed, trimmed oldest segments |
| 319 | 2026-03-12T05:19:07Z | compactor | us-west-2 | retrying | 1830 | clock skew corrected against NTP |
| 320 | 2026-03-13T05:20:20Z | watcher | eu-north-1 | warning | 1867 | config reloaded from disk |
| 321 | 2026-03-14T05:21:33Z | renderer | sa-east-1 | skipped | 1904 | no change since the previous sweep |
| 322 | 2026-03-15T05:22:46Z | scheduler | us-east-1 | ok | 1941 | backpressure from the upstream shard |
| 323 | 2026-03-16T05:23:59Z | gateway | ap-northeast-3 | pending | 1978 | DNS lookup retried twice |
| 324 | 2026-03-17T05:24:12Z | indexer | ap-south-1 | cancelled | 2015 | restarted after a failed health check |
| 325 | 2026-03-18T05:25:25Z | cache | eu-west-2 | error | 2052 | leader election completed |
| 326 | 2026-03-19T05:26:38Z | resolver | af-south-1 | retrying | 2089 | manual intervention requested by the operator |
| 327 | 2026-03-20T05:27:51Z | shipper | us-west-2 | warning | 2126 | cold start took longer than the budget |
| 328 | 2026-03-21T05:28:04Z | reaper | eu-north-1 | skipped | 2163 | certificate rotated |
| 329 | 2026-03-22T05:29:17Z | notifier | sa-east-1 | ok | 2200 | queue drained without incident |
| 330 | 2026-03-23T05:30:30Z | uploader | us-east-1 | pending | 2237 | disk watermark crossed, trimmed oldest segments |
| 331 | 2026-03-24T05:31:43Z | compactor | ap-northeast-3 | cancelled | 2274 | clock skew corrected against NTP |
| 332 | 2026-03-25T05:32:56Z | watcher | ap-south-1 | error | 2311 | config reloaded from disk |
| 333 | 2026-03-26T05:33:09Z | renderer | eu-west-2 | retrying | 2348 | no change since the previous sweep |
| 334 | 2026-03-27T05:34:22Z | scheduler | af-south-1 | warning | 2385 | backpressure from the upstream shard |
| 335 | 2026-03-28T05:35:35Z | gateway | us-west-2 | skipped | 2422 | DNS lookup retried twice |
| 336 | 2026-03-01T05:36:48Z | indexer | eu-north-1 | ok | 2459 | restarted after a failed health check |
| 337 | 2026-03-02T05:37:01Z | cache | sa-east-1 | pending | 2496 | leader election completed |
| 338 | 2026-03-03T05:38:14Z | resolver | us-east-1 | cancelled | 2533 | manual intervention requested by the operator |
| 339 | 2026-03-04T05:39:27Z | shipper | ap-northeast-3 | error | 2570 | cold start took longer than the budget |
| 340 | 2026-03-05T05:40:40Z | reaper | ap-south-1 | retrying | 2607 | certificate rotated |
| 341 | 2026-03-06T05:41:53Z | notifier | eu-west-2 | warning | 2644 | queue drained without incident |
| 342 | 2026-03-07T05:42:06Z | uploader | af-south-1 | skipped | 2681 | disk watermark crossed, trimmed oldest segments |
| 343 | 2026-03-08T05:43:19Z | compactor | us-west-2 | ok | 2718 | clock skew corrected against NTP |
| 344 | 2026-03-09T05:44:32Z | watcher | eu-north-1 | pending | 2755 | config reloaded from disk |
| 345 | 2026-03-10T05:45:45Z | renderer | sa-east-1 | cancelled | 2792 | no change since the previous sweep |
| 346 | 2026-03-11T05:46:58Z | scheduler | us-east-1 | error | 2829 | backpressure from the upstream shard |
| 347 | 2026-03-12T05:47:11Z | gateway | ap-northeast-3 | retrying | 2866 | DNS lookup retried twice |
| 348 | 2026-03-13T05:48:24Z | indexer | ap-south-1 | warning | 2903 | restarted after a failed health check |
| 349 | 2026-03-14T05:49:37Z | cache | eu-west-2 | skipped | 2940 | leader election completed |
| 350 | 2026-03-15T05:50:50Z | resolver | af-south-1 | ok | 2977 | manual intervention requested by the operator |
| 351 | 2026-03-16T05:51:03Z | shipper | us-west-2 | pending | 3014 | cold start took longer than the budget |
| 352 | 2026-03-17T05:52:16Z | reaper | eu-north-1 | cancelled | 3051 | certificate rotated |
| 353 | 2026-03-18T05:53:29Z | notifier | sa-east-1 | error | 3088 | queue drained without incident |
| 354 | 2026-03-19T05:54:42Z | uploader | us-east-1 | retrying | 3125 | disk watermark crossed, trimmed oldest segments |
| 355 | 2026-03-20T05:55:55Z | compactor | ap-northeast-3 | warning | 3162 | clock skew corrected against NTP |
| 356 | 2026-03-21T05:56:08Z | watcher | ap-south-1 | skipped | 3199 | config reloaded from disk |
| 357 | 2026-03-22T05:57:21Z | renderer | eu-west-2 | ok | 3236 | no change since the previous sweep |
| 358 | 2026-03-23T05:58:34Z | scheduler | af-south-1 | pending | 3273 | backpressure from the upstream shard |
| 359 | 2026-03-24T05:59:47Z | gateway | us-west-2 | cancelled | 3310 | DNS lookup retried twice |
| 360 | 2026-03-25T06:00:00Z | indexer | eu-north-1 | error | 3347 | restarted after a failed health check |
| 361 | 2026-03-26T06:01:13Z | cache | sa-east-1 | retrying | 3384 | leader election completed |
| 362 | 2026-03-27T06:02:26Z | resolver | us-east-1 | warning | 3421 | manual intervention requested by the operator |
| 363 | 2026-03-28T06:03:39Z | shipper | ap-northeast-3 | skipped | 3458 | cold start took longer than the budget |
| 364 | 2026-03-01T06:04:52Z | reaper | ap-south-1 | ok | 3495 | certificate rotated |
| 365 | 2026-03-02T06:05:05Z | notifier | eu-west-2 | pending | 3532 | queue drained without incident |
| 366 | 2026-03-03T06:06:18Z | uploader | af-south-1 | cancelled | 3569 | disk watermark crossed, trimmed oldest segments |
| 367 | 2026-03-04T06:07:31Z | compactor | us-west-2 | error | 3606 | clock skew corrected against NTP |
| 368 | 2026-03-05T06:08:44Z | watcher | eu-north-1 | retrying | 3643 | config reloaded from disk |
| 369 | 2026-03-06T06:09:57Z | renderer | sa-east-1 | warning | 3680 | no change since the previous sweep |
| 370 | 2026-03-07T06:10:10Z | scheduler | us-east-1 | skipped | 3717 | backpressure from the upstream shard |
| 371 | 2026-03-08T06:11:23Z | gateway | ap-northeast-3 | ok | 3754 | DNS lookup retried twice |
| 372 | 2026-03-09T06:12:36Z | indexer | ap-south-1 | pending | 3791 | restarted after a failed health check |
| 373 | 2026-03-10T06:13:49Z | cache | eu-west-2 | cancelled | 3828 | leader election completed |
| 374 | 2026-03-11T06:14:02Z | resolver | af-south-1 | error | 3865 | manual intervention requested by the operator |
| 375 | 2026-03-12T06:15:15Z | shipper | us-west-2 | retrying | 3902 | cold start took longer than the budget |
| 376 | 2026-03-13T06:16:28Z | reaper | eu-north-1 | warning | 3939 | certificate rotated |
| 377 | 2026-03-14T06:17:41Z | notifier | sa-east-1 | skipped | 3976 | queue drained without incident |
| 378 | 2026-03-15T06:18:54Z | uploader | us-east-1 | ok | 4013 | disk watermark crossed, trimmed oldest segments |
| 379 | 2026-03-16T06:19:07Z | compactor | ap-northeast-3 | pending | 4050 | clock skew corrected against NTP |
| 380 | 2026-03-17T06:20:20Z | watcher | ap-south-1 | cancelled | 4087 | config reloaded from disk |
| 381 | 2026-03-18T06:21:33Z | renderer | eu-west-2 | error | 4124 | no change since the previous sweep |
| 382 | 2026-03-19T06:22:46Z | scheduler | af-south-1 | retrying | 4161 | backpressure from the upstream shard |
| 383 | 2026-03-20T06:23:59Z | gateway | us-west-2 | warning | 4198 | DNS lookup retried twice |
| 384 | 2026-03-21T06:24:12Z | indexer | eu-north-1 | skipped | 4235 | restarted after a failed health check |
| 385 | 2026-03-22T06:25:25Z | cache | sa-east-1 | ok | 4272 | leader election completed |
| 386 | 2026-03-23T06:26:38Z | resolver | us-east-1 | pending | 4309 | manual intervention requested by the operator |
| 387 | 2026-03-24T06:27:51Z | shipper | ap-northeast-3 | cancelled | 4346 | cold start took longer than the budget |
| 388 | 2026-03-25T06:28:04Z | reaper | ap-south-1 | error | 4383 | certificate rotated |
| 389 | 2026-03-26T06:29:17Z | notifier | eu-west-2 | retrying | 4420 | queue drained without incident |
| 390 | 2026-03-27T06:30:30Z | uploader | af-south-1 | warning | 4457 | disk watermark crossed, trimmed oldest segments |
| 391 | 2026-03-28T06:31:43Z | compactor | us-west-2 | skipped | 4494 | clock skew corrected against NTP |
| 392 | 2026-03-01T06:32:56Z | watcher | eu-north-1 | ok | 4531 | config reloaded from disk |
| 393 | 2026-03-02T06:33:09Z | renderer | sa-east-1 | pending | 4568 | no change since the previous sweep |
| 394 | 2026-03-03T06:34:22Z | scheduler | us-east-1 | cancelled | 4605 | backpressure from the upstream shard |
| 395 | 2026-03-04T06:35:35Z | gateway | ap-northeast-3 | error | 4642 | DNS lookup retried twice |
| 396 | 2026-03-05T06:36:48Z | indexer | ap-south-1 | retrying | 4679 | restarted after a failed health check |
| 397 | 2026-03-06T06:37:01Z | cache | eu-west-2 | warning | 4716 | leader election completed |
| 398 | 2026-03-07T06:38:14Z | resolver | af-south-1 | skipped | 4753 | manual intervention requested by the operator |
| 399 | 2026-03-08T06:39:27Z | shipper | us-west-2 | ok | 4790 | cold start took longer than the budget |
| 400 | 2026-03-09T06:40:40Z | reaper | eu-north-1 | pending | 4827 | certificate rotated |
| 401 | 2026-03-10T06:41:53Z | notifier | sa-east-1 | cancelled | 4864 | queue drained without incident |
| 402 | 2026-03-11T06:42:06Z | uploader | us-east-1 | error | 4901 | disk watermark crossed, trimmed oldest segments |
| 403 | 2026-03-12T06:43:19Z | compactor | ap-northeast-3 | retrying | 4938 | clock skew corrected against NTP |
| 404 | 2026-03-13T06:44:32Z | watcher | ap-south-1 | warning | 4975 | config reloaded from disk |
| 405 | 2026-03-14T06:45:45Z | renderer | eu-west-2 | skipped | 5012 | no change since the previous sweep |
| 406 | 2026-03-15T06:46:58Z | scheduler | af-south-1 | ok | 5049 | backpressure from the upstream shard |
| 407 | 2026-03-16T06:47:11Z | gateway | us-west-2 | pending | 5086 | DNS lookup retried twice |
| 408 | 2026-03-17T06:48:24Z | indexer | eu-north-1 | cancelled | 5123 | restarted after a failed health check |
| 409 | 2026-03-18T06:49:37Z | cache | sa-east-1 | error | 5160 | leader election completed |
| 410 | 2026-03-19T06:50:50Z | resolver | us-east-1 | retrying | 5197 | manual intervention requested by the operator |
| 411 | 2026-03-20T06:51:03Z | shipper | ap-northeast-3 | warning | 5234 | cold start took longer than the budget |
| 412 | 2026-03-21T06:52:16Z | reaper | ap-south-1 | skipped | 5271 | certificate rotated |
| 413 | 2026-03-22T06:53:29Z | notifier | eu-west-2 | ok | 5308 | queue drained without incident |
| 414 | 2026-03-23T06:54:42Z | uploader | af-south-1 | pending | 5345 | disk watermark crossed, trimmed oldest segments |
| 415 | 2026-03-24T06:55:55Z | compactor | us-west-2 | cancelled | 5382 | clock skew corrected against NTP |
| 416 | 2026-03-25T06:56:08Z | watcher | eu-north-1 | error | 5419 | config reloaded from disk |
| 417 | 2026-03-26T06:57:21Z | renderer | sa-east-1 | retrying | 5456 | no change since the previous sweep |
| 418 | 2026-03-27T06:58:34Z | scheduler | us-east-1 | warning | 5493 | backpressure from the upstream shard |
| 419 | 2026-03-28T06:59:47Z | gateway | ap-northeast-3 | skipped | 5530 | DNS lookup retried twice |
| 420 | 2026-03-01T07:00:00Z | indexer | ap-south-1 | ok | 5567 | restarted after a failed health check |
| 421 | 2026-03-02T07:01:13Z | cache | eu-west-2 | pending | 5604 | leader election completed |
| 422 | 2026-03-03T07:02:26Z | resolver | af-south-1 | cancelled | 5641 | manual intervention requested by the operator |
| 423 | 2026-03-04T07:03:39Z | shipper | us-west-2 | error | 5678 | cold start took longer than the budget |
| 424 | 2026-03-05T07:04:52Z | reaper | eu-north-1 | retrying | 5715 | certificate rotated |
| 425 | 2026-03-06T07:05:05Z | notifier | sa-east-1 | warning | 5752 | queue drained without incident |
| 426 | 2026-03-07T07:06:18Z | uploader | us-east-1 | skipped | 5789 | disk watermark crossed, trimmed oldest segments |
| 427 | 2026-03-08T07:07:31Z | compactor | ap-northeast-3 | ok | 5826 | clock skew corrected against NTP |
| 428 | 2026-03-09T07:08:44Z | watcher | ap-south-1 | pending | 5863 | config reloaded from disk |
| 429 | 2026-03-10T07:09:57Z | renderer | eu-west-2 | cancelled | 5900 | no change since the previous sweep |
| 430 | 2026-03-11T07:10:10Z | scheduler | af-south-1 | error | 5937 | backpressure from the upstream shard |
| 431 | 2026-03-12T07:11:23Z | gateway | us-west-2 | retrying | 5974 | DNS lookup retried twice |
| 432 | 2026-03-13T07:12:36Z | indexer | eu-north-1 | warning | 6011 | restarted after a failed health check |
| 433 | 2026-03-14T07:13:49Z | cache | sa-east-1 | skipped | 6048 | leader election completed |
| 434 | 2026-03-15T07:14:02Z | resolver | us-east-1 | ok | 6085 | manual intervention requested by the operator |
| 435 | 2026-03-16T07:15:15Z | shipper | ap-northeast-3 | pending | 6122 | cold start took longer than the budget |
| 436 | 2026-03-17T07:16:28Z | reaper | ap-south-1 | cancelled | 6159 | certificate rotated |
| 437 | 2026-03-18T07:17:41Z | notifier | eu-west-2 | error | 6196 | queue drained without incident |
| 438 | 2026-03-19T07:18:54Z | uploader | af-south-1 | retrying | 6233 | disk watermark crossed, trimmed oldest segments |
| 439 | 2026-03-20T07:19:07Z | compactor | us-west-2 | warning | 6270 | clock skew corrected against NTP |
| 440 | 2026-03-21T07:20:20Z | watcher | eu-north-1 | skipped | 6307 | config reloaded from disk |
| 441 | 2026-03-22T07:21:33Z | renderer | sa-east-1 | ok | 6344 | no change since the previous sweep |
| 442 | 2026-03-23T07:22:46Z | scheduler | us-east-1 | pending | 6381 | backpressure from the upstream shard |
| 443 | 2026-03-24T07:23:59Z | gateway | ap-northeast-3 | cancelled | 6418 | DNS lookup retried twice |
| 444 | 2026-03-25T07:24:12Z | indexer | ap-south-1 | error | 6455 | restarted after a failed health check |
| 445 | 2026-03-26T07:25:25Z | cache | eu-west-2 | retrying | 6492 | leader election completed |
| 446 | 2026-03-27T07:26:38Z | resolver | af-south-1 | warning | 6529 | manual intervention requested by the operator |
| 447 | 2026-03-28T07:27:51Z | shipper | us-west-2 | skipped | 6566 | cold start took longer than the budget |
| 448 | 2026-03-01T07:28:04Z | reaper | eu-north-1 | ok | 6603 | certificate rotated |
| 449 | 2026-03-02T07:29:17Z | notifier | sa-east-1 | pending | 6640 | queue drained without incident |
| 450 | 2026-03-03T07:30:30Z | uploader | us-east-1 | cancelled | 6677 | disk watermark crossed, trimmed oldest segments |
| 451 | 2026-03-04T07:31:43Z | compactor | ap-northeast-3 | error | 6714 | clock skew corrected against NTP |
| 452 | 2026-03-05T07:32:56Z | watcher | ap-south-1 | retrying | 6751 | config reloaded from disk |
| 453 | 2026-03-06T07:33:09Z | renderer | eu-west-2 | warning | 6788 | no change since the previous sweep |
| 454 | 2026-03-07T07:34:22Z | scheduler | af-south-1 | skipped | 6825 | backpressure from the upstream shard |
| 455 | 2026-03-08T07:35:35Z | gateway | us-west-2 | ok | 6862 | DNS lookup retried twice |
| 456 | 2026-03-09T07:36:48Z | indexer | eu-north-1 | pending | 6899 | restarted after a failed health check |
| 457 | 2026-03-10T07:37:01Z | cache | sa-east-1 | cancelled | 6936 | leader election completed |
| 458 | 2026-03-11T07:38:14Z | resolver | us-east-1 | error | 6973 | manual intervention requested by the operator |
| 459 | 2026-03-12T07:39:27Z | shipper | ap-northeast-3 | retrying | 7010 | cold start took longer than the budget |
| 460 | 2026-03-13T07:40:40Z | reaper | ap-south-1 | warning | 7047 | certificate rotated |
| 461 | 2026-03-14T07:41:53Z | notifier | eu-west-2 | skipped | 7084 | queue drained without incident |
| 462 | 2026-03-15T07:42:06Z | uploader | af-south-1 | ok | 7121 | disk watermark crossed, trimmed oldest segments |
| 463 | 2026-03-16T07:43:19Z | compactor | us-west-2 | pending | 7158 | clock skew corrected against NTP |
| 464 | 2026-03-17T07:44:32Z | watcher | eu-north-1 | cancelled | 7195 | config reloaded from disk |
| 465 | 2026-03-18T07:45:45Z | renderer | sa-east-1 | error | 7232 | no change since the previous sweep |
| 466 | 2026-03-19T07:46:58Z | scheduler | us-east-1 | retrying | 7269 | backpressure from the upstream shard |
| 467 | 2026-03-20T07:47:11Z | gateway | ap-northeast-3 | warning | 7306 | DNS lookup retried twice |
| 468 | 2026-03-21T07:48:24Z | indexer | ap-south-1 | skipped | 7343 | restarted after a failed health check |
| 469 | 2026-03-22T07:49:37Z | cache | eu-west-2 | ok | 7380 | leader election completed |
| 470 | 2026-03-23T07:50:50Z | resolver | af-south-1 | pending | 7417 | manual intervention requested by the operator |
| 471 | 2026-03-24T07:51:03Z | shipper | us-west-2 | cancelled | 7454 | cold start took longer than the budget |
| 472 | 2026-03-25T07:52:16Z | reaper | eu-north-1 | error | 7491 | certificate rotated |
| 473 | 2026-03-26T07:53:29Z | notifier | sa-east-1 | retrying | 7528 | queue drained without incident |
| 474 | 2026-03-27T07:54:42Z | uploader | us-east-1 | warning | 7565 | disk watermark crossed, trimmed oldest segments |
| 475 | 2026-03-28T07:55:55Z | compactor | ap-northeast-3 | skipped | 7602 | clock skew corrected against NTP |
| 476 | 2026-03-01T07:56:08Z | watcher | ap-south-1 | ok | 7639 | config reloaded from disk |
| 477 | 2026-03-02T07:57:21Z | renderer | eu-west-2 | pending | 7676 | no change since the previous sweep |
| 478 | 2026-03-03T07:58:34Z | scheduler | af-south-1 | cancelled | 7713 | backpressure from the upstream shard |
| 479 | 2026-03-04T07:59:47Z | gateway | us-west-2 | error | 7750 | DNS lookup retried twice |
| 480 | 2026-03-05T08:00:00Z | indexer | eu-north-1 | retrying | 7787 | restarted after a failed health check |
| 481 | 2026-03-06T08:01:13Z | cache | sa-east-1 | warning | 7824 | leader election completed |
| 482 | 2026-03-07T08:02:26Z | resolver | us-east-1 | skipped | 7861 | manual intervention requested by the operator |
| 483 | 2026-03-08T08:03:39Z | shipper | ap-northeast-3 | ok | 7898 | cold start took longer than the budget |
| 484 | 2026-03-09T08:04:52Z | reaper | ap-south-1 | pending | 7935 | certificate rotated |
| 485 | 2026-03-10T08:05:05Z | notifier | eu-west-2 | cancelled | 7972 | queue drained without incident |
| 486 | 2026-03-11T08:06:18Z | uploader | af-south-1 | error | 8009 | disk watermark crossed, trimmed oldest segments |
| 487 | 2026-03-12T08:07:31Z | compactor | us-west-2 | retrying | 8046 | clock skew corrected against NTP |
| 488 | 2026-03-13T08:08:44Z | watcher | eu-north-1 | warning | 8083 | config reloaded from disk |
| 489 | 2026-03-14T08:09:57Z | renderer | sa-east-1 | skipped | 8120 | no change since the previous sweep |
| 490 | 2026-03-15T08:10:10Z | scheduler | us-east-1 | ok | 8157 | backpressure from the upstream shard |
| 491 | 2026-03-16T08:11:23Z | gateway | ap-northeast-3 | pending | 8194 | DNS lookup retried twice |
| 492 | 2026-03-17T08:12:36Z | indexer | ap-south-1 | cancelled | 8231 | restarted after a failed health check |
| 493 | 2026-03-18T08:13:49Z | cache | eu-west-2 | error | 8268 | leader election completed |
| 494 | 2026-03-19T08:14:02Z | resolver | af-south-1 | retrying | 8305 | manual intervention requested by the operator |
| 495 | 2026-03-20T08:15:15Z | shipper | us-west-2 | warning | 8342 | cold start took longer than the budget |
| 496 | 2026-03-21T08:16:28Z | reaper | eu-north-1 | skipped | 8379 | certificate rotated |
| 497 | 2026-03-22T08:17:41Z | notifier | sa-east-1 | ok | 8416 | queue drained without incident |
| 498 | 2026-03-23T08:18:54Z | uploader | us-east-1 | pending | 8453 | disk watermark crossed, trimmed oldest segments |
| 499 | 2026-03-24T08:19:07Z | compactor | ap-northeast-3 | cancelled | 8490 | clock skew corrected against NTP |
| 500 | 2026-03-25T08:20:20Z | watcher | ap-south-1 | error | 8527 | config reloaded from disk |
| 501 | 2026-03-26T08:21:33Z | renderer | eu-west-2 | retrying | 8564 | no change since the previous sweep |
| 502 | 2026-03-27T08:22:46Z | scheduler | af-south-1 | warning | 8601 | backpressure from the upstream shard |
| 503 | 2026-03-28T08:23:59Z | gateway | us-west-2 | skipped | 8638 | DNS lookup retried twice |
| 504 | 2026-03-01T08:24:12Z | indexer | eu-north-1 | ok | 8675 | restarted after a failed health check |
| 505 | 2026-03-02T08:25:25Z | cache | sa-east-1 | pending | 8712 | leader election completed |
| 506 | 2026-03-03T08:26:38Z | resolver | us-east-1 | cancelled | 8749 | manual intervention requested by the operator |
| 507 | 2026-03-04T08:27:51Z | shipper | ap-northeast-3 | error | 8786 | cold start took longer than the budget |
| 508 | 2026-03-05T08:28:04Z | reaper | ap-south-1 | retrying | 8823 | certificate rotated |
| 509 | 2026-03-06T08:29:17Z | notifier | eu-west-2 | warning | 8860 | queue drained without incident |
| 510 | 2026-03-07T08:30:30Z | uploader | af-south-1 | skipped | 8897 | disk watermark crossed, trimmed oldest segments |
| 511 | 2026-03-08T08:31:43Z | compactor | us-west-2 | ok | 8934 | clock skew corrected against NTP |
| 512 | 2026-03-09T08:32:56Z | watcher | eu-north-1 | pending | 8971 | config reloaded from disk |
| 513 | 2026-03-10T08:33:09Z | renderer | sa-east-1 | cancelled | 9008 | no change since the previous sweep |
| 514 | 2026-03-11T08:34:22Z | scheduler | us-east-1 | error | 9045 | backpressure from the upstream shard |
| 515 | 2026-03-12T08:35:35Z | gateway | ap-northeast-3 | retrying | 9082 | DNS lookup retried twice |
| 516 | 2026-03-13T08:36:48Z | indexer | ap-south-1 | warning | 9119 | restarted after a failed health check |
| 517 | 2026-03-14T08:37:01Z | cache | eu-west-2 | skipped | 9156 | leader election completed |
| 518 | 2026-03-15T08:38:14Z | resolver | af-south-1 | ok | 9193 | manual intervention requested by the operator |
| 519 | 2026-03-16T08:39:27Z | shipper | us-west-2 | pending | 9230 | cold start took longer than the budget |
| 520 | 2026-03-17T08:40:40Z | reaper | eu-north-1 | cancelled | 9267 | certificate rotated |
| 521 | 2026-03-18T08:41:53Z | notifier | sa-east-1 | error | 9304 | queue drained without incident |
| 522 | 2026-03-19T08:42:06Z | uploader | us-east-1 | retrying | 9341 | disk watermark crossed, trimmed oldest segments |
| 523 | 2026-03-20T08:43:19Z | compactor | ap-northeast-3 | warning | 9378 | clock skew corrected against NTP |
| 524 | 2026-03-21T08:44:32Z | watcher | ap-south-1 | skipped | 9415 | config reloaded from disk |
| 525 | 2026-03-22T08:45:45Z | renderer | eu-west-2 | ok | 9452 | no change since the previous sweep |
| 526 | 2026-03-23T08:46:58Z | scheduler | af-south-1 | pending | 9489 | backpressure from the upstream shard |
| 527 | 2026-03-24T08:47:11Z | gateway | us-west-2 | cancelled | 9526 | DNS lookup retried twice |
| 528 | 2026-03-25T08:48:24Z | indexer | eu-north-1 | error | 9563 | restarted after a failed health check |
| 529 | 2026-03-26T08:49:37Z | cache | sa-east-1 | retrying | 9600 | leader election completed |
| 530 | 2026-03-27T08:50:50Z | resolver | us-east-1 | warning | 9637 | manual intervention requested by the operator |
| 531 | 2026-03-28T08:51:03Z | shipper | ap-northeast-3 | skipped | 9674 | cold start took longer than the budget |
| 532 | 2026-03-01T08:52:16Z | reaper | ap-south-1 | ok | 9711 | certificate rotated |
| 533 | 2026-03-02T08:53:29Z | notifier | eu-west-2 | pending | 9748 | queue drained without incident |
| 534 | 2026-03-03T08:54:42Z | uploader | af-south-1 | cancelled | 9785 | disk watermark crossed, trimmed oldest segments |
| 535 | 2026-03-04T08:55:55Z | compactor | us-west-2 | error | 9822 | clock skew corrected against NTP |
| 536 | 2026-03-05T08:56:08Z | watcher | eu-north-1 | retrying | 9859 | config reloaded from disk |
| 537 | 2026-03-06T08:57:21Z | renderer | sa-east-1 | warning | 9896 | no change since the previous sweep |
| 538 | 2026-03-07T08:58:34Z | scheduler | us-east-1 | skipped | 9933 | backpressure from the upstream shard |
| 539 | 2026-03-08T08:59:47Z | gateway | ap-northeast-3 | ok | 9970 | DNS lookup retried twice |
| 540 | 2026-03-09T09:00:00Z | indexer | ap-south-1 | pending | 34 | restarted after a failed health check |
| 541 | 2026-03-10T09:01:13Z | cache | eu-west-2 | cancelled | 71 | leader election completed |
| 542 | 2026-03-11T09:02:26Z | resolver | af-south-1 | error | 108 | manual intervention requested by the operator |
| 543 | 2026-03-12T09:03:39Z | shipper | us-west-2 | retrying | 145 | cold start took longer than the budget |
| 544 | 2026-03-13T09:04:52Z | reaper | eu-north-1 | warning | 182 | certificate rotated |
| 545 | 2026-03-14T09:05:05Z | notifier | sa-east-1 | skipped | 219 | queue drained without incident |
| 546 | 2026-03-15T09:06:18Z | uploader | us-east-1 | ok | 256 | disk watermark crossed, trimmed oldest segments |
| 547 | 2026-03-16T09:07:31Z | compactor | ap-northeast-3 | pending | 293 | clock skew corrected against NTP |
| 548 | 2026-03-17T09:08:44Z | watcher | ap-south-1 | cancelled | 330 | config reloaded from disk |
| 549 | 2026-03-18T09:09:57Z | renderer | eu-west-2 | error | 367 | no change since the previous sweep |
| 550 | 2026-03-19T09:10:10Z | scheduler | af-south-1 | retrying | 404 | backpressure from the upstream shard |
| 551 | 2026-03-20T09:11:23Z | gateway | us-west-2 | warning | 441 | DNS lookup retried twice |
| 552 | 2026-03-21T09:12:36Z | indexer | eu-north-1 | skipped | 478 | restarted after a failed health check |
| 553 | 2026-03-22T09:13:49Z | cache | sa-east-1 | ok | 515 | leader election completed |
| 554 | 2026-03-23T09:14:02Z | resolver | us-east-1 | pending | 552 | manual intervention requested by the operator |
| 555 | 2026-03-24T09:15:15Z | shipper | ap-northeast-3 | cancelled | 589 | cold start took longer than the budget |
| 556 | 2026-03-25T09:16:28Z | reaper | ap-south-1 | error | 626 | certificate rotated |
| 557 | 2026-03-26T09:17:41Z | notifier | eu-west-2 | retrying | 663 | queue drained without incident |
| 558 | 2026-03-27T09:18:54Z | uploader | af-south-1 | warning | 700 | disk watermark crossed, trimmed oldest segments |
| 559 | 2026-03-28T09:19:07Z | compactor | us-west-2 | skipped | 737 | clock skew corrected against NTP |
| 560 | 2026-03-01T09:20:20Z | watcher | eu-north-1 | ok | 774 | config reloaded from disk |
| 561 | 2026-03-02T09:21:33Z | renderer | sa-east-1 | pending | 811 | no change since the previous sweep |
| 562 | 2026-03-03T09:22:46Z | scheduler | us-east-1 | cancelled | 848 | backpressure from the upstream shard |
| 563 | 2026-03-04T09:23:59Z | gateway | ap-northeast-3 | error | 885 | DNS lookup retried twice |
| 564 | 2026-03-05T09:24:12Z | indexer | ap-south-1 | retrying | 922 | restarted after a failed health check |
| 565 | 2026-03-06T09:25:25Z | cache | eu-west-2 | warning | 959 | leader election completed |
| 566 | 2026-03-07T09:26:38Z | resolver | af-south-1 | skipped | 996 | manual intervention requested by the operator |
| 567 | 2026-03-08T09:27:51Z | shipper | us-west-2 | ok | 1033 | cold start took longer than the budget |
| 568 | 2026-03-09T09:28:04Z | reaper | eu-north-1 | pending | 1070 | certificate rotated |
| 569 | 2026-03-10T09:29:17Z | notifier | sa-east-1 | cancelled | 1107 | queue drained without incident |
| 570 | 2026-03-11T09:30:30Z | uploader | us-east-1 | error | 1144 | disk watermark crossed, trimmed oldest segments |
| 571 | 2026-03-12T09:31:43Z | compactor | ap-northeast-3 | retrying | 1181 | clock skew corrected against NTP |
| 572 | 2026-03-13T09:32:56Z | watcher | ap-south-1 | warning | 1218 | config reloaded from disk |
| 573 | 2026-03-14T09:33:09Z | renderer | eu-west-2 | skipped | 1255 | no change since the previous sweep |
| 574 | 2026-03-15T09:34:22Z | scheduler | af-south-1 | ok | 1292 | backpressure from the upstream shard |
| 575 | 2026-03-16T09:35:35Z | gateway | us-west-2 | pending | 1329 | DNS lookup retried twice |
| 576 | 2026-03-17T09:36:48Z | indexer | eu-north-1 | cancelled | 1366 | restarted after a failed health check |
| 577 | 2026-03-18T09:37:01Z | cache | sa-east-1 | error | 1403 | leader election completed |
| 578 | 2026-03-19T09:38:14Z | resolver | us-east-1 | retrying | 1440 | manual intervention requested by the operator |
| 579 | 2026-03-20T09:39:27Z | shipper | ap-northeast-3 | warning | 1477 | cold start took longer than the budget |
| 580 | 2026-03-21T09:40:40Z | reaper | ap-south-1 | skipped | 1514 | certificate rotated |
| 581 | 2026-03-22T09:41:53Z | notifier | eu-west-2 | ok | 1551 | queue drained without incident |
| 582 | 2026-03-23T09:42:06Z | uploader | af-south-1 | pending | 1588 | disk watermark crossed, trimmed oldest segments |
| 583 | 2026-03-24T09:43:19Z | compactor | us-west-2 | cancelled | 1625 | clock skew corrected against NTP |
| 584 | 2026-03-25T09:44:32Z | watcher | eu-north-1 | error | 1662 | config reloaded from disk |
| 585 | 2026-03-26T09:45:45Z | renderer | sa-east-1 | retrying | 1699 | no change since the previous sweep |
| 586 | 2026-03-27T09:46:58Z | scheduler | us-east-1 | warning | 1736 | backpressure from the upstream shard |
| 587 | 2026-03-28T09:47:11Z | gateway | ap-northeast-3 | skipped | 1773 | DNS lookup retried twice |
| 588 | 2026-03-01T09:48:24Z | indexer | ap-south-1 | ok | 1810 | restarted after a failed health check |
| 589 | 2026-03-02T09:49:37Z | cache | eu-west-2 | pending | 1847 | leader election completed |
| 590 | 2026-03-03T09:50:50Z | resolver | af-south-1 | cancelled | 1884 | manual intervention requested by the operator |
| 591 | 2026-03-04T09:51:03Z | shipper | us-west-2 | error | 1921 | cold start took longer than the budget |
| 592 | 2026-03-05T09:52:16Z | reaper | eu-north-1 | retrying | 1958 | certificate rotated |
| 593 | 2026-03-06T09:53:29Z | notifier | sa-east-1 | warning | 1995 | queue drained without incident |
| 594 | 2026-03-07T09:54:42Z | uploader | us-east-1 | skipped | 2032 | disk watermark crossed, trimmed oldest segments |
| 595 | 2026-03-08T09:55:55Z | compactor | ap-northeast-3 | ok | 2069 | clock skew corrected against NTP |
| 596 | 2026-03-09T09:56:08Z | watcher | ap-south-1 | pending | 2106 | config reloaded from disk |
| 597 | 2026-03-10T09:57:21Z | renderer | eu-west-2 | cancelled | 2143 | no change since the previous sweep |
| 598 | 2026-03-11T09:58:34Z | scheduler | af-south-1 | error | 2180 | backpressure from the upstream shard |
| 599 | 2026-03-12T09:59:47Z | gateway | us-west-2 | retrying | 2217 | DNS lookup retried twice |
| 600 | 2026-03-13T10:00:00Z | indexer | eu-north-1 | warning | 2254 | restarted after a failed health check |
| 601 | 2026-03-14T10:01:13Z | cache | sa-east-1 | skipped | 2291 | leader election completed |
| 602 | 2026-03-15T10:02:26Z | resolver | us-east-1 | ok | 2328 | manual intervention requested by the operator |
| 603 | 2026-03-16T10:03:39Z | shipper | ap-northeast-3 | pending | 2365 | cold start took longer than the budget |
| 604 | 2026-03-17T10:04:52Z | reaper | ap-south-1 | cancelled | 2402 | certificate rotated |
| 605 | 2026-03-18T10:05:05Z | notifier | eu-west-2 | error | 2439 | queue drained without incident |
| 606 | 2026-03-19T10:06:18Z | uploader | af-south-1 | retrying | 2476 | disk watermark crossed, trimmed oldest segments |
| 607 | 2026-03-20T10:07:31Z | compactor | us-west-2 | warning | 2513 | clock skew corrected against NTP |
| 608 | 2026-03-21T10:08:44Z | watcher | eu-north-1 | skipped | 2550 | config reloaded from disk |
| 609 | 2026-03-22T10:09:57Z | renderer | sa-east-1 | ok | 2587 | no change since the previous sweep |
| 610 | 2026-03-23T10:10:10Z | scheduler | us-east-1 | pending | 2624 | backpressure from the upstream shard |
| 611 | 2026-03-24T10:11:23Z | gateway | ap-northeast-3 | cancelled | 2661 | DNS lookup retried twice |
| 612 | 2026-03-25T10:12:36Z | indexer | ap-south-1 | error | 2698 | restarted after a failed health check |
| 613 | 2026-03-26T10:13:49Z | cache | eu-west-2 | retrying | 2735 | leader election completed |
| 614 | 2026-03-27T10:14:02Z | resolver | af-south-1 | warning | 2772 | manual intervention requested by the operator |
| 615 | 2026-03-28T10:15:15Z | shipper | us-west-2 | skipped | 2809 | cold start took longer than the budget |
| 616 | 2026-03-01T10:16:28Z | reaper | eu-north-1 | ok | 2846 | certificate rotated |
| 617 | 2026-03-02T10:17:41Z | notifier | sa-east-1 | pending | 2883 | queue drained without incident |
| 618 | 2026-03-03T10:18:54Z | uploader | us-east-1 | cancelled | 2920 | disk watermark crossed, trimmed oldest segments |
| 619 | 2026-03-04T10:19:07Z | compactor | ap-northeast-3 | error | 2957 | clock skew corrected against NTP |
| 620 | 2026-03-05T10:20:20Z | watcher | ap-south-1 | retrying | 2994 | config reloaded from disk |
| 621 | 2026-03-06T10:21:33Z | renderer | eu-west-2 | warning | 3031 | no change since the previous sweep |
| 622 | 2026-03-07T10:22:46Z | scheduler | af-south-1 | skipped | 3068 | backpressure from the upstream shard |
| 623 | 2026-03-08T10:23:59Z | gateway | us-west-2 | ok | 3105 | DNS lookup retried twice |
| 624 | 2026-03-09T10:24:12Z | indexer | eu-north-1 | pending | 3142 | restarted after a failed health check |
| 625 | 2026-03-10T10:25:25Z | cache | sa-east-1 | cancelled | 3179 | leader election completed |
| 626 | 2026-03-11T10:26:38Z | resolver | us-east-1 | error | 3216 | manual intervention requested by the operator |
| 627 | 2026-03-12T10:27:51Z | shipper | ap-northeast-3 | retrying | 3253 | cold start took longer than the budget |
| 628 | 2026-03-13T10:28:04Z | reaper | ap-south-1 | warning | 3290 | certificate rotated |
| 629 | 2026-03-14T10:29:17Z | notifier | eu-west-2 | skipped | 3327 | queue drained without incident |
| 630 | 2026-03-15T10:30:30Z | uploader | af-south-1 | ok | 3364 | disk watermark crossed, trimmed oldest segments |
| 631 | 2026-03-16T10:31:43Z | compactor | us-west-2 | pending | 3401 | clock skew corrected against NTP |
| 632 | 2026-03-17T10:32:56Z | watcher | eu-north-1 | cancelled | 3438 | config reloaded from disk |
| 633 | 2026-03-18T10:33:09Z | renderer | sa-east-1 | error | 3475 | no change since the previous sweep |
| 634 | 2026-03-19T10:34:22Z | scheduler | us-east-1 | retrying | 3512 | backpressure from the upstream shard |
| 635 | 2026-03-20T10:35:35Z | gateway | ap-northeast-3 | warning | 3549 | DNS lookup retried twice |
| 636 | 2026-03-21T10:36:48Z | indexer | ap-south-1 | skipped | 3586 | restarted after a failed health check |
| 637 | 2026-03-22T10:37:01Z | cache | eu-west-2 | ok | 3623 | leader election completed |
| 638 | 2026-03-23T10:38:14Z | resolver | af-south-1 | pending | 3660 | manual intervention requested by the operator |
| 639 | 2026-03-24T10:39:27Z | shipper | us-west-2 | cancelled | 3697 | cold start took longer than the budget |
| 640 | 2026-03-25T10:40:40Z | reaper | eu-north-1 | error | 3734 | certificate rotated |
| 641 | 2026-03-26T10:41:53Z | notifier | sa-east-1 | retrying | 3771 | queue drained without incident |
| 642 | 2026-03-27T10:42:06Z | uploader | us-east-1 | warning | 3808 | disk watermark crossed, trimmed oldest segments |
| 643 | 2026-03-28T10:43:19Z | compactor | ap-northeast-3 | skipped | 3845 | clock skew corrected against NTP |
| 644 | 2026-03-01T10:44:32Z | watcher | ap-south-1 | ok | 3882 | config reloaded from disk |
| 645 | 2026-03-02T10:45:45Z | renderer | eu-west-2 | pending | 3919 | no change since the previous sweep |
| 646 | 2026-03-03T10:46:58Z | scheduler | af-south-1 | cancelled | 3956 | backpressure from the upstream shard |
| 647 | 2026-03-04T10:47:11Z | gateway | us-west-2 | error | 3993 | DNS lookup retried twice |
| 648 | 2026-03-05T10:48:24Z | indexer | eu-north-1 | retrying | 4030 | restarted after a failed health check |
| 649 | 2026-03-06T10:49:37Z | cache | sa-east-1 | warning | 4067 | leader election completed |
| 650 | 2026-03-07T10:50:50Z | resolver | us-east-1 | skipped | 4104 | manual intervention requested by the operator |
| 651 | 2026-03-08T10:51:03Z | shipper | ap-northeast-3 | ok | 4141 | cold start took longer than the budget |
| 652 | 2026-03-09T10:52:16Z | reaper | ap-south-1 | pending | 4178 | certificate rotated |
| 653 | 2026-03-10T10:53:29Z | notifier | eu-west-2 | cancelled | 4215 | queue drained without incident |
| 654 | 2026-03-11T10:54:42Z | uploader | af-south-1 | error | 4252 | disk watermark crossed, trimmed oldest segments |
| 655 | 2026-03-12T10:55:55Z | compactor | us-west-2 | retrying | 4289 | clock skew corrected against NTP |
| 656 | 2026-03-13T10:56:08Z | watcher | eu-north-1 | warning | 4326 | config reloaded from disk |
| 657 | 2026-03-14T10:57:21Z | renderer | sa-east-1 | skipped | 4363 | no change since the previous sweep |
| 658 | 2026-03-15T10:58:34Z | scheduler | us-east-1 | ok | 4400 | backpressure from the upstream shard |
| 659 | 2026-03-16T10:59:47Z | gateway | ap-northeast-3 | pending | 4437 | DNS lookup retried twice |
| 660 | 2026-03-17T11:00:00Z | indexer | ap-south-1 | cancelled | 4474 | restarted after a failed health check |
| 661 | 2026-03-18T11:01:13Z | cache | eu-west-2 | error | 4511 | leader election completed |
| 662 | 2026-03-19T11:02:26Z | resolver | af-south-1 | retrying | 4548 | manual intervention requested by the operator |
| 663 | 2026-03-20T11:03:39Z | shipper | us-west-2 | warning | 4585 | cold start took longer than the budget |
| 664 | 2026-03-21T11:04:52Z | reaper | eu-north-1 | skipped | 4622 | certificate rotated |
| 665 | 2026-03-22T11:05:05Z | notifier | sa-east-1 | ok | 4659 | queue drained without incident |
| 666 | 2026-03-23T11:06:18Z | uploader | us-east-1 | pending | 4696 | disk watermark crossed, trimmed oldest segments |
| 667 | 2026-03-24T11:07:31Z | compactor | ap-northeast-3 | cancelled | 4733 | clock skew corrected against NTP |
| 668 | 2026-03-25T11:08:44Z | watcher | ap-south-1 | error | 4770 | config reloaded from disk |
| 669 | 2026-03-26T11:09:57Z | renderer | eu-west-2 | retrying | 4807 | no change since the previous sweep |
| 670 | 2026-03-27T11:10:10Z | scheduler | af-south-1 | warning | 4844 | backpressure from the upstream shard |
| 671 | 2026-03-28T11:11:23Z | gateway | us-west-2 | skipped | 4881 | DNS lookup retried twice |
| 672 | 2026-03-01T11:12:36Z | indexer | eu-north-1 | ok | 4918 | restarted after a failed health check |
| 673 | 2026-03-02T11:13:49Z | cache | sa-east-1 | pending | 4955 | leader election completed |
| 674 | 2026-03-03T11:14:02Z | resolver | us-east-1 | cancelled | 4992 | manual intervention requested by the operator |
| 675 | 2026-03-04T11:15:15Z | shipper | ap-northeast-3 | error | 5029 | cold start took longer than the budget |
| 676 | 2026-03-05T11:16:28Z | reaper | ap-south-1 | retrying | 5066 | certificate rotated |
| 677 | 2026-03-06T11:17:41Z | notifier | eu-west-2 | warning | 5103 | queue drained without incident |
| 678 | 2026-03-07T11:18:54Z | uploader | af-south-1 | skipped | 5140 | disk watermark crossed, trimmed oldest segments |
| 679 | 2026-03-08T11:19:07Z | compactor | us-west-2 | ok | 5177 | clock skew corrected against NTP |
| 680 | 2026-03-09T11:20:20Z | watcher | eu-north-1 | pending | 5214 | config reloaded from disk |
| 681 | 2026-03-10T11:21:33Z | renderer | sa-east-1 | cancelled | 5251 | no change since the previous sweep |
| 682 | 2026-03-11T11:22:46Z | scheduler | us-east-1 | error | 5288 | backpressure from the upstream shard |
| 683 | 2026-03-12T11:23:59Z | gateway | ap-northeast-3 | retrying | 5325 | DNS lookup retried twice |
| 684 | 2026-03-13T11:24:12Z | indexer | ap-south-1 | warning | 5362 | restarted after a failed health check |
| 685 | 2026-03-14T11:25:25Z | cache | eu-west-2 | skipped | 5399 | leader election completed |
| 686 | 2026-03-15T11:26:38Z | resolver | af-south-1 | ok | 5436 | manual intervention requested by the operator |
| 687 | 2026-03-16T11:27:51Z | shipper | us-west-2 | pending | 5473 | cold start took longer than the budget |
| 688 | 2026-03-17T11:28:04Z | reaper | eu-north-1 | cancelled | 5510 | certificate rotated |
| 689 | 2026-03-18T11:29:17Z | notifier | sa-east-1 | error | 5547 | queue drained without incident |
| 690 | 2026-03-19T11:30:30Z | uploader | us-east-1 | retrying | 5584 | disk watermark crossed, trimmed oldest segments |
| 691 | 2026-03-20T11:31:43Z | compactor | ap-northeast-3 | warning | 5621 | clock skew corrected against NTP |
| 692 | 2026-03-21T11:32:56Z | watcher | ap-south-1 | skipped | 5658 | config reloaded from disk |
| 693 | 2026-03-22T11:33:09Z | renderer | eu-west-2 | ok | 5695 | no change since the previous sweep |
| 694 | 2026-03-23T11:34:22Z | scheduler | af-south-1 | pending | 5732 | backpressure from the upstream shard |
| 695 | 2026-03-24T11:35:35Z | gateway | us-west-2 | cancelled | 5769 | DNS lookup retried twice |
| 696 | 2026-03-25T11:36:48Z | indexer | eu-north-1 | error | 5806 | restarted after a failed health check |
| 697 | 2026-03-26T11:37:01Z | cache | sa-east-1 | retrying | 5843 | leader election completed |
| 698 | 2026-03-27T11:38:14Z | resolver | us-east-1 | warning | 5880 | manual intervention requested by the operator |
| 699 | 2026-03-28T11:39:27Z | shipper | ap-northeast-3 | skipped | 5917 | cold start took longer than the budget |
| 700 | 2026-03-01T11:40:40Z | reaper | ap-south-1 | ok | 5954 | certificate rotated |
| 701 | 2026-03-02T11:41:53Z | notifier | eu-west-2 | pending | 5991 | queue drained without incident |
| 702 | 2026-03-03T11:42:06Z | uploader | af-south-1 | cancelled | 6028 | disk watermark crossed, trimmed oldest segments |
| 703 | 2026-03-04T11:43:19Z | compactor | us-west-2 | error | 6065 | clock skew corrected against NTP |
| 704 | 2026-03-05T11:44:32Z | watcher | eu-north-1 | retrying | 6102 | config reloaded from disk |
| 705 | 2026-03-06T11:45:45Z | renderer | sa-east-1 | warning | 6139 | no change since the previous sweep |
| 706 | 2026-03-07T11:46:58Z | scheduler | us-east-1 | skipped | 6176 | backpressure from the upstream shard |
| 707 | 2026-03-08T11:47:11Z | gateway | ap-northeast-3 | ok | 6213 | DNS lookup retried twice |
| 708 | 2026-03-09T11:48:24Z | indexer | ap-south-1 | pending | 6250 | restarted after a failed health check |
| 709 | 2026-03-10T11:49:37Z | cache | eu-west-2 | cancelled | 6287 | leader election completed |
| 710 | 2026-03-11T11:50:50Z | resolver | af-south-1 | error | 6324 | manual intervention requested by the operator |
| 711 | 2026-03-12T11:51:03Z | shipper | us-west-2 | retrying | 6361 | cold start took longer than the budget |
| 712 | 2026-03-13T11:52:16Z | reaper | eu-north-1 | warning | 6398 | certificate rotated |
| 713 | 2026-03-14T11:53:29Z | notifier | sa-east-1 | skipped | 6435 | queue drained without incident |
| 714 | 2026-03-15T11:54:42Z | uploader | us-east-1 | ok | 6472 | disk watermark crossed, trimmed oldest segments |
| 715 | 2026-03-16T11:55:55Z | compactor | ap-northeast-3 | pending | 6509 | clock skew corrected against NTP |
| 716 | 2026-03-17T11:56:08Z | watcher | ap-south-1 | cancelled | 6546 | config reloaded from disk |
| 717 | 2026-03-18T11:57:21Z | renderer | eu-west-2 | error | 6583 | no change since the previous sweep |
| 718 | 2026-03-19T11:58:34Z | scheduler | af-south-1 | retrying | 6620 | backpressure from the upstream shard |
| 719 | 2026-03-20T11:59:47Z | gateway | us-west-2 | warning | 6657 | DNS lookup retried twice |
| 720 | 2026-03-21T12:00:00Z | indexer | eu-north-1 | skipped | 6694 | restarted after a failed health check |
| 721 | 2026-03-22T12:01:13Z | cache | sa-east-1 | ok | 6731 | leader election completed |
| 722 | 2026-03-23T12:02:26Z | resolver | us-east-1 | pending | 6768 | manual intervention requested by the operator |
| 723 | 2026-03-24T12:03:39Z | shipper | ap-northeast-3 | cancelled | 6805 | cold start took longer than the budget |
| 724 | 2026-03-25T12:04:52Z | reaper | ap-south-1 | error | 6842 | certificate rotated |
| 725 | 2026-03-26T12:05:05Z | notifier | eu-west-2 | retrying | 6879 | queue drained without incident |
| 726 | 2026-03-27T12:06:18Z | uploader | af-south-1 | warning | 6916 | disk watermark crossed, trimmed oldest segments |
| 727 | 2026-03-28T12:07:31Z | compactor | us-west-2 | skipped | 6953 | clock skew corrected against NTP |
| 728 | 2026-03-01T12:08:44Z | watcher | eu-north-1 | ok | 6990 | config reloaded from disk |
| 729 | 2026-03-02T12:09:57Z | renderer | sa-east-1 | pending | 7027 | no change since the previous sweep |
| 730 | 2026-03-03T12:10:10Z | scheduler | us-east-1 | cancelled | 7064 | backpressure from the upstream shard |
| 731 | 2026-03-04T12:11:23Z | gateway | ap-northeast-3 | error | 7101 | DNS lookup retried twice |
| 732 | 2026-03-05T12:12:36Z | indexer | ap-south-1 | retrying | 7138 | restarted after a failed health check |
| 733 | 2026-03-06T12:13:49Z | cache | eu-west-2 | warning | 7175 | leader election completed |
| 734 | 2026-03-07T12:14:02Z | resolver | af-south-1 | skipped | 7212 | manual intervention requested by the operator |
| 735 | 2026-03-08T12:15:15Z | shipper | us-west-2 | ok | 7249 | cold start took longer than the budget |
| 736 | 2026-03-09T12:16:28Z | reaper | eu-north-1 | pending | 7286 | certificate rotated |
| 737 | 2026-03-10T12:17:41Z | notifier | sa-east-1 | cancelled | 7323 | queue drained without incident |
| 738 | 2026-03-11T12:18:54Z | uploader | us-east-1 | error | 7360 | disk watermark crossed, trimmed oldest segments |
| 739 | 2026-03-12T12:19:07Z | compactor | ap-northeast-3 | retrying | 7397 | clock skew corrected against NTP |
| 740 | 2026-03-13T12:20:20Z | watcher | ap-south-1 | warning | 7434 | config reloaded from disk |
| 741 | 2026-03-14T12:21:33Z | renderer | eu-west-2 | skipped | 7471 | no change since the previous sweep |
| 742 | 2026-03-15T12:22:46Z | scheduler | af-south-1 | ok | 7508 | backpressure from the upstream shard |
| 743 | 2026-03-16T12:23:59Z | gateway | us-west-2 | pending | 7545 | DNS lookup retried twice |
| 744 | 2026-03-17T12:24:12Z | indexer | eu-north-1 | cancelled | 7582 | restarted after a failed health check |
| 745 | 2026-03-18T12:25:25Z | cache | sa-east-1 | error | 7619 | leader election completed |
| 746 | 2026-03-19T12:26:38Z | resolver | us-east-1 | retrying | 7656 | manual intervention requested by the operator |
| 747 | 2026-03-20T12:27:51Z | shipper | ap-northeast-3 | warning | 7693 | cold start took longer than the budget |
| 748 | 2026-03-21T12:28:04Z | reaper | ap-south-1 | skipped | 7730 | certificate rotated |
| 749 | 2026-03-22T12:29:17Z | notifier | eu-west-2 | ok | 7767 | queue drained without incident |
| 750 | 2026-03-23T12:30:30Z | uploader | af-south-1 | pending | 7804 | disk watermark crossed, trimmed oldest segments |
| 751 | 2026-03-24T12:31:43Z | compactor | us-west-2 | cancelled | 7841 | clock skew corrected against NTP |
| 752 | 2026-03-25T12:32:56Z | watcher | eu-north-1 | error | 7878 | config reloaded from disk |
| 753 | 2026-03-26T12:33:09Z | renderer | sa-east-1 | retrying | 7915 | no change since the previous sweep |
| 754 | 2026-03-27T12:34:22Z | scheduler | us-east-1 | warning | 7952 | backpressure from the upstream shard |
| 755 | 2026-03-28T12:35:35Z | gateway | ap-northeast-3 | skipped | 7989 | DNS lookup retried twice |
| 756 | 2026-03-01T12:36:48Z | indexer | ap-south-1 | ok | 8026 | restarted after a failed health check |
| 757 | 2026-03-02T12:37:01Z | cache | eu-west-2 | pending | 8063 | leader election completed |
| 758 | 2026-03-03T12:38:14Z | resolver | af-south-1 | cancelled | 8100 | manual intervention requested by the operator |
| 759 | 2026-03-04T12:39:27Z | shipper | us-west-2 | error | 8137 | cold start took longer than the budget |
| 760 | 2026-03-05T12:40:40Z | reaper | eu-north-1 | retrying | 8174 | certificate rotated |
| 761 | 2026-03-06T12:41:53Z | notifier | sa-east-1 | warning | 8211 | queue drained without incident |
| 762 | 2026-03-07T12:42:06Z | uploader | us-east-1 | skipped | 8248 | disk watermark crossed, trimmed oldest segments |
| 763 | 2026-03-08T12:43:19Z | compactor | ap-northeast-3 | ok | 8285 | clock skew corrected against NTP |
| 764 | 2026-03-09T12:44:32Z | watcher | ap-south-1 | pending | 8322 | config reloaded from disk |
| 765 | 2026-03-10T12:45:45Z | renderer | eu-west-2 | cancelled | 8359 | no change since the previous sweep |
| 766 | 2026-03-11T12:46:58Z | scheduler | af-south-1 | error | 8396 | backpressure from the upstream shard |
| 767 | 2026-03-12T12:47:11Z | gateway | us-west-2 | retrying | 8433 | DNS lookup retried twice |
| 768 | 2026-03-13T12:48:24Z | indexer | eu-north-1 | warning | 8470 | restarted after a failed health check |
| 769 | 2026-03-14T12:49:37Z | cache | sa-east-1 | skipped | 8507 | leader election completed |
| 770 | 2026-03-15T12:50:50Z | resolver | us-east-1 | ok | 8544 | manual intervention requested by the operator |
| 771 | 2026-03-16T12:51:03Z | shipper | ap-northeast-3 | pending | 8581 | cold start took longer than the budget |
| 772 | 2026-03-17T12:52:16Z | reaper | ap-south-1 | cancelled | 8618 | certificate rotated |
| 773 | 2026-03-18T12:53:29Z | notifier | eu-west-2 | error | 8655 | queue drained without incident |
| 774 | 2026-03-19T12:54:42Z | uploader | af-south-1 | retrying | 8692 | disk watermark crossed, trimmed oldest segments |
| 775 | 2026-03-20T12:55:55Z | compactor | us-west-2 | warning | 8729 | clock skew corrected against NTP |
| 776 | 2026-03-21T12:56:08Z | watcher | eu-north-1 | skipped | 8766 | config reloaded from disk |
| 777 | 2026-03-22T12:57:21Z | renderer | sa-east-1 | ok | 8803 | no change since the previous sweep |
| 778 | 2026-03-23T12:58:34Z | scheduler | us-east-1 | pending | 8840 | backpressure from the upstream shard |
| 779 | 2026-03-24T12:59:47Z | gateway | ap-northeast-3 | cancelled | 8877 | DNS lookup retried twice |
| 780 | 2026-03-25T13:00:00Z | indexer | ap-south-1 | error | 8914 | restarted after a failed health check |
| 781 | 2026-03-26T13:01:13Z | cache | eu-west-2 | retrying | 8951 | leader election completed |
| 782 | 2026-03-27T13:02:26Z | resolver | af-south-1 | warning | 8988 | manual intervention requested by the operator |
| 783 | 2026-03-28T13:03:39Z | shipper | us-west-2 | skipped | 9025 | cold start took longer than the budget |
| 784 | 2026-03-01T13:04:52Z | reaper | eu-north-1 | ok | 9062 | certificate rotated |
| 785 | 2026-03-02T13:05:05Z | notifier | sa-east-1 | pending | 9099 | queue drained without incident |
| 786 | 2026-03-03T13:06:18Z | uploader | us-east-1 | cancelled | 9136 | disk watermark crossed, trimmed oldest segments |
| 787 | 2026-03-04T13:07:31Z | compactor | ap-northeast-3 | error | 9173 | clock skew corrected against NTP |
| 788 | 2026-03-05T13:08:44Z | watcher | ap-south-1 | retrying | 9210 | config reloaded from disk |
| 789 | 2026-03-06T13:09:57Z | renderer | eu-west-2 | warning | 9247 | no change since the previous sweep |
| 790 | 2026-03-07T13:10:10Z | scheduler | af-south-1 | skipped | 9284 | backpressure from the upstream shard |
| 791 | 2026-03-08T13:11:23Z | gateway | us-west-2 | ok | 9321 | DNS lookup retried twice |
| 792 | 2026-03-09T13:12:36Z | indexer | eu-north-1 | pending | 9358 | restarted after a failed health check |
| 793 | 2026-03-10T13:13:49Z | cache | sa-east-1 | cancelled | 9395 | leader election completed |
| 794 | 2026-03-11T13:14:02Z | resolver | us-east-1 | error | 9432 | manual intervention requested by the operator |
| 795 | 2026-03-12T13:15:15Z | shipper | ap-northeast-3 | retrying | 9469 | cold start took longer than the budget |
| 796 | 2026-03-13T13:16:28Z | reaper | ap-south-1 | warning | 9506 | certificate rotated |
| 797 | 2026-03-14T13:17:41Z | notifier | eu-west-2 | skipped | 9543 | queue drained without incident |
| 798 | 2026-03-15T13:18:54Z | uploader | af-south-1 | ok | 9580 | disk watermark crossed, trimmed oldest segments |
| 799 | 2026-03-16T13:19:07Z | compactor | us-west-2 | pending | 9617 | clock skew corrected against NTP |
| 800 | 2026-03-17T13:20:20Z | watcher | eu-north-1 | cancelled | 9654 | config reloaded from disk |
| 801 | 2026-03-18T13:21:33Z | renderer | sa-east-1 | error | 9691 | no change since the previous sweep |
| 802 | 2026-03-19T13:22:46Z | scheduler | us-east-1 | retrying | 9728 | backpressure from the upstream shard |
| 803 | 2026-03-20T13:23:59Z | gateway | ap-northeast-3 | warning | 9765 | DNS lookup retried twice |
| 804 | 2026-03-21T13:24:12Z | indexer | ap-south-1 | skipped | 9802 | restarted after a failed health check |
| 805 | 2026-03-22T13:25:25Z | cache | eu-west-2 | ok | 9839 | leader election completed |
| 806 | 2026-03-23T13:26:38Z | resolver | af-south-1 | pending | 9876 | manual intervention requested by the operator |
| 807 | 2026-03-24T13:27:51Z | shipper | us-west-2 | cancelled | 9913 | cold start took longer than the budget |
| 808 | 2026-03-25T13:28:04Z | reaper | eu-north-1 | error | 9950 | certificate rotated |
| 809 | 2026-03-26T13:29:17Z | notifier | sa-east-1 | retrying | 14 | queue drained without incident |
| 810 | 2026-03-27T13:30:30Z | uploader | us-east-1 | warning | 51 | disk watermark crossed, trimmed oldest segments |
| 811 | 2026-03-28T13:31:43Z | compactor | ap-northeast-3 | skipped | 88 | clock skew corrected against NTP |
| 812 | 2026-03-01T13:32:56Z | watcher | ap-south-1 | ok | 125 | config reloaded from disk |
| 813 | 2026-03-02T13:33:09Z | renderer | eu-west-2 | pending | 162 | no change since the previous sweep |
| 814 | 2026-03-03T13:34:22Z | scheduler | af-south-1 | cancelled | 199 | backpressure from the upstream shard |
| 815 | 2026-03-04T13:35:35Z | gateway | us-west-2 | error | 236 | DNS lookup retried twice |
| 816 | 2026-03-05T13:36:48Z | indexer | eu-north-1 | retrying | 273 | restarted after a failed health check |
| 817 | 2026-03-06T13:37:01Z | cache | sa-east-1 | warning | 310 | leader election completed |
| 818 | 2026-03-07T13:38:14Z | resolver | us-east-1 | skipped | 347 | manual intervention requested by the operator |
| 819 | 2026-03-08T13:39:27Z | shipper | ap-northeast-3 | ok | 384 | cold start took longer than the budget |
| 820 | 2026-03-09T13:40:40Z | reaper | ap-south-1 | pending | 421 | certificate rotated |
| 821 | 2026-03-10T13:41:53Z | notifier | eu-west-2 | cancelled | 458 | queue drained without incident |
| 822 | 2026-03-11T13:42:06Z | uploader | af-south-1 | error | 495 | disk watermark crossed, trimmed oldest segments |
| 823 | 2026-03-12T13:43:19Z | compactor | us-west-2 | retrying | 532 | clock skew corrected against NTP |
| 824 | 2026-03-13T13:44:32Z | watcher | eu-north-1 | warning | 569 | config reloaded from disk |
| 825 | 2026-03-14T13:45:45Z | renderer | sa-east-1 | skipped | 606 | no change since the previous sweep |
| 826 | 2026-03-15T13:46:58Z | scheduler | us-east-1 | ok | 643 | backpressure from the upstream shard |
| 827 | 2026-03-16T13:47:11Z | gateway | ap-northeast-3 | pending | 680 | DNS lookup retried twice |
| 828 | 2026-03-17T13:48:24Z | indexer | ap-south-1 | cancelled | 717 | restarted after a failed health check |
| 829 | 2026-03-18T13:49:37Z | cache | eu-west-2 | error | 754 | leader election completed |
| 830 | 2026-03-19T13:50:50Z | resolver | af-south-1 | retrying | 791 | manual intervention requested by the operator |
| 831 | 2026-03-20T13:51:03Z | shipper | us-west-2 | warning | 828 | cold start took longer than the budget |
| 832 | 2026-03-21T13:52:16Z | reaper | eu-north-1 | skipped | 865 | certificate rotated |
| 833 | 2026-03-22T13:53:29Z | notifier | sa-east-1 | ok | 902 | queue drained without incident |
| 834 | 2026-03-23T13:54:42Z | uploader | us-east-1 | pending | 939 | disk watermark crossed, trimmed oldest segments |
| 835 | 2026-03-24T13:55:55Z | compactor | ap-northeast-3 | cancelled | 976 | clock skew corrected against NTP |
| 836 | 2026-03-25T13:56:08Z | watcher | ap-south-1 | error | 1013 | config reloaded from disk |
| 837 | 2026-03-26T13:57:21Z | renderer | eu-west-2 | retrying | 1050 | no change since the previous sweep |
| 838 | 2026-03-27T13:58:34Z | scheduler | af-south-1 | warning | 1087 | backpressure from the upstream shard |
| 839 | 2026-03-28T13:59:47Z | gateway | us-west-2 | skipped | 1124 | DNS lookup retried twice |
| 840 | 2026-03-01T14:00:00Z | indexer | eu-north-1 | ok | 1161 | restarted after a failed health check |
| 841 | 2026-03-02T14:01:13Z | cache | sa-east-1 | pending | 1198 | leader election completed |
| 842 | 2026-03-03T14:02:26Z | resolver | us-east-1 | cancelled | 1235 | manual intervention requested by the operator |
| 843 | 2026-03-04T14:03:39Z | shipper | ap-northeast-3 | error | 1272 | cold start took longer than the budget |
| 844 | 2026-03-05T14:04:52Z | reaper | ap-south-1 | retrying | 1309 | certificate rotated |
| 845 | 2026-03-06T14:05:05Z | notifier | eu-west-2 | warning | 1346 | queue drained without incident |
| 846 | 2026-03-07T14:06:18Z | uploader | af-south-1 | skipped | 1383 | disk watermark crossed, trimmed oldest segments |
| 847 | 2026-03-08T14:07:31Z | compactor | us-west-2 | ok | 1420 | clock skew corrected against NTP |
| 848 | 2026-03-09T14:08:44Z | watcher | eu-north-1 | pending | 1457 | config reloaded from disk |
| 849 | 2026-03-10T14:09:57Z | renderer | sa-east-1 | cancelled | 1494 | no change since the previous sweep |
| 850 | 2026-03-11T14:10:10Z | scheduler | us-east-1 | error | 1531 | backpressure from the upstream shard |
| 851 | 2026-03-12T14:11:23Z | gateway | ap-northeast-3 | retrying | 1568 | DNS lookup retried twice |
| 852 | 2026-03-13T14:12:36Z | indexer | ap-south-1 | warning | 1605 | restarted after a failed health check |
| 853 | 2026-03-14T14:13:49Z | cache | eu-west-2 | skipped | 1642 | leader election completed |
| 854 | 2026-03-15T14:14:02Z | resolver | af-south-1 | ok | 1679 | manual intervention requested by the operator |
| 855 | 2026-03-16T14:15:15Z | shipper | us-west-2 | pending | 1716 | cold start took longer than the budget |
| 856 | 2026-03-17T14:16:28Z | reaper | eu-north-1 | cancelled | 1753 | certificate rotated |
| 857 | 2026-03-18T14:17:41Z | notifier | sa-east-1 | error | 1790 | queue drained without incident |
| 858 | 2026-03-19T14:18:54Z | uploader | us-east-1 | retrying | 1827 | disk watermark crossed, trimmed oldest segments |
| 859 | 2026-03-20T14:19:07Z | compactor | ap-northeast-3 | warning | 1864 | clock skew corrected against NTP |
| 860 | 2026-03-21T14:20:20Z | watcher | ap-south-1 | skipped | 1901 | config reloaded from disk |
| 861 | 2026-03-22T14:21:33Z | renderer | eu-west-2 | ok | 1938 | no change since the previous sweep |
| 862 | 2026-03-23T14:22:46Z | scheduler | af-south-1 | pending | 1975 | backpressure from the upstream shard |
| 863 | 2026-03-24T14:23:59Z | gateway | us-west-2 | cancelled | 2012 | DNS lookup retried twice |
| 864 | 2026-03-25T14:24:12Z | indexer | eu-north-1 | error | 2049 | restarted after a failed health check |
| 865 | 2026-03-26T14:25:25Z | cache | sa-east-1 | retrying | 2086 | leader election completed |
| 866 | 2026-03-27T14:26:38Z | resolver | us-east-1 | warning | 2123 | manual intervention requested by the operator |
| 867 | 2026-03-28T14:27:51Z | shipper | ap-northeast-3 | skipped | 2160 | cold start took longer than the budget |
| 868 | 2026-03-01T14:28:04Z | reaper | ap-south-1 | ok | 2197 | certificate rotated |
| 869 | 2026-03-02T14:29:17Z | notifier | eu-west-2 | pending | 2234 | queue drained without incident |
| 870 | 2026-03-03T14:30:30Z | uploader | af-south-1 | cancelled | 2271 | disk watermark crossed, trimmed oldest segments |
| 871 | 2026-03-04T14:31:43Z | compactor | us-west-2 | error | 2308 | clock skew corrected against NTP |
| 872 | 2026-03-05T14:32:56Z | watcher | eu-north-1 | retrying | 2345 | config reloaded from disk |
| 873 | 2026-03-06T14:33:09Z | renderer | sa-east-1 | warning | 2382 | no change since the previous sweep |
| 874 | 2026-03-07T14:34:22Z | scheduler | us-east-1 | skipped | 2419 | backpressure from the upstream shard |
| 875 | 2026-03-08T14:35:35Z | gateway | ap-northeast-3 | ok | 2456 | DNS lookup retried twice |
| 876 | 2026-03-09T14:36:48Z | indexer | ap-south-1 | pending | 2493 | restarted after a failed health check |
| 877 | 2026-03-10T14:37:01Z | cache | eu-west-2 | cancelled | 2530 | leader election completed |
| 878 | 2026-03-11T14:38:14Z | resolver | af-south-1 | error | 2567 | manual intervention requested by the operator |
| 879 | 2026-03-12T14:39:27Z | shipper | us-west-2 | retrying | 2604 | cold start took longer than the budget |
| 880 | 2026-03-13T14:40:40Z | reaper | eu-north-1 | warning | 2641 | certificate rotated |
| 881 | 2026-03-14T14:41:53Z | notifier | sa-east-1 | skipped | 2678 | queue drained without incident |
| 882 | 2026-03-15T14:42:06Z | uploader | us-east-1 | ok | 2715 | disk watermark crossed, trimmed oldest segments |
| 883 | 2026-03-16T14:43:19Z | compactor | ap-northeast-3 | pending | 2752 | clock skew corrected against NTP |
| 884 | 2026-03-17T14:44:32Z | watcher | ap-south-1 | cancelled | 2789 | config reloaded from disk |
| 885 | 2026-03-18T14:45:45Z | renderer | eu-west-2 | error | 2826 | no change since the previous sweep |
| 886 | 2026-03-19T14:46:58Z | scheduler | af-south-1 | retrying | 2863 | backpressure from the upstream shard |
| 887 | 2026-03-20T14:47:11Z | gateway | us-west-2 | warning | 2900 | DNS lookup retried twice |
| 888 | 2026-03-21T14:48:24Z | indexer | eu-north-1 | skipped | 2937 | restarted after a failed health check |
| 889 | 2026-03-22T14:49:37Z | cache | sa-east-1 | ok | 2974 | leader election completed |
| 890 | 2026-03-23T14:50:50Z | resolver | us-east-1 | pending | 3011 | manual intervention requested by the operator |
| 891 | 2026-03-24T14:51:03Z | shipper | ap-northeast-3 | cancelled | 3048 | cold start took longer than the budget |
| 892 | 2026-03-25T14:52:16Z | reaper | ap-south-1 | error | 3085 | certificate rotated |
| 893 | 2026-03-26T14:53:29Z | notifier | eu-west-2 | retrying | 3122 | queue drained without incident |
| 894 | 2026-03-27T14:54:42Z | uploader | af-south-1 | warning | 3159 | disk watermark crossed, trimmed oldest segments |
| 895 | 2026-03-28T14:55:55Z | compactor | us-west-2 | skipped | 3196 | clock skew corrected against NTP |
| 896 | 2026-03-01T14:56:08Z | watcher | eu-north-1 | ok | 3233 | config reloaded from disk |
| 897 | 2026-03-02T14:57:21Z | renderer | sa-east-1 | pending | 3270 | no change since the previous sweep |
| 898 | 2026-03-03T14:58:34Z | scheduler | us-east-1 | cancelled | 3307 | backpressure from the upstream shard |
| 899 | 2026-03-04T14:59:47Z | gateway | ap-northeast-3 | error | 3344 | DNS lookup retried twice |
| 900 | 2026-03-05T15:00:00Z | indexer | ap-south-1 | retrying | 3381 | restarted after a failed health check |
| 901 | 2026-03-06T15:01:13Z | cache | eu-west-2 | warning | 3418 | leader election completed |
| 902 | 2026-03-07T15:02:26Z | resolver | af-south-1 | skipped | 3455 | manual intervention requested by the operator |
| 903 | 2026-03-08T15:03:39Z | shipper | us-west-2 | ok | 3492 | cold start took longer than the budget |
| 904 | 2026-03-09T15:04:52Z | reaper | eu-north-1 | pending | 3529 | certificate rotated |
| 905 | 2026-03-10T15:05:05Z | notifier | sa-east-1 | cancelled | 3566 | queue drained without incident |
| 906 | 2026-03-11T15:06:18Z | uploader | us-east-1 | error | 3603 | disk watermark crossed, trimmed oldest segments |
| 907 | 2026-03-12T15:07:31Z | compactor | ap-northeast-3 | retrying | 3640 | clock skew corrected against NTP |
| 908 | 2026-03-13T15:08:44Z | watcher | ap-south-1 | warning | 3677 | config reloaded from disk |
| 909 | 2026-03-14T15:09:57Z | renderer | eu-west-2 | skipped | 3714 | no change since the previous sweep |
| 910 | 2026-03-15T15:10:10Z | scheduler | af-south-1 | ok | 3751 | backpressure from the upstream shard |
| 911 | 2026-03-16T15:11:23Z | gateway | us-west-2 | pending | 3788 | DNS lookup retried twice |
| 912 | 2026-03-17T15:12:36Z | indexer | eu-north-1 | cancelled | 3825 | restarted after a failed health check |
| 913 | 2026-03-18T15:13:49Z | cache | sa-east-1 | error | 3862 | leader election completed |
| 914 | 2026-03-19T15:14:02Z | resolver | us-east-1 | retrying | 3899 | manual intervention requested by the operator |
| 915 | 2026-03-20T15:15:15Z | shipper | ap-northeast-3 | warning | 3936 | cold start took longer than the budget |
| 916 | 2026-03-21T15:16:28Z | reaper | ap-south-1 | skipped | 3973 | certificate rotated |
| 917 | 2026-03-22T15:17:41Z | notifier | eu-west-2 | ok | 4010 | queue drained without incident |
| 918 | 2026-03-23T15:18:54Z | uploader | af-south-1 | pending | 4047 | disk watermark crossed, trimmed oldest segments |
| 919 | 2026-03-24T15:19:07Z | compactor | us-west-2 | cancelled | 4084 | clock skew corrected against NTP |
| 920 | 2026-03-25T15:20:20Z | watcher | eu-north-1 | error | 4121 | config reloaded from disk |
| 921 | 2026-03-26T15:21:33Z | renderer | sa-east-1 | retrying | 4158 | no change since the previous sweep |
| 922 | 2026-03-27T15:22:46Z | scheduler | us-east-1 | warning | 4195 | backpressure from the upstream shard |
| 923 | 2026-03-28T15:23:59Z | gateway | ap-northeast-3 | skipped | 4232 | DNS lookup retried twice |
| 924 | 2026-03-01T15:24:12Z | indexer | ap-south-1 | ok | 4269 | restarted after a failed health check |
| 925 | 2026-03-02T15:25:25Z | cache | eu-west-2 | pending | 4306 | leader election completed |
| 926 | 2026-03-03T15:26:38Z | resolver | af-south-1 | cancelled | 4343 | manual intervention requested by the operator |
| 927 | 2026-03-04T15:27:51Z | shipper | us-west-2 | error | 4380 | cold start took longer than the budget |
| 928 | 2026-03-05T15:28:04Z | reaper | eu-north-1 | retrying | 4417 | certificate rotated |
| 929 | 2026-03-06T15:29:17Z | notifier | sa-east-1 | warning | 4454 | queue drained without incident |
| 930 | 2026-03-07T15:30:30Z | uploader | us-east-1 | skipped | 4491 | disk watermark crossed, trimmed oldest segments |
| 931 | 2026-03-08T15:31:43Z | compactor | ap-northeast-3 | ok | 4528 | clock skew corrected against NTP |
| 932 | 2026-03-09T15:32:56Z | watcher | ap-south-1 | pending | 4565 | config reloaded from disk |
| 933 | 2026-03-10T15:33:09Z | renderer | eu-west-2 | cancelled | 4602 | no change since the previous sweep |
| 934 | 2026-03-11T15:34:22Z | scheduler | af-south-1 | error | 4639 | backpressure from the upstream shard |
| 935 | 2026-03-12T15:35:35Z | gateway | us-west-2 | retrying | 4676 | DNS lookup retried twice |
| 936 | 2026-03-13T15:36:48Z | indexer | eu-north-1 | warning | 4713 | restarted after a failed health check |
| 937 | 2026-03-14T15:37:01Z | cache | sa-east-1 | skipped | 4750 | leader election completed |
| 938 | 2026-03-15T15:38:14Z | resolver | us-east-1 | ok | 4787 | manual intervention requested by the operator |
| 939 | 2026-03-16T15:39:27Z | shipper | ap-northeast-3 | pending | 4824 | cold start took longer than the budget |
| 940 | 2026-03-17T15:40:40Z | reaper | ap-south-1 | cancelled | 4861 | certificate rotated |
| 941 | 2026-03-18T15:41:53Z | notifier | eu-west-2 | error | 4898 | queue drained without incident |
| 942 | 2026-03-19T15:42:06Z | uploader | af-south-1 | retrying | 4935 | disk watermark crossed, trimmed oldest segments |
| 943 | 2026-03-20T15:43:19Z | compactor | us-west-2 | warning | 4972 | clock skew corrected against NTP |
| 944 | 2026-03-21T15:44:32Z | watcher | eu-north-1 | skipped | 5009 | config reloaded from disk |
| 945 | 2026-03-22T15:45:45Z | renderer | sa-east-1 | ok | 5046 | no change since the previous sweep |
| 946 | 2026-03-23T15:46:58Z | scheduler | us-east-1 | pending | 5083 | backpressure from the upstream shard |
| 947 | 2026-03-24T15:47:11Z | gateway | ap-northeast-3 | cancelled | 5120 | DNS lookup retried twice |
| 948 | 2026-03-25T15:48:24Z | indexer | ap-south-1 | error | 5157 | restarted after a failed health check |
| 949 | 2026-03-26T15:49:37Z | cache | eu-west-2 | retrying | 5194 | leader election completed |
| 950 | 2026-03-27T15:50:50Z | resolver | af-south-1 | warning | 5231 | manual intervention requested by the operator |
| 951 | 2026-03-28T15:51:03Z | shipper | us-west-2 | skipped | 5268 | cold start took longer than the budget |
| 952 | 2026-03-01T15:52:16Z | reaper | eu-north-1 | ok | 5305 | certificate rotated |
| 953 | 2026-03-02T15:53:29Z | notifier | sa-east-1 | pending | 5342 | queue drained without incident |
| 954 | 2026-03-03T15:54:42Z | uploader | us-east-1 | cancelled | 5379 | disk watermark crossed, trimmed oldest segments |
| 955 | 2026-03-04T15:55:55Z | compactor | ap-northeast-3 | error | 5416 | clock skew corrected against NTP |
| 956 | 2026-03-05T15:56:08Z | watcher | ap-south-1 | retrying | 5453 | config reloaded from disk |
| 957 | 2026-03-06T15:57:21Z | renderer | eu-west-2 | warning | 5490 | no change since the previous sweep |
| 958 | 2026-03-07T15:58:34Z | scheduler | af-south-1 | skipped | 5527 | backpressure from the upstream shard |
| 959 | 2026-03-08T15:59:47Z | gateway | us-west-2 | ok | 5564 | DNS lookup retried twice |
| 960 | 2026-03-09T16:00:00Z | indexer | eu-north-1 | pending | 5601 | restarted after a failed health check |
| 961 | 2026-03-10T16:01:13Z | cache | sa-east-1 | cancelled | 5638 | leader election completed |
| 962 | 2026-03-11T16:02:26Z | resolver | us-east-1 | error | 5675 | manual intervention requested by the operator |
| 963 | 2026-03-12T16:03:39Z | shipper | ap-northeast-3 | retrying | 5712 | cold start took longer than the budget |
| 964 | 2026-03-13T16:04:52Z | reaper | ap-south-1 | warning | 5749 | certificate rotated |
| 965 | 2026-03-14T16:05:05Z | notifier | eu-west-2 | skipped | 5786 | queue drained without incident |
| 966 | 2026-03-15T16:06:18Z | uploader | af-south-1 | ok | 5823 | disk watermark crossed, trimmed oldest segments |
| 967 | 2026-03-16T16:07:31Z | compactor | us-west-2 | pending | 5860 | clock skew corrected against NTP |
| 968 | 2026-03-17T16:08:44Z | watcher | eu-north-1 | cancelled | 5897 | config reloaded from disk |
| 969 | 2026-03-18T16:09:57Z | renderer | sa-east-1 | error | 5934 | no change since the previous sweep |
| 970 | 2026-03-19T16:10:10Z | scheduler | us-east-1 | retrying | 5971 | backpressure from the upstream shard |
| 971 | 2026-03-20T16:11:23Z | gateway | ap-northeast-3 | warning | 6008 | DNS lookup retried twice |
| 972 | 2026-03-21T16:12:36Z | indexer | ap-south-1 | skipped | 6045 | restarted after a failed health check |
| 973 | 2026-03-22T16:13:49Z | cache | eu-west-2 | ok | 6082 | leader election completed |
| 974 | 2026-03-23T16:14:02Z | resolver | af-south-1 | pending | 6119 | manual intervention requested by the operator |
| 975 | 2026-03-24T16:15:15Z | shipper | us-west-2 | cancelled | 6156 | cold start took longer than the budget |
| 976 | 2026-03-25T16:16:28Z | reaper | eu-north-1 | error | 6193 | certificate rotated |
| 977 | 2026-03-26T16:17:41Z | notifier | sa-east-1 | retrying | 6230 | queue drained without incident |
| 978 | 2026-03-27T16:18:54Z | uploader | us-east-1 | warning | 6267 | disk watermark crossed, trimmed oldest segments |
| 979 | 2026-03-28T16:19:07Z | compactor | ap-northeast-3 | skipped | 6304 | clock skew corrected against NTP |
| 980 | 2026-03-01T16:20:20Z | watcher | ap-south-1 | ok | 6341 | config reloaded from disk |
| 981 | 2026-03-02T16:21:33Z | renderer | eu-west-2 | pending | 6378 | no change since the previous sweep |
| 982 | 2026-03-03T16:22:46Z | scheduler | af-south-1 | cancelled | 6415 | backpressure from the upstream shard |
| 983 | 2026-03-04T16:23:59Z | gateway | us-west-2 | error | 6452 | DNS lookup retried twice |
| 984 | 2026-03-05T16:24:12Z | indexer | eu-north-1 | retrying | 6489 | restarted after a failed health check |
| 985 | 2026-03-06T16:25:25Z | cache | sa-east-1 | warning | 6526 | leader election completed |
| 986 | 2026-03-07T16:26:38Z | resolver | us-east-1 | skipped | 6563 | manual intervention requested by the operator |
| 987 | 2026-03-08T16:27:51Z | shipper | ap-northeast-3 | ok | 6600 | cold start took longer than the budget |
| 988 | 2026-03-09T16:28:04Z | reaper | ap-south-1 | pending | 6637 | certificate rotated |
| 989 | 2026-03-10T16:29:17Z | notifier | eu-west-2 | cancelled | 6674 | queue drained without incident |
| 990 | 2026-03-11T16:30:30Z | uploader | af-south-1 | error | 6711 | disk watermark crossed, trimmed oldest segments |
| 991 | 2026-03-12T16:31:43Z | compactor | us-west-2 | retrying | 6748 | clock skew corrected against NTP |
| 992 | 2026-03-13T16:32:56Z | watcher | eu-north-1 | warning | 6785 | config reloaded from disk |
| 993 | 2026-03-14T16:33:09Z | renderer | sa-east-1 | skipped | 6822 | no change since the previous sweep |
| 994 | 2026-03-15T16:34:22Z | scheduler | us-east-1 | ok | 6859 | backpressure from the upstream shard |
| 995 | 2026-03-16T16:35:35Z | gateway | ap-northeast-3 | pending | 6896 | DNS lookup retried twice |
| 996 | 2026-03-17T16:36:48Z | indexer | ap-south-1 | cancelled | 6933 | restarted after a failed health check |
| 997 | 2026-03-18T16:37:01Z | cache | eu-west-2 | error | 6970 | leader election completed |
| 998 | 2026-03-19T16:38:14Z | resolver | af-south-1 | retrying | 7007 | manual intervention requested by the operator |
| 999 | 2026-03-20T16:39:27Z | shipper | us-west-2 | warning | 7044 | cold start took longer than the budget |
| 1000 | 2026-03-21T16:40:40Z | reaper | eu-north-1 | skipped | 7081 | certificate rotated |
| 1001 | 2026-03-22T16:41:53Z | notifier | sa-east-1 | ok | 7118 | queue drained without incident |
| 1002 | 2026-03-23T16:42:06Z | uploader | us-east-1 | pending | 7155 | disk watermark crossed, trimmed oldest segments |
| 1003 | 2026-03-24T16:43:19Z | compactor | ap-northeast-3 | cancelled | 7192 | clock skew corrected against NTP |
| 1004 | 2026-03-25T16:44:32Z | watcher | ap-south-1 | error | 7229 | config reloaded from disk |
| 1005 | 2026-03-26T16:45:45Z | renderer | eu-west-2 | retrying | 7266 | no change since the previous sweep |
| 1006 | 2026-03-27T16:46:58Z | scheduler | af-south-1 | warning | 7303 | backpressure from the upstream shard |
| 1007 | 2026-03-28T16:47:11Z | gateway | us-west-2 | skipped | 7340 | DNS lookup retried twice |
| 1008 | 2026-03-01T16:48:24Z | indexer | eu-north-1 | ok | 7377 | restarted after a failed health check |
| 1009 | 2026-03-02T16:49:37Z | cache | sa-east-1 | pending | 7414 | leader election completed |
| 1010 | 2026-03-03T16:50:50Z | resolver | us-east-1 | cancelled | 7451 | manual intervention requested by the operator |
| 1011 | 2026-03-04T16:51:03Z | shipper | ap-northeast-3 | error | 7488 | cold start took longer than the budget |
| 1012 | 2026-03-05T16:52:16Z | reaper | ap-south-1 | retrying | 7525 | certificate rotated |
| 1013 | 2026-03-06T16:53:29Z | notifier | eu-west-2 | warning | 7562 | queue drained without incident |
| 1014 | 2026-03-07T16:54:42Z | uploader | af-south-1 | skipped | 7599 | disk watermark crossed, trimmed oldest segments |
| 1015 | 2026-03-08T16:55:55Z | compactor | us-west-2 | ok | 7636 | clock skew corrected against NTP |
| 1016 | 2026-03-09T16:56:08Z | watcher | eu-north-1 | pending | 7673 | config reloaded from disk |
| 1017 | 2026-03-10T16:57:21Z | renderer | sa-east-1 | cancelled | 7710 | no change since the previous sweep |
| 1018 | 2026-03-11T16:58:34Z | scheduler | us-east-1 | error | 7747 | backpressure from the upstream shard |
| 1019 | 2026-03-12T16:59:47Z | gateway | ap-northeast-3 | retrying | 7784 | DNS lookup retried twice |
| 1020 | 2026-03-13T17:00:00Z | indexer | ap-south-1 | warning | 7821 | restarted after a failed health check |
| 1021 | 2026-03-14T17:01:13Z | cache | eu-west-2 | skipped | 7858 | leader election completed |
| 1022 | 2026-03-15T17:02:26Z | resolver | af-south-1 | ok | 7895 | manual intervention requested by the operator |
| 1023 | 2026-03-16T17:03:39Z | shipper | us-west-2 | pending | 7932 | cold start took longer than the budget |
| 1024 | 2026-03-17T17:04:52Z | reaper | eu-north-1 | cancelled | 7969 | certificate rotated |
| 1025 | 2026-03-18T17:05:05Z | notifier | sa-east-1 | error | 8006 | queue drained without incident |
| 1026 | 2026-03-19T17:06:18Z | uploader | us-east-1 | retrying | 8043 | disk watermark crossed, trimmed oldest segments |
| 1027 | 2026-03-20T17:07:31Z | compactor | ap-northeast-3 | warning | 8080 | clock skew corrected against NTP |
| 1028 | 2026-03-21T17:08:44Z | watcher | ap-south-1 | skipped | 8117 | config reloaded from disk |
| 1029 | 2026-03-22T17:09:57Z | renderer | eu-west-2 | ok | 8154 | no change since the previous sweep |
| 1030 | 2026-03-23T17:10:10Z | scheduler | af-south-1 | pending | 8191 | backpressure from the upstream shard |
| 1031 | 2026-03-24T17:11:23Z | gateway | us-west-2 | cancelled | 8228 | DNS lookup retried twice |
| 1032 | 2026-03-25T17:12:36Z | indexer | eu-north-1 | error | 8265 | restarted after a failed health check |
| 1033 | 2026-03-26T17:13:49Z | cache | sa-east-1 | retrying | 8302 | leader election completed |
| 1034 | 2026-03-27T17:14:02Z | resolver | us-east-1 | warning | 8339 | manual intervention requested by the operator |
| 1035 | 2026-03-28T17:15:15Z | shipper | ap-northeast-3 | skipped | 8376 | cold start took longer than the budget |
| 1036 | 2026-03-01T17:16:28Z | reaper | ap-south-1 | ok | 8413 | certificate rotated |
| 1037 | 2026-03-02T17:17:41Z | notifier | eu-west-2 | pending | 8450 | queue drained without incident |
| 1038 | 2026-03-03T17:18:54Z | uploader | af-south-1 | cancelled | 8487 | disk watermark crossed, trimmed oldest segments |
| 1039 | 2026-03-04T17:19:07Z | compactor | us-west-2 | error | 8524 | clock skew corrected against NTP |
| 1040 | 2026-03-05T17:20:20Z | watcher | eu-north-1 | retrying | 8561 | config reloaded from disk |
| 1041 | 2026-03-06T17:21:33Z | renderer | sa-east-1 | warning | 8598 | no change since the previous sweep |
| 1042 | 2026-03-07T17:22:46Z | scheduler | us-east-1 | skipped | 8635 | backpressure from the upstream shard |
| 1043 | 2026-03-08T17:23:59Z | gateway | ap-northeast-3 | ok | 8672 | DNS lookup retried twice |
| 1044 | 2026-03-09T17:24:12Z | indexer | ap-south-1 | pending | 8709 | restarted after a failed health check |
| 1045 | 2026-03-10T17:25:25Z | cache | eu-west-2 | cancelled | 8746 | leader election completed |
| 1046 | 2026-03-11T17:26:38Z | resolver | af-south-1 | error | 8783 | manual intervention requested by the operator |
| 1047 | 2026-03-12T17:27:51Z | shipper | us-west-2 | retrying | 8820 | cold start took longer than the budget |
| 1048 | 2026-03-13T17:28:04Z | reaper | eu-north-1 | warning | 8857 | certificate rotated |
| 1049 | 2026-03-14T17:29:17Z | notifier | sa-east-1 | skipped | 8894 | queue drained without incident |
| 1050 | 2026-03-15T17:30:30Z | uploader | us-east-1 | ok | 8931 | disk watermark crossed, trimmed oldest segments |
| 1051 | 2026-03-16T17:31:43Z | compactor | ap-northeast-3 | pending | 8968 | clock skew corrected against NTP |
| 1052 | 2026-03-17T17:32:56Z | watcher | ap-south-1 | cancelled | 9005 | config reloaded from disk |
| 1053 | 2026-03-18T17:33:09Z | renderer | eu-west-2 | error | 9042 | no change since the previous sweep |
| 1054 | 2026-03-19T17:34:22Z | scheduler | af-south-1 | retrying | 9079 | backpressure from the upstream shard |
| 1055 | 2026-03-20T17:35:35Z | gateway | us-west-2 | warning | 9116 | DNS lookup retried twice |
| 1056 | 2026-03-21T17:36:48Z | indexer | eu-north-1 | skipped | 9153 | restarted after a failed health check |
| 1057 | 2026-03-22T17:37:01Z | cache | sa-east-1 | ok | 9190 | leader election completed |
| 1058 | 2026-03-23T17:38:14Z | resolver | us-east-1 | pending | 9227 | manual intervention requested by the operator |
| 1059 | 2026-03-24T17:39:27Z | shipper | ap-northeast-3 | cancelled | 9264 | cold start took longer than the budget |
| 1060 | 2026-03-25T17:40:40Z | reaper | ap-south-1 | error | 9301 | certificate rotated |
| 1061 | 2026-03-26T17:41:53Z | notifier | eu-west-2 | retrying | 9338 | queue drained without incident |
| 1062 | 2026-03-27T17:42:06Z | uploader | af-south-1 | warning | 9375 | disk watermark crossed, trimmed oldest segments |
| 1063 | 2026-03-28T17:43:19Z | compactor | us-west-2 | skipped | 9412 | clock skew corrected against NTP |
| 1064 | 2026-03-01T17:44:32Z | watcher | eu-north-1 | ok | 9449 | config reloaded from disk |
| 1065 | 2026-03-02T17:45:45Z | renderer | sa-east-1 | pending | 9486 | no change since the previous sweep |
| 1066 | 2026-03-03T17:46:58Z | scheduler | us-east-1 | cancelled | 9523 | backpressure from the upstream shard |
| 1067 | 2026-03-04T17:47:11Z | gateway | ap-northeast-3 | error | 9560 | DNS lookup retried twice |
| 1068 | 2026-03-05T17:48:24Z | indexer | ap-south-1 | retrying | 9597 | restarted after a failed health check |
| 1069 | 2026-03-06T17:49:37Z | cache | eu-west-2 | warning | 9634 | leader election completed |
| 1070 | 2026-03-07T17:50:50Z | resolver | af-south-1 | skipped | 9671 | manual intervention requested by the operator |
| 1071 | 2026-03-08T17:51:03Z | shipper | us-west-2 | ok | 9708 | cold start took longer than the budget |
| 1072 | 2026-03-09T17:52:16Z | reaper | eu-north-1 | pending | 9745 | certificate rotated |
| 1073 | 2026-03-10T17:53:29Z | notifier | sa-east-1 | cancelled | 9782 | queue drained without incident |
| 1074 | 2026-03-11T17:54:42Z | uploader | us-east-1 | error | 9819 | disk watermark crossed, trimmed oldest segments |
| 1075 | 2026-03-12T17:55:55Z | compactor | ap-northeast-3 | retrying | 9856 | clock skew corrected against NTP |
| 1076 | 2026-03-13T17:56:08Z | watcher | ap-south-1 | warning | 9893 | config reloaded from disk |
| 1077 | 2026-03-14T17:57:21Z | renderer | eu-west-2 | skipped | 9930 | no change since the previous sweep |
| 1078 | 2026-03-15T17:58:34Z | scheduler | af-south-1 | ok | 9967 | backpressure from the upstream shard |
| 1079 | 2026-03-16T17:59:47Z | gateway | us-west-2 | pending | 31 | DNS lookup retried twice |
| 1080 | 2026-03-17T18:00:00Z | indexer | eu-north-1 | cancelled | 68 | restarted after a failed health check |
| 1081 | 2026-03-18T18:01:13Z | cache | sa-east-1 | error | 105 | leader election completed |
| 1082 | 2026-03-19T18:02:26Z | resolver | us-east-1 | retrying | 142 | manual intervention requested by the operator |
| 1083 | 2026-03-20T18:03:39Z | shipper | ap-northeast-3 | warning | 179 | cold start took longer than the budget |
| 1084 | 2026-03-21T18:04:52Z | reaper | ap-south-1 | skipped | 216 | certificate rotated |
| 1085 | 2026-03-22T18:05:05Z | notifier | eu-west-2 | ok | 253 | queue drained without incident |
| 1086 | 2026-03-23T18:06:18Z | uploader | af-south-1 | pending | 290 | disk watermark crossed, trimmed oldest segments |
| 1087 | 2026-03-24T18:07:31Z | compactor | us-west-2 | cancelled | 327 | clock skew corrected against NTP |
| 1088 | 2026-03-25T18:08:44Z | watcher | eu-north-1 | error | 364 | config reloaded from disk |
| 1089 | 2026-03-26T18:09:57Z | renderer | sa-east-1 | retrying | 401 | no change since the previous sweep |
| 1090 | 2026-03-27T18:10:10Z | scheduler | us-east-1 | warning | 438 | backpressure from the upstream shard |
| 1091 | 2026-03-28T18:11:23Z | gateway | ap-northeast-3 | skipped | 475 | DNS lookup retried twice |
| 1092 | 2026-03-01T18:12:36Z | indexer | ap-south-1 | ok | 512 | restarted after a failed health check |
| 1093 | 2026-03-02T18:13:49Z | cache | eu-west-2 | pending | 549 | leader election completed |
| 1094 | 2026-03-03T18:14:02Z | resolver | af-south-1 | cancelled | 586 | manual intervention requested by the operator |
| 1095 | 2026-03-04T18:15:15Z | shipper | us-west-2 | error | 623 | cold start took longer than the budget |
| 1096 | 2026-03-05T18:16:28Z | reaper | eu-north-1 | retrying | 660 | certificate rotated |
| 1097 | 2026-03-06T18:17:41Z | notifier | sa-east-1 | warning | 697 | queue drained without incident |
| 1098 | 2026-03-07T18:18:54Z | uploader | us-east-1 | skipped | 734 | disk watermark crossed, trimmed oldest segments |
| 1099 | 2026-03-08T18:19:07Z | compactor | ap-northeast-3 | ok | 771 | clock skew corrected against NTP |
| 1100 | 2026-03-09T18:20:20Z | watcher | ap-south-1 | pending | 808 | config reloaded from disk |
| 1101 | 2026-03-10T18:21:33Z | renderer | eu-west-2 | cancelled | 845 | no change since the previous sweep |
| 1102 | 2026-03-11T18:22:46Z | scheduler | af-south-1 | error | 882 | backpressure from the upstream shard |
| 1103 | 2026-03-12T18:23:59Z | gateway | us-west-2 | retrying | 919 | DNS lookup retried twice |
| 1104 | 2026-03-13T18:24:12Z | indexer | eu-north-1 | warning | 956 | restarted after a failed health check |
| 1105 | 2026-03-14T18:25:25Z | cache | sa-east-1 | skipped | 993 | leader election completed |
| 1106 | 2026-03-15T18:26:38Z | resolver | us-east-1 | ok | 1030 | manual intervention requested by the operator |
| 1107 | 2026-03-16T18:27:51Z | shipper | ap-northeast-3 | pending | 1067 | cold start took longer than the budget |
| 1108 | 2026-03-17T18:28:04Z | reaper | ap-south-1 | cancelled | 1104 | certificate rotated |
| 1109 | 2026-03-18T18:29:17Z | notifier | eu-west-2 | error | 1141 | queue drained without incident |
| 1110 | 2026-03-19T18:30:30Z | uploader | af-south-1 | retrying | 1178 | disk watermark crossed, trimmed oldest segments |
| 1111 | 2026-03-20T18:31:43Z | compactor | us-west-2 | warning | 1215 | clock skew corrected against NTP |
| 1112 | 2026-03-21T18:32:56Z | watcher | eu-north-1 | skipped | 1252 | config reloaded from disk |
| 1113 | 2026-03-22T18:33:09Z | renderer | sa-east-1 | ok | 1289 | no change since the previous sweep |
| 1114 | 2026-03-23T18:34:22Z | scheduler | us-east-1 | pending | 1326 | backpressure from the upstream shard |
| 1115 | 2026-03-24T18:35:35Z | gateway | ap-northeast-3 | cancelled | 1363 | DNS lookup retried twice |
| 1116 | 2026-03-25T18:36:48Z | indexer | ap-south-1 | error | 1400 | restarted after a failed health check |
| 1117 | 2026-03-26T18:37:01Z | cache | eu-west-2 | retrying | 1437 | leader election completed |
| 1118 | 2026-03-27T18:38:14Z | resolver | af-south-1 | warning | 1474 | manual intervention requested by the operator |
| 1119 | 2026-03-28T18:39:27Z | shipper | us-west-2 | skipped | 1511 | cold start took longer than the budget |
| 1120 | 2026-03-01T18:40:40Z | reaper | eu-north-1 | ok | 1548 | certificate rotated |
| 1121 | 2026-03-02T18:41:53Z | notifier | sa-east-1 | pending | 1585 | queue drained without incident |
| 1122 | 2026-03-03T18:42:06Z | uploader | us-east-1 | cancelled | 1622 | disk watermark crossed, trimmed oldest segments |
| 1123 | 2026-03-04T18:43:19Z | compactor | ap-northeast-3 | error | 1659 | clock skew corrected against NTP |
| 1124 | 2026-03-05T18:44:32Z | watcher | ap-south-1 | retrying | 1696 | config reloaded from disk |
| 1125 | 2026-03-06T18:45:45Z | renderer | eu-west-2 | warning | 1733 | no change since the previous sweep |
| 1126 | 2026-03-07T18:46:58Z | scheduler | af-south-1 | skipped | 1770 | backpressure from the upstream shard |
| 1127 | 2026-03-08T18:47:11Z | gateway | us-west-2 | ok | 1807 | DNS lookup retried twice |
| 1128 | 2026-03-09T18:48:24Z | indexer | eu-north-1 | pending | 1844 | restarted after a failed health check |
| 1129 | 2026-03-10T18:49:37Z | cache | sa-east-1 | cancelled | 1881 | leader election completed |
| 1130 | 2026-03-11T18:50:50Z | resolver | us-east-1 | error | 1918 | manual intervention requested by the operator |
| 1131 | 2026-03-12T18:51:03Z | shipper | ap-northeast-3 | retrying | 1955 | cold start took longer than the budget |
| 1132 | 2026-03-13T18:52:16Z | reaper | ap-south-1 | warning | 1992 | certificate rotated |
| 1133 | 2026-03-14T18:53:29Z | notifier | eu-west-2 | skipped | 2029 | queue drained without incident |
| 1134 | 2026-03-15T18:54:42Z | uploader | af-south-1 | ok | 2066 | disk watermark crossed, trimmed oldest segments |
| 1135 | 2026-03-16T18:55:55Z | compactor | us-west-2 | pending | 2103 | clock skew corrected against NTP |
| 1136 | 2026-03-17T18:56:08Z | watcher | eu-north-1 | cancelled | 2140 | config reloaded from disk |
| 1137 | 2026-03-18T18:57:21Z | renderer | sa-east-1 | error | 2177 | no change since the previous sweep |
| 1138 | 2026-03-19T18:58:34Z | scheduler | us-east-1 | retrying | 2214 | backpressure from the upstream shard |
| 1139 | 2026-03-20T18:59:47Z | gateway | ap-northeast-3 | warning | 2251 | DNS lookup retried twice |
| 1140 | 2026-03-21T19:00:00Z | indexer | ap-south-1 | skipped | 2288 | restarted after a failed health check |
| 1141 | 2026-03-22T19:01:13Z | cache | eu-west-2 | ok | 2325 | leader election completed |
| 1142 | 2026-03-23T19:02:26Z | resolver | af-south-1 | pending | 2362 | manual intervention requested by the operator |
| 1143 | 2026-03-24T19:03:39Z | shipper | us-west-2 | cancelled | 2399 | cold start took longer than the budget |
| 1144 | 2026-03-25T19:04:52Z | reaper | eu-north-1 | error | 2436 | certificate rotated |
| 1145 | 2026-03-26T19:05:05Z | notifier | sa-east-1 | retrying | 2473 | queue drained without incident |
| 1146 | 2026-03-27T19:06:18Z | uploader | us-east-1 | warning | 2510 | disk watermark crossed, trimmed oldest segments |
| 1147 | 2026-03-28T19:07:31Z | compactor | ap-northeast-3 | skipped | 2547 | clock skew corrected against NTP |
| 1148 | 2026-03-01T19:08:44Z | watcher | ap-south-1 | ok | 2584 | config reloaded from disk |
| 1149 | 2026-03-02T19:09:57Z | renderer | eu-west-2 | pending | 2621 | no change since the previous sweep |
| 1150 | 2026-03-03T19:10:10Z | scheduler | af-south-1 | cancelled | 2658 | backpressure from the upstream shard |
| 1151 | 2026-03-04T19:11:23Z | gateway | us-west-2 | error | 2695 | DNS lookup retried twice |
| 1152 | 2026-03-05T19:12:36Z | indexer | eu-north-1 | retrying | 2732 | restarted after a failed health check |
| 1153 | 2026-03-06T19:13:49Z | cache | sa-east-1 | warning | 2769 | leader election completed |
| 1154 | 2026-03-07T19:14:02Z | resolver | us-east-1 | skipped | 2806 | manual intervention requested by the operator |
| 1155 | 2026-03-08T19:15:15Z | shipper | ap-northeast-3 | ok | 2843 | cold start took longer than the budget |
| 1156 | 2026-03-09T19:16:28Z | reaper | ap-south-1 | pending | 2880 | certificate rotated |
| 1157 | 2026-03-10T19:17:41Z | notifier | eu-west-2 | cancelled | 2917 | queue drained without incident |
| 1158 | 2026-03-11T19:18:54Z | uploader | af-south-1 | error | 2954 | disk watermark crossed, trimmed oldest segments |
| 1159 | 2026-03-12T19:19:07Z | compactor | us-west-2 | retrying | 2991 | clock skew corrected against NTP |
| 1160 | 2026-03-13T19:20:20Z | watcher | eu-north-1 | warning | 3028 | config reloaded from disk |
| 1161 | 2026-03-14T19:21:33Z | renderer | sa-east-1 | skipped | 3065 | no change since the previous sweep |
| 1162 | 2026-03-15T19:22:46Z | scheduler | us-east-1 | ok | 3102 | backpressure from the upstream shard |
| 1163 | 2026-03-16T19:23:59Z | gateway | ap-northeast-3 | pending | 3139 | DNS lookup retried twice |
| 1164 | 2026-03-17T19:24:12Z | indexer | ap-south-1 | cancelled | 3176 | restarted after a failed health check |
| 1165 | 2026-03-18T19:25:25Z | cache | eu-west-2 | error | 3213 | leader election completed |
| 1166 | 2026-03-19T19:26:38Z | resolver | af-south-1 | retrying | 3250 | manual intervention requested by the operator |
| 1167 | 2026-03-20T19:27:51Z | shipper | us-west-2 | warning | 3287 | cold start took longer than the budget |
| 1168 | 2026-03-21T19:28:04Z | reaper | eu-north-1 | skipped | 3324 | certificate rotated |
| 1169 | 2026-03-22T19:29:17Z | notifier | sa-east-1 | ok | 3361 | queue drained without incident |
| 1170 | 2026-03-23T19:30:30Z | uploader | us-east-1 | pending | 3398 | disk watermark crossed, trimmed oldest segments |
| 1171 | 2026-03-24T19:31:43Z | compactor | ap-northeast-3 | cancelled | 3435 | clock skew corrected against NTP |
| 1172 | 2026-03-25T19:32:56Z | watcher | ap-south-1 | error | 3472 | config reloaded from disk |
| 1173 | 2026-03-26T19:33:09Z | renderer | eu-west-2 | retrying | 3509 | no change since the previous sweep |
| 1174 | 2026-03-27T19:34:22Z | scheduler | af-south-1 | warning | 3546 | backpressure from the upstream shard |
| 1175 | 2026-03-28T19:35:35Z | gateway | us-west-2 | skipped | 3583 | DNS lookup retried twice |
| 1176 | 2026-03-01T19:36:48Z | indexer | eu-north-1 | ok | 3620 | restarted after a failed health check |
| 1177 | 2026-03-02T19:37:01Z | cache | sa-east-1 | pending | 3657 | leader election completed |
| 1178 | 2026-03-03T19:38:14Z | resolver | us-east-1 | cancelled | 3694 | manual intervention requested by the operator |
| 1179 | 2026-03-04T19:39:27Z | shipper | ap-northeast-3 | error | 3731 | cold start took longer than the budget |
| 1180 | 2026-03-05T19:40:40Z | reaper | ap-south-1 | retrying | 3768 | certificate rotated |
| 1181 | 2026-03-06T19:41:53Z | notifier | eu-west-2 | warning | 3805 | queue drained without incident |
| 1182 | 2026-03-07T19:42:06Z | uploader | af-south-1 | skipped | 3842 | disk watermark crossed, trimmed oldest segments |
| 1183 | 2026-03-08T19:43:19Z | compactor | us-west-2 | ok | 3879 | clock skew corrected against NTP |
| 1184 | 2026-03-09T19:44:32Z | watcher | eu-north-1 | pending | 3916 | config reloaded from disk |
| 1185 | 2026-03-10T19:45:45Z | renderer | sa-east-1 | cancelled | 3953 | no change since the previous sweep |
| 1186 | 2026-03-11T19:46:58Z | scheduler | us-east-1 | error | 3990 | backpressure from the upstream shard |
| 1187 | 2026-03-12T19:47:11Z | gateway | ap-northeast-3 | retrying | 4027 | DNS lookup retried twice |
| 1188 | 2026-03-13T19:48:24Z | indexer | ap-south-1 | warning | 4064 | restarted after a failed health check |
| 1189 | 2026-03-14T19:49:37Z | cache | eu-west-2 | skipped | 4101 | leader election completed |
| 1190 | 2026-03-15T19:50:50Z | resolver | af-south-1 | ok | 4138 | manual intervention requested by the operator |
| 1191 | 2026-03-16T19:51:03Z | shipper | us-west-2 | pending | 4175 | cold start took longer than the budget |
| 1192 | 2026-03-17T19:52:16Z | reaper | eu-north-1 | cancelled | 4212 | certificate rotated |
| 1193 | 2026-03-18T19:53:29Z | notifier | sa-east-1 | error | 4249 | queue drained without incident |
| 1194 | 2026-03-19T19:54:42Z | uploader | us-east-1 | retrying | 4286 | disk watermark crossed, trimmed oldest segments |
| 1195 | 2026-03-20T19:55:55Z | compactor | ap-northeast-3 | warning | 4323 | clock skew corrected against NTP |
| 1196 | 2026-03-21T19:56:08Z | watcher | ap-south-1 | skipped | 4360 | config reloaded from disk |
| 1197 | 2026-03-22T19:57:21Z | renderer | eu-west-2 | ok | 4397 | no change since the previous sweep |
| 1198 | 2026-03-23T19:58:34Z | scheduler | af-south-1 | pending | 4434 | backpressure from the upstream shard |
| 1199 | 2026-03-24T19:59:47Z | gateway | us-west-2 | cancelled | 4471 | DNS lookup retried twice |
| 1200 | 2026-03-25T20:00:00Z | indexer | eu-north-1 | error | 4508 | restarted after a failed health check |
| 1201 | 2026-03-26T20:01:13Z | cache | sa-east-1 | retrying | 4545 | leader election completed |
| 1202 | 2026-03-27T20:02:26Z | resolver | us-east-1 | warning | 4582 | manual intervention requested by the operator |
| 1203 | 2026-03-28T20:03:39Z | shipper | ap-northeast-3 | skipped | 4619 | cold start took longer than the budget |
| 1204 | 2026-03-01T20:04:52Z | reaper | ap-south-1 | ok | 4656 | certificate rotated |
| 1205 | 2026-03-02T20:05:05Z | notifier | eu-west-2 | pending | 4693 | queue drained without incident |
| 1206 | 2026-03-03T20:06:18Z | uploader | af-south-1 | cancelled | 4730 | disk watermark crossed, trimmed oldest segments |
| 1207 | 2026-03-04T20:07:31Z | compactor | us-west-2 | error | 4767 | clock skew corrected against NTP |
| 1208 | 2026-03-05T20:08:44Z | watcher | eu-north-1 | retrying | 4804 | config reloaded from disk |
| 1209 | 2026-03-06T20:09:57Z | renderer | sa-east-1 | warning | 4841 | no change since the previous sweep |
| 1210 | 2026-03-07T20:10:10Z | scheduler | us-east-1 | skipped | 4878 | backpressure from the upstream shard |
| 1211 | 2026-03-08T20:11:23Z | gateway | ap-northeast-3 | ok | 4915 | DNS lookup retried twice |
| 1212 | 2026-03-09T20:12:36Z | indexer | ap-south-1 | pending | 4952 | restarted after a failed health check |
| 1213 | 2026-03-10T20:13:49Z | cache | eu-west-2 | cancelled | 4989 | leader election completed |
| 1214 | 2026-03-11T20:14:02Z | resolver | af-south-1 | error | 5026 | manual intervention requested by the operator |
| 1215 | 2026-03-12T20:15:15Z | shipper | us-west-2 | retrying | 5063 | cold start took longer than the budget |
| 1216 | 2026-03-13T20:16:28Z | reaper | eu-north-1 | warning | 5100 | certificate rotated |
| 1217 | 2026-03-14T20:17:41Z | notifier | sa-east-1 | skipped | 5137 | queue drained without incident |
| 1218 | 2026-03-15T20:18:54Z | uploader | us-east-1 | ok | 5174 | disk watermark crossed, trimmed oldest segments |
| 1219 | 2026-03-16T20:19:07Z | compactor | ap-northeast-3 | pending | 5211 | clock skew corrected against NTP |
| 1220 | 2026-03-17T20:20:20Z | watcher | ap-south-1 | cancelled | 5248 | config reloaded from disk |
| 1221 | 2026-03-18T20:21:33Z | renderer | eu-west-2 | error | 5285 | no change since the previous sweep |
| 1222 | 2026-03-19T20:22:46Z | scheduler | af-south-1 | retrying | 5322 | backpressure from the upstream shard |
| 1223 | 2026-03-20T20:23:59Z | gateway | us-west-2 | warning | 5359 | DNS lookup retried twice |
| 1224 | 2026-03-21T20:24:12Z | indexer | eu-north-1 | skipped | 5396 | restarted after a failed health check |
| 1225 | 2026-03-22T20:25:25Z | cache | sa-east-1 | ok | 5433 | leader election completed |
| 1226 | 2026-03-23T20:26:38Z | resolver | us-east-1 | pending | 5470 | manual intervention requested by the operator |
| 1227 | 2026-03-24T20:27:51Z | shipper | ap-northeast-3 | cancelled | 5507 | cold start took longer than the budget |
| 1228 | 2026-03-25T20:28:04Z | reaper | ap-south-1 | error | 5544 | certificate rotated |
| 1229 | 2026-03-26T20:29:17Z | notifier | eu-west-2 | retrying | 5581 | queue drained without incident |
| 1230 | 2026-03-27T20:30:30Z | uploader | af-south-1 | warning | 5618 | disk watermark crossed, trimmed oldest segments |
| 1231 | 2026-03-28T20:31:43Z | compactor | us-west-2 | skipped | 5655 | clock skew corrected against NTP |
| 1232 | 2026-03-01T20:32:56Z | watcher | eu-north-1 | ok | 5692 | config reloaded from disk |
| 1233 | 2026-03-02T20:33:09Z | renderer | sa-east-1 | pending | 5729 | no change since the previous sweep |
| 1234 | 2026-03-03T20:34:22Z | scheduler | us-east-1 | cancelled | 5766 | backpressure from the upstream shard |
| 1235 | 2026-03-04T20:35:35Z | gateway | ap-northeast-3 | error | 5803 | DNS lookup retried twice |
| 1236 | 2026-03-05T20:36:48Z | indexer | ap-south-1 | retrying | 5840 | restarted after a failed health check |
| 1237 | 2026-03-06T20:37:01Z | cache | eu-west-2 | warning | 5877 | leader election completed |
| 1238 | 2026-03-07T20:38:14Z | resolver | af-south-1 | skipped | 5914 | manual intervention requested by the operator |
| 1239 | 2026-03-08T20:39:27Z | shipper | us-west-2 | ok | 5951 | cold start took longer than the budget |
| 1240 | 2026-03-09T20:40:40Z | reaper | eu-north-1 | pending | 5988 | certificate rotated |
| 1241 | 2026-03-10T20:41:53Z | notifier | sa-east-1 | cancelled | 6025 | queue drained without incident |
| 1242 | 2026-03-11T20:42:06Z | uploader | us-east-1 | error | 6062 | disk watermark crossed, trimmed oldest segments |
| 1243 | 2026-03-12T20:43:19Z | compactor | ap-northeast-3 | retrying | 6099 | clock skew corrected against NTP |
| 1244 | 2026-03-13T20:44:32Z | watcher | ap-south-1 | warning | 6136 | config reloaded from disk |
| 1245 | 2026-03-14T20:45:45Z | renderer | eu-west-2 | skipped | 6173 | no change since the previous sweep |
| 1246 | 2026-03-15T20:46:58Z | scheduler | af-south-1 | ok | 6210 | backpressure from the upstream shard |
| 1247 | 2026-03-16T20:47:11Z | gateway | us-west-2 | pending | 6247 | DNS lookup retried twice |
| 1248 | 2026-03-17T20:48:24Z | indexer | eu-north-1 | cancelled | 6284 | restarted after a failed health check |
| 1249 | 2026-03-18T20:49:37Z | cache | sa-east-1 | error | 6321 | leader election completed |
| 1250 | 2026-03-19T20:50:50Z | resolver | us-east-1 | retrying | 6358 | manual intervention requested by the operator |
| 1251 | 2026-03-20T20:51:03Z | shipper | ap-northeast-3 | warning | 6395 | cold start took longer than the budget |
| 1252 | 2026-03-21T20:52:16Z | reaper | ap-south-1 | skipped | 6432 | certificate rotated |
| 1253 | 2026-03-22T20:53:29Z | notifier | eu-west-2 | ok | 6469 | queue drained without incident |
| 1254 | 2026-03-23T20:54:42Z | uploader | af-south-1 | pending | 6506 | disk watermark crossed, trimmed oldest segments |
| 1255 | 2026-03-24T20:55:55Z | compactor | us-west-2 | cancelled | 6543 | clock skew corrected against NTP |
| 1256 | 2026-03-25T20:56:08Z | watcher | eu-north-1 | error | 6580 | config reloaded from disk |
| 1257 | 2026-03-26T20:57:21Z | renderer | sa-east-1 | retrying | 6617 | no change since the previous sweep |
| 1258 | 2026-03-27T20:58:34Z | scheduler | us-east-1 | warning | 6654 | backpressure from the upstream shard |
| 1259 | 2026-03-28T20:59:47Z | gateway | ap-northeast-3 | skipped | 6691 | DNS lookup retried twice |
| 1260 | 2026-03-01T21:00:00Z | indexer | ap-south-1 | ok | 6728 | restarted after a failed health check |
| 1261 | 2026-03-02T21:01:13Z | cache | eu-west-2 | pending | 6765 | leader election completed |
| 1262 | 2026-03-03T21:02:26Z | resolver | af-south-1 | cancelled | 6802 | manual intervention requested by the operator |
| 1263 | 2026-03-04T21:03:39Z | shipper | us-west-2 | error | 6839 | cold start took longer than the budget |
| 1264 | 2026-03-05T21:04:52Z | reaper | eu-north-1 | retrying | 6876 | certificate rotated |
| 1265 | 2026-03-06T21:05:05Z | notifier | sa-east-1 | warning | 6913 | queue drained without incident |
| 1266 | 2026-03-07T21:06:18Z | uploader | us-east-1 | skipped | 6950 | disk watermark crossed, trimmed oldest segments |
| 1267 | 2026-03-08T21:07:31Z | compactor | ap-northeast-3 | ok | 6987 | clock skew corrected against NTP |
| 1268 | 2026-03-09T21:08:44Z | watcher | ap-south-1 | pending | 7024 | config reloaded from disk |
| 1269 | 2026-03-10T21:09:57Z | renderer | eu-west-2 | cancelled | 7061 | no change since the previous sweep |
| 1270 | 2026-03-11T21:10:10Z | scheduler | af-south-1 | error | 7098 | backpressure from the upstream shard |
| 1271 | 2026-03-12T21:11:23Z | gateway | us-west-2 | retrying | 7135 | DNS lookup retried twice |
| 1272 | 2026-03-13T21:12:36Z | indexer | eu-north-1 | warning | 7172 | restarted after a failed health check |
| 1273 | 2026-03-14T21:13:49Z | cache | sa-east-1 | skipped | 7209 | leader election completed |
| 1274 | 2026-03-15T21:14:02Z | resolver | us-east-1 | ok | 7246 | manual intervention requested by the operator |
| 1275 | 2026-03-16T21:15:15Z | shipper | ap-northeast-3 | pending | 7283 | cold start took longer than the budget |
| 1276 | 2026-03-17T21:16:28Z | reaper | ap-south-1 | cancelled | 7320 | certificate rotated |
| 1277 | 2026-03-18T21:17:41Z | notifier | eu-west-2 | error | 7357 | queue drained without incident |
| 1278 | 2026-03-19T21:18:54Z | uploader | af-south-1 | retrying | 7394 | disk watermark crossed, trimmed oldest segments |
| 1279 | 2026-03-20T21:19:07Z | compactor | us-west-2 | warning | 7431 | clock skew corrected against NTP |
| 1280 | 2026-03-21T21:20:20Z | watcher | eu-north-1 | skipped | 7468 | config reloaded from disk |
| 1281 | 2026-03-22T21:21:33Z | renderer | sa-east-1 | ok | 7505 | no change since the previous sweep |
| 1282 | 2026-03-23T21:22:46Z | scheduler | us-east-1 | pending | 7542 | backpressure from the upstream shard |
| 1283 | 2026-03-24T21:23:59Z | gateway | ap-northeast-3 | cancelled | 7579 | DNS lookup retried twice |
| 1284 | 2026-03-25T21:24:12Z | indexer | ap-south-1 | error | 7616 | restarted after a failed health check |
| 1285 | 2026-03-26T21:25:25Z | cache | eu-west-2 | retrying | 7653 | leader election completed |
| 1286 | 2026-03-27T21:26:38Z | resolver | af-south-1 | warning | 7690 | manual intervention requested by the operator |
| 1287 | 2026-03-28T21:27:51Z | shipper | us-west-2 | skipped | 7727 | cold start took longer than the budget |
| 1288 | 2026-03-01T21:28:04Z | reaper | eu-north-1 | ok | 7764 | certificate rotated |
| 1289 | 2026-03-02T21:29:17Z | notifier | sa-east-1 | pending | 7801 | queue drained without incident |
| 1290 | 2026-03-03T21:30:30Z | uploader | us-east-1 | cancelled | 7838 | disk watermark crossed, trimmed oldest segments |
| 1291 | 2026-03-04T21:31:43Z | compactor | ap-northeast-3 | error | 7875 | clock skew corrected against NTP |
| 1292 | 2026-03-05T21:32:56Z | watcher | ap-south-1 | retrying | 7912 | config reloaded from disk |
| 1293 | 2026-03-06T21:33:09Z | renderer | eu-west-2 | warning | 7949 | no change since the previous sweep |
| 1294 | 2026-03-07T21:34:22Z | scheduler | af-south-1 | skipped | 7986 | backpressure from the upstream shard |
| 1295 | 2026-03-08T21:35:35Z | gateway | us-west-2 | ok | 8023 | DNS lookup retried twice |
| 1296 | 2026-03-09T21:36:48Z | indexer | eu-north-1 | pending | 8060 | restarted after a failed health check |
| 1297 | 2026-03-10T21:37:01Z | cache | sa-east-1 | cancelled | 8097 | leader election completed |
| 1298 | 2026-03-11T21:38:14Z | resolver | us-east-1 | error | 8134 | manual intervention requested by the operator |
| 1299 | 2026-03-12T21:39:27Z | shipper | ap-northeast-3 | retrying | 8171 | cold start took longer than the budget |
| 1300 | 2026-03-13T21:40:40Z | reaper | ap-south-1 | warning | 8208 | certificate rotated |
| 1301 | 2026-03-14T21:41:53Z | notifier | eu-west-2 | skipped | 8245 | queue drained without incident |
| 1302 | 2026-03-15T21:42:06Z | uploader | af-south-1 | ok | 8282 | disk watermark crossed, trimmed oldest segments |
| 1303 | 2026-03-16T21:43:19Z | compactor | us-west-2 | pending | 8319 | clock skew corrected against NTP |
| 1304 | 2026-03-17T21:44:32Z | watcher | eu-north-1 | cancelled | 8356 | config reloaded from disk |
| 1305 | 2026-03-18T21:45:45Z | renderer | sa-east-1 | error | 8393 | no change since the previous sweep |
| 1306 | 2026-03-19T21:46:58Z | scheduler | us-east-1 | retrying | 8430 | backpressure from the upstream shard |
| 1307 | 2026-03-20T21:47:11Z | gateway | ap-northeast-3 | warning | 8467 | DNS lookup retried twice |
| 1308 | 2026-03-21T21:48:24Z | indexer | ap-south-1 | skipped | 8504 | restarted after a failed health check |
| 1309 | 2026-03-22T21:49:37Z | cache | eu-west-2 | ok | 8541 | leader election completed |
| 1310 | 2026-03-23T21:50:50Z | resolver | af-south-1 | pending | 8578 | manual intervention requested by the operator |
| 1311 | 2026-03-24T21:51:03Z | shipper | us-west-2 | cancelled | 8615 | cold start took longer than the budget |
| 1312 | 2026-03-25T21:52:16Z | reaper | eu-north-1 | error | 8652 | certificate rotated |
| 1313 | 2026-03-26T21:53:29Z | notifier | sa-east-1 | retrying | 8689 | queue drained without incident |
| 1314 | 2026-03-27T21:54:42Z | uploader | us-east-1 | warning | 8726 | disk watermark crossed, trimmed oldest segments |
| 1315 | 2026-03-28T21:55:55Z | compactor | ap-northeast-3 | skipped | 8763 | clock skew corrected against NTP |
| 1316 | 2026-03-01T21:56:08Z | watcher | ap-south-1 | ok | 8800 | config reloaded from disk |
| 1317 | 2026-03-02T21:57:21Z | renderer | eu-west-2 | pending | 8837 | no change since the previous sweep |
| 1318 | 2026-03-03T21:58:34Z | scheduler | af-south-1 | cancelled | 8874 | backpressure from the upstream shard |
| 1319 | 2026-03-04T21:59:47Z | gateway | us-west-2 | error | 8911 | DNS lookup retried twice |
| 1320 | 2026-03-05T22:00:00Z | indexer | eu-north-1 | retrying | 8948 | restarted after a failed health check |
| 1321 | 2026-03-06T22:01:13Z | cache | sa-east-1 | warning | 8985 | leader election completed |
| 1322 | 2026-03-07T22:02:26Z | resolver | us-east-1 | skipped | 9022 | manual intervention requested by the operator |
| 1323 | 2026-03-08T22:03:39Z | shipper | ap-northeast-3 | ok | 9059 | cold start took longer than the budget |
| 1324 | 2026-03-09T22:04:52Z | reaper | ap-south-1 | pending | 9096 | certificate rotated |
| 1325 | 2026-03-10T22:05:05Z | notifier | eu-west-2 | cancelled | 9133 | queue drained without incident |
| 1326 | 2026-03-11T22:06:18Z | uploader | af-south-1 | error | 9170 | disk watermark crossed, trimmed oldest segments |
| 1327 | 2026-03-12T22:07:31Z | compactor | us-west-2 | retrying | 9207 | clock skew corrected against NTP |
| 1328 | 2026-03-13T22:08:44Z | watcher | eu-north-1 | warning | 9244 | config reloaded from disk |
| 1329 | 2026-03-14T22:09:57Z | renderer | sa-east-1 | skipped | 9281 | no change since the previous sweep |
| 1330 | 2026-03-15T22:10:10Z | scheduler | us-east-1 | ok | 9318 | backpressure from the upstream shard |
| 1331 | 2026-03-16T22:11:23Z | gateway | ap-northeast-3 | pending | 9355 | DNS lookup retried twice |
| 1332 | 2026-03-17T22:12:36Z | indexer | ap-south-1 | cancelled | 9392 | restarted after a failed health check |
| 1333 | 2026-03-18T22:13:49Z | cache | eu-west-2 | error | 9429 | leader election completed |
| 1334 | 2026-03-19T22:14:02Z | resolver | af-south-1 | retrying | 9466 | manual intervention requested by the operator |
| 1335 | 2026-03-20T22:15:15Z | shipper | us-west-2 | warning | 9503 | cold start took longer than the budget |
| 1336 | 2026-03-21T22:16:28Z | reaper | eu-north-1 | skipped | 9540 | certificate rotated |
| 1337 | 2026-03-22T22:17:41Z | notifier | sa-east-1 | ok | 9577 | queue drained without incident |
| 1338 | 2026-03-23T22:18:54Z | uploader | us-east-1 | pending | 9614 | disk watermark crossed, trimmed oldest segments |
| 1339 | 2026-03-24T22:19:07Z | compactor | ap-northeast-3 | cancelled | 9651 | clock skew corrected against NTP |
| 1340 | 2026-03-25T22:20:20Z | watcher | ap-south-1 | error | 9688 | config reloaded from disk |
| 1341 | 2026-03-26T22:21:33Z | renderer | eu-west-2 | retrying | 9725 | no change since the previous sweep |
| 1342 | 2026-03-27T22:22:46Z | scheduler | af-south-1 | warning | 9762 | backpressure from the upstream shard |
| 1343 | 2026-03-28T22:23:59Z | gateway | us-west-2 | skipped | 9799 | DNS lookup retried twice |
| 1344 | 2026-03-01T22:24:12Z | indexer | eu-north-1 | ok | 9836 | restarted after a failed health check |
| 1345 | 2026-03-02T22:25:25Z | cache | sa-east-1 | pending | 9873 | leader election completed |
| 1346 | 2026-03-03T22:26:38Z | resolver | us-east-1 | cancelled | 9910 | manual intervention requested by the operator |
| 1347 | 2026-03-04T22:27:51Z | shipper | ap-northeast-3 | error | 9947 | cold start took longer than the budget |
| 1348 | 2026-03-05T22:28:04Z | reaper | ap-south-1 | retrying | 11 | certificate rotated |
| 1349 | 2026-03-06T22:29:17Z | notifier | eu-west-2 | warning | 48 | queue drained without incident |
| 1350 | 2026-03-07T22:30:30Z | uploader | af-south-1 | skipped | 85 | disk watermark crossed, trimmed oldest segments |
| 1351 | 2026-03-08T22:31:43Z | compactor | us-west-2 | ok | 122 | clock skew corrected against NTP |
| 1352 | 2026-03-09T22:32:56Z | watcher | eu-north-1 | pending | 159 | config reloaded from disk |
| 1353 | 2026-03-10T22:33:09Z | renderer | sa-east-1 | cancelled | 196 | no change since the previous sweep |
| 1354 | 2026-03-11T22:34:22Z | scheduler | us-east-1 | error | 233 | backpressure from the upstream shard |
| 1355 | 2026-03-12T22:35:35Z | gateway | ap-northeast-3 | retrying | 270 | DNS lookup retried twice |
| 1356 | 2026-03-13T22:36:48Z | indexer | ap-south-1 | warning | 307 | restarted after a failed health check |
| 1357 | 2026-03-14T22:37:01Z | cache | eu-west-2 | skipped | 344 | leader election completed |
| 1358 | 2026-03-15T22:38:14Z | resolver | af-south-1 | ok | 381 | manual intervention requested by the operator |
| 1359 | 2026-03-16T22:39:27Z | shipper | us-west-2 | pending | 418 | cold start took longer than the budget |
| 1360 | 2026-03-17T22:40:40Z | reaper | eu-north-1 | cancelled | 455 | certificate rotated |
| 1361 | 2026-03-18T22:41:53Z | notifier | sa-east-1 | error | 492 | queue drained without incident |
| 1362 | 2026-03-19T22:42:06Z | uploader | us-east-1 | retrying | 529 | disk watermark crossed, trimmed oldest segments |
| 1363 | 2026-03-20T22:43:19Z | compactor | ap-northeast-3 | warning | 566 | clock skew corrected against NTP |
| 1364 | 2026-03-21T22:44:32Z | watcher | ap-south-1 | skipped | 603 | config reloaded from disk |
| 1365 | 2026-03-22T22:45:45Z | renderer | eu-west-2 | ok | 640 | no change since the previous sweep |
| 1366 | 2026-03-23T22:46:58Z | scheduler | af-south-1 | pending | 677 | backpressure from the upstream shard |
| 1367 | 2026-03-24T22:47:11Z | gateway | us-west-2 | cancelled | 714 | DNS lookup retried twice |
| 1368 | 2026-03-25T22:48:24Z | indexer | eu-north-1 | error | 751 | restarted after a failed health check |
| 1369 | 2026-03-26T22:49:37Z | cache | sa-east-1 | retrying | 788 | leader election completed |
| 1370 | 2026-03-27T22:50:50Z | resolver | us-east-1 | warning | 825 | manual intervention requested by the operator |
| 1371 | 2026-03-28T22:51:03Z | shipper | ap-northeast-3 | skipped | 862 | cold start took longer than the budget |
| 1372 | 2026-03-01T22:52:16Z | reaper | ap-south-1 | ok | 899 | certificate rotated |
| 1373 | 2026-03-02T22:53:29Z | notifier | eu-west-2 | pending | 936 | queue drained without incident |
| 1374 | 2026-03-03T22:54:42Z | uploader | af-south-1 | cancelled | 973 | disk watermark crossed, trimmed oldest segments |
| 1375 | 2026-03-04T22:55:55Z | compactor | us-west-2 | error | 1010 | clock skew corrected against NTP |
| 1376 | 2026-03-05T22:56:08Z | watcher | eu-north-1 | retrying | 1047 | config reloaded from disk |
| 1377 | 2026-03-06T22:57:21Z | renderer | sa-east-1 | warning | 1084 | no change since the previous sweep |
| 1378 | 2026-03-07T22:58:34Z | scheduler | us-east-1 | skipped | 1121 | backpressure from the upstream shard |
| 1379 | 2026-03-08T22:59:47Z | gateway | ap-northeast-3 | ok | 1158 | DNS lookup retried twice |
| 1380 | 2026-03-09T23:00:00Z | indexer | ap-south-1 | pending | 1195 | restarted after a failed health check |
| 1381 | 2026-03-10T23:01:13Z | cache | eu-west-2 | cancelled | 1232 | leader election completed |
| 1382 | 2026-03-11T23:02:26Z | resolver | af-south-1 | error | 1269 | manual intervention requested by the operator |
| 1383 | 2026-03-12T23:03:39Z | shipper | us-west-2 | retrying | 1306 | cold start took longer than the budget |
| 1384 | 2026-03-13T23:04:52Z | reaper | eu-north-1 | warning | 1343 | certificate rotated |
| 1385 | 2026-03-14T23:05:05Z | notifier | sa-east-1 | skipped | 1380 | queue drained without incident |
| 1386 | 2026-03-15T23:06:18Z | uploader | us-east-1 | ok | 1417 | disk watermark crossed, trimmed oldest segments |
| 1387 | 2026-03-16T23:07:31Z | compactor | ap-northeast-3 | pending | 1454 | clock skew corrected against NTP |
| 1388 | 2026-03-17T23:08:44Z | watcher | ap-south-1 | cancelled | 1491 | config reloaded from disk |
| 1389 | 2026-03-18T23:09:57Z | renderer | eu-west-2 | error | 1528 | no change since the previous sweep |
| 1390 | 2026-03-19T23:10:10Z | scheduler | af-south-1 | retrying | 1565 | backpressure from the upstream shard |
| 1391 | 2026-03-20T23:11:23Z | gateway | us-west-2 | warning | 1602 | DNS lookup retried twice |
| 1392 | 2026-03-21T23:12:36Z | indexer | eu-north-1 | skipped | 1639 | restarted after a failed health check |
| 1393 | 2026-03-22T23:13:49Z | cache | sa-east-1 | ok | 1676 | leader election completed |
| 1394 | 2026-03-23T23:14:02Z | resolver | us-east-1 | pending | 1713 | manual intervention requested by the operator |
| 1395 | 2026-03-24T23:15:15Z | shipper | ap-northeast-3 | cancelled | 1750 | cold start took longer than the budget |
| 1396 | 2026-03-25T23:16:28Z | reaper | ap-south-1 | error | 1787 | certificate rotated |
| 1397 | 2026-03-26T23:17:41Z | notifier | eu-west-2 | retrying | 1824 | queue drained without incident |
| 1398 | 2026-03-27T23:18:54Z | uploader | af-south-1 | warning | 1861 | disk watermark crossed, trimmed oldest segments |
| 1399 | 2026-03-28T23:19:07Z | compactor | us-west-2 | skipped | 1898 | clock skew corrected against NTP |
| 1400 | 2026-03-01T23:20:20Z | watcher | eu-north-1 | ok | 1935 | config reloaded from disk |
| 1401 | 2026-03-02T23:21:33Z | renderer | sa-east-1 | pending | 1972 | no change since the previous sweep |
| 1402 | 2026-03-03T23:22:46Z | scheduler | us-east-1 | cancelled | 2009 | backpressure from the upstream shard |
| 1403 | 2026-03-04T23:23:59Z | gateway | ap-northeast-3 | error | 2046 | DNS lookup retried twice |
| 1404 | 2026-03-05T23:24:12Z | indexer | ap-south-1 | retrying | 2083 | restarted after a failed health check |
| 1405 | 2026-03-06T23:25:25Z | cache | eu-west-2 | warning | 2120 | leader election completed |
| 1406 | 2026-03-07T23:26:38Z | resolver | af-south-1 | skipped | 2157 | manual intervention requested by the operator |
| 1407 | 2026-03-08T23:27:51Z | shipper | us-west-2 | ok | 2194 | cold start took longer than the budget |
| 1408 | 2026-03-09T23:28:04Z | reaper | eu-north-1 | pending | 2231 | certificate rotated |
| 1409 | 2026-03-10T23:29:17Z | notifier | sa-east-1 | cancelled | 2268 | queue drained without incident |
| 1410 | 2026-03-11T23:30:30Z | uploader | us-east-1 | error | 2305 | disk watermark crossed, trimmed oldest segments |
| 1411 | 2026-03-12T23:31:43Z | compactor | ap-northeast-3 | retrying | 2342 | clock skew corrected against NTP |
| 1412 | 2026-03-13T23:32:56Z | watcher | ap-south-1 | warning | 2379 | config reloaded from disk |
| 1413 | 2026-03-14T23:33:09Z | renderer | eu-west-2 | skipped | 2416 | no change since the previous sweep |
| 1414 | 2026-03-15T23:34:22Z | scheduler | af-south-1 | ok | 2453 | backpressure from the upstream shard |
| 1415 | 2026-03-16T23:35:35Z | gateway | us-west-2 | pending | 2490 | DNS lookup retried twice |
| 1416 | 2026-03-17T23:36:48Z | indexer | eu-north-1 | cancelled | 2527 | restarted after a failed health check |
| 1417 | 2026-03-18T23:37:01Z | cache | sa-east-1 | error | 2564 | leader election completed |
| 1418 | 2026-03-19T23:38:14Z | resolver | us-east-1 | retrying | 2601 | manual intervention requested by the operator |
| 1419 | 2026-03-20T23:39:27Z | shipper | ap-northeast-3 | warning | 2638 | cold start took longer than the budget |
| 1420 | 2026-03-21T23:40:40Z | reaper | ap-south-1 | skipped | 2675 | certificate rotated |
| 1421 | 2026-03-22T23:41:53Z | notifier | eu-west-2 | ok | 2712 | queue drained without incident |
| 1422 | 2026-03-23T23:42:06Z | uploader | af-south-1 | pending | 2749 | disk watermark crossed, trimmed oldest segments |
| 1423 | 2026-03-24T23:43:19Z | compactor | us-west-2 | cancelled | 2786 | clock skew corrected against NTP |
| 1424 | 2026-03-25T23:44:32Z | watcher | eu-north-1 | error | 2823 | config reloaded from disk |
| 1425 | 2026-03-26T23:45:45Z | renderer | sa-east-1 | retrying | 2860 | no change since the previous sweep |
| 1426 | 2026-03-27T23:46:58Z | scheduler | us-east-1 | warning | 2897 | backpressure from the upstream shard |
| 1427 | 2026-03-28T23:47:11Z | gateway | ap-northeast-3 | skipped | 2934 | DNS lookup retried twice |
| 1428 | 2026-03-01T23:48:24Z | indexer | ap-south-1 | ok | 2971 | restarted after a failed health check |
| 1429 | 2026-03-02T23:49:37Z | cache | eu-west-2 | pending | 3008 | leader election completed |
| 1430 | 2026-03-03T23:50:50Z | resolver | af-south-1 | cancelled | 3045 | manual intervention requested by the operator |
| 1431 | 2026-03-04T23:51:03Z | shipper | us-west-2 | error | 3082 | cold start took longer than the budget |
| 1432 | 2026-03-05T23:52:16Z | reaper | eu-north-1 | retrying | 3119 | certificate rotated |
| 1433 | 2026-03-06T23:53:29Z | notifier | sa-east-1 | warning | 3156 | queue drained without incident |
| 1434 | 2026-03-07T23:54:42Z | uploader | us-east-1 | skipped | 3193 | disk watermark crossed, trimmed oldest segments |
| 1435 | 2026-03-08T23:55:55Z | compactor | ap-northeast-3 | ok | 3230 | clock skew corrected against NTP |
| 1436 | 2026-03-09T23:56:08Z | watcher | ap-south-1 | pending | 3267 | config reloaded from disk |
| 1437 | 2026-03-10T23:57:21Z | renderer | eu-west-2 | cancelled | 3304 | no change since the previous sweep |
| 1438 | 2026-03-11T23:58:34Z | scheduler | af-south-1 | error | 3341 | backpressure from the upstream shard |
| 1439 | 2026-03-12T23:59:47Z | gateway | us-west-2 | retrying | 3378 | DNS lookup retried twice |
| 1440 | 2026-03-13T00:00:00Z | indexer | eu-north-1 | warning | 3415 | restarted after a failed health check |
| 1441 | 2026-03-14T00:01:13Z | cache | sa-east-1 | skipped | 3452 | leader election completed |
| 1442 | 2026-03-15T00:02:26Z | resolver | us-east-1 | ok | 3489 | manual intervention requested by the operator |
| 1443 | 2026-03-16T00:03:39Z | shipper | ap-northeast-3 | pending | 3526 | cold start took longer than the budget |
| 1444 | 2026-03-17T00:04:52Z | reaper | ap-south-1 | cancelled | 3563 | certificate rotated |
| 1445 | 2026-03-18T00:05:05Z | notifier | eu-west-2 | error | 3600 | queue drained without incident |
| 1446 | 2026-03-19T00:06:18Z | uploader | af-south-1 | retrying | 3637 | disk watermark crossed, trimmed oldest segments |
| 1447 | 2026-03-20T00:07:31Z | compactor | us-west-2 | warning | 3674 | clock skew corrected against NTP |
| 1448 | 2026-03-21T00:08:44Z | watcher | eu-north-1 | skipped | 3711 | config reloaded from disk |
| 1449 | 2026-03-22T00:09:57Z | renderer | sa-east-1 | ok | 3748 | no change since the previous sweep |
| 1450 | 2026-03-23T00:10:10Z | scheduler | us-east-1 | pending | 3785 | backpressure from the upstream shard |
| 1451 | 2026-03-24T00:11:23Z | gateway | ap-northeast-3 | cancelled | 3822 | DNS lookup retried twice |
| 1452 | 2026-03-25T00:12:36Z | indexer | ap-south-1 | error | 3859 | restarted after a failed health check |
| 1453 | 2026-03-26T00:13:49Z | cache | eu-west-2 | retrying | 3896 | leader election completed |
| 1454 | 2026-03-27T00:14:02Z | resolver | af-south-1 | warning | 3933 | manual intervention requested by the operator |
| 1455 | 2026-03-28T00:15:15Z | shipper | us-west-2 | skipped | 3970 | cold start took longer than the budget |
| 1456 | 2026-03-01T00:16:28Z | reaper | eu-north-1 | ok | 4007 | certificate rotated |
| 1457 | 2026-03-02T00:17:41Z | notifier | sa-east-1 | pending | 4044 | queue drained without incident |
| 1458 | 2026-03-03T00:18:54Z | uploader | us-east-1 | cancelled | 4081 | disk watermark crossed, trimmed oldest segments |
| 1459 | 2026-03-04T00:19:07Z | compactor | ap-northeast-3 | error | 4118 | clock skew corrected against NTP |
| 1460 | 2026-03-05T00:20:20Z | watcher | ap-south-1 | retrying | 4155 | config reloaded from disk |
| 1461 | 2026-03-06T00:21:33Z | renderer | eu-west-2 | warning | 4192 | no change since the previous sweep |
| 1462 | 2026-03-07T00:22:46Z | scheduler | af-south-1 | skipped | 4229 | backpressure from the upstream shard |
| 1463 | 2026-03-08T00:23:59Z | gateway | us-west-2 | ok | 4266 | DNS lookup retried twice |
| 1464 | 2026-03-09T00:24:12Z | indexer | eu-north-1 | pending | 4303 | restarted after a failed health check |
| 1465 | 2026-03-10T00:25:25Z | cache | sa-east-1 | cancelled | 4340 | leader election completed |
| 1466 | 2026-03-11T00:26:38Z | resolver | us-east-1 | error | 4377 | manual intervention requested by the operator |
| 1467 | 2026-03-12T00:27:51Z | shipper | ap-northeast-3 | retrying | 4414 | cold start took longer than the budget |
| 1468 | 2026-03-13T00:28:04Z | reaper | ap-south-1 | warning | 4451 | certificate rotated |
| 1469 | 2026-03-14T00:29:17Z | notifier | eu-west-2 | skipped | 4488 | queue drained without incident |
| 1470 | 2026-03-15T00:30:30Z | uploader | af-south-1 | ok | 4525 | disk watermark crossed, trimmed oldest segments |
| 1471 | 2026-03-16T00:31:43Z | compactor | us-west-2 | pending | 4562 | clock skew corrected against NTP |
| 1472 | 2026-03-17T00:32:56Z | watcher | eu-north-1 | cancelled | 4599 | config reloaded from disk |
| 1473 | 2026-03-18T00:33:09Z | renderer | sa-east-1 | error | 4636 | no change since the previous sweep |
| 1474 | 2026-03-19T00:34:22Z | scheduler | us-east-1 | retrying | 4673 | backpressure from the upstream shard |
| 1475 | 2026-03-20T00:35:35Z | gateway | ap-northeast-3 | warning | 4710 | DNS lookup retried twice |
| 1476 | 2026-03-21T00:36:48Z | indexer | ap-south-1 | skipped | 4747 | restarted after a failed health check |
| 1477 | 2026-03-22T00:37:01Z | cache | eu-west-2 | ok | 4784 | leader election completed |
| 1478 | 2026-03-23T00:38:14Z | resolver | af-south-1 | pending | 4821 | manual intervention requested by the operator |
| 1479 | 2026-03-24T00:39:27Z | shipper | us-west-2 | cancelled | 4858 | cold start took longer than the budget |
| 1480 | 2026-03-25T00:40:40Z | reaper | eu-north-1 | error | 4895 | certificate rotated |
| 1481 | 2026-03-26T00:41:53Z | notifier | sa-east-1 | retrying | 4932 | queue drained without incident |
| 1482 | 2026-03-27T00:42:06Z | uploader | us-east-1 | warning | 4969 | disk watermark crossed, trimmed oldest segments |
| 1483 | 2026-03-28T00:43:19Z | compactor | ap-northeast-3 | skipped | 5006 | clock skew corrected against NTP |
| 1484 | 2026-03-01T00:44:32Z | watcher | ap-south-1 | ok | 5043 | config reloaded from disk |
| 1485 | 2026-03-02T00:45:45Z | renderer | eu-west-2 | pending | 5080 | no change since the previous sweep |
| 1486 | 2026-03-03T00:46:58Z | scheduler | af-south-1 | cancelled | 5117 | backpressure from the upstream shard |
| 1487 | 2026-03-04T00:47:11Z | gateway | us-west-2 | error | 5154 | DNS lookup retried twice |
| 1488 | 2026-03-05T00:48:24Z | indexer | eu-north-1 | retrying | 5191 | restarted after a failed health check |
| 1489 | 2026-03-06T00:49:37Z | cache | sa-east-1 | warning | 5228 | leader election completed |
| 1490 | 2026-03-07T00:50:50Z | resolver | us-east-1 | skipped | 5265 | manual intervention requested by the operator |
| 1491 | 2026-03-08T00:51:03Z | shipper | ap-northeast-3 | ok | 5302 | cold start took longer than the budget |
| 1492 | 2026-03-09T00:52:16Z | reaper | ap-south-1 | pending | 5339 | certificate rotated |
| 1493 | 2026-03-10T00:53:29Z | notifier | eu-west-2 | cancelled | 5376 | queue drained without incident |
| 1494 | 2026-03-11T00:54:42Z | uploader | af-south-1 | error | 5413 | disk watermark crossed, trimmed oldest segments |
| 1495 | 2026-03-12T00:55:55Z | compactor | us-west-2 | retrying | 5450 | clock skew corrected against NTP |
| 1496 | 2026-03-13T00:56:08Z | watcher | eu-north-1 | warning | 5487 | config reloaded from disk |
| 1497 | 2026-03-14T00:57:21Z | renderer | sa-east-1 | skipped | 5524 | no change since the previous sweep |
| 1498 | 2026-03-15T00:58:34Z | scheduler | us-east-1 | ok | 5561 | backpressure from the upstream shard |
| 1499 | 2026-03-16T00:59:47Z | gateway | ap-northeast-3 | pending | 5598 | DNS lookup retried twice |
| 1500 | 2026-03-17T01:00:00Z | indexer | ap-south-1 | cancelled | 5635 | restarted after a failed health check |
| 1501 | 2026-03-18T01:01:13Z | cache | eu-west-2 | error | 5672 | leader election completed |
| 1502 | 2026-03-19T01:02:26Z | resolver | af-south-1 | retrying | 5709 | manual intervention requested by the operator |
| 1503 | 2026-03-20T01:03:39Z | shipper | us-west-2 | warning | 5746 | cold start took longer than the budget |
| 1504 | 2026-03-21T01:04:52Z | reaper | eu-north-1 | skipped | 5783 | certificate rotated |
| 1505 | 2026-03-22T01:05:05Z | notifier | sa-east-1 | ok | 5820 | queue drained without incident |
| 1506 | 2026-03-23T01:06:18Z | uploader | us-east-1 | pending | 5857 | disk watermark crossed, trimmed oldest segments |
| 1507 | 2026-03-24T01:07:31Z | compactor | ap-northeast-3 | cancelled | 5894 | clock skew corrected against NTP |
| 1508 | 2026-03-25T01:08:44Z | watcher | ap-south-1 | error | 5931 | config reloaded from disk |
| 1509 | 2026-03-26T01:09:57Z | renderer | eu-west-2 | retrying | 5968 | no change since the previous sweep |
| 1510 | 2026-03-27T01:10:10Z | scheduler | af-south-1 | warning | 6005 | backpressure from the upstream shard |
| 1511 | 2026-03-28T01:11:23Z | gateway | us-west-2 | skipped | 6042 | DNS lookup retried twice |
| 1512 | 2026-03-01T01:12:36Z | indexer | eu-north-1 | ok | 6079 | restarted after a failed health check |
| 1513 | 2026-03-02T01:13:49Z | cache | sa-east-1 | pending | 6116 | leader election completed |
| 1514 | 2026-03-03T01:14:02Z | resolver | us-east-1 | cancelled | 6153 | manual intervention requested by the operator |
| 1515 | 2026-03-04T01:15:15Z | shipper | ap-northeast-3 | error | 6190 | cold start took longer than the budget |
| 1516 | 2026-03-05T01:16:28Z | reaper | ap-south-1 | retrying | 6227 | certificate rotated |
| 1517 | 2026-03-06T01:17:41Z | notifier | eu-west-2 | warning | 6264 | queue drained without incident |
| 1518 | 2026-03-07T01:18:54Z | uploader | af-south-1 | skipped | 6301 | disk watermark crossed, trimmed oldest segments |
| 1519 | 2026-03-08T01:19:07Z | compactor | us-west-2 | ok | 6338 | clock skew corrected against NTP |
| 1520 | 2026-03-09T01:20:20Z | watcher | eu-north-1 | pending | 6375 | config reloaded from disk |
| 1521 | 2026-03-10T01:21:33Z | renderer | sa-east-1 | cancelled | 6412 | no change since the previous sweep |
| 1522 | 2026-03-11T01:22:46Z | scheduler | us-east-1 | error | 6449 | backpressure from the upstream shard |
| 1523 | 2026-03-12T01:23:59Z | gateway | ap-northeast-3 | retrying | 6486 | DNS lookup retried twice |
| 1524 | 2026-03-13T01:24:12Z | indexer | ap-south-1 | warning | 6523 | restarted after a failed health check |
| 1525 | 2026-03-14T01:25:25Z | cache | eu-west-2 | skipped | 6560 | leader election completed |
| 1526 | 2026-03-15T01:26:38Z | resolver | af-south-1 | ok | 6597 | manual intervention requested by the operator |
| 1527 | 2026-03-16T01:27:51Z | shipper | us-west-2 | pending | 6634 | cold start took longer than the budget |
| 1528 | 2026-03-17T01:28:04Z | reaper | eu-north-1 | cancelled | 6671 | certificate rotated |
| 1529 | 2026-03-18T01:29:17Z | notifier | sa-east-1 | error | 6708 | queue drained without incident |
| 1530 | 2026-03-19T01:30:30Z | uploader | us-east-1 | retrying | 6745 | disk watermark crossed, trimmed oldest segments |
| 1531 | 2026-03-20T01:31:43Z | compactor | ap-northeast-3 | warning | 6782 | clock skew corrected against NTP |
| 1532 | 2026-03-21T01:32:56Z | watcher | ap-south-1 | skipped | 6819 | config reloaded from disk |
| 1533 | 2026-03-22T01:33:09Z | renderer | eu-west-2 | ok | 6856 | no change since the previous sweep |
| 1534 | 2026-03-23T01:34:22Z | scheduler | af-south-1 | pending | 6893 | backpressure from the upstream shard |
| 1535 | 2026-03-24T01:35:35Z | gateway | us-west-2 | cancelled | 6930 | DNS lookup retried twice |
| 1536 | 2026-03-25T01:36:48Z | indexer | eu-north-1 | error | 6967 | restarted after a failed health check |
| 1537 | 2026-03-26T01:37:01Z | cache | sa-east-1 | retrying | 7004 | leader election completed |
| 1538 | 2026-03-27T01:38:14Z | resolver | us-east-1 | warning | 7041 | manual intervention requested by the operator |
| 1539 | 2026-03-28T01:39:27Z | shipper | ap-northeast-3 | skipped | 7078 | cold start took longer than the budget |
| 1540 | 2026-03-01T01:40:40Z | reaper | ap-south-1 | ok | 7115 | certificate rotated |
| 1541 | 2026-03-02T01:41:53Z | notifier | eu-west-2 | pending | 7152 | queue drained without incident |
| 1542 | 2026-03-03T01:42:06Z | uploader | af-south-1 | cancelled | 7189 | disk watermark crossed, trimmed oldest segments |
| 1543 | 2026-03-04T01:43:19Z | compactor | us-west-2 | error | 7226 | clock skew corrected against NTP |
| 1544 | 2026-03-05T01:44:32Z | watcher | eu-north-1 | retrying | 7263 | config reloaded from disk |
| 1545 | 2026-03-06T01:45:45Z | renderer | sa-east-1 | warning | 7300 | no change since the previous sweep |
| 1546 | 2026-03-07T01:46:58Z | scheduler | us-east-1 | skipped | 7337 | backpressure from the upstream shard |
| 1547 | 2026-03-08T01:47:11Z | gateway | ap-northeast-3 | ok | 7374 | DNS lookup retried twice |
| 1548 | 2026-03-09T01:48:24Z | indexer | ap-south-1 | pending | 7411 | restarted after a failed health check |
| 1549 | 2026-03-10T01:49:37Z | cache | eu-west-2 | cancelled | 7448 | leader election completed |
| 1550 | 2026-03-11T01:50:50Z | resolver | af-south-1 | error | 7485 | manual intervention requested by the operator |
| 1551 | 2026-03-12T01:51:03Z | shipper | us-west-2 | retrying | 7522 | cold start took longer than the budget |
| 1552 | 2026-03-13T01:52:16Z | reaper | eu-north-1 | warning | 7559 | certificate rotated |
| 1553 | 2026-03-14T01:53:29Z | notifier | sa-east-1 | skipped | 7596 | queue drained without incident |
| 1554 | 2026-03-15T01:54:42Z | uploader | us-east-1 | ok | 7633 | disk watermark crossed, trimmed oldest segments |
| 1555 | 2026-03-16T01:55:55Z | compactor | ap-northeast-3 | pending | 7670 | clock skew corrected against NTP |
| 1556 | 2026-03-17T01:56:08Z | watcher | ap-south-1 | cancelled | 7707 | config reloaded from disk |
| 1557 | 2026-03-18T01:57:21Z | renderer | eu-west-2 | error | 7744 | no change since the previous sweep |
| 1558 | 2026-03-19T01:58:34Z | scheduler | af-south-1 | retrying | 7781 | backpressure from the upstream shard |
| 1559 | 2026-03-20T01:59:47Z | gateway | us-west-2 | warning | 7818 | DNS lookup retried twice |
| 1560 | 2026-03-21T02:00:00Z | indexer | eu-north-1 | skipped | 7855 | restarted after a failed health check |
| 1561 | 2026-03-22T02:01:13Z | cache | sa-east-1 | ok | 7892 | leader election completed |
| 1562 | 2026-03-23T02:02:26Z | resolver | us-east-1 | pending | 7929 | manual intervention requested by the operator |
| 1563 | 2026-03-24T02:03:39Z | shipper | ap-northeast-3 | cancelled | 7966 | cold start took longer than the budget |
| 1564 | 2026-03-25T02:04:52Z | reaper | ap-south-1 | error | 8003 | certificate rotated |
| 1565 | 2026-03-26T02:05:05Z | notifier | eu-west-2 | retrying | 8040 | queue drained without incident |
| 1566 | 2026-03-27T02:06:18Z | uploader | af-south-1 | warning | 8077 | disk watermark crossed, trimmed oldest segments |
| 1567 | 2026-03-28T02:07:31Z | compactor | us-west-2 | skipped | 8114 | clock skew corrected against NTP |
| 1568 | 2026-03-01T02:08:44Z | watcher | eu-north-1 | ok | 8151 | config reloaded from disk |
| 1569 | 2026-03-02T02:09:57Z | renderer | sa-east-1 | pending | 8188 | no change since the previous sweep |
| 1570 | 2026-03-03T02:10:10Z | scheduler | us-east-1 | cancelled | 8225 | backpressure from the upstream shard |
| 1571 | 2026-03-04T02:11:23Z | gateway | ap-northeast-3 | error | 8262 | DNS lookup retried twice |
| 1572 | 2026-03-05T02:12:36Z | indexer | ap-south-1 | retrying | 8299 | restarted after a failed health check |
| 1573 | 2026-03-06T02:13:49Z | cache | eu-west-2 | warning | 8336 | leader election completed |
| 1574 | 2026-03-07T02:14:02Z | resolver | af-south-1 | skipped | 8373 | manual intervention requested by the operator |
| 1575 | 2026-03-08T02:15:15Z | shipper | us-west-2 | ok | 8410 | cold start took longer than the budget |
| 1576 | 2026-03-09T02:16:28Z | reaper | eu-north-1 | pending | 8447 | certificate rotated |
| 1577 | 2026-03-10T02:17:41Z | notifier | sa-east-1 | cancelled | 8484 | queue drained without incident |
| 1578 | 2026-03-11T02:18:54Z | uploader | us-east-1 | error | 8521 | disk watermark crossed, trimmed oldest segments |
| 1579 | 2026-03-12T02:19:07Z | compactor | ap-northeast-3 | retrying | 8558 | clock skew corrected against NTP |
| 1580 | 2026-03-13T02:20:20Z | watcher | ap-south-1 | warning | 8595 | config reloaded from disk |
| 1581 | 2026-03-14T02:21:33Z | renderer | eu-west-2 | skipped | 8632 | no change since the previous sweep |
| 1582 | 2026-03-15T02:22:46Z | scheduler | af-south-1 | ok | 8669 | backpressure from the upstream shard |
| 1583 | 2026-03-16T02:23:59Z | gateway | us-west-2 | pending | 8706 | DNS lookup retried twice |
| 1584 | 2026-03-17T02:24:12Z | indexer | eu-north-1 | cancelled | 8743 | restarted after a failed health check |
| 1585 | 2026-03-18T02:25:25Z | cache | sa-east-1 | error | 8780 | leader election completed |
| 1586 | 2026-03-19T02:26:38Z | resolver | us-east-1 | retrying | 8817 | manual intervention requested by the operator |
| 1587 | 2026-03-20T02:27:51Z | shipper | ap-northeast-3 | warning | 8854 | cold start took longer than the budget |
| 1588 | 2026-03-21T02:28:04Z | reaper | ap-south-1 | skipped | 8891 | certificate rotated |
| 1589 | 2026-03-22T02:29:17Z | notifier | eu-west-2 | ok | 8928 | queue drained without incident |
| 1590 | 2026-03-23T02:30:30Z | uploader | af-south-1 | pending | 8965 | disk watermark crossed, trimmed oldest segments |
| 1591 | 2026-03-24T02:31:43Z | compactor | us-west-2 | cancelled | 9002 | clock skew corrected against NTP |
| 1592 | 2026-03-25T02:32:56Z | watcher | eu-north-1 | error | 9039 | config reloaded from disk |
| 1593 | 2026-03-26T02:33:09Z | renderer | sa-east-1 | retrying | 9076 | no change since the previous sweep |
| 1594 | 2026-03-27T02:34:22Z | scheduler | us-east-1 | warning | 9113 | backpressure from the upstream shard |
| 1595 | 2026-03-28T02:35:35Z | gateway | ap-northeast-3 | skipped | 9150 | DNS lookup retried twice |
| 1596 | 2026-03-01T02:36:48Z | indexer | ap-south-1 | ok | 9187 | restarted after a failed health check |
| 1597 | 2026-03-02T02:37:01Z | cache | eu-west-2 | pending | 9224 | leader election completed |
| 1598 | 2026-03-03T02:38:14Z | resolver | af-south-1 | cancelled | 9261 | manual intervention requested by the operator |
| 1599 | 2026-03-04T02:39:27Z | shipper | us-west-2 | error | 9298 | cold start took longer than the budget |
| 1600 | 2026-03-05T02:40:40Z | reaper | eu-north-1 | retrying | 9335 | certificate rotated |
| 1601 | 2026-03-06T02:41:53Z | notifier | sa-east-1 | warning | 9372 | queue drained without incident |
| 1602 | 2026-03-07T02:42:06Z | uploader | us-east-1 | skipped | 9409 | disk watermark crossed, trimmed oldest segments |
| 1603 | 2026-03-08T02:43:19Z | compactor | ap-northeast-3 | ok | 9446 | clock skew corrected against NTP |
| 1604 | 2026-03-09T02:44:32Z | watcher | ap-south-1 | pending | 9483 | config reloaded from disk |
| 1605 | 2026-03-10T02:45:45Z | renderer | eu-west-2 | cancelled | 9520 | no change since the previous sweep |
| 1606 | 2026-03-11T02:46:58Z | scheduler | af-south-1 | error | 9557 | backpressure from the upstream shard |
| 1607 | 2026-03-12T02:47:11Z | gateway | us-west-2 | retrying | 9594 | DNS lookup retried twice |
| 1608 | 2026-03-13T02:48:24Z | indexer | eu-north-1 | warning | 9631 | restarted after a failed health check |
| 1609 | 2026-03-14T02:49:37Z | cache | sa-east-1 | skipped | 9668 | leader election completed |
| 1610 | 2026-03-15T02:50:50Z | resolver | us-east-1 | ok | 9705 | manual intervention requested by the operator |
| 1611 | 2026-03-16T02:51:03Z | shipper | ap-northeast-3 | pending | 9742 | cold start took longer than the budget |
| 1612 | 2026-03-17T02:52:16Z | reaper | ap-south-1 | cancelled | 9779 | certificate rotated |
| 1613 | 2026-03-18T02:53:29Z | notifier | eu-west-2 | error | 9816 | queue drained without incident |
| 1614 | 2026-03-19T02:54:42Z | uploader | af-south-1 | retrying | 9853 | disk watermark crossed, trimmed oldest segments |
| 1615 | 2026-03-20T02:55:55Z | compactor | us-west-2 | warning | 9890 | clock skew corrected against NTP |
| 1616 | 2026-03-21T02:56:08Z | watcher | eu-north-1 | skipped | 9927 | config reloaded from disk |
| 1617 | 2026-03-22T02:57:21Z | renderer | sa-east-1 | ok | 9964 | no change since the previous sweep |
| 1618 | 2026-03-23T02:58:34Z | scheduler | us-east-1 | pending | 28 | backpressure from the upstream shard |
| 1619 | 2026-03-24T02:59:47Z | gateway | ap-northeast-3 | cancelled | 65 | DNS lookup retried twice |
| 1620 | 2026-03-25T03:00:00Z | indexer | ap-south-1 | error | 102 | restarted after a failed health check |
| 1621 | 2026-03-26T03:01:13Z | cache | eu-west-2 | retrying | 139 | leader election completed |
| 1622 | 2026-03-27T03:02:26Z | resolver | af-south-1 | warning | 176 | manual intervention requested by the operator |
| 1623 | 2026-03-28T03:03:39Z | shipper | us-west-2 | skipped | 213 | cold start took longer than the budget |
| 1624 | 2026-03-01T03:04:52Z | reaper | eu-north-1 | ok | 250 | certificate rotated |
| 1625 | 2026-03-02T03:05:05Z | notifier | sa-east-1 | pending | 287 | queue drained without incident |
| 1626 | 2026-03-03T03:06:18Z | uploader | us-east-1 | cancelled | 324 | disk watermark crossed, trimmed oldest segments |
| 1627 | 2026-03-04T03:07:31Z | compactor | ap-northeast-3 | error | 361 | clock skew corrected against NTP |
| 1628 | 2026-03-05T03:08:44Z | watcher | ap-south-1 | retrying | 398 | config reloaded from disk |
| 1629 | 2026-03-06T03:09:57Z | renderer | eu-west-2 | warning | 435 | no change since the previous sweep |
| 1630 | 2026-03-07T03:10:10Z | scheduler | af-south-1 | skipped | 472 | backpressure from the upstream shard |
| 1631 | 2026-03-08T03:11:23Z | gateway | us-west-2 | ok | 509 | DNS lookup retried twice |
| 1632 | 2026-03-09T03:12:36Z | indexer | eu-north-1 | pending | 546 | restarted after a failed health check |
| 1633 | 2026-03-10T03:13:49Z | cache | sa-east-1 | cancelled | 583 | leader election completed |
| 1634 | 2026-03-11T03:14:02Z | resolver | us-east-1 | error | 620 | manual intervention requested by the operator |
| 1635 | 2026-03-12T03:15:15Z | shipper | ap-northeast-3 | retrying | 657 | cold start took longer than the budget |
| 1636 | 2026-03-13T03:16:28Z | reaper | ap-south-1 | warning | 694 | certificate rotated |
| 1637 | 2026-03-14T03:17:41Z | notifier | eu-west-2 | skipped | 731 | queue drained without incident |
| 1638 | 2026-03-15T03:18:54Z | uploader | af-south-1 | ok | 768 | disk watermark crossed, trimmed oldest segments |
| 1639 | 2026-03-16T03:19:07Z | compactor | us-west-2 | pending | 805 | clock skew corrected against NTP |
| 1640 | 2026-03-17T03:20:20Z | watcher | eu-north-1 | cancelled | 842 | config reloaded from disk |
| 1641 | 2026-03-18T03:21:33Z | renderer | sa-east-1 | error | 879 | no change since the previous sweep |
| 1642 | 2026-03-19T03:22:46Z | scheduler | us-east-1 | retrying | 916 | backpressure from the upstream shard |
| 1643 | 2026-03-20T03:23:59Z | gateway | ap-northeast-3 | warning | 953 | DNS lookup retried twice |
| 1644 | 2026-03-21T03:24:12Z | indexer | ap-south-1 | skipped | 990 | restarted after a failed health check |
| 1645 | 2026-03-22T03:25:25Z | cache | eu-west-2 | ok | 1027 | leader election completed |
| 1646 | 2026-03-23T03:26:38Z | resolver | af-south-1 | pending | 1064 | manual intervention requested by the operator |
| 1647 | 2026-03-24T03:27:51Z | shipper | us-west-2 | cancelled | 1101 | cold start took longer than the budget |
| 1648 | 2026-03-25T03:28:04Z | reaper | eu-north-1 | error | 1138 | certificate rotated |
| 1649 | 2026-03-26T03:29:17Z | notifier | sa-east-1 | retrying | 1175 | queue drained without incident |
| 1650 | 2026-03-27T03:30:30Z | uploader | us-east-1 | warning | 1212 | disk watermark crossed, trimmed oldest segments |
| 1651 | 2026-03-28T03:31:43Z | compactor | ap-northeast-3 | skipped | 1249 | clock skew corrected against NTP |
| 1652 | 2026-03-01T03:32:56Z | watcher | ap-south-1 | ok | 1286 | config reloaded from disk |
| 1653 | 2026-03-02T03:33:09Z | renderer | eu-west-2 | pending | 1323 | no change since the previous sweep |
| 1654 | 2026-03-03T03:34:22Z | scheduler | af-south-1 | cancelled | 1360 | backpressure from the upstream shard |
| 1655 | 2026-03-04T03:35:35Z | gateway | us-west-2 | error | 1397 | DNS lookup retried twice |
| 1656 | 2026-03-05T03:36:48Z | indexer | eu-north-1 | retrying | 1434 | restarted after a failed health check |
| 1657 | 2026-03-06T03:37:01Z | cache | sa-east-1 | warning | 1471 | leader election completed |
| 1658 | 2026-03-07T03:38:14Z | resolver | us-east-1 | skipped | 1508 | manual intervention requested by the operator |
| 1659 | 2026-03-08T03:39:27Z | shipper | ap-northeast-3 | ok | 1545 | cold start took longer than the budget |
| 1660 | 2026-03-09T03:40:40Z | reaper | ap-south-1 | pending | 1582 | certificate rotated |
| 1661 | 2026-03-10T03:41:53Z | notifier | eu-west-2 | cancelled | 1619 | queue drained without incident |
| 1662 | 2026-03-11T03:42:06Z | uploader | af-south-1 | error | 1656 | disk watermark crossed, trimmed oldest segments |
| 1663 | 2026-03-12T03:43:19Z | compactor | us-west-2 | retrying | 1693 | clock skew corrected against NTP |
| 1664 | 2026-03-13T03:44:32Z | watcher | eu-north-1 | warning | 1730 | config reloaded from disk |
| 1665 | 2026-03-14T03:45:45Z | renderer | sa-east-1 | skipped | 1767 | no change since the previous sweep |
| 1666 | 2026-03-15T03:46:58Z | scheduler | us-east-1 | ok | 1804 | backpressure from the upstream shard |
| 1667 | 2026-03-16T03:47:11Z | gateway | ap-northeast-3 | pending | 1841 | DNS lookup retried twice |
| 1668 | 2026-03-17T03:48:24Z | indexer | ap-south-1 | cancelled | 1878 | restarted after a failed health check |
| 1669 | 2026-03-18T03:49:37Z | cache | eu-west-2 | error | 1915 | leader election completed |
| 1670 | 2026-03-19T03:50:50Z | resolver | af-south-1 | retrying | 1952 | manual intervention requested by the operator |
| 1671 | 2026-03-20T03:51:03Z | shipper | us-west-2 | warning | 1989 | cold start took longer than the budget |
| 1672 | 2026-03-21T03:52:16Z | reaper | eu-north-1 | skipped | 2026 | certificate rotated |
| 1673 | 2026-03-22T03:53:29Z | notifier | sa-east-1 | ok | 2063 | queue drained without incident |
| 1674 | 2026-03-23T03:54:42Z | uploader | us-east-1 | pending | 2100 | disk watermark crossed, trimmed oldest segments |
| 1675 | 2026-03-24T03:55:55Z | compactor | ap-northeast-3 | cancelled | 2137 | clock skew corrected against NTP |
| 1676 | 2026-03-25T03:56:08Z | watcher | ap-south-1 | error | 2174 | config reloaded from disk |
| 1677 | 2026-03-26T03:57:21Z | renderer | eu-west-2 | retrying | 2211 | no change since the previous sweep |
| 1678 | 2026-03-27T03:58:34Z | scheduler | af-south-1 | warning | 2248 | backpressure from the upstream shard |
| 1679 | 2026-03-28T03:59:47Z | gateway | us-west-2 | skipped | 2285 | DNS lookup retried twice |
| 1680 | 2026-03-01T04:00:00Z | indexer | eu-north-1 | ok | 2322 | restarted after a failed health check |
| 1681 | 2026-03-02T04:01:13Z | cache | sa-east-1 | pending | 2359 | leader election completed |
| 1682 | 2026-03-03T04:02:26Z | resolver | us-east-1 | cancelled | 2396 | manual intervention requested by the operator |
| 1683 | 2026-03-04T04:03:39Z | shipper | ap-northeast-3 | error | 2433 | cold start took longer than the budget |
| 1684 | 2026-03-05T04:04:52Z | reaper | ap-south-1 | retrying | 2470 | certificate rotated |
| 1685 | 2026-03-06T04:05:05Z | notifier | eu-west-2 | warning | 2507 | queue drained without incident |
| 1686 | 2026-03-07T04:06:18Z | uploader | af-south-1 | skipped | 2544 | disk watermark crossed, trimmed oldest segments |
| 1687 | 2026-03-08T04:07:31Z | compactor | us-west-2 | ok | 2581 | clock skew corrected against NTP |
| 1688 | 2026-03-09T04:08:44Z | watcher | eu-north-1 | pending | 2618 | config reloaded from disk |
| 1689 | 2026-03-10T04:09:57Z | renderer | sa-east-1 | cancelled | 2655 | no change since the previous sweep |
| 1690 | 2026-03-11T04:10:10Z | scheduler | us-east-1 | error | 2692 | backpressure from the upstream shard |
| 1691 | 2026-03-12T04:11:23Z | gateway | ap-northeast-3 | retrying | 2729 | DNS lookup retried twice |
| 1692 | 2026-03-13T04:12:36Z | indexer | ap-south-1 | warning | 2766 | restarted after a failed health check |
| 1693 | 2026-03-14T04:13:49Z | cache | eu-west-2 | skipped | 2803 | leader election completed |
| 1694 | 2026-03-15T04:14:02Z | resolver | af-south-1 | ok | 2840 | manual intervention requested by the operator |
| 1695 | 2026-03-16T04:15:15Z | shipper | us-west-2 | pending | 2877 | cold start took longer than the budget |
| 1696 | 2026-03-17T04:16:28Z | reaper | eu-north-1 | cancelled | 2914 | certificate rotated |
| 1697 | 2026-03-18T04:17:41Z | notifier | sa-east-1 | error | 2951 | queue drained without incident |
| 1698 | 2026-03-19T04:18:54Z | uploader | us-east-1 | retrying | 2988 | disk watermark crossed, trimmed oldest segments |
| 1699 | 2026-03-20T04:19:07Z | compactor | ap-northeast-3 | warning | 3025 | clock skew corrected against NTP |
| 1700 | 2026-03-21T04:20:20Z | watcher | ap-south-1 | skipped | 3062 | config reloaded from disk |
| 1701 | 2026-03-22T04:21:33Z | renderer | eu-west-2 | ok | 3099 | no change since the previous sweep |
| 1702 | 2026-03-23T04:22:46Z | scheduler | af-south-1 | pending | 3136 | backpressure from the upstream shard |
| 1703 | 2026-03-24T04:23:59Z | gateway | us-west-2 | cancelled | 3173 | DNS lookup retried twice |
| 1704 | 2026-03-25T04:24:12Z | indexer | eu-north-1 | error | 3210 | restarted after a failed health check |
| 1705 | 2026-03-26T04:25:25Z | cache | sa-east-1 | retrying | 3247 | leader election completed |
| 1706 | 2026-03-27T04:26:38Z | resolver | us-east-1 | warning | 3284 | manual intervention requested by the operator |
| 1707 | 2026-03-28T04:27:51Z | shipper | ap-northeast-3 | skipped | 3321 | cold start took longer than the budget |
| 1708 | 2026-03-01T04:28:04Z | reaper | ap-south-1 | ok | 3358 | certificate rotated |
| 1709 | 2026-03-02T04:29:17Z | notifier | eu-west-2 | pending | 3395 | queue drained without incident |
| 1710 | 2026-03-03T04:30:30Z | uploader | af-south-1 | cancelled | 3432 | disk watermark crossed, trimmed oldest segments |
| 1711 | 2026-03-04T04:31:43Z | compactor | us-west-2 | error | 3469 | clock skew corrected against NTP |
| 1712 | 2026-03-05T04:32:56Z | watcher | eu-north-1 | retrying | 3506 | config reloaded from disk |
| 1713 | 2026-03-06T04:33:09Z | renderer | sa-east-1 | warning | 3543 | no change since the previous sweep |
| 1714 | 2026-03-07T04:34:22Z | scheduler | us-east-1 | skipped | 3580 | backpressure from the upstream shard |
| 1715 | 2026-03-08T04:35:35Z | gateway | ap-northeast-3 | ok | 3617 | DNS lookup retried twice |
| 1716 | 2026-03-09T04:36:48Z | indexer | ap-south-1 | pending | 3654 | restarted after a failed health check |
| 1717 | 2026-03-10T04:37:01Z | cache | eu-west-2 | cancelled | 3691 | leader election completed |
| 1718 | 2026-03-11T04:38:14Z | resolver | af-south-1 | error | 3728 | manual intervention requested by the operator |
| 1719 | 2026-03-12T04:39:27Z | shipper | us-west-2 | retrying | 3765 | cold start took longer than the budget |
| 1720 | 2026-03-13T04:40:40Z | reaper | eu-north-1 | warning | 3802 | certificate rotated |
| 1721 | 2026-03-14T04:41:53Z | notifier | sa-east-1 | skipped | 3839 | queue drained without incident |
| 1722 | 2026-03-15T04:42:06Z | uploader | us-east-1 | ok | 3876 | disk watermark crossed, trimmed oldest segments |
| 1723 | 2026-03-16T04:43:19Z | compactor | ap-northeast-3 | pending | 3913 | clock skew corrected against NTP |
| 1724 | 2026-03-17T04:44:32Z | watcher | ap-south-1 | cancelled | 3950 | config reloaded from disk |
| 1725 | 2026-03-18T04:45:45Z | renderer | eu-west-2 | error | 3987 | no change since the previous sweep |
| 1726 | 2026-03-19T04:46:58Z | scheduler | af-south-1 | retrying | 4024 | backpressure from the upstream shard |
| 1727 | 2026-03-20T04:47:11Z | gateway | us-west-2 | warning | 4061 | DNS lookup retried twice |
| 1728 | 2026-03-21T04:48:24Z | indexer | eu-north-1 | skipped | 4098 | restarted after a failed health check |
| 1729 | 2026-03-22T04:49:37Z | cache | sa-east-1 | ok | 4135 | leader election completed |
| 1730 | 2026-03-23T04:50:50Z | resolver | us-east-1 | pending | 4172 | manual intervention requested by the operator |
| 1731 | 2026-03-24T04:51:03Z | shipper | ap-northeast-3 | cancelled | 4209 | cold start took longer than the budget |
| 1732 | 2026-03-25T04:52:16Z | reaper | ap-south-1 | error | 4246 | certificate rotated |
| 1733 | 2026-03-26T04:53:29Z | notifier | eu-west-2 | retrying | 4283 | queue drained without incident |
| 1734 | 2026-03-27T04:54:42Z | uploader | af-south-1 | warning | 4320 | disk watermark crossed, trimmed oldest segments |
| 1735 | 2026-03-28T04:55:55Z | compactor | us-west-2 | skipped | 4357 | clock skew corrected against NTP |
| 1736 | 2026-03-01T04:56:08Z | watcher | eu-north-1 | ok | 4394 | config reloaded from disk |
| 1737 | 2026-03-02T04:57:21Z | renderer | sa-east-1 | pending | 4431 | no change since the previous sweep |
| 1738 | 2026-03-03T04:58:34Z | scheduler | us-east-1 | cancelled | 4468 | backpressure from the upstream shard |
| 1739 | 2026-03-04T04:59:47Z | gateway | ap-northeast-3 | error | 4505 | DNS lookup retried twice |
| 1740 | 2026-03-05T05:00:00Z | indexer | ap-south-1 | retrying | 4542 | restarted after a failed health check |
| 1741 | 2026-03-06T05:01:13Z | cache | eu-west-2 | warning | 4579 | leader election completed |
| 1742 | 2026-03-07T05:02:26Z | resolver | af-south-1 | skipped | 4616 | manual intervention requested by the operator |
| 1743 | 2026-03-08T05:03:39Z | shipper | us-west-2 | ok | 4653 | cold start took longer than the budget |
| 1744 | 2026-03-09T05:04:52Z | reaper | eu-north-1 | pending | 4690 | certificate rotated |
| 1745 | 2026-03-10T05:05:05Z | notifier | sa-east-1 | cancelled | 4727 | queue drained without incident |
| 1746 | 2026-03-11T05:06:18Z | uploader | us-east-1 | error | 4764 | disk watermark crossed, trimmed oldest segments |
| 1747 | 2026-03-12T05:07:31Z | compactor | ap-northeast-3 | retrying | 4801 | clock skew corrected against NTP |
| 1748 | 2026-03-13T05:08:44Z | watcher | ap-south-1 | warning | 4838 | config reloaded from disk |
| 1749 | 2026-03-14T05:09:57Z | renderer | eu-west-2 | skipped | 4875 | no change since the previous sweep |
| 1750 | 2026-03-15T05:10:10Z | scheduler | af-south-1 | ok | 4912 | backpressure from the upstream shard |
| 1751 | 2026-03-16T05:11:23Z | gateway | us-west-2 | pending | 4949 | DNS lookup retried twice |
| 1752 | 2026-03-17T05:12:36Z | indexer | eu-north-1 | cancelled | 4986 | restarted after a failed health check |
| 1753 | 2026-03-18T05:13:49Z | cache | sa-east-1 | error | 5023 | leader election completed |
| 1754 | 2026-03-19T05:14:02Z | resolver | us-east-1 | retrying | 5060 | manual intervention requested by the operator |
| 1755 | 2026-03-20T05:15:15Z | shipper | ap-northeast-3 | warning | 5097 | cold start took longer than the budget |
| 1756 | 2026-03-21T05:16:28Z | reaper | ap-south-1 | skipped | 5134 | certificate rotated |
| 1757 | 2026-03-22T05:17:41Z | notifier | eu-west-2 | ok | 5171 | queue drained without incident |
| 1758 | 2026-03-23T05:18:54Z | uploader | af-south-1 | pending | 5208 | disk watermark crossed, trimmed oldest segments |
| 1759 | 2026-03-24T05:19:07Z | compactor | us-west-2 | cancelled | 5245 | clock skew corrected against NTP |
| 1760 | 2026-03-25T05:20:20Z | watcher | eu-north-1 | error | 5282 | config reloaded from disk |
| 1761 | 2026-03-26T05:21:33Z | renderer | sa-east-1 | retrying | 5319 | no change since the previous sweep |
| 1762 | 2026-03-27T05:22:46Z | scheduler | us-east-1 | warning | 5356 | backpressure from the upstream shard |
| 1763 | 2026-03-28T05:23:59Z | gateway | ap-northeast-3 | skipped | 5393 | DNS lookup retried twice |
| 1764 | 2026-03-01T05:24:12Z | indexer | ap-south-1 | ok | 5430 | restarted after a failed health check |
| 1765 | 2026-03-02T05:25:25Z | cache | eu-west-2 | pending | 5467 | leader election completed |
| 1766 | 2026-03-03T05:26:38Z | resolver | af-south-1 | cancelled | 5504 | manual intervention requested by the operator |
| 1767 | 2026-03-04T05:27:51Z | shipper | us-west-2 | error | 5541 | cold start took longer than the budget |
| 1768 | 2026-03-05T05:28:04Z | reaper | eu-north-1 | retrying | 5578 | certificate rotated |
| 1769 | 2026-03-06T05:29:17Z | notifier | sa-east-1 | warning | 5615 | queue drained without incident |
| 1770 | 2026-03-07T05:30:30Z | uploader | us-east-1 | skipped | 5652 | disk watermark crossed, trimmed oldest segments |
| 1771 | 2026-03-08T05:31:43Z | compactor | ap-northeast-3 | ok | 5689 | clock skew corrected against NTP |
| 1772 | 2026-03-09T05:32:56Z | watcher | ap-south-1 | pending | 5726 | config reloaded from disk |
| 1773 | 2026-03-10T05:33:09Z | renderer | eu-west-2 | cancelled | 5763 | no change since the previous sweep |
| 1774 | 2026-03-11T05:34:22Z | scheduler | af-south-1 | error | 5800 | backpressure from the upstream shard |
| 1775 | 2026-03-12T05:35:35Z | gateway | us-west-2 | retrying | 5837 | DNS lookup retried twice |
| 1776 | 2026-03-13T05:36:48Z | indexer | eu-north-1 | warning | 5874 | restarted after a failed health check |
| 1777 | 2026-03-14T05:37:01Z | cache | sa-east-1 | skipped | 5911 | leader election completed |
| 1778 | 2026-03-15T05:38:14Z | resolver | us-east-1 | ok | 5948 | manual intervention requested by the operator |
| 1779 | 2026-03-16T05:39:27Z | shipper | ap-northeast-3 | pending | 5985 | cold start took longer than the budget |
| 1780 | 2026-03-17T05:40:40Z | reaper | ap-south-1 | cancelled | 6022 | certificate rotated |
| 1781 | 2026-03-18T05:41:53Z | notifier | eu-west-2 | error | 6059 | queue drained without incident |
| 1782 | 2026-03-19T05:42:06Z | uploader | af-south-1 | retrying | 6096 | disk watermark crossed, trimmed oldest segments |
| 1783 | 2026-03-20T05:43:19Z | compactor | us-west-2 | warning | 6133 | clock skew corrected against NTP |
| 1784 | 2026-03-21T05:44:32Z | watcher | eu-north-1 | skipped | 6170 | config reloaded from disk |
| 1785 | 2026-03-22T05:45:45Z | renderer | sa-east-1 | ok | 6207 | no change since the previous sweep |
| 1786 | 2026-03-23T05:46:58Z | scheduler | us-east-1 | pending | 6244 | backpressure from the upstream shard |
| 1787 | 2026-03-24T05:47:11Z | gateway | ap-northeast-3 | cancelled | 6281 | DNS lookup retried twice |
| 1788 | 2026-03-25T05:48:24Z | indexer | ap-south-1 | error | 6318 | restarted after a failed health check |
| 1789 | 2026-03-26T05:49:37Z | cache | eu-west-2 | retrying | 6355 | leader election completed |
| 1790 | 2026-03-27T05:50:50Z | resolver | af-south-1 | warning | 6392 | manual intervention requested by the operator |
| 1791 | 2026-03-28T05:51:03Z | shipper | us-west-2 | skipped | 6429 | cold start took longer than the budget |
| 1792 | 2026-03-01T05:52:16Z | reaper | eu-north-1 | ok | 6466 | certificate rotated |
| 1793 | 2026-03-02T05:53:29Z | notifier | sa-east-1 | pending | 6503 | queue drained without incident |
| 1794 | 2026-03-03T05:54:42Z | uploader | us-east-1 | cancelled | 6540 | disk watermark crossed, trimmed oldest segments |
| 1795 | 2026-03-04T05:55:55Z | compactor | ap-northeast-3 | error | 6577 | clock skew corrected against NTP |
| 1796 | 2026-03-05T05:56:08Z | watcher | ap-south-1 | retrying | 6614 | config reloaded from disk |
| 1797 | 2026-03-06T05:57:21Z | renderer | eu-west-2 | warning | 6651 | no change since the previous sweep |
| 1798 | 2026-03-07T05:58:34Z | scheduler | af-south-1 | skipped | 6688 | backpressure from the upstream shard |
| 1799 | 2026-03-08T05:59:47Z | gateway | us-west-2 | ok | 6725 | DNS lookup retried twice |
| 1800 | 2026-03-09T06:00:00Z | indexer | eu-north-1 | pending | 6762 | restarted after a failed health check |
| 1801 | 2026-03-10T06:01:13Z | cache | sa-east-1 | cancelled | 6799 | leader election completed |
| 1802 | 2026-03-11T06:02:26Z | resolver | us-east-1 | error | 6836 | manual intervention requested by the operator |
| 1803 | 2026-03-12T06:03:39Z | shipper | ap-northeast-3 | retrying | 6873 | cold start took longer than the budget |
| 1804 | 2026-03-13T06:04:52Z | reaper | ap-south-1 | warning | 6910 | certificate rotated |
| 1805 | 2026-03-14T06:05:05Z | notifier | eu-west-2 | skipped | 6947 | queue drained without incident |
| 1806 | 2026-03-15T06:06:18Z | uploader | af-south-1 | ok | 6984 | disk watermark crossed, trimmed oldest segments |
| 1807 | 2026-03-16T06:07:31Z | compactor | us-west-2 | pending | 7021 | clock skew corrected against NTP |
| 1808 | 2026-03-17T06:08:44Z | watcher | eu-north-1 | cancelled | 7058 | config reloaded from disk |
| 1809 | 2026-03-18T06:09:57Z | renderer | sa-east-1 | error | 7095 | no change since the previous sweep |
| 1810 | 2026-03-19T06:10:10Z | scheduler | us-east-1 | retrying | 7132 | backpressure from the upstream shard |
| 1811 | 2026-03-20T06:11:23Z | gateway | ap-northeast-3 | warning | 7169 | DNS lookup retried twice |
| 1812 | 2026-03-21T06:12:36Z | indexer | ap-south-1 | skipped | 7206 | restarted after a failed health check |
| 1813 | 2026-03-22T06:13:49Z | cache | eu-west-2 | ok | 7243 | leader election completed |
| 1814 | 2026-03-23T06:14:02Z | resolver | af-south-1 | pending | 7280 | manual intervention requested by the operator |
| 1815 | 2026-03-24T06:15:15Z | shipper | us-west-2 | cancelled | 7317 | cold start took longer than the budget |
| 1816 | 2026-03-25T06:16:28Z | reaper | eu-north-1 | error | 7354 | certificate rotated |
| 1817 | 2026-03-26T06:17:41Z | notifier | sa-east-1 | retrying | 7391 | queue drained without incident |
| 1818 | 2026-03-27T06:18:54Z | uploader | us-east-1 | warning | 7428 | disk watermark crossed, trimmed oldest segments |
| 1819 | 2026-03-28T06:19:07Z | compactor | ap-northeast-3 | skipped | 7465 | clock skew corrected against NTP |
| 1820 | 2026-03-01T06:20:20Z | watcher | ap-south-1 | ok | 7502 | config reloaded from disk |
| 1821 | 2026-03-02T06:21:33Z | renderer | eu-west-2 | pending | 7539 | no change since the previous sweep |
| 1822 | 2026-03-03T06:22:46Z | scheduler | af-south-1 | cancelled | 7576 | backpressure from the upstream shard |
| 1823 | 2026-03-04T06:23:59Z | gateway | us-west-2 | error | 7613 | DNS lookup retried twice |
| 1824 | 2026-03-05T06:24:12Z | indexer | eu-north-1 | retrying | 7650 | restarted after a failed health check |
| 1825 | 2026-03-06T06:25:25Z | cache | sa-east-1 | warning | 7687 | leader election completed |
| 1826 | 2026-03-07T06:26:38Z | resolver | us-east-1 | skipped | 7724 | manual intervention requested by the operator |
| 1827 | 2026-03-08T06:27:51Z | shipper | ap-northeast-3 | ok | 7761 | cold start took longer than the budget |
| 1828 | 2026-03-09T06:28:04Z | reaper | ap-south-1 | pending | 7798 | certificate rotated |
| 1829 | 2026-03-10T06:29:17Z | notifier | eu-west-2 | cancelled | 7835 | queue drained without incident |
| 1830 | 2026-03-11T06:30:30Z | uploader | af-south-1 | error | 7872 | disk watermark crossed, trimmed oldest segments |
| 1831 | 2026-03-12T06:31:43Z | compactor | us-west-2 | retrying | 7909 | clock skew corrected against NTP |
| 1832 | 2026-03-13T06:32:56Z | watcher | eu-north-1 | warning | 7946 | config reloaded from disk |
| 1833 | 2026-03-14T06:33:09Z | renderer | sa-east-1 | skipped | 7983 | no change since the previous sweep |
| 1834 | 2026-03-15T06:34:22Z | scheduler | us-east-1 | ok | 8020 | backpressure from the upstream shard |
| 1835 | 2026-03-16T06:35:35Z | gateway | ap-northeast-3 | pending | 8057 | DNS lookup retried twice |
| 1836 | 2026-03-17T06:36:48Z | indexer | ap-south-1 | cancelled | 8094 | restarted after a failed health check |
| 1837 | 2026-03-18T06:37:01Z | cache | eu-west-2 | error | 8131 | leader election completed |
| 1838 | 2026-03-19T06:38:14Z | resolver | af-south-1 | retrying | 8168 | manual intervention requested by the operator |
| 1839 | 2026-03-20T06:39:27Z | shipper | us-west-2 | warning | 8205 | cold start took longer than the budget |
| 1840 | 2026-03-21T06:40:40Z | reaper | eu-north-1 | skipped | 8242 | certificate rotated |
| 1841 | 2026-03-22T06:41:53Z | notifier | sa-east-1 | ok | 8279 | queue drained without incident |
| 1842 | 2026-03-23T06:42:06Z | uploader | us-east-1 | pending | 8316 | disk watermark crossed, trimmed oldest segments |
| 1843 | 2026-03-24T06:43:19Z | compactor | ap-northeast-3 | cancelled | 8353 | clock skew corrected against NTP |
| 1844 | 2026-03-25T06:44:32Z | watcher | ap-south-1 | error | 8390 | config reloaded from disk |
| 1845 | 2026-03-26T06:45:45Z | renderer | eu-west-2 | retrying | 8427 | no change since the previous sweep |
| 1846 | 2026-03-27T06:46:58Z | scheduler | af-south-1 | warning | 8464 | backpressure from the upstream shard |
| 1847 | 2026-03-28T06:47:11Z | gateway | us-west-2 | skipped | 8501 | DNS lookup retried twice |
| 1848 | 2026-03-01T06:48:24Z | indexer | eu-north-1 | ok | 8538 | restarted after a failed health check |
| 1849 | 2026-03-02T06:49:37Z | cache | sa-east-1 | pending | 8575 | leader election completed |
| 1850 | 2026-03-03T06:50:50Z | resolver | us-east-1 | cancelled | 8612 | manual intervention requested by the operator |
| 1851 | 2026-03-04T06:51:03Z | shipper | ap-northeast-3 | error | 8649 | cold start took longer than the budget |
| 1852 | 2026-03-05T06:52:16Z | reaper | ap-south-1 | retrying | 8686 | certificate rotated |
| 1853 | 2026-03-06T06:53:29Z | notifier | eu-west-2 | warning | 8723 | queue drained without incident |
| 1854 | 2026-03-07T06:54:42Z | uploader | af-south-1 | skipped | 8760 | disk watermark crossed, trimmed oldest segments |
| 1855 | 2026-03-08T06:55:55Z | compactor | us-west-2 | ok | 8797 | clock skew corrected against NTP |
| 1856 | 2026-03-09T06:56:08Z | watcher | eu-north-1 | pending | 8834 | config reloaded from disk |
| 1857 | 2026-03-10T06:57:21Z | renderer | sa-east-1 | cancelled | 8871 | no change since the previous sweep |
| 1858 | 2026-03-11T06:58:34Z | scheduler | us-east-1 | error | 8908 | backpressure from the upstream shard |
| 1859 | 2026-03-12T06:59:47Z | gateway | ap-northeast-3 | retrying | 8945 | DNS lookup retried twice |
| 1860 | 2026-03-13T07:00:00Z | indexer | ap-south-1 | warning | 8982 | restarted after a failed health check |
| 1861 | 2026-03-14T07:01:13Z | cache | eu-west-2 | skipped | 9019 | leader election completed |
| 1862 | 2026-03-15T07:02:26Z | resolver | af-south-1 | ok | 9056 | manual intervention requested by the operator |
| 1863 | 2026-03-16T07:03:39Z | shipper | us-west-2 | pending | 9093 | cold start took longer than the budget |
| 1864 | 2026-03-17T07:04:52Z | reaper | eu-north-1 | cancelled | 9130 | certificate rotated |
| 1865 | 2026-03-18T07:05:05Z | notifier | sa-east-1 | error | 9167 | queue drained without incident |
| 1866 | 2026-03-19T07:06:18Z | uploader | us-east-1 | retrying | 9204 | disk watermark crossed, trimmed oldest segments |
| 1867 | 2026-03-20T07:07:31Z | compactor | ap-northeast-3 | warning | 9241 | clock skew corrected against NTP |
| 1868 | 2026-03-21T07:08:44Z | watcher | ap-south-1 | skipped | 9278 | config reloaded from disk |
| 1869 | 2026-03-22T07:09:57Z | renderer | eu-west-2 | ok | 9315 | no change since the previous sweep |
| 1870 | 2026-03-23T07:10:10Z | scheduler | af-south-1 | pending | 9352 | backpressure from the upstream shard |
| 1871 | 2026-03-24T07:11:23Z | gateway | us-west-2 | cancelled | 9389 | DNS lookup retried twice |
| 1872 | 2026-03-25T07:12:36Z | indexer | eu-north-1 | error | 9426 | restarted after a failed health check |
| 1873 | 2026-03-26T07:13:49Z | cache | sa-east-1 | retrying | 9463 | leader election completed |
| 1874 | 2026-03-27T07:14:02Z | resolver | us-east-1 | warning | 9500 | manual intervention requested by the operator |
| 1875 | 2026-03-28T07:15:15Z | shipper | ap-northeast-3 | skipped | 9537 | cold start took longer than the budget |
| 1876 | 2026-03-01T07:16:28Z | reaper | ap-south-1 | ok | 9574 | certificate rotated |
| 1877 | 2026-03-02T07:17:41Z | notifier | eu-west-2 | pending | 9611 | queue drained without incident |
| 1878 | 2026-03-03T07:18:54Z | uploader | af-south-1 | cancelled | 9648 | disk watermark crossed, trimmed oldest segments |
| 1879 | 2026-03-04T07:19:07Z | compactor | us-west-2 | error | 9685 | clock skew corrected against NTP |
| 1880 | 2026-03-05T07:20:20Z | watcher | eu-north-1 | retrying | 9722 | config reloaded from disk |
| 1881 | 2026-03-06T07:21:33Z | renderer | sa-east-1 | warning | 9759 | no change since the previous sweep |
| 1882 | 2026-03-07T07:22:46Z | scheduler | us-east-1 | skipped | 9796 | backpressure from the upstream shard |
| 1883 | 2026-03-08T07:23:59Z | gateway | ap-northeast-3 | ok | 9833 | DNS lookup retried twice |
| 1884 | 2026-03-09T07:24:12Z | indexer | ap-south-1 | pending | 9870 | restarted after a failed health check |
| 1885 | 2026-03-10T07:25:25Z | cache | eu-west-2 | cancelled | 9907 | leader election completed |
| 1886 | 2026-03-11T07:26:38Z | resolver | af-south-1 | error | 9944 | manual intervention requested by the operator |
| 1887 | 2026-03-12T07:27:51Z | shipper | us-west-2 | retrying | 8 | cold start took longer than the budget |
| 1888 | 2026-03-13T07:28:04Z | reaper | eu-north-1 | warning | 45 | certificate rotated |
| 1889 | 2026-03-14T07:29:17Z | notifier | sa-east-1 | skipped | 82 | queue drained without incident |
| 1890 | 2026-03-15T07:30:30Z | uploader | us-east-1 | ok | 119 | disk watermark crossed, trimmed oldest segments |
| 1891 | 2026-03-16T07:31:43Z | compactor | ap-northeast-3 | pending | 156 | clock skew corrected against NTP |
| 1892 | 2026-03-17T07:32:56Z | watcher | ap-south-1 | cancelled | 193 | config reloaded from disk |
| 1893 | 2026-03-18T07:33:09Z | renderer | eu-west-2 | error | 230 | no change since the previous sweep |
| 1894 | 2026-03-19T07:34:22Z | scheduler | af-south-1 | retrying | 267 | backpressure from the upstream shard |
| 1895 | 2026-03-20T07:35:35Z | gateway | us-west-2 | warning | 304 | DNS lookup retried twice |
| 1896 | 2026-03-21T07:36:48Z | indexer | eu-north-1 | skipped | 341 | restarted after a failed health check |
| 1897 | 2026-03-22T07:37:01Z | cache | sa-east-1 | ok | 378 | leader election completed |
| 1898 | 2026-03-23T07:38:14Z | resolver | us-east-1 | pending | 415 | manual intervention requested by the operator |
| 1899 | 2026-03-24T07:39:27Z | shipper | ap-northeast-3 | cancelled | 452 | cold start took longer than the budget |
| 1900 | 2026-03-25T07:40:40Z | reaper | ap-south-1 | error | 489 | certificate rotated |
| 1901 | 2026-03-26T07:41:53Z | notifier | eu-west-2 | retrying | 526 | queue drained without incident |
| 1902 | 2026-03-27T07:42:06Z | uploader | af-south-1 | warning | 563 | disk watermark crossed, trimmed oldest segments |
| 1903 | 2026-03-28T07:43:19Z | compactor | us-west-2 | skipped | 600 | clock skew corrected against NTP |
| 1904 | 2026-03-01T07:44:32Z | watcher | eu-north-1 | ok | 637 | config reloaded from disk |
| 1905 | 2026-03-02T07:45:45Z | renderer | sa-east-1 | pending | 674 | no change since the previous sweep |
| 1906 | 2026-03-03T07:46:58Z | scheduler | us-east-1 | cancelled | 711 | backpressure from the upstream shard |
| 1907 | 2026-03-04T07:47:11Z | gateway | ap-northeast-3 | error | 748 | DNS lookup retried twice |
| 1908 | 2026-03-05T07:48:24Z | indexer | ap-south-1 | retrying | 785 | restarted after a failed health check |
| 1909 | 2026-03-06T07:49:37Z | cache | eu-west-2 | warning | 822 | leader election completed |
| 1910 | 2026-03-07T07:50:50Z | resolver | af-south-1 | skipped | 859 | manual intervention requested by the operator |
| 1911 | 2026-03-08T07:51:03Z | shipper | us-west-2 | ok | 896 | cold start took longer than the budget |
| 1912 | 2026-03-09T07:52:16Z | reaper | eu-north-1 | pending | 933 | certificate rotated |
| 1913 | 2026-03-10T07:53:29Z | notifier | sa-east-1 | cancelled | 970 | queue drained without incident |
| 1914 | 2026-03-11T07:54:42Z | uploader | us-east-1 | error | 1007 | disk watermark crossed, trimmed oldest segments |
| 1915 | 2026-03-12T07:55:55Z | compactor | ap-northeast-3 | retrying | 1044 | clock skew corrected against NTP |
| 1916 | 2026-03-13T07:56:08Z | watcher | ap-south-1 | warning | 1081 | config reloaded from disk |
| 1917 | 2026-03-14T07:57:21Z | renderer | eu-west-2 | skipped | 1118 | no change since the previous sweep |
| 1918 | 2026-03-15T07:58:34Z | scheduler | af-south-1 | ok | 1155 | backpressure from the upstream shard |
| 1919 | 2026-03-16T07:59:47Z | gateway | us-west-2 | pending | 1192 | DNS lookup retried twice |
| 1920 | 2026-03-17T08:00:00Z | indexer | eu-north-1 | cancelled | 1229 | restarted after a failed health check |
| 1921 | 2026-03-18T08:01:13Z | cache | sa-east-1 | error | 1266 | leader election completed |
| 1922 | 2026-03-19T08:02:26Z | resolver | us-east-1 | retrying | 1303 | manual intervention requested by the operator |
| 1923 | 2026-03-20T08:03:39Z | shipper | ap-northeast-3 | warning | 1340 | cold start took longer than the budget |
| 1924 | 2026-03-21T08:04:52Z | reaper | ap-south-1 | skipped | 1377 | certificate rotated |
| 1925 | 2026-03-22T08:05:05Z | notifier | eu-west-2 | ok | 1414 | queue drained without incident |
| 1926 | 2026-03-23T08:06:18Z | uploader | af-south-1 | pending | 1451 | disk watermark crossed, trimmed oldest segments |
| 1927 | 2026-03-24T08:07:31Z | compactor | us-west-2 | cancelled | 1488 | clock skew corrected against NTP |
| 1928 | 2026-03-25T08:08:44Z | watcher | eu-north-1 | error | 1525 | config reloaded from disk |
| 1929 | 2026-03-26T08:09:57Z | renderer | sa-east-1 | retrying | 1562 | no change since the previous sweep |
| 1930 | 2026-03-27T08:10:10Z | scheduler | us-east-1 | warning | 1599 | backpressure from the upstream shard |
| 1931 | 2026-03-28T08:11:23Z | gateway | ap-northeast-3 | skipped | 1636 | DNS lookup retried twice |
| 1932 | 2026-03-01T08:12:36Z | indexer | ap-south-1 | ok | 1673 | restarted after a failed health check |
| 1933 | 2026-03-02T08:13:49Z | cache | eu-west-2 | pending | 1710 | leader election completed |
| 1934 | 2026-03-03T08:14:02Z | resolver | af-south-1 | cancelled | 1747 | manual intervention requested by the operator |
| 1935 | 2026-03-04T08:15:15Z | shipper | us-west-2 | error | 1784 | cold start took longer than the budget |
| 1936 | 2026-03-05T08:16:28Z | reaper | eu-north-1 | retrying | 1821 | certificate rotated |
| 1937 | 2026-03-06T08:17:41Z | notifier | sa-east-1 | warning | 1858 | queue drained without incident |
| 1938 | 2026-03-07T08:18:54Z | uploader | us-east-1 | skipped | 1895 | disk watermark crossed, trimmed oldest segments |
| 1939 | 2026-03-08T08:19:07Z | compactor | ap-northeast-3 | ok | 1932 | clock skew corrected against NTP |
| 1940 | 2026-03-09T08:20:20Z | watcher | ap-south-1 | pending | 1969 | config reloaded from disk |
| 1941 | 2026-03-10T08:21:33Z | renderer | eu-west-2 | cancelled | 2006 | no change since the previous sweep |
| 1942 | 2026-03-11T08:22:46Z | scheduler | af-south-1 | error | 2043 | backpressure from the upstream shard |
| 1943 | 2026-03-12T08:23:59Z | gateway | us-west-2 | retrying | 2080 | DNS lookup retried twice |
| 1944 | 2026-03-13T08:24:12Z | indexer | eu-north-1 | warning | 2117 | restarted after a failed health check |
| 1945 | 2026-03-14T08:25:25Z | cache | sa-east-1 | skipped | 2154 | leader election completed |
| 1946 | 2026-03-15T08:26:38Z | resolver | us-east-1 | ok | 2191 | manual intervention requested by the operator |
| 1947 | 2026-03-16T08:27:51Z | shipper | ap-northeast-3 | pending | 2228 | cold start took longer than the budget |
| 1948 | 2026-03-17T08:28:04Z | reaper | ap-south-1 | cancelled | 2265 | certificate rotated |
| 1949 | 2026-03-18T08:29:17Z | notifier | eu-west-2 | error | 2302 | queue drained without incident |
| 1950 | 2026-03-19T08:30:30Z | uploader | af-south-1 | retrying | 2339 | disk watermark crossed, trimmed oldest segments |
| 1951 | 2026-03-20T08:31:43Z | compactor | us-west-2 | warning | 2376 | clock skew corrected against NTP |
| 1952 | 2026-03-21T08:32:56Z | watcher | eu-north-1 | skipped | 2413 | config reloaded from disk |
| 1953 | 2026-03-22T08:33:09Z | renderer | sa-east-1 | ok | 2450 | no change since the previous sweep |
| 1954 | 2026-03-23T08:34:22Z | scheduler | us-east-1 | pending | 2487 | backpressure from the upstream shard |
| 1955 | 2026-03-24T08:35:35Z | gateway | ap-northeast-3 | cancelled | 2524 | DNS lookup retried twice |
| 1956 | 2026-03-25T08:36:48Z | indexer | ap-south-1 | error | 2561 | restarted after a failed health check |
| 1957 | 2026-03-26T08:37:01Z | cache | eu-west-2 | retrying | 2598 | leader election completed |
| 1958 | 2026-03-27T08:38:14Z | resolver | af-south-1 | warning | 2635 | manual intervention requested by the operator |
| 1959 | 2026-03-28T08:39:27Z | shipper | us-west-2 | skipped | 2672 | cold start took longer than the budget |
| 1960 | 2026-03-01T08:40:40Z | reaper | eu-north-1 | ok | 2709 | certificate rotated |
| 1961 | 2026-03-02T08:41:53Z | notifier | sa-east-1 | pending | 2746 | queue drained without incident |
| 1962 | 2026-03-03T08:42:06Z | uploader | us-east-1 | cancelled | 2783 | disk watermark crossed, trimmed oldest segments |
| 1963 | 2026-03-04T08:43:19Z | compactor | ap-northeast-3 | error | 2820 | clock skew corrected against NTP |
| 1964 | 2026-03-05T08:44:32Z | watcher | ap-south-1 | retrying | 2857 | config reloaded from disk |
| 1965 | 2026-03-06T08:45:45Z | renderer | eu-west-2 | warning | 2894 | no change since the previous sweep |
| 1966 | 2026-03-07T08:46:58Z | scheduler | af-south-1 | skipped | 2931 | backpressure from the upstream shard |
| 1967 | 2026-03-08T08:47:11Z | gateway | us-west-2 | ok | 2968 | DNS lookup retried twice |
| 1968 | 2026-03-09T08:48:24Z | indexer | eu-north-1 | pending | 3005 | restarted after a failed health check |
| 1969 | 2026-03-10T08:49:37Z | cache | sa-east-1 | cancelled | 3042 | leader election completed |
| 1970 | 2026-03-11T08:50:50Z | resolver | us-east-1 | error | 3079 | manual intervention requested by the operator |
| 1971 | 2026-03-12T08:51:03Z | shipper | ap-northeast-3 | retrying | 3116 | cold start took longer than the budget |
| 1972 | 2026-03-13T08:52:16Z | reaper | ap-south-1 | warning | 3153 | certificate rotated |
| 1973 | 2026-03-14T08:53:29Z | notifier | eu-west-2 | skipped | 3190 | queue drained without incident |
| 1974 | 2026-03-15T08:54:42Z | uploader | af-south-1 | ok | 3227 | disk watermark crossed, trimmed oldest segments |
| 1975 | 2026-03-16T08:55:55Z | compactor | us-west-2 | pending | 3264 | clock skew corrected against NTP |
| 1976 | 2026-03-17T08:56:08Z | watcher | eu-north-1 | cancelled | 3301 | config reloaded from disk |
| 1977 | 2026-03-18T08:57:21Z | renderer | sa-east-1 | error | 3338 | no change since the previous sweep |
| 1978 | 2026-03-19T08:58:34Z | scheduler | us-east-1 | retrying | 3375 | backpressure from the upstream shard |
| 1979 | 2026-03-20T08:59:47Z | gateway | ap-northeast-3 | warning | 3412 | DNS lookup retried twice |
| 1980 | 2026-03-21T09:00:00Z | indexer | ap-south-1 | skipped | 3449 | restarted after a failed health check |
| 1981 | 2026-03-22T09:01:13Z | cache | eu-west-2 | ok | 3486 | leader election completed |
| 1982 | 2026-03-23T09:02:26Z | resolver | af-south-1 | pending | 3523 | manual intervention requested by the operator |
| 1983 | 2026-03-24T09:03:39Z | shipper | us-west-2 | cancelled | 3560 | cold start took longer than the budget |
| 1984 | 2026-03-25T09:04:52Z | reaper | eu-north-1 | error | 3597 | certificate rotated |
| 1985 | 2026-03-26T09:05:05Z | notifier | sa-east-1 | retrying | 3634 | queue drained without incident |
| 1986 | 2026-03-27T09:06:18Z | uploader | us-east-1 | warning | 3671 | disk watermark crossed, trimmed oldest segments |
| 1987 | 2026-03-28T09:07:31Z | compactor | ap-northeast-3 | skipped | 3708 | clock skew corrected against NTP |
| 1988 | 2026-03-01T09:08:44Z | watcher | ap-south-1 | ok | 3745 | config reloaded from disk |
| 1989 | 2026-03-02T09:09:57Z | renderer | eu-west-2 | pending | 3782 | no change since the previous sweep |
| 1990 | 2026-03-03T09:10:10Z | scheduler | af-south-1 | cancelled | 3819 | backpressure from the upstream shard |
| 1991 | 2026-03-04T09:11:23Z | gateway | us-west-2 | error | 3856 | DNS lookup retried twice |
| 1992 | 2026-03-05T09:12:36Z | indexer | eu-north-1 | retrying | 3893 | restarted after a failed health check |
| 1993 | 2026-03-06T09:13:49Z | cache | sa-east-1 | warning | 3930 | leader election completed |
| 1994 | 2026-03-07T09:14:02Z | resolver | us-east-1 | skipped | 3967 | manual intervention requested by the operator |
| 1995 | 2026-03-08T09:15:15Z | shipper | ap-northeast-3 | ok | 4004 | cold start took longer than the budget |
| 1996 | 2026-03-09T09:16:28Z | reaper | ap-south-1 | pending | 4041 | certificate rotated |
| 1997 | 2026-03-10T09:17:41Z | notifier | eu-west-2 | cancelled | 4078 | queue drained without incident |
| 1998 | 2026-03-11T09:18:54Z | uploader | af-south-1 | error | 4115 | disk watermark crossed, trimmed oldest segments |
| 1999 | 2026-03-12T09:19:07Z | compactor | us-west-2 | retrying | 4152 | clock skew corrected against NTP |
| 2000 | 2026-03-13T09:20:20Z | watcher | eu-north-1 | warning | 4189 | config reloaded from disk |

End of the 2,000-row table. The row above should read `| 2000 |`.

---

## 5. Wide cells

One cell in each table is far wider than its neighbours. The renderer has to
pick column widths anyway. Acceptable outcomes: the wide cell wraps, or the
table scrolls horizontally. Not acceptable: text clipped with no scrollbar,
cells overlapping, or the wide cell pushing the page layout sideways.

### 5.1 A very long unbroken string

420 characters with no spaces, so there is nowhere to wrap.

| Short | Unbroken | Short |
| --- | --- | --- |
| a | ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkr | b |
| c | fine | d |

300 identical characters, which some layout engines treat differently:

| Label | Value |
| --- | --- |
| repeated | AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA |
| normal | a normal value |

### 5.2 A long URL

Once as plain text, once as an autolink, once as a labelled link.

| Form | Cell |
| --- | --- |
| plain text | https://example.com/a/very/deep/path/segment/that/keeps/going/and/going/and/going?query=1&another=2&third=3&fourth=4&fifth=5&sixth=6&seventh=7&eighth=8#and-a-fragment-on-the-end-as-well |
| autolink | <https://example.com/a/very/deep/path/segment/that/keeps/going/and/going/and/going?query=1&another=2&third=3&fourth=4&fifth=5&sixth=6&seventh=7&eighth=8#and-a-fragment-on-the-end-as-well> |
| labelled | [a short label](https://example.com/a/very/deep/path/segment/that/keeps/going/and/going/and/going?query=1&another=2&third=3&fourth=4&fifth=5&sixth=6&seventh=7&eighth=8#and-a-fragment-on-the-end-as-well) |

### 5.3 A long code span

Code spans do not wrap in most preview stylesheets, so this is the most
likely place to see overflow.

| Name | Command |
| --- | --- |
| short | `ls` |
| long | `token_01 token_02 token_03 token_04 token_05 token_06 token_07 token_08 token_09 token_10 token_11 token_12 token_13 token_14 token_15 token_16 token_17 token_18 token_19 token_20 token_21 token_22 token_23 token_24 token_25 token_26 token_27 token_28 token_29 token_30 token_31 token_32 token_33 token_34 token_35 token_36 token_37 token_38 token_39 token_40` |
| medium | `git log --oneline --graph --decorate --all` |

### 5.4 Several hundred words of prose in one cell

Roughly 320 words in a single cell, next to a two-character cell.

| ID | Prose |
| ---: | :--- |
| 1 | The quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be. |
| 2 | short |
| 3 | The quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be. |

### 5.5 All of the above in one table

| Kind | Payload | Note |
| :--- | :--- | ---: |
| unbroken | ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkry5cjqx4bipw3ahov29gnu18fmt07elsz6dkr | 420 chars |
| url | https://example.com/a/very/deep/path/segment/that/keeps/going/and/going/and/going?query=1&another=2&third=3&fourth=4&fifth=5&sixth=6&seventh=7&eighth=8#and-a-fragment-on-the-end-as-well | autolinkable |
| code | `token_01 token_02 token_03 token_04 token_05 token_06 token_07 token_08 token_09 token_10 token_11 token_12 token_13 token_14 token_15 token_16 token_17 token_18 token_19 token_20 token_21 token_22 token_23 token_24 token_25 token_26 token_27 token_28 token_29 token_30 token_31 token_32 token_33 token_34 token_35 token_36 token_37 token_38 token_39 token_40` | 40 tokens |
| prose | The quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be and whether the text should wrap inside the cell or force the table to grow past the edge of the pane which is precisely the behaviour under test here so read carefully and compare the two panes before filing anything the quick brown fox jumps over a lazy dog while the renderer decides how wide this column ought to be. | ~320 words |
| tiny | x | 1 char |

---

## 6. Uneven / ragged tables

**Everything in this section is intentionally malformed.** None of it is a
bug report waiting to happen; the point is that Fence must handle it the way
GFM says and must not crash, hang, or blank the preview.

What the GFM spec says:

- The delimiter row **must** have exactly the same number of cells as the
  header row. If it does not, the whole construct is **not a table** and is
  parsed as an ordinary paragraph.
- A body row with **fewer** cells than the header is padded with empty cells.
- A body row with **more** cells than the header has the excess cells
  **discarded**.
- Empty cells are legal and render as empty `<td>` elements.

### 6.1 Rows with fewer cells than the header

Rows 2 and 3 should be padded on the right with empty cells.

| A | B | C | D |
| --- | --- | --- | --- |
| 1 | 2 | 3 | 4 |
| 1 | 2 | 3 |
| 1 |
| 1 | 2 | 3 | 4 |

### 6.2 Rows with more cells than the header

The extra cells in rows 2 and 3 should be dropped, not spill into a new
column and not push the table wider.

| A | B |
| --- | --- |
| 1 | 2 |
| 1 | 2 | 3 | 4 |
| 1 | 2 | this cell should not appear | nor this one | nor this |
| 1 | 2 |

### 6.3 Both at once

| A | B | C |
| --- | --- | --- |
| 1 | 2 | 3 |
| 1 |
| 1 | 2 | 3 | 4 | 5 |
| | | |
| 1 | 2 | 3 |

### 6.4 A single empty cell

The middle cell of row 2 is empty. It should render as an empty cell, not
collapse the row.

| Left | Middle | Right |
| --- | --- | --- |
| a | b | c |
| a | | c |
| a | b | c |

### 6.5 A row of entirely empty cells

Row 2 is empty in every column. The row should still exist and occupy height.

| One | Two | Three |
| --- | --- | --- |
| filled | filled | filled |
| | | |
| filled | filled | filled |

Two consecutive empty rows:

| One | Two |
| --- | --- |
| a | b |
| | |
| | |
| c | d |

### 6.6 Delimiter row count does not match the header

Per the spec these are **not tables**. Each block should render as a plain
paragraph with visible pipe characters.

Three header cells, two delimiter cells:

| A | B | C |
| --- | --- |
| 1 | 2 | 3 |

Two header cells, three delimiter cells:

| A | B |
| --- | --- | --- |
| 1 | 2 |

One header cell, five delimiter cells:

| A |
| --- | --- | --- | --- | --- |
| 1 |

### 6.7 Delimiter row that is not a delimiter row

Also not tables. The second line fails the delimiter grammar, so the block is
a paragraph.

| A | B |
| --- | -x- |
| 1 | 2 |

| A | B |
| :--:- | --- |
| 1 | 2 |

| A | B |
| : | : |
| 1 | 2 |

---

## 7. Inline content in cells

Inline markup works inside table cells; block markup does not. Every cell
below should render its markup, and the pipe-escaping cases should show a
literal `|` without splitting the cell.

### 7.1 Emphasis and code

| What | Cell | Expected |
| :--- | :--- | :--- |
| bold | **bold text** | heavy weight |
| italic | *italic text* | slanted |
| bold italic | ***both at once*** | heavy and slanted |
| strikethrough | ~~struck out~~ | line through it |
| inline code | `const x = 1;` | monospace, tinted background |
| code plus bold | **`bold code`** | both, no literal backticks |
| nested | *outer **inner** outer* | italic with a bold word inside |
| subscript-ish | H~2~O | plain text unless subscript is enabled |

### 7.2 Links, autolinks and images

| What | Cell |
| :--- | :--- |
| inline link | [Fence on GitHub](https://github.com/HelgeSverre/fence) |
| reference link | [reference style][fence-ref] |
| autolink | <https://example.com/autolinked> |
| bare URL | https://example.com/bare |
| email autolink | <someone@example.com> |
| link with title | [hover me](https://example.com "a title attribute") |
| image | ![a tiny inline image](../build/icons/icon.png) |
| linked image | [![linked image](../build/icons/icon.png)](https://example.com) |
| broken image | ![missing file](./definitely-not-here.png) |

[fence-ref]: https://github.com/HelgeSverre/fence

### 7.3 Footnote references

| Claim | Source |
| :--- | :--- |
| Tables are a GFM extension | see the spec[^spec] |
| Delimiter rows must match the header | also the spec[^spec] |
| This one has its own note | a second footnote[^other] |

[^spec]: GitHub Flavored Markdown, section 4.10, "Tables (extension)".
[^other]: A second footnote, to check that two references in one table both
    resolve and link to distinct targets.

### 7.4 Line breaks inside cells

A cell cannot contain a real newline, so `<br>` is the only way to break a
line. The backslash and two-space forms do not work here.

| Method | Cell |
| :--- | :--- |
| `<br>` | first line<br>second line<br>third line |
| `<br/>` | first line<br/>second line |
| two spaces | first line  second line (should stay on one line) |
| backslash | first line\ second line (should stay on one line) |

### 7.5 Escaped and literal pipes

| Case | Cell | Expected |
| :--- | :--- | :--- |
| escaped pipe | a \| b | one cell reading `a | b` |
| two escaped pipes | a \| b \| c | one cell, two visible pipes |
| pipe in a code span | `a \| b` | code span containing a pipe |
| pipe in code, unescaped | `a | b` | GFM splits this first — the cell breaks |
| escaped backslash then pipe | a \\\| b | a backslash, then a pipe |
| pipe in a link label | [a \| b](https://example.com) | link text with a pipe |

The fourth row is the famous gotcha: GFM splits cells on `|` **before**
parsing inline code, so an unescaped pipe inside backticks still ends the
cell. It is here on purpose.

### 7.6 HTML entities and raw HTML

| Kind | Cell | Expected |
| :--- | :--- | :--- |
| named entity | &amp; &lt; &gt; &quot; &nbsp; | `& < > " ` and a hard space |
| numeric entity | &#65; &#x42; &#8212; | `A`, `B`, an em dash |
| pipe entity | &#124; | a literal pipe, not a cell break |
| raw span | <span style="color: crimson">red text</span> | red, if raw HTML is allowed |
| raw code | <code>html code element</code> | monospace |
| raw bold | <strong>strong</strong> and <em>em</em> | heavy and slanted |
| script | <script>alert(1)</script> | must **not** execute |

### 7.7 Cells that look like other Markdown

| Kind | Cell | Expected |
| :--- | :--- | :--- |
| looks like a delimiter row | --- | a literal `---`, not a rule |
| looks like an aligned delimiter | :---: | literal text |
| looks like a heading | # not a heading | literal `#` |
| looks like a list | - not a list item | literal dash |
| looks like a quote | > not a quote | literal `>` |
| looks like a fence | ``` | literal backticks |
| looks like a task | - [ ] not a checkbox | literal brackets |
| looks like frontmatter | --- title: x --- | literal text |

### 7.8 A whole row that looks like a delimiter row

The second body row is `| --- | --- |` in the middle of the table. It should
render as a normal row containing three dashes per cell, because only the
row directly after the header is a delimiter row.

| A | B |
| --- | --- |
| 1 | 2 |
| --- | --- |
| 3 | 4 |

---

## 8. Emoji and multibyte content

This is the section that matters most for Fence. The editor measures one
monospace cell and lays out every glyph on that grid, so any character that
is not exactly one cell wide is a candidate for column drift. Check the
editor pane and the preview pane separately — they use different fonts and
can fail independently.

### 8.1 Single-codepoint emoji

| Emoji | Name | Codepoint |
| :---: | :--- | ---: |
| 😀 | grinning face | U+1F600 |
| 🎉 | party popper | U+1F389 |
| 🐙 | octopus | U+1F419 |
| ⚠ | warning sign (text presentation) | U+26A0 |
| ⚠️ | warning sign (emoji presentation) | U+26A0 U+FE0F |
| ☕ | hot beverage | U+2615 |
| ✅ | check mark button | U+2705 |
| ❌ | cross mark | U+274C |
| ♻️ | recycling symbol | U+267B U+FE0F |
| 🅰️ | A button | U+1F170 U+FE0F |

### 8.2 ZWJ sequences and skin tones

A ZWJ sequence that renders as several separate glyphs means the font or the
shaper lost the joiner. A skin tone that renders as a separate colour swatch
means the modifier was split off.

| Sequence | Description | Parts |
| :---: | :--- | ---: |
| 👨‍👩‍👧‍👦 | family: man, woman, girl, boy | 7 codepoints |
| 👩‍👩‍👦 | family: woman, woman, boy | 5 codepoints |
| 👩‍💻 | woman technologist | 3 codepoints |
| 👨🏿‍🚀 | man astronaut, dark skin tone | 5 codepoints |
| 🧑🏽‍🍳 | cook, medium skin tone | 5 codepoints |
| 👋🏻 | waving hand, light skin tone | 2 codepoints |
| 👋🏾 | waving hand, medium-dark skin tone | 2 codepoints |
| 🏳️‍🌈 | rainbow flag | 4 codepoints |
| 🏴‍☠️ | pirate flag | 4 codepoints |
| 🇳🇴 | flag of Norway | 2 regional indicators |
| 🇯🇵 | flag of Japan | 2 regional indicators |
| 🏴󠁧󠁢󠁳󠁣󠁴󠁿 | flag of Scotland | 7 codepoints, tag sequence |
| 🧑‍🤝‍🧑 | people holding hands | 5 codepoints |
| ❤️‍🔥 | heart on fire | 4 codepoints |

### 8.3 CJK

CJK ideographs are double-width in a monospace grid. A column of them should
be exactly twice as wide as the same count of Latin letters.

| Language | Sample | Latin |
| :--- | :--- | :--- |
| Chinese (simplified) | 这是一个表格单元格 | this is a table cell |
| Chinese (traditional) | 這是一個表格儲存格 | this is a table cell |
| Japanese (kanji) | 表計算の見出し行 | spreadsheet header row |
| Japanese (hiragana) | これはひょうのセルです | this is a table cell |
| Japanese (katakana) | マークダウンエディタ | markdown editor |
| Japanese (mixed) | 日本語のテキストが入ります | Japanese text goes here |
| Korean (hangul) | 이것은 표 셀입니다 | this is a table cell |
| Korean (hanja) | 韓國語 混用 表記 | mixed hanja notation |
| Half-width katakana | ﾊﾝｶｸｶﾀｶﾅ | half-width katakana |

### 8.4 Combining diacritics: precomposed vs decomposed

Each row shows the same visual text twice. The precomposed form is one
codepoint per letter; the decomposed form is a base letter plus a combining
mark. They should look identical and occupy the same width. In the editor,
walking the caret across the decomposed form should not leave the mark
stranded on the wrong letter.

| Text | Precomposed (NFC) | Decomposed (NFD) | Marks |
| :--- | :--- | :--- | ---: |
| e acute | café | café | 1 |
| a ring | Åland | Åland | 1 |
| n tilde | mañana | mañana | 1 |
| u umlaut | Müller | Müller | 1 |
| Vietnamese | Tiếng Việt | Tiếng Việt | 4 |
| Norwegian | blåbærsyltetøy | blåbærsyltetøy | 1 |
| Greek | ἄνθρωπος | ἄνθρωπος | 2 |
| Czech | Dvořák příliš | Dvořák příliš | 5 |
| Polish | zażółć gęślą jaźń | zażółć gęślą jaźń | 8 |
| stacked marks | q̣̇ (dot above, dot below) | q̣̇ (order swapped) | 2 |
| many marks | é̂̃̈̊ | e plus five marks | 5 |
| mark on emoji | 😀́ | emoji plus acute | 1 |

### 8.5 Right-to-left text

RTL inside an LTR table is where bidi reordering shows up. The cell borders
must stay put; only the text inside a cell may be reordered.

| Language | Sample | Translation |
| :--- | :--- | :--- |
| Arabic | مرحبا بالعالم | hello world |
| Arabic (longer) | هذه خلية في جدول ماركداون | this is a cell in a Markdown table |
| Hebrew | שלום עולם | hello world |
| Hebrew (longer) | זהו תא בטבלת מארקדאון | this is a cell in a Markdown table |
| Persian | سلام دنیا | hello world |
| Mixed LTR/RTL | the word مرحبا sits inside English | bidi run in the middle |
| RTL with digits | العدد 12345 هنا | digits inside RTL text |
| RTL with punctuation | مرحبا، كيف حالك؟ | comma and question mark are mirrored |

### 8.6 Full-width Latin forms

Full-width forms are double-width even though they look like ASCII.

| Half-width | Full-width | Note |
| :--- | :--- | :--- |
| ABCDEFG | ＡＢＣＤＥＦＧ | letters |
| abcdefg | ａｂｃｄｅｆｇ | lowercase |
| 0123456789 | ０１２３４５６７８９ | digits |
| !@#$%^&*() | ！＠＃＄％＾＆＊（） | punctuation |
| Fence editor | Ｆｅｎｃｅ　ｅｄｉｔｏｒ | including the ideographic space |

### 8.7 Everything in one row

| Kind | Mixed cell |
| :--- | :--- |
| all of it | ASCII 日本語 مرحبا 😀 café Ａ 한국어 👨‍👩‍👧‍👦 עברית ｆｕｌｌ |
| all of it again | 🎉 中文 עברית ＡＢＣ mañana 🧑🏽‍🍳 한국어 العربية plain |
| padded | a 日 م 😀 é Ａ 한 👋🏾 ע ｆ z |

Now the same mixture spread across a table so each kind gets its own column:

| Latin | CJK | RTL | Emoji | Combining | Full-width |
| :--- | :--- | :--- | :---: | :--- | :--- |
| one | 一 | واحد | 1️⃣ | á | １ |
| two | 二 | اثنان | 2️⃣ | é | ２ |
| three | 三 | ثلاثة | 3️⃣ | í | ３ |
| four | 四 | أربعة | 4️⃣ | ó | ４ |
| five | 五 | خمسة | 5️⃣ | ú | ５ |
| longer word here | 五つの文字列 | نص أطول قليلا | 🎉🎊🎈 | ẽẽẽẽẽ | ｌｏｎｇｅｒ |

### 8.8 Deliberately aligned tables — column drift detector

Every cell in the tables below is padded so that, in a correct monospace
grid, all the `|` characters form straight vertical lines. **Read these in
the editor pane, not just the preview.** If a pipe steps left or right, the
editor's width model disagrees with the font: emoji counted as one cell
instead of two, a combining mark counted as a character, a ZWJ sequence
counted as its parts.

Baseline — pure ASCII, six columns of four cells each. These pipes must be
perfectly straight or nothing below means anything:

| aaaa | bbbb | cccc | dddd | eeee | ffff |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 0000 | 1111 | 2222 | 3333 | 4444 | 5555 |
| abcd | efgh | ijkl | mnop | qrst | uvwx |
| .... | ,,,, | :::: | ;;;; | !!!! | ???? |
| WWWW | MMMM | iiii | llll | 0000 | OOOO |

Emoji grid — two emoji per cell, each emoji intended as two cells wide, so
every cell is four cells wide like the baseline above:

| aaaa | bbbb | cccc | dddd |
| ---- | ---- | ---- | ---- |
| 😀😀 | 🎉🎉 | 🐙🐙 | ☕☕ |
| 🍕🍕 | 🚀🚀 | 🌍🌍 | 🔥🔥 |
| ✅✅ | ❌❌ | ⭐⭐ | 💡💡 |
| 🧊🧊 | 🥑🥑 | 🦊🦊 | 🐈🐈 |

CJK grid — two ideographs per cell, same intended width:

| aaaa | bbbb | cccc | dddd |
| ---- | ---- | ---- | ---- |
| 日本 | 中国 | 韓国 | 台湾 |
| 東京 | 北京 | 首爾 | 台北 |
| 春夏 | 秋冬 | 朝昼 | 夕夜 |
| 一二 | 三四 | 五六 | 七八 |

Mixed grid — every row is intended to be the same total width, using
different kinds of character to get there:

| four | four | four | four |
| ---- | ---- | ---- | ---- |
| abcd | 日本 | 😀😀 | ＡＢ |
| 日本 | 😀😀 | ＡＢ | abcd |
| 😀😀 | ＡＢ | abcd | 日本 |
| ＡＢ | abcd | 日本 | 😀😀 |
| 한국 | العر | éééé | ﾊﾝｶｸ |

Combining-mark grid — the left column is precomposed, the right decomposed.
Both are four visible characters and should occupy four cells:

| nfc_ | nfd_ | nfc_ | nfd_ |
| ---- | ---- | ---- | ---- |
| áéíó | áéíó | àèìò | àèìò |
| äëïö | äëïö | âêîô | âêîô |
| ãñõü | ãñõü | åçñø | åçñø |

ZWJ grid — one family emoji per cell. A cell that suddenly becomes eight
columns wide is a shaper or measurement failure:

| zwj_ | zwj_ | zwj_ | zwj_ |
| ---- | ---- | ---- | ---- |
| 👨‍👩‍👧‍👦 x | 👩‍👩‍👦 xx | 👩‍💻 xxx | 👋🏾 xxx |
| 🏳️‍🌈 xx | 🏴‍☠️ xx | 🇳🇴 xxx | 🇯🇵 xxx |
| 🧑🏽‍🍳 x | 👨🏿‍🚀 x | ❤️‍🔥 xx | 🧑‍🤝‍🧑 x |

Ruler — count the columns against this row before deciding anything above is
broken:

| ruler |
| ----- |
| `0123456789012345678901234567890123456789` |
| `|....|....|....|....|....|....|....|....` |

---

## 9. Nested and adjacent structures

Tables next to, or inside, other blocks. Each one should stay a table, and
the surrounding block should keep its own formatting.

### 9.1 A table inside a list item

- First item, plain text.
- Second item, with a table indented under it:

  | Key | Value |
  | --- | --- |
  | indent | two spaces |
  | parent | a list item |

- Third item, after the table. The bullet should still line up with the
  first two.

Ordered list, table at the second level:

1. Outer item.
   1. Inner item with a table:

      | Depth | Marker |
      | ---: | :--- |
      | 1 | `1.` |
      | 2 | `1.` |

   2. Inner item after the table.
2. Outer item after the table.

Task list with a table inside a checked item:

- [x] Done, and here is the evidence:

  | Check | Result |
  | :--- | :---: |
  | unit tests | pass |
  | e2e tests | pass |

- [ ] Not done yet.

### 9.2 A table inside a blockquote

> A quoted paragraph, then a quoted table:
>
> | Quoted | Table |
> | --- | --- |
> | still | a table |
> | with | a quote bar |
>
> And a quoted paragraph after it.

Nested blockquote, two levels deep:

> Outer quote.
>
> > Inner quote with its own table:
> >
> > | Level | Bars |
> > | ---: | :--- |
> > | 1 | `>` |
> > | 2 | `> >` |

### 9.3 Two tables separated by only a blank line

These must render as two separate tables, not one merged table with a
stray row in the middle.

| First | Table |
| --- | --- |
| a | b |
| c | d |

| Second | Table |
| --- | --- |
| e | f |
| g | h |

Two tables with *different* column counts, still only a blank line apart:

| One |
| --- |
| x |

| One | Two | Three |
| --- | --- | --- |
| x | y | z |

### 9.4 A table immediately after a heading

#### No paragraph between the heading and the table

| Adjacent | To a heading |
| --- | --- |
| no | blank paragraph above |

### 9.5 A table immediately before a fenced code block

| Adjacent | To a fence |
| --- | --- |
| the fence | starts on the next line |

```elm
view : Model -> Html Msg
view model =
    table [] (viewHeader model :: List.map viewRow model.rows)
```

And a table immediately after the closing fence, with one blank line:

| Adjacent | After a fence |
| --- | --- |
| the fence | closed on the line above |

### 9.6 A table inside a `<details>` element

<details>
<summary>Click to expand a table</summary>

| Hidden | Until expanded |
| --- | --- |
| the blank line | after `<summary>` is required |
| without it | the Markdown stays raw |

</details>

Nested `<details>`, table in the inner one:

<details>
<summary>Outer</summary>

<details>
<summary>Inner</summary>

| Depth | Element |
| ---: | :--- |
| 1 | outer `<details>` |
| 2 | inner `<details>` |

</details>

</details>

### 9.7 A table between two paragraphs with no blank lines

GFM needs a blank line before a table that follows a paragraph — without it
the pipes are just paragraph text. The first block below has no blank line
and should stay a paragraph; the second has one and should be a table.

Paragraph text immediately above.
| A | B |
| --- | --- |
| 1 | 2 |

Paragraph text with a blank line after it.

| A | B |
| --- | --- |
| 1 | 2 |
Paragraph text immediately below with no blank line — this line is absorbed
as a table row in GFM.

---

## 10. Not tables

None of the constructs in this section should produce a `<table>` element.
If any of them do, the table parser is too eager.

### 10.1 A delimiter row with no header

A delimiter row at the start of a block has no header to describe, so it is
a paragraph — or, for a dash-only line, a thematic break.

| --- | --- |
| 1 | 2 |

And with colons:

| :--- | ---: |
| 1 | 2 |

### 10.2 Pipes inside a fenced code block

The fence wins. Everything below should render as code, with the pipes
visible and no table.

```
| Name | Role |
| --- | --- |
| this | is code |
| not | a table |
```

With a language tag, so syntax highlighting also runs over it:

```markdown
| Name | Role |
| --- | --- |
| still | code |
```

Shell pipes, which are a different thing entirely:

```bash
cat samples/tables.md | grep -c '^|' | xargs echo 'pipe-leading lines:'
ps aux | awk '{print $2}' | head -5 | sort -n
```

Tilde fence, same expectation:

~~~
| A | B |
| --- | --- |
| tilde | fence |
~~~

### 10.3 Pipes in ordinary prose

The vertical bar is a normal character. In `a | b` it means alternation, in
`P(A | B)` it means conditional probability, in `x | y` it is a bitwise or,
and in a shell it is a pipe. None of these sentences should become a table.

Consider the grammar rule expr | term | factor, which has three alternatives
separated by bars and sits in the middle of a paragraph.

A line that is nothing but pipes and words, with no delimiter row anywhere:

apples | oranges | pears

Two such lines in a row, still with no delimiter row:

apples | oranges | pears
plums | cherries | figs

A line of pipes with a *dash* line after it that is not a valid delimiter
row, because the dashes are not separated per column:

apples | oranges | pears
-------

That last pair is a setext heading followed by nothing, in fact — the dashes
underline the line above and turn it into an `<h2>`. Which is its own
interesting failure mode, and is why it is here.

### 10.4 An indented (code block) table

Four spaces of indent makes an indented code block, which outranks the table
extension. This should render as code:

    | Name | Role |
    | --- | --- |
    | indented | four spaces |
    | therefore | code |

Three spaces is still a table (the maximum indent for a block is three):

   | Name | Role |
   | --- | --- |
   | indented | three spaces |
   | therefore | a table |

### 10.5 Escaped pipes at the start of a line

A row whose leading pipe is escaped has one fewer cell than it appears to.
With a two-column header, the row below collapses to a single cell.

| A | B |
| --- | --- |
\| 1 | 2 |
| 3 | 4 |

### 10.6 A table with no rows and no delimiter

A single line of pipes and nothing else. Paragraph.

| just | one | line |

---

End of file. If you got here with the preview still responsive and the
2,000-row table fully scrollable, tables are in decent shape.

