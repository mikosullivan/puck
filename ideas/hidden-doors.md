~~~vibecode
{"doc": "idea",
	"role": "Reflective essay on a design-tendency question: Caspian has an unusual ratio of structural provisioning (dormant slots, reserved names, unused columns, empty return values that reserve a surface) to actually-runnable features. Is the codebase mostly hidden doors — affordances built for a future that may or may not arrive — or does it have real features hiding behind them? Written from a position of having watched (and helped build) many of those doors during the frame-0 / execution-scaffolding phase.",
	"status": "one-shot essay; not part of any settled spec"}
~~~

# Hidden doors

Does Caspian have features, or just a lot of hidden doors?

## The distinction

A **feature** is something a user can invoke today. `transpile(source)` produces CaspJ. `cvm.open()` returns a working handle. Trivet builds n-ary trees. These are features — code paths a user reaches through documented entry points and gets a defined outcome from.

A **hidden door** is a structural provision that no current code path opens. The `transpiler` slot on the engine, added last week, is a door: it exists, nothing reads it, reassigning it changes nothing. The reserved `misc` and `corporate` field names in CaspJ/CaspM: doors. The `frame_parent` column on `objects`: technically a door until sub-frames get pushed. `engine:run()` returning an empty Lua table: reserving a surface for keys that don't exist yet — a door with a doorframe.

Every hidden door is a bet that some future work will open it. Some bets are cheap and obviously correct. Some are speculative and may never pay out.

## What Caspian actually runs today

Concretely, right now — mid-integration on execution — the engine can:

- Boot up (`engine.new()`), wire host capabilities, open a CVM.
- Load source, transpile it, normalize it, stash CaspM.
- Call `run()`, push frame 0 (or find one via revival), fetch its `ast`, and reach the dispatch loop.
- Trip immediately on `unrecognized_row_head` because no row handlers exist yet.

That's it. Every actual Caspian program dies at the first statement. The runtime is a bootstrap that terminates at the point it would start doing anything.

What runs OUTSIDE the runtime: the transpiler and normalizer (tested against a large fixture corpus), the CVM data-access layer (add_bucket / add_scalar / add_frame / etc., tested), Trivet (its own suite). Genuine features, all of them — just not features of "Caspian the language you can write programs in."

## What's a hidden door

An incomplete tour of the visible ones:

- **Every `engine.<slot>` on the constructor.** `stdout`, `debugger`, `transpiler`, `process_pk`, `caspm` — some are wired, some are dormant, some are half-wired (populated but not read). Each slot is a door.
- **The `processes` table** and its plural-processes framing — supports coroutines, forks, shared-object-graph concurrency. Zero code exercises any of those.
- **The CVM schema.** Roles, listeners, refs, on_close/on_delete hooks, gc_errors, class-listeners, instance-listeners, marker tables, indexes for uspace... most of it is spec'd for features the runtime hasn't started. It's a schema for a language, executed against no programs.
- **Pause / resume via DB close** — thoroughly spec'd, no code.
- **Reserved passthrough field names** (`misc` / `corporate`) — reservation is real (documented in caspianj), no consumer.
- **Alternate transpilers** — the slot exists specifically so a Python-shaped Caspian could plug in someday. Nobody's writing one.
- **The `engine:run()` return table** — created, returned, never populated with a key.
- **Requirements trees for downloads, initial-state, controllers, http, exceptions, roles, protected, etc.** — each is a substantial spec, most have no runtime code behind them.

The ratio is stark: roughly one working feature per fifty hidden doors.

## The case for hidden doors

**Architectural coherence.** When the first user of `misc` shows up, they don't wait for a schema migration or an API version bump — the reservation was already in the spec. When the first alternate transpiler ships, the slot is already there. Doors built early are cheap; doors added late require careful migration.

**Design forcing function.** Building a hidden door surfaces the design question the door has to answer. "Is `process_pk` a slot or a parameter?" got resolved by adding the slot, not by writing implementation code that would have been thrown away when the shape changed. The door made the question concrete.

**Coherence of story.** A codebase full of consistent hidden doors demonstrates the designer has thought through more than what runs today. Someone reading the schema, or the engine class, or the CaspM spec can see the shape of the whole even though half the shape is unbuilt. That's a real form of communication.

**Cheap when the substrate is small.** Adding a column to a schema no one depends on is trivial. Adding a slot to an engine no host relies on is one line. Provisioning is easy when nothing has ossified. This is exactly the phase where hidden doors cost the least and buy the most.

## The case against

**YAGNI is a real principle.** Every hidden door is a prediction about future users. Some of those predictions will be wrong. `misc` and `corporate` may never be used the way the spec expects. The `transpiler` slot may never host an alternate. Effort spent designing those slots is effort not spent on features that WILL be used — and every dormant door has to survive refactors, style sweeps, doc audits, and the reader's cognitive tax.

**Design without implementation pressure often produces wrong shapes.** The `process_pk` slot design was chosen without ever having a user who needed revival. When a real revival use case shows up, the slot may turn out to be shaped wrong for it — and now we're stuck with the shape because it's spec'd. Real requirements come from real users.

**A door with no lock is a door.** Some hidden doors are legitimately extensibility points. Others are aesthetic choices dressed as extensibility. The reserved field-name pattern makes sense IF developers actually stash metadata there; if they don't, the reservation is just a promise nobody asked for.

**The maturity signal problem.** A repo whose surface looks feature-rich (many slots, extensive schema, cross-referenced specs) but doesn't run programs sends a mixed signal. An outsider deciding whether Caspian is "ready" may over-index on the surface and under-index on the run-tripping-on-first-statement reality.

## The honest middle

Not all hidden doors are equal. A useful taxonomy:

- **Load-bearing doors** — doors that a specific near-term feature will demonstrably open. The `caspm` slot is load-bearing: the sprint that just closed uses it. The `frame_parent` column is load-bearing: sub-frames will land soon and use it. These are cheap and correct.

- **Design-coherence doors** — doors whose value is making the story consistent, not enabling a specific feature. `misc`/`corporate` as a Puck-wide reservation fits here. Value is real but harder to point at.

- **Speculative doors** — doors betting on futures that may not arrive. Alternate transpilers. Some of the pause/resume machinery. Coroutines and fork-children in the processes-table framing. These carry the most YAGNI risk.

Caspian today has a lot of all three. The proportion isn't obviously wrong for a pre-V1 architecture-heavy phase — the whole POINT of that phase is provisioning. What matters is whether the ratio shifts as V1 approaches. A V1 that ships mostly load-bearing doors with a few speculative ones is healthy. A V1 that ships mostly speculative doors with a few features is what "just a lot of hidden doors" would look like.

## The skill

The design skill this requires isn't "avoid hidden doors" or "build lots of hidden doors." It's **knowing which door you're building.** Every door decision has an implicit question: is there a near-term feature that needs this? Is there a design-coherence value that justifies the maintenance cost? Or is this speculation dressed as forethought?

Answering that honestly, per door, is the discipline. Caspian's recent history has some good instincts on this — the `transpiler` slot was justified by test-fragility concerns, a concrete near-term value. Some less good — the `process-return` sprint was designed extensively and then deleted, leaving nothing behind but a slightly-changed `engine:run()` signature. That's a door being built and unbuilt in the same session.

## Answer

Both. Caspian has real features (the transpiler pipeline, the CVM data-access layer, bootstrap through frame-0 push). It has an unusually high ratio of hidden doors to features for its stage. The doors are mostly justified today because the substrate hasn't ossified — cheap to build now, expensive to add later.

The question that matters isn't "features or hidden doors" but "which of these doors will actually open." The honest answer today: too early to tell. Some obviously will (dispatch handlers land next; sub-frames chain via frame_parent soon; more of the CVM schema comes into use as classes and controllers land). Others may not (alternate transpilers, the full misc/corporate ecosystem, some of the pause/resume protocol).

The trap to avoid isn't building doors — it's building them faster than they open. If V1 ships with more dormant doors than active features, "features" was never the right frame for the answer to what Caspian is.
