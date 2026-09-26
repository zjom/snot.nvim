# Simple Note Format — Specification

## 1. Introduction

Simple Note Format (snot) is a line-oriented plain text format for quick-capture notes. All structure and metadata can be found with `grep` and read without tooling.

### 1.1 Design principles

1. **One sigil per concept.** `#` is structure, `@` is metadata, `[[ ]]` is a link, `-` and `N.` are list items, `[ ]` is task state, `|` is a table row, `*` and `_` are emphasis, `` ` `` is code, `$` is math, `\` is escape. No sigil has a second meaning.
2. **Line-local.** Every construct is recognisable from its own line. The only exception is code and math blocks, which run between fence lines.
3. **No inheritance.** Metadata applies only to the scope it is written in.
4. **Human-readable metadata.** Keys and values are plain words and ISO dates, written inline.

### 1.2 Conformance

The key words MUST, MUST NOT, SHOULD and MAY are to be interpreted as in RFC 2119. A _reader_ is any program that parses CNF. A _writer_ is any person or program that produces it.

## 2. Lexical structure

### 2.1 Files

A note is a file. Files MUST be UTF-8. Lines end with LF or CRLF; readers MUST accept both. The note file extension is set by the collection and defaults to `.snot`.

The _notes root_ is the top directory of a collection. Link paths (section 7) are relative to it.

### 2.2 Line kinds

Every line is exactly one of these, tested in this order:

| Kind      | Rule                                                                       |
| --------- | -------------------------------------------------------------------------- |
| Verbatim  | A code or math block's fence lines and every line between them (section 9) |
| Blank     | Only whitespace                                                            |
| Heading   | Starts at column 0 with 1–6 `#` then a space (section 4)                   |
| List item | Indentation, then `- ` or digits + `. ` (section 5)                        |
| Table row | Indentation, then `\|` (section 10)                                        |
| Text      | Anything else                                                              |

### 2.3 Indentation

Indentation MUST use spaces; a tab in leading whitespace is an error. One level is 2 spaces. A line with _n_ leading spaces is at depth floor(_n_ / 2).

### 2.4 Escapes

A backslash followed by an ASCII punctuation character produces that character literally and stops it from acting as syntax, e.g. `\@`, `\*`, `\[`, `\#`. A backslash followed by anything else is a literal backslash. Outside code and math (section 9), escapes work everywhere, including at the start of a line (`\# not a heading`).

## 3. Scopes

A _scope_ is something metadata can be attached to and a link can point at. There are exactly four kinds: the **file**, a **heading**, a **list item**, and a **table row**.

Every non-blank line belongs to exactly one scope, its _owner_:

1. A heading line owns itself.
2. A table row owns itself, unless it is a separator row (section 10.2).
3. A list item line owns itself. So does each following line indented deeper than the item's marker, up to the next blank line or line at the same or lesser depth. These are its _continuation lines_.
4. Any other line is owned by the nearest heading above it. With no heading above, the file owns it.

Scopes nest (a heading contains lower-level headings; a list item contains deeper items), but nesting carries no meaning for metadata. Each scope has only the metadata written on the lines it owns.

For quick capture, several notes MAY share one file, each as a heading. A heading and a file are interchangeable: moving a heading's section into its own file keeps its metadata unchanged.

## 4. Headings

A heading line starts at column 0 with 1 to 6 `#` characters, then one space, then the heading text. The number of `#` is the level.

```
# Atlas kickoff @project:atlas
## Decisions @id:decisions
```

- `#text` (no space) and `####### x` (7 or more) are text lines.
- The heading text is inline content (section 8) and may hold metadata tokens and links.
- A heading's section runs until the next heading of the same or lower level, or end of file.

## 5. Lists and tasks

### 5.1 List items

A list item line is indentation, a marker, one space, then content.

| Marker          | Kind      | Example    |
| --------------- | --------- | ---------- |
| `-`             | Unordered | `- milk`   |
| digits then `.` | Ordered   | `12. milk` |

An item at depth _d_ + 1 is a child of the nearest item above it at depth _d_. An item deeper than depth 0 with no such parent is an error; readers SHOULD treat it as depth 0.

Ordered numbers are kept as written. Readers MUST NOT renumber them. Unordered and ordered items MAY be mixed in one list.

### 5.2 Tasks

A task is a list item whose content starts with a state box, then a space or end of line.

| Box   | State     |
| ----- | --------- |
| `[ ]` | Open      |
| `[x]` | Done      |
| `[-]` | Cancelled |

The box letter MUST be lowercase. Any other bracketed text, such as `[X]` or `[?]`, is ordinary content. Tasks are list items in every other respect: they nest, may be ordered (`1. [ ] draft`), and carry metadata.

```
- [ ] Book design review @due:2026-10-02
  - [x] Find a room
  - [ ] Invite Priya @person:priya
- [-] Chase old invoice
```

## 6. Metadata

Metadata is written as _tokens_ anywhere in inline content. A token attaches one or more values under a key to the scope that owns its line (section 3).

### 6.1 Token forms

| Form             | Meaning    | Values            |
| ---------------- | ---------- | ----------------- |
| `@key`           | Flag (tag) | `["true"]`        |
| `@key:value`     | Scalar     | `["value"]`       |
| `@key:[a, b, c]` | List       | `["a", "b", "c"]` |
| `@key:[]`        | Empty list | `[]`              |

### 6.2 Recognition

- `@` starts a token only at the start of a line or right after whitespace. `bob@example.com` is text.
- A key is a lowercase ASCII letter followed by lowercase letters, digits, `-` or `_`. `@Bob` and `@1x` are text.
- Tokens are not recognised inside links, code, math or other tokens.

### 6.3 Values

- **Scalar:** everything after `:` up to the next whitespace or end of line. It MUST NOT start with `[`. Writers SHOULD NOT put punctuation directly after a token (write `@due:2026-10-01 .`, or put the token elsewhere); a trailing `.` would be part of the value.
- **List:** `[`, then items separated by `,`, then `]`, all on the same line. Whitespace around each item is trimmed and empty items are dropped. Items may contain spaces; `\,` and `\]` escape a literal comma or bracket. An unclosed `[` makes the whole token text.
- Values are strings. Readers MUST NOT interpret them beyond this section, except for the conventions in 6.5.

### 6.4 Combining

Every key on a scope maps to an ordered list of strings. All tokens for the same key in the same scope are concatenated in reading order. These are equivalent:

```
@person:bob @person:priya
@person:[bob, priya]
@person:bob @person:[priya]
```

Duplicate values are kept; readers MAY deduplicate. Tokens in child scopes never affect a parent, and parents never affect children.

### 6.5 Conventions

- **Dates and times** use ISO 8601: `2026-09-26`, `2026-09-26T14:00`, `2026-09-26T14:00+10:00`. They sort correctly as text and support prefix search (`@due:2026-10`).
- **Booleans** are `true` and `false`.
- **Multi-word values** use a list: `@client:[Acme Corp]`.

### 6.6 Reserved keys

`@id` is the only reserved key. It names a scope as a link anchor (section 7.3). It MUST be a single value matching the key syntax, and MUST be unique within its file. All other keys are free for any use.

## 7. Links

### 7.1 Syntax

A link is `[[target]]` or `[[target|label]]`, on one line. Target and label are trimmed. The label is plain text; no tokens, links or emphasis are recognised inside a link. `\|` and `\]` escape literal characters.

### 7.2 Target kinds

The target's shape decides its kind, tested in order:

| Shape                                      | Kind                | Example                         |
| ------------------------------------------ | ------------------- | ------------------------------- |
| Starts with a scheme and `://`             | URL                 | `[[https://example.com/brief]]` |
| Starts with `#`                            | Anchor in this file | `[[#decisions]]`                |
| Path with no extension, optional `#anchor` | Note                | `[[projects/atlas#risks]]`      |
| Path with an extension                     | File                | `[[img/whiteboard.png]]`        |

- A scheme is a letter followed by letters, digits, `+`, `-` or `.`.
- Paths use `/` and are relative to the notes root. They MUST NOT start with `/` or contain `..`. Each note therefore has exactly one spelling, which keeps backlinks greppable.
- A note path resolves to _path_ + the note extension.
- An anchor is only valid on a note or on `#` alone. `[[img/a.png#x]]` is an error.

### 7.3 Anchor resolution

An anchor names a scope in the target note:

1. The scope carrying `@id:<anchor>`, if one exists.
2. Otherwise the first heading whose slug equals the anchor.

The slug of a heading is its text with tokens removed, lowercased, every run of non-alphanumeric characters replaced by `-`, and leading and trailing `-` removed. `## Open Risks (Q4) @status:open` has the slug `open-risks-q4`.

An unresolved link is not a parse error. Readers SHOULD report it as a broken link.

## 8. Inline content and emphasis

Inline content is the text of headings, list items and text lines. It may contain tokens, links, emphasis and escapes.

| Syntax   | Meaning   |
| -------- | --------- |
| `*text*` | Bold      |
| `_text_` | Underline |

Delimiter rules, the same for both:

- An opening delimiter follows start of line, whitespace or punctuation, and is followed by a non-whitespace character.
- A closing delimiter follows a non-whitespace character, and is followed by end of line, whitespace or punctuation.
- A span MUST close on the same line; an unclosed delimiter is literal text.
- Bold and underline MAY nest in each other (`*_both_*`), but not in themselves.

So `snake_case_name`, `2*3*4` and `*/` are left as text. Emphasis is not recognised inside tokens, links, code or math.

## 9. Code and math

Code and math content is _verbatim_. No tokens, links, emphasis or escapes are recognised inside it, and a backslash is a literal backslash. Math content is TeX.

### 9.1 Blocks

| Kind | Opening fence line                             | Closing fence line                        |
| ---- | ---------------------------------------------- | ----------------------------------------- |
| Code | 3 or more backticks, then an optional language | At least as many backticks as the opening |
| Math | `$$`                                           | `$$`                                      |

- A fence line is optional indentation, the fence, and optional trailing whitespace. On a code fence, the first word after the backticks is the language; the rest of the line is ignored.
- Every line between the fences is content. Up to the opening fence's indentation is stripped from each content line.
- An unclosed block runs to the end of the file.
- The whole block, fences included, is owned by the owner of its opening fence line (section 3). An indented fence under a list item is a continuation of that item, and blank lines inside the block do not end the item.

````
```python
print("@not-metadata")
```

$$
\int_0^1 x^2\,dx = \tfrac{1}{3}
$$
````

### 9.2 Inline

| Syntax       | Meaning     |
| ------------ | ----------- |
| `` `code` `` | Inline code |
| `$x^2$`      | Inline math |

- **Inline code** opens with a run of _n_ backticks and closes at the next run of exactly _n_ backticks on the same line. To include a backtick, use a longer run: ``` `` a`b `` ```. When the content both starts and ends with a space, one space is stripped from each end.
- **Inline math** opens with a `$` followed by a non-whitespace character. It closes at the next `$` that follows a non-whitespace character and is not followed by a digit, on the same line. So `$5 and $10` is text. Write a literal dollar sign as `\$`.
- An unclosed span is literal text.

### 9.3 Precedence

Inline constructs are recognised left to right. At each position, the construct that opens there takes its whole extent. Nothing is recognised inside code, math, tokens or links. Bold and underline are the only constructs that contain others, and their closing delimiter never matches inside a construct they contain.

### 9.4 Effect on grep

Plain grep cannot tell verbatim content from live syntax. `@key` inside a code block will match a metadata search, though readers MUST NOT treat it as metadata. If this matters, pipe results through a reader-aware filter.

## 10. Tables

Tables are pipe tables. Each row is one line, so a grep hit on a row returns the whole row.

```
| Milestone | Due        | Owner |
|-----------|------------|-------|
| Beta      | 2026-10-31 | bob   |
| Retro     | 2026-11-07 | priya |
```

### 10.1 Rows

- A table row is optional indentation, then `|`, then cells separated by `|`. A trailing `|` is optional. Write `\|` at the start of a line for literal text.
- A table is a maximal run of consecutive rows at the same indentation. A blank line or any other line ends it.
- Each cell is inline content, trimmed. Empty cells are allowed. Rows may have different numbers of cells; missing cells are empty.
- A cell ends at the next `|` that is not escaped and not inside code, math or a link (section 9.3). So `` `a|b` `` and `[[x|label]]` need no escaping, and a scalar metadata value also ends at `|`.
- Alignment padding is optional and carries no meaning. `|a|b|` and `| a | b |` are the same row.

### 10.2 Header and separators

- A _separator row_ is a row whose every cell is one or more `-`, with optional surrounding spaces.
- If a table's second row is a separator, its first row is the header. Otherwise the table has no header.
- Separator rows elsewhere are visual dividers and carry no data. Alignment markers such as `:---:` are not supported; such a row is an ordinary data row.

### 10.3 Rows as scopes

Every row except a separator is a scope (section 3). Tokens in any of its cells attach to that row, so a row can carry `@due`, `@person` or an `@id` to link to. The table itself is not a scope.

```
| Beta  | 2026-10-31 | @owner:bob @id:beta |
| Retro | 2026-11-07 | @owner:priya        |
```

A row cannot span lines. For long cell content, use a list instead.

### 10.4 CSV and TSV

A code block whose language is `csv` (RFC 4180) or `tsv` MAY be displayed as a table. Its content stays verbatim: no metadata, links or emphasis, and its rows are not scopes. Use it for data pasted from spreadsheets.

## 11. Grammar

ABNF (RFC 5234). Context rules the grammar can't express (token position, emphasis boundaries, scope ownership) are normative in sections 3, 6, 8, 9 and 10.

```
file          = *element
element       = code-block / math-block / line EOL
line          = blank / heading / item / row / text
blank         = *WSP

code-block    = indent code-open EOL *(verbatim EOL) [*WSP code-close *WSP EOL]
code-open     = 3*"`" *WSP [info]         ; info has no "`"; first word = language
code-close    = 3*"`"                      ; at least as many as code-open
math-block    = indent "$$" *WSP EOL *(verbatim EOL) [*WSP "$$" *WSP EOL]
verbatim      = *char                      ; any line but the closing fence

heading       = 1*6"#" SP inline
item          = indent marker SP [taskbox (SP / EOL-AHEAD)] inline
indent        = *(2SP)
marker        = "-" / 1*DIGIT "."
taskbox       = "[" (SP / "x" / "-") "]"
row           = indent "|" cell *("|" cell) *WSP
                                           ; an empty last cell after a trailing "|" is dropped
cell          = inline                     ; ends at an unprotected "|"; trimmed
separator     = indent "|" sep-cell *("|" sep-cell) *WSP
sep-cell      = *WSP 1*"-" *WSP
text          = inline

inline        = *(escape / code-span / math-span / token / link
                  / bold / underline / char)
escape        = "\" PUNCT
code-span     = n"`" 1*char n"`"          ; same run length n; content has no run of exactly n
math-span     = "$" NONWS [*char NONWS] "$"  ; closing "$" not followed by DIGIT

token         = "@" key [":" value]      ; only at line start or after WSP
key           = LCALPHA *(LCALPHA / DIGIT / "-" / "_")
value         = list / scalar
scalar        = scalar-first *(escape / NONWS)
scalar-first  = escape / (NONWS except "[")
list          = "[" [list-item *("," list-item)] "]"
list-item     = *(escape / (char except "," / "]"))   ; trimmed

link          = "[[" target ["|" label] "]]"
target        = url / anchor / path [anchor]
url           = scheme "://" *(escape / (char except "|" / "]"))
scheme        = ALPHA *(ALPHA / DIGIT / "+" / "-" / ".")
anchor        = "#" 1*(char except "|" / "]")
path          = segment *("/" segment)
segment       = 1*(char except "/" / "#" / "|" / "]")   ; not ".."
label         = *(escape / (char except "]"))

bold          = "*" 1*inline-char "*"          ; boundary rules in 8
underline     = "_" 1*inline-char "_"

EOL           = LF / CRLF                  ; optional after the last line
LCALPHA       = %x61-7A
PUNCT         = %x21-2F / %x3A-40 / %x5B-60 / %x7B-7E
NONWS         = any char except WSP
char          = any Unicode scalar except CR / LF
```

## 12. Example and grep reference

### 10.1 Example: `projects/atlas.snot`

````
@area:work @created:2026-09-26

# Atlas kickoff @project:atlas @person:[bob, priya]

Met with Bob about the *new* timeline. See [[projects/atlas-plan#risks|risk list]]
and the [[https://example.com/brief|client brief]]. Whiteboard: [[img/atlas-wb.png]].

## Decisions @id:decisions
1. Ship beta by end of Oct @due:2026-10-31
2. Drop the _legacy_ importer
3. Cap each import at `MAX_ROWS` rows

## Estimate
Expected load is $r = n / t$, with `n` taken from the import log:

$$
r = \frac{12000}{60} = 200 \text{ rows/s}
$$

```sh
grep -c import atlas.log   # @count here is not metadata
```

## Milestones
| Milestone | Due        | Owner                  |
|-----------|------------|------------------------|
| Beta      | 2026-10-31 | @owner:bob @id:beta    |
| Retro     | 2026-11-07 | @owner:[priya, sam]    |

## Follow-ups @status:open
- [ ] Send Bob revised plan @due:2026-09-30 @person:bob @id:send-plan
- [ ] Book design review @urgent @person:[priya, sam]
  - [x] Find a room
  - [ ] Invite Priya
- [-] Chase old invoice
````

The file has `area: [work]` and `created: [2026-09-26]`. "Atlas kickoff" has `project` and `person: [bob, priya]`; the paragraph below it adds nothing, since it holds no tokens. "Invite Priya" has no metadata at all: nothing is inherited from "Book design review". The "@count" inside the code block is not metadata. Each Milestones row is its own scope, so the Beta row has owner bob and can be linked as \[\[projects/atlas#beta\]\]. Other notes can link to `[[projects/atlas#decisions]]` or `[[projects/atlas#send-plan]]`.

### 10.2 Grep reference

All commands use GNU grep and run from the notes root.

```sh
# Outline: every heading
grep -rnE '^#{1,6} ' .

# Open tasks
grep -rnE '^ *(-|[0-9]+\.) \[ \]' .

# A flag (tag)
grep -rnE '(^|[[:space:]])@urgent([[:space:]:]|$)' .

# A scalar key-value, with date prefix search
grep -rn '@due:2026-10' .

# One value, whether scalar or inside a list
grep -rnE '@person:(bob([[:space:]]|$)|\[([^]]*,)?[[:space:]]*bob[[:space:]]*[],])' .

# Every key in use, with counts
grep -rhoE '(^|[[:space:]])@[a-z][a-z0-9_-]*' . | tr -d ' \t' | sort | uniq -c

# Backlinks to a note
grep -rnE '\[\[projects/atlas(#|\||\]\])' .

# Table rows mentioning bob
grep -rnE '^ *\|.*bob' .

# Where an anchor is defined
grep -rn '@id:decisions' .
```

The one-value search is the only awkward pattern. A shell function hides it:

```sh
meta() {  # usage: meta KEY VALUE [DIR]
  grep -rnE "@$1:($2([[:space:]]|\$)|\[([^]]*,)?[[:space:]]*$2[[:space:]]*[],])" "${3:-.}"
}
```
