# Comments and whitespace
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_comments_and_whitespace",
	"role": "spec for Caspian's comment syntax and whitespace rules — the `#` line-comment marker, the `%documentation` and `%vibecode` structured-documentation methods, and the lexer's treatment of blanks, tabs, and newlines",
	"audience": "lexer implementers; developers writing Caspian"
}}
~~~

## Line comments

Line comments start with `#` and run to end of line. Whitespace is cosmetic outside string literals. Statements are separated by newlines — no terminator character.

~~~caspian
# a line comment
$x = 1
$y = 2   # end-of-line comment
~~~

## Structured documentation: `%documentation` and `%vibecode`

For longer or machine-readable documentation, use one of the two documentation methods. Both take a heredoc:

~~~caspian
%documentation <<(markdown)EOF
This routine looks up the current temperature at the given zip code.
Returns null if the lookup fails.
EOF

%vibecode <<EOF
{
	"purpose": "Look up the current temperature at the given zip code",
	"returns": "number (degrees Fahrenheit) or null on lookup failure"
}
EOF
~~~

Both are **always allowed** — no role or grant governs them — and both **produce no runtime artifact** the script can read back (pre-V1). They exist for tooling (documentation generators, syntax highlighters, AI readers) and are recorded in CaspianJ at parse time.

Full spec at [global-methods § `%documentation`](https://puck.uno/documentation/requirements/caspian/global-methods/#documentation) and [global-methods § `%vibecode`](https://puck.uno/documentation/requirements/caspian/global-methods/#vibecode).

## Testing

- **`#` at start of line comments to end of line** — `# hello\n$x = 1` parses; `$x` is bound to `1`; the comment is dropped.
- **End-of-line `#` comments to end of line** — `$x = 1 # trailing` binds `$x` to `1`; the trailing text is dropped.
- **Comment ends at newline, next line is code** — `# comment\n$y = 2` binds `$y` to `2`.
- **`#` inside a double-quoted string is a literal character** — `$s = "a # b"` binds `$s` to the six-character string `a # b`.
- **`#` inside a single-quoted string is a literal character** — `$s = 'a # b'` binds `$s` to the six-character string `a # b`.
- **`#` inside a heredoc is a literal character** — a heredoc body containing `# something` contains a literal `#` in the string value.
- **Comment-only file parses to no-op** — a file consisting solely of `# comment` lines parses successfully and produces no runtime effect.
- **Blank line between statements is ignored** — `$x = 1\n\n\n$y = 2` binds both variables.
- **Trailing whitespace at end of line is ignored** — a line with trailing spaces before the newline parses the same as one without.
- **Leading whitespace on continuation lines is cosmetic** — tabs and spaces used for indentation carry no meaning to the parser.
- **Tab and space are both accepted as whitespace** — `$x\t=\t1` and `$x = 1` both parse.
- **Statement separation is by newline, not by semicolon** — two statements on separate lines parse; no terminator character required.
- **`%documentation` heredoc parses at any scope** — `%documentation <<(markdown)EOF ... EOF` at top level parses without error.
- **`%vibecode` heredoc parses at any scope** — `%vibecode <<EOF ... EOF` at top level parses without error.
- **`%documentation` produces no runtime artifact** — no readable value is bound; a subsequent `%documentation.last` or similar read raises (surface not defined).
- **`%vibecode` produces no runtime artifact** — same as `%documentation`.
- **`%documentation` and `%vibecode` are always allowed** — no grant is required to call them in any role.
- **Unterminated heredoc raises at parse time** — a `%vibecode <<EOF` with no closing `EOF` fails to parse.
- **Heredoc label mismatch keeps reading** — a `%vibecode <<EOF` where the body contains `eof` (wrong case) does not terminate the heredoc.
- **Comment as first line of file** — `# header\n$x = 1` parses; `$x` is bound.
- **Comment as last line of file, no trailing newline** — `$x = 1\n# tail` parses (no trailing newline required after the comment).
- **Comment on its own line inside an expression is not supported** — placing a `# comment` line between the LHS and RHS of a multi-line expression is a parse error unless the expression syntactically continues.
- **Bare `#` with no text after is a valid empty comment** — `#\n$x = 1` parses.
