# Functions and closures
<!--index: 9-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_functions_and_closures",
	"role": "cover page for Caspian's two free-standing callable-definition forms — `function` (closed scope) and `closure` (captures outer scope). Method definitions inside classes are a related but distinct construct; those get their own spec under the classes doc.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Caspian has two free-standing callable-definition forms, distinguished by whether they see the enclosing scope:

- **[Functions](https://puck.uno/documentation/requirements/caspian/syntax/functions-and-closures/functions)** — self-contained; see only their parameters. No access to the enclosing scope.
- **[Closures](https://puck.uno/documentation/requirements/caspian/syntax/functions-and-closures/closures)** — capture the enclosing scope; can read (and write, when the scope is mutable) outer variables.

Both use the same call syntax and share the same return semantics — the last expression in the body is the return value; use `%call.return $value` for actual early exit.

## Methods

Methods — functions or closures defined inside a class — are covered separately under the classes spec. The keyword is `method` rather than `function` or `closure`; scope behavior otherwise mirrors the two forms above. Full spec lands when the classes doc is written.
