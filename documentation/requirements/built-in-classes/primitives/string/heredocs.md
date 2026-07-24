# Heredocs
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_string_heredocs",
	"role": "spec for Caspian's heredoc syntax — the `<<TERMINATOR ... TERMINATOR` multi-line string form, its terminator quoting, the (type) annotation slot for tooling metadata, and the compile-time metadata methods' (%documentation, %vibecode) special always-literal rule. Sibling of string/index.md (the class every heredoc materializes into) and regular-expressions.md under primitives/string/.",
	"status": "spec — basic form, indent-stripping rule (least-indented-line-sets-base; mixing tabs and spaces raises a compile-time warning), (type) annotation, terminator-quoting-controls-interpolation rule, `#{expr}` interpolation form, escape processing follows terminator quoting (literal terminators have no escapes; double-quoted terminators process escapes), heredocs-as-arguments with strict in-order body collection, per-statement duplicate-terminator-name raise, and compile-time-metadata always-literal override all settled. A related open question about `<<` as array-append operator (which would conflict with the heredoc opener) lives on the array page, not here.",
	"audience": "developers writing Caspian; lexer implementers"
}}
~~~

A **heredoc** is a multi-line string literal — the content starts on the line after the opener and runs until a terminator line. Every heredoc produces a plain [string](./) at runtime; nothing about the heredoc form changes the resulting type. Heredocs are used both by the compile-time metadata methods ([`%documentation`](https://puck.uno/documentation/requirements/global-methods/#documentation), [`%vibecode`](https://puck.uno/documentation/requirements/global-methods/#vibecode)) and anywhere else a string literal is expected.

## Basic form

Opener `<<TERMINATOR` at the end of a statement. The body starts on the next line and runs until a line whose only content is the terminator:

~~~caspian
$msg = <<EOF
Hello, world.
This is a multi-line string.
EOF
~~~

The terminator name can be any identifier — `EOF` is convention, not a keyword. Pick a name that doesn't appear inside the content on its own line.

## Indentation

**Leading whitespace is stripped based on the least-indented line, including the terminator.** The terminator's own indent effectively marks the base — every body line has that much whitespace stripped from its start. This is always on; there is no separate opener syntax for indent-preservation (Ruby's `<<EOF` vs. `<<~EOF` distinction doesn't exist here).

~~~caspian
if $whatever
	$doc = <<EOF
	whatever
	dude
	EOF
end
~~~

`$doc` receives:

~~~
whatever
dude
~~~

The line with the fewest leading whitespace characters sets the base — that many characters get stripped from every body line. Accidentally-outdenting a body line makes that line the base (less gets stripped, not more). Flush-left is always safe: `<<EOF` with a flush-left terminator strips nothing.

**Only whitespace is ever stripped.** The stripper never touches non-whitespace characters. If for any reason a line's leading whitespace is shorter than the base indent, stripping stops at the first non-whitespace character on that line — the base is a maximum, not a mandatory amount. The worst any miscalculation can produce is surprising leftover whitespace at the start of a line; content bytes are always preserved.

**Mixing tabs and spaces raises a compile-time warning.** The stripper counts each leading character as one unit of indent — one tab is one unit, one space is also one unit. A line starting with `\t` and a line starting with `    ` (four spaces) look identical under `tab-size: 4`, but the character counts differ (1 vs. 4). The base indent is whichever line has the fewest — the tab-indented line, at 1 character — so only ONE character gets stripped from every line, leaving four-space-indented lines with three leading spaces they didn't expect. Stay consistent within a heredoc: all tabs or all spaces.

When the parser detects mixed tab/space leading whitespace within a single heredoc's body-and-terminator lines, it emits a warning naming the heredoc and pointing at the mismatched lines, and it also attaches the warning to the resulting string. The heredoc still compiles — the warning doesn't stop the build — but the surprising result described above is what you get if you ignore it. Fix the indentation to make the warning go away; there's no way to intentionally "want" mixed indentation, so no opt-out flag suppresses it.

(The exact mechanism for how warnings are emitted and how they attach to a string is undefined here — Caspian's warning-delivery model hasn't been settled yet. This section only commits to the two facts: a warning IS produced at parse time, and it IS attached to the constructed string. The plumbing lands when the warning system does.)

## Type annotation

An optional MIME-type annotation goes immediately after `<<`, in parens, before the terminator:

~~~caspian
$doc = <<('text/markdown')EOF
# Hello

This is **markdown**.
EOF
~~~

**The type attaches to the string at construction time**, via the string's `content_type` property:

~~~caspian
$doc.content_type          # 'text/markdown'
~~~

`content_type` is a straightforward getter/setter pair on every string, backed by the string's bucket at `@content_type`. When a heredoc opener includes `(type)`, the parser writes the type to that bucket entry at construction. When the opener omits `(type)`, nothing is written and the getter returns `null`. Programs can set the field explicitly at any time (`$str.content_type = 'text/html'`) — no validation, no restrictions on what value goes in.

The Caspian runtime does not act on the type on its own. Nothing renders, escapes, or dispatches based on it implicitly. Sinks and consumers that want to consult it — an HTTP response body setting `Content-Type`, an editor preview picking a renderer — read `$str.content_type` explicitly.

**Caspian does not validate the type.** Whatever text appears inside the parens is what lands in `@content_type` verbatim. `<<(markdown)EOF` sets it to `'markdown'`; `<<('text/markdown')EOF` sets it to `'text/markdown'`; `<<(anything-you-want)EOF` sets it to `'anything-you-want'`. No known-type list, no normalization, no rejection of unrecognized values — the parser writes what the writer typed, and consumers interpret it however they want.

## Terminator quoting

The terminator can be bare or quoted. Whether the body interpolates depends on the terminator form:

| Opener | Interpolates? |
|---|---|
| `<<EOF` | No — bare terminator means literal content. |
| `<<'EOF'` | No — single-quoted terminator, still literal. Equivalent to the bare form. |
| `<<"EOF"` | Yes — double-quoted terminator, uses `#{expr}` interpolation. |

The rule mirrors regular string quoting ([string § Interpolation](https://puck.uno/documentation/requirements/built-in-classes/primitives/string/#interpolation)): single quotes are literal, double quotes interpolate. Bare terminators default to literal (the safer default) so callers opt IN to interpolation by writing the terminator with double quotes.

**Interpolation form.** Inside a `<<"EOF"` body, `#{expr}` is evaluated the same way it is inside a double-quoted string — any expression is legal; the result is stringified through the value's `to_string` hook. To write a literal `#{` in an interpolating heredoc, escape the `#`: `\#{not interpolated}`. Nested braces inside `#{...}` are tracked by depth, so hash literals compose cleanly.

~~~caspian
$name = 'Alice'

$literal = <<EOF
hello, #{$name}
EOF
# 'hello, #{$name}' — literal, no interpolation

$greeted = <<"EOF"
hello, #{$name}
EOF
# 'hello, Alice' — interpolated
~~~

**Escapes follow the terminator quoting.** Same rule as regular strings:

- **Literal heredocs (`<<EOF`, `<<'EOF'`) have no escape processing.** Backslash sequences like `\n`, `\t`, `\\`, `\'`, `\"` are just the literal characters — a backslash followed by `n`, not a newline. Every byte in the body appears verbatim (after indent-stripping).
- **Interpolated heredocs (`<<"EOF"`) DO process escapes.** `\n`, `\t`, `\\`, `\"`, and the other usual escape sequences are recognized and expanded to their control-character values, same as inside a double-quoted string.

~~~caspian
$literal = <<EOF
line one
\n is not a newline here
EOF
# 'line one\n\\n is not a newline here' — the backslash is literal

$processed = <<"EOF"
line one
this contains a newline: \n and a tab: \t
EOF
# 'line one\nthis contains a newline: \n and a tab: \t' — escapes processed
~~~

The escape-processing rule matches the interpolation rule: single-quoted and bare terminators are truly literal (no escapes, no interpolation); double-quoted terminators process both escape sequences and `#{expr}` interpolation.

## Heredocs as arguments

A heredoc is an expression — anywhere a value is legal, so is `<<TERMINATOR`. The most common non-trivial use is passing a heredoc directly as a function argument:

~~~caspian
&foo($blah, <<EOF, $blue)
this is the string that foo receives as its second argument
EOF
~~~

**Multiple heredocs on the same statement collect their bodies in opener-order.** After the current statement's line completes, the parser reads the following lines and matches them to the openers in the order the openers appeared on the statement line. First `<<`-opener gets the first body block; second `<<`-opener gets the second; and so on:

~~~caspian
&foo($blah, <<A, $blue, <<B)
whatever
A
dude
B
~~~

That call gets four arguments — `$blah`, `"whatever"`, `$blue`, `"dude"`. A's body is read first (until `A` terminates it), then B's body (until `B` terminates it).

**Body-to-opener matching is strict in-order, not by which terminator appears first.** If the terminator lines appear in the wrong order, the earlier opener swallows the later terminator as content and the later opener is left unterminated:

~~~caspian
&foo($blah, <<A, $blue, <<B)
whatever
B
dude
A
~~~

Here, A collects `"whatever\nB\ndude"` (the `B` line is just content — the parser is looking for A's terminator) and terminates at `A`. Then B has nothing to collect and no terminator to find. **Parse error: unterminated heredoc `B`.**

**Reusing the same terminator name within one statement raises.** `&foo(<<A, <<A)` — two openers with the same terminator name — raises at parse time. Even though the parser could in principle match them in-order (first body to first opener, second body to second), the confusion cost isn't worth the ambiguity. Every stacked heredoc in one statement must have a distinct terminator name:

~~~caspian
&foo(<<A, <<A)          # raises: duplicate terminator name 'A'
~~~

The rule applies per statement, not globally — different statements can independently use `<<A`.

## Compile-time metadata methods: always literal

Heredocs feeding the compile-time metadata methods `%documentation` and `%vibecode` **never interpolate, regardless of terminator quoting.** All three of these produce identical (literal) content:

~~~caspian
%documentation <<EOF
%documentation <<"EOF"
%documentation <<'EOF'
~~~

Variables, expressions, and escape sequences inside those heredoc bodies appear as literal text. Compile-time metadata blocks aren't evaluated at runtime; there's nothing to interpolate against.

The type slot on these methods' heredocs still works as normal — `%documentation <<(markdown)EOF ... EOF` records `text/markdown` as the annotation the tooling layer reads (the `%documentation` block itself produces no observable runtime string, so the `content_type` question is moot for these methods specifically; but the recording is what the tooling layer reads).

## Testing

### Basic form

- **Heredoc produces a plain String** — the resulting value is a String instance (same class as any quoted literal).
- **Simple two-line body** — opener `<<EOF`, body `hello\nworld`, terminator `EOF` produces the string `"hello\nworld"` (with an internal newline).
- **Empty body** — opener `<<EOF` immediately followed by `EOF` produces `''`.
- **Single-line body** — one content line between opener and terminator produces the line's content (with trailing newline per spec).
- **Terminator name is any identifier** — `<<FOO ... FOO`, `<<XYZ ... XYZ`, `<<EOF ... EOF` all work.
- **Trailing newline** — spec what the final newline behavior is (test whichever way spec settles).

### Terminator matching

- **Terminator matches only on a line whose sole content is the identifier** — a line containing the identifier plus other characters is body, not terminator.
- **Terminator with surrounding whitespace matches** — with the least-indented-line rule, spec whether whitespace-only prefix on the terminator line is OK; test that it is.
- **Unclosed heredoc raises** — reaching EOF without seeing the terminator raises a parse error naming the terminator.
- **Terminator identifier is exact-match, case-sensitive** — `<<EOF ... eof` does NOT terminate.

### Indentation stripping

- **Least-indented line sets the base** — a body with lines indented by 4, 4, 2 spaces strips 2 from every line.
- **Terminator's indent participates in setting the base** — if the terminator has 3 spaces and every body line has 4, base is 3, one space remains on each body line.
- **Flush-left terminator strips nothing** — a terminator at column 0 forces base 0; all body leading whitespace is preserved.
- **Body lines above the base stop stripping at their own non-whitespace** — a body line with fewer leading whitespace characters than the base is preserved starting at its first non-whitespace character (base is a maximum).
- **Only whitespace is ever stripped** — non-whitespace characters are never touched.
- **All-tabs works consistently** — a heredoc indented entirely with tabs strips correctly.
- **All-spaces works consistently**.
- **Mixed tabs and spaces raises a compile-time warning** — the compiler emits a warning naming the heredoc, and the warning attaches to the resulting string.
- **Mixed tabs/spaces still compiles** — the warning does not stop the build.
- **No opt-out flag for mixed-indent warning** — the warning cannot be suppressed.

### Type annotation

- **`<<(type)EOF` writes to `content_type`** — after `$doc = <<(text/markdown)EOF ... EOF`, `$doc.content_type` returns `'text/markdown'`.
- **`<<EOF` without a type slot leaves `content_type` null** — `$doc.content_type` returns `null`.
- **Type slot with quoted string** — `<<('text/markdown')EOF` accepts a single-quoted content type.
- **Type slot without quotes** — `<<(markdown)EOF` sets `content_type` to `'markdown'`; no validation.
- **Type slot with arbitrary value** — `<<(anything-you-want)EOF` sets `content_type` to `'anything-you-want'`.
- **The Caspian runtime does not act on `content_type`** — no rendering, escaping, or dispatch happens implicitly.
- **`.content_type=` can override the annotation** after construction.

### Terminator quoting and interpolation

- **`<<EOF` is literal** — `#{$x}` in the body is left as `#{$x}`.
- **`<<'EOF'` is literal** — equivalent to bare form.
- **`<<"EOF"` interpolates** — for `$name = 'Alice'`, a body `hello, #{$name}` produces `hello, Alice`.
- **`<<"EOF"` interpolation stringifies non-string values** — `#{42}` becomes `'42'`.
- **`<<"EOF"` supports nested braces** — `#{{a: 1}.length}` produces `'1'`.
- **`\#{` in `<<"EOF"` escapes to a literal `#{`**.
- **`\#{` in `<<EOF` is a literal backslash followed by `#{`** — no escape processing.

### Escape processing

- **Literal heredocs (`<<EOF`) do NOT process escapes** — a body containing `\n` produces a backslash followed by `n`, no newline.
- **Literal heredocs preserve `\\`, `\t`, `\'`, `\"` verbatim** — no expansion.
- **Interpolated heredocs (`<<"EOF"`) process `\n`** as a newline.
- **Interpolated heredocs process `\t`** as a tab.
- **Interpolated heredocs process `\\`** as a single backslash.
- **Interpolated heredocs process `\"`** as a literal double quote.
- **Single-quoted terminator `<<'EOF'` behaves as literal** (same as bare form).

### Heredocs as arguments

- **Single heredoc as argument** — `&foo(<<EOF)` followed by a body then `EOF` passes the body string as the argument.
- **Multiple heredocs on one statement collect in opener order** — `&foo(<<A, $x, <<B)` reads A's body first, then B's body.
- **Opener order matters, not terminator name order** — with `<<A, <<B` on the same statement, the first body block goes to A regardless of which terminator name appears first in the following lines.
- **Out-of-order terminators cause the earlier opener to swallow the later terminator as content** — `<<A, <<B` followed by body ending in `B` then more body then `A` gives A a multi-line body (including the `B` line as content) and leaves B unterminated. Parse error.
- **Duplicate terminator name in one statement raises** — `&foo(<<A, <<A)` raises at parse time.
- **Different statements CAN reuse a terminator name** — `&foo(<<A)` on one line and `&bar(<<A)` on another line each work independently.

### Compile-time metadata methods

- **`%documentation <<EOF` body is literal** — variables and escapes appear as text.
- **`%documentation <<"EOF"` is ALSO literal** — the interpolation/escape rules do not fire on compile-time metadata heredocs.
- **`%documentation <<'EOF'` is also literal**.
- **`%vibecode <<EOF` is literal** with the same override.
- **`%documentation <<(type)EOF` records the type annotation** for tooling; the block produces no observable runtime string, but the annotation is readable by tooling.

## Related

- [string](./) — the class every heredoc materializes into.
- [regular-expressions](regular-expressions) — the other Caspian-side surface under `string/`.
- [array § Open questions](https://puck.uno/documentation/requirements/built-in-classes/primitives/array/#open-questions) — whether `<<` doubles as an array-append operator, which would create a token conflict with the heredoc opener here. Open question owned by the array doc.
- [global-methods § `%documentation`](https://puck.uno/documentation/requirements/global-methods/#documentation) — the compile-time documentation method that consumes heredocs.
- [global-methods § `%vibecode`](https://puck.uno/documentation/requirements/global-methods/#vibecode) — the compile-time AI-readable-JSON documentation method; shorthand for `%documentation <<(vibecode)EOF ... EOF`.
