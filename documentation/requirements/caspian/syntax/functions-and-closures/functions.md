# Functions
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_functions",
	"role": "spec for Caspian's `function` keyword. Function scope — a function sees only its parameters, never the enclosing scope — is one of the core security features of the language; the doc leads with that. Also covers: how a function object is created and stored, how it's called (the .call method and the & short-form), and the class-defined & method that makes the short form work. Implicit-last-expression return.",
	"audience": "developers writing Caspian; parser implementers; anyone reasoning about Caspian's security model"
}}
~~~

A **function** is a first-class object in Caspian, just like a string or a hash. Like every object, a function has no inherent name — it lives at whatever storage slot references it (a variable, a hash entry, an argument being passed to another call, etc.). If two variables reference the same function object, both call sites invoke the same underlying thing.

## A function sees only its parameters

Inside a function's body, **caller-side local variables are invisible.** Whatever `$foo`, `$bar`, `$secret` the caller had in scope, the function has no way to reach. The only caller-side data the function can name is what it received through its parameter list.

This is **function scope**, and it's one of the core security features of Caspian: caller state doesn't leak into the callee unless the caller passed it explicitly. Wrap untrusted work in a function and hand it only the values you want it to see; whatever else was in the caller's scope is out of reach.

~~~caspian
$secret  = 'password123'
$greeting = 'hi'

function &greet($name)
	&puts $greeting + ', ' + $name    # error — $greeting is not visible here
	&puts $secret                     # error — $secret is not visible here either
	return null
end
~~~

### System methods stay visible — subject to role and chain

Function scope isolates **local variables** — not the always-on system-method surface. The `%`-prefixed names remain reachable inside a function's body, governed by role and chain rather than by scope:

- **`%chain`** always resolves to the current frame's chain. What's ON that chain depends on whether the call crossed a role boundary:
    - **Same-role call** — a function owned by the same role as the caller. The chain is inherited from the caller; whatever capabilities the caller had (say, `%chain.stdout`, `%chain.net`, `%chain.root`) are still reachable via `%chain` inside the callee.
    - **Cross-role call** — calling a function whose owning role is different from the caller's (e.g., a function that lives inside a downloaded object). The chain crosses a role boundary; only [default-granted surfaces](https://puck.uno/documentation/requirements/caspian/chain/#two-layers-of-grant) survive the crossing. Default-deny surfaces (`%chain.stdout`, `%chain.net`, `%chain.root`, `%chain.env`, `%chain.stdin`, `%chain.stderr`) are stripped from the callee's chain unless the caller explicitly grants them.
- **`%engine`** is visible from user-role frames — including user-role functions — since `%engine`'s gate is per-role, not per-scope. From any other role, `%engine` raises regardless of where you are.
- **`%self`** and **`%call`** are visible where they're contextually meaningful (inside a method for `%self`; inside any call body for `%call`).

Concrete example: a user-owned function can write to `%stdout` (assuming the host wired `%stdout` at all). A function owned by another role cannot, by default — `%chain.stdout` is default-deny across role boundaries. To let a cross-role function reach `%stdout`, the caller either passes it in as a parameter or grants it for the duration of the call:

~~~caspian
# Pass %stdout in explicitly.
&some_fn %stdout, ...

# Or grant %chain.stdout across the role boundary for the duration of the block.
%chain.stdout.grant do
	&some_fn ...
end
~~~

Full spec for the grant model: [chain/grant-revoke](https://puck.uno/documentation/requirements/caspian/chain/grant-revoke).

### Two mechanisms, complementary

- **Function scope** isolates the callee from caller-side local variables. Applies to every function call.
- **The chain-grant model + role boundaries** govern which ambient capabilities the callee can reach through `%chain`. Cross-role calls strip default-deny surfaces automatically; same-role calls inherit the full chain.

For a fully sandboxed cross-role call, most of the isolation happens by default. For a same-role call, the caller has to work harder — revoke what shouldn't be reachable via `%chain`, pass only what the callee needs.

### Passing capabilities in explicitly is still a good habit

Even when a capability IS ambient, passing it in through a parameter often reads better and makes intent obvious:

~~~caspian
function &write_log($fs, $message)
	return $fs.write('log.txt', $message)
end

&write_log %chain.root, 'starting up'
~~~

The function's signature announces what it needs; readers don't have to scan the body for ambient references. This is style, not a language rule — the function could also have written `%chain.root.write('log.txt', $message)` and gotten the same result if `%chain.root` was granted at the call site.

### Reach for closures when isolation is the wrong tool

When a function genuinely needs access to enclosing state — the point is to close over a variable, not to be isolated — the right construct is a [closure](https://puck.uno/documentation/requirements/caspian/syntax/functions-and-closures/closures). Closures are functions' companion, sharing everything else but deliberately opting out of the local-variable isolation. Use functions by default; reach for closures only when you have a specific reason.

## Creating and storing a function

The primitive form is an expression that produces a function object, assigned into a variable:

~~~caspian
$foo = function($tgt)
	&puts $tgt
	return null
end
~~~

That expression makes a function and stores it at `$foo`. `$foo` isn't the function's "name" — it's just where the function happens to live. Doing `$bar = $foo` makes `$bar` point at the same function object.

Caspian also offers a familiar-looking sugar for the common case of defining and naming in one step:

~~~caspian
function &foo($tgt)
	&puts $tgt
	return null
end
~~~

This does **exactly the same thing** as the primitive form. The parser desugars it to `$foo = function($tgt) ... end`. Nothing about the resulting function is different; it just reads more like function definitions in other languages.

## Calling a function

Function objects have a `.call` method. The honest primitive form for invoking one is:

~~~caspian
$foo.call 'bar'
~~~

That works, but writing `.call` at every call site would be tedious, so Caspian provides `&` as a short form:

~~~caspian
&foo 'bar'
~~~

### What `&` actually is

`&` is not a language-level "call the function" operator — it's a **method name**, the same way `==`, `+`, `<`, and `[]` are method names. Any class can define a `&` method, and `&foo args` invokes whatever `&` method the object at `foo` defines. The `Function` class defines its `&` to call `.call` internally, which is why `&foo 'bar'` reaches the function body.

The generalization: many classes have a **primary action** — the thing the class exists to do. `&` names that primary action. For a function, the primary action is invocation. Other classes can define `&` however they like — an event class's `&` might fire the event; a request class's `&` might send it; anything with an obvious "point of the thing" can hang it on `&` so call sites read cleanly.

## Return value

Three ways a function can return a value — pick whichever reads best in context. They're equivalent in effect.

### Implicit: the last expression

The last expression in the body is the return value — no explicit `return` needed:

~~~caspian
function &square($n)
	$n * $n           # this expression's value is what &square returns
end
~~~

The common style. If the function's job is to compute one thing, let the final expression BE that thing and skip the ceremony.

### Explicit: the `return` keyword

For early exit or when the "here's my answer" step is worth being explicit about:

~~~caspian
function &square($n)
	return $n * $n
end

function &safe_divide($a, $b)
	if $b == 0
		return null
	end

	return $a / $b
end
~~~

`return` exits the function immediately with the given value. Any statements after the `return` in the same block don't run.

### System-method form: `%call.return`

`%call.return $value` does exactly the same thing as `return $value` — it's the underlying system-method form of the same operation:

~~~caspian
function &square($n)
	%call.return $n * $n
end
~~~

The keyword `return` is sugar for `%call.return`. The keyword reads more naturally in most code; the system-method form is available when you want to name the mechanism directly (or in a context where the `return` keyword has been rebound as a DSL entry).
