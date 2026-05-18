# Documentation issues

~~~json
{"vibecode": {
	"doc": "issues",
	"role": "tracker for contradictions, gaps, and stale references found by a 2026-05-17 four-agent parallel audit of canonical docs and the development plan; 49 issues categorized by severity, mostly resolved with three deferred",
	"key_concepts": ["doc_issue_tracker", "audit_findings", "severity_tags",
		"all_resolved_or_deferred", "design_outcomes_from_audit"]
}}
~~~

Tracker for contradictions, gaps, and stale references found in the
canonical docs and the development plan. Produced 2026-05-17 by a
four-agent parallel audit covering the core Charlie language spec,
the subsystem specs, the ecosystem layer, and the development plan
versus the V0.01 shipped code.

49 issues total, grouped by theme. Severity tags:

- **[BLOCKER]** — fix before V0.02 implementation starts
- **[HIGH]** — fix before V0.03 plan goes live, or before broader work
- **[MEDIUM]** — per-spec cleanups when each area is next touched
- **[LOW]** — gaps and dead pointers; clean up opportunistically

Out of scope for this tracker: anything in `documentation/ideas/`
(deferred / scratch per CLAUDE.md).

---

<a id="status-final-2026-05-17"></a>
## 1 Status (final, 2026-05-17)

**All 49 audit issues resolved or deferred.**

- **Resolved: 46** — see each issue heading below for the per-issue resolution note.
- **Deferred: 3** — issues that touch larger unsettled designs:
  - **#10 (filesystem.md "Authorizing Untrusted Paths" section)** — small inline `untrusted()`/`trusted string` fixes applied; the larger filesystem section needs the role model's filesystem story to settle first.
  - **#14 (operator namespace `charlie.uno` vs `puck.uno`)** — deferred pending operator-registration design pass.
  - **#41 (`scope.operators` namespace)** — entangled with #14; resolved together when operator subsystem is revisited.

Engine + test suite: **213/213 passing** after all changes.

<a id="design-work-that-emerged-from-the-walkthrough"></a>
### 1.1 Design work that emerged from the walkthrough

- **Mikobase v1 engine list expanded to three** (sqlite-file, sqlite-memory, worldlet-direct). The worldlet-direct engine operates on worldlet JSON in place — built for AI2AI conversations where SQLite import/export overhead would dominate.
- **Worldlets reframed as one of (at least) two export formats**, not a kind of mikobase. The second format is TBD.
- **Mikobase overview gained explicit framing**: worldlets are the primary use case, microservices probably want non-temporal too.
- **Exception namespace flattened** (`puck.uno/exception/X` → `puck.uno/X`); umbrella preserved; UNS-no-inheritance principle saved as a memory and noted in canonical spec.
- **`stdlib` role** added to roles.md as enumerated minimum; replaces TBD `string_class_role` in engine.lua.
- **`%role` backfilled** into engine.lua with 6 new tests (213/213 passing).
- **Parameter spec consolidated** into one canonical `parameters.md` (with `optional: true` opt-out, hash-spacing convention, hash-splat style preference).
- **Anonymous (bare) class** form added to charlie.md (`class\n    inherits ... end`), unblocking Robinson pages and per-dir handlers.
- **break bwc spec** landed post-soft-lock with explicit deliberateness log in Scotty section.

<a id="brainstorm-docs-filed-from-the-walkthrough-in-documentationideas"></a>
### 1.2 Brainstorm docs filed from the walkthrough (in `documentation/ideas/`)

- [dogberry.md](ideas/dogberry.md) — transforming-proxy idea (fetch + execute remote scripts).
- [robinson-per-dir-handlers.md](ideas/robinson-per-dir-handlers.md) — `robinson.charlie` per-directory middleware; paused with explicit resume points.
- [browser-charlie-sandbox.md](ideas/browser-charlie-sandbox.md) — three-artifact plan (WASM Lua engine for browser; TS CharlieJSON-engine for community; TS parser already in vscode-extension v2 plans).
- [charlie-as-a-service.md](ideas/charlie-as-a-service.md) — server-side script execution as a service (peer of Dogberry).
- [ai-script-messaging.md](ideas/ai-script-messaging.md) — AIs authoring CharlieJSON directly and exchanging signed executable messages.
- [vscode-extension.md](ideas/vscode-extension.md) — V1 self-contained TypeScript extension spec (formatter + syntax + settings).
- [vscode-extension-v2.md](ideas/vscode-extension-v2.md) — parser-based V2 ambitions, parked.

---

<a id="a-self-introduced-this-session-fix-first"></a>
## 2 A. Self-introduced this session (fix first)

These were created or amplified by the V0.02 and V0.03 plan work I
added today. Address before the plans go live.

<a id="1-dev-plan-toc-anchors-are-broken-for-every-h2-blocker-resolved-2026-05-17"></a>
### 2.1 1. Dev plan TOC anchors are broken for every H2 [BLOCKER] [RESOLVED 2026-05-17]

**File:** [documentation/development/development.md:16-92](documentation/development/development.md#L16-L92)

GitHub generates heading anchors from the full heading text including
the Star Trek nicknames. The TOC says `#v001-hello-world`; the real
anchor is `#v001-hello-world-kirk`. Every H2 link in the Spock TOC
fails. Suggestion: regenerate the TOC with nickname-suffixed anchors,
or strip nicknames from anchors via explicit `<a name="...">` tags.

<a id="2-v003-t32-contradicts-its-own-open-question-high-resolved-2026-05-17"></a>
### 2.2 2. V0.03 T3.2 contradicts its own open question [HIGH] [RESOLVED 2026-05-17]

**Files:** [development.md:2284-2289, 2366](documentation/development/development.md)

Test asserts `engine.bwcs.puts is a function`. The open question at
~2284 says the storage shape (function vs `{fn, owning_role}` table)
is "to be decided during implementation." The test commits to one
shape while the spec says it's undecided. Suggestion: pick the shape
in Step 2 before the test exists.

<a id="3-sulu-roadmap-vs-sarek-cli-position-disagree-high-resolved-2026-05-17"></a>
### 2.3 3. Sulu roadmap vs Sarek CLI position disagree [HIGH] [RESOLVED 2026-05-17]

**Files:** [development.md:617, 2436-2437](documentation/development/development.md)

Sulu now lists CLI after V0.05; Sarek still says "after V0.02, before
V0.1." Suggestion: pick one — Sarek's "after V0.02" predates the
V0.03-V0.05 split.

<a id="4-v00x-sarek-lists-stdoutstderr-separation-as-new-high-resolved-2026-05-17"></a>
### 2.4 4. V0.0X Sarek lists "stdout/stderr separation" as new [HIGH] [RESOLVED 2026-05-17]

**Files:** [development.md:2459, 2478-2480](documentation/development/development.md)

V0.03 (Janeway) already ships stdout. Sarek's "introduces" list
claims stdout/stderr separation as new in the CLI slice. Suggestion:
rewrite Sarek to drop stdout; frame as "stderr + exit codes + shebang
+ permission flags."

<a id="5-chekov-role-growth-path-skips-v003v004v005-high-resolved-2026-05-17"></a>
### 2.5 5. Chekov role-growth path skips V0.03/V0.04/V0.05 [HIGH] [RESOLVED 2026-05-17]

**File:** [development.md:710-741](documentation/development/development.md#L710-L741)

Jumps from V0.02 to "First HTTP" with no rows for the three slices I
added. Suggestion: add rows for V0.03 (stdout role), V0.04 (hash-class
role), V0.05 (no new role).

---

<a id="b-v001-shipped-vs-promised-gaps"></a>
## 3 B. V0.01 shipped-vs-promised gaps

<a id="6-role-system-method-promised-but-not-shipped-blocker-resolved-2026-05-17"></a>
### 3.1 6. `%role` system method promised but not shipped [BLOCKER] [RESOLVED 2026-05-17]

**Files:** [development.md:686-687, 1522](documentation/development/development.md); [engine.lua](code/charlie/lua/charlie/engine.lua)

V0.01 footprint lists "role_system_method" but engine.lua has no
sys-reference handling. The fixture didn't require it so V0.01
passed. Suggestion: either remove from V0.01 footprint or schedule a
follow-up slice.

<a id="7-string_class_role-is-a-tbd-name-hardcoded-into-shipped-code-test-blocker-resolved-2026-05-17-renamed-to-stdlib"></a>
### 3.2 7. `string_class_role` is a TBD name hardcoded into shipped code + test [BLOCKER] [RESOLVED 2026-05-17 — renamed to `stdlib`]

**Files:** [engine.lua:44](code/charlie/lua/charlie/engine.lua#L44); [test_bootstrap.lua:21](tests/charlie/v001/test_bootstrap.lua#L21); [roles.md:92-124](documentation/charlie/roles.md#L92-L124)

roles.md does not enumerate this role. Plan flags it as "provisional"
but test_bootstrap.lua asserts the exact string. Suggestion: pick a
final name now (or use one of roles.md's named roles like `engine`)
and update both code and test.

<a id="8-testssanity-directory-promised-by-phase-0-not-present-blocker-resolved-2026-05-17-backfilled-with-11-sanity-tests"></a>
### 3.3 8. `tests/sanity/` directory promised by Phase 0 not present [BLOCKER] [RESOLVED 2026-05-17 — backfilled with 11 sanity tests]

**Files:** [development.md:1287-1297, 1418-1430, 1452-1464](documentation/development/development.md); `tests/sanity/` (does not exist)

All six T0.x sanity files (lua_hello, package_path, framework_sanity,
json_parse, file_read) were skipped. Phase 0 acceptance ("all six
pass before Phase 1 begins") was bypassed. Suggestion: either
backfill the six tests or amend the plan to say Phase 0 was skipped
deliberately and why.

---

<a id="c-cross-cutting-issues-multiple-files"></a>
## 4 C. Cross-cutting issues (multiple files)

<a id="9-exceptionerror-class-hierarchy-is-forked-across-7-files-high-resolved-2026-05-17-flattened-to-puckunox-umbrella-puckunoexception-kept"></a>
### 4.1 9. Exception/error class hierarchy is forked across ~7 files [HIGH] [RESOLVED 2026-05-17 — flattened to `puck.uno/X`, umbrella `puck.uno/exception` kept]

**Canonical:** `puck.uno/exception/error/timeout` — [charlie-runtime.md:745-765](documentation/charlie/charlie-runtime.md#L745-L765)

**Diverging shorthand `puck.uno/error/...`:**
- [utils.md:47](documentation/charlie/utils.md#L47)
- [versioning.md:99](documentation/charlie/versioning.md#L99)
- [jasmine.md:311](documentation/charlie/jasmine/jasmine.md#L311)
- [charlie-runtime.md:1792](documentation/charlie/charlie-runtime.md#L1792) (itself)

**Subsystem-minted roots:** `puck.uno/touchstone/error/*`, `puck.uno/robinson/warning/*`, `puck.uno/trivet/error/cycle`

**Also:** [puck/puck.md:363-364](documentation/puck/puck.md#L363-L364) lists `puck.uno/exception` twice as two different classes.

Suggestion: decide on one root, or document the shorthand as sugar.

<a id="10-binary-trust-model-still-leaks-through-despite-rolesmd-superseding-it-high-partial-2026-05-17-small-inline-fixes-applied-charlie-runtimemd-untrusted-role-based-wording-nullsmd-trusted-string-fresh-string-filesystemmd-authorizing-untrusted-paths-section-still-deferred-until-the-role-models-filesystem-story-is-settled"></a>
### 4.2 10. Binary trust model still leaks through despite roles.md superseding it [HIGH] [PARTIAL — 2026-05-17: small inline fixes applied (charlie-runtime.md `untrusted()` → role-based wording; nulls.md "trusted string" → "fresh string"); filesystem.md "Authorizing Untrusted Paths" section still deferred until the role model's filesystem story is settled]

**Files:**
- `untrusted()` referenced as real construct — [charlie-runtime.md:822, 826](documentation/charlie/charlie-runtime.md#L822-L826)
- `%chain.trust` analogues — [filesystem.md:295-362](documentation/charlie/built-in-classes/filesystem.md#L295-L362)
- "trusted string" vocabulary — [nulls.md:430-432](documentation/charlie/built-in-classes/nulls.md#L430-L432)

roles.md explicitly retires all of this. Suggestion: rewrite affected
sections in role terms, or remove if the concept doesn't survive
translation.

<a id="11-worldlet-format-is-forked-three-ways-high-resolved-2026-05-17-mikobases-and-worldlets-carry-a-top-level-temporal-flag-default-is-temporal-non-temporal-requires-explicit-temporal-false-worldletmd-describes-the-non-temporal-shape-ai-conversation-formatmd-describes-the-temporal-shape-mikobasemd-documents-the-flag-itself-mixed-mode-databases-left-undecided"></a>
### 4.3 11. Worldlet format is forked three ways [HIGH] [RESOLVED 2026-05-17 — mikobases (and worldlets) carry a top-level `"temporal"` flag; default is temporal, non-temporal requires explicit `"temporal": false`; worldlet.md describes the non-temporal shape, ai-conversation-format.md describes the temporal shape, mikobase.md documents the flag itself; mixed-mode databases left undecided]

**Files:**
- [worldlet.md:54](documentation/mikobase/worldlets/worldlet.md#L54): "worldlets are non-temporal, no history key"
- [ai-conversation-format.md:210-236](documentation/mikobase/ai-conversation-format.md#L210-L236): "history is the only required top-level key"
- [mikobase.md:294-311](documentation/mikobase/mikobase.md#L294-L311): HTTP endpoint accepts worldlet whose body is a history block

Three docs, three shapes. Suggestion: pick one canonical worldlet
shape and reconcile across all three docs, including the HTTP
endpoint contract.

<a id="12-updated_at-vs-created_at-for-the-same-per-version-field-high-resolved-2026-05-17-temporal-mode-history-rows-use-updated_at-record-was-updated-at-this-time-non-temporal-mode-records-use-created_at-the-current-state-was-created-at-this-time-ai-conversation-formatmd-renamed-history-fields-created_at-updated_at-metacreated_at-export-timestamp-preserved-worldletmd-non-temporal-records-keep-created_at-sqlite-schemamds-temporal-history-table-keeps-updated_at-mikobasemd-examples-updated"></a>
### 4.4 12. `updated_at` vs `created_at` for the same per-version field [HIGH] [RESOLVED 2026-05-17 — temporal-mode history rows use `updated_at` (record was updated at this time); non-temporal-mode records use `created_at` (the current state was created at this time). ai-conversation-format.md renamed (history fields `created_at` → `updated_at`; `meta.created_at` export-timestamp preserved); worldlet.md non-temporal records keep `created_at`; sqlite-schema.md's temporal history table keeps `updated_at`; mikobase.md examples updated.]

**Files:**
- `updated_at` — [sqlite-schema.md:50, 55, 197](documentation/mikobase/sqlite-schema.md); [requirements.md:228, 374](documentation/mikobase/requirements.md)
- `created_at` — [worldlet.md:304, 313, 538-564](documentation/mikobase/worldlets/worldlet.md); [ai-conversation-format.md:48, 306, 315](documentation/mikobase/ai-conversation-format.md)

A worldlet round-tripped through the SQLite engine loses or renames
the timestamp. Suggestion: pick one — `created_at` reads cleaner for
an append-only history row.

<a id="13-parameter-spec-is-forked-high-resolved-2026-05-17-merged-into-one-canonical-parametersmd-combining-metadata-as-hash-programmatic-api-classes-nullable-freezing-from-old-parametersmd-with-call-binding-public-names-argsopts-splats-errors-from-old-paramsmd-optional-true-chosen-as-the-opt-out-lazy-true-spacing-locked-paramsmd-deleted-charlie-runtimemd-callout-updated"></a>
### 4.5 13. Parameter spec is forked [HIGH] [RESOLVED 2026-05-17 — merged into one canonical parameters.md combining metadata-as-hash + programmatic API + classes + nullable + freezing (from old parameters.md) with call binding + public names + `*args`/`**opts` + splats + errors (from old params.md); `optional: true` chosen as the opt-out; `lazy: true` spacing locked; params.md deleted; charlie-runtime.md callout updated]

**Files:** [parameters.md](documentation/charlie/parameters.md), [params.md](documentation/charlie/params.md); [charlie-runtime.md:1456-1459](documentation/charlie/charlie-runtime.md#L1456-L1459)

Two parameter spec docs cover overlapping ground with divergent
conventions: `lazy:true` syntax, nullable/classes/default vs
public/optional/`*args`/`**opts`. The runtime spec explicitly flags
the fork: "two parameter spec docs exist… Reconciling them is a
separate task." Suggestion: merge into one canonical doc; move the
other to `ideas/`.

<a id="14-operator-namespace-inconsistent-charlieuno-vs-puckuno-high"></a>
### 4.6 14. Operator namespace inconsistent: `charlie.uno/` vs `puck.uno/` [HIGH]

**Files:**
- `charlie.uno/...` — [operators.md:66ff](documentation/charlie/operators.md#L66), [assignment-operators.md:78ff](documentation/charlie/assignment-operators.md#L78)
- `puck.uno/...` (the rest of the stdlib) — [parameters.md:134](documentation/charlie/parameters.md#L134), [charlie-runtime.md](documentation/charlie/charlie-runtime.md)

`charlie.uno/` is never defined as a separate namespace. Suggestion:
unify on `puck.uno/`.

---

<a id="d-hard-contradictions-inside-single-language-docs"></a>
## 5 D. Hard contradictions inside single language docs

<a id="15-class-method-definition-function-name-vs-function-name-medium-resolved-2026-05-17-function-nameargs-end-with-the-sigil-and-no-do-keyword-applied-across-charlie-runtimemd-class-method-examples-and-prose-charliemd-definition-section-examples-updated-to-drop-the-do-scope-summary-table-updated"></a>
### 5.1 15. Class-method definition: `function name()` vs `function &name()` [MEDIUM] [RESOLVED 2026-05-17 — `function &name($args) ... end` with the `&` sigil and no `do` keyword. Applied across charlie-runtime.md class-method examples and prose; charlie.md "Definition" section examples updated to drop the `do`; scope summary table updated.]

**Files:**
- `&` sigil form — [charlie.md:553, 624](documentation/charlie/charlie.md), class-definition.md
- Bare form — [charlie-runtime.md:1900, 1914, 2029-2084](documentation/charlie/charlie-runtime.md)

Pick one; the `&` form is consistent with the rest of charlie.md's
"function vs &function" rule.

<a id="16-property-syntax-nickname-vs-foo-get-set-defaultbar-medium-resolved-2026-05-17-canonical-form-property-foo-get-set-sigil-prefixed-name-accessor-flags-charliemd-updated-to-use-sigil-form-charlie-runtimemd-kept-the-form-but-default-option-dropped-for-v1-deferred-mechanics-noted-in-both-docs-the-accessors-readwrite-bucketname"></a>
### 5.2 16. `property` syntax: `:nickname` vs `@foo, :get, :set, default:'bar'` [MEDIUM] [RESOLVED 2026-05-17 — canonical form: `property @foo, :get, :set` (sigil-prefixed name + accessor flags). charlie.md updated to use sigil form; charlie-runtime.md kept the form but `default:` option dropped for v1 (deferred). Mechanics noted in both docs: the accessors read/write `%bucket['<name>']`.]

**Files:** [charlie.md:591](documentation/charlie/charlie.md#L591), [charlie-runtime.md:2005-2010](documentation/charlie/charlie-runtime.md#L2005-L2010)

Two different first-argument shapes for the same construct.
Suggestion: reconcile in one place and reference from the other.

<a id="17-pipe-semantics-first-positional-arg-vs-first-and-only-arg-medium-resolved-2026-05-17-first-positional-wins-charliemd-pipesmd-updated-the-piped-value-occupies-the-first-positional-slot-additional-positionalnamed-args-at-the-call-site-bind-normally-matches-elixirfr-conventions"></a>
### 5.3 17. Pipe semantics: "first positional arg" vs "first and only arg" [MEDIUM] [RESOLVED 2026-05-17 — first-positional wins (charlie.md). pipes.md updated: the piped value occupies the first positional slot; additional positional/named args at the call site bind normally. Matches Elixir/F#/R conventions.]

**Files:** [charlie.md:758](documentation/charlie/charlie.md#L758), [pipes.md:33, 38-42](documentation/charlie/pipes.md#L33-L42)

charlie.md allows other args; pipes.md forbids them and desugars
`a | b` to `b(a)` only. Suggestion: pick one; the charlie.md form
is more general.

<a id="18-charliemd-self-conflict-function-with-do-for-definitions-medium-resolved-2026-05-17-resolved-alongside-15-definition-examples-no-longer-use-do-the-no-do-for-definitions-rule-at-charliemd271-now-matches-the-examples"></a>
### 5.4 18. charlie.md self-conflict: `function`-with-`do` for definitions [MEDIUM] [RESOLVED 2026-05-17 — resolved alongside #15. Definition examples no longer use `do`; the "No `do` for definitions" rule at charlie.md:271 now matches the examples.]

**File:** [charlie.md:271 vs 441-461](documentation/charlie/charlie.md)

"No `do` for definitions" at line 271 vs every function/closure
definition example using `function(...) do ... end`. Suggestion:
clarify whether the form is a call (explains the `do`) or a
definition (forbids it).

<a id="19-charliejson-core-principle-broken-by-its-own-ifwhile-form-medium-resolved-2026-05-17-prose-fix-only-no-shape-changes-core-principle-section-rewritten-to-acknowledge-two-receiver-shapes-value-receivers-take-receiver-method-args-bwc-receivers-take-bwc-args-the-bwc-name-is-the-call-no-method-slot-v001-engine-already-runs-the-bwc-shape-as-is-no-code-change-needed"></a>
### 5.5 19. CharlieJSON core principle broken by its own `if`/`while` form [MEDIUM] [RESOLVED 2026-05-17 — prose fix only, no shape changes. Core Principle section rewritten to acknowledge two receiver shapes: value receivers take `[receiver, method, args?]`; bwc receivers take `[{bwc}, args?]` (the bwc name IS the call, no method slot). V0.01 engine already runs the bwc shape as-is, no code change needed.]

**File:** [charliejson.md:42 vs 267-301](documentation/charlie/charliejson.md)

Core principle: every statement is `[receiver, method, args?]`.
`if` and `while` are encoded as `[{bwc:...}, {...}]` — two-element
forms with no method slot. Suggestion: either add an explicit method
for symmetry, or revise the core principle to note bwc statements may
omit the method slot.

<a id="20-blocks-system-method-listed-but-never-defined-medium-resolved-2026-05-17-dropped-blocks-from-system-methodsmd-table-row-vibecode-list-callblocks-remains-the-canonical-access-pattern-documented-in-charlie-runtimemd-a-future-shortcut-can-be-added-deliberately-as-sugar-with-documented-sugaring-rules-not-as-a-parallel-spec"></a>
### 5.6 20. `%blocks` system method listed but never defined [MEDIUM] [RESOLVED 2026-05-17 — dropped `%blocks` from system-methods.md (table row + vibecode list). `%call.blocks` remains the canonical access pattern documented in charlie-runtime.md. A future shortcut can be added deliberately as sugar with documented sugaring rules, not as a parallel spec.]

**Files:** [system-methods.md:37](documentation/charlie/system-methods.md#L37), [charlie-runtime.md:2118, 2467](documentation/charlie/charlie-runtime.md)

Only `%call.blocks` is defined; `%blocks` is listed in the top-level
system methods table. Suggestion: drop `%blocks` from the table or
define it as a shortcut.

<a id="21-trilean-primitive-vs-boolean-medium-resolved-2026-05-17-boolean-is-the-core-primitive-trilean-was-an-idea-for-three-valued-logic-not-core-system-methodsmd-utilsjsonparse-description-updated-trilean-boolean-trileanmd-moved-from-documentationcharliebuilt-in-classes-to-documentationideas-with-a-status-banner"></a>
### 5.7 21. `trilean` primitive vs `boolean` [MEDIUM] [RESOLVED 2026-05-17 — `boolean` is the core primitive; `trilean` was an idea for three-valued logic, not core. system-methods.md `%utils.json.parse` description updated (trilean → boolean); `trilean.md` moved from `documentation/charlie/built-in-classes/` to `documentation/ideas/` with a status banner.]

**Files:** [charlie-runtime.md:422](documentation/charlie/charlie-runtime.md#L422), [system-methods.md:326](documentation/charlie/system-methods.md#L326), [trilean.md](documentation/charlie/built-in-classes/trilean.md)

Runtime declares Boolean as primitive; `%utils.json.parse` is
described as returning "trilean." `trilean.md` exists in
built-in-classes; nothing in the core declares a three-valued logic.
Suggestion: rename to `boolean`, or introduce trilean explicitly with
a defined logic system.

---

<a id="e-subsystem-vs-subsystem-and-dead-references"></a>
## 6 E. Subsystem-vs-subsystem and dead references

<a id="22-brytonxeme-disagree-on-runner-error-class-prefix-medium-resolved-2026-05-17-honored-xememds-own-working-convention-at-line-479-480-uns-style-identifier-without-domain-prefix-replaced-puckunoresultfailureruntime-brytonruntime-and-puckunoresultnull-brytonnull-in-xememd-runnermd-was-already-consistent-the-runtime-middle-segment-is-reserved-for-runner-level-failures-test-missing-crashed-timeout-unparseable-exception-test-payload-failures-like-assertion-or-connection_refused-live-under-bryton-directly-without-runtime"></a>
### 6.1 22. Bryton/Xeme disagree on runner-error class prefix [MEDIUM] [RESOLVED 2026-05-17 — honored xeme.md's own working convention at line 479-480 (UNS-style identifier without domain prefix). Replaced `puck.uno/result/failure/runtime/*` → `bryton/runtime/*` and `puck.uno/result/null/*` → `bryton/null/*` in xeme.md. runner.md was already consistent. The `runtime/` middle segment is reserved for runner-level failures (test missing, crashed, timeout, unparseable, exception); test-payload failures like assertion or connection_refused live under `bryton/` directly without `runtime/`.]

**Files:** [runner.md:440-444](documentation/charlie/bryton/runner.md#L440-L444), [xeme.md:808, 823](documentation/charlie/bryton/xeme/xeme.md)

runner.md: `class: "bryton/runtime/missing"`. xeme.md: same concept
uses `puck.uno/result/failure/runtime/crashed`. Suggestion: pick one
prefix for `errors[].class` and propagate.

<a id="23-xememd-promised-jasmine-will-be-flattened-to-this-shape-it-wasnt-medium-resolved-2026-05-17-soften-not-apply-the-jasmine-flattening-alignment-in-xememd-is-now-labeled-proposed-not-yet-applied-with-an-explicit-pointer-to-jasminemd-as-the-current-canonical-shape-the-actual-flattening-of-jasminemd-is-deferred-substantial-rewrite-the-spec-is-at-least-honest-about-current-state"></a>
### 6.2 23. xeme.md promised "Jasmine will be flattened to this shape." It wasn't. [MEDIUM] [RESOLVED 2026-05-17 — soften, not apply. The Jasmine-flattening alignment in xeme.md is now labeled "proposed, not yet applied" with an explicit pointer to jasmine.md as the current canonical shape. The actual flattening of jasmine.md is deferred (substantial rewrite); the spec is at least honest about current state.]

**Files:** [xeme.md:503-547](documentation/charlie/bryton/xeme/xeme.md#L503-L547), [jasmine.md:411-468](documentation/charlie/jasmine/jasmine.md#L411-L468)

xeme.md describes a flat target; jasmine.md still has the nested
`calls + {function, entry}` shape. Suggestion: either update Jasmine
to the flattened shape or back the proposal out of xeme.md.

<a id="24-jasminemd-still-describes-itself-as-for-the-robinson-handler-in-dogberry-medium-resolved-2026-05-17-rewritten-to-originally-motivated-by-robinson-with-an-explicit-parenthetical-noting-robinson-and-dogberry-are-independent-http-middleware-peers-stale-link-to-dogberry-wishlistmd-replaced-with-link-to-the-current-ideasdogberrymd"></a>
### 6.3 24. jasmine.md still describes itself as "for the Robinson handler in Dogberry" [MEDIUM] [RESOLVED 2026-05-17 — rewritten to "originally motivated by Robinson" with an explicit parenthetical noting Robinson and Dogberry are independent HTTP middleware peers. Stale link to dogberry-wishlist.md replaced with link to the current ideas/dogberry.md.]

**Files:** [jasmine.md:26-28](documentation/charlie/jasmine/jasmine.md#L26-L28); http-middleware.md, dogberry.md (which retire this framing)

Also matches the memory note: Dogberry is undefined. Suggestion:
update jasmine.md's framing to drop the retired association.

<a id="25-chainlog-treated-as-engine-granted-ambient-missing-from-system-methodsmd-medium-resolved-2026-05-17-extended-the-chain-row-in-system-methodsmd-to-enumerate-engine-installed-methods-on-chain-flag-raising-chainwarnthrowerrorexitabort-pointer-to-charlie-runtimemd-and-logging-chainlog-pointer-to-jasminemd-jasminemds-usage-is-now-backed-by-an-explicit-mention-in-the-system-methods-spec"></a>
### 6.4 25. `%chain.log` treated as engine-granted ambient, missing from system-methods.md [MEDIUM] [RESOLVED 2026-05-17 — extended the `%chain` row in system-methods.md to enumerate engine-installed methods on `%chain`: flag-raising (`%chain.warn`/`throw`/`error`/`exit`/`abort`, pointer to charlie-runtime.md) and logging (`%chain.log`, pointer to jasmine.md). jasmine.md's usage is now backed by an explicit mention in the system-methods spec.]

**Files:** [jasmine.md:218-241](documentation/charlie/jasmine/jasmine.md#L218-L241) vs [system-methods.md:20-26](documentation/charlie/system-methods.md)

jasmine.md treats `%chain.log` as always-present, engine-configured.
system-methods.md doesn't list it. User code can't define new
`%`-prefixed methods, so jasmine.md depends on a core surface not
declared in core. Suggestion: add `%chain.log` to system-methods.md
or revise jasmine.md to use a non-system-method mechanism.

<a id="26-robinson-page-class-with-no-uns-uses-a-class-decl-form-charliemd-doesnt-define-medium-resolved-2026-05-17-added-an-anonymous-bare-class-subsection-to-charliemd-after-the-definition-section-class-end-with-no-uns-produces-an-anonymous-class-its-identity-comes-from-its-locationcontext-robinson-pages-per-dir-handlers-inherits-and-other-declarations-work-identically"></a>
### 6.5 26. Robinson "page = class with no UNS" uses a class-decl form charlie.md doesn't define [MEDIUM] [RESOLVED 2026-05-17 — added an "Anonymous (bare) class" subsection to charlie.md after the Definition section. `class ... end` with no UNS produces an anonymous class; its identity comes from its location/context (Robinson pages, per-dir handlers). `inherits` and other declarations work identically.]

**Files:** [robinson.md:270-284](documentation/charlie/http-middleware/robinson.md#L270-L284), [charlie.md:543-557](documentation/charlie/charlie.md#L543-L557)

charlie.md defines `class 'UNS' ... end`; no bare/anonymous form.
Robinson depends on a syntax variant the core doesn't define.
Suggestion: either define the bare-class form in charlie.md or change
Robinson's page declaration to use a synthetic UNS derived from path.

<a id="27-fso-filesystem-object-used-in-touchstonemd-without-a-definition-low-resolved-2026-05-17-defined-fso-in-touchstonemd-at-first-use-an-engine-configured-object-that-can-accept-byte-writes-for-storage-in-v1-a-dirjail-per-filesystemmd-leaves-room-for-non-filesystem-backings-later-without-changing-the-handler-contract"></a>
### 6.6 27. "FSO (filesystem object)" used in touchstone.md without a definition [LOW] [RESOLVED 2026-05-17 — defined FSO in touchstone.md at first use: "an engine-configured object that can accept byte writes for storage; in v1, a dirjail (per filesystem.md)." Leaves room for non-filesystem backings later without changing the handler contract.]

**File:** [touchstone.md:199, 294-326](documentation/charlie/http-middleware/touchstone.md)

The term doesn't appear in filesystem.md (which uses "jail / file
object / directory object") or any other doc. Suggestion: define FSO,
or rename to the existing terminology.

<a id="28-touchstonemdsinatramd-mutate-responsecsp-etc-before-any-response-exists-medium-resolved-2026-05-17-reframed-transactionresponse-as-starts-at-null-but-auto-creates-on-first-write-writes-to-cspheadersstatusbody-instantiate-an-empty-response-on-the-spot-the-cspheader-examples-in-touchstonemd-and-sinatramd-auto-options-now-have-coherent-semantics-the-null-no-handler-wrote-anything-fallback-fires-rule-is-preserved"></a>
### 6.7 28. touchstone.md/sinatra.md mutate `$response.csp` etc. before any `$response` exists [MEDIUM] [RESOLVED 2026-05-17 — reframed `$transaction.response` as "starts at null but auto-creates on first write": writes to `csp`/`headers`/`status`/`body` instantiate an empty response on the spot. The CSP/header examples in touchstone.md and sinatra.md (auto-OPTIONS) now have coherent semantics. The "null = no handler wrote anything → fallback fires" rule is preserved.]

**Files:** [touchstone.md:60-61, 766-792](documentation/charlie/http-middleware/touchstone.md); [sinatra.md:304-310](documentation/charlie/http-middleware/sinatra.md#L304-L310)

touchstone.md says `$response` starts at null and is built by stage
2. Then handlers write into `$response.csp[...]` and
`$response.headers[...]` as if it always exists. Suggestion:
reconcile the "starts at null" model with the per-transaction
mutable-response usage.

<a id="29-uma-referenced-by-robinson-and-trivet-no-uma-spec-in-canonical-tree-medium-resolved-2026-05-17-added-explicit-pointers-in-robinsonmd-requestuma-section-and-trivetmd-the-inline-mention-noting-uma-is-currently-in-documentationideasumaumamd-not-yet-promoted-to-canonical-and-that-uma-must-be-canonical-before-robinson-can-be-implemented-honest-about-state-actual-uma-promotion-deferred-as-substantial-separate-work"></a>
### 6.8 29. Uma referenced by Robinson and Trivet, no Uma spec in canonical tree [MEDIUM] [RESOLVED 2026-05-17 — added explicit pointers in robinson.md (`$request.uma` section) and trivet.md (the inline mention) noting Uma is currently in `documentation/ideas/uma/uma.md`, not yet promoted to canonical, and that Uma must be canonical before Robinson can be implemented. Honest about state; actual Uma promotion deferred as substantial separate work.]

**Files:** [robinson.md:561-624](documentation/charlie/http-middleware/robinson.md), [trivet.md:7, 651, 691](documentation/charlie/trivet/trivet.md)

Only Uma spec lives in `documentation/ideas/uma/uma.md` (out of
scope). Suggestion: promote a minimal Uma spec into canonical
`documentation/charlie/uma/` before Robinson/Trivet work proceeds.

---

<a id="f-ecosystem-repo-accuracy"></a>
## 7 F. Ecosystem / repo accuracy

<a id="30-readme-overview-promise-python-mikobase-engine-that-doesnt-exist-medium-resolved-2026-05-17-readmemd-repo-layout-row-rewritten-to-reflect-actual-state-charlie-lua-engine-shipped-mikobasepuckdogberry-placeholders-overviewmd-status-table-rewritten-removed-python-mikobase-references-added-rows-for-charlie-lua-reference-engine-v001-shipped-213-tests-passing-and-the-three-planned-mikobase-engines-sqlite-file-sqlite-memory-worldlet-direct"></a>
### 7.1 30. README + overview promise Python Mikobase engine that doesn't exist [MEDIUM] [RESOLVED 2026-05-17 — README.md repo-layout row rewritten to reflect actual state (Charlie Lua engine shipped; Mikobase/Puck/Dogberry placeholders). overview.md status table rewritten: removed Python Mikobase references; added rows for Charlie Lua reference engine (V0.01 shipped, 213 tests passing) and the three planned Mikobase engines (SQLite file, SQLite memory, worldlet-direct).]

**Files:** [README.md:25](README.md#L25), [overview.md:99-107](documentation/overview.md#L99-L107); [code/mikobase/](code/mikobase/) (empty)

CLAUDE.md confirms V0.01 walking-skeleton target is the Lua Charlie
engine, not Python Mikobase. Suggestion: update README and overview
to reflect current state; mark Mikobase engine as design only.

<a id="31-pucklower-examples-violate-immutability-stated-50-lines-later-medium-resolved-2026-05-17-dropped-the-assignment-examples-that-violated-the-immutability-rule-replaced-with-a-read-only-property-framing-properties-can-be-read-x-puckupper-assignment-raises-pointed-to-deriving-a-narrower-puck-and-restrict-doend-as-the-canonical-ways-to-narrow-the-window"></a>
### 7.2 31. `%puck.lower = ...` examples violate immutability stated 50 lines later [MEDIUM] [RESOLVED 2026-05-17 — dropped the assignment examples that violated the immutability rule. Replaced with a read-only-property framing: properties can be read (`$x = %puck.upper`); assignment raises. Pointed to "Deriving a Narrower Puck" and `restrict do...end` as the canonical ways to narrow the window.]

**File:** [puck/puck.md:135-138, 184-194 vs 147-149](documentation/puck/puck.md)

Both properties are described as "immutable once the puck exists"
right after assignment examples. Suggestion: drop the assignment
examples since they directly violate the immutability rule.

<a id="32-puck-propagation-undefined-at-role-boundaries-medium-resolved-2026-05-17-added-a-clarifying-paragraph-to-the-early-puck-section-the-engine-decides-what-puck-if-any-populates-each-role-boundary-this-reconciles-the-two-earlier-statements-wiped-at-role-boundaries-early-engine-controls-later-both-are-per-role-boundary-not-globally-contradictory"></a>
### 7.3 32. `%puck` propagation undefined at role boundaries [MEDIUM] [RESOLVED 2026-05-17 — added a clarifying paragraph to the early `%puck` section: the engine decides what puck (if any) populates each role boundary. This reconciles the two earlier statements ("wiped at role boundaries" early; "engine controls" later) — both are per-role-boundary, not globally contradictory.]

**File:** [puck/puck.md:35-38 vs 268-282](documentation/puck/puck.md)

Lines 35-38: "wiped at role boundaries, returns null when no puck
in `%chain`." Lines 268-282: "engine controls; universally
available." Suggestion: decide explicitly — the role-crossing case
is the common one.

<a id="33-vibecode-reserved-field-count-off-by-one-low-resolved-2026-05-17-all-three-reserved-fields-all-four-reserved-fields-vibecode-comment-misc-corporate-field-later-renamed-from-enterprise-to-corporate-on-2026-05-18"></a>
### 7.4 33. Vibecode reserved-field count off by one [LOW] [RESOLVED 2026-05-17 — "All three reserved fields" → "All four reserved fields (`vibecode`, `comment`, `misc`, `corporate`)". (Field later renamed from `enterprise` to `corporate` on 2026-05-18.)]

**File:** [vibecode.md:1-3, 247-267, 203](documentation/ecoverse/vibecode.md)

Introduces FOUR reserved keys (`vibecode`, `comment`, `misc`,
`corporate`); line 203 says "all three reserved fields are always
passed through." Suggestion: fix "three" → "four."

<a id="34-memory-note-says-signingmd-blockchainmd-file-isnt-at-the-new-location-low-resolved-2026-05-17-moved-documentationcharlieblockchainblockchainmd-documentationblockchainmd-updated-three-external-link-references-versioningmd-2-bindingsmd-puckmd-the-blockchain-server-infrastructure-dockerfile-blockchainjson-scripts-nginxconf-flytoml-lua-is-still-under-documentationcharlieblockchain-flagged-as-needing-a-separate-restructure-since-its-codeinfra-not-docs"></a>
### 7.5 34. Memory note says signing.md → blockchain.md; file isn't at the new location [LOW] [RESOLVED 2026-05-17 — moved `documentation/charlie/blockchain/blockchain.md` → `documentation/blockchain.md`. Updated three external link references (versioning.md ×2, bindings.md, puck.md). The blockchain SERVER infrastructure (Dockerfile, blockchain.json, scripts, nginx.conf, fly.toml, lua/) is still under `documentation/charlie/blockchain/` — flagged as needing a separate restructure since it's code/infra, not docs.]

**Files:** `documentation/blockchain.md` (does not exist); [documentation/charlie/blockchain/blockchain.md](documentation/charlie/blockchain/blockchain.md) (does exist)

Either move the file as the memory note says, or update the memory.

<a id="35-puckunovibcode-typo-missing-e-low-resolved-2026-05-17-fixed-in-puck-htmlmd-and-json-htmljsonhtml-via-global-sed-issuesmd-retains-the-typo-in-the-audit-finding-context-for-historical-reference"></a>
### 7.6 35. `puck.uno/vibcode` typo (missing 'e') [LOW] [RESOLVED 2026-05-17 — fixed in puck-html.md and json-html/json.html via global sed. issues.md retains the typo in the audit-finding context for historical reference.]

**Files:** [puck-html.md:26, 39](documentation/puck/puck-html.md), json.html:16

Every other doc uses "vibecode." Suggestion: fix typo before
`puck.uno` is live (it will become a real addressable UNS).

<a id="36-dogberry-described-in-implementation-detail-in-json-urlsmd-medium-resolved-2026-05-17-replaced-the-implementation-detail-dogberry-support-section-in-json-urlsmd-with-a-tbd-when-dogberry-lands-framing-stale-link-to-dogberry-wishlistmd-deleted-file-replaced-with-link-to-ideasdogberrymd-the-current-brainstorm"></a>
### 7.7 36. Dogberry described in implementation detail in json-urls.md [MEDIUM] [RESOLVED 2026-05-17 — replaced the implementation-detail Dogberry-support section in json-urls.md with a "TBD when Dogberry lands" framing. Stale link to `dogberry-wishlist.md` (deleted file) replaced with link to `ideas/dogberry.md` (the current brainstorm).]

**Files:** [puck/json-urls.md:78, 149-156](documentation/puck/json-urls.md)

Project memory explicitly says "Dogberry is undefined" and "do NOT
describe it as role-based access control." json-urls.md:149-156
describes Dogberry's request layer in implementation detail.
Suggestion: demote the Dogberry section to "TBD when Dogberry lands."

---

<a id="g-smaller-gaps-and-dead-pointers"></a>
## 8 G. Smaller gaps and dead pointers

<a id="37-__end__-spec-requirement-not-yet-implemented-with-no-compliant-engine-behavior-stated-low-resolved-2026-05-17-added-compliant-engine-behavior-for-the-unimplemented-state-subsection-to-charliemd-until-implemented-__end__-is-treated-as-an-ordinary-unrecognized-identifier-typically-a-parse-error-not-silently-accepted-or-special-cased"></a>
### 8.1 37. `__END__` "spec requirement; not yet implemented" with no compliant-engine behavior stated [LOW] [RESOLVED 2026-05-17 — added "Compliant-engine behavior for the unimplemented state" subsection to charlie.md: until implemented, `__END__` is treated as an ordinary unrecognized identifier (typically a parse error), not silently accepted or special-cased.]

**File:** [charlie.md:362-414](documentation/charlie/charlie.md)

For a "spec requirement," what happens when an engine sees `__END__`
but doesn't implement it should be stated (silent? error? warning?).

<a id="38-stack-trace-shape-tbd-but-several-specs-depend-on-it-medium-resolved-2026-05-17-stubbed-the-minimum-v1-shape-in-charlie-runtimemd-estack-is-an-array-of-class-method-line-hashes-root-frame-first-engines-may-add-fields-consumers-treat-unknown-fields-as-additive-now-versioningmd-rolesmd-cross-role-trust-and-jasmine-serialization-have-a-concrete-shape-to-anchor-against"></a>
### 8.2 38. Stack-trace shape "TBD" but several specs depend on it [MEDIUM] [RESOLVED 2026-05-17 — stubbed the minimum v1 shape in charlie-runtime.md: `$e.stack` is an array of `{class, method, line}` hashes, root frame first. Engines may add fields; consumers treat unknown fields as additive. Now versioning.md, roles.md cross-role trust, and Jasmine serialization have a concrete shape to anchor against.]

**Files:** [charlie-runtime.md:676-679](documentation/charlie/charlie-runtime.md#L676-L679); [versioning.md:127](documentation/charlie/versioning.md#L127); roles.md cross-role trust mechanics

Suggestion: stub a minimal shape (array of `{class, method, line}`
frames) even if extensions are TBD.

<a id="39-bwcif-branchless-if-undefined-low-resolved-2026-05-17-charliejsonmd-now-states-if-both-branches-and-else-are-absentempty-the-if-is-a-no-op-returning-null-not-an-error"></a>
### 8.3 39. `[{bwc:"if"}, {}]` (branchless `if`) undefined [LOW] [RESOLVED 2026-05-17 — charliejson.md now states: if both `branches` and `else` are absent/empty, the `if` is a no-op returning `null`. Not an error.]

**File:** [charliejson.md:290](documentation/charlie/charliejson.md#L290)

Doc says branches and else are both optional; never says what the
empty form evaluates to.

<a id="40-puckcall-referenced-but-signature-unspecified-medium-resolved-2026-05-17-added-return-value-and-error-model-subsection-to-puckmds-puckcall-section-specifies-the-return-value-shape-and-the-canonical-error-classes-for-the-five-common-failure-modes-target-lookup-failure-puckunoerrornot_found-method-not-found-transport-failure-remote-exception-propagation-authorization-failure-signature-was-already-in-the-section-chain-forwarding-was-already-in-the-section"></a>
### 8.4 40. `%puck.call` referenced but signature unspecified [MEDIUM] [RESOLVED 2026-05-17 — added "Return value and error model" subsection to puck.md's `%puck.call` section. Specifies the return value shape and the canonical error classes for the five common failure modes: target lookup failure (`puck.uno/error/not_found`), method not found, transport failure, remote exception propagation, authorization failure. Signature was already in the section; chain forwarding was already in the section.]

**File:** [charlie.md:505-521](documentation/charlie/charlie.md#L505-L521)

`remote function` delegates to `%puck.call(self, :save, name: name)`.
Neither system-methods.md nor charlie-runtime.md defines `%puck.call`.
The in-scope spec leaves the call signature, error model, and
`%chain` forwarding unspecified.

<a id="41-scopeoperators-namespace-referenced-but-not-specified-low-deferred-2026-05-17-entangled-with-14-operator-namespace-both-questions-touch-operator-registration-design-should-be-resolved-together-when-the-operator-subsystem-is-revisited"></a>
### 8.5 41. `scope.operators` namespace referenced but not specified [LOW] [DEFERRED 2026-05-17 — entangled with #14 (operator namespace). Both questions touch operator-registration design; should be resolved together when the operator subsystem is revisited.]

**Files:** [operators.md:63-70](documentation/charlie/operators.md#L63-L70), [assignment-operators.md:134](documentation/charlie/assignment-operators.md#L134)

Whether `scope` here is `%scope` (the lexical scope) or a different
concept is unspecified. The doc's own open questions confirm it's not
settled.

<a id="42-vibecode-side-field-has-no-documented-consumer-effect-low-resolved-2026-05-17-added-explicit-consumer-effect-of-side-is-tbd-note-to-the-vibecode-row-in-system-methodsmd-the-field-is-recorded-for-future-tooling-no-current-consumer-reads-it-honest-about-state"></a>
### 8.6 42. `%vibecode side` field has no documented consumer effect [LOW] [RESOLVED 2026-05-17 — added explicit "Consumer effect of `side` is TBD" note to the `%vibecode` row in system-methods.md. The field is recorded for future tooling; no current consumer reads it. Honest about state.]

**File:** [system-methods.md:39](documentation/charlie/system-methods.md#L39)

Introduces `side: "target" | "value"` as "attachment intent." No file
says what consumers do with it.

<a id="43-loopsmd-structural-blocks-have-no-grammar-contract-in-core-low-resolved-2026-05-17-added-a-loop-scoped-section-markers-note-to-charlie-runtimemds-core-bwcs-section-beforebetweenafternoloop-are-reserved-keywords-recognized-by-the-lexerparser-consumed-by-the-loop-runner-and-not-valid-outside-loop-bodies-distinguished-from-general-bwcs-to-avoid-mischaracterization"></a>
### 8.7 43. `loops.md` structural blocks have no grammar contract in core [LOW] [RESOLVED 2026-05-17 — added a "Loop-scoped section markers" note to charlie-runtime.md's core bwcs section. `before`/`between`/`after`/`noloop` are reserved keywords recognized by the lexer/parser, consumed by the loop runner, and not valid outside loop bodies. Distinguished from general bwcs to avoid mischaracterization.]

**File:** [loops.md:204-227](documentation/charlie/loops.md#L204-L227); [charlie-runtime.md:533-538](documentation/charlie/charlie-runtime.md) (core bwcs list)

`before` / `between` / `after` / `noloop` are shown in examples but
their lexer/parser contract (reserved bwcs? scoped only inside
loops?) is not defined.

<a id="44-meta-hashmd-self-contradicts-on-per-level-writes-low-resolved-2026-05-17-use-cases-bullet-rewritten-to-match-the-authoritative-writes-section-writes-through-the-meta-hash-always-land-in-the-last-most-specific-layer-per-layer-mutation-requires-writing-to-the-underlying-hash-directly-no-conflicting-wording-remains"></a>
### 8.8 44. `meta-hash.md` self-contradicts on per-level writes [LOW] [RESOLVED 2026-05-17 — Use cases bullet rewritten to match the authoritative "Writes" section: writes through the meta-hash always land in the last (most-specific) layer; per-layer mutation requires writing to the underlying hash directly. No conflicting wording remains.]

**File:** [meta-hash.md:60-77 vs 122-125](documentation/charlie/built-in-classes/meta-hash.md)

"Writes always land in the last hash" vs "writes at a level set just
that level." Suggestion: pick one.

<a id="45-brytonrunnermd128-slob-pattern-link-is-incomplete-low-resolved-2026-05-17-replaced-broken-link-with-italics-a-parenthetical-pointing-at-overviewmd-which-has-the-companion-no-nanny-principle-no-canonical-slob-pattern-doc-exists-phrase-kept-as-inline-italics"></a>
### 8.9 45. `bryton/runner.md:128` "[slob pattern](../../)" link is incomplete [LOW] [RESOLVED 2026-05-17 — replaced broken link with italics + a parenthetical pointing at overview.md (which has the companion "no-nanny" principle). No canonical "slob pattern" doc exists; phrase kept as inline italics.]

**File:** [runner.md:128](documentation/charlie/bryton/runner.md#L128)

Points at the documentation root rather than a specific document
discussing the slob pattern.

<a id="46-vscodesyntaxsyntaxmd-is-zero-bytes-low-resolved-2026-05-17-filled-the-empty-file-with-a-small-pointer-stub-directing-to-the-actual-extension-scaffolding-at-vscodesyntax-the-v1-spec-at-ideasvscode-extensionmd-the-v2-ideas-and-formattermd-the-previously-empty-file-is-now-a-useful-index"></a>
### 8.10 46. `vscode/syntax/syntax.md` is zero bytes [LOW] [RESOLVED 2026-05-17 — filled the empty file with a small pointer stub directing to the actual extension scaffolding at `vscode/syntax/`, the V1 spec at `ideas/vscode-extension.md`, the V2 ideas, and `formatter.md`. The previously empty file is now a useful index.]

**File:** [syntax.md](documentation/charlie/vscode/syntax/syntax.md)

Either planned stub or should be removed; right now it's a dead link
target.

<a id="47-trileanmd370-points-to-nonexistent-codecharliestdlibtrileancharlie-low-resolved-2026-05-17-moot-trileanmd-moved-to-documentationideas-as-a-non-core-idea-see-21-the-dead-reference-inside-is-now-correctly-contextualized-as-what-this-would-look-like-if-implemented"></a>
### 8.11 47. `trilean.md:370` points to nonexistent `code/charlie/stdlib/trilean.charlie` [LOW] [RESOLVED 2026-05-17 — moot; trilean.md moved to `documentation/ideas/` as a non-core idea (see #21). The dead reference inside is now correctly contextualized as "what this would look like if implemented."]

**File:** [trilean.md:370](documentation/charlie/built-in-classes/trilean.md#L370)

The entire stdlib directory is empty. Spec lists this as if it ships
in v1.

<a id="48-bryton-spec-link-path-wrong-in-v01-amanda-vibecode-low-resolved-2026-05-17-fixed-vibecode-paths-documentationbryton-documentationcharliebryton-and-the-prose-brytonoverviewmdoverviewmd-link-which-was-resolving-to-the-wrong-file-project-overview-now-correctly-points-to-charliebrytonoverviewmd"></a>
### 8.12 48. Bryton spec link path wrong in V0.1 Amanda vibecode [LOW] [RESOLVED 2026-05-17 — fixed vibecode paths (`documentation/bryton/...` → `documentation/charlie/bryton/...`) and the prose `[bryton/overview.md](../overview.md)` link which was resolving to the wrong file (project overview); now correctly points to `../charlie/bryton/overview.md`.]

**File:** [development.md:2674-2676, 2680-2681](documentation/development/development.md)

Vibecode paths point at `documentation/bryton/...`; real path is
`documentation/charlie/bryton/...`. Prose link `[bryton/overview.md](../overview.md)`
resolves to `documentation/overview.md` (which exists but is the
project overview, not Bryton's).

<a id="49-hardcoded-homemikoprojectsmikobaseworkingbin-in-v00x-cli-pseudocode-low-resolved-2026-05-17-replaced-hardcoded-developer-specific-homemikoprojectsmikobaseworkingbin-with-generic-pathtopuckworkingbin-an-inline-replace-with-your-local-checkout-path-comment"></a>
### 8.13 49. Hardcoded `/home/miko/projects/mikobase/working/bin` in V0.0X CLI pseudocode [LOW] [RESOLVED 2026-05-17 — replaced hardcoded developer-specific `/home/miko/projects/mikobase/working/bin` with generic `/path/to/puck/working/bin` + an inline "replace with your local checkout path" comment.]

**File:** [development.md:2576](documentation/development/development.md#L2576)

Repo lives at `/home/miko/projects/puck/working/`. CLAUDE.md
acknowledges the historical `mikobase` directory name but this is a
copy/paste from a developer's actual rc file.

---

<a id="priority-cheat-sheet"></a>
## 9 Priority cheat sheet

**Before V0.02 implementation starts (BLOCKER):**
~~#1 (broken TOC), #6 (missing `%role`), #7 (`string_class_role` TBD),
#8 (missing `tests/sanity/`)~~ — all resolved 2026-05-17.

**Before V0.03 plan goes live (HIGH within the plan):**
~~#2 (T3.2 vs open question), #3 (Sulu vs Sarek position), #4 (Sarek
stdout duplication), #5 (Chekov role growth missing rows)~~ — all
resolved 2026-05-17.

**Spec reconciliation pass (HIGH cross-cutting):** all resolved
except #10's filesystem.md piece (still deferred — see Status above)
and #14 (deferred together with #41).

**Per-spec cleanups (MEDIUM/LOW):** all resolved.

**Currently outstanding work:** only #10 (filesystem section), #14
(operator namespace), and #41 (scope.operators) — all three deferred
pending larger design passes.
