# Sigils
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_sigils",
	"role": "spec for the four sigils that prefix Caspian identifiers ($ & @ %). Each sigil says what kind of name it is; identifier body rules are shared across all four.",
	"sigils": ["$", "&", "@", "%"],
	"audience": "lexer/parser implementers; developers writing Caspian; anyone learning how to read Caspian code"
}}
~~~

Every identifier that names something the runtime tracks is **prefixed with a sigil**. The prefix character says what kind of name it is; the rules for reading the body of the name are the same across all sigils (letters, digits, underscore; case-sensitive).

| Sigil | Names | Example |
|---|---|---|
| `$` | A local variable or parameter | `$name`, `$widget` |
| `&` | A function reference — used both to define and to call | `function &greet`, `&greet 'hi'` |
| `@` | An entry in the current object's bucket (instance data) | `@name` reads `%bucket['name']` |
| `%` | A system method — always available, never user-defined | `%self`, `%chain`, `%engine`, `%puck` |

Sigils are mutually exclusive within an identifier — `$&foo` is not a name. Reserved keywords (like `if`, `class`, `do`) are unsigiled words the parser recognises directly.
