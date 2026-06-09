# Caspian V1 plan

~~~vibecode
{"vibecode": {
	"doc": "caspian_v1_plan",
	"role": "V1 plan for the Caspian engine: slice progression, Caspian-specific cross-cutting principles, scope, dependencies. Sits under the umbrella Puck-wide V1 plan at v1.md.",
	"status": "active",
	"current_slice": "Corin",
	"feature_lock": "soft",
	"source_of_truth": "vibecode_blocks"
}}
~~~

This is the V1 plan for the **Caspian engine** specifically — one
strand of [Puck's V1](../index.md). It defines the slice-by-slice build
that takes Caspian from "no code" through "hello-world from source"
through "stdout, hashes, JSON, CLI, cache, Bryton" — i.e., the engine
that V1 ships with.

Per-slice detail lives in the sibling per-slice files in this
directory, each named after its codename.

---

<a id="slice-progression"></a>
## Slice progression

Slices are ordered alphabetically by codename; that's the development
sequence. Nothing ships until V1.0 — these are development checkpoints.

| Codename | Delivers | Page |
|---|---|---|
| **Ashley** | inventory of existing code as the baseline (no new code) | [ashley.md](ashley.md) |
| **Aslan** | hello-world | [aslan.md](aslan.md) |
| **Bree** | hello-world from Caspian source | [bree.md](bree.md) |
| **Corin** | stdout | [corin.md](corin.md) |
| **Digory** | hashes | [digory.md](digory.md) |
| **Edmund** | JSON serialization | [edmund.md](edmund.md) |
| **Frank** | `caspian` command-line launcher | [frank.md](frank.md) |
| **Gabbo** | on-disk `caspj/` cache | [gabbo.md](gabbo.md) |
| **Glenstorm** | Bryton | [glenstorm.md](glenstorm.md) |

Each per-slice page is self-contained: goal, definition of done, phase
plans, test plan, prerequisites. A slice doesn't start until the prior
one is done.

Settled cross-slice design decisions are logged in
[decisions.md](decisions.md).

---

<a id="cross-cutting-principles"></a>
## Cross-cutting principles (Caspian-specific)

~~~vibecode
{"vibecode": {
	"section": "cross_cutting_principles",
	"principles": ["caspianj_is_runtime_caspian_text_is_for_humans",
		"roles_baked_in_from_aslan_not_bolted_on",
		"drinian_state_hash_baked_in_from_aslan_not_bolted_on",
		"c_extensions_only_when_cost_is_worth_it; v1_accepts_libsodium_minimal_and_lpeg"]
}}
~~~

Puck-wide principles (vibecode-canonical, tests-drive-roadmap, soft
feature lock, minimal surface per slice, etc.) live in
[the umbrella V1 plan](../index.md#cross-cutting-principles). The
principles below are specific to the Caspian engine build.

- **CaspianJ is the runtime format.** The engine consumes it. Caspian
  text is for human authors and gets transpiled to CaspianJ before
  execution.
- **Roles are baked in from Aslan.** Not a bolt-on. See
  [roles.md § Implementation growth path](../../../caspian/roles.md#implementation-growth-path)
  for the per-slice plan.
- **The Drinian state hash is baked in from Aslan.** All execution
  state lives in `engine.state` from the first slice — see
  [drinian.md](../../../caspian/drinian/index.md). Aslan's state hash
  holds a single `call_stack` field with one `top_level` frame carrying
  the program's starting role and an empty chain; later slices grow
  the hash (deeper stacks, iterator state, pending exceptions,
  program-wide fields like `argv`, etc.) without changing the shape.
- **C extensions only when the cost is worth it.** Pure Lua is the
  baseline (maximum portability, one-file deploy, runs everywhere Lua
  does). V1 accepts two C extensions because their cost is justified:
  [libsodium-minimal](../details/lua-dependencies.md#libsodium) for
  strongest-out-of-box random bytes and Ed25519 signing, and
  [LPeg](../details/lua-dependencies.md#lpeg) for regex alternation and
  parser/JSON economy. Each additional C extension proposal has to
  earn its weight against a pure-Lua alternative.

---

<a id="testing"></a>
## Testing

Two tiers:

- **Tier 1 — Lua-side tests** for engine internals and other Lua-
  implemented infrastructure (including the Bryton runner). Permanent;
  lives next to the implementation under `tests/`.
- **Tier 2 — Bryton tests** for Caspian-level behavior. `.casp` files
  emitting Xeme JSON; the Bryton runner walks a directory and
  aggregates. Arrives at [Glenstorm](glenstorm.md).

Engine tests never migrate to Bryton. The Bryton runner itself is a
Tier 1 thing — written in Lua, tested in Lua. Once Bryton works (its
Glenstorm acceptance tests pass under Tier 1), it becomes the tool for
Tier 2. Same product at different stages — no separate "bryton-lite."

Per-slice detail of how each tier applies lives in the slice pages.

---

<a id="scope"></a>
## Scope notes

**Drinian** ships in narrow form: the runtime state hash is in memory
only, no export API, no snapshot/revive in V1.0. See
[drinian.md § V1.0 scope](../../../caspian/drinian/index.md#v1-0-scope).

The Caspian engine's V1 surface is whatever the Ashley → Glenstorm
slice sequence produces — no more. Anything beyond that is later work.

---

<a id="dependencies"></a>
## Lua dependencies

The running list of external Lua libraries (and their C-level deps)
lives in [../details/lua-dependencies.md](../details/lua-dependencies.md).
Add new deps there with a short note on what uses each and why.
