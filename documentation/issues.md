# Documentation issues

Tracker for contradictions, gaps, and stale references found in the
canonical docs and the development plan. Produced 2026-05-17 by a
four-agent parallel audit covering the core KScript language spec,
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

## A. Self-introduced this session (fix first)

These were created or amplified by the V0.02 and V0.03 plan work I
added today. Address before the plans go live.

### 1. Dev plan TOC anchors are broken for every H2 [BLOCKER]

**File:** [documentation/development/development.md:16-92](documentation/development/development.md#L16-L92)

GitHub generates heading anchors from the full heading text including
the Star Trek nicknames. The TOC says `#v001-hello-world`; the real
anchor is `#v001-hello-world-kirk`. Every H2 link in the Spock TOC
fails. Suggestion: regenerate the TOC with nickname-suffixed anchors,
or strip nicknames from anchors via explicit `<a name="...">` tags.

### 2. V0.03 T3.2 contradicts its own open question [HIGH]

**Files:** [development.md:2284-2289, 2366](documentation/development/development.md)

Test asserts `engine.bwcs.puts is a function`. The open question at
~2284 says the storage shape (function vs `{fn, owning_role}` table)
is "to be decided during implementation." The test commits to one
shape while the spec says it's undecided. Suggestion: pick the shape
in Step 2 before the test exists.

### 3. Sulu roadmap vs Sarek CLI position disagree [HIGH]

**Files:** [development.md:617, 2436-2437](documentation/development/development.md)

Sulu now lists CLI after V0.05; Sarek still says "after V0.02, before
V0.1." Suggestion: pick one — Sarek's "after V0.02" predates the
V0.03-V0.05 split.

### 4. V0.0X Sarek lists "stdout/stderr separation" as new [HIGH]

**Files:** [development.md:2459, 2478-2480](documentation/development/development.md)

V0.03 (Janeway) already ships stdout. Sarek's "introduces" list
claims stdout/stderr separation as new in the CLI slice. Suggestion:
rewrite Sarek to drop stdout; frame as "stderr + exit codes + shebang
+ permission flags."

### 5. Chekov role-growth path skips V0.03/V0.04/V0.05 [HIGH]

**File:** [development.md:710-741](documentation/development/development.md#L710-L741)

Jumps from V0.02 to "First HTTP" with no rows for the three slices I
added. Suggestion: add rows for V0.03 (stdout role), V0.04 (hash-class
role), V0.05 (no new role).

---

## B. V0.01 shipped-vs-promised gaps

### 6. `%role` system method promised but not shipped [BLOCKER]

**Files:** [development.md:686-687, 1522](documentation/development/development.md); [engine.lua](code/kscript/lua/kscript/engine.lua)

V0.01 footprint lists "role_system_method" but engine.lua has no
sys-reference handling. The fixture didn't require it so V0.01
passed. Suggestion: either remove from V0.01 footprint or schedule a
follow-up slice.

### 7. `string_class_role` is a TBD name hardcoded into shipped code + test [BLOCKER]

**Files:** [engine.lua:44](code/kscript/lua/kscript/engine.lua#L44); [test_bootstrap.lua:21](tests/kscript/v001/test_bootstrap.lua#L21); [roles.md:92-124](documentation/kscript/roles.md#L92-L124)

roles.md does not enumerate this role. Plan flags it as "provisional"
but test_bootstrap.lua asserts the exact string. Suggestion: pick a
final name now (or use one of roles.md's named roles like `engine`)
and update both code and test.

### 8. `tests/sanity/` directory promised by Phase 0 not present [BLOCKER]

**Files:** [development.md:1287-1297, 1418-1430, 1452-1464](documentation/development/development.md); `tests/sanity/` (does not exist)

All six T0.x sanity files (lua_hello, package_path, framework_sanity,
json_parse, file_read) were skipped. Phase 0 acceptance ("all six
pass before Phase 1 begins") was bypassed. Suggestion: either
backfill the six tests or amend the plan to say Phase 0 was skipped
deliberately and why.

---

## C. Cross-cutting issues (multiple files)

### 9. Exception/error class hierarchy is forked across ~7 files [HIGH]

**Canonical:** `kiera.uno/exception/error/timeout` — [kscript-runtime.md:745-765](documentation/kscript/kscript-runtime.md#L745-L765)

**Diverging shorthand `kiera.uno/error/...`:**
- [utils.md:47](documentation/kscript/utils.md#L47)
- [versioning.md:99](documentation/kscript/versioning.md#L99)
- [jasmine.md:311](documentation/kscript/jasmine/jasmine.md#L311)
- [kscript-runtime.md:1792](documentation/kscript/kscript-runtime.md#L1792) (itself)

**Subsystem-minted roots:** `kiera.uno/touchstone/error/*`, `kiera.uno/robinson/warning/*`, `kiera.uno/trivet/error/cycle`

**Also:** [kiera/kiera.md:363-364](documentation/kiera/kiera.md#L363-L364) lists `kiera.uno/exception` twice as two different classes.

Suggestion: decide on one root, or document the shorthand as sugar.

### 10. Binary trust model still leaks through despite roles.md superseding it [HIGH]

**Files:**
- `untrusted()` referenced as real construct — [kscript-runtime.md:822, 826](documentation/kscript/kscript-runtime.md#L822-L826)
- `%chain.trust` analogues — [filesystem.md:295-362](documentation/kscript/built-in-classes/filesystem.md#L295-L362)
- "trusted string" vocabulary — [nulls.md:430-432](documentation/kscript/built-in-classes/nulls.md#L430-L432)

roles.md explicitly retires all of this. Suggestion: rewrite affected
sections in role terms, or remove if the concept doesn't survive
translation.

### 11. Worldlet format is forked three ways [HIGH]

**Files:**
- [worldlet.md:54](documentation/mikobase/worldlets/worldlet.md#L54): "worldlets are non-temporal, no history key"
- [ai-conversation-format.md:210-236](documentation/mikobase/ai-conversation-format.md#L210-L236): "history is the only required top-level key"
- [mikobase.md:294-311](documentation/mikobase/mikobase.md#L294-L311): HTTP endpoint accepts worldlet whose body is a history block

Three docs, three shapes. Suggestion: pick one canonical worldlet
shape and reconcile across all three docs, including the HTTP
endpoint contract.

### 12. `updated_at` vs `created_at` for the same per-version field [HIGH]

**Files:**
- `updated_at` — [sqlite-schema.md:50, 55, 197](documentation/mikobase/sqlite-schema.md); [requirements.md:228, 374](documentation/mikobase/requirements.md)
- `created_at` — [worldlet.md:304, 313, 538-564](documentation/mikobase/worldlets/worldlet.md); [ai-conversation-format.md:48, 306, 315](documentation/mikobase/ai-conversation-format.md)

A worldlet round-tripped through the SQLite engine loses or renames
the timestamp. Suggestion: pick one — `created_at` reads cleaner for
an append-only history row.

### 13. Parameter spec is forked [HIGH]

**Files:** [parameters.md](documentation/kscript/parameters.md), [params.md](documentation/kscript/params.md); [kscript-runtime.md:1456-1459](documentation/kscript/kscript-runtime.md#L1456-L1459)

Two parameter spec docs cover overlapping ground with divergent
conventions: `lazy:true` syntax, nullable/classes/default vs
public/optional/`*args`/`**opts`. The runtime spec explicitly flags
the fork: "two parameter spec docs exist… Reconciling them is a
separate task." Suggestion: merge into one canonical doc; move the
other to `ideas/`.

### 14. Operator namespace inconsistent: `kscript.uno/` vs `kiera.uno/` [HIGH]

**Files:**
- `kscript.uno/...` — [operators.md:66ff](documentation/kscript/operators.md#L66), [assignment-operators.md:78ff](documentation/kscript/assignment-operators.md#L78)
- `kiera.uno/...` (the rest of the stdlib) — [parameters.md:134](documentation/kscript/parameters.md#L134), [kscript-runtime.md](documentation/kscript/kscript-runtime.md)

`kscript.uno/` is never defined as a separate namespace. Suggestion:
unify on `kiera.uno/`.

---

## D. Hard contradictions inside single language docs

### 15. Class-method definition: `function name()` vs `function &name()` [MEDIUM]

**Files:**
- `&` sigil form — [kscript.md:553, 624](documentation/kscript/kscript.md), class-definition.md
- Bare form — [kscript-runtime.md:1900, 1914, 2029-2084](documentation/kscript/kscript-runtime.md)

Pick one; the `&` form is consistent with the rest of kscript.md's
"function vs &function" rule.

### 16. `property` syntax: `:nickname` vs `@foo, :get, :set, default:'bar'` [MEDIUM]

**Files:** [kscript.md:591](documentation/kscript/kscript.md#L591), [kscript-runtime.md:2005-2010](documentation/kscript/kscript-runtime.md#L2005-L2010)

Two different first-argument shapes for the same construct.
Suggestion: reconcile in one place and reference from the other.

### 17. Pipe semantics: "first positional arg" vs "first and only arg" [MEDIUM]

**Files:** [kscript.md:758](documentation/kscript/kscript.md#L758), [pipes.md:33, 38-42](documentation/kscript/pipes.md#L33-L42)

kscript.md allows other args; pipes.md forbids them and desugars
`a | b` to `b(a)` only. Suggestion: pick one; the kscript.md form
is more general.

### 18. kscript.md self-conflict: `function`-with-`do` for definitions [MEDIUM]

**File:** [kscript.md:271 vs 441-461](documentation/kscript/kscript.md)

"No `do` for definitions" at line 271 vs every function/closure
definition example using `function(...) do ... end`. Suggestion:
clarify whether the form is a call (explains the `do`) or a
definition (forbids it).

### 19. KScriptJSON core principle broken by its own `if`/`while` form [MEDIUM]

**File:** [kscriptjson.md:42 vs 267-301](documentation/kscript/kscriptjson.md)

Core principle: every statement is `[receiver, method, args?]`.
`if` and `while` are encoded as `[{bwc:...}, {...}]` — two-element
forms with no method slot. Suggestion: either add an explicit method
for symmetry, or revise the core principle to note bwc statements may
omit the method slot.

### 20. `%blocks` system method listed but never defined [MEDIUM]

**Files:** [system-methods.md:37](documentation/kscript/system-methods.md#L37), [kscript-runtime.md:2118, 2467](documentation/kscript/kscript-runtime.md)

Only `%call.blocks` is defined; `%blocks` is listed in the top-level
system methods table. Suggestion: drop `%blocks` from the table or
define it as a shortcut.

### 21. `trilean` primitive vs `boolean` [MEDIUM]

**Files:** [kscript-runtime.md:422](documentation/kscript/kscript-runtime.md#L422), [system-methods.md:326](documentation/kscript/system-methods.md#L326), [trilean.md](documentation/kscript/built-in-classes/trilean.md)

Runtime declares Boolean as primitive; `%utils.json.parse` is
described as returning "trilean." `trilean.md` exists in
built-in-classes; nothing in the core declares a three-valued logic.
Suggestion: rename to `boolean`, or introduce trilean explicitly with
a defined logic system.

---

## E. Subsystem-vs-subsystem and dead references

### 22. Bryton/Xeme disagree on runner-error class prefix [MEDIUM]

**Files:** [runner.md:440-444](documentation/kscript/bryton/runner.md#L440-L444), [xeme.md:808, 823](documentation/kscript/bryton/xeme/xeme.md)

runner.md: `class: "bryton/runtime/missing"`. xeme.md: same concept
uses `kiera.uno/result/failure/runtime/crashed`. Suggestion: pick one
prefix for `errors[].class` and propagate.

### 23. xeme.md promised "Jasmine will be flattened to this shape." It wasn't. [MEDIUM]

**Files:** [xeme.md:503-547](documentation/kscript/bryton/xeme/xeme.md#L503-L547), [jasmine.md:411-468](documentation/kscript/jasmine/jasmine.md#L411-L468)

xeme.md describes a flat target; jasmine.md still has the nested
`calls + {function, entry}` shape. Suggestion: either update Jasmine
to the flattened shape or back the proposal out of xeme.md.

### 24. jasmine.md still describes itself as "for the Robinson handler in Dogberry" [MEDIUM]

**Files:** [jasmine.md:26-28](documentation/kscript/jasmine/jasmine.md#L26-L28); http-middleware.md, dogberry.md (which retire this framing)

Also matches the memory note: Dogberry is undefined. Suggestion:
update jasmine.md's framing to drop the retired association.

### 25. `%chain.log` treated as engine-granted ambient, missing from system-methods.md [MEDIUM]

**Files:** [jasmine.md:218-241](documentation/kscript/jasmine/jasmine.md#L218-L241) vs [system-methods.md:20-26](documentation/kscript/system-methods.md)

jasmine.md treats `%chain.log` as always-present, engine-configured.
system-methods.md doesn't list it. User code can't define new
`%`-prefixed methods, so jasmine.md depends on a core surface not
declared in core. Suggestion: add `%chain.log` to system-methods.md
or revise jasmine.md to use a non-system-method mechanism.

### 26. Robinson "page = class with no UNS" uses a class-decl form kscript.md doesn't define [MEDIUM]

**Files:** [robinson.md:270-284](documentation/kscript/http-middleware/robinson.md#L270-L284), [kscript.md:543-557](documentation/kscript/kscript.md#L543-L557)

kscript.md defines `class 'UNS' ... end`; no bare/anonymous form.
Robinson depends on a syntax variant the core doesn't define.
Suggestion: either define the bare-class form in kscript.md or change
Robinson's page declaration to use a synthetic UNS derived from path.

### 27. "FSO (filesystem object)" used in touchstone.md without a definition [LOW]

**File:** [touchstone.md:199, 294-326](documentation/kscript/http-middleware/touchstone.md)

The term doesn't appear in filesystem.md (which uses "jail / file
object / directory object") or any other doc. Suggestion: define FSO,
or rename to the existing terminology.

### 28. touchstone.md/sinatra.md mutate `$response.csp` etc. before any `$response` exists [MEDIUM]

**Files:** [touchstone.md:60-61, 766-792](documentation/kscript/http-middleware/touchstone.md); [sinatra.md:304-310](documentation/kscript/http-middleware/sinatra.md#L304-L310)

touchstone.md says `$response` starts at null and is built by stage
2. Then handlers write into `$response.csp[...]` and
`$response.headers[...]` as if it always exists. Suggestion:
reconcile the "starts at null" model with the per-transaction
mutable-response usage.

### 29. Uma referenced by Robinson and Trivet, no Uma spec in canonical tree [MEDIUM]

**Files:** [robinson.md:561-624](documentation/kscript/http-middleware/robinson.md), [trivet.md:7, 651, 691](documentation/kscript/trivet/trivet.md)

Only Uma spec lives in `documentation/ideas/uma/uma.md` (out of
scope). Suggestion: promote a minimal Uma spec into canonical
`documentation/kscript/uma/` before Robinson/Trivet work proceeds.

---

## F. Ecosystem / repo accuracy

### 30. README + overview promise Python Mikobase engine that doesn't exist [MEDIUM]

**Files:** [README.md:25](README.md#L25), [overview.md:99-107](documentation/overview.md#L99-L107); [code/mikobase/](code/mikobase/) (empty)

CLAUDE.md confirms V0.01 walking-skeleton target is the Lua KScript
engine, not Python Mikobase. Suggestion: update README and overview
to reflect current state; mark Mikobase engine as design only.

### 31. `%kiera.lower = ...` examples violate immutability stated 50 lines later [MEDIUM]

**File:** [kiera/kiera.md:135-138, 184-194 vs 147-149](documentation/kiera/kiera.md)

Both properties are described as "immutable once the kiera exists"
right after assignment examples. Suggestion: drop the assignment
examples since they directly violate the immutability rule.

### 32. `%kiera` propagation undefined at role boundaries [MEDIUM]

**File:** [kiera/kiera.md:35-38 vs 268-282](documentation/kiera/kiera.md)

Lines 35-38: "wiped at role boundaries, returns null when no kiera
in `%chain`." Lines 268-282: "engine controls; universally
available." Suggestion: decide explicitly — the role-crossing case
is the common one.

### 33. Vibecode reserved-field count off by one [LOW]

**File:** [vibecode.md:1-3, 247-267, 203](documentation/ecoverse/vibecode.md)

Introduces FOUR reserved keys (`vibecode`, `comment`, `misc`,
`enterprise`); line 203 says "all three reserved fields are always
passed through." Suggestion: fix "three" → "four."

### 34. Memory note says signing.md → blockchain.md; file isn't at the new location [LOW]

**Files:** `documentation/blockchain.md` (does not exist); [documentation/kscript/blockchain/blockchain.md](documentation/kscript/blockchain/blockchain.md) (does exist)

Either move the file as the memory note says, or update the memory.

### 35. `kiera.uno/vibcode` typo (missing 'e') [LOW]

**Files:** [kiera-html.md:26, 39](documentation/kiera/kiera-html.md), json.html:16

Every other doc uses "vibecode." Suggestion: fix typo before
`kiera.uno` is live (it will become a real addressable UNS).

### 36. Dogberry described in implementation detail in json-urls.md [MEDIUM]

**Files:** [kiera/json-urls.md:78, 149-156](documentation/kiera/json-urls.md)

Project memory explicitly says "Dogberry is undefined" and "do NOT
describe it as role-based access control." json-urls.md:149-156
describes Dogberry's request layer in implementation detail.
Suggestion: demote the Dogberry section to "TBD when Dogberry lands."

---

## G. Smaller gaps and dead pointers

### 37. `__END__` "spec requirement; not yet implemented" with no compliant-engine behavior stated [LOW]

**File:** [kscript.md:362-414](documentation/kscript/kscript.md)

For a "spec requirement," what happens when an engine sees `__END__`
but doesn't implement it should be stated (silent? error? warning?).

### 38. Stack-trace shape "TBD" but several specs depend on it [MEDIUM]

**Files:** [kscript-runtime.md:676-679](documentation/kscript/kscript-runtime.md#L676-L679); [versioning.md:127](documentation/kscript/versioning.md#L127); roles.md cross-role trust mechanics

Suggestion: stub a minimal shape (array of `{class, method, line}`
frames) even if extensions are TBD.

### 39. `[{bwc:"if"}, {}]` (branchless `if`) undefined [LOW]

**File:** [kscriptjson.md:290](documentation/kscript/kscriptjson.md#L290)

Doc says branches and else are both optional; never says what the
empty form evaluates to.

### 40. `%kiera.call` referenced but signature unspecified [MEDIUM]

**File:** [kscript.md:505-521](documentation/kscript/kscript.md#L505-L521)

`remote function` delegates to `%kiera.call(self, :save, name: name)`.
Neither system-methods.md nor kscript-runtime.md defines `%kiera.call`.
The in-scope spec leaves the call signature, error model, and
`%chain` forwarding unspecified.

### 41. `scope.operators` namespace referenced but not specified [LOW]

**Files:** [operators.md:63-70](documentation/kscript/operators.md#L63-L70), [assignment-operators.md:134](documentation/kscript/assignment-operators.md#L134)

Whether `scope` here is `%scope` (the lexical scope) or a different
concept is unspecified. The doc's own open questions confirm it's not
settled.

### 42. `%vibecode side` field has no documented consumer effect [LOW]

**File:** [system-methods.md:39](documentation/kscript/system-methods.md#L39)

Introduces `side: "target" | "value"` as "attachment intent." No file
says what consumers do with it.

### 43. `loops.md` structural blocks have no grammar contract in core [LOW]

**File:** [loops.md:204-227](documentation/kscript/loops.md#L204-L227); [kscript-runtime.md:533-538](documentation/kscript/kscript-runtime.md) (core bwcs list)

`before` / `between` / `after` / `noloop` are shown in examples but
their lexer/parser contract (reserved bwcs? scoped only inside
loops?) is not defined.

### 44. `meta-hash.md` self-contradicts on per-level writes [LOW]

**File:** [meta-hash.md:60-77 vs 122-125](documentation/kscript/built-in-classes/meta-hash.md)

"Writes always land in the last hash" vs "writes at a level set just
that level." Suggestion: pick one.

### 45. `bryton/runner.md:128` "[slob pattern](../../)" link is incomplete [LOW]

**File:** [runner.md:128](documentation/kscript/bryton/runner.md#L128)

Points at the documentation root rather than a specific document
discussing the slob pattern.

### 46. `vscode/syntax/syntax.md` is zero bytes [LOW]

**File:** [syntax.md](documentation/kscript/vscode/syntax/syntax.md)

Either planned stub or should be removed; right now it's a dead link
target.

### 47. `trilean.md:370` points to nonexistent `code/kscript/stdlib/trilean.kscript` [LOW]

**File:** [trilean.md:370](documentation/kscript/built-in-classes/trilean.md#L370)

The entire stdlib directory is empty. Spec lists this as if it ships
in v1.

### 48. Bryton spec link path wrong in V0.1 Amanda vibecode [LOW]

**File:** [development.md:2674-2676, 2680-2681](documentation/development/development.md)

Vibecode paths point at `documentation/bryton/...`; real path is
`documentation/kscript/bryton/...`. Prose link `[bryton/overview.md](../overview.md)`
resolves to `documentation/overview.md` (which exists but is the
project overview, not Bryton's).

### 49. Hardcoded `/home/miko/projects/mikobase/working/bin` in V0.0X CLI pseudocode [LOW]

**File:** [development.md:2576](documentation/development/development.md#L2576)

Repo lives at `/home/miko/projects/kiera/working/`. CLAUDE.md
acknowledges the historical `mikobase` directory name but this is a
copy/paste from a developer's actual rc file.

---

## Priority cheat sheet

**Before V0.02 implementation starts (BLOCKER):**
#1 (broken TOC), #6 (missing `%role`), #7 (`string_class_role` TBD),
#8 (missing `tests/sanity/`).

**Before V0.03 plan goes live (HIGH within the plan):**
#2 (T3.2 vs open question), #3 (Sulu vs Sarek position), #4 (Sarek
stdout duplication), #5 (Chekov role growth missing rows).

**Spec reconciliation pass before broader work (HIGH cross-cutting):**
#9 (exception namespace), #10 (binary-trust leftover), #11 (worldlet
fork), #12 (timestamp field), #13 (parameter fork), #14 (operator
namespace).

**Per-spec cleanups when each area is next touched (MEDIUM):**
Items 15-21 (D), 22-29 (E), 30-32, 36 (F), 38, 40 (G).

**Opportunistic (LOW):**
Remaining items in F and G.
