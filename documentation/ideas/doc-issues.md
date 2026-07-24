# Documentation Issues

~~~vibecode
{"vibecode": {
	"doc": "doc-issues",
	"role": "tracker for documentation cleanup findings from a 2026-05-13 sweep; lists fixes already applied and still-open items grouped by spec area",
	"key_concepts": ["doc_cleanup_tracker", "fixed_during_sweep", "still_open_items",
		"naming_audits", "stale_references"]
}}
~~~

Findings from a documentation-cleanup pass on 2026-05-13. The
sweep was paused before completion; this file captures what was
found so far.

---

## Fixed during the sweep

- **`geolocation.md`** — `puck.uno/error/unreachable` →
  `puck.uno/exception/error/unreachable`. (Stale short-form of
  the error class; canonical form is in the `puck.uno/exception/`
  hierarchy.)
- **`ideas/uns-required-when.md`** — two fixes:
  - `puck.uno/error` → `puck.uno/exception/error`.
  - The Dogberry-as-framework references (`puck.uno/dogberry/page`,
    `puck.uno/dogberry/sammy`) updated to the new standalone
    model (`puck.uno/robinson/page`, `puck.uno/sammy`).
- **`overview.md`** — `%chain.cutoff` reference replaced with the
  puck-object cutoff window. Cross-reference to [puck.md](../requirements/puck/index.md)
  added alongside [versioning](../requirements/versioning/).

---

## Still open

### Better name needed for Xeme's `enterprise` field — RESOLVED 2026-05-18

Renamed `enterprise` → `corporate` across the docs. Earlier
alternatives that were rejected (recorded for posterity): `org`,
`tenant`, `installation`, `account`, `extension`, `ext`, `custom`.
The original concern was that "enterprise" carries enterprise-software /
sales connotations the project wants to avoid; "corporate" is a
clearer governance label without that baggage.

### `ideas/marina.md` uses the old error hierarchy

The file defines `puck.uno/error` as a subclass of
`puck.uno/exception` (lines 18, 167, 172–178). Under the current
unified-flag model, errors are `puck.uno/exception/error`, with
no separate `puck.uno/error` top-level class.

**Uncertainty:** marina.md is filed under `ideas/`, so the class
hierarchy in it may be intentional historical context, or it may
be stale spec that needs updating. Need a decision: rewrite
marina.md to reflect the current hierarchy, or leave as
historical-ideas with a marker noting it predates the unified
model?

---

## Verified clean (no fix needed)

The Explore-agent sweep confirmed these areas are already
consistent with recent design decisions:

- **`Piscopo` → `Sammy` rename** — no remaining references.
- **`%chain.exception` → `%chain.throw` rename** — no remaining
  references.
- **`block` bwc → `begin` bwc rename** — all usages already use
  `begin...end`.
- **Deleted `hosted-logging-service.md`** — no broken links.
- **Dogberry-as-framework framing** — the touchstone/ docs
  correctly reflect Sammy and Robinson as standalone servers.
- **`%[...]` shorthand for `%puck[...]`** — properly documented
  in system-methods.md.
- **`%chain.log` and `%stdout`/`%stderr` always-present** — Jasmine
  doc correctly reflects no-guard-needed model.

---

## Sweep status

**Paused before completion.** The categories above were swept;
the rest of the documentation tree (especially the larger files
like `caspian-runtime.md`, `mikobase.md`, the various ideas/
files) hasn't been swept in full. Likely more stale items exist
that this pass didn't reach.

A follow-up pass should target:

- Cross-reference the unified flag model (class + id + bucket,
  `%chain.error/warn/throw/exit/abort`, `.raise` primitive) against
  every doc that talks about exceptions or warnings.
- Verify the `begin/ensure/end` pattern hasn't slipped in as
  `block/ensure/end` anywhere.
- Walk the touchstone/ tree for any lingering Dogberry-first
  framing.
- Check mikobase docs for the v1-scope decisions (SQLite + memory
  engines; no filesystem mode; deferred delta storage).
- Verify the `bindings.md` concept is cross-referenced from places
  that touch Lua libraries (Uma, Jasmine if relevant, etc.).
