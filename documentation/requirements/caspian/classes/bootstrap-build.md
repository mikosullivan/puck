# Bootstrap build

~~~vibecode
{"vibecode": {
	"doc": "bootstrap_build",
	"role": "spec for the `bootstrap` keyword — a Caspian construct that builds a single object using the same body shape as a class definition. Two forms: bare `bootstrap ... end` returns the constructed object; `bootstrap(:method, args...) ... end` constructs the object, invokes the named method with the args, and returns whatever the method returns. Effectively sugar for `$cls = class ... end; $foo = $cls.new()` with optional immediate method dispatch.",
	"status": "active spec — keyword settled, both forms defined; factory-args still open",
	"audience": "Caspian programmers; engine implementers",
	"related": ["index.md (class definitions)",
		"../../../ideas/caspian/bootstraps.md (the broader design-pattern framing)"]
}}
~~~

The **`bootstrap`** keyword builds a single object directly, without going through a separate class declaration. The body uses the same shape as `class ... end` — fields, methods, inheritance — and everything in the body populates the shadow class of the new object.

For the broader design-pattern framing (when to reach for this vs. declaring a class, what's a "bootstrap object" conceptually), see [ideas/caspian/bootstraps.md](../../../ideas/caspian/bootstraps.md). This file specs the keyword itself.

---

<a id="forms"></a>
## Two forms

The keyword has two forms, distinguished by whether a method-name argument is passed.

### Bare form

```
bootstrap ... end
```

Builds the object, returns it. The caller takes it from there.

~~~caspian
$config = bootstrap # the script's config
	field :host, class: 'string', default: 'localhost'
	field :port, class: 'integer', default: 8080

	method &dsn()
		'tcp://' + @host + ':' + @port
	end
end

%stdout.puts $config.dsn   # tcp://localhost:8080
~~~

`$config` is the constructed bootstrap object. Methods and fields are reachable through it as on any object.

### With method invocation

```
bootstrap(:method_name, args...) ... end
```

Builds the object, immediately invokes the named method with the args, returns whatever the method returns. The object itself doesn't escape unless the method returned it explicitly.

~~~caspian
$parsed = bootstrap(:parse, '{[foo]}') # parser
	method &parse($input)
		# ... parsing logic ...
		# returns the parse tree
	end
end
~~~

`$parsed` is the result of `&parse`, not the bootstrap object. The pattern reads as "set up a parser and parse this," with the implementation detail "an object got built in the middle" gracefully invisible at the call site.

This form solves a common shape: construct an object, immediately call one method on it, return that method's result. Without this form, the caller would write `$parser = bootstrap ... end; $parsed = $parser.parse('{[foo]}')` — two lines for what is conceptually one expression.

---

<a id="body-semantics"></a>
## Body semantics

The body is structurally identical to a class definition body. Whatever is legal in a `class ... end` block is legal in a `bootstrap ... end` block, and means the same thing — except it all populates the shadow class of one specific object rather than producing a reusable class.

Concretely:

- **Field declarations** (`field :name, class: ..., default: ..., required: ...`) work as in classes. Defaults are applied to the new object's bucket via the implicit `.new()` call. `required: true` with no default would error at construction since the implicit `.new()` is called without args (use a class with an explicit `.new(...)` if you need required-but-no-default fields).
- **Methods** (`method &name(...) ... end`, `function &name(...) ... end`) are defined on the shadow class. Calling them on the bootstrap object dispatches normally.
- **Inheritance** (`inherits: [...]`) is supported. The shadow class inherits from the listed classes; methods not defined locally fall back through the inheritance chain just as for any other class.
- **Inline label.** Per the [class inline label convention](index.md), `bootstrap # short label` carries a brief readable label after the keyword. Useful since the bootstrap, like an anonymous class, has no name to identify it.

---

<a id="under-the-hood"></a>
## What it desugars to

`bootstrap` is sugar. Conceptually:

~~~caspian
$foo = bootstrap
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

And:

~~~caspian
$result = bootstrap(:method_name, $arg1, $arg2)
	# body
end
~~~

is equivalent to:

~~~caspian
$_cls = class
	# body
end
$_obj = $_cls.new()
$result = $_obj.method_name($arg1, $arg2)
~~~

The anonymous class isn't kept around past construction (no variable holds it; nothing else can reach it). Everything the body declares ends up on the bootstrap object's shadow.

The implicit `.new()` takes no args. If you need to pass construction args to a class-defined `&new`, declare a class explicitly and instantiate it — `bootstrap` is for the common case where the object's setup happens via field defaults, inherited classes, and optionally an immediately-invoked method.

---

<a id="examples"></a>
## Examples

### A configuration object for one script

~~~caspian
$config = bootstrap # script config
	field :host, class: 'string', default: 'localhost'
	field :port, class: 'integer', default: 8080
	field :tls,  class: 'boolean', default: false

	method &dsn()
		($tls ? 'tcps://' : 'tcp://') + @host + ':' + @port
	end
end

# elsewhere in the script:
$conn = %net.tcp_listen(@host, @port)
%stdout.puts $config.dsn
~~~

### A custom parser used once

~~~caspian
$parsed = bootstrap(:parse, $source) # markup parser
	field :pos, class: 'integer', default: 0

	method &parse($source)
		@pos = 0
		# ... custom parse rules for this script's markup ...
		# returns the parse tree
	end
end
~~~

`$parsed` is the parse tree. The parser object doesn't escape.

### A small content builder

~~~caspian
$html = bootstrap(:render) # html builder for this report
	field :sections, class: 'array', default: []

	method &add_heading($text)
		@sections.push({class: 'h2', content: $text})
	end

	method &add_paragraph($text)
		@sections.push({class: 'p', content: $text})
	end

	method &render()
		# ... assemble @sections into HTML string ...
		# returns the HTML
	end
end
~~~

The wrinkle here: the bare-form pattern would let the caller call `add_heading` and `add_paragraph` before calling `render`. The `bootstrap(:render)` form short-circuits that, calling `render` immediately with no content added first — not actually useful unless `render` itself does the population work. For a builder that genuinely needs the caller to drive it, use the bare form and call methods explicitly.

---

<a id="open"></a>
## Open

- **Factory case.** Whether `bootstrap` is the right substrate for object factories — and how args should land into the constructed object when neither field defaults nor an auto-invoked method covers what the caller needs to pass — is undecided. The current with-method form covers many cases; factories that need to construct-and-return the object (not just the work's result) are not yet ergonomic.
- **Method-name notation.** The spec sketches `:method_name` (a symbol-like notation). Whether that's the actual Caspian syntax for naming a method, or whether some other form (string literal, bare identifier) is used, follows from the broader method-naming conventions and may shift.
