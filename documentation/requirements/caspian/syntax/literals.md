# Literals
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_literals",
	"role": "spec for Caspian's literal forms — numbers, strings (single- and double-quoted), booleans, null, arrays, and hashes",
	"audience": "lexer/parser implementers; developers writing Caspian"
}}
~~~

~~~caspian
$count   = 42
$price   = 19.99
$message = "hello, world"
$single  = 'single quotes work too'
$flag    = true                   # or false
$empty   = null                   # written 'null' as a bare word
$items   = [1, 2, 3]
$table   = {name: 'alice', age: 30}
~~~

Strings support the usual escapes (`\n`, `\t`, `\'`, `\"`, `\\`). Hash keys written as bare identifiers become string keys — `{name: ...}` is `{'name': ...}`.
