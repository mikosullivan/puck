# Instance

~~~vibecode
{"vibecode": {
	"doc": "instance_keyword",
	"role": "spec for the `instance` keyword — a Caspian construct that builds a single object directly using the same body shape as a class definition. Two forms: `instance ... end` constructs with no args; `instance(args...) ... end` passes the args through to the new object's `&init`. Sugar for `$cls = class ... end; $foo = $cls.new(args...)`. Includes the design-pattern framing (ad-hoc instances), guidance on when to use it, worked examples, and the `auto_run` directive that runs a method on the constructed object and returns its value instead of the object itself (instance-only; is really a boolean property on the method object; three equivalent ways to set it — `auto_run :name` symbol directive, inline `auto_run method name(...) ... end` form, or direct `$m.auto_run = true` assignment on a captured method value; multiple `auto_run` directives raise at compile time).",
	"status": "active spec",
	"audience": "Caspian programmers; engine implementers",
	"related": ["index.md (class definitions)"]
}}
~~~

The **`instance`** keyword builds a single object directly, without going through a separate class declaration. The body uses the same shape as `class ... end` — fields, methods, inheritance — and everything in the body populates the shadow class of the new object.

The object built this way is sometimes called an **ad-hoc instance**: a one-off object made directly for a specific situation, without the ceremony of declaring a class first. The pattern is realized in code via the `instance` keyword but exists conceptually independent of any specific syntax — it's whatever results from "start with a bare object, add methods and inheritance to its shadow, use it, move on."

---

## Forms

The keyword has two forms, distinguished by whether arguments are passed.

### Bare form

```
instance ... end
```

Builds the object with no constructor arguments, returns it. Field defaults populate the bucket; no `&init` arguments are passed.

~~~caspian
$config = instance
	field :host, class: 'string', default: 'localhost'
	field :port, class: 'integer', default: 8080

	method dsn()
		'tcp://' + @host + ':' + @port
	end
end

%stdout.puts $config.dsn   # tcp://localhost:8080
~~~

`$config` is the constructed object. Methods and fields are reachable through it as on any object.

### With init args

```
instance(args...) ... end
```

Builds the object with constructor arguments, passing them through to the new object's `&init` method.

~~~caspian
$config = instance('localhost', 8080)
	method init(@host, @port)
	end

	method dsn()
		return 'tcp://' + @host + ':' + @port
	end
end

%stdout.puts $config.dsn   # tcp://localhost:8080
~~~

The args land in `&init` like any normal method call. The example uses the [`@param` bucket-binding shorthand](../syntax/parameters#bucket-binding-parameters) — `init(@host, @port)` stores each parameter directly into the bucket — but `init` is otherwise a regular method and any parameter shape it accepts works (positional, keyword, defaults, lazy, etc.).

Keyword args are passed the same way:

~~~caspian
$config = instance(host: 'localhost', port: 8080)
	method init(@host, @port)
	end
end
~~~

If the body has no `&init`, calling `instance(args...)` with args raises — same as calling `.new(args...)` on a class with no matching `&init` would.

---

## Body semantics

The body is structurally identical to a class definition body. Whatever is legal in a `class ... end` block is legal in an `instance ... end` block, and means the same thing — except it all populates the shadow class of one specific object rather than producing a reusable class.

Concretely:

- **Field declarations** (`field :name, class: ..., default: ..., required: ...`) work as in classes. Defaults are applied to the new object's bucket via the implicit `.new()` call. `required: true` with no default would error at construction since the implicit `.new()` is called without args (use a class with an explicit `.new(...)` if you need required-but-no-default fields).
- **Methods** (`method name(...) ... end`) are defined on the shadow class. Calling them on the new object dispatches normally.
- **Inheritance** (`inherits: [...]`) is supported. The shadow class inherits from the listed classes; methods not defined locally fall back through the inheritance chain just as for any other class.
- **Inline label.** Per the [class inline label convention](index.md), `instance # short label` carries a brief readable label after the keyword. Useful since the object, like an anonymous class, has no name to identify it.

---

## `auto_run`

A method declared inside an `instance` body carries a boolean `auto_run` property, default `false`. (Methods declared inside a `class` body or as singleton methods on an object do not — the property is specific to methods that come out of `instance`.) When the `instance` is constructed, if any of its methods has `.auto_run = true`, that method is invoked on the new object and **the method's return value is what `instance` produces** — the object itself is discarded.

~~~caspian
$dsn = instance('localhost', 8080)
	method init(@host, @port)
	end

	method dsn()
		return 'tcp://' + @host + ':' + @port
	end

	auto_run :dsn
end
~~~

`$dsn` above holds the string `'tcp://localhost:8080'`, not the constructed object. The build-and-use flow collapses into a single expression: `instance` constructs the object, calls `.dsn` on it, and hands back the result.

**Instance-only.** `auto_run` matters inside `instance` bodies and has no counterpart in `class` construction. A class doesn't run on its own — it produces instances, and each caller of `.new` decides what to do with the result. `instance ... end` is a one-shot construction, so "run this method and return its value" is meaningful in a way it isn't for a class-plus-`.new` sequence.

**When it fits.** Any place where a script wants "build this ad-hoc object, use it once, keep only the result":

- Computed values that need a small amount of object state to derive (URL builders, formatters, structured summaries).
- One-off pipeline stages where the object exists purely to package the computation.
- Config-and-run helpers where the object's whole purpose is a single output.

**When it doesn't fit.** If code outside the `instance ... end` block needs to reach back into the object, or if the object will be used more than once, don't set `auto_run` — construct the instance normally and drive it from the outside.

**Interaction with `init`.** `init` runs first (as it does on any construction). The auto-run method runs next, on the fully-initialized object, and sees whatever `init` set up in the bucket.

### Setting `auto_run`

Three equivalent forms — all three set the same underlying `.auto_run` property on the method object. Use whichever reads best.

**Symbol.** The body-level `auto_run :name` directive resolves the named method and sets its `.auto_run` to `true`. The named method must be declared in the body (or inherited); a missing name raises at `instance` evaluation time.

~~~caspian
auto_run :dsn
~~~

**Inline method value.** Because `method name(...) ... end` is a declaration that also evaluates to the method object, prefixing it with `auto_run` sets `.auto_run = true` on the resulting value in the same expression:

~~~caspian
$result = instance()
	auto_run method foo()
		return 'result'
	end
end
~~~

The method is declared on the body as `foo` (same as if it appeared standalone) and its `.auto_run` is set to `true` in one step.

**Direct property assignment.** Because `method name(...) ... end` returns the method value, you can capture it and set the property yourself:

~~~caspian
$dsn = instance('localhost', 8080)
	method init(@host, @port)
	end

	$m = method dsn()
		return 'tcp://' + @host + ':' + @port
	end

	$m.auto_run = true
end
~~~

Useful when the property should be set conditionally, or when the setting has to happen after the declaration for any other reason.

The auto-run method must accept an empty argument list — the runtime invokes it with no arguments (the arguments the caller passed to `instance` go to `&init`, not to the auto-run method).

**Multiple methods with `auto_run = true`.** Raise. If a body would produce two methods both marked auto-run, the parser rejects it when it can see the conflict statically (two `auto_run :name` directives, or two `auto_run method ...` inline forms). When one or both settings happen via direct property assignment and the conflict isn't visible at parse time, the engine raises at `instance` evaluation time instead. Either way: at most one method may have `auto_run = true` per body.

---

## What it desugars to

`instance` is sugar. Conceptually:

~~~caspian
$foo = instance
	# body
end
~~~

is equivalent to:

~~~caspian
$_cls = class
	# body
end
$foo = $_cls.new()
~~~

And the with-args form:

~~~caspian
$foo = instance($arg1, $arg2)
	# body
end
~~~

is equivalent to:

~~~caspian
$_cls = class
	# body
end
$foo = $_cls.new($arg1, $arg2)
~~~

The anonymous class isn't kept around past construction (no variable holds it; nothing else can reach it). Everything the body declares ends up on the new object's shadow.

**With `auto_run`.** When the body includes an `auto_run :name` directive, the desugar has one extra step: after `.new`, the object's `.name` method is invoked and its return value becomes the value of the whole expression.

~~~caspian
$result = instance($arg1, $arg2)
	# body
	auto_run :run
end
~~~

is equivalent to:

~~~caspian
$_cls = class
	# body (minus the auto_run directive)
end
$_obj = $_cls.new($arg1, $arg2)
$result = $_obj.run()
~~~

---

## What an ad-hoc instance is

- **Conceptual, not technical.** "Ad-hoc instance" is a design-pattern label, not an engine concept. Nothing in Caspian's runtime cares whether an object was built this way; the resulting object is structurally identical to one built through any other path.
- **Starts bare, gets built up.** Conceptually, the developer instantiates "object" itself — an empty thing with no methods and no inherited classes — and then adds custom behavior to its shadow. The `instance` keyword does this in one block, but the same outcome could be reached by creating a bare object and using `.object.classes.add` plus `method $obj.name() ... end` step by step.
- **Singleton-spirited.** Like a singleton, it's one of its kind. Unlike a singleton, there's no global registry, no convention for finding it later — it lives wherever the variable holding it lives, and when that variable goes out of scope, the object goes with it.

---

## Use cases

### When to reach for one

The canonical case: a developer is writing a custom script for one specific situation and doesn't want the baggage of class declaration. Examples of that shape:

- **A configuration object** assembled for this run of this script. Specific values, specific methods, no need to publish it as a type.
- **A bespoke handler / actor / agent** that exists only inside one function or one script. Defines its behavior inline; nobody outside the script ever sees it.
- **A test fixture** that needs tailored behavior for one assertion. Local to the test, dies with the test.
- **A module-global "the X"** — the logger, the registry, the connection pool — when there really is only one of it and inventing a class to make one feels like overhead.
- **An object factory.** Wrap `instance ... end` in a function and each call constructs a fresh object with its own bucket state, using args flowed through `&init` — a clean way to produce tailored objects on demand without needing a named class. Especially good when the shape is fixed and only the state varies per call; `auto_run` also lets the factory return a computed value instead of the object.

What unites these: **the object is one-of-a-kind by intent** (or, in the factory case, each object *from* the factory is one-of-a-kind by intent), not a candidate-for-reuse waiting to be extracted into a named class later.

### When NOT to reach for one

The pattern's right when the object IS genuinely one-of-a-kind; wrong when it's secretly a class waiting to be extracted.

- **Don't use `instance` for shapes used in many places.** If the same body would appear in N call sites, that's a class. Reach for `class`, give it a name, instantiate it. (Wrapping `instance` in a factory function is a different case — one declaration site, many call sites, all producing tailored objects; see [factory bullet above](#when-to-reach-for-one).)

The boundary to draw: **classes are for shapes worth sharing; ad-hoc instances are for behavior worth doing once.**

---

## Examples

Worked examples showing common shapes the `instance` keyword takes. Each one is a real-world-ish situation with the code and a brief rationale.

### Script-specific configuration

A deploy script needs a handful of configurable values plus a method or two for using them:

~~~caspian
%vibecode
	role: 'the deploy script configuration — one object, used across the script';
end

$config = instance # deploy config
	field :env, class: 'string', default: 'staging'
	field :region, class: 'string', default: 'us-east-1'
	field :max_attempts, class: 'integer', default: 3

	method endpoint()
		'https://' + @env + '.example.com'
	end

	method is_production?()
		@env == 'production'
	end
end

# elsewhere in the script:
$client = %net.http_client.new(base_url: $config.endpoint)
if $config.is_production?
	%stdout.puts 'deploying to prod, attempts: ' + $config.max_attempts
end
~~~

**Why an ad-hoc instance.** This is the deploy script's config. It's not a reusable "DeployConfig" type; nobody else needs it. The methods are convenient packaging for "compute the endpoint URL from the env" — a function would work but the object groups the data and the derivations together cleanly.

### Custom one-shot parser

A script processes a small custom markup format used only here. The parsing logic isn't worth publishing as a class:

~~~caspian
%vibecode
	role: 'parse a one-off markup format used only by this report script';
end

$parser = instance($source) # markup parser
	field :source, class: 'string', required: true
	field :pos,    class: 'integer', default: 0

	method init(@source)
	end

	method parse()
		@pos = 0
		# ... walk @source, build the tree ...
		# returns the parse tree
	end

	method expect($ch)
		if @source.char_at(@pos) != $ch
			%self.error('expected ' + $ch)
		end
		@pos = @pos + 1
	end
end

$ast = $parser.parse
~~~

**Why an ad-hoc instance.** The parser has real state (position, error context, partial tree) and methods that call each other recursively. Plain functions would thread `$pos, $errors, $tree` through every call — noise. A class would imply "MarkupParser is a thing in the system" — but it isn't; it's just this report script's helper. The `instance($source)` form sets up the parser inline; the caller then runs it. The parser exists only as long as it takes to do the work.

### Recursive-descent expression parser

Arithmetic-expression parser with mutually-recursive grammar rules. Each rule (`parse_expression`, `parse_term`, `parse_factor`) is a method that calls sibling rules and shares cursor state through the bucket:

~~~caspian
%vibecode
	role: 'parse an arithmetic expression string into a nested-hash AST';
end

$ast = instance('1 + 2 * (3 - 4)') # expression parser
	field :source, class: 'string', required: true
	field :pos, class: 'integer', default: 0

	method init(@source)
	end

	method parse_expression()
		$left = %self.parse_term

		while %self.peek == '+' || %self.peek == '-'
			$op = %self.consume
			$right = %self.parse_term
			$left = {op: $op, left: $left, right: $right}
		end

		return $left
	end

	method parse_term()
		$left = %self.parse_factor

		while %self.peek == '*' || %self.peek == '/'
			$op = %self.consume
			$right = %self.parse_factor
			$left = {op: $op, left: $left, right: $right}
		end

		return $left
	end

	method parse_factor()
		if %self.peek == '('
			%self.consume
			$inner = %self.parse_expression
			%self.consume
			return $inner
		end

		return %self.consume
	end

	method peek()
		return @source.char_at(@pos)
	end

	method consume()
		$ch = @source.char_at(@pos)
		@pos = @pos + 1
		return $ch
	end

	auto_run :parse_expression
end
~~~

**Why an ad-hoc instance.** This example is the canonical case for the pattern. Each grammar rule dispatches to sibling rules — `parse_expression` calls `parse_term`, `parse_term` calls `parse_factor`, and `parse_factor` recurses back into `parse_expression` for parenthesized sub-expressions. **Bare functions can't express this**: a bare function can't see other functions defined nearby (sealed scope; see [functions/bare § Sealed scope](../functions/bare#sealed-scope)), so calling `&parse_term` from inside `&parse_expression`'s body would raise. The alternatives without `instance` are painful — thread both a cursor state dict and a hash of function references through every call, or build a shared `$fns = {}` lookup hash the closures can reach through. `instance` collapses both concerns: sibling dispatch through `%self.name`, shared cursor state through `@pos`. `auto_run :parse_expression` returns the resulting AST directly, since the parser object is throwaway once its output is captured.

The same shape shows up in interpreters (`eval_call` → `eval_if` → `eval_lambda`, sharing an environment), state machines (each state a method that transitions to sibling states), and multi-pass code generators (`build_header` → `build_body` → `build_footer` sharing a buffer). Anywhere many small pieces of code call each other AND need shared state, `instance` is the natural fit.

### Small content builder

A script generates a one-off summary document by accumulating sections:

~~~caspian
%vibecode
	role: 'build a summary HTML page; not a reusable builder class';
end

$html = instance # report builder
	field :sections, class: 'array', default: []

	method heading($text)
		@sections.push('<h2>' + $text + '</h2>')
		%self    # return self for chaining
	end

	method paragraph($text)
		@sections.push('<p>' + $text + '</p>')
		%self
	end

	method render()
		@sections.join("\n")
	end
end

$html.heading('Summary').paragraph('Things went OK.').paragraph('No errors.')
%fs.write_text('summary.html', $html.render())
~~~

**Why an ad-hoc instance.** State accumulates across method calls (`@sections` grows as the script adds content). Methods are chainable — they're for THIS script's writer, not a builder pattern worth publishing. A plain function would lose the accumulation; a class would be ceremony for what's a one-off bit of report-generation code.

### Server-management actor

A maintenance script manages one specific server through its lifecycle:

~~~caspian
%vibecode
	role: 'manage the one server this script is targeting';
end

$server = instance # server controller
	field :host, class: 'string', required: true, :get, :set
	field :ssh,  class: 'object'

	method connect()
		@ssh = %net.ssh.new(host: @host)
	end

	method snapshot()
		@ssh.exec('snapshot-cmd')
	end

	method restart()
		@ssh.exec('systemctl restart app')
	end

	method wait_healthy($timeout)
		# poll until healthy or timeout
	end

	method teardown()
		@ssh.close
	end
end

$server.host = 'app-01.example.com'
$server.connect
$server.snapshot
$server.restart
$server.wait_healthy(timeout: 60)
$server.teardown
~~~

**Why an ad-hoc instance.** The script manages ONE specific server through a sequence of operations. Each method needs the shared SSH connection. State (the connection) is genuinely tied together; methods call related methods. There's no "ServerController" class worth designing — the next script that does similar work will have its own concerns and its own instance. This object is local craft for this maintenance task.

---

## Why Caspian fits this naturally

Several features make the `instance` pattern cheap and idiomatic at the syntactic level:

- **Everything is a class.** The shadow class inside an object is real and addressable; adding methods and inherited classes to it isn't a special case.
- **Classes can be modified at runtime.** Adding methods to a shadow class doesn't require a separate ceremony or workaround.
- **Singleton methods are first-class.** Caspian already provides `method $foo.name(params) ... end` for adding methods to any specific object. The `instance ... end` block is just doing this in bulk at construction time instead of one method at a time later.

Other languages support related patterns but with friction. Java requires every object to be an instance of a declared type; building an object inline that doesn't conform to one isn't expressible. Python supports it via `object()` then `__class__.method = ...`, but with dunder mechanics that signal "you're going off the rails." In Caspian, ad-hoc object construction is on the rails — no special engine support is needed, just a syntactic convenience.
