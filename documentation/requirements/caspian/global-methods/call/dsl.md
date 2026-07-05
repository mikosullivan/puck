# DSLs

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_call_dsl",
	"role": "plan for how Caspian supports DSLs (domain-specific languages) — the dispatcher mechanism on %call, the four-tier model of where bare-word commands come from, how Caspian's own constructs (class, instance, loops) are built as DSLs, and the open questions that need answers before this lands.",
	"audience": "engine implementers building the dispatcher, language designers reading Caspian's own use of DSLs, programmers writing custom DSLs in their own code",
	"status": "plan — the core mechanism (`%call.dispatcher.new`, dsl hash, yield) is settled; tier model is settled; specific unusual-situation rules and sugar forms are open"
}}
~~~

DSLs (domain-specific languages) are a **first-class developer feature** in Caspian. Any function can configure a dispatcher with custom bare-word commands and accept a block that uses them. Library authors use this to give their callers small focused vocabularies — a transaction's `commit` / `rollback`, a test runner's `pass` / `fail`, a builder's `step` / `cache`, a config block's `host` / `port` getter-setter pairs.

Caspian itself uses the same machinery for almost every construct that **looks** like syntax. Words like `field`, `inherits`, `return`, `break` are not parser keywords — they're bare-word commands resolved through a dispatcher's DSL hash at runtime, exactly the same way a library author's DSL works. The parser only handles what genuinely requires structural parsing. That dogfooding is the proof the mechanism is good enough for any developer to reach for.

This page describes how DSLs work, the patterns library authors use, how Caspian uses the same mechanism internally (class definitions and `instance` bodies are both DSL bodies), and what remains open.

## Why DSLs

- **Consistency.** Fewer special words. Everything you can do in a block is a method call on some receiver, even when it looks like a keyword.
- **Extensibility.** Library code introduces control-flow-shaped commands (transaction `commit`, test runner `pass`, builder `step`) without inventing new syntax. The DSL hash is the extension point.
- **Pedagogy.** "Bare words resolve through the dispatcher's DSL hash" is one rule; "here's a list of 40 keywords" is 40 rules.
- **Dogfooding.** Caspian's own class-definition syntax goes through the same DSL machinery user code uses. If the mechanism is good enough for the language to define itself, it's good enough for everyone.

## The mechanism

A function that wants to expose a DSL constructs a dispatcher explicitly with [`%call.dispatcher.new`](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-dispatcher-new), configures its `dsl` hash with bare-word-name to receiver mappings, then yields. When the block uses a bare word, the engine looks it up in the dispatcher's DSL hash; if found, the call dispatches to that receiver.

Dispatchers are not implicit. A function that just calls bare `yield` (the tier-3 bwc for `%call.yield`) hands control to the passed block without involving any dispatcher object. The dispatcher exists only when DSL setup is needed.

The minimal end-to-end shape:

~~~caspian
$logger = function()
	$dispatcher = %call.dispatcher.new
	$dispatcher.dsl['info']  = $log_handler   # bwc 'info'  → $log_handler.info(...)
	$dispatcher.dsl['warn']  = $log_handler
	$dispatcher.dsl['error'] = $log_handler
	return $dispatcher.yield
end

&logger do
	info 'starting up'
	warn 'queue is filling'
	error 'fatal'
end
~~~

Three rules govern dispatcher behavior:

- The DSL exists for the lifetime of the yielded block. When the block returns, the dispatcher (and its DSL hash) goes away.
- DSL entries take priority over scope variables. A DSL entry named `foo` shadows a scope variable also named `foo` for the block's duration.
- DSL bindings do not propagate. A function called from inside the yielded block runs with its own (empty or differently-configured) dispatcher, or none at all. Nested DSL bodies stack rather than merge.

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
| `yield` | `%call.yield` |
| `raise` | the raise primitive |
| `catch` / `heed` | the catch primitive |
| `break` | `$loop.break` (registered by the enclosing loop) |
| `next` / `continue` | `$loop.next` (registered by the enclosing loop) |

`break` and `next` are loop-scoped — each loop type registers them on its dispatcher before yielding. Outside any loop they have no binding and raise.

Specific scopes can override. A test runner can rebind `return` to "add to test report"; a transaction block can rebind `raise` to "rollback and rethrow." The override applies only inside the directly yielded block.

### Tier 4 — Pure DSL

Words that only have meaning inside a specific scope, with no default binding outside it. The class body is the canonical example: `field`, `helper`, `inherits`, `join`, `abstract` are bwcs the class-definer's DSL provides — and they mean nothing outside a class definition block.

## Caspian's own constructs as DSLs

The mechanism above isn't reserved for library authors — Caspian itself is built on it. The same `%call.dispatcher.new`-and-yield shape that a developer would write for a custom DSL is what powers three of the most-touched constructs in the language.

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

Each of `inherits`, `field`, `method` is a bare-word command that the class-definer's dispatcher resolves through its DSL. The class definer is a function that:

1. Constructs a dispatcher via `%call.dispatcher.new`.
2. Registers `inherits`, `field`, `method`, `helper`, `join`, `abstract`, etc. on the DSL hash, each pointing at the class-builder object that accumulates state.
3. Yields to the block.
4. After the block returns, finalizes the accumulated class object and returns it.

`class` itself is a parser-baked tier-1 keyword (the parser needs to recognize the `class ... end` boundary), but everything **inside** the block flows through the same DSL machinery any user-written DSL would.

### `instance` is the same DSL body

`instance` builds a single ad-hoc object using the **same body shape** as `class`. The DSL inside the body is identical: `field`, `method`, `inherits`, `helper`, etc. The only difference is the parser-baked outer wrapper (`instance ... end` vs `class ... end`) and what happens after the block returns — `class` finalizes a class; `instance` finalizes a single object backed by a per-instance shadow class.

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

`each`, `while`, the eventual `times`, `repeat`, and any user-defined iterator are functions that take a block and register loop-control bwcs on the dispatcher before yielding:

| Bwc | Routes to |
|---|---|
| `break` | `$loop.break` |
| `next` / `continue` | `$loop.next` |
| `before` / `between` / `after` / `noloop` | `$loop` (structural lifecycle hooks) |

Custom loops add their own bwcs. A test runner registers `pass` / `fail` / `skip`; a transaction registers `commit` / `rollback`; a builder registers `step` / `cache`. The structural lifecycle hooks (`before` / `between` / `after`) are themselves bwcs the loop's DSL provides — not parser keywords.

## Patterns

### Virtual getters and setters

The dispatcher treats read and write dispatch as separate keys: `name` is one entry, `name=` is another. Wire both to the same receiver and the block reads and writes a value as if it were a local variable, with method calls happening underneath:

~~~caspian
$foo = function()
	$dispatcher = %call.dispatcher.new

	$bear = some_object
	$dispatcher.dsl['height']  = $bear   # virtual getter
	$dispatcher.dsl['height='] = $bear   # virtual setter

	return $dispatcher.yield
end

&foo do
	puts height       # calls $bear.height
	height = 400      # calls $bear.height=
end
~~~

This unlocks configuration-style blocks, builder blocks, and any "the block's apparent locals are really methods on a backing object" pattern. The `name=` convention reuses the assignment-dispatch shape that property setters already use on regular objects.

### Targeting specific blocks

`%call.dispatcher.new(n)` constructs a dispatcher targeting the nth passed block (default 0). When a function accepts multiple blocks and wants DSLs on each, it calls `.new` once per block and configures each independently.

### Receiving fall-through

A receiver wired into the DSL hash exposes its full method surface. When the block writes `foo`, the dispatcher calls `receiver.foo`; when it writes `bar`, the dispatcher calls `receiver.bar`. Both route to the same object. Configuring one DSL entry effectively makes every method on that object reachable as a bwc — useful for "the block is configuring this object" patterns where the configurer object has a small surface and every method is fair game.

## DSLs should be documented

Because DSL commands look like first-class keywords to the reader, every dispatcher's DSL hash should come with documentation describing what each method does, what its arguments are, and what scope it applies in. The exact mechanism (a `.doc` property on each receiver, a separate `.md` file per DSL, an introspection method that lists the dispatcher's `(name, receiver, method)` triples, all of the above) is open — but the requirement that the documentation exists is firm.

## The cheat clause

Parser shortcuts are allowed when DSL would be impractical, costly, or premature. The default direction is toward DSLs, but pragmatism wins when there's a real reason.

Acceptable cheats:

- **Operator precedence.** Infix operators (`+`, `-`, `*`, `==`, `&&`) need precedence rules that the parser resolves. They can route through DSL-style methods at runtime, but their **dispatch order** is parser-resolved.
- **Logical word operators.** `and`, `or`, `not` have precedence and short-circuit semantics; parser-level for now, even if their underlying dispatch could be DSL-routable.
- **V0.01 walking-skeleton expedience.** The V0.01 parser may bake some class-body bwcs (`field`, `helper`, etc.) into its keyword table to keep V0.01 small. The refactor to pure-DSL handling is a follow-up.

A cheat is OK when (a) the alternative isn't worth the engineering cost yet, (b) the surface behavior matches what the DSL form would produce, or (c) the construct genuinely can't be expressed as a DSL.

When we cheat, we say so. The construct's own doc names the cheat; this spec's open-questions section tracks the refactor debt.

## Implementation plan

Roughly the order this lands in the engine:

1. **Dispatcher constructor on `%call`.** Already settled at the spec level (see [`%call.dispatcher.new`](https://puck.uno/documentation/requirements/caspian/global-methods/call/#call-dispatcher-new)). The engine implements the `%call.dispatcher` class with a `.new(n)` constructor that returns a fresh dispatcher targeting passed block `n`, plus the `dsl` hash and `yield` method on each instance.

2. **Resolution chain.** When a bare word is evaluated inside a block, the engine resolves it in order: reserved bwcs (tier 1, tier 2) → DSL entries from the innermost active dispatcher → scope variables. Get this right once; everything else rides on it.

3. **Tier 3 default bindings.** `return`, `yield`, `raise`, `catch` ship as default bindings in an ambient core DSL that every scope inherits.

4. **Loop-control wiring.** Each loop type (`each`, `while`, etc.) registers `break`, `next`, and any structural-hook bwcs on its dispatcher before yielding. The shared registration helper is worth pulling out so loop authors don't write the same boilerplate.

5. **Class-body DSL.** The class definer wires `field`, `method`, `inherits`, `helper`, `join`, `abstract` onto the class-builder receiver and yields. `instance` reuses the same DSL.

6. **Refactor any V0.01 cheats.** Class-body bwcs that were parser-baked move into the DSL receiver. The construct's surface behavior is unchanged; the implementation path is what shifts.

## Open questions

- **`self` rebinding.** Tier 2 (reserved) or tier 3 (overridable)? Likely tier 2 given its load-bearing role in method dispatch, but the question deserves an explicit answer rather than implicit treatment.

- **DSL documentation shape.** `.doc` property on each receiver? A separate `.md` file per DSL body? An introspection method that lists `(name, receiver, method)` triples on the dispatcher? Pick a convention before user-written DSLs proliferate, so the documentation pattern is uniform across libraries.

- **Sugar for single-receiver DSLs.** The long-form ceremony is fine for the general case but verbose when the DSL just wires every entry to one receiver. A compact form for "DSL with N entries all pointing at receiver R" would clean up common cases. Concrete syntax TBD.

- **DSL-stacking with collisions.** When a loop body opens another loop, the inner loop's DSL entries shadow the outer's for any name collision. Documented; worth a worked example with intentional collision so the semantics are concrete.

- **Loop-helper extraction.** Loop authors currently re-register `break` and `next` themselves. A shared helper (a `loop_control` class or free-standing helper function) so each loop type doesn't redo the same boilerplate would be ergonomically nice; needs design.

- **Parser-refactor schedule.** Which V0.01 parser shortcuts get refactored to pure-DSL handling, and when? Class-body bwcs are the prime candidate; the answer is V0.02 or later, but a target milestone helps.

- **Reflection.** Can code inside a yielded block introspect its own dispatcher? List active DSL entries? This would enable runtime tooling (debugger views, documentation extractors) but adds a surface to design.

- **Error messages on bwc resolution failure.** When a block uses a bwc that has no DSL binding and no scope variable, the engine raises. What does the error say? "Unknown bwc 'foo'"? "No DSL entry or variable named 'foo' in scope"? The diagnostic shape matters for debugging blocks that came from libraries.
