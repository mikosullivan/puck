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
%documentation('markdown') <<EOF
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
