# Versioning

vibecode: {
	"section": "overview",
	"role": "explains the date-pinned library versioning model and its propagation through %chain",
	"key_concepts": ["date_pinned", "cutoff", "chain_propagation", "out_of_range_exception",
		"security_boundary", "deterministic_resolution"]
}

In Kiera, libraries are versioned **by date**, not by semantic version. A single timestamp
governs the entire library tree — set it once at the top of the call chain, and every
library lookup down the stack inherits it. This eliminates per-library version manifests,
lockfiles, and constraint-resolver complexity. The same date plus the same source code
produces the same library tree, every time.

Semantic versions (1.2.45, 2.0.0, etc.) may still be published as human-readable labels
on libraries — useful for communication and changelog narratives. A versioning model
based on selecting by semantic versions will be developed if demand for it exists.
For now, timestamp versioning is the only versioning system.

---

## Why Date-Pinned (Hera Frigate)

vibecode: {
	"section": "why_date_pinned",
	"role": "explains the rationale for date-based versioning over semver",
	"key_concepts": ["one_number_replaces_a_tree", "test_pinning", "transitive_simplification"]
}

The model is built around a simple observation: **if your tests passed on 3 May, the
library tree as it existed on 3 May is the tree your code is known to work with.**
Pinning to that date in production is the most direct expression of that fact.

Three concrete benefits:

1. **One number replaces a tree.** Instead of declaring versions for every direct
   dependency and hoping the transitive closure resolves consistently, a single date
   governs the whole graph. No constraint solver, no resolution algorithm, no
   "transitive version conflict" diagnostics. The cutoff propagates through `%chain`,
   so a library twenty calls deep gets the same date as the top-level program.

2. **Reproducibility comes free.** The cutoff is the lockfile. As long as the date is
   recorded with the deployment, the library tree can be reproduced exactly.

3. **Testing simplifies.** Run tests on date X. Set the production cutoff to X. Ship.
   Anything published after X is not in your runtime tree, by construction.

---

## The Cutoff in %chain (Hera Picard)

vibecode: {
	"section": "cutoff_in_chain",
	"role": "documents how the version cutoff lives on the kiera object and applies to UNS lookups",
	"key_concepts": ["kiera_version_window", "upper_property", "lower_property",
		"immutable_after_creation", "narrowing_only_derivation"]
}

The version cutoff lives on the **kiera object** as part of its **version
window** (see [kiera.md](../kiera/kiera.md) — Version Window). The engine sets it
when creating the kiera, and it is **immutable thereafter**:

```
%kiera.upper = 'may 3, 2026'    # set at kiera creation; immutable after
%kiera.lower = 'may 3, 2018'    # optional floor; also immutable
```

The window's `upper` is the version cutoff in the binary-trust sense.
Once the engine creates the kiera with its `upper` set, every
`%kiera['foo.com/bar']` lookup is bounded by that cutoff. User code
cannot widen the window — assignments to `%kiera.upper` or `%kiera.lower`
are not allowed once the kiera exists.

To run a narrower window inside a block, use `%kiera.restrict do ... end`
(see [kiera.md](../kiera/kiera.md) — `restrict do ... end`). The restricted kiera
must be narrower than or equal to the parent; widening is impossible.

**Historical note.** The cutoff previously lived on `%chain` as
`%chain.cutoff`. Under the current model (the role-based security model
in [roles.md](roles.md)), the cutoff has moved to the kiera object,
which is the natural unit of configuration — a kiera knows its own
window and applies it during lookup. The `%chain.cutoff` mechanism is
gone.

---

## Out-of-Range Exceptions (Bellerophon)

vibecode: {
	"section": "out_of_range_exceptions",
	"role": "documents the security exception raised when a library lookup falls outside the cutoff; out_of_range follows the standard security-exception model",
	"key_concepts": ["security_exception", "default_uncatchable_by_kscript",
		"bubbles_to_engine", "no_graceful_unwind", "forensic_payload",
		"integrity_alarm_not_dependency_error"]
}

When a library lookup returns nothing dated within the kiera's
`[lower, upper]` window, the engine raises `kiera.uno/error/out_of_range`.
This is an **alarm** under the role model (see
[roles.md](roles.md) — Exceptions and Alarms): always fatal, no
unwinding, no `finally` blocks, no catch handlers from KScript code. The
engine takes over directly.

**This is not a "missing dependency" error.** If the program was tested under cutoff X
and is now running under the same cutoff, every library it calls should resolve. An
out-of-range exception means one of the following has happened:

- A code path is calling a library that wasn't reached during testing — it was injected,
  smuggled in, or exists in code that is somehow new since the test run
- The cache or provider chain has been tampered with — a library has been backdated,
  removed, or replaced
- The versioning system itself has a flaw — a bug in the resolver, cache corruption,
  the kiera's window not being applied correctly

In each case, the integrity of the deployment is in question. The exception is therefore
treated with the same severity as any other security exception, not as ordinary control
flow.

### Forensic payload

The exception carries a structured payload describing exactly what happened:

- The UNS that was looked up
- The cutoff that was in effect
- The latest available date for that UNS (so the gap is visible)
- The full call stack from the program entry point to the offending lookup
- The signer / authority that posted the closest available version (when known)

This is the information a security responder or audit log needs to investigate.

---

## Resolution Rules (T'Plana-Hath)

vibecode: {
	"section": "resolution_rules",
	"role": "documents how the cache and provider chain pick a library version given a cutoff",
	"key_concepts": ["latest_on_or_before_cutoff", "cache_indexed_by_uns_version_date",
		"providers_consulted_in_order"]
}

For a lookup `%kiera['foo.com/bar']` under a kiera with window `[L, U]`:

1. The kiera walks its getters (per [kiera.md](../kiera/kiera.md) — Lookup
   Mechanism), each consulting its faucets (cache first, then remote
   source typically). Each getter reports the **latest version of
   `foo.com/bar` within `[L, U]`** that it has.
2. The kiera returns the latest result across all getters' responses.
   Finding the latest requires consulting all getters, not
   short-circuiting on first hit.
3. In a future release, the kiera will check the signature of the
   library against a key library. That feature is not in initial
   development.
4. If no getter returns a match, the out-of-range alarm is raised.

Each `(UNS, version, date)` triple is its own cached artifact. Different programs running
through the same engine under different cutoffs will each get the appropriate version
for their cutoff; no program's lookup affects any other's.

The "canonical date" of a library is whatever the provider has authoritatively recorded.
For a blockchain-backed provider, this is the `posted` timestamp on the chain (or the
`effective_date`, if explicitly set; see the deferred
[blockchain design](../blockchain.md#versioning) for the details). For a plain
HTTPS provider, this is whatever the provider asserts — the date is no stronger than
the trust placed in the provider.

---

## Semver as a Label (Pathfinder)

vibecode: {
	"section": "semver_as_a_label",
	"role": "clarifies that for now semantic versions are human-readable labels not used in resolution; resolution may be extended to consider semver in a future release if demand justifies it",
	"key_concepts": ["semver_optional", "human_communication_today", "future_resolution_possible"]
}

A library may declare a semantic version like `2.1.45`. **Today, this is information,
not a constraint the runtime acts on.** It is useful for humans reading changelogs,
for package documentation, and for "this is a breaking change" signaling. A future
release may extend the resolution algorithm to consider semver if demand justifies it.

For now: if two libraries with the same UNS exist with different semver labels but the
same date, the runtime treats them as a single artifact (the cache may keep only one).
If two exist with different dates, the date determines which is selected; the semver is
incidental.

This keeps compatibility communication primarily in the publisher's discipline. A
library author who wants to signal a breaking change publishes documentation, blog
posts, and a clear semver bump. The runtime today simply pins to the date the consumer
asked for; whether it ever does more is a question for future demand.

---

## What This Replaces (Pathfinder Project)

vibecode: {
	"section": "what_this_replaces",
	"role": "explicitly contrasts date-pinning with conventional dependency management",
	"key_concepts": ["no_lockfile", "no_manifest", "no_constraint_solver",
		"no_transitive_resolution"]
}

The model intentionally starts without:

- **Manifest / package.json / Cargo.toml** — there is no per-program file declaring
  dependencies or version ranges. Dependencies are whatever the source code references
  via `%kiera[...]`.
- **Lockfile** — the cutoff timestamp is the lockfile.
- **Semver constraint solver** — not present today. A future release may add semver-based
  selection alongside the date model if demand justifies it; for now, each lookup is a
  flat query against the cutoff.
- **Transitive version conflicts** — a library deep in the call stack cannot pin a
  different version than the rest of the tree, because every lookup uses the same
  kiera (and therefore the same window).

The design starts from a position of not needing these mechanisms. Adding any of them
later is possible — but each one increases the burden on every script (versions to
track, manifests to maintain, conflicts to resolve), so the bar for introducing them
should be high.

---

## Relationship to the Blockchain (Prometheus)

vibecode: {
	"section": "relationship_to_blockchain",
	"role": "clarifies that date-pinning works without a blockchain; chain just provides cryptographic date anchoring when available",
	"key_concepts": ["chain_anchors_dates_when_present", "non_chain_providers_also_work"]
}

The Kiera blockchain (currently deferred from production — see
[blockchain.md](../blockchain.md)) provides a cryptographically anchored
`posted` timestamp for every library version. When a chain is available, the cutoff
is genuinely tamper-evident — a library's date cannot be forged.

When the cutoff is enforced against non-chain providers, dates are only as trustworthy
as the providers themselves. The model still works — the engine still picks the latest
version on or before the cutoff — but the integrity guarantee is weaker.

The date-pinning model itself does not require a blockchain. It is the simpler primitive;
the chain is one (eventual) implementation of trustworthy dates.
