# Method
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions_method",
	"role": "spec for the method type — a function bound to a receiver object. `%self` is the receiver; `%bucket` is the receiver's bucket; `%chain` is available same as in bare functions and closures. No captured outer scope. Like `function` and `closure`, `method name(...) ... end` is an expression that evaluates to the declared method object, so it can be captured and manipulated as a value. Method objects carry the shared function surface (`.call`, `.params`) plus a method-specific `.private` / `.private=` getter/setter pair. Content TBD beyond the shape captured here.",
	"status": "draft — receiver-bound surface described; deeper semantics of dispatch, ownership, and role interactions to be filled in",
	"audience": "developers writing Caspian; parser implementers; class authors"
}}
~~~

A **method** is a function bound to a receiver object. The receiver — the object the method was called on — is the ambient surface inside the body.

Inside the body:

- **`%self`** — the receiver itself. `%self.some_method(...)` reaches sibling methods on the same receiver; `%self.@field` reads a specific bucket entry via `%self`.
- **`%bucket`** — the receiver's bucket hash. `%bucket['field']` reads and writes bucket entries directly.
- **`@field`** — shorthand for `%bucket['field']`. The most common way to read and write bucket state.
- **[`%chain`](https://puck.uno/requirements/chain/)** — the ambient capability channel, the same one bare functions and closures see. Per-frame and always reachable; carries `%stdout`, `%net`, `%fetch`, and everything else the caller granted.
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

`%self.some_method` (or `%self.some_method(args)`) dispatches through the receiver, so it picks up any method declared on the same class as well as anything inherited. It uses the same dispatch mechanism an outside caller uses via `$obj.some_method` — no special short form for in-body calls — with one meaningful difference: **the calling frame is inside the class body, so private methods are reachable.**

The engine's private-method check consults [`%call.method_class`](https://puck.uno/requirements/global-methods/call/#call-method-class) at dispatch time. When a sibling method calls `%self.private_helper()`, `%call.method_class` in that sibling's frame is the same class that carries `.private_helper`, so the call is allowed. When outside code calls `$foo.private_helper()`, `%call.method_class` in that frame is a different class (or `null`), and the dispatch raises. The rule is uniform: **access is checked at dispatch time against the current frame, not against the reference**. Capturing `%self` and returning it (`method &me() return %self end`) doesn't grant private access to whoever receives the reference — the calling frame's `%call.method_class` still governs.

Full spec of the private-method mechanism: [classes/definition § Private methods](https://puck.uno/requirements/classes/definition/#private-methods).

## Method surface

Method objects add the following methods on top of the [shared function surface](https://puck.uno/requirements/functions/bare#method-surface) (`.call`, `.params`):

| Method | Purpose |
|---|---|
| `.private` | Read the `private` boolean. When `true`, calls from outside the receiver's own class body raise — the method is only reachable from within its own class. |
| `.private=` | Set the `private` boolean. `$m.private = true` marks the method as private; assigning `false` makes it callable from anywhere again. |

The `autorun` convention on `instance` bodies (see [instance § autorun](https://puck.uno/requirements/classes/instance#autorun)) is method-name-based — nothing on the method-object surface changes. A method named `autorun` inside `instance ... end` is just a regular method with that particular name; the `instance` construct's runtime checks for that name and invokes it after `init`.

**Setting `.private` at declaration time.** Inside a class body, the `private` DSL bare-word command is the idiomatic form:

~~~caspian
class # widget
	private method helper()
		return @count * 2
	end
end
~~~

`method helper() ... end` produces the method object; `private` receives it, sets `.private = true`, and returns it. The class-body DSL spec is on [classes/definition § Private methods](https://puck.uno/requirements/classes/definition#private-methods). The `.private = true` assignment form remains available for cases where the property should be set on a captured value after the fact.

## return

Exits with `return $value` (bare keyword) or `%call.return $value`. Both raise the return exception targeted at this method's frame; the engine catches at the method boundary and hands the value back as the call's return value. See [exceptions § ReturnException](https://puck.uno/requirements/exceptions/#returnexception).

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

Separately from either declaration form, a first-class function value can be **applied** as a method on any object at the call site via `$obj.$fn` ([downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods)). That mechanism doesn't use the `method` keyword — the underlying function was declared as a bare function or closure — but the applied call produces the same in-body surface, because the receiver-binding happens at the point of application.

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

Capturing the value lets code hand the method to constructs that expect one — hold it for later invocation, thread it through a lookup table, apply a modifier that returns a mutated method object, etc.

## Testing

- **`%self` is the receiver** — `method greet() return %self end` invoked as `$obj.greet` returns `$obj`.
- **`@field` reads bucket entry** — after `.new(name: 'p')`, a method body reading `@name` returns `'p'`.
- **`@field` writes bucket entry** — a method body assigning `@name = 'x'` mutates the receiver's bucket.
- **`%bucket['field']` equivalent to `@field`** — `%bucket['name']` and `@name` produce and mutate the same slot.
- **Sibling method call** — `%self.sibling()` inside a method body dispatches to the receiver's `.sibling` method.
- **No captured outer scope** — a method defined inside another function's body does not see that function's locals.
- **`%call.role` is the caller's role** — a method invoked cross-role reads `%call.role` as the caller's role, not the method's role.
- **Method runs as its class's role** — a method's ambient role is the class's owning role, not the caller's.
- **Class method inherited by instances** — after `class # foo; method greet(); end; end`, every instance responds to `.greet`.
- **Singleton method attached to specific instance** — `method $picard.rank; return 'admiral'; end` makes `$picard.rank` work but sibling instances of the same class don't get it.
- **`method` at top level raises** — a `method` declaration outside a class body and without a `$obj.name` target errors.
- **`method` inside a bare function body raises** — `function() method foo() end end` errors.
- **`method` inside a closure body raises** — `closure() method foo() end end` errors.
- **`.private = true` blocks external call** — after `$m.private = true`, an outside caller invoking the method raises.
- **`.private = false` restores external call** — after `$m.private = false`, the method is callable again.
- **Private method callable from sibling** — a private method invoked via `%self.` from another method of the same class works.
- **`method name(...) ... end` evaluates to the method object** — inside a class body, `$m = method foo() end` captures the method value while also declaring `foo` on the class.
- **`.call` on a method object invokes it** — `$m.call` with `%self` bound to the receiver produces the same result as invoking through the receiver.
- **`.params` on a method object** — same shape as bare functions; keyed by private name.
- **Method chain on returned receiver** — `$obj.a().b()` runs `.a` then `.b` on `.a`'s return value.
- **`return $value` exits the method** — `method foo() return 'x'; puts 'no' end` returns `'x'` without executing the `puts`.
- **`%call.return $value` exits the method** — same effect as bare `return` when the immediate frame is the method.
- **Ad-hoc application via `$obj.$fn`** — an externally-defined bare function applied as `$obj.$fn` runs with `%self = $obj`.
- **Downloaded methods have full `%bucket` access** — an applied function reads `@field` directly on the receiver.
- **Ad-hoc application by non-user role requires ownership** — see [downloaded-methods § receiver-ownership rule](https://puck.uno/requirements/classes/downloaded-methods#the-receiver-ownership-rule); the applied call raises when the current role neither owns the receiver nor is user.
- **`autorun` is name-based, not property-based** — an `instance` body's runtime looks for a method literally named `autorun` after `init`. Methods carry no `.autorun` property.

## Related

- [classes/definition § Methods](https://puck.uno/requirements/classes/definition#methods) — how methods are declared inside a class body.
- [classes/downloaded-methods](https://puck.uno/requirements/classes/downloaded-methods) — the ad-hoc `$foo.$method` mechanism that turns any function into a method at the point of application.
- [object/methods](https://puck.uno/requirements/built-in-classes/object/methods) — the cross-cutting `object` method namespace that every value carries.
