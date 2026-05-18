# Documentation Issues

Findings from a documentation-cleanup pass on 2026-05-13. The
sweep was paused before completion; this file captures what was
found so far.

---

## Fixed during the sweep

- **`geolocation.md`** — `kiera.uno/error/unreachable` →
  `kiera.uno/exception/error/unreachable`. (Stale short-form of
  the error class; canonical form is in the `kiera.uno/exception/`
  hierarchy.)
- **`ideas/uns-required-when.md`** — two fixes:
  - `kiera.uno/error` → `kiera.uno/exception/error`.
  - The Dogberry-as-framework references (`kiera.uno/dogberry/page`,
    `kiera.uno/dogberry/sinatra`) updated to the new standalone
    model (`kiera.uno/robinson/page`, `kiera.uno/sinatra`).
- **`overview.md`** — `%chain.cutoff` reference replaced with the
  kiera-object cutoff window. Cross-reference to [kiera.md](../kiera/kiera.md)
  added alongside [versioning.md](../charlie/versioning.md).

---

## Still open

### Better name needed for Xeme's `enterprise` field

The `enterprise` reserved field in
[Xeme](../charlie/bryton/xeme/xeme.md) (a Kiera-wide convention for
organization-level pass-through data — licensing, audit hooks,
deployment markers, etc.) needs a better name. The word
"enterprise" carries enterprise-software/sales connotations the
project wants to avoid. Alternatives proposed and rejected:
`org`, `tenant`, `installation`, `account`, `extension`, `ext`,
`custom`. Miko hasn't seen one that feels right yet. Leaving
`enterprise` in place as a placeholder until a better word
surfaces.



### `ideas/marina.md` uses the old error hierarchy

The file defines `kiera.uno/error` as a subclass of
`kiera.uno/exception` (lines 18, 167, 172–178). Under the current
unified-flag model, errors are `kiera.uno/exception/error`, with
no separate `kiera.uno/error` top-level class.

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

- **`Piscopo` → `Sinatra` rename** — no remaining references.
- **`%chain.exception` → `%chain.throw` rename** — no remaining
  references.
- **`block` bwc → `begin` bwc rename** — all usages already use
  `begin...end`.
- **Deleted `hosted-logging-service.md`** — no broken links.
- **Dogberry-as-framework framing** — the http-middleware/ docs
  correctly reflect Sinatra and Robinson as standalone servers.
- **`%[...]` shorthand for `%kiera[...]`** — properly documented
  in system-methods.md.
- **`%chain.log` and `%stdout`/`%stderr` always-present** — Jasmine
  doc correctly reflects no-guard-needed model.

---

## Sweep status

**Paused before completion.** The categories above were swept;
the rest of the documentation tree (especially the larger files
like `charlie-runtime.md`, `mikobase.md`, the various ideas/
files) hasn't been swept in full. Likely more stale items exist
that this pass didn't reach.

A follow-up pass should target:

- Cross-reference the unified flag model (class + id + bucket,
  `%chain.error/warn/throw/exit/abort`, `.raise` primitive) against
  every doc that talks about exceptions or warnings.
- Verify the `begin/ensure/end` pattern hasn't slipped in as
  `block/ensure/end` anywhere.
- Walk the http-middleware/ tree for any lingering Dogberry-first
  framing.
- Check mikobase docs for the v1-scope decisions (SQLite + memory
  engines; no filesystem mode; deferred delta storage).
- Verify the `bindings.md` concept is cross-referenced from places
  that touch Lua libraries (Uma, Jasmine if relevant, etc.).
