# Caspian file values
<!--index: 14-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_files",
	"role": "spec for what a Caspian source file evaluates to when executed or fetched via %puck. Covers the file-as-value model, the two canonical patterns for class-serving files (single class or an instance with getter methods per class), the hash-form alternative, and the auto_run caveat for class-serving instances. Sits alongside content-types.md — that page specs how a file is transported over HTTP; this page specs what fetchers actually receive.",
	"status": "spec — single-class and multi-class file shapes settled; hash form documented as legal but instance form is recommended for multi-class",
	"audience": "developers authoring Caspian source files; anyone publishing objects for %puck fetch; engine implementers who realize a file's value after evaluation"
}}
~~~

A Caspian source file is a program. When executed — whether run locally or fetched and evaluated through `%puck` — the file produces a **value**: whatever its top-level evaluation yields. That value is what fetchers receive, what other files see when they reference the file's URL, and what the engine hands to any consumer of the file.

## Single-class files

The simplest and most common shape is a file whose entire body is a `class ... end` expression:

~~~caspian
class # widget
	field @label, class: :string

	method render()
		return @label
	end
end
~~~

The file's value is that class object. A consumer fetching the file's URL gets the class directly:

~~~caspian
$widget_class = %['https://foo.bar/widget.casp']
$w = $widget_class.new(label: 'primary')
~~~

No wrapping, no ceremony — the class **is** the file.

## Multi-class files

For files that expose more than one class from a single URL, wrap them in `instance ... end` and expose each class through a getter:

~~~caspian
instance # colors
	getter :red, class
		# ... red class body ...
	end

	getter :green, class
		# ... green class body ...
	end

	getter :blue, class
		# ... blue class body ...
	end
end
~~~

The file's value is the instance. Consumers reach each class through the getter:

~~~caspian
$colors = %['https://foo.bar/colors.casp']
$red = $colors.red

$paint = $colors.red.new(shade: 'crimson')
~~~

The wrapping instance is a full object, not just a lookup table. It can carry shared helpers, config values, an `init` hook, singleton methods — anything a regular `instance ... end` body can carry. Classes exposed via `getter` are the everyday case; the extra capacity is there when a file needs it.

## Alternative: hash form

A file body that evaluates to a plain hash of classes also works:

~~~caspian
{
	red: class # red
		# ...
	end,
	green: class # green
		# ...
	end,
	blue: class # blue
		# ...
	end
}
~~~

Consumers reach classes via subscript:

~~~caspian
$colors = %['https://foo.bar/colors.casp']
$red = $colors['red']
~~~

The hash form is legal, but the instance form is the recommended shape for class-serving files. Three reasons:

- **Read ergonomics.** `$colors.red` reads better than `$colors['red']` at every call site.
- **Extension.** The instance form can grow to include helpers, shared state, or hooks. The hash form is a fixed lookup — adding anything else requires switching to `instance` later.
- **Introspection.** The instance form exposes structure via the object's method surface (`$colors.object.classes` and similar). A hash is just a hash.

Reach for the hash form when the file genuinely produces a lookup table and nothing more; use `instance` for anything that might grow.

## `auto_run` in a class-serving instance

Setting `auto_run` on a method inside a class-serving instance replaces the instance with that method's return value as the file's value — so consumers stop receiving the instance and start receiving whatever the method returns:

~~~caspian
instance
	getter :red, class
		# ...
	end

	method compute_something()
		return null
	end

	auto_run :compute_something   # file's value is now null, not the instance
end
~~~

Almost always the wrong shape for a class-serving file. Don't set `auto_run` on a class-serving instance — `auto_run` is meaningful for instances that exist to compute a single result; class-serving instances exist to hold classes and want the instance itself to be the file's value.

## Related

- [content-types](https://puck.uno/documentation/requirements/caspian/content-types) — how the file is transported over HTTP (the wire-level companion to this page's what-does-the-file-produce concern).
- [classes/definition § getter shorthand](https://puck.uno/documentation/requirements/caspian/classes/definition#getter-shorthand) — the `getter :name, value` construct used by the multi-class pattern.
- [instance](https://puck.uno/documentation/requirements-old/caspian/classes/instance) — the full spec for the `instance ... end` construct.
