# Basic helper

~~~vibecode
{"vibecode": {
	"doc": "ideas_helpers_basic",
	"role": "design doc for the inline-helper pattern: a class body declares its helpers via `helper &name(inherits:[@base]) ... end` DSL commands. The parent class body IS the helper's declaration site — no separate .casp file, no wiring call at construction time. Shared behavior across a family of helpers goes through a plain class assigned to a bucket field (`@base = class ... end`) and referenced by concrete helpers via the `inherits:` kwarg. Isolation: helper reaches its parent only via `@target.public_method()`, not through the parent's `%bucket`. Companion to [ideas/helpers/agents](agents), which spec's the internal-access variant.",
	"status": "active_design — pattern shape settled from design conversation; syntax details and framework mechanics still being worked out",
	"context": "started after the helper-based approach for HTTP requests was walked back for complexity reasons; this pattern collapses the two-step 'define a helper class + wire it up' friction into a single inline declaration. Supersedes the older `caspian.uno/helpers.casp` download-based approach (moved to ideas/helper-helper as historical reference)."
}}
~~~

The class body declares its helpers inline. Each helper gets a `helper &name(inherits:[@base]) ... end` block inside the parent class; the helper's methods are defined right there. No separate `.casp` file, no `.helpers.add` wiring call at parent-construction time. Every helper reaches its parent via `@target`.

## The pattern

~~~caspian
class
	@base = class
		method unique()
			return false
		end
	end

	helper &accept(inherits:[@base])
		method &init(@target)
			@items = []
		end

		method unique()
			return true
		end
	end
end
~~~

Three pieces at play:

### Abstract base as a plain class

`@base = class ... end` — a regular class assigned to a bucket field. No dedicated `helper_base` DSL, no `abstract` marker. It becomes reusable inheritance scaffolding by virtue of being defined and referenced by name; nothing about `class` itself makes it a helper. Only concrete `helper &name` calls wrap classes with the accessor-wiring machinery.

The base can declare defaults (like `unique()` returning `false`) that concrete helpers override. Classic template-method pattern without extra syntax.

### `helper &name(inherits:[@base])` as the DSL command

`helper &accept(inherits:[@base])` — a class-body DSL command that:

1. Creates an anonymous helper class whose inherits list is `[caspian.uno/helper.casp, @base]` — the standard helper root first (for the framework machinery), then anything listed in the `inherits:` kwarg.
2. Runs the block body against that anonymous class (method declarations, field declarations, etc.).
3. Registers the class as `.accept` on the parent's instances — reading `$instance.accept` returns a fresh instance of the helper class constructed with the parent as `@target`.

The `inherits:` kwarg is an array, so multiple inheritance is a first-class parameter, not a special-case syntax.

### `method &init(@target)` constructor

`@target` in the parameter list auto-assigns to the helper's own bucket. The framework passes the parent object as the constructor arg; the helper stashes it in `@target` for later use.

Any state the helper maintains across method calls (`@items` in the example) initializes here — fresh per instance.

## Delegation

Delegation collapses the boilerplate of "expose another object's methods as if they were methods on the helper itself." The helper declares which methods forward and to what target; delegations are stored on the class object and consulted at dispatch time, not compiled into methods at class-definition.

### The dispatch model

When a method is called on a value:

1. **Check the value itself.** Walk the platter stack, including any shadow class, per the standard [method-resolution](tag:method-resolution) algorithm. If found, dispatch normally — no delegation consulted.
2. **If not found, walk the value's class's delegations** in declaration order. For each delegation entry:
   - **Explicit method list.** If the called method name is in the list, evaluate the target (read the field or call the method) and dispatch to it.
   - **Class-ref.** Call `.has_method?(name)` on the class ref ([classes/has-method](tag:has-method)). If true, evaluate the target and dispatch to it.
3. **If no delegation responds, raise** (standard no-such-method behavior).

The class-ref check is metadata-only — inspecting the class's method surface, not calling anything on the target. That keeps the check cheap and side-effect-free. The target itself is only evaluated once the class ref has confirmed the method exists.

**Class mutation propagates.** Because `.has_method?` runs per dispatch, adding a method to a class ref (via `.inherited.push` or method addition) makes it delegable immediately. Removing it makes it undelegable immediately. No cached forwarder list to invalidate.

### The DSL

`delegate` is a class-body DSL command — peer to `field`, `method`, `private`. Two positional args: target, then either a method list or a class reference. Delegations are stored on the class object at declaration time; nothing is compiled into methods.

~~~caspian
helper &accept(inherits:[@base])
	field :items
	delegate :@items, ['<+', 'shift']

	method &init(@target)
		@items = []
	end
end
~~~

The `delegate` line appends an entry to the class's [`.delegations`](#the-delegations-runtime-property) — target `:@items`, list `['<+', 'shift']`. That's the whole class-definition-time effect. At dispatch time, `$helper <+ 'text/html'` runs the search from [The dispatch model](#the-dispatch-model), matches `<+` in the explicit list, reads `@items`, and calls `<+` on the array.

### Target syntax

The target is a symbol whose sigil disambiguates. Every target carries a sigil.

- **`:@field_name`** — a bucket field. Dispatch reads `%bucket[field_name]` at each call to get the target.
- **`:&method_name`** — a method on the helper (or inherited). Dispatch calls the method at each call to get the target; never memoized, since the method might return a different object each time.

~~~caspian
delegate :@items, ['<+', 'shift']       # field target
delegate :&bar, ['some_method']         # method target
~~~

Matches Caspian's sigil convention everywhere — `@` for bucket fields, `&` for methods.

### Method-list arg

Three forms accepted for the second arg:

- **Single method name (string).** `delegate :@items, '<+'` — one entry, single-method list.
- **Array of method names.** `delegate :@items, ['<+', 'shift', 'length']` — one entry, explicit list.
- **Class reference.** `delegate :@items, %('core:array')` — one entry, class-ref. See below.

The single-vs-array polymorphism follows Caspian's usual pattern for values that could reasonably be either shape.

### Class-reference form

The ergonomic shortcut for "delegate whatever methods this class publishes." Instead of enumerating every method name of `core:array`, store the class ref and let dispatch consult it per call:

~~~caspian
helper &accept(inherits:[@base])
	field :items
	delegate :@items, %('core:array')

	method &init(@target)
		@items = []
	end
end
~~~

`$helper <+ 'x'`, `$helper.length`, `$helper.each`, `$helper.shift` — each call runs the dispatch model, sees the class-ref entry, asks `core:array.has_method?(name)` — true for these — reads `@items`, and dispatches to the array.

Ruby's `Forwardable` requires enumerating each method name because Ruby doesn't have a `.has_method?` predicate on class objects to consult at dispatch time. Caspian's first-class class objects let you name the type contract and let the framework check live. The check is cheap (metadata inspection, not method calls); the target is only evaluated once the class ref has confirmed the method exists.

**Duck-typed at runtime.** The class ref is a promise about the target's shape — "trust me, `@items` will respond to whatever `core:array` publishes." If the actual runtime target doesn't respond (wrong type stashed in the field, method returned something else), dispatch raises when the delegated method is called. The framework doesn't verify at declaration time that the field's stored type matches the class ref; standard Caspian duck-typing posture.

### Class mutation is live

Because the class-ref check runs per dispatch, mutating the referenced class propagates to every consumer immediately. Adding a method (via `.inherited.push` on the class ref or a method definition) makes it delegable on the next call. Removing it stops delegation for that name on the next call.

Not a snapshot at declaration time — that would be redundant with looking through the class anyway, and would go stale on any mutation. The class ref is the source of truth, consulted live.

If a helper needs frozen delegation (e.g., the developer wants to lock down the surface even against future mutations of the class ref), the workaround is to enumerate the methods explicitly via an array list, taking the snapshot into the class's own `.delegations` structure.

### Methods act on the target, not the helper

A call dispatched through delegation operates on the TARGET (the field's value or the method's return), not on the helper. `$helper <+ 'text/html'` mutates `@items`; the helper's own state is unchanged.

Return values come from the target. If the target's method returns the target itself for chaining (as `.push` sometimes does), the caller sees the underlying object — potentially a reference leak. That's the developer's call; delegation doesn't rewrap.

### The `.delegations` runtime property

The class object exposes `.delegations` — a hash mapping target-specifier strings to method lists or class refs. Populated by the `delegate` DSL at class-definition time; readable and mutable at runtime for introspection or monkey-patching.

~~~caspian
$myclass.delegations['@items'] = ['<+', 'shift']
$myclass.delegations['foo'] = %('core:array')
~~~

Hash keys preserve insertion order, so declaration-order semantics carry across DSL-defined and runtime-mutated entries. Mutations propagate to dispatch immediately (same live semantics as the class-ref check itself).

### Multiple `delegate` calls

`delegate` can appear multiple times, targeting different fields or methods:

~~~caspian
delegate :@items, %('core:array')          # array surface to @items
delegate :&metadata, ['name', 'tags']      # narrow set to metadata's return
~~~

Each stores its own entry in `.delegations`. Dispatch walks them in declaration order.

### Details still to pin

- **Same method name in multiple delegations.** If two `delegate` entries both match a given method — overlapping explicit lists, or class refs whose publications overlap — does the first-declared win at dispatch (declaration-order precedence), or does the framework raise at class-definition time?
- **Sigil convention on `.delegations` keys.** Miko's example shows `'@items'` (with `@`) for the field and `'foo'` (no `&`) for the method. Runtime hash keys strip the `&` from method targets while keeping `@` for fields; or preserves `&` for consistency with the DSL. TBD.
- **Public vs private methods on the class ref.** `.has_method?` on a class needs its own answer about how private methods surface. When called from delegation dispatch, private methods presumably shouldn't be delegable (they're not part of the class's public contract). Confirm and cross-link.
- **Explicit list + class ref in one call.** `delegate :@items, [%('core:array'), 'extra_method']` — allow the mixed form to combine a class-ref with additional specific methods? Or one form per call, and mix via two `delegate` lines?
- **`delegate` command scope.** Class-body DSL only for helpers, or general to any class body? General is more flexible; helper-scoped keeps the surface narrow. Since `.delegations` is on class objects generally, the DSL command probably should be general too.

## Isolation

The helper reaches its parent only through `@target`, and only via the parent's public method surface. The helper's own bucket (`@items`, `@base`, etc.) is its own; the parent's bucket stays private. Caspian's normal class-visibility rules enforce this; nothing helper-specific.

For the parallel variant that DOES have internal access to the parent, see [ideas/helpers/agents](agents).

## Open design points

- **`method unique()` sigil.** Miko's example writes `method unique()` without the `&` sigil, distinct from `method &init(@target)` and `method &append($x)`. Whether the sigil-less form has a specific meaning (property accessor? class-attribute-like?) or is informal shorthand — unresolved. Preserved verbatim above; may need clarification.
- **Standard helper root.** Every inline helper implicitly inherits a standard base (something like `caspian.uno/helper.casp`) that provides `@target` and any framework surface. The base's exact contents (constructor scaffolding, convention-method hooks, etc.) still to spec.
- **Class-level vs per-instance `@base`.** `@base = class ... end` at class-body scope reads like a bucket field assignment. Whether this is class-level (shared across all instances) or per-instance (new base class allocated per instance — expensive) is a Caspian semantics question. Class-level is the sensible read; syntax may need refinement to make that explicit.
- **Cross-source uniqueness.** The `unique()` method returning `true`/`false` per helper suggests the parent class walks its helpers and consults each one at composition time. Whether this integrates with any general cross-source-collision machinery (like the rule the request class has for `.headers` vs `.auth_headers`) is TBD.
- **Lazy vs eager instantiation.** Does `$instance.accept` create the helper on first read (lazy — matches the "untouched helper = no header" behavior we wanted for `.accept`), or at parent construction time (eager — helpers always exist)? Lazy is more likely useful.
(Delegation-specific TBDs are consolidated in the [Details still to pin](#details-still-to-pin) subsection of the Delegation section itself, since they cluster there.)
