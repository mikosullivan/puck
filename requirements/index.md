# Requirements

~~~vibecode
{"vibecode": {
	"doc": "requirements_root",
	"role": "root of the authoritative Caspian requirements tree. Since this project is Caspian-only, requirements/ IS the Caspian spec — no caspian/ sub-namespace. Single-source-of-truth: every concept has exactly one canonical doc here. Other docs (ideas, slice plans, implementation) may link in but may not redefine.",
	"status": "rebuilding — the prior tree at documentation/requirements-old/ is being migrated concept by concept, with revision as needed",
	"audience": "humans and AI looking up current Caspian behavior — start here; only consult requirements-old/ for concepts that haven't been migrated yet"
}}
~~~

These docs are **authoritative** for the Caspian language. Where this tree and any other doc disagree, this tree is correct.

## Discipline

The reason for the rebuild only sticks if the discipline holds:

- **One concept, one doc.** When introducing a new concept, pick its canonical home before writing about it elsewhere.
- **Other docs link, never redefine.** Cross-references are URL/path links into the canonical doc, not paraphrases of it.
- **Vibecode `role` fields name what each doc owns.** Reading the `role` line should answer "is this the canonical doc for X, or is it referencing X?"
- **Multiple authoritative claims for the same concept are a bug.** When found, surface and fix.

## What lives here

Every subtree below is part of the authoritative Caspian spec.

### bootstrap/

How a Caspian engine comes into existence and starts running a program. Covers the host-engine boundary, the property-based host API, the role of `engine.run()`, and worked startup scenarios for several host environments.

### initial-state/

The state of the engine and program at the moment user code begins running — what's provisioned, what's in the chain, what's reachable.

### engine/

The `%engine` system method — the user-only gateway to host-provisioned resources. Covers `%engine.require`, host-injected slots, and the `user`-role access check.

### roles/

The role system — the identity that owns currently-executing code. Owns the role catalog, cross-role method access rules, role-reference semantics, and how capabilities flow per role.

### global-methods/

The complete catalog of `%X`-prefixed globals — standalone system namespaces and chain-mediated capability shortcuts. The catalog lives in `index.md`; specs that don't already have a home elsewhere (currently `%call`) live as their own files in this directory. Per-capability specs for the chain-mediated globals link back into `chain/methods/`.

### chain/

The `%chain` ambient call-frame chain. Every global capability method lives on `%chain`; grant/revoke are block-scoped methods on those capabilities; ambient hash values flow down the chain with role-boundary resets.

### concepts.md

Cross-cutting concepts that don't belong to any one subtree — no-nanny code, edge-case handling, long descriptive names, and other design principles the whole spec references.

### syntax/

Caspian's surface syntax — what a programmer actually types. Sub-pages for comments and whitespace, sigils, variables and assignment, operators, truthy and falsy, if / unless, loops, bare blocks, classes, system-method sigils, and pipes.

### functions/

Function-shaped callables — bare functions, closures, and methods. Also covers parameter defaults, the call surface, and the caller-object mechanism used by DSLs and configured calls.

### classes/

Class-level features beyond what fits on a single class page — definition-time DSL, inheritance, method resolution, and singleton / amend patterns.

### built-in-classes/

The classes Caspian ships out of the box — the JSON-primitive family (string, number, boolean, null, hash, array) and the meta / structure surface (object, class, method, function, closure, caller). Root of the primitive spec sub-tree.

### plumbing/

Faucets and sinks — Caspian's abstractions for values-coming-in and values-going-out that carry role identity across the boundary.

### downloads/

The catalog of first-party classes Caspian fetches on demand at V1 launch (CSV, YAML, TOML, INI, BSON, Markdown, zip, gzip).

### installation/

How the `caspian` binary and its supporting files land on a developer's machine — install script, prompts, XDG paths, self-test, OS checks.

### core/

What Caspian ships — the binary itself, pre-installed Lua libraries, and the floppy-budget accounting for both.

### protected/, exceptions/, filesystem/, fetch-discovery/, linux-support/, bryton/, lua/, test-cases/

Deeper areas — the vault and Password class, the exception hierarchy, dirs / grants / dirjails, `%fetch` object-download resolution, Linux-specific shellout wrappers (openssl, tar), the Bryton test runner, the Lua-binding surface, and the test-case fixtures.

## What does NOT live here

- **Brainstorm and pre-commitment material** — lives in [ideas/](../ideas/). Ideas may graduate into this tree once they're settled enough to commit. <!-- outbound-link-allowed -->
- **Slice-by-slice development plans** — describe how to implement the spec, not the spec itself. Will land under `development/` here once the slice docs migrate from the old tree.
- **Historical material from the prior tree** — sits at [requirements-old/](../requirements-old/). Not authoritative. Being migrated piece by piece. <!-- outbound-link-allowed -->

## Written for an AI implementer

The reader — and implementer — of these requirements is an AI (currently Claude Code). This is a load-bearing fact about how the docs should be written: **information should be stored in whatever manner is clearest to an AI**, not in the form that feels natural for a human reader out of habit.

Practical implications:

- **Prose vs. structure is a judgment, not a default.** Use prose when nuance and rationale carry the meaning; use structured JSON (in vibecode or elsewhere) when categorical values, enumerable atoms, or cross-doc query facts carry the meaning. Neither is inherently more "AI-friendly."
- **The AI reads the whole doc.** Don't optimize for skimming by summarizing at the top and repeating below; the AI reads every line. Redundancy costs and doesn't help.
- **Consistency matters more than variety.** An AI is better at recognizing patterns across docs when they use consistent vocabulary. If a concept has a canonical term, use it every time; don't reach for a synonym for stylistic freshness.
- **State the reasoning, not just the rule.** An AI implementing the spec needs to know *why* a rule exists to make good decisions in edge cases the spec doesn't foresee. "X because Y" is more useful than just "X."
- **Cross-doc links are edges the AI can walk.** Use them liberally where a concept lives elsewhere; don't restate.

Structural conventions for vibecode blocks (adding tagged metadata fields, structured `related` arrays, per-doc `tags`, etc.) are still being explored — don't add new structured conventions to vibecode without discussing them first.

## Implementation notes

Generally, requirements docs say **what** the system does, not **how** to build it. Implementation belongs in the slice-by-slice development plans, not here.

The exception: some requirements, if implemented the obvious naïve way, are expensive enough that the cost would be prohibitive. In those cases the requirement carries an **Implementation notes** section at the bottom of the doc that sketches an efficient approach — enough guidance that the implementer knows the feature is realistic and roughly how to get there.

Rules for **Implementation notes** sections when they appear:

- They live at the bottom of the doc, after the spec proper.
- They sketch a known-workable approach, not a binding mandate. An implementer free to find a better way still can.
- They are NOT a substitute for the development plan, which still owns the schedule and the slice-by-slice rollout.
- They are NOT a place to dump random implementation thoughts. If the naïve implementation is fine, no Implementation notes section is needed.

If you're authoring a new requirements doc and you find yourself wanting to add an Implementation notes section, ask first whether the requirement itself could be simplified to avoid the cost. If the cost is real and inherent, then the section earns its place.
