# Trailing commas

<span class="tag">syntax</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_trailing_commas",
	"role": "spec for where a trailing comma is legal in Caspian source. Rule: a trailing comma is allowed ONLY when the comma-separated list is delimited by brackets (`[]`), braces (`{}`), or parens (`()`). Paren-less call positions — bareword-call args (`field :name, class: :string`), bareword-amp statement calls (`&foo 1, 2`), and pipe-RHS paren-less calls (`| &sort 'asc'`) — reject a trailing comma and raise `trailing comma allowed only inside \\`[]\\`, \\`{}\\`, or \\`()\\``. Separate but related: a comma at end-of-line followed by more source on the next line is a line-continuation signal (same as trailing `|` / `|&`), not a trailing comma — the parser folds the next line into the same statement, so a paren-less multi-line arg list works cleanly. Delimiters mark the developer's explicit boundary; without them, a stray comma with nothing after is more likely a mistake than a formatting choice.",
	"audience": "developers writing Caspian; parser implementers deciding when to accept vs. reject a comma-terminated list"
}}
~~~

A **trailing comma** — a comma with no argument following it before the list's closing delimiter — is a common formatting convenience: it lets every entry in a multi-line list end with a comma, which keeps diffs clean when entries are added or removed.

Caspian allows a trailing comma **only inside brackets, braces, or parens**. Every context that has a matched delimiter around a comma-separated list accepts one:

~~~caspian
$arr = [1, 2, 3,]                                # array literal
$hash = {a: 1, b: 2, c: 3,}                      # hash literal
&foo(1, 2, 3,)                                   # paren-form bwc call
$obj.method('x', 'y',)                           # method call
$obj.method(name: 'picard', rank: 'captain',)    # method call with kwargs
$arr[0, 1, 2,]                                   # multi-key subscript
%(url, kwarg: 'x',)                              # fetch lookup
~~~

## Paren-less contexts reject a trailing comma

When the same list of args isn't wrapped in a delimiter — the paren-less forms of bareword calls, bareword-amp statement calls, and pipe-RHS paren-less calls — a trailing comma raises. Same message in every case: `trailing comma allowed only inside [], {}, or ()`.

~~~caspian
&foo 1, 2, 3,                       # RAISES — paren-less &-BWC statement
field :name, class: :string,        # RAISES — paren-less bareword-call
$x = &foo | &sort 'asc',            # RAISES — pipe-RHS paren-less
~~~

The fix in each case is to add the delimiter you meant:

~~~caspian
&foo(1, 2, 3,)
field(:name, class: :string,)
$x = &foo | &sort('asc',)
~~~

## Comma-plus-newline is a line-continuation signal

A comma at end-of-line followed by more source on the next line **is not a trailing comma** — the parser reads it as a line-continuation signal, folding the next line into the same statement. Programmers already know this from most languages: a line ending in `,` says "I'm not done." Same shape as the trailing `|` / `|&` pipe-continuation rule.

Both forms below parse identically:

~~~caspian
&foo 'x',
	&bar
~~~

~~~caspian
&foo 'x', &bar
~~~

The trailing-comma error only fires when the comma really is the last thing — no further content on any subsequent line. `&foo 'x',` as the whole statement raises; `&foo 'x',\n\t&bar` reads as one call with two args.

## Rationale

Delimiters mark the developer's explicit boundary of the list. Inside a `[...]` or `(...)`, the parser knows where the list starts and ends — a trailing comma is unambiguous formatting, and the developer opted into the delimiters. In a paren-less context, the parser is already inferring the list's edges from a mix of whitespace, statement terminators, and operator precedence — a stray comma there is much more likely a typo than a deliberate choice, so refusing to parse it catches the mistake at the point it was made.

The rule is symmetric across every bracket kind — no special-casing per container type — and applies uniformly to positional args, kwargs, hash entries, array elements, and subscript keys.

## Related

- [comments-and-whitespace](https://puck.uno/requirements/syntax/comments-and-whitespace) — the general newline / whitespace policy this rule sits inside.
