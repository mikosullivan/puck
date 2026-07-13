# Class definition
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_classes_definition",
	"role": "spec for how classes are defined in Caspian — the `class ... end` DSL, the inline `# label` convention, field declarations with their constraints, method definitions, inheritance (single and multiple), engine-invoked hooks (init, to_string, on_close), abstract classes, auto-getters/setters, the `getter :name, value` shorthand for preset-plus-getter fields, how a class body becomes the class object that appears in an instance's stack, and the `amend $var ... end` construct that extends an existing class with additional declarations (Ruby-style class reopening; mutation-vs-derived-class semantics still open). Uniqueness constraints and the `join` shorthand are Mikobase concepts and are not part of the Caspian class model.",
	"status": "draft — DSL surface for the common constructs spec'd; a few areas noted as TBD (helper namespaces, hook-in-class declaration, `implements?` structural check)",
	"audience": "developers writing Caspian classes; parser implementers; anyone reasoning about class construction"
}}
~~~

Every class in Caspian is defined by a **class body** — a block that declares fields, methods, inheritance, and other class-level structure. The body evaluates to a class object, which the caller stores wherever it wants.

Classes are the sole method-carrier in Caspian ([concepts § Classes are the only method-carrier](https://puck.uno/documentation/requirements/caspian/concepts#classes-are-the-only-method-carrier)); everything about attaching behavior to values goes through this construct.

## A complete example

A class with the everyday pieces — typed fields, a default, regular methods, and a few engine-invoked methods (`init`, `to_string`, `on_close`) — bound to a variable so it can be instantiated:

~~~caspian
$character = class # character
	field @name,      class: :string,               get: true, set: true
	field @rank,      class: :string,               get: true, set: true
	field @soliloquy, class: :string, default: '',  get: true, set: true

	# The @-sigil parameters in init auto-assign to the matching field.
	# No explicit @name = $name lines needed.
	method init(@name, @rank, @soliloquy: '')
	end

	method greet()
		return @rank + ' ' + @name
	end

	method recite()
		puts @name + ': ' + @soliloquy
	end

	# May change to to.string (nested-method-style) in a future revision.
	method to_string()
		return @rank + ' ' + @name
	end

	method on_close()
		puts @name + ' exits.'
	end
end

$hamlet = $character.new(name: 'Hamlet', rank: 'Prince', soliloquy: 'To be or not to be')
$hamlet.greet          # 'Prince Hamlet'
$hamlet.recite         # Hamlet: To be or not to be
$hamlet.name           # 'Hamlet'      (auto-generated getter)
$hamlet.name = 'Bob'   # assigns       (auto-generated setter)
puts $hamlet           # Prince Bob    (via to_string)
# ... when $hamlet's last reference drops:
                       # Bob exits.    (via on_close)
~~~

**Auto-generated accessors.** `get: true` on a field creates a public method with the field's name — `.name`, `.rank`, `.soliloquy` — that returns the current value. `set: true` creates a paired setter with the `=` suffix — `.name=`, `.rank=`, `.soliloquy=` — that assigns a new value. Callers reach them with `$hamlet.name` and `$hamlet.name = 'new'` without the class author writing those methods explicitly.

Three of those are **engine-invoked** — not called by user code, called by the engine at the right moment:

- `init` — runs during `.new()` with the field arguments. The `@name`-shaped parameter form auto-assigns each named param to its matching field, so the body often ends up empty.
- `to_string` — runs whenever the object needs a string representation (`puts $hamlet`, string concatenation, etc.).
- `on_close` — runs when the engine destroys the object (deterministic GC hook).

Method definitions can be written with an explicit `&` sigil (`method &greet()` — matching the general callable-value sigil), but examples in this doc omit the `&` for readability. Both forms are legal.

The rest of this doc breaks each piece down.

## The class body

The bare form is `class ... end`. The class body evaluates to a class object; assign it to whatever variable or storage location makes sense:

~~~caspian
$widget = class
	# ... class body ...
end
~~~

**Inline label** — the `class # widget` convention adds a human-readable label immediately after the keyword. The label doesn't participate in dispatch or identity; it's purely a readability aid for code review, debug output, and error messages ([concepts § Class inline label](https://puck.uno/documentation/requirements/caspian/concepts) — settled convention):

~~~caspian
$widget = class # widget
	# ... class body ...
end
~~~

The class object doesn't carry a name at the language level — where it lives (the variable, the download URL, the record key) is where you find it. That principle applies uniformly: a class stored in `$widget` is at `$widget`; a class published for download at `https://puck.uno/color/` is at that URL; the same class stored somewhere else is at that somewhere-else. Publication addresses are storage locations, not intrinsic identity.

## Fields

`field` declares a bucket entry the class expects instances to carry, along with its constraints. The field name is written with the `@` sigil (matching how the field is accessed inside methods):

~~~caspian
class # character
	field @name,      class: :string
	field @age,       class: :number, min: 0, integer_only: true
	field @homeworld, class: Planet
end
~~~

**Common settings:**

| Setting | Description |
|---|---|
| `class:` | The field's type. Symbols for built-ins (`:string`, `:number`, `:boolean`, `:hash`, `:array`, `:timestamp`, etc.), class objects for user classes. |
| `default:` | Value used when the caller doesn't supply one. |
| `get:` / `set:` | Booleans. Auto-generate a reader / writer method for the field. |
| `collapse:` | Boolean. Compact-serialization hint for storage/transport. |

**Mikobase-only settings.** The Caspian class DSL recognizes these keys for cross-surface compatibility, but they don't affect the class at the language level — they're honored only when a class is used as a Mikobase record shape:

- **`required:`** — a record-level presence check applied by the store, not the language. A Caspian class never rejects an instantiation for a missing field.

Caspian classes accept any field the caller passes to `.new()`; they never validate presence at the language level. That validation belongs to whichever store persists the instance.

**Type-specific settings** — each type accepts additional keys relevant to its shape. Numbers: `min`, `max`, `gte`, `lte`, `integer_only`. Strings: `min_length`, `max_length`, `pattern`. Arrays: `of` (element type), `min_elements`, `max_elements`. Hashes: `fields` (inline sub-field declarations), `of` (element type for uniform hashes), `default` (per-field defaults inside the hash).

### Auto-getters and auto-setters

The `get:` and `set:` flags on `field` auto-generate reader and writer methods for the field. The generated methods are named after the field (without the `@` sigil):

~~~caspian
class # widget
	field @label, class: :string, get: true, set: true
end

$widget = $widget_class.new(label: 'primary')
$widget.label            # 'primary' — auto-generated getter
$widget.label = 'other'  # auto-generated setter
~~~

`get: true` alone creates a getter only; `set: true` alone creates a setter only. Callers wanting bucket-shaped subscript access (`$widget[:label]`) instead of named accessors should use one of the [bucket-access utility classes](https://puck.uno/documentation/requirements/caspian/built-in-classes/bucket-access).

### `getter` shorthand

`getter :name, value` is a one-liner shortcut for the common pattern of "put a value in the bucket and expose it via a getter method." The line below sets `%bucket['foo'] = 'foo'` on every new instance and creates a `.foo` method that returns `@foo`:

~~~caspian
class
	getter :foo, 'blah'
end
~~~

Equivalent to the full field form:

~~~caspian
class
	field @foo, default: 'blah', get: true
end
~~~

**Both arguments required.** The first argument is a symbol naming the bucket entry and the getter method; the second is any expression producing the value to store.

**Value is a fresh expression on each construction.** Same evaluation rule as `default:` on parameters — the expression re-runs for every instance, so `getter :opts, {}` gives each instance its own hash rather than a shared one.

**Internal writes still work.** `@foo = 'other'` from inside a method mutates the bucket entry the same as any other bucket field. `getter` controls the external surface (what callers see on the outside of the object), not internal access from sibling methods.

**Getter only — no matching setter.** If the field should also be externally writable, use the full `field @foo, default: 'foo', get: true, set: true` form. `getter` is deliberately narrower.

**When to reach for it.** Small classes with several preset values — decorators, tag classes, small handlers with a fixed label or type. Once a field needs a type constraint, custom validation, or the paired setter, drop back to the full `field` form.

## Methods

`method` declares a callable named surface on the class. Methods use the `&` sigil (the callable-value sigil):

~~~caspian
class # character
	method greet()
		return 'Hello, ' + @name
	end

	method record_visit($place)
		@visits.push($place)
		return null
	end
end
~~~

Inside a method body:

- **`%self`** is the receiver — the instance the method was called on.
- **`@name`** is shorthand for `%bucket['name']` — direct access to the instance's bucket.
- **`%bucket`** is the full bucket hash if the caller needs the bucket object itself.
- **`%call`** is the current call frame (arguments, caller, etc.).
- **`%chain`** is the ambient chain for role-mediated capabilities.

### Method parameters

Parameters follow the general Caspian call convention — positional args, keyword args (with `name:`), and defaults:

~~~caspian
class # widget
	method render($mode, $indent: 0, $verbose: false)
		# ...
	end
end

$widget.render('html')                        # positional
$widget.render('html', indent: 2)              # kwarg with default
$widget.render('html', indent: 2, verbose: true)
~~~

### Engine-invoked methods

A handful of method names are called by the engine at specific moments in an instance's lifecycle. The class author defines them; the engine invokes them:

| Method | When invoked |
|---|---|
| `init` | During `.new()`. Receives the field arguments as kwargs. The `@name`-shaped parameter form auto-assigns each named param to its matching field, so a bare `method init(@name, @rank)` body can be empty. |
| `to_string` | Whenever the instance needs a string representation (`puts $obj`, string concatenation, etc.). Should `return` the string. |
| `on_close` | When the engine destroys the instance (deterministic GC hook). |

Engine-invoked methods aren't called from user code directly; they fire on their triggers. Defining them is opt-in — a class with no `to_string` gets a default representation from the runtime; a class with no `on_close` has no cleanup hook.

`to_string` may migrate to a nested-method form (`to.string`) in a future revision, alongside a broader `to.*` conversion surface (`to.json`, `to.hash`, etc.). Current spec uses the flat name.

## Inheritance

`inherits` declares the class's parents. Caspian supports **multiple inheritance** — a class can inherit any number of others:

~~~caspian
class # officer
	inherits Person
	inherits Serializable
	inherits AuditLogged
end
~~~

Or the inline-list form:

~~~caspian
class # officer
	inherits Person, Serializable, AuditLogged
end
~~~

Inheritance is always **explicit**. There's no path-based, URL-based, or naming-convention-based inheritance — parent-class relationships come from the `inherits` clause and only from there.

The inherited classes contribute methods, fields, and other class-level structure to the child class. Method resolution walks the class's stack in order — see [object structure § Stack](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure/#stack) for the mechanics.

## Abstract classes

`abstract true` marks a class as abstract — direct instantiation raises. Subclasses can be instantiated normally:

~~~caspian
class # animal
	abstract true

	field @name, class: :string

	method speak()
		# subclasses override
	end
end
~~~

`$animal.new(name: 'x')` raises because `$animal` is abstract; a concrete subclass's `.new()` works normally.

## Amending an existing class

A class value can be extended after its initial `class ... end` block using the `amend` construct. The body has the same shape as a class body, and its declarations are added to the class:

~~~caspian
$foo = class
	method bar()
	end
end

amend $foo
	method gup()
	end
end
~~~

After the `amend` block runs, `$foo` responds to both `.bar` and `.gup`.

**`$foo` must already hold a class value.** If the variable is unbound or holds something else, `amend` raises. There's no create-or-extend branch — creation goes through `class ... end`; extension goes through `amend $var ... end`; the two operations don't share a syntactic form.

**Body shape.** Everything legal inside `class ... end` is legal inside `amend ... end` — methods, fields, inheritance additions, engine-invoked hooks, everything. Each declaration means the same thing it would have meant if it had appeared in the original class body.

**Common use.** Rebuilding a Ruby-style "class defined across multiple files" pattern: the base declaration lives in one place, and cross-cutting additions (mixins, domain-specific extensions, plugin registrations) live in others.

**Open — mutation vs. derived class.** Whether `amend` mutates the existing class object in place or mints a new class that inherits from the original and rebinds `$var` to it is not yet settled. The choice affects existing instances constructed before the amend:

- **Mutation.** The class object at `$foo` keeps its identity across the amend. Instances constructed *before* the amend gain access to `.gup` immediately, because they hold a reference to the same class object. Matches Ruby's semantics; sits awkwardly with any "class objects are immutable" principle.
- **Derivation.** The amend mints a new class that inherits from the pre-amend class, and rebinds `$foo` to the new class. Existing instances still reference the pre-amend class and continue to see only `.bar`; only instances built from `$foo.new` *after* the amend see both methods. Safer under immutability, but any name held elsewhere still points at the old class.

Written form is the same either way — this is a semantics decision that surfaces when you ask what happens to older instances or to other names holding the pre-amend value.

## Storage of the class body's evaluation

The `class ... end` construct evaluates to a **class object**. Where it goes depends on what the caller writes:

- **Assign it**: `$widget = class ... end` — the class object lives at `$widget`.
- **Store it in a hash or record**: `$library[:widget] = class ... end` — the class object lives inside that hash.
- **Publish it via `%puck`**: `%puck.publish('https://foo.com/widget', class ... end)` — the class object lives at the given URL for download.
- **Use it inline as an argument**: `some_method(class ... end)` — the class object is passed to that method, which stores it wherever the method decides.

The "things live where you store them" principle applies fully — the class object has no intrinsic name or location.

## Open questions

Areas the current spec does not settle:

- **Helpers.** Some designs allow a class body to declare lazy-initialized helper objects namespaced off the parent. Whether Caspian ships this construct, what its declaration form is, and how it composes with method dispatch is TBD.
- **Hooks declared in-class.** Currently `on_close` is declared inside the class body but `before_save` / `after_save` (Mikobase transaction hooks) are registered externally. Whether the whole hook surface should be class-body-declared, external-only, or a mix is TBD.
- **`.implements?($other_class)`** — a runtime structural conformance check that returns true when the receiver's class carries every method the other class does. Sketched in the old spec; scope for V1 not yet confirmed.
- **Body serialization format.** Class definitions can be stored and transported as JSON records (in worldlets, Mikobase records, Puck-protocol messages). The exact JSON shape for method bodies (Caspian source string vs. CaspianJ IR tree vs. both) has a couple of pending decisions.

## Testing

- **`class ... end` evaluates to a class object** — `$c = class end; $c.object.isa?(class)` is true.
- **Inline label parsed but has no dispatch effect** — `class # widget ... end` and `class ... end` produce identical class objects apart from the label metadata.
- **`.new()` builds an instance** — after `$c = class field @x, class: :number end`, `$c.new(x: 1)` returns an object with `@x == 1`.
- **`field` declares bucket entry** — a class with `field @name, class: :string` builds instances where `@name` is bucket-backed.
- **Field default applied on construction** — after `field @rank, default: 'ensign'`, an instance built without a `rank:` arg has `@rank == 'ensign'`.
- **Field type constraint at construction** — a Caspian class never rejects; passing `rank: 5` where `class: :string` is set still binds (validation is Mikobase-side).
- **`get: true` auto-generates getter** — `$obj.name` returns the field value.
- **`set: true` auto-generates setter** — `$obj.name = 'x'` mutates the bucket entry.
- **`get: true` alone: no setter** — with `get: true` but not `set:`, `$obj.name = 'x'` raises.
- **`set: true` alone: no getter** — with `set: true` but not `get:`, reading `$obj.name` raises.
- **`getter :name, value` sets bucket entry and exposes reader** — `getter :foo, 'blah'` creates instances where `@foo == 'blah'` and `$obj.foo` returns `'blah'`.
- **`getter` produces a fresh expression per instance** — `getter :opts, {}` gives each instance its own hash; mutating one does not affect another.
- **`getter` writes via `@foo` from within methods** — `@foo = 'x'` inside a method mutates the bucket entry.
- **`getter` produces no external setter** — `$obj.foo = 'x'` raises with `getter`.
- **`getter` requires both arguments** — `getter :foo` with no value raises at definition.
- **`method` declares callable** — `method greet() return 'hi' end` produces `$obj.greet` returning `'hi'`.
- **Method sees `%self` as receiver** — `method me() return %self end` returns the receiver.
- **Method sees `@field`** — `method name() return @name end` reads the bucket.
- **`method &greet` (with sigil) equivalent to `method greet`** — both forms produce the same class method.
- **`inherits Foo`** — a subclass responds to methods defined on `Foo`.
- **Multiple inheritance** — `inherits A; inherits B` gives access to methods from both.
- **Inline inherits list** — `inherits A, B, C` equivalent to three separate `inherits` lines.
- **`abstract true` blocks direct `.new`** — an abstract class's `.new(...)` raises.
- **Abstract class subclass instantiable** — a concrete subclass of an abstract class's `.new()` works normally.
- **`init` runs during `.new`** — `method init(@name) end` called as `.new(name: 'p')` binds `@name = 'p'`.
- **`init` `@param` auto-assigns** — the `@name` parameter form assigns directly into the bucket with no explicit body.
- **`init` receives keyword args** — `.new(name: 'p', rank: 'c')` binds both.
- **`to_string` invoked by `puts`** — `puts $obj` produces whatever `to_string` returns.
- **`on_close` invoked at destruction** — after the last reference to an instance drops, `on_close` runs; observable via side effect.
- **`amend $var ... end` extends existing class** — after amending, the class responds to newly added methods.
- **`amend` on unbound variable raises** — `amend $undefined ... end` errors.
- **`amend` on non-class value raises** — `amend $string ... end` errors.
- **`amend` body accepts every class-body construct** — methods, fields, `inherits`, `on_close` all legal inside `amend`.
- **Method resolution walks class stack** — a method defined on a parent is reachable through the child instance.
- **Child method shadows parent method** — same-name method on the child takes precedence over inherited one.
- **Storing class in a hash** — `$library[:widget] = class end; $library[:widget].new()` works.
- **Publishing via `%puck`** — `%puck.publish(url, class end)` makes the class downloadable at that URL.
- **`class` inside another expression** — passing `class end` as an argument works; the receiver gets the class object.
- **Class carries no intrinsic name** — the class object has no `.name` property tied to any variable it was assigned to.

## Related

- [Classes are the only method-carrier](https://puck.uno/documentation/requirements/caspian/concepts#classes-are-the-only-method-carrier) — the design principle that motivates the flexibility of the class construct.
- [Object structure](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/structure) — what a class object contributes to an instance's stack, and how method dispatch walks the stack.
- [Nested methods](https://puck.uno/documentation/requirements/caspian/classes/nested) — the `nested :name ... end` construct inside a class body for organizing method namespaces.
- [Downloaded methods](https://puck.uno/documentation/requirements/caspian/classes/downloaded-methods) — the instance-side counterpart for ad-hoc method application via `$foo.$method`.
