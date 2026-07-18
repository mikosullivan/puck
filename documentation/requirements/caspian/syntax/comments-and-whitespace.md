# Comments and whitespace
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_comments_and_whitespace",
	"role": "spec for Caspian's comment syntax and whitespace rules. **Newline-non-significance is a general policy, not an absolute rule** — most of the time newlines are cosmetic and the parser figures out statement boundaries from context, but specific constructs (like heredocs) may require newline structure and are called out on the page that owns each construct. Covers: the `#` line-comment marker, the `%documentation` and `%vibecode` structured-documentation methods, the newline-non-significance policy itself, the semicolon-as-command-separator rule (semicolons always mark a divider between commands; redundant semicolons silently ignored), and the lexer's treatment of blanks and tabs.",
	"audience": "lexer implementers; parser implementers; developers writing Caspian"
}}
~~~

## Line comments

Line comments start with `#` and run to end of line. Whitespace outside string literals is cosmetic.

~~~caspian
# a line comment
$x = 1
$y = 2   # end-of-line comment
~~~

## Newlines are generally not significant

Newlines are **not required** to separate statements. The parser figures out statement boundaries from context — matched delimiters, keyword scopes, operator precedence, argument-list rules. Two statements on separate lines parse the same as two statements on one line without an explicit separator:

~~~caspian
&foo
&bar
~~~

parses identically to:

~~~caspian
&foo &bar
~~~

Continuation of an expression across a newline works from either side: a line ending in a binary operator (`|`, `+`, `.`, etc.) OR a line starting with a binary operator both mean "continue the previous expression":

~~~caspian
$result = &foo() |
	&bar

$result = &foo()
	| &bar
~~~

Both forms parse identically. Whichever reads more naturally in context is fine.

### The rule is not absolute

Newline-non-significance is a **general policy**, not an absolute rule. Specific constructs may require newlines to mark structure — [heredocs](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/string/heredocs) are one such case, where the terminator label must appear on its own line. Additional exceptions may emerge as language features are spec'd; each is called out on the page that owns the construct.

## Semicolons as command separators

`;` is a **command separator**. It always marks a divider between commands. Multiple semicolons in a row, or a semicolon on an otherwise-empty line, are silently ignored:

~~~caspian
&foo; &bar            # two commands, semicolon separates
&foo; ; ; &bar        # same — extra ;'s ignored
;;; &foo              # leading ;'s ignored, one command
&foo ;                # trailing ; ignored
~~~

Semicolons are never required — newlines and juxtaposition also serve as command separators. Use `;` when you want an explicit divider on the same line, or when the parser would otherwise be ambiguous.

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
- **Two statements on separate lines parse** — `$x = 1\n$y = 2` binds both variables.
- **Two statements on one line without separator parse** — `&foo() &bar()` parses as two statements.
- **Semicolon separates statements on one line** — `&foo(); &bar()` parses as two statements.
- **Multiple consecutive semicolons collapse to one separator** — `&foo() ;;; &bar()` parses as two statements.
- **Bare semicolon on its own line is a no-op** — `;\n$x = 1` parses; only binds `$x`.
- **Leading semicolons are ignored** — `;;;&foo()` parses as one statement.
- **Trailing semicolons are ignored** — `&foo();` parses as one statement.
- **Trailing operator continues an expression across newline** — `$x = $a +\n$b` binds `$x` to `$a + $b`.
- **Leading operator on next line continues an expression** — `$x = $a\n+ $b` also binds `$x` to `$a + $b`.
- **Newlines inside `()`, `[]`, `{}` are not significant** — multi-line calls, arrays, and hashes parse without regard to newline placement inside the delimiters.
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
