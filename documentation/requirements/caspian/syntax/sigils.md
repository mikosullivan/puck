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

Every identifier that names something the runtime tracks is **prefixed with a sigil**. The prefix character says what kind of name it is; the rules for reading the body of the name are the same across all sigils (letters, digits, underscore; case-sensitive). Sigils are mutually exclusive within an identifier — `$&foo` is not a name. Reserved keywords (like `if`, `class`, `do`) are unsigiled words the parser recognises directly.

## `$` — local variable or parameter

`$name` names a local variable or a function parameter.

Locals are scoped to the enclosing function, closure, or method body. They come into existence on first assignment and disappear when the enclosing frame returns:

~~~caspian
$greet = function($name)
	$rank = 'ensign'
	return $rank + ' ' + $name
end
~~~

Parameters use the same sigil at the declaration site (`$name` above) — mechanically they behave like locals the caller has already bound.

## `&` — primary call

`&name` invokes the primary operation of the object bound to `name`. What that operation *is* depends on the object's class:

- **On a function object**, `&` is aliased to `.call`. The Function class ships with this alias, so `&greet 'picard'` and `$greet.call 'picard'` do exactly the same thing. This is the case most Caspian code hits day-to-day.
- **On any other class**, `&` invokes whatever method the class designates as the primary operation. A widget class might make `&` render the widget; a counter class might make `&` increment; a query class might make `&` run the query. The class author picks the mapping in the class definition — see [classes/definition](https://puck.uno/documentation/requirements/caspian/classes/definition) for how to set the `&` method for a class.

The same sigil is used at the **definition site**. `function &greet` binds a new function to the identifier `greet`, and `method &foo` inside a class body declares a method (both matching the "this name is callable" reading):

~~~caspian
function &greet($name)
	return 'hello, ' + $name
end

&greet 'picard'
~~~

See [calling](tag:calling) for full call-site syntax when the underlying object is a function.

## `@` — bucket entry

`@field` names an entry in the current object's bucket — shorthand for `%bucket['field']`. Only meaningful inside a method body, where `%bucket` exists (see [method](https://puck.uno/documentation/requirements/caspian/functions/method)); using `@field` in a bare function or closure body raises.

Read and write use the same form; assignment context is what distinguishes them:

~~~caspian
class # captain
	method rank()
		return @rank
	end

	method promote($new_rank)
		@rank = $new_rank
	end
end
~~~

`@rank` is the everyday way to touch object state. The alternatives `%self.@rank` and `%bucket['rank']` both work and mean the same thing, but read as noise for the common case.

## `%` — system method

`%name` names a system method — a surface the engine provides. `%self`, `%chain`, `%engine`, `%puck`, `%call`, `%bucket`, `%stdout`, `%now`, `%net`, and so on. The full list lives under [global-methods](https://puck.uno/documentation/requirements/caspian/global-methods/).

Two properties matter:

- **Always available where reachable.** Every `%X` surface either resolves (returns the runtime value) or raises with a clear "surface not granted" — never returns `null` for missing.
- **Never user-defined.** A Caspian program cannot introduce a new `%X` name. The sigil is reserved to the engine; the language surface is closed.

Most `%X` names are sugar for `%chain.X` — `%now` is `%chain.now`, `%net` is `%chain.net`, and so on. See [%chain](https://puck.uno/documentation/requirements/caspian/chain/) for the full mechanism, including capability propagation and role boundaries. A small number of `%X` names live outside `%chain` (`%call`, `%engine`, `%self`, `%bucket`); those pages spell out where each one hangs.

## Testing

- **`$name` binds a local variable** — `$x = 5; $x` returns `5`.
- **`$name` on first assignment declares the local** — `$x = 5` in an empty scope creates `$x`.
- **Reading undeclared `$name` raises** — `$never_set` at the top of a fresh scope raises undeclared-variable.
- **Parameter uses `$` sigil at declaration site** — `function &f($p); $p; end` declares `$p` as a parameter.
- **Parameter reads inside body without special sigil** — the parameter is read as `$p`, same as any local.
- **Bare `name` (no sigil) is a parse error for a variable read** — `x + 1` where `x` is not a keyword fails to parse.
- **`&name` calls the primary operation of a function value** — `$greet = function(); 'hi'; end; &greet` returns `'hi'`.
- **`&name` and `$name.call` are equivalent for function values** — both produce identical CaspianJ / behavior.
- **`&name` on a non-callable raises** — `$x = 5; &x` raises (no primary-call surface on Number).
- **`&name` on a class calls the class's designated primary operation** — a widget class whose primary is `render` runs `render` on `&widget`.
- **Definition site uses `&`** — `function &greet` and `method &foo` both parse; without `&` they are parse errors.
- **`@field` reads bucket entry inside a method** — `@x` inside a method returns the current instance's `x` bucket entry.
- **`@field = value` writes bucket entry inside a method** — updates the current instance's `x`.
- **`@field` outside any method raises** — a top-level `@x` raises (no `%bucket` in that scope).
- **`@field` inside a bare function raises** — bare `function` bodies do not have `%bucket`.
- **`@field` inside a closure raises** — closure bodies do not have `%bucket`.
- **`%name` reads a system method** — `%stdout` returns the stdout surface (or raises "not granted" if the role forbids).
- **`%name` cannot be user-defined** — attempting to write `%foo = 1` is a parse error (`%` on LHS of `=` is not a valid target).
- **`%name` never returns null for missing surface** — a missing surface either resolves or raises with "not granted"; never returns `null`.
- **Bare `%X` shortcut resolves to `%chain.X`** — `%now` and `%chain.now` produce the same value.
- **Two sigils on same identifier is a parse error** — `$&foo` fails to parse.
- **Sigil with no identifier body is a parse error** — bare `$` with no name fails to parse.
- **Identifiers are case-sensitive** — `$foo` and `$Foo` are distinct names.
- **Identifiers accept letters, digits, underscore** — `$abc_123` parses as one name.
- **Identifier starting with a digit is a parse error** — `$1foo` fails to parse.
- **Reserved keywords are not sigiled** — `if`, `class`, `do`, `end`, `while`, `until`, `return` all parse as keywords without any sigil.
- **Sigil on a keyword is invalid** — `$if` is a parse error (or if permitted, does not invoke keyword semantics).
