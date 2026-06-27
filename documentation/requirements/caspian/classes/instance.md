# Instance

~~~vibecode
{"vibecode": {
	"doc": "instance_keyword",
	"role": "spec for the `instance` keyword — a Caspian construct that builds a single object directly using the same body shape as a class definition. Two forms: `instance ... end` constructs with no args; `instance(args...) ... end` passes the args through to the new object's `&init`. Sugar for `$cls = class ... end; $foo = $cls.new(args...)`. Includes the design-pattern framing (ad-hoc instances), guidance on when to use it, and worked examples.",
	"status": "active spec",
	"audience": "Caspian programmers; engine implementers",
	"related": ["index.md (class definitions)"]
}}
~~~

The **`instance`** keyword builds a single object directly, without going through a separate class declaration. The body uses the same shape as `class ... end` — fields, methods, inheritance — and everything in the body populates the shadow class of the new object.

The object built this way is sometimes called an **ad-hoc instance**: a one-off object made directly for a specific situation, without the ceremony of declaring a class first. The pattern is realized in code via the `instance` keyword but exists conceptually independent of any specific syntax — it's whatever results from "start with a bare object, add methods and inheritance to its shadow, use it, move on."

---

<a id="forms"></a>
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

<a id="with-init-args"></a>
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

<a id="body-semantics"></a>
## Body semantics

The body is structurally identical to a class definition body. Whatever is legal in a `class ... end` block is legal in an `instance ... end` block, and means the same thing — except it all populates the shadow class of one specific object rather than producing a reusable class.

Concretely:

- **Field declarations** (`field :name, class: ..., default: ..., required: ...`) work as in classes. Defaults are applied to the new object's bucket via the implicit `.new()` call. `required: true` with no default would error at construction since the implicit `.new()` is called without args (use a class with an explicit `.new(...)` if you need required-but-no-default fields).
- **Methods** (`method name(...) ... end`) are defined on the shadow class. Calling them on the new object dispatches normally.
- **Inheritance** (`inherits: [...]`) is supported. The shadow class inherits from the listed classes; methods not defined locally fall back through the inheritance chain just as for any other class.
- **Inline label.** Per the [class inline label convention](index.md), `instance # short label` carries a brief readable label after the keyword. Useful since the object, like an anonymous class, has no name to identify it.

---

<a id="under-the-hood"></a>
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

---

<a id="what-an-ad-hoc-instance-is"></a>
## What an ad-hoc instance is

- **Conceptual, not technical.** "Ad-hoc instance" is a design-pattern label, not an engine concept. Nothing in Caspian's runtime cares whether an object was built this way; the resulting object is structurally identical to one built through any other path.
- **Starts bare, gets built up.** Conceptually, the developer instantiates "object" itself — an empty thing with no methods and no inherited classes — and then adds custom behavior to its shadow. The `instance` keyword does this in one block, but the same outcome could be reached by creating a bare object and using `.object.classes.add` plus `method $obj.name() ... end` step by step.
- **Singleton-spirited.** Like a singleton, it's one of its kind. Unlike a singleton, there's no global registry, no convention for finding it later — it lives wherever the variable holding it lives, and when that variable goes out of scope, the object goes with it.

---

<a id="when-to-reach-for-one"></a>
## When to reach for one

The canonical case: a developer is writing a custom script for one specific situation and doesn't want the baggage of class declaration. Examples of that shape:

- **A configuration object** assembled for this run of this script. Specific values, specific methods, no need to publish it as a type.
- **A bespoke handler / actor / agent** that exists only inside one function or one script. Defines its behavior inline; nobody outside the script ever sees it.
- **A test fixture** that needs tailored behavior for one assertion. Local to the test, dies with the test.
- **A module-global "the X"** — the logger, the registry, the connection pool — when there really is only one of it and inventing a class to make one feels like overhead.

What unites these: **the object is one-of-a-kind by intent**, not a candidate-for-reuse waiting to be extracted later.

---

<a id="when-not-to-reach-for-one"></a>
## When NOT to reach for one

The pattern's right when the object IS genuinely one-of-a-kind; wrong when it's secretly a class waiting to be extracted.

- **Don't use `instance` for shapes used in many places.** If the same body would appear in N call sites, that's a class. Reach for `class`, give it a name, instantiate it.
- **Object factories aren't the best fit.** A factory function that produces tailored instances on demand is closer to "varied recipes from a shared base" than "one-of-a-kind objects." The `instance` form can be used inside a factory, but it's not what the pattern is for. Whether factory implementations want their own syntactic treatment is an open question.

The boundary to draw: **classes are for shapes worth sharing; ad-hoc instances are for behavior worth doing once.**

---

<a id="examples"></a>
## Examples

Worked examples showing common shapes the `instance` keyword takes. Each one is a real-world-ish situation with the code and a brief rationale.

<a id="example-script-specific-configuration"></a>
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

<a id="example-custom-one-shot-parser"></a>
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

<a id="example-small-content-builder"></a>
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

<a id="example-server-management-actor"></a>
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

<a id="why-caspian-fits-this-naturally"></a>
## Why Caspian fits this naturally

Several features make the `instance` pattern cheap and idiomatic at the syntactic level:

- **Everything is a class.** The shadow class inside an object is real and addressable; adding methods and inherited classes to it isn't a special case.
- **Classes can be modified at runtime.** Adding methods to a shadow class doesn't require a separate ceremony or workaround.
- **Singleton methods are first-class.** Caspian already provides `method $foo.name(params) ... end` for adding methods to any specific object. The `instance ... end` block is just doing this in bulk at construction time instead of one method at a time later.

Other languages support related patterns but with friction. Java requires every object to be an instance of a declared type; building an object inline that doesn't conform to one isn't expressible. Python supports it via `object()` then `__class__.method = ...`, but with dunder mechanics that signal "you're going off the rails." In Caspian, ad-hoc object construction is on the rails — no special engine support is needed, just a syntactic convenience.

---

<a id="open"></a>
## Open

- **Factory implementations.** Whether the `instance` form is the right substrate for object factories — and if so, how args get passed into the build when neither field defaults nor `&init` covers what the caller needs to pass — is undecided. Factories that need to construct-and-return a tailored object are not yet ergonomic.
