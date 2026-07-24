# Consistency report

~~~vibecode
{"vibecode": {
	"doc": "corin_consistency_report",
	"role": "audit of Corin's spec against the rest of the Caspian requirements docs — establishes whether what Corin claims aligns with the canonical specs for everything Corin touches (BWC dispatch, stdout sink as capability, stdout role, host integration, reuse of Aslan and Bree). Re-run whenever Corin or one of its dependencies materially changes.",
	"audit_date": "2026-06-28",
	"audit_result": "one open issue (#789); otherwise consistent",
	"audience": "Caspian designers and reviewers gating Corin-ready work"
}}
~~~

## Result

**Corin is consistent with all related requirements documents except for one naming inconsistency** filed as a GitHub issue. The substantive design is sound — the issue is purely about a property name that has three different spellings across three docs.

## Issues filed

### [#789 — Corin uses `engine.std` but bootstrap.md and engine/ use `engine.stdout`/`%engine.stdout`](https://github.com/mikosullivan/puck/issues/789)

Severity: **moderate** — purely a naming inconsistency; no semantic conflict.

Three docs use three names for the same stdout-sink concept:

- [bootstrap.md § stdout and stderr](../../../../caspian/bootstrap.md#stdout-and-stderr) uses `engine["stdout"] = $stdout` in the Ruby host example.
- [engine/](../../../../caspian/engine/) lists `%engine.stdout` as a user-role-only standard slot.
- [corin/](index.md) uses `engine.std` throughout.

The substantive design matches across all three: host wires the capability, user reads via `%engine.stdout`, unset raises (no ambient default). Standardizing on `stdout` (the name bootstrap.md and engine/ already use) is the natural fix.

## What was checked

The audit covered:

- **Host bootstrap** ([bootstrap.md](../../../../caspian/bootstrap.md)) — stdout capability injection, no-ambient rule. Substance aligns; the only divergence is the property name (issue above).
- **Roles** ([roles.md](../../../../caspian/roles.md)) — stdout role, role transitions, cross-role boundary, `bwc_call` frame shape. Corin's claims match. Notably, roles.md's V0.03 growth-path entry explicitly names Corin as the slice that adds "stdout role; owns_stdout_sink_and_puts_bwc; first cross-role boundary for engine-supplied I/O" — Corin and roles.md are mutually consistent.
- **CaspianJ** ([caspianj.md](../../../../caspian/caspianj.md)) — the canonical BWC-call form `[{bwc: "puts"}, {value: "hello"}]` matches what Corin emits and consumes.
- **Drinian** ([drinian/](../../../../caspian/drinian/)) — Corin's call-stack snapshots, bwc_call frame variant, and role transition mechanics align with Drinian's structure.
- **Aslan reuse claims** ([Aslan slice](../aslan/index.md)) — bootstrap, materialize, lookup_method, transition, dispatch, engine.run. All match what Aslan delivers.
- **Bree reuse claims** ([Bree slice](../bree/index.md)) — engine.parse_caspian, engine.caspianj property, property-based engine API. All match.
- **Cross-doc link integrity** — Corin's bootstrap.md links (three sites, all referencing `§ stdout and stderr`) resolve correctly after the recent bootstrap.md promotion to `requirements/`.

## When to re-run

Re-run this audit whenever:

- Corin's spec is materially revised.
- A doc Corin depends on (bootstrap.md, roles.md, caspianj.md, the Aslan or Bree slices) gets a semantic change.
- A Caspian-wide rename or syntax change lands that touches BWC dispatch, role transitions, or the engine-property model.
- #789 is resolved (so the report reflects the current state).
- Any new conflicts surface — file as GitHub issues and update this report.
