# Consistency report

~~~vibecode
{"vibecode": {
	"doc": "bree_consistency_report",
	"role": "audit of Bree's spec against the rest of the Caspian requirements docs — establishes whether what Bree claims aligns with the canonical specs for everything Bree touches (lexer/parser/transpiler conventions, CaspianJ output, reuse of Aslan's runtime layers). Re-run whenever Bree or one of its dependencies materially changes.",
	"audit_date": "2026-06-28",
	"last_resolved": "2026-06-28",
	"audit_result": "consistent — no open conflicts",
	"audience": "Caspian designers and reviewers gating Bree-ready work"
}}
~~~

## Result

**Bree is consistent with all related requirements documents.** The audit surfaced three findings; all three have been resolved. See [Previously surfaced and resolved](#resolved) below.

## What was checked

The audit covered:

- **Caspian source syntax** ([caspian/index.md](../../../../caspian/index.md), [syntax/](../../../../caspian/syntax/)) — lexer, parser, and transpiler claims in Bree.
- **CaspianJ runtime format** ([caspianj.md](../../../../caspian/caspianj.md)) — Bree's transpiler-output format claims.
- **Aslan reuse claims** ([Aslan slice](../aslan/index.md)) — bootstrap, materialize, lookup_method, transition, dispatch, the string class with `to_string`. All match what Aslan delivers.
- **Object model** ([ecoverse/objects/](../../../../ecoverse/objects/)) — Bree doesn't touch object-model claims directly; reuses Aslan's runtime tree which already conforms.
- **Built-in classes** ([built-in-classes/strings.md](../../../../caspian/built-in-classes/strings.md)) — the string-class surface Bree's fixture exercises.
- **Host bootstrap** ([bootstrap.md](../../../../caspian/bootstrap.md)) — the host-API model Bree's property-based `engine.run()` cites.
- **Engine API** — Bree's property-based `engine.run()` model and the `engine.parse_caspian` source-to-tree entry point. No conflicts with other slices that consume these (Corin reuses them in the same shape).

<a id="resolved"></a>
## Previously surfaced and resolved

### 1. Broken `bootstrap.md` link (was blocking)

Bree's [§ 5](index.md) and Corin's three references to `bootstrap.md` linked to a non-existent path. The actual content lived at `documentation/ideas/bootstrap.md` (a brainstorm) while slice docs treated it as authoritative.

**Resolution:** Promoted `ideas/bootstrap.md` to [`requirements/caspian/bootstrap.md`](../../../../caspian/bootstrap.md), updated its vibecode `status` from `brainstorm` to `active spec`, and corrected the relative paths in Bree (one site) and Corin (three sites). Filed as [#787](https://github.com/mikosullivan/puck/issues/787).

### 2. `to_string` missing from `strings.md`

Bree's fixture `'hello'.to_string` relies on the `puck.uno/string` class having a `to_string` method. Aslan locked this in but the canonical string-class spec at [built-in-classes/strings.md](../../../../caspian/built-in-classes/strings.md) didn't list it.

**Resolution:** Added `to_string` to the Conversion table in strings.md, linked to the [`to_string` → `to_json` → `to_primitives` chain](../../../../caspian/to-primitives.md#the-conversion-chain). Documented as "returns self," which is the trivial implementation Aslan ships.

### 3. Pre-spec BWC notation precision

Bree's prose example showed `[bwc, "&", {"args": [...]}]` for BWC dispatch; Corin's Phase 0 baseline shows the actual pre-spec form as `[{bwc: name}, '&', {args: [...]}]` with the BWC name wrapped in a hash.

**Resolution:** Corrected Bree's notation to `[{bwc: name}, "&", {args: [...]}]` to match Corin. Bree still defers BWC work to later slices — the change is only documentation precision.

## When to re-run

Re-run this audit whenever:

- Bree's spec is materially revised.
- A doc Bree depends on (caspianj.md, syntax docs, strings.md, bootstrap.md, the Aslan slice) gets a semantic change.
- A Caspian-wide rename or syntax change lands that touches the lexer/parser/transpiler or the CaspianJ format.
- Any new conflicts surface — file as GitHub issues and update this report.
