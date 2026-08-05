# Nested DSLs

~~~vibecode
{"vibecode": {
	"doc": "ideas_nested_dsls",
	"role": "design for how Caspian organizes bare-word commands. Two-tier model: primitives (parser-baked structural + value literals + control flow) and DSL (bare word commands that map to objects and their methods). DSLs are per-method-invocation, pushed onto a chain of hashes when a caller's .call fires and popped when it returns. Reads walk the chain end-to-start; nested method invocations get push-shadow semantics. Wiring is `$caller.dsl $receiver, :name1, :name2`. A push-time audit catches primitive collisions and missing methods on receivers; all conflicts in one wiring are reported in a single raise. Same mechanism serves engine internals (class body, loops) and developer DSLs.",
	"status": "designed 2026-08-05 with Miko — two-tier model, DSL-chain-with-push-shadow, push-time audit, report-all-conflicts settled; not yet in requirements, not yet built"
}}
~~~

Two tiers for every bare-word command Caspian recognizes:

- **Primitives.** Reserved names Caspian handles specially. Some are pure parser-baked structural — they never reach BWC dispatch because the parser consumes them (`elsif`, `else`, `end`). Others might be handled by the parser AND registered in the DSL chain so the audit can catch conflicts (`if`, `unless`). Others might have real DSL-side dispatch (`return` could point at `%call.return`). What unifies them is that no user DSL can override any of them. Starting sample: `return`, `raise`, `catch`, `yield`, `break`, `next`, `true`, `false`, `null`, `if`, `unless`. More added as needed.
- **DSL.** Bare word commands that resolve to methods on objects at runtime. Everything not-a-primitive.

## The DSL chain

The active DSL is an array of hashes. Each hash maps `bwc_name -> receiver`. When a bare word fires, the engine walks the array end-to-start; the first hit returns the receiver, and the engine calls `receiver.<name>(args)`.

### The primitives layer

The first frame in the array is always the **primitives layer**. Created at engine startup, never popped, never overwritten. It carries an entry for every primitive name (starting from the sample above and growing as needed).

Registration is not implementation. The primitives layer's job is to say "this name is taken" — it doesn't have to hold real dispatch code for every entry. A primitive like `if` is handled structurally by the parser; its entry in the primitives layer exists only so the push-time audit can reject any DSL that tries to wire `:if`. Other primitives might have real dispatch (`return` could point at `%call.return` and route through the DSL walk); the layer accommodates both cases.

Two things fall out of naming the layer:

- **Error clarity.** The audit's "primitive collision" message names the primitives layer specifically ("cannot bind primitive `if` — reserved in the primitives layer"), not a generic "outer frame."
- **Immutability by design.** Push and pop operate only on frames above the primitives layer. Nothing can accidentally tear it down.

### Per-invocation frames

Above the primitives layer, DSL frames are per-method-invocation. When a caller's `.call` fires, the caller's wired DSL hash pushes onto the array. When the call returns, the hash pops. Nothing else touches the array — no file-level DSLs, no scope-block DSLs, no ambient "for this AST subtree" DSLs.

## Wiring

A caller wires its DSL through the method form or the subscript form. Both share storage on the caller's own hash:

~~~caspian
$caller.dsl $log_handler, :info, :warn, :error
$caller.dsl[:info] = $log_handler
~~~

The method form is the common case — one receiver mapped to multiple bwc names in one call. Reads left-to-right as "wire this receiver to handle these bwcs."

Method dispatch: when `info 'starting up'` fires inside the running block, the engine walks the DSL chain, finds `$log_handler` under `:info`, and calls `$log_handler.info('starting up')`. The bwc name IS the method name.

## Nesting

A block-passing method that invokes another block-passing method gets stacked DSLs during the inner invocation. Push-shadow: the inner DSL's entries take precedence for the duration of the inner call.

~~~caspian
$foo.bar do
	gup

	zap do
		something
	end
end
~~~

Walk-through:

- `$foo.bar do ... end` invokes `$foo.bar`, which wires `gup` and `zap` on its DSL and calls the block. The DSL pushes onto the chain.
- Inside the outer block, `gup` and `zap` resolve through the current innermost DSL (`$foo.bar`'s).
- `zap` receives its own block. Its implementation wires `something` on ITS DSL and calls that inner block. The inner DSL pushes.
- Inside the inner block, `something` resolves through the innermost DSL (`zap`'s). `gup` and `zap` remain reachable — the walk falls through to the outer DSL.
- When the inner block returns, the inner DSL pops. `something` becomes unreachable.
- When the outer block returns, the outer DSL pops. `gup` and `zap` become unreachable.

Nested class definitions, nested loops, and nested developer DSLs all work the same way. A nested loop pushes its own DSL with its own `break` / `next` receivers; the innermost loop's `break` wins during its body.

## Rules

### Primitives are inviolable

A DSL cannot wire a bwc name that matches a primitive. The primitives layer registers every reserved name at engine startup, and the push-time audit walks the chain — an incoming wire that collides with any name in the primitives layer raises with a message naming the specific primitive.

### A caller can't wire the same name twice

Within a single caller's DSL hash, each name maps to exactly one receiver. `$caller.dsl $recv, :info, :info` raises at wire time. `$caller.dsl $r1, :info` followed by `$caller.dsl $r2, :info` on the same caller also raises.

### Push-shadow across nested invocations is allowed

An inner method's DSL wiring a name that's already defined by an outer method's DSL is fine. The inner binding wins for the duration of the inner call; the outer's original binding returns when the inner call ends.

This is what makes nested loops work (each loop has its own `break`), what lets nested class definitions coexist (each class body has its own `method`), and what enables the general nested-DSL example above.

## Push-time audit

At the earliest point at which the full picture is available — when a DSL is about to be pushed onto the chain — the engine audits the incoming hash for conflicts. The audit runs BEFORE the push, so a caught conflict never leaves the chain in a broken state.

**The audit walks the entire chain, not just the incoming layer.** For each name in the incoming hash, the audit scans every frame already on the chain looking for redundancy. This is deliberate belts-and-suspenders: if the audit were restricted to any subset of the chain (only the primitives layer, only the top frame, only the incoming hash itself), a future addition of another reserved layer or another kind of chain-wide check would silently miss its scope. Walking the whole chain is the safe default.

What the walk finds and what it does about it:

- **Primitive collision.** A name that appears in the primitives layer → raise. Message names the specific primitive.
- **Missing method on receiver.** A wired entry names a method the receiver doesn't have → raise. Catches typos at push time rather than at first dispatch. This check doesn't depend on the walk, but it runs at the same audit pass.
- **Same-DSL duplicate.** The caller wired the same name twice within its own hash → raise. Primarily caught at wire time; defensive re-check at push.
- **Cross-invocation shadow** (a name that appears in another DSL layer above the primitives layer) → NOT raised. This is push-shadow, the intended nesting behavior. The walk still visits those frames, but the finding is informational only — nested loops each defining `break` and nested class definitions each defining `method` are exactly this case.

### Report all conflicts in one raise

The audit collects every conflict it finds and raises one error listing all of them. Not one raise per conflict; no fix-one-find-another cycles. Matches the general "report all errors at once" preference — same rule the transpiler uses for parse errors, the class definer uses for definition-time issues, and every other batch-detectable check applies.

Example error text for a caller trying to wire multiple bad entries:

```
DSL wiring failed:
  cannot bind primitive 'if' — primitives are immutable
  cannot bind primitive 'while' — primitives are immutable
  wired :info but receiver of class Foo has no method 'info'
  wired :warn but receiver of class Foo has no method 'warn'
```

Same principle applies to wire-time duplicate detection — `$c.dsl $recv, :info, :warn, :info, :error, :info` reports both duplicate occurrences of `:info` in one raise, not one at a time.

## One mechanism, engine and developer

Caspian's own constructs use the same DSL machinery a developer would use for their own DSL. There is no separate engine-side dispatch path.

- **`class` body.** The class-definer function wires `field`, `method`, `private`, `inherits`, etc. on its caller's DSL, calls the body, and finalizes the resulting class object when the body returns.
- **`instance` body.** Same DSL as `class` — same bwcs, same receiver shape. The parser-baked outer wrapper (`instance ... end` vs `class ... end`) is what differs; the DSL is shared.
- **Loops.** `each`, `while`, `until`, `.times`, `.upto`, `.downto` each wire loop-control bwcs (`break`, `next`, structural hooks) on their DSL and call the block.
- **Developer DSLs.** A transaction library wires `commit` / `rollback` on its caller's DSL. A test runner wires `pass` / `fail`. A builder wires `step` / `cache`. Same shape as everything the engine does internally.

The ergonomic payoff: adding a construct-scoped bwc is a one-line hash write. Pick or build a receiver, add a method with the bwc's name to it, wire it into the appropriate caller's DSL. No engine dispatcher code to touch — the general DSL walk handles it.

## Example: class

The class body is the canonical case of an internal DSL. `method` and `private` here are bwcs the class-DSL provides.

~~~caspian
class do

	method &foo
		return 'foo'
	end

	private method &bar
		return 'bar'
	end

end
~~~

`method &foo ... end` creates and returns a method object. `private method &bar ... end` composes: the inner `method &bar ... end` creates a method object, then `private` (a bwc the class-DSL wires) receives that object and marks it as private on the class. Both `method` and `private` come from the same class-DSL — they're wired onto its receiver at push time.

Outside `class`, both `method` and `private` are unbound; using them raises.

## Open questions

Work on the engine's DSL implementation waits until these are resolved.

### Loop controllers, `break`, and `next` — deferred entirely

The routing question for `break` and `next` turned out to be trickier than the design conversation had accounted for. Miko's call on 2026-08-05: defer the whole loop-controller concept until the DSL / bwc-routing decisions stabilize. See [loops § Deliberately out of scope](https://www.puck.uno/requirements/syntax/loops#deliberately-out-of-scope) for what's on hold — `break`, `next`, `break N`, `as $loop`, all `$loop.X` methods (state readers and control methods), and named-loop targeting all go together. They WILL land once the routing shape is clear.

Design work on this doc doesn't include an implementation path for these until the deferral is lifted.

### Where the push-time audit runs vs the wire-time audit

The audit is described as running at push time (the earliest point at which the incoming hash and the active chain are both visible), with wire-time as the primary line for duplicate detection within a single caller. Which specific checks run at which point — and whether push time re-runs them defensively — hasn't been pinned down.

### The DSL chain's exact API surface

The doc says the DSL chain is a purpose-built array-with-rules. Push and pop are described; walk-on-read is described. What's not spelled out: whether there's a way to introspect the chain from Caspian code (list active DSLs, list the current innermost binding for a name), how a receiver un-wires itself if it needs to, and the exact error-object shape the audit raises with.
