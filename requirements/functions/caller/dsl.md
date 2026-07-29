# DSLs

<span class="tag">dsl</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_functions_caller_dsl",
	"role": "spec for how Caspian supports DSLs (domain-specific languages). The mechanism sits on caller objects (see tag:caller): a caller has a `.dsl` hash that maps bare-word-command names to receivers; those wirings are active for the duration of the `.call` that executes. `.dsl` has one behavior with two entry points — the method form `$c.dsl $recv, :a, :b, :c` bulk-writes, the subscript form `$c.dsl[:a] = $recv` accesses the underlying hash directly, and both share storage. Covers the four-tier token model (parser-baked structural, reserved invariants, DSL-overridable-with-default, pure DSL), how Caspian's own constructs (class body, instance body, loops) are DSL bodies, patterns for common DSL uses, the cheat clause, implementation plan, and open questions. This is the single home for the DSL spec.",
	"audience": "developers writing DSL-based library APIs, engine implementers building the DSL surface, language designers reading Caspian's own use of DSLs",
	"status": "spec — mechanism settled on caller objects; tier model settled; specific unusual-situation rules and sugar forms remain open"
}}
~~~

DSLs (domain-specific languages) are a **first-class developer feature** in Caspian. Any function that wants to run a passed block under a custom vocabulary builds a caller for that block, wires bare-word commands on `.dsl`, and invokes `.call`. Library authors use this to give their callers small focused vocabularies — a transaction's `commit` / `rollback`, a test runner's `pass` / `fail`, a builder's `step` / `cache`, a config block's `host` / `port` getter/setter pairs.

Caspian itself uses the same machinery for almost every construct that **looks** like syntax. Words like `field`, `inherits`, `return`, `break` are not parser keywords — they're bare-word commands resolved through a caller's DSL at runtime, exactly the same way a library author's DSL works. The parser only handles what genuinely requires structural parsing. That dogfooding is the proof the mechanism is good enough for any developer to reach for.

The caller-object surface itself — construction, param setting, `.call`, reuse semantics — is spec'd on [caller](tag:caller). This page owns everything DSL-specific.

## Why DSLs

- **Consistency.** Fewer special words. Everything you can do in a block is a method call on some receiver, even when it looks like a keyword.
- **Extensibility.** Library code introduces control-flow-shaped commands (transaction `commit`, test runner `pass`, builder `step`) without inventing new syntax. The caller's `.dsl` is the extension point.
- **Pedagogy.** "Bare words resolve through the active caller's DSL" is one rule; "here's a list of 40 keywords" is 40 rules.
- **Dogfooding.** Caspian's own class-definition syntax goes through the same DSL machinery user code uses. If the mechanism is good enough for the language to define itself, it's good enough for everyone.

## The mechanism

A function that wants to expose a DSL builds a caller for the block it's going to invoke, wires bare-word commands on the caller's `.dsl`, then calls it. Inside the running block, when a bare word is used, the engine looks it up in the caller's DSL hash; if found, the call dispatches to that receiver.

The minimal end-to-end shape:

~~~caspian
$logger = function()
	$log_handler = %('foo.bar/logger.casp').new()

	$caller = %call.blocks[0].caller.new
	$caller.dsl $log_handler, :info, :warn, :error
	return $caller.call
end

&logger do
	info 'starting up'
	warn 'queue is filling'
	error 'fatal'
end
~~~

`$caller.dsl $receiver, :name1, :name2, ...` wires the receiver as the routing target for each named bwc, in one call. Inside the running block, `info 'starting up'` dispatches to `$log_handler.info('starting up')`, `warn '...'` to `$log_handler.warn(...)`, and so on.

Three rules govern DSL behavior:

- The DSL is active for the lifetime of the `.call`. When the block returns, the DSL goes away.
- DSL entries take priority over scope variables. A DSL entry named `foo` shadows a scope variable also named `foo` for the block's duration.
- DSL bindings do not propagate. A function called from inside the running block runs with its own (empty or differently-configured) caller, or none at all. Nested DSL bodies stack rather than merge.

## `.dsl` has one behavior with two entry points

`.dsl` returns the underlying DSL hash. Called with args, it bulk-writes wirings on that hash. Called bare, it returns the hash for direct access. Both entry points share the same storage.

**Method form** — bulk-wire a receiver to N bwc names in one call:

~~~caspian
$caller.dsl $log_handler, :info, :warn, :error
~~~

Reads as "wire `$log_handler` to handle info, warn, error." Handles the common case (one receiver, several bwcs) cleanly. This is the emphasized form in docs and examples.

**Subscript form** — direct hash access. One bwc per assignment:

~~~caspian
$caller.dsl[:info]  = $log_handler
$caller.dsl[:warn]  = $log_handler
$caller.dsl[:error] = $log_handler
~~~

Reach for subscript when the method form doesn't fit:

- **Introspection.** `$caller.dsl[:info]` reads the current receiver wired for `info`.
- **Programmatic wiring.** Loop over a hash and assign each entry, or wire conditionally.
- **Removal.** Assign `null` to un-wire a name.
- **Fine-grained getter/setter control.** See [§ Virtual getters and setters](#virtual-getters-and-setters).

### Multi-receiver DSLs

Multiple `.dsl` calls on the same caller each add to the shared hash. Same-name entries overwrite:

~~~caspian
$caller.dsl $log_handler, :info, :warn, :error
$caller.dsl $timer, :start, :stop
~~~

The block running inside the `.call` sees `info` / `warn` / `error` routed to `$log_handler` and `start` / `stop` routed to `$timer`.

### Namespace separation from params

The caller's own subscript surface (`$caller[:name]`) is for **params** — the values passed to the target callable when `.call` fires. The caller's `.dsl` hash (`$caller.dsl[:name]`) is for **DSL entries** — the bwc wirings active inside the block.

Two different subscript targets on the same caller object. A param named `info` (`$caller[:info] = 'x'`) and a DSL entry for `info` (`$caller.dsl[:info] = $recv`) coexist without interaction.

## The four-tier token model

Every word that appears in Caspian source falls into one of four tiers. The tier determines whether the word is parser-baked, reserved, or DSL-resolvable.

### Tier 1 — Parser-built structural

Multi-token constructs that require structural parsing. Cannot be DSL.

- `if` / `elsif` / `elseif` / `else` / `end`
- `while` / `do` / `end`
- `class` / `instance` / `function` / `closure` / `end`

The parser needs these to build the AST. Programmer code cannot redefine them through any DSL.

### Tier 2 — Reserved invariants

Single tokens whose meaning is identity-critical and cannot be overridden by any DSL.

- `true`, `false`, `null`

Rebinding any of these would break engine assumptions about boolean and null semantics, so no DSL is allowed to.

### Tier 3 — DSL-overridable with engine defaults

Single tokens that **look** like keywords but are method calls dispatched through an ambient core DSL. Every scope inherits the defaults; specific scopes can override.

Canonical members:

| Bwc | Default binding |
|---|---|
| `return` | `%call.return` |
| `yield` | `%call.blocks[0].call` |
| `raise` | the raise primitive |
| `catch` / `heed` | the catch primitive |
| `break` | `$loop.break` (registered by the enclosing loop) |
| `next` / `continue` | `$loop.next` (registered by the enclosing loop) |

`break` and `next` are loop-scoped — each loop type registers them on its caller's DSL before invoking the body. Outside any loop they have no binding and raise.

Specific scopes can override. A test runner can rebind `return` to "add to test report"; a transaction block can rebind `raise` to "rollback and rethrow." The override applies only inside the directly running block.

### Tier 4 — Pure DSL

Words that only have meaning inside a specific scope, with no default binding outside it. The class body is the canonical example: `field`, `method`, `private`, `inherits`, `abstract` are bwcs the class-definer's DSL provides — and they mean nothing outside a class definition block.

## Caspian's own constructs as DSLs

The mechanism above isn't reserved for library authors — Caspian itself is built on it. The same "build a caller, wire DSL, call" shape that a developer would write for a custom DSL is what powers three of the most-touched constructs in the language.

### `class` is a DSL body

~~~caspian
class # person
	inherits 'foo.com/person'

	field :name, class: :string, required: true
	field :age,  class: :number, min: 0

	method &greet()
		return 'Hello, ' + @name
	end
end
~~~

Each of `inherits`, `field`, `method`, `private` is a bare-word command that the class-definer's DSL resolves. The class definer is a function that:

1. Builds a caller for the class-body block.
2. Wires `inherits`, `field`, `method`, `private`, `abstract`, etc. on the caller's DSL, each pointing at the class-builder object that accumulates state.
3. Invokes `.call`.
4. After the block returns, finalizes the accumulated class object and returns it.

`class` itself is a parser-baked tier-1 keyword (the parser needs to recognize the `class ... end` boundary), but everything **inside** the block flows through the same DSL machinery any user-written DSL would.

### `instance` is the same DSL body

`instance` builds a single ad-hoc object using the **same body shape** as `class`. The DSL inside the body is identical: `field`, `method`, `private`, `inherits`. The differences are the parser-baked outer wrapper (`instance ... end` vs `class ... end`), what happens after the block returns (`class` finalizes a class; `instance` finalizes a single object backed by a per-instance shadow class), and one instance-specific convention: a method literally named `autorun` runs after `init` and its return value replaces the constructed object.

~~~caspian
$config = instance
	field :host, class: 'string', default: 'localhost'
	field :port, class: 'integer', default: 8080

	method &dsn()
		return 'tcp://' + @host + ':' + @port
	end
end
~~~

The implication: there's one shared DSL implementation — the class-body DSL — and two parser-baked entry forms for it. Adding a future construct that wants the same body shape (a hypothetical `record`, say) is a tier-1 parser addition plus reuse of the same DSL receiver. No new DSL entries are needed.

### Loops are DSL bodies

`each`, `while`, the eventual `times`, `repeat`, and any user-defined iterator are functions that take a block and wire loop-control bwcs on the caller's DSL before invoking it:

| Bwc | Routes to |
|---|---|
| `break` | `$loop.break` |
| `next` / `continue` | `$loop.next` |
| `before` / `between` / `after` / `noloop` | `$loop` (structural lifecycle hooks) |

Custom loops add their own bwcs. A test runner registers `pass` / `fail` / `skip`; a transaction registers `commit` / `rollback`; a builder registers `step` / `cache`. The structural lifecycle hooks (`before` / `between` / `after`) are themselves bwcs the loop's DSL provides — not parser keywords.

## Patterns

### Virtual getters and setters

The DSL treats read and write dispatch as separate bwcs: `name` is one entry, `name=` is another. Wire both to the same receiver and the block reads and writes a value as if it were a local variable, with method calls happening underneath:

~~~caspian
$foo = function()
	$bear = some_object
	$caller = %call.blocks[0].caller.new
	$caller.dsl $bear, :height, 'height='
	return $caller.call
end

&foo do
	puts height       # calls $bear.height
	height = 400      # calls $bear.height=
end
~~~

Both names in one method call. The subscript form works too and lets a caller wire the getter and setter separately when only one direction is wanted:

~~~caspian
$caller.dsl[:height] = $bear     # getter only — block can read, not write
~~~

This unlocks configuration-style blocks, builder blocks, and any "the block's apparent locals are really methods on a backing object" pattern. The `name=` convention reuses the assignment-dispatch shape that property setters already use on regular objects.

### Targeting specific blocks

A caller is built for a specific callable — `%call.blocks[N].caller.new` targets block N. When a function accepts multiple blocks and wants DSLs on each, it builds one caller per block and configures each independently.

### Receiving fall-through

A receiver wired into the DSL exposes each wired name as a route to the matching method. When the block writes `foo`, the caller dispatches to `receiver.foo`; when it writes `bar`, the caller dispatches to `receiver.bar`. The method form makes this shape compact:

~~~caspian
$caller.dsl $configurer, :host, :port, :timeout, :retries
~~~

One line covers a small configuration surface. Useful for "the block is configuring this object" patterns where the configurer object has a small surface and every method is fair game.

## DSLs should be documented

Because DSL commands look like first-class keywords to the reader, every DSL should come with documentation describing what each bwc does, what its arguments are, and what scope it applies in. The exact mechanism (a `.doc` property on each receiver, a separate `.md` file per DSL, an introspection method that lists the caller's `(name, receiver, method)` triples, all of the above) is open — but the requirement that the documentation exists is firm.

## The cheat clause

Parser shortcuts are allowed when DSL would be impractical, costly, or premature. The default direction is toward DSLs, but pragmatism wins when there's a real reason.

Acceptable cheats:

- **Operator precedence.** Infix operators (`+`, `-`, `*`, `==`, `&&`) need precedence rules that the parser resolves. They can route through DSL-style methods at runtime, but their **dispatch order** is parser-resolved.
- **Logical word operators.** `and`, `or`, `not` have precedence and short-circuit semantics; parser-level for now, even if their underlying dispatch could be DSL-routable.
- **V0.01 walking-skeleton expedience.** The V0.01 parser may bake some class-body bwcs (`field`, `method`, etc.) into its keyword table to keep V0.01 small. The refactor to pure-DSL handling is a follow-up.

A cheat is OK when (a) the alternative isn't worth the engineering cost yet, (b) the surface behavior matches what the DSL form would produce, or (c) the construct genuinely can't be expressed as a DSL.

When we cheat, we say so. The construct's own doc names the cheat; this spec's open-questions section tracks the refactor debt.

## Implementation plan

Roughly the order this lands in the engine:

1. **Caller objects.** The base caller class carries `.call`, `.dsl`, and the param-subscript surface. Each callable's `.caller` accessor returns a specialized subclass. Spec'd on [caller](tag:caller).
2. **Resolution chain.** When a bare word is evaluated inside a block, the engine resolves it in order: reserved bwcs (tier 1, tier 2) → DSL entries from the currently active caller → scope variables. Get this right once; everything else rides on it.
3. **Tier 3 default bindings.** `return`, `yield`, `raise`, `catch` ship as default bindings in an ambient core DSL that every scope inherits.
4. **Loop-control wiring.** Each loop type (`each`, `while`, etc.) wires `break`, `next`, and any structural-hook bwcs on the caller for its body before invoking. The shared wiring helper is worth pulling out so loop authors don't write the same boilerplate.
5. **Class-body DSL.** The class definer wires `field`, `method`, `private`, `inherits`, `abstract` onto the class-builder receiver and invokes the body. `instance` reuses the same DSL — no additional bwcs; the `autorun` convention on `instance` is name-based (see [classes/instance § autorun](https://puck.uno/requirements/classes/instance#autorun)).
6. **Refactor any V0.01 cheats.** Class-body bwcs that were parser-baked move into the DSL receiver. The construct's surface behavior is unchanged; the implementation path is what shifts.

## Open questions

- **DSL documentation shape.** `.doc` property on each receiver? A separate `.md` file per DSL body? An introspection method that lists `(name, receiver, method)` triples on the caller? Pick a convention before user-written DSLs proliferate, so the documentation pattern is uniform across libraries.

- **Sugar for single-receiver DSLs.** The long-form ceremony is fine for the general case but verbose when the DSL just wires every entry to one receiver. A compact form for "DSL with N entries all pointing at receiver R" would clean up common cases. Concrete syntax TBD.

- **DSL-stacking with collisions.** When a loop body opens another loop, the inner loop's DSL entries shadow the outer's for any name collision. Documented; worth a worked example with intentional collision so the semantics are concrete.

- **Loop-helper extraction.** Loop authors currently re-wire `break` and `next` themselves. A shared helper (a `loop_control` class or free-standing helper function) so each loop type doesn't redo the same boilerplate would be ergonomically nice; needs design.

- **Parser-refactor schedule.** Which V0.01 parser shortcuts get refactored to pure-DSL handling, and when? Class-body bwcs are the prime candidate; the answer is V0.02 or later, but a target milestone helps.

- **Reflection.** Can code inside a running block introspect its own active DSL? List active entries? This would enable runtime tooling (debugger views, documentation extractors) but adds a surface to design.

- **Error messages on bwc resolution failure.** When a block uses a bwc that has no DSL binding and no scope variable, the engine raises. What does the error say? "Unknown bwc 'foo'"? "No DSL entry or variable named 'foo' in scope"? The diagnostic shape matters for debugging blocks that came from libraries.

## Testing

### Wiring surface

- **`.dsl` bare returns the DSL hash** — `$c.dsl` returns a hash object.
- **`.dsl` with args bulk-writes** — `$c.dsl $recv, :a, :b, :c` wires each name to `$recv` on the same hash.
- **Method form and subscript form share storage** — a wiring set via method form is readable via subscript, and vice versa.
- **Subscript read returns the wired receiver** — `$c.dsl[:info]` after a wire reads back the receiver.
- **Subscript null un-wires** — `$c.dsl[:info] = null` removes the entry.
- **Multiple `.dsl` calls accumulate** — later calls add to the same hash; same-name entries overwrite.
- **Virtual getter/setter split** — `$c.dsl $r, :name, 'name='` wires both; the block writing `name = 5` calls the setter.
- **Params namespace and DSL namespace are separate** — `$c[:info] = 'x'` and `$c.dsl[:info] = $recv` coexist without interaction.
- **Bulk wiring exposes each named method** — `$c.dsl $r, :a, :b, :c` routes each name to the corresponding method on `$r`.

### Dispatch semantics

- **DSL entry routes bare word to receiver** — `$c = %call.blocks[0].caller.new; $c.dsl[:info] = $recv; $c.call` with a block calling `info 'x'` dispatches to `$recv.info('x')`.
- **DSL entry with args** — `info 'a', 'b'` inside the running block calls the receiver with both args.
- **Undefined bare word falls through to scope variable** — a block naming `foo` with no DSL entry and a scope variable `$foo` reads `$foo`.
- **Undefined bare word with no scope variable raises** — a block naming `foo` with no DSL entry and no `$foo` raises.
- **DSL entry shadows scope variable** — when both exist, the DSL entry wins for the block's duration.
- **DSL entries don't propagate to nested calls** — a function called from inside the running block does not inherit the caller's DSL.
- **DSL active for the duration of `.call`** — the wirings apply while the target callable runs; after `.call` returns, they no longer apply.
- **Nested DSL stacking** — inner block's DSL entry shadows outer's for the same name, restored on return.
- **One caller per passed block** — a function can build one caller per block in `%call.blocks` and configure each independently.

### Tier interactions

- **`return` bwc default binding** — a block using `return X` (with no override) invokes `%call.return X`.
- **`yield` bwc default binding** — a block using `yield X` (with no override) invokes `%call.blocks[0].call X`.
- **`raise` bwc default binding** — a block using `raise X` triggers the raise primitive.
- **Tier 3 bwc override** — a caller setting `dsl[:return] = $recv` diverts `return` inside the block to `$recv.return`.
- **`break` outside any loop raises** — `break` in a block with no enclosing loop has no binding and errors.
- **`next` outside any loop raises** — same.
- **Loop wires `break` and `next` on its caller** — inside an `each ... end` block, `break` and `next` are bound.
- **Tier 2 rebind blocked** — attempting to set `dsl[:true] = $x` (or evaluating a block that would rebind `true`/`false`/`null`) raises.
- **Tier 1 rebind blocked** — attempting to route `if` or `class` through DSL raises.

### Caspian's own DSLs

- **Class body uses class-DSL** — `class ... field :name, class: :string ... end` resolves `field` as a bwc in the class-builder DSL.
- **`inherits` inside class body dispatches through DSL** — `inherits Person` calls the class-builder's `inherits` method.
- **`instance` body uses the same DSL as `class`** — the same bwcs (`field`, `method`, `inherits`, `private`) resolve identically inside `instance ... end`. The `autorun` behavior is name-based (a method literally named `autorun`), not a DSL command.
- **Loop `before` / `after` / `between` are bwcs** — inside a loop block, these names dispatch through the loop's DSL.
