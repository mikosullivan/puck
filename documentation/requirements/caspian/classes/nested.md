# Nested methods
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_classes_nested",
	"role": "spec for the `nested :name ... end` construct inside a class body — a way to group methods under a named sub-namespace reachable via dotted paths (`$obj.name.method(...)`). Nested methods have full access to the parent instance's bucket, %self, and ambient surfaces; the nesting is a naming convention, not an isolation boundary.",
	"status": "draft — DSL form, access semantics, and dispatch spec'd; a few open questions listed at the bottom",
	"audience": "developers writing Caspian classes; engine implementers building the class-runtime; tooling authors"
}}
~~~

**Nested methods** let a class organize its method surface into named sub-namespaces. Instead of a flat method list, methods can be grouped under a name like `stats` or `to`, and callers reach them via a dotted path: `$widget.stats.average()`. The sub-namespace becomes part of the call path.

## Nested methods are still methods on the object

**A nested method has full access to the object's state.** Inside its body:

- `%self` is the parent instance (the widget, not a helper).
- `@name`, `@count`, and every other bucket entry are read and written directly.
- `%chain`, `%engine` (if in user role), and every other ambient surface behave exactly the same as inside a top-level method.
- Any other method of the class — nested or top-level — can be called via `%self.other_method(...)`.

**Nested methods are NOT helper objects.** The name `stats` doesn't identify a separate object with its own bucket and role. It's a namespace label on a set of methods that belong to the parent instance. Nothing about the object model is different for nested methods; only the call-site path is.

## Syntax

Declare a nested namespace with `nested :name ... end` inside a class body. Method definitions inside the block become members of the namespace:

~~~caspian
$widget = class # widget
	field @count, class: :number, default: 0
	field @total, class: :number, default: 0

	method &record($value)
		@count += 1
		@total += $value
		return null
	end

	nested :stats
		method &average()
			if @count == 0
				return 0
			end

			return @total / @count
		end

		method &sum()
			return @total
		end
	end
end
~~~

Callers reach nested methods with a dotted path:

~~~caspian
$w = $widget.new()
&w.record 10
&w.record 20

$avg = $w.stats.average    # 15
$sum = $w.stats.sum        # 30
~~~

Notice that inside `&average`, `@count` and `@total` read the widget's bucket directly — the nested method sees the same instance state as `&record` does.

## Why nested, not helper

An older sketch of this construct used the word `helper` and described it as "a lazily-initialized helper object namespaced off the parent." That framing implied a separate object with its own identity that could only see the parent's public surface — like Ruby's `Struct` or Python's inner class. That's NOT what Caspian does. The word `nested` was chosen to make the framing explicit: it's about **method namespacing**, not object composition.

If you want a separate object with its own state that happens to reference the parent, that's what a field holding an instance is for. `nested` is only for grouping methods.

## What `$obj.stats` returns as a bare expression

Currently **TBD.** Two reasonable options:

- **A namespace-view object bound to the instance.** `$widget.stats` returns a small object whose methods dispatch back to the widget's nested-namespace methods. This makes the namespace introspectable (`$widget.stats.methods` lists what's in it) and passable as a value.
- **Only dotted-path calls are legal.** `$widget.stats` on its own raises; only `$widget.stats.something` is a legal expression.

The first is more flexible and is what the [conversion protocol](https://puck.uno/documentation/ideas/conversion) design already needs — `$foo.to` needs to be an object whose methods you can enumerate. So the first is likely what lands; leaving formally open until the protocol lands.

## Depth

Whether a `nested :name ... end` block can contain another `nested :name ... end` block — enabling `$obj.foo.bar.baz(...)` — is unresolved. The simplest answer is **yes, arbitrary depth**, since the mechanism is just naming; the harder answer requires a rule about what a bare `$obj.foo.bar` returns. See the open questions.

## Interaction with the conversion protocol

The `.to` and `.from` conversion protocol described in [ideas/conversion](https://puck.uno/documentation/ideas/conversion) uses this exact mechanism. `.to.number` is a nested-method call: the class declares

~~~caspian
class # string
	nested :to
		method &number()
			# parse @value into a number
			return %puck.number.from.string(%self)
		end
	end
end
~~~

Inside `&number`, `%self` is the string instance — the nested method has full read access to its state, just like any other method. The `.to` namespace is just a naming grouping.

## CaspianJ form

The engine's runtime representation carries the namespace directly in the class record's `methods` table. Each entry can carry a `nested: {...}` map holding sub-methods, and each sub-method is itself an entry with the same shape (`params`, `returns`, `body`) as a top-level method:

~~~json
"methods": {
	"stats": {
		"nested": {
			"average": {
				"params": {},
				"returns": {"class": "number"},
				"body": "..."
			},
			"sum": {
				"params": {},
				"returns": {"class": "number"},
				"body": "..."
			}
		}
	}
}
~~~

Since each nested entry has the same shape as a top-level method, arbitrary depth is expressible in the JSON without any structural change — a nested entry could itself carry a further `nested: {}` map.

## Open questions

- **What `$obj.namespace` returns as a bare expression** — namespace-view object vs raise. Likely a namespace-view object once the conversion protocol lands, since that design needs it.
- **Nesting depth.** Whether `nested` blocks can contain further `nested` blocks (yielding paths like `$obj.foo.bar.baz(...)`). The JSON allows it; the DSL might restrict it if there's a reason.
- **Method-name conflicts.** A top-level method literally named `stats` alongside a nested block named `stats` — is that a class-load-time error, or does one shadow the other? Likely error; worth confirming.
- **Inheritance.** Whether a subclass can add methods to a parent's nested namespace (`class inherits parent { nested :stats { method &new_one() ... end } end }`). The natural answer is yes — nested is naming, and subclasses can add sibling methods — but the dispatch precedence needs to be spelled out.
- **The name registry.** Whether `nested` names sit in the same namespace as `field` names (so `field :stats` and `nested :stats` would conflict) or in separate namespaces. Probably separate — fields and methods are already in separate tables — but worth confirming.
