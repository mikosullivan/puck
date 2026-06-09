# V1

~~~vibecode
{"vibecode": {
	"doc": "v1_plan",
	"role": "Puck-wide V1 plan: components in scope, cross-cutting principles, navigation pointer to per-component build plans. Caspian-specific slice progression lives in caspian/index.md; per-component plans land here as they get scoped.",
	"status": "active",
	"feature_lock": "soft",
	"source_of_truth": "vibecode_blocks"
}}
~~~

V1 ships **Puck.uno as a deployable service**. The Puck ecoverse has
several strands — the Caspian engine, the Mikobase store, the Puck
protocol, plus support layers (Touchstone, Sammy, jasmine, jqmin,
Trivet, Uma, Bryton, deployment) — and this page is the umbrella plan
that names which strands ship in V1 and points to each strand's
detailed plan.

Per-strand detail (slice progressions, definition-of-done, test plans)
lives in subdirectories under this one. The first concrete plan is for
the Caspian engine in [caspian/index.md](caspian/index.md).

---

<a id="components"></a>
## Components in V1

~~~vibecode
{"vibecode": {
	"v1_in": ["caspian", "caspian_cli", "mikobase", "touchstone", "sammy",
		"trivet", "uma", "bryton", "jasmine", "puck_identity",
		"deployment", "drinian"],
	"v1_companion_projects": ["caspian_vscode_extension_separate_repo"],
	"v1_out": ["robinson", "caspian_lsp"],
	"v1_blockchain_role": "external_service; caspian_client_is_thin_http",
	"v1_http_path": "sammy_explicit_handlers",
	"v1_authn": "signed_request",
	"v1_authz": "handler_implements_directly; no_declarative_role_policy"
}}
~~~

| Component | Role in V1 | Plan |
|---|---|---|
| **Caspian** + CLI + Drinian | engine, command-line launcher, in-memory runtime state | [caspian/index.md](caspian/index.md) |
| **Mikobase** | live object store | TBD |
| **Touchstone** | shared utility base layer | TBD |
| **Sammy** | HTTP path: explicit handlers | TBD |
| **Trivet** | (component plan TBD) | TBD |
| **Uma** | core component + the real-world program that exercises Caspian at non-trivial scale | TBD |
| **Bryton** | Tier-2 test runner for Caspian-level behavior | covered in caspian/glenstorm.md |
| **jasmine** | (component plan TBD) | TBD |
| **Puck identity** | signed-request authentication scaffolding | TBD |
| **Deployment** | the actual puck.uno service shape | TBD |

### Companion projects (separate repos)

These ship alongside Puck V1 but live in their own GitHub repositories:

| Project | Role | Repo |
|---|---|---|
| **Caspian VSCode extension** (codename Molly) | syntax highlighting + static hover + language config + custom file icon; no LSP, no Caspian-install dependency | spec: [caspian/vscode-extension/](../../caspian/vscode-extension/) · repo: [caspian-vscode](https://github.com/mikosullivan/caspian-vscode) |

**Robinson** (the filesystem-tree page-server) is **not** bundled with
V1; it lands on its own timeline as a Puck-resolved library.

**Caspian LSP** is also deferred to post-V1. Requiring a local Caspian
install for editor tooling conflicts with the first-contact goal and
with remote-development workflows. The VSCode extension ships
syntax-highlighting only for V1; rich LSP features wait until the
install story is robust enough. Spec and build plan are parked at
[ideas/lsp/](../../ideas/lsp/) and [ideas/lsp-build/](../../ideas/lsp-build/).

The HTTP path is Sammy-style explicit handlers (built on Touchstone).
Authentication is signed-request based; authorization is whatever each
handler implements directly. Blockchain is an external service Caspian
talks to via a thin HTTP client.

---

<a id="cross-cutting-principles"></a>
## Cross-cutting principles

~~~vibecode
{"vibecode": {
	"section": "cross_cutting_principles",
	"scope": "puck_wide",
	"principles": ["vibecode_canonical_prose_derivative",
		"each_phase_runnable_end_to_end", "tests_drive_roadmap",
		"soft_feature_lock_with_visible_overrides",
		"inventory_before_implement",
		"minimal_surface_per_slice_not_full_spec_upfront"]
}}
~~~

These apply across every V1 strand. Strand-specific principles live in
each strand's plan (e.g., Caspian's CaspianJ-runtime / roles-from-Aslan
/ Drinian-from-Aslan / C-extension policy live in
[caspian/index.md § Cross-cutting principles](caspian/index.md#cross-cutting-principles)).

- **Vibecode blocks are canonical.** Surrounding prose is derivative.
  When the two disagree, vibecode wins.
- **Each phase ends runnable.** Walking-skeleton development; every
  slice is an end-to-end runnable demo proving a thin band of the stack.
- **Tests drive the roadmap.** What's missing in the next test is what
  gets built next.
- **Soft feature lock.** Anything not specced as V1 is deferred. The
  lock can break — but only deliberately, never casually. Companion
  discipline to `no-bolt-on-additions`.
- **Inventory before implementing.** Never rewrite without
  understanding what's there.
- **Minimal surface per slice.** Each strand's full spec emerges over
  many slices, not as a single upfront effort.

---

<a id="status"></a>
## Status

| Strand | Status |
|---|---|
| Caspian engine | active — current slice: Corin done (2026-05-27); next: Digory |
| Everything else | not yet scoped at this level of detail |

When a new strand's V1 plan gets written, add it to the Components
table above with a link to its plan file.
