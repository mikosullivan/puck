# Method
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_functions_types_method",
	"role": "spec for the method type — a function bound to a receiver object. `%self` is the receiver; `%bucket` is the receiver's bucket; `%chain` is available same as in bare functions and closures. No captured outer scope. Like `function` and `closure`, `method name(...) ... end` is an expression that evaluates to the declared method object, so it can be captured and manipulated as a value. Method objects carry the shared function surface (`.call`, `.params`) plus a method-specific `.private` / `.private=` getter/setter pair; methods declared inside `instance` bodies additionally carry an `auto_run` getter/setter (spec'd on the instance page). Content TBD beyond the shape captured here.",
	"status": "draft — receiver-bound surface described; deeper semantics of dispatch, ownership, and role interactions to be filled in",
	"audience": "developers writing Caspian; parser implementers; class authors"
}}
~~~

A **method** is a function bound to a receiver object. The receiver — the object the method was called on — is the ambient surface inside the body.

Inside the body:

- **`%self`** — the receiver itself. `%self.some_method(...)` reaches sibling methods on the same receiver; `%self.@field` reads a specific bucket entry via `%self`.
- **`%bucket`** — the receiver's bucket hash. `%bucket['field']` reads and writes bucket entries directly.
- **`@field`** — shorthand for `%bucket['field']`. The most common way to read and write bucket state.
- **[`%chain`](https://puck.uno/documentation/requirements/caspian/chain/)** — the ambient capability channel, the same one bare functions and closures see. Per-frame and always reachable; carries `%now`, `%stdout`, `%net`, and everything else the caller granted.
- **No captured outer scope.** A method defined inside another function or class body does not see that outer scope's locals. The receiver surface (`%self`, `%bucket`, sibling methods) is what a method has instead. This is the difference from a closure — closures and methods each have their own environment, and neither can also be the other.

### Calling sibling methods

Sibling methods on the same receiver are reached through `%self`:

~~~caspian
class # captain
	method greet()
		$r = %self.rank
		return 'greetings from ' + $r
	end

	method rank()
		return @rank
	end
end
~~~

`%self.some_method` (or `%self.some_method(args)`) dispatches through the receiver, so it picks up any method declared on the same class as well as anything inherited. The dispatch is the same one an outside caller uses via `$obj.some_method` — no special short form for in-body calls.

## Method surface

Method objects add the following methods on top of the [shared function surface](https://puck.uno/documentation/requirements/caspian/functions/bare#method-surface) (`.call`, `.params`):

| Method | Purpose |
|---|---|
| `.private` | Read the `private` boolean. When `true`, calls from outside the receiver's own class body raise — the method is only reachable from within its own class. Full semantics are spec'd in the classes section. |
| `.private=` | Set the `private` boolean. `$m.private = true` marks the method as private; assigning `false` makes it callable from anywhere again. |

Methods declared inside an `instance` body additionally carry an `auto_run` getter/setter pair — see [instance § auto_run](https://puck.uno/documentation/requirements-old/caspian/classes/instance#auto-run) for the property, its semantics, and the one-per-body rule.

## return

Exits with `return $value` (bare keyword) or `%call.return $value`. Both raise the return exception targeted at this method's frame; the engine catches at the method boundary and hands the value back as the call's return value. See [exceptions § ReturnException](https://puck.uno/documentation/requirements/caspian/exceptions/#returnexception).

## When a function is a method

A function is a method when it's declared with the `method` keyword. Two declaration contexts:

**Class method.** Declared inside a `class ... end` body. The method is defined on the class and inherited by every instance:

~~~caspian
class # captain
	method rank()
		return @rank
	end
end
~~~

**Singleton method.** Declared with `method $obj.name` syntax, attached to a specific object instance. Sibling instances of the same class do not get the method — it lives on `$obj` alone:

~~~caspian
method $picard.rank
	return @rank
end
~~~

Both cases produce the same in-body surface: `%self`, `%bucket`, `@field`, no captured outer scope. Inside a singleton method's body, `%self` is the object the method was declared on (`$picard` in the example above).

`method` cannot appear anywhere else. A `method` declaration at the top level (with no `$obj.name` target), inside a bare function body, or inside a closure body raises. See [bare function](bare) and [closure](closure) for the other two types.

Separately from either declaration form, a first-class function value can be **applied** as a method on any object at the call site via `$obj.$fn` ([downloaded-methods](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods)). That mechanism doesn't use the `method` keyword — the underlying function was declared as a bare function or closure — but the applied call produces the same in-body surface, because the receiver-binding happens at the point of application.

## `method` returns the method object

Like [`function`](bare) and [`closure`](closure), `method` is an expression: `method name(...) ... end` evaluates to the method object it just declared. The two effects — declaring the method on the enclosing class (or on `$obj` for the singleton form) and producing the method value — happen together in one statement.

~~~caspian
class # captain
	$m = method rank()
		return @rank
	end
end
~~~

Inside the class body above, `rank` is declared on the class as a normal class method AND the method object is assigned to the local `$m`. Both effects happen from the single expression; the value captured at `$m` is the same object the class now has for `.rank`.

Capturing the value lets code hand the method to constructs that expect one. The [`instance` doc's `auto_run` section](https://puck.uno/documentation/requirements-old/caspian/classes/instance#auto-run) is the current motivating example: `$m.auto_run = true` on a captured method value flips a boolean property that changes how `instance` construction finishes.

## Related

- [classes/definition § Methods](https://puck.uno/documentation/requirements/caspian/classes/definition#methods) — how methods are declared inside a class body.
- [classes/downloaded-methods](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods) — the ad-hoc `$foo.$method` mechanism that turns any function into a method at the point of application.
- [object/methods](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods) — the cross-cutting `object` method namespace that every value carries.
