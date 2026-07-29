# Caspian file values
<!--index: 14-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_files",
	"role": "spec for what a Caspian source file evaluates to when executed or fetched via %import. Covers the file-as-value model, the single-class pattern, and the two multi-class patterns (plain hash literal for pure lookup, or instance-with-`public_const` when the file also needs helpers, hooks, or other structure). Includes the autorun caveat for class-serving instances. Sits alongside content-types.md — that page specs how a file is transported over HTTP; this page specs what fetchers actually receive.",
	"status": "spec — single-class and multi-class file shapes settled; two multi-class patterns (hash literal for pure lookup, instance-with-public_const when other capabilities are needed) documented as peers",
	"audience": "developers authoring Caspian source files; anyone publishing objects for %import fetch; engine implementers who realize a file's value after evaluation"
}}
~~~

A Caspian source file is a program. When executed — whether run locally or fetched and evaluated through `%import` — the file produces a **value**: whatever its top-level evaluation yields. That value is what fetchers receive, what other files see when they reference the file's URL, and what the engine hands to any consumer of the file.

## Single-class files

The simplest and most common shape is a file whose entire body is a `class ... end` expression:

~~~caspian
class # widget
	field :label, class: :string

	method render()
		return @label
	end
end
~~~

The file's value is that class object. A consumer fetching the file's URL gets the class directly:

~~~caspian
$widget_class = %('https://foo.bar/widget.casp')
$w = $widget_class.new(label: 'primary')
~~~

No wrapping, no ceremony — the class **is** the file.

## Multi-class files

For files that expose more than one class from a single URL, two patterns work — pick based on whether the file also needs to carry helpers, hooks, or other structure alongside the classes.

### Pattern A: plain hash literal

The file body is a hash whose values are classes:

~~~caspian
{
	red: class # red
		# ... red class body ...
	end,
	green: class # green
		# ... green class body ...
	end,
	blue: class # blue
		# ... blue class body ...
	end
}
~~~

Consumers reach each class via subscript:

~~~caspian
$colors = %('https://foo.bar/colors.casp')
$red = $colors['red']
$paint = $colors['red'].new(shade: 'crimson')
~~~

Reach for the hash form when the file is a pure lookup table and nothing else.

### Pattern B: instance with `public_const`

The file body is an `instance ... end` block that exposes each class through a `public_const` declaration:

~~~caspian
instance # colors
	public_const :red, class # red
		# ... red class body ...
	end

	public_const :green, class # green
		# ... green class body ...
	end

	public_const :blue, class # blue
		# ... blue class body ...
	end

	method &describe()
		return 'colors library'
	end
end
~~~

The file's value is the instance. Consumers reach each class through the generated getter:

~~~caspian
$colors = %('https://foo.bar/colors.casp')
$red = $colors.red
$paint = $colors.red.new(shade: 'crimson')

$colors.describe   # 'colors library'
~~~

`public_const :name, value` freezes the value into the class-object's bucket and generates an external getter method with the same name (see [classes/definition § Constants](https://puck.uno/requirements/classes/definition#constants)). Because the wrapping is a full instance, the file body can also carry shared helpers, config values, an `init` hook, singleton methods, or a `.call` method (making the file's returned instance amp-invocable) — anything a regular `instance ... end` body can carry.

### Choosing between them

- **Read ergonomics.** `$colors.red` reads better than `$colors['red']` at every call site.
- **Extension.** The instance form can grow to include helpers, shared state, hooks, or a `.call` method. The hash form is a fixed lookup — adding anything else requires switching to `instance` later.
- **Introspection.** The instance form exposes structure via the object's method surface. A hash is just a hash.

Reach for the hash form when the file is a pure lookup table; use the instance form when the file carries additional capabilities or is likely to grow.

## `autorun` in a class-serving instance

Declaring a method named `autorun` inside a class-serving instance replaces the instance with that method's return value as the file's value — so consumers stop receiving the instance and start receiving whatever the method returns:

~~~caspian
instance
	public_const :red, class
		# ...
	end

	method autorun()
		return null   # file's value is now null, not the instance
	end
end
~~~

Almost always the wrong shape for a class-serving file. Don't declare an `autorun` method on a class-serving instance — the convention is meaningful for instances that exist to compute a single result; class-serving instances exist to hold classes and want the instance itself to be the file's value.

## Testing

- **Single-class file yields the class** — a file whose body is one `class ... end` fetched via `%import` returns the class object; `.new(...)` on it produces an instance.
- **Class name literal-label is preserved** — a `class # widget` file yields a class whose introspectable label is `widget`.
- **Multi-class instance file yields the instance** — a file wrapping several `public_const :name, class` expressions inside `instance ... end` fetched via `%import` returns the instance.
- **`public_const` reaches its class** — after fetching the multi-class instance, `$colors.red` returns the `red` class object.
- **`public_const` class is instantiable** — `$colors.red.new(shade: 'crimson')` produces a valid instance.
- **Instance-form file may carry helpers** — a helper method or config value declared alongside the `public_const` declarations is reachable on the returned instance.
- **Instance-form file honors `init` hook** — an `init` hook inside the wrapping instance runs exactly once when the file is loaded, not on each class-property access.
- **Hash-form file yields a hash** — a file whose body is a hash literal of classes yields a hash; `$colors['red']` returns the red class.
- **Hash-form file class is instantiable** — `$colors['red'].new(...)` produces a valid instance.
- **`autorun` method on a class-serving instance replaces the file's value** — after adding `method autorun() return null end`, `%import(url)` yields `null`, not the instance.
- **Fetching from `local:` produces the same value as HTTP** — a file at `local:/widget.casp` and the same file served over HTTP yield equivalent objects.
- **Fetching from cache produces the same value** — a cached copy of a file yields a value equivalent to the origin fetch.
- **Fetching an empty file raises** — a zero-byte `.casp` file raises per [non-caspian-mime-types § Empty-content handling](https://puck.uno/requirements/non-caspian-mime-types#empty-content-handling).
- **File with syntax error raises during fetch** — a `.casp` file that fails to parse raises at fetch time, not on first use.
- **File whose top-level is a plain value returns that value** — a file whose body is `42` yields the number `42`.
- **UTF-8 identifiers survive fetch** — a file that defines a class name containing multi-byte UTF-8 characters remains reachable by its exact name.

## Related

- [content-types](https://puck.uno/requirements/content-types) — how the file is transported over HTTP (the wire-level companion to this page's what-does-the-file-produce concern).
- [classes/definition § Constants](https://puck.uno/requirements/classes/definition#constants) — the `public_const` construct used by the instance-based multi-class pattern.
- [instance](https://puck.uno/requirements/classes/instance) — the full spec for the `instance ... end` construct.
