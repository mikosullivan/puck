# DSLs

~~~json
{"vibecode": {
	"doc": "dsl",
	"role": "canonical doc on Caspian's DSL architecture — first-class commitment to using the language's own DSL machinery wherever practical",
	"key_concepts": ["four_tier_token_model", "dsl_on_dispatcher_per_yield",
		"virtual_getters_and_setters_via_name_and_name_equals_dispatch",
		"loop_dsl_with_control_and_structural_bwcs", "class_def_is_a_dsl",
		"cheat_clause_when_dsl_is_impractical"],
	"related": ["lucy.md § DSL Receivers", "index.md § Classes",
		"syntax/loops.md"]
}}
~~~

Caspian commits to using its own DSL machinery for as much of the language surface as is practical. Things that **look** like keywords — `accessor`, `field`, `return`, `break`, `before`, `after`, `pass`, `commit`, etc. — are mostly bare-word commands (bwcs) resolved through a DSL, not entries in the parser's keyword list. The parser handles only what genuinely requires structural parsing.

The mechanism that backs this is documented in [lucy.md § DSL Receivers](lucy/index.md#dsl-receivers). This file is about **how** we use it across the language.

## Philosophy

Use the DSL mechanism wherever practical. Parser shortcuts are allowed when they aren't — pragmatism beats purity — but the default direction is toward DSLs.

Why:

- **Consistency.** Fewer "magic words." Everything you can do is a method on something.
- **Extensibility.** Library code can introduce control-flow-shaped commands (transaction `commit`, test runner `pass`, builder `step`) without inventing new syntax.
- **Pedagogy.** "Everything is a method call on a receiver" is one rule; "here's a list of 40 keywords" is 40 rules.
- **Eating our own dog food.** The DSL machinery has to be good enough to power Caspian's own definition. That's the proving ground.

## The four-tier token model

Every word that shows up in Caspian source falls into one of four tiers. The tier determines whether the word is parser-baked, reserved, or DSL.

### Tier 1: Parser-built structural

Multi-token constructs that require structural parsing. Cannot be DSL.

- `if` / `elsif` / `elseif` / `else` / `end`
- `while` / `do` / `end`
- `class` / `end`
- `function` / `end`

These define block boundaries; the parser needs to know about them to build the AST.

### Tier 2: Reserved invariants

Single tokens whose meaning is identity-critical and cannot be overridden by any DSL.

- `true`, `false`, `null`

These are language-level constants. A DSL cannot rebind them because doing so would break every assumption the engine makes about boolean and null semantics.

(See [object.md § Identity Guarantees](built-in-classes/object.md#identity-guarantees) for the engine-enforced read-only character that backs this.)

### Tier 3: DSL-overridable with system defaults

Single tokens that **look** like keywords but are really named method calls. They have default bindings in an ambient core DSL every scope inherits; specific scopes can override them.

Canonical members:

- `return` → `%call.return`
- `yield` → `%call.yield`
- `break` → `%loop.break`
- `next` / `continue` → `%loop.next`
- `raise` → `%exception.raise`
- `catch` / `heed` → `%exception.catch`
- `exit` → `%process.exit`

Specific scopes can override. A Bryton test runner can rebind `return` to "add to test report"; a transaction block can rebind `raise` to "rollback and rethrow." The overrides apply only within the directly yielded block (per [lucy.md § DSL Receivers](lucy/index.md#dsl-receivers)).

### Tier 4: Pure DSL

Words that only have meaning inside a specific scope, with no default binding outside it. The classic example is the class body: `accessor` / `field` / `helper` / `inherits` / `join` / `abstract` mean something inside a class definition block and nothing outside it.

## How DSLs work

A DSL is configured per-yield on the function's dispatcher and travels with the dispatcher into the yielded block. It exists for the lifetime of the yield and goes away when the block returns. This matches the actual scope of a DSL binding — DSLs only apply when a function yields, so the dispatcher (which only exists during a yield) is their natural home.

Underlying machinery: [lucy.md § DSL Receivers](lucy/index.md#dsl-receivers).

### Basic shape

Inside the function, get the dispatcher, set entries on its DSL hash mapping bwc names to receivers, then yield:

```caspian
$myfunc = function()
    $dispatcher = %call.dispatcher
    $dispatcher.dsl['foo'] = $bar
    $dispatcher.dsl['gup'] = $baz
    $dispatcher.yield
end
```

When the block runs, bare-word `foo` resolves to `$bar.foo`; `gup` resolves to `$baz.gup`. The resolution order (reserved bwcs → DSL entries → scope variables) is documented in lucy.md.

### Virtual getters and setters

The dispatcher treats read and write dispatch as separate keys: `name` is one entry, `name=` is another. Wire both to the same receiver and the block reads and writes a value as if it were a local variable, with method calls happening underneath.

```caspian
$foo = function()
    $dispatcher = %call.dispatcher

    $bear = some_object
    $bear.height = 300

    $dispatcher.dsl['height']  = $bear
    $dispatcher.dsl['height='] = $bear

    $dispatcher.yield
end

&foo do
    puts height       # calls $bear.height under the hood
    height = 400      # calls $bear.height=
end
```

This unlocks configuration-style blocks, builder blocks, and scope-like blocks where the block's apparent "local variables" are actually method calls on a backing object. The `name=` convention is the natural assignment-dispatch pattern — it's already how property setters work on regular objects, so the dispatcher just reuses the same name-to-receiver mechanism for the bwc layer.

### Sugar to come later

Long-form dispatcher setup is fine for the general case, but for common patterns (basic block yield with no special DSL, a single-receiver DSL, etc.) a more compact form is worth designing. TBD; not blocking.

## Loop DSLs

A loop is fundamentally a function that takes a block. Before yielding, it configures its dispatcher's DSL to expose:

1. **Loop-control bwcs** — `break`, `next` (overridable per loop type but with sensible defaults).
2. **Structural bwcs** — `before`, `between`, `after`, `noloop` — block-accepting commands that attach lifecycle hooks to the loop.
3. **Domain-specific bwcs** — whatever the loop's purpose calls for (`pass`/`fail`/`skip` for a test runner, `commit`/`rollback` for a transaction, `step`/`cache` for a builder).

### Standard loop example

```caspian
$items.each do($item)
    if $item.empty?
        next            # bwc → %loop.next
    end
    if found($item)
        break           # bwc → %loop.break
    end
    puts $item.name
end
```

### Custom loop: test runner

```caspian
$tests.run do($test)
    if $test.passed?
        pass            # bwc → %test.pass($test)
    elseif $test.error?
        fail $test.error_message
    else
        skip
    end
end
```

### Custom loop: transaction

```caspian
$db.transaction do
    if $balance < $amount
        rollback        # bwc → %tx.rollback
    end
    debit $account, $amount
    credit $other, $amount
    commit              # bwc → %tx.commit
end
```

### Custom loop: build pipeline

```caspian
$builder.pipeline do
    step :compile
    step :test, parallel: true
    cache :artifacts
end
```

### Structural blocks as bwcs

The structural blocks `before` / `between` / `after` / `noloop` (described in [loops.md](syntax/loops.md)) are themselves bwcs the loop's DSL provides — not parser keywords. Each takes a block:

```caspian
$items.each do($item) as $loop
    before do
        $loop.summary = ''
    end

    $loop.summary += $item.name

    between do
        $loop.summary += ', '
    end

    after do
        puts $loop.summary
    end
end
```

## Class definition is a DSL

The class definition block is the canonical tier-4 DSL. Words like `accessor`, `field`, `helper`, `inherits`, `join`, `abstract` are bwcs the class-definer's DSL provides — not parser keywords.

```
class 'foo.com/character'
    inherits 'foo.com/person'

    field :name, class: :string, required: true
    field :age,  class: :number, min: 0

    accessor :nickname

    function &greet(name:)
        'Hello, ' + name
    end
end
```

Each of `inherits`, `field`, `accessor` is a bwc resolved through the class-definer's DSL. See [caspian.md § Classes](index.md#classes) for the class-DSL command set in detail.

## DSLs should be documented

Because DSL commands look like first-class keywords to the reader, the receivers wired into a dispatcher's DSL should come with documentation describing what each method does, what its arguments are, and what scope it applies in. The exact form (a `.doc` property on each receiver, a separate `.md` file, an introspection method that lists the dispatcher's `(name, receiver, method)` triples, all of the above) is TBD; the requirement that it exists is not.

## The cheat clause

Parser shortcuts are allowed when DSL would be impractical, costly, or premature. Cheating is expected for:

- **Operator precedence.** Infix operators like `+`, `-`, `*`, `==`, `&&` need precedence rules in the parser; the parser resolves them, even if the underlying operation routes through DSL-style methods at runtime.
- **Logical word operators.** `and`, `or`, `not` have precedence and short-circuit semantics; parser-level for now, even if their dispatch could be DSL-resolvable underneath.
- **V0.01 walking-skeleton expedience.** The V0.01 parser bakes class-body keywords (`accessor`, `field`, `helper`, `inherits`, `join`) into its keyword table rather than going through a DSL receiver. This is a deliberate shortcut to keep V0.01 small; the refactor to pure-DSL handling is tracked separately.

A cheat is OK if (a) the alternative isn't worth the engineering cost yet, (b) the surface behavior is identical to what the DSL form would produce, or (c) the construct genuinely can't be expressed as a DSL (operator precedence is the strongest example).

When we cheat, we say so — in the doc for the construct and in this file's open questions if a refactor is owed.

## Open questions

- **Loop-control scope.** Should `break` / `next` be part of the **loop's** DSL (loop-local, registered by each loop type) or part of the **ambient scope's** DSL inherited by anything that runs in a loop context (loop-aware via `%loop`)? The first is more consistent with the per-loop model; the second avoids each loop having to redeclare the obvious controls.
- **`self`.** Identity-critical (tier 2, reserved) or DSL-overridable (tier 3)? Probably reserved given its role in method dispatch, but worth being explicit.
- **DSL documentation shape.** `.doc` property, separate `.md` file, introspection method, all of the above? Pick a convention so DSLs are uniformly discoverable.
- **DSL-stacking semantics.** When a loop body opens another loop, the inner loop's DSL takes priority over the outer's for name collisions. Per [lucy.md § DSL Receivers](lucy/index.md#dsl-receivers), DSL settings don't propagate down the call stack; the dispatch chain at any point is "innermost DSL → ... → ambient core DSL → scope variables." Worth a worked example with intentional collision.
- **Parser-refactor schedule for V0.01 cheats.** The class-body keyword shortcut in `parser.lua` needs a refactor pass; when does that land — V0.02, V0.1, or later?
