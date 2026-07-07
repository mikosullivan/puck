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

See [functions/call](https://puck.uno/documentation/requirements/caspian/functions/call) for full call-site syntax when the underlying object is a function.

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
