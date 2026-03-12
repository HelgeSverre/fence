---
title: GFM Kitchen Sink
author: Fence Editor
date: 2026-03-12
tags: [markdown, gfm, demo]
draft: false
---

# Heading 1

## Heading 2

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

---

## Paragraphs and Inline Formatting

This is a regular paragraph with **bold text**, *italic text*, and ***bold italic*** combined. You can also use __underscores for bold__ and _underscores for italic_.

Here's some ~~strikethrough text~~ that GFM supports. And here's some `inline code` mixed into a sentence. You can escape \*asterisks\* and \`backticks\` with backslashes.

This paragraph has a
hard line break using two trailing spaces, and this continues on the next line.

This paragraph has a\
hard line break using a backslash.

## Links

- [Inline link](https://example.com)
- [Link with title](https://example.com "Example Site")
- [Reference link][ref1]
- Autolinked URL: https://example.com
- Email autolink: user@example.com

[ref1]: https://example.com "Reference Link"

## Images

![A mountain landscape](https://picsum.photos/800/400)

![Small thumbnail](https://picsum.photos/200/200 "A square thumbnail image")

[![Clickable image link](https://picsum.photos/400/200)](https://example.com)

## Blockquotes

> This is a blockquote. It can span multiple lines and contains **formatted text**.
>
> It can have multiple paragraphs.

> Blockquotes can be nested:
>
> > This is a nested blockquote.
> >
> > > And a third level deep.

> **Note:** Blockquotes are great for callouts and citations.
>
> — *Someone Famous*

## Lists

### Unordered Lists

- Item one
- Item two
  - Nested item A
  - Nested item B
    - Deeply nested item
- Item three

* Asterisk style
* Also works

### Ordered Lists

1. First item
2. Second item
   1. Sub-item one
   2. Sub-item two
3. Third item
4. Fourth item

### Mixed Lists

1. First ordered item
   - Unordered sub-item
   - Another sub-item
2. Second ordered item
   1. Ordered sub-item
   2. Another ordered sub-item
      - Mixed deeper

### Task Lists

- [x] Completed task
- [x] Another done task
- [ ] Incomplete task
- [ ] Another pending task
  - [x] Nested completed subtask
  - [ ] Nested incomplete subtask

## Code

### Inline Code

Use `const x = 42;` for inline code. Backticks inside code: `` `backtick` `` works too.

### Fenced Code Blocks

```javascript
function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

const result = fibonacci(10);
console.log(`Fibonacci(10) = ${result}`);
```

```python
def quicksort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    middle = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quicksort(left) + middle + quicksort(right)

print(quicksort([3, 6, 8, 10, 1, 2, 1]))
```

```rust
fn main() {
    let names = vec!["Alice", "Bob", "Charlie"];
    for name in &names {
        println!("Hello, {}!", name);
    }
}
```

```css
.container {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1rem;
  padding: 2rem;
}
```

```json
{
  "name": "fence",
  "version": "1.0.0",
  "dependencies": {
    "electron": "^28.0.0",
    "vite": "^5.0.0"
  }
}
```

```bash
#!/bin/bash
for file in *.md; do
  echo "Processing: $file"
  wc -w "$file"
done
```

```
Plain code block without language specification.
No syntax highlighting here.
```

### Indented Code Block

    This is an indented code block.
    It uses four spaces of indentation.
    No syntax highlighting is applied.

## Tables

### Simple Table

| Feature     | Supported |
| ----------- | --------- |
| Bold        | Yes       |
| Italic      | Yes       |
| Strikethrough | Yes     |
| Task Lists  | Yes       |

### Aligned Table

| Left-aligned | Center-aligned | Right-aligned |
| :----------- | :------------: | ------------: |
| Cell 1       | Cell 2         | Cell 3        |
| Cell 4       | Cell 5         | Cell 6        |
| Longer content here | **Bold cell** | `code cell` |

### Complex Table

| Method   | Endpoint          | Status | Description              |
| -------- | ----------------- | ------ | ------------------------ |
| `GET`    | `/api/users`      | 200    | List all users           |
| `POST`   | `/api/users`      | 201    | Create a new user        |
| `GET`    | `/api/users/:id`  | 200    | Get user by ID           |
| `PUT`    | `/api/users/:id`  | 200    | Update user              |
| `DELETE` | `/api/users/:id`  | 204    | Delete user              |

## Horizontal Rules

Three different syntaxes:

---

***

___

## Emphasis Combinations

- **Bold and *nested italic* inside**
- *Italic and **nested bold** inside*
- ***All bold and italic***
- ~~Strikethrough with **bold** inside~~
- **Bold with `code` inside**
- *Italic with [a link](https://example.com) inside*

## Footnotes

Here's a sentence with a footnote[^1]. And another one[^note].

[^1]: This is the first footnote.
[^note]: This is a named footnote with more detail.

    It can even have multiple paragraphs.

## Definition-style Content

Term 1
: Definition for term 1

Term 2
: Definition for term 2
: An alternate definition

## Escaping

These characters can be escaped with backslashes:

\\ \` \* \_ \{ \} \[ \] \( \) \# \+ \- \. \! \|

## Paragraphs with Varied Content

Here is a paragraph that discusses *performance characteristics* of various **sorting algorithms**. The best general-purpose algorithm is often `quicksort` with O(n log n) average time complexity, though `mergesort` guarantees O(n log n) in the worst case.

> **Algorithm Comparison:**
> - Quicksort: O(n log n) average, O(n^2) worst
> - Mergesort: O(n log n) guaranteed
> - Heapsort: O(n log n) guaranteed, in-place

For more details, see the [Wikipedia article on sorting](https://en.wikipedia.org/wiki/Sorting_algorithm).

## Long Content for Scroll Testing

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra, est eros bibendum elit, nec luctus magna felis sollicitudin mauris.

Integer in mauris eu nibh euismod gravida. Duis ac tellus et risus vulputate vehicula. Donec lobortis risus a elit. Etiam tempor. Ut ullamcorper, ligula ut dictum pharetra, nisi nunc fringilla magna, in commodo elit erat nec turpis. Ut pharetra purus quis magna.

---

*End of GFM kitchen sink.*
