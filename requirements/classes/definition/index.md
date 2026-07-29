# Class definition
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_classes_definition",
	"role": "spec for how classes are defined in Caspian — the `class ... end` DSL, the inline `# label` convention, the DSL bare-word commands active inside the class body (field, method, private, inherits, abstract), field declarations with their constraints, method definitions, private methods (chainable via the `private method foo()` DSL prefix that transforms the method object it receives), inheritance (single and multiple), engine-invoked hooks (init, to_string, on_close), abstract classes, auto-getters/setters, the `.call` method convention (defining a method named `.call` makes an instance amp-invocable — `&$instance(args)` desugars to `$instance.call(args)` at CaspM time, no runtime property lookup), how a class body becomes the class object that appears in an instance's stack, declarations targeting the class itself — `@x = v` sets the class's bucket, `method %self.foo()` attaches a singleton method to the class, `%self.object.field :x, ...` adds a field to the class-as-instance — with the underlying rule that `%self` is the class inside a class body and any object-op works against it, and the `amend $var ... end` construct that extends an existing class with additional declarations (Ruby-style class reopening; mutation-vs-derived-class semantics still open). Uniqueness constraints and the `join` shorthand are Mikobase concepts and are not part of the Caspian class model.",
	"status": "draft — DSL surface for the common constructs spec'd; a few areas noted as TBD (helper namespaces, hook-in-class declaration, `implements?` structural check)",
	"audience": "developers writing Caspian classes; parser implementers; anyone reasoning about class construction"
}}
~~~

Every class in Caspian is defined by a **class body** — a block that declares fields, methods, inheritance, and other class-level structure. The body evaluates to a class object, which the caller stores wherever it wants.

Classes are the sole method-carrier in Caspian ([concepts § Classes are the only method-carrier](https://puck.uno/requirements/concepts#classes-are-the-only-method-carrier)); everything about attaching behavior to values goes through this construct.

## A complete example

A class with the everyday pieces — typed fields, a default, regular methods, and a few engine-invoked methods (`init`, `to_string`, `on_close`) — bound to a variable so it can be instantiated:

~~~caspian
$character = class # character
	field :name,      class: :string,               get: true, set: true
	field :rank,      class: :string,               get: true, set: true
	field :soliloquy, class: :string, default: '',  get: true, set: true

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

**Inline label** — the `class # widget` convention adds a human-readable label immediately after the keyword. The label doesn't participate in dispatch or identity; it's purely a readability aid for code review, debug output, and error messages ([concepts § Class inline label](https://puck.uno/requirements/concepts) — settled convention):

~~~caspian
$widget = class # widget
	# ... class body ...
end
~~~

The class object doesn't carry a name at the language level — where it lives (the variable, the download URL, the record key) is where you find it. That principle applies uniformly: a class stored in `$widget` is at `$widget`; a class published for download at `https://puck.uno/color/` is at that URL; the same class stored somewhere else is at that somewhere-else. Publication addresses are storage locations, not intrinsic identity.

## DSL bare-word commands

Inside a class body, certain bare words are recognized as **DSL commands** — callables scoped to the body. Each command is spec'd in its own section below:

| Command | Purpose |
|---|---|
| `field` | Declare a bucket entry with type and constraints. [Fields](#fields). |
| `private_const` | Declare a class-level frozen constant, internal-only (no external getter). [Constants](#constants). |
| `public_const` | Declare a class-level frozen constant with an external getter. [Constants](#constants). |
| `method` | Declare a class method. [Methods](#methods). |
| `private` | Mark a method as private. [Private methods](#private-methods). |
| `inherits` | Declare a parent class. [Inheritance](#inheritance). |
| `abstract` | Mark the class abstract. [Abstract classes](#abstract-classes). |

**No confusion with variables.** Every Caspian variable begins with `$`; no DSL command does. `private` the command and a would-be `$private` variable never look the same at the parse level.

**Chaining transformer commands.** Some commands take the value produced by the DSL expression that follows and return a mutated version. `method foo() ... end` evaluates to a method object; `private` accepts a method object, sets `.private = true`, and returns it. The two chain naturally:

~~~caspian
class # foo
	private method bar()
	end
end
~~~

Reads as: `method bar() ... end` produces a method object; `private` receives that value, mutates it, returns it. Chains of any length compose the same way — see [instance § autorun](../instance#autorun) for `autorun private method foo() ... end`. Commands with fixed-shape argument lists (`field :name, ...`, `inherits Person`, `abstract true`) don't participate in this chain — they take their own args, not a following DSL expression.

**Scope.** The class-body DSL is active inside `class ... end` and inside `instance ... end` (which inherits the class DSL and adds `autorun`). Outside those bodies, these words are not automatically callable.

## Fields

`field` declares a bucket entry the class expects instances to carry, along with its constraints. The field name is written as a **symbol** — the first arg is data (a name label), not a reference to a not-yet-existing field:

~~~caspian
class # character
	field :name,      class: :string
	field :age,       class: :number, min: 0, integer_only: true
	field :homeworld, class: Planet
end
~~~

**The `@` sigil is USE-site sugar, not declaration syntax.** `@foo` transpiles to the bucket-access shape (`{at: "foo"}` / `["scope", "setat", "foo", ...]`) and reads/writes the bucket entry at runtime regardless of whether a `field` declaration ever named it. `field @foo, ...` raises at class-body evaluation time — the DSL command requires a symbol name. Use `:foo`.

Neither form depends on the other: a `field :foo` declaration can register constraints and accessors for the `@foo` bucket entry, and `@foo` writes work without ever calling `field`. The two surfaces are orthogonal.

**Common settings:**

| Setting | Description |
|---|---|
| `class:` | The field's type. Symbols for built-ins (`:string`, `:number`, `:boolean`, `:hash`, `:array`, `:timestamp`, etc.), class objects for user classes. |
| `default:` | Value used when the caller doesn't supply one. Stored as an expression and re-evaluated on every construction — see below. |
| `get:` / `set:` | Booleans. Auto-generate a reader / writer method for the field. |
| `getset:` | Boolean. Shorthand for `get: true, set: true` — one flag, both accessors. |
| `collapse:` | Boolean. Compact-serialization hint for storage/transport. |

**Field defaults are fresh on every construction.** Same rule as [parameter defaults](tag:parameter-defaults): a `default:` value is stored as an unevaluated expression and re-runs when a new instance is constructed without providing that field. Mutable defaults (`[]`, `{}`, strings, class instances) produce a fresh object per instance — never a shared mutable object across instances. Two widgets each declared with `field :items, default: []` get two separate arrays; mutating one instance's `@items` does not affect any other instance's.

**Mikobase-only settings.** The Caspian class DSL recognizes these keys for cross-surface compatibility, but they don't affect the class at the language level — they're honored only when a class is used as a Mikobase record shape:

- **`required:`** — a record-level presence check applied by the store, not the language. A Caspian class never rejects an instantiation for a missing field.

Caspian classes accept any field the caller passes to `.new()`; they never validate presence at the language level. That validation belongs to whichever store persists the instance.

**Type-specific settings** — each type accepts additional keys relevant to its shape. Numbers: `min`, `max`, `gte`, `lte`, `integer_only`. Strings: `min_length`, `max_length`, `pattern`. Arrays: `of` (element type), `min_elements`, `max_elements`. Hashes: `fields` (inline sub-field declarations), `of` (element type for uniform hashes), `default` (per-field defaults inside the hash).

### Auto-getters and auto-setters

The `get:` and `set:` flags on `field` auto-generate reader and writer methods for the field. The generated methods are named after the field (without the `@` sigil):

~~~caspian
class # widget
	field :label, class: :string, get: true, set: true
end

$widget = $widget_class.new(label: 'primary')
$widget.label            # 'primary' — auto-generated getter
$widget.label = 'other'  # auto-generated setter
~~~

`get: true` alone creates a getter only; `set: true` alone creates a setter only. `getset: true` is a one-flag shorthand for both — `field :foo, getset: true` is exactly `field :foo, get: true, set: true`; the class DSL expands it before dispatching.

**Exactly one of `get:` / `set:` / `getset:` may appear on a field declaration.** Any combination — contradictory (`getset: true, get: false`), redundant (`getset: true, get: true`), or otherwise — raises at class-body evaluation with a message naming the two flags. Contradictions are ambiguous (which one wins?); pure redundancy is almost always a copy-paste slip or half-finished refactor. Either way the developer's intent is unclear enough that surfacing it is better than silently picking an interpretation.

Callers wanting bucket-shaped subscript access (`$widget[:label]`) instead of named accessors should use one of the [bucket-access utility classes](https://puck.uno/requirements/built-in-classes/bucket-access).

## Constants

Class-body DSL for declaring **class-level constants** — values shared across all instances, initialized once at class-definition time, and frozen against reassignment. Two commands, distinguished by external visibility:

- **`private_const :name, value`** — sets the class-bucket field, freezes it. No external accessor; reachable inside class methods via `@name`.
- **`public_const :name, value`** — same as `private_const` plus a getter method so instances can read the value externally as `$instance.name`.

~~~caspian
class # my_database
	private_const :internal_id, 'abcd-1234'
	public_const :path, '/home/miko/shakespeare.db'

	method report()
		return @internal_id + ': ' + @path
	end
end

$db = $my_database.new()
$db.path         # '/home/miko/shakespeare.db' — public_const getter
$db.report       # 'abcd-1234: /home/miko/shakespeare.db' — internal_id readable from inside
$db.internal_id  # raises — no getter for private_const
~~~

### Desugaring

**`private_const :name, value`** desugars to:

~~~caspian
@name = value
%bucket.freeze_field 'name'
~~~

**`public_const :name, value`** desugars to:

~~~caspian
@name = value
%bucket.freeze_field 'name'
%self.field :name, get: true
~~~

`public_const` is a strict superset of `private_const` — same first two steps plus the getter declaration.

### Fail-loud on redefine

Redefining a constant raises. Since the second step of both desugarings freezes the field, any subsequent `@name = other_value` (whether from another `private_const :name, ...` call or from anywhere else in the class body) hits the frozen-field guard and raises.

~~~caspian
class
	private_const :path, '/first'
	private_const :path, '/second'  # raises — 'path' is already frozen
end
~~~

No silent overwrite. Fail-loud behavior comes for free from the freeze mechanism — no special-case logic in the DSL commands.

### Composition

Both commands compose from primitives spec'd elsewhere:

- **`%bucket['name'] = value`** — write to the class's bucket (see [built-in-classes/primitives/hash](https://puck.uno/requirements/built-in-classes/primitives/hash)).
- **`.freeze_field 'name'`** — freeze the field ([hash § Freezing fields](https://puck.uno/requirements/built-in-classes/primitives/hash#freezing-fields)).
- **`field :name, get: true`** — declare the getter ([Fields](#fields)).

The DSL commands are sugar over these primitives; developers who need non-standard combinations (e.g., a private constant with a hand-written getter that computes something) can compose the primitives directly.

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

### Private methods

`private` is a class-body DSL command that marks a method as private — callable from inside the class's own methods, not from outside. It takes the method object produced by a following `method ... end` declaration, sets `.private = true` on it, and returns it:

~~~caspian
class # widget
	method public_op()
		return %self.helper()
	end

	private method helper()
		return @count * 2
	end
end
~~~

`.helper` is reachable from `.public_op` (same class), unreachable from outside the class.

Three equivalent forms — all set the same `.private` property. Use whichever reads best:

- **Bare-word command.** `private method foo() ... end` — the form shown above. Setting the property at the declaration site.
- **Property assignment on a captured method value.** `$m = method foo() ... end; $m.private = true` — useful when the setting is conditional.
- **Getter/setter surface on the method object.** `$m.private` reads the flag; `$m.private = true` writes it. Same as the assignment form above, called out because it's part of the general [method surface](https://puck.uno/requirements/functions/method#method-surface).

**Access is checked at dispatch time via [`%call.method_class`](https://puck.uno/requirements/global-methods/call/#call-method-class).** When code dispatches a method marked `.private = true`, the engine reads the current frame's `%call.method_class` — the class the currently-executing method was defined on. If that class defines the private method being dispatched (or is a subclass that inherits it), the call proceeds. Otherwise, it raises. The check is against the CALLING FRAME, not against the reference in hand — so:

- A sibling method calling `%self.helper()` from inside the class body succeeds; `%call.method_class` in the sibling's frame is the same class carrying `.helper`.
- Outside code calling `$obj.helper()` raises; the outside frame's `%call.method_class` is either some other class or `null`.
- Capturing `%self` inside a method and returning it (`method &me() return %self end`) doesn't grant private access to whoever receives the reference. The reference itself carries no access token — the calling frame's `%call.method_class` at dispatch time is what governs. See [functions/method § Calling sibling methods](https://puck.uno/requirements/functions/method#calling-sibling-methods) for the walkthrough.

Real capability restriction (as opposed to convention-plus-enforcement) uses [jails](https://puck.uno/requirements/built-in-classes/object/methods/#jail) — pass a jail exposing only the public methods and outside code literally cannot reach anything else.

Full runtime semantics (dispatch rule, error on external call) are spec'd on [functions/method § Method surface](https://puck.uno/requirements/functions/method#method-surface).

### The `.call` method — making a class amp-invocable

A class becomes `&`-invocable by defining a method named `.call`. `&$my_instance(args)` desugars to `$my_instance.call(args)` — there's no runtime property lookup, no class-level "which method is main?" question, just a direct method call by the name `call`.

~~~caspian
$greeter = class # greeter
	method hello($name)
		return 'Hello, ' + $name
	end

	method &call($name)
		return %self.hello($name)
	end
end

&$greeter('Puck')   # invokes .call — returns 'Hello, Puck'
~~~

Same convention as Ruby (`Proc#call`), Python (`__call__`), Java (`Callable.call()`). If a class wants domain-specific naming for its callable verb — say `Report` with `.generate` as the semantic action — write `.call` as a one-line wrapper: `method &call() &generate end`.

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

The inherited classes contribute methods, fields, and other class-level structure to the child class. Instance dispatch and `super()` — including multiple-inheritance walk order, diamond handling, and the no-cache guarantee — are spec'd on [method resolution](tag:method-resolution).

## Abstract classes

`abstract true` marks a class as abstract — direct instantiation raises. Subclasses can be instantiated normally:

~~~caspian
class # animal
	abstract true

	field :name, class: :string

	method speak()
		# subclasses override
	end
end
~~~

`$animal.new(name: 'x')` raises because `$animal` is abstract; a concrete subclass's `.new()` works normally.

## Declarations on the class itself

The class-body DSL — `field :name`, `method &name()`, `inherits X`, etc. — describes what INSTANCES of the class get. Sometimes you want to attach something to the CLASS OBJECT itself: a value in its bucket, a utility method callable on the class directly, or a metadata slot with generated accessors on the class object. Every one of those uses the same rule: the class is an object, so operate on it the way you'd operate on any object — and inside a class body, `%self` is that object.

### `@name = value` — set the class's bucket

`@name = value` is sugar for `%self.bucket[:name] = value` (see [sigils](https://puck.uno/requirements/syntax/sigils)). Inside a class body `%self` is the class, so the assignment lands in the class's own bucket, not an instance's:

~~~caspian
$widget = class
	@version = 3
	@created_at = %('core:now').stamp
end
~~~

`$widget.bucket[:version]` returns `3`. `$widget.new().bucket[:version]` isn't there — new instances get a fresh bucket, not the class's.

### `method %self.name() ... end` — attach a method to the class

The singleton-method form — `method $obj.name() ... end` — attaches a method to a specific object. Using `%self` as the receiver in a class body attaches the method to the class itself:

~~~caspian
$widget = class
	method %self.about()
		return 'widget factory, version ' + @version.to_s
	end
end

$widget.about()   # 'widget factory, version 3'
~~~

The method is callable on the class directly; instances don't inherit it via their normal method dispatch (it lives on the class's shadow, not on the class's method table for instances).

### `%self.object.field :name, ...` — add a field to the class-as-instance

Bare `field :name, kwargs` at class body declares an INSTANCE-side field. To add a field to the class OBJECT itself — a bucket slot with generated accessors on the class — write the operation out in full:

~~~caspian
$widget = class
	%self.object.field :version, class: :integer, default: 3, getset: true
end

$widget.version       # 3 (via the generated getter)
$widget.version = 4   # sets the class-level slot
~~~

The long form is intentional. Adding a field to the class itself (as opposed to its instances) is rare — the verbose syntax keeps it visible in code review and hard to write by accident.

### Rule of thumb

Inside a class body:

- Bareword DSL (`field :x`, `method &y()`, `inherits Z`, `abstract true`, etc.) — declares things for INSTANCES.
- Receiver-form with `%self` (`@x = 1`, `method %self.y()`, `%self.object.field :z`) — declares things on the CLASS itself.

The pattern generalizes: any declaration you'd write on an object with a receiver-form (`$obj.something(...)`) works inside a class body against `%self`, and the target is the class as an object.

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
- **Publish it via `%import`**: `%import.publish('https://foo.com/widget', class ... end)` — the class object lives at the given URL for download.
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
- **`.new()` builds an instance** — after `$c = class field :x, class: :number end`, `$c.new(x: 1)` returns an object with `@x == 1`.
- **`field` declares bucket entry** — a class with `field :name, class: :string` builds instances where `@name` is bucket-backed.
- **`field @name, ...` raises** — the `@`-sigil is USE-site sugar for `%bucket[...]`; the declaration form requires a symbol. `field @name, class: :string` raises at class-body evaluation.
- **Field default applied on construction** — after `field :rank, default: 'ensign'`, an instance built without a `rank:` arg has `@rank == 'ensign'`.
- **Field default is fresh per instance** — for `field :items, default: []`, two instances built without an `items:` arg have separate arrays; mutating one instance's `@items` doesn't affect the other.
- **Field default expression re-runs per construction** — for `field :id, default: &generate_id()`, two instances have different `@id` values (assuming `&generate_id` produces distinct values).
- **Field type constraint at construction** — a Caspian class never rejects; passing `rank: 5` where `class: :string` is set still binds (validation is Mikobase-side).
- **`get: true` auto-generates getter** — `$obj.name` returns the field value.
- **`set: true` auto-generates setter** — `$obj.name = 'x'` mutates the bucket entry.
- **`get: true` alone: no setter** — with `get: true` but not `set:`, `$obj.name = 'x'` raises.
- **`set: true` alone: no getter** — with `set: true` but not `get:`, reading `$obj.name` raises.
- **`getset: true` generates both accessors** — with `field :name, getset: true`, both `$obj.name` and `$obj.name = 'x'` work; equivalent to `get: true, set: true`.
- **Combining `get:` / `set:` / `getset:` raises** — any combination raises at class-body evaluation. Contradictory (`field :name, getset: true, get: false`) and pure-redundancy (`field :name, getset: true, get: true`) cases both raise with a message naming the two flags.
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
- **Publishing via `%import`** — `%import.publish(url, class end)` makes the class downloadable at that URL.
- **`class` inside another expression** — passing `class end` as an argument works; the receiver gets the class object.
- **Class carries no intrinsic name** — the class object has no `.name` property tied to any variable it was assigned to.
- **`public_const` exposes a getter on instances** — after `class ... public_const :path, '/x' end`, `$c.new().path` is `'/x'`.
- **`private_const` does NOT expose a getter** — after `class ... private_const :id, 'abc' end`, `$c.new().id` raises with method-missing.
- **`private_const` is reachable inside class methods via `@name`** — after `class ... private_const :id, 'abc'; method report() return @id end end`, `$c.new().report` is `'abc'`.
- **Constants are frozen against reassignment inside the class** — after `public_const :path, '/x'`, any `@path = '/y'` from inside a method raises.
- **Redefining a constant in the class body raises** — `private_const :path, 'a'; private_const :path, 'b'` raises on the second declaration.
- **Constants are shared across all instances** — two instances of the same class see the same constant value; mutating one does not affect any other (constants are frozen anyway).
- **Constant expression evaluates once at class-definition time** — `private_const :stamp, %('core:now').stamp` captures the timestamp at class-definition, not at each instance construction; every instance sees the same value.

## Related

- [Classes are the only method-carrier](https://puck.uno/requirements/concepts#classes-are-the-only-method-carrier) — the design principle that motivates the flexibility of the class construct.
- [Object structure](https://puck.uno/requirements/built-in-classes/object/structure) — what a class object contributes to an instance's stack, and how method dispatch walks the stack.
- [Nested methods](https://puck.uno/requirements/classes/nested) — the `nested :name ... end` construct inside a class body for organizing method namespaces.
- [Downloaded methods](https://puck.uno/requirements/classes/downloaded-methods) — the instance-side counterpart for ad-hoc method application via `$foo.$method`.
