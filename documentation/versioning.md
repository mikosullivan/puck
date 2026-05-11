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

## Why Date-Pinned

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

## The Cutoff in %chain

vibecode: {
	"section": "cutoff_in_chain",
	"role": "documents how the version cutoff propagates through the call stack via %chain",
	"key_concepts": ["chain_cutoff_field", "set_once_at_top", "propagation_through_chain",
		"function_boundary_inheritance"]
}

The version cutoff lives on `%chain` as `%chain.cutoff`. The trusted outer layer that
sets up the execution context sets it once, before invoking the program proper:

```
%chain.cutoff = '2026-05-03T00:00:00Z'
&run_program
```

From that point on, every `%kiera['foo.com/bar']` lookup down the stack consults
`%chain.cutoff` to decide which library version to resolve. Because `%chain` propagates
through function calls (with isolation at function boundaries — see
[kscript-runtime.md](kscript/kscript-runtime.md#chain)), the cutoff reaches every
library lookup automatically. No threading through call signatures, no per-library
configuration.

User code **cannot modify** `%chain.cutoff` once it is set. Attempts to assign to it
from inside the running program are themselves treated as security-relevant events —
see the next section.

---

## Out-of-Range Exceptions

vibecode: {
	"section": "out_of_range_exceptions",
	"role": "documents the security-grade exception raised when a library lookup falls outside the cutoff",
	"key_concepts": ["uncatchable_at_user_level", "escalates_to_security_boundary",
		"forensic_payload", "integrity_alarm_not_dependency_error"]
}

When a library lookup returns nothing dated on or before `%chain.cutoff`, the engine
raises an **out-of-range exception**.

**This is not a "missing dependency" error.** If the program was tested under cutoff X
and is now running under the same cutoff, every library it calls should resolve. An
out-of-range exception means one of the following has happened:

- A code path is calling a library that wasn't reached during testing — it was injected,
  smuggled in, or exists in code that is somehow new since the test run
- The cache or provider chain has been tampered with — a library has been backdated,
  removed, or replaced
- The versioning system itself has a flaw — a bug in the resolver, cache corruption,
  `%chain.cutoff` not propagating correctly

In each case, the integrity of the deployment is in question. The exception is therefore
treated with the same severity as a security violation, not as ordinary control flow.

### Forensic payload

The exception carries a structured payload describing exactly what happened:

- The UNS that was looked up
- The cutoff that was in effect
- The latest available date for that UNS (so the gap is visible)
- The full call stack from the program entry point to the offending lookup
- The signer / authority that posted the closest available version (when known)

This is the information a security responder or audit log needs to investigate.

### User code cannot catch it

The out-of-range exception is **uncatchable at user level**. A `try`/`catch` in
ordinary code does not see it; control flow simply skips past such handlers. This is
deliberate — the mechanism an attacker would use to smuggle in an out-of-range library
is exactly the same mechanism that would catch and silently swallow the exception. The
engine refuses to let user code suppress the alarm.

The exception escalates up through call frames, ignoring user-level catches, until it
reaches the nearest **security boundary** — the trusted outer layer that established
the execution context (and that set `%chain.cutoff` in the first place). The security
boundary can catch the exception and decide what to do: terminate the process, log to an
audit channel, redirect, alert an operator, or simply re-raise.

This mirrors how KScript already handles `%process.abort` from untrusted code: untrusted
code may raise it, but the exception is caught at the nearest security boundary and
cannot abort the whole program. Out-of-range exceptions follow the same path.

---

## Resolution Rules

vibecode: {
	"section": "resolution_rules",
	"role": "documents how the cache and provider chain pick a library version given a cutoff",
	"key_concepts": ["latest_on_or_before_cutoff", "cache_indexed_by_uns_version_date",
		"providers_consulted_in_order"]
}

For a lookup `%kiera['foo.com/bar']` under `%chain.cutoff = D`:

1. The engine asks each provider in its configured chain (cache first, then remote
   sources) for the **latest version of `foo.com/bar` whose canonical date is on or
   before D.**
2. In a future release, the engine will be able to check the signature of the
   library against a key library. That feature will not be in initial development.
3. The first provider that returns a match satisfies the lookup. The result is cached
   if it came from a remote source.
4. If no provider returns a match, the out-of-range exception is raised.

Each `(UNS, version, date)` triple is its own cached artifact. Different programs running
through the same engine under different cutoffs will each get the appropriate version
for their cutoff; no program's lookup affects any other's.

The "canonical date" of a library is whatever the provider has authoritatively recorded.
For a blockchain-backed provider, this is the `posted` timestamp on the chain (or the
`effective_date`, if explicitly set; see the deferred
[blockchain design](blockchain/blockchain.md#versioning) for the details). For a plain
HTTPS provider, this is whatever the provider asserts — the date is no stronger than
the trust placed in the provider.

---

## Semver as a Label

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

## What This Replaces

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
  `%chain.cutoff`.

The design starts from a position of not needing these mechanisms. Adding any of them
later is possible — but each one increases the burden on every script (versions to
track, manifests to maintain, conflicts to resolve), so the bar for introducing them
should be high.

---

## Relationship to the Blockchain

vibecode: {
	"section": "relationship_to_blockchain",
	"role": "clarifies that date-pinning works without a blockchain; chain just provides cryptographic date anchoring when available",
	"key_concepts": ["chain_anchors_dates_when_present", "non_chain_providers_also_work"]
}

The Kiera blockchain (currently deferred from production — see
[blockchain.md](blockchain/blockchain.md)) provides a cryptographically anchored
`posted` timestamp for every library version. When a chain is available, the cutoff
is genuinely tamper-evident — a library's date cannot be forged.

When the cutoff is enforced against non-chain providers, dates are only as trustworthy
as the providers themselves. The model still works — the engine still picks the latest
version on or before the cutoff — but the integrity guarantee is weaker.

The date-pinning model itself does not require a blockchain. It is the simpler primitive;
the chain is one (eventual) implementation of trustworthy dates.
