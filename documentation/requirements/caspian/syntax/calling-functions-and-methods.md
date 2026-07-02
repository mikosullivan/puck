# Calling functions and methods
<!--index: 10-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_calling_functions_and_methods",
	"role": "spec for Caspian's call syntax — the `&name args` form for stored functions, receiver-first method calls, keyword arguments, and splat expansion. Full parameter mechanics live in a separate sub-page.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Call a stored function with `&name args` (parens optional if the return value is unused, required when it isn't):

~~~caspian
&greet 'alice'
$result = &compute(10, 20)
~~~

Method calls use the receiver-first form:

~~~caspian
$obj.method_name(arg1, arg2)
$obj.method_name arg1, arg2
~~~

Keyword arguments use `name: value` syntax. Positional and named can mix; all positional args must come before the first named arg.

~~~caspian
&fetch 'https://example.com', timeout: 30, retries: 3
~~~

Splat expansion:

~~~caspian
$args = ['alice', 'captain']
&greet *$args              # expands positionally

$opts = {timeout: 30}
&fetch 'https://example.com', **$opts   # expands as named
~~~

Full parameter mechanics (metadata, optionality, `*rest`, `**opts`, lazy parameters, class constraints) get their own sub-page.
