# Colorize (example: adding methods to another class)

<span class="tag">colorize</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_test_cases_colorize",
	"role": "test case for class-inheritance mutation. Demonstrates the `.inherited.ensure` pattern — the block-form idiom that temporarily adds a class as a parent of another class and removes it on block exit, and the bare form that adds permanently. Uses the Ruby `colorize` gem pattern (ANSI-color methods on String) as a familiar hook: the class itself isn't shipped by Caspian, but the flow shown here is a required behavior of the language. If any of the surfaces the test case depends on (`.inherited` on class values, Array's block-form `.ensure`, `.$class.method` downloaded-method application) don't behave as shown, the language is broken.",
	"status": "test case — this flow is required behavior; the colorize class is illustrative only",
	"audience": "engine implementers verifying class-inheritance mutation works; developers reading the language spec looking for a concrete worked example"
}}
~~~

**The colorize class itself is illustrative** — Caspian doesn't ship it. What's required is the **flow**: the ability to temporarily (or permanently) add a class as a parent of another class using `.inherited.ensure`, with method resolution seeing the new parent for the duration. Ruby's `colorize` gem ([github.com/fazibear/colorize](https://github.com/fazibear/colorize)) provides the familiar hook — a small class whose whole purpose is being mixed into `String` to gain per-color methods like `.red`, `.blue`, `.bold` — but the pattern generalizes to any class you want to bolt onto a built-in.

## The class

Short version, two colors only. A real implementation would define one method per color/mode and they'd all look like these:

~~~caspian
$colorize = class # colorize
	method red()
		return "\e[31m" + %self + "\e[0m"
	end

	method blue()
		return "\e[34m" + %self + "\e[0m"
	end
end
~~~

Two methods, both wrapping the receiver in ANSI escape codes. `\e` is the ASCII escape character (0x1B); `[31m` starts red foreground, `[34m` starts blue, `[0m` resets. Both read `%self` and return a new string. Nothing is mutated.

**Note on `\e`.** Caspian's string escape list is currently `\n`, `\t`, `\'`, `\"`, `\\`. `\e` isn't in it yet. Real code would either wait for `\e` to land or build the escape character from its char code. Written as `\e` here for readability.

## Using it — temporarily

Add Colorize as a parent of `String` for the duration of a block; remove it on exit:

~~~caspian
%('core:string').inherited.ensure($colorize) do
	puts 'error'.red        # outputs: "\e[31merror\e[0m"
	puts 'ok'.blue          # outputs: "\e[34mok\e[0m"
end

puts 'plain'.red            # raises: method-not-found — Colorize is no longer a parent of String
~~~

Inside the block, every String has `.red` and `.blue` — method resolution walks up through Colorize and finds them. Outside, String is back to its baseline surface.

## Using it — permanently

Same call, no block. Colorize becomes a parent of String for the rest of the process:

~~~caspian
%('core:string').inherited.ensure($colorize)
# String now has .red / .blue forever.
~~~

If `$colorize` is already a parent, no-op.

## Using it — explicit per-call

If mutating String is undesirable, apply the class's methods explicitly via the [downloaded-method](https://puck.uno/documentation/requirements/classes/downloaded-methods) form. Nothing global changes; each call opts in individually:

~~~caspian
puts 'error'.$colorize.methods['red']
~~~

## What's actually happening

1. `%('core:string').inherited` is the live inheritance array on the built-in `String` class. Any class can be added to it; instances of the class immediately see the new parent's methods via normal method resolution.
2. `.ensure($colorize)` (block form) — if `$colorize` isn't already a parent, adds it, runs the block, and removes exactly that platter at block exit. Identity-tracked cleanup: the engine remembers which platter it added and removes only that one.
3. Inside the block, calling `'error'.red` dispatches through method resolution. `String` doesn't have `.red`, but its inheritance graph now includes `$colorize`, which does. The dispatch finds `.red` there, invokes it with `%self` bound to `'error'`, gets back the wrapped string.
4. On block exit, `.ensure`'s cleanup removes the `$colorize` platter. Subsequent `.red` on any String raises method-not-found.

## Spec surfaces this example depends on

- **`.inherited` on class values** — the live per-class inheritance array, along with its bare and block forms of `.ensure`. Spec'd on [classes/inheritance](tag:class-inheritance).
- **Array's block-form `.ensure`** — `.inherited` uses it, but the general Array-level `.ensure` (bare and block, on any array) still needs its own dedicated spec entry under [primitives/array/](https://puck.uno/documentation/requirements/built-in-classes/primitives/array/). Behavior mirrors what's shown on [classes/inheritance](tag:class-inheritance).

## Related

- [classes/definition § Inheritance](https://puck.uno/documentation/requirements/classes/definition/#inheritance) — the `inherits` clause; class-level inheritance.
- [built-in-classes/object/methods § `.classes`](https://puck.uno/documentation/requirements/built-in-classes/object/methods/#classes--classesensureclass--classesaddunconditionallyclass--classesshadow) — the per-instance analog (`$obj.object.classes.ensure(...)`).
- [primitives/string/](https://puck.uno/documentation/requirements/built-in-classes/primitives/string/) — the base String class this example extends.
- [downloaded-methods](https://puck.uno/documentation/requirements/classes/downloaded-methods) — the `.$fn` explicit-per-call alternative.
- [fazibear/colorize (Ruby)](https://github.com/fazibear/colorize) — the pattern this example mirrors.
