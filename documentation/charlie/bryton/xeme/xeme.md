# Xeme

~~~json
{"vibecode": {
	"doc": "xeme",
	"role": "spec for Xeme, the JSON-shaped tree format for reporting structured results (test outcomes, Jasmine entries); covers the required success field, groups and leaves",
	"key_concepts": ["xeme_format", "success_field", "groups_and_leaves",
		"language_agnostic_json", "bryton_contract"]
}}
~~~

A **Xeme** is a JSON structure for reporting structured results
— most commonly test results, but also any tree-shaped record of
outcomes. It is the format Bryton consumes and produces, and the
same shape underpins [Jasmine](../../jasmine/jasmine.md) entries (Jasmine
entries are Xemes).

The format is deliberately small and language-agnostic. Any
language that can emit JSON can produce Xemes; any tool that can
parse JSON can consume them.

---

<a id="required-field"></a>
## 1 Required field

Every Xeme has a `success` field. Three valid values:

| Value | Meaning |
|---|---|
| `true` | Definitively succeeded. |
| `false` | Definitively failed. |
| `null` | No verdict reached (crashed before result, timed out, interrupted, or the developer explicitly chose null). |

`success` is **always present**. If the producer doesn't know the
outcome, it writes `null` explicitly.

In practice, most "didn't complete" cases are failures (false)
rather than null. Null is reserved for cases where the developer
*chose* to leave the verdict undetermined, or where the value was
never set at all. The distinction matters mainly when results
need to be promoted to verdicts later (e.g., promises, async
resolution).

---

<a id="groups-and-leaves"></a>
## 2 Groups and leaves

A Xeme is either a **leaf** or a **group**, distinguished by the
presence of `nested`:

- **Leaf** — no `nested` field. Its `success` reflects its own
  verdict, set by whatever code produced it (a test assertion, a
  runtime result, etc.). This is where actual results live.
- **Group** — has a `nested` field (even if empty). Its `success`
  is **entirely derived from its children's successes**. A group
  has no opinion of its own; it's an aggregation node.

Bryton uses this strict split rigorously: a test is either a
group (a directory, a suite) or a leaf (an individual assertion
or test result). Mixing — a node that has its own verdict *and*
children — isn't a Bryton concept.

The Xeme format itself is more flexible (Jasmine entries, for
example, carry their own data alongside children), but most
consumers will find the strict group/leaf split easier to reason
about.

```json
// Leaf
{"success": true}

// Group
{
    "success": true,
    "nested": [
        {"success": true},
        {"success": true}
    ]
}
```

<a id="validation-group-errors-or-nulls-raises-a-warning"></a>
### 2.1 Validation: group + `errors` or `nulls` raises a warning

`errors` and `nulls` are **leaf-only concerns** — they explain why
this Xeme's verdict isn't a plain success, which only makes sense
when the Xeme has its own verdict. A group's success is derived
from its children, so a group with either field is a structural
inconsistency.

**Validators emit a warning when they encounter a group with
`errors` or `nulls`, but pass the Xeme through unchanged.** The
data isn't lost; the warning surfaces the inconsistency so the
producer can fix it.

Other field combinations are unconstrained — groups can have
`name`, `class`, `warnings`, `notes`, `run_time`, etc. without
issue. Only `errors` and `nulls` are leaf-only.

---

<a id="resolution"></a>
## 3 Resolution

Before a Xeme is **valid**, it must be **resolved** — its
parent-child relationships must be consistent.

The rule:

> **A parent cannot be more successful than any of its children.**

With ordering `false < null < true`, resolution works as follows:

- **Leaf**: `success` stays whatever the producer set.
- **Group**:
  - Compute the **children's verdict**: minimum of all children's
    `success` values under the `false < null < true` ordering.
    **Skipped Xemes** (those with `meta.skipped: true`) are
    excluded from this calculation entirely.
  - If the group's own `success` is `null` (the typical
    placeholder), adopt the children's verdict.
  - Otherwise, the group's resolved `success` is `min(own, children's verdict)`.

In other words, a group can be **less successful than its
children's verdict** (a producer explicitly setting `false` on
the group wins over `true` children — see "Explicit fail" below),
but never more successful.

Examples:

```
own: null,  children: [true, true]    →  group resolves to true
own: null,  children: [true, false]   →  group resolves to false
own: null,  children: [true, null]    →  group resolves to null
own: true,  children: [true, true]    →  group resolves to true
own: true,  children: [false]         →  group resolves to false
own: false, children: [true, true]    →  group resolves to false  ← explicit fail
own: false, children: [true, null]    →  group resolves to false
```

This is the **least-good-result** rule, with the parent's `null`
treated as "no opinion, defer to children."

<a id="explicit-fail-on-a-group-is-allowed"></a>
### 3.1 Explicit fail on a group is allowed

A producer **can** explicitly set a group's `success` to `false`
even when all its children pass:

```json
{
    "success": false,
    "nested": [
        {"success": true}
    ]
}
```

This resolves to `false` (the group stays failed) because a
parent is allowed to be **less** successful than its children.
It's bad form — a group's success should usually come from its
children — but the format allows it. No nanny code for that; the
validator doesn't warn.

<a id="mixed-nodes-general-case"></a>
### 3.2 Mixed nodes (general case)

For non-Bryton consumers that produce Xemes carrying both their
own success and children (Jasmine entries are the working
example): the resolution rule becomes "min over own success and
all children's successes." That introduces a parent-null edge
case (a parent's own `null` interacting with all-`true` children
under strict least-good ordering), which is **not yet resolved**.

Bryton sidesteps this entirely by using the strict group/leaf
split. Consumers that need mixed nodes should treat the
parent-null case as open until pinned down.

---

<a id="keep-xemes-small"></a>
## 4 Keep Xemes small

A Xeme should carry **only the information that's actually
relevant**. Most Xemes won't populate most reserved fields. Empty
arrays and empty hashes should be omitted entirely, not written
as placeholders.

This is a valid Xeme:

```json
{
    "success": true,
    "nested": [
        {"success": true},
        {"success": true}
    ]
}
```

That's it — no `name`, no `class`, no empty `warnings: []`. The
structure carries exactly what the producer needed to report.

The reserved fields are *available* when needed, not *expected*
in every Xeme. A test run that produces a clean pass should
generate a sparse tree, not a verbose one padded with empty
fields.

---

<a id="reserved-fields"></a>
## 5 Reserved fields

Beyond the required `success`, Xemes use a small set of **reserved
fields**. Producers aren't required to include any of them, but
when they appear, they have specific meanings and consumers rely
on those meanings.

| Field | Type | Purpose |
|---|---|---|
| `class` | string | Typed identifier — see [Class field](#class-field) below. |
| `nested` | array of Xemes | Children (presence = group). |
| `errors` | array | Failure causes; populated when `success: false`. Flat entries; see [Errors and nulls](#errors-and-nulls) below. |
| `nulls` | array | Null-reasons; populated when `success: null`. Flat entries; see [Errors and nulls](#errors-and-nulls) below. |
| `warnings` | array | Non-fatal observations. Flat entries with `{"id":..., "details":...}` shape. |
| `notes` | array | Informational messages. Flat entries — strings or `{"id":..., "details":...}` hashes. |
| `location` | hash | Where the Xeme was produced — see [Location field](#location-field) below. |
| `tags` | hash | Tags about this run's result. Distinct from `location.tags` (which carries source tags). See [Tags](#tags) below. |
| `meta` | hash | Metadata about the Xeme itself — see [Meta field](#meta-field) below. |
| `io` | hash | Captured I/O streams — see [I/O field](#io-field) below. |
| `misc` | hash | Arbitrary application-specific extras. Puck-wide convention; pass-through. |
| `corporate` | hash | Organization-level data (licensing, audit, org tags, etc.). Puck-wide convention; pass-through. |
| `vibecode` | hash | AI-readable annotations (design notes, commentary). Puck-wide convention; consumed by AI tooling. |

The top-level surface deliberately stays small. Less-commonly-
attended fields live one level deeper under `meta` and `io`,
keeping the outer structure focused on the verdict and what
matters per Xeme.

The last three (`misc`, `corporate`, `vibecode`) are **Puck-wide
conventions** — they appear on Puck objects generally, not just
Xemes. Xeme inherits them as part of being a Puck-shaped
structure. None of them carry semantics that Xeme processors
consume; they're pass-through buckets that consumers and tooling
can use without having to invent yet another extension field.

Producers can add additional fields beyond these reserved names.
The reserved set is closed at the spec level; anything else is the
producer's namespace.

<a id="meta-field"></a>
### 5.1 Meta field

The `meta` hash holds **metadata about the Xeme itself** — fields
that are about the result-as-record rather than the verdict-as-
content. Less commonly attended day-to-day; nesting them keeps
the outer surface focused.

Conventional keys inside `meta`:

| Key | Type | Purpose |
|---|---|---|
| `name` | string | Human-readable identifier (file name, test name, function name). |
| `uuid` | string | Unique identifier; UUIDv4 (random). See below. |
| `timestamp` | string | When the Xeme was created. ISO 8601, millisecond precision. |
| `run_time` | number | Duration in seconds. |
| `skipped` | bool | `true` if the Xeme represents something that was deliberately not run. See below. |

**Skipped.** Skip is orthogonal to class — a test keeps its class
identity (`test`, `group/file/rb`, etc.) regardless of whether it
ran. `meta.skipped: true` is the flag that says "this Xeme didn't
actually run; don't count it toward the verdict."

**Resolution** excludes skipped Xemes from the min-calculation
over children. A group whose only failing child is skipped
resolves the same as if that child weren't there at all. Reporters
can count skipped Xemes separately by filtering on
`meta.skipped`.

**UUIDs.** UUIDs are the simple way to reference a specific test.
Tools that cross-reference results across runs, link failures to
bug-tracker entries, persist test history, or build reporting
dashboards rely on a stable identifier. Producers may generate
UUIDs automatically in some situations (typically when persistence
or cross-referencing matters); trivial Xemes don't need them.

When a UUID is auto-generated, it's typically UUIDv4 (random per
run). Producers that want UUIDs stable across runs (so the same
logical test gets the same UUID each time) derive them
deterministically — but that's a producer decision, not part of
the Xeme spec.

**Timestamps.** Typically only appear on the top-level (central)
Xeme of a run. Nested Xemes don't usually need their own
timestamp — they share the run's timestamp by inheritance.
Producers can add deeper timestamps if they want; not the default.


<a id="io-field"></a>
### 5.2 I/O field

The `io` hash holds **captured I/O streams**. Mostly relevant for
runtime-failure Xemes where the runner captured the test
process's output before failing.

Conventional keys inside `io`:

| Key | Type | Purpose |
|---|---|---|
| `stdout` | string | Captured stdout. |
| `stderr` | string | Captured stderr. |

<a id="location-field"></a>
### 5.3 Location field

The `location` field is a hash that records where the Xeme was
produced — file, line, source-level metadata. Common keys (by
convention):

| Key | Type | Purpose |
|---|---|---|
| `file` | string | File path (absolute or relative — producer's choice). |
| `line` | integer | Line number. |
| `stack` | language-specific | Stack trace. The format is the producer's choice; consumers should expect language variation. |
| `tags` | hash | Tags declared at this location. See [Location tags](#location-tags) below. |

Example:

```json
{
    "success": false,
    "location": {
        "file": "foo.charlie",
        "line": 22
    }
}
```

Producers can add additional keys (`column`, `function`, `module`,
etc.) as their language and use case need. The reserved keys
above are the *conventionally-named* ones; everything else inside
`location` is the producer's namespace.

`location` can appear on any Xeme.

- **Leaves** typically point at the assertion that failed (or
  passed): the file and line of the test code.
- **Groups** commonly point at the file or directory that the
  group represents. For Bryton:
  - A group representing a file of tests has `location.file` set
    to that file path.
  - A group representing a directory tree of tests has
    `location.file` set to the directory path.
  - This is the common case, not an exception.
- **Jasmine call frames** point at where the call was made.

Producers decide what makes sense in context.

<a id="location-tags"></a>
#### 5.3.1 Location tags

`location.tags` is a hash describing **tags declared at this
location** (a tagged directory's bryton.json, a tagged file,
etc.). Keys are tag names; values are opaque metadata that
consumers can use however they want (Xeme itself doesn't
interpret them).

```json
"location": {
    "file": "tests/integration",
    "tags": {
        "integration": true,
        "slow": {"timeout_hint": 60}
    }
}
```

**Tags belong in `location` because that's where they came
from** — they were declared at the source of this Xeme. The Xeme
is the *result* of running that source; the tags are properties
of the source, carried through the result to consumers.

**Tags are per-node, not inherited.** A tagged directory's Xeme
carries those tags in its location; its children's Xemes have
their own location with their own tags (which won't include the
parent's tags unless the child was declared with them too).

The same value semantics from Bryton's tag declarations apply: a
falsy value means the tag is absent. Producers that include
`tags` in their Xeme output should omit falsy entries (write the
effective tag set, not the raw declaration).

Tags enable consumers to group, filter, or report by tag — "show
me all failing tests tagged 'integration'," "summarize
performance by tag," etc.

<a id="errors-and-nulls"></a>
### 5.4 Errors and nulls

Two parallel fields describe why a Xeme's verdict isn't a plain
success:

- **`errors`** — populated when `success: false`. Each entry is a
  flat object describing one failure cause (assertion failed,
  exception raised, timeout, etc.).
- **`nulls`** — populated when `success: null`. Each entry is a
  flat object describing one reason no verdict was reached (result
  pending as a promise, test deliberately skipped, etc.).

Each entry has a `class` field identifying the specific kind,
plus any other descriptive fields:

```json
"errors": [
    {
        "class": "bryton/runtime/exception",
        "message": "uncaught NoMethodError",
        "details": {...}
    }
]
```

```json
"nulls": [
    {"class": "bryton/null/promise"}
]
```

**About promises.** A `promise` null-reason means the test result
isn't ready yet — the verdict will be determined later. Bryton
doesn't define how promises get resolved (async runners, deferred
evaluation, etc.); just that the placeholder is a null with class
`bryton/null/promise`.

Because the result is null, the
[resolution rule](#resolution) means **none of its ancestors can
be true** — they can be `false` (if there's a failure elsewhere
in the tree) or `null` (if no failures), but never `true`. A
promise propagates as "not yet decided" up the tree until
something fills it in (or the run ends and it stays null).

Real promise machinery isn't designed; this is just the
placeholder concept and its propagation behavior.

**Entries are flat — they don't have their own `nested` arrays.**
A reason entry isn't a Xeme; it's a description of a cause. If a
failure has a cascade (A caused B caused C), the chain lives
inside one entry's stack/details, not as nested entries. If a
failure has multiple independent causes, those are multiple
entries in the flat array.

This is a deliberate constraint to keep `errors`/`nulls` distinct
from `nested`: `nested` is for sub-tests participating in the
verdict, `errors`/`nulls` are for flat descriptors of why the
verdict is what it is. The two don't mimic each other because
they're solving different problems.

<a id="tags"></a>
### 5.5 Tags

Top-level `tags` is a hash describing **tags about this run's
result**. Keys are tag names; values are opaque metadata that
consumers can use however they want (Xeme itself doesn't
interpret them).

```json
{
    "success": false,
    "tags": {
        "regression": true,
        "flaky": {"recent_failures": 3, "recent_passes": 47}
    }
}
```

**Top-level `tags` ≠ `location.tags`.** Two distinct concepts:

| Field | What it carries |
|---|---|
| `location.tags` | Tags from the *source* — properties of the test (declared in bryton.json or on the file). |
| `tags` (top-level) | Tags about the *run's result* — properties of the verdict (set during execution or by analytics). |

Examples:

- `location.tags: {"integration": true}` — "this test is part of
  the integration suite" (developer-declared).
- `tags: {"regression": true}` — "this run revealed a regression"
  (analyzer-applied).
- `location.tags: {"slow": true}` — "this test is generally slow"
  (developer-declared).
- `tags: {"under_5s": true}` — "this specific run completed in
  under 5 seconds" (auto-applied).

The value semantics are the same as `location.tags` — falsy
values mean the tag is absent; producers should omit falsy
entries in output.

<a id="class-field"></a>
### 5.6 Class field

Working convention: **UNS-style identifier without the domain
prefix.** Examples:

- `"bryton/group/dir/runner"` — the runner's top-level Xeme.
- `"bryton/runtime/crashed"` — a test file that crashed.
- `"bryton/runtime/timeout"` — a test that timed out.
- `"bryton/runtime/unparseable"` — a test whose stdout couldn't
  be parsed as JSON.
- `"jasmine/call"` — a function-call frame inside a Jasmine
  entry tree.

The format is parseable with the same conventions as
[UNS](../../../ecoverse/uns.md) (slash-separated segments, lowercase, etc.).
Third-party Xeme producers can use their own UNS prefix:
`"myorg.com/test/integration"`.

---

<a id="jasmine-entries-are-xemes"></a>
## 6 Jasmine entries are Xemes

[Jasmine](../../jasmine/jasmine.md) entries follow the Xeme format. A
Jasmine log is a stream of Xemes (one per entry), each potentially
containing nested call frames as `nested` children.

The proposed alignment (to fold into the Jasmine spec):

- Jasmine's `calls` array becomes `nested` (uniform with Xeme).
- The two-level wrapper (`{"function": "...", "entry": {...}}`)
  flattens — each child is just a Xeme directly, with the
  function name as the child's `name` field and `class:
  "jasmine/call"`.

Result:

```json
{
    "success": true,
    "meta": {
        "uuid": "...",
        "timestamp": "..."
    },
    "web": {"request": "...", "response": "..."},
    "nested": [
        {
            "success": true,
            "class": "jasmine/call",
            "meta": {"name": "process_request"},
            "location": {"line": 142},
            "nested": [
                {
                    "success": true,
                    "class": "jasmine/call",
                    "meta": {"name": "authenticate"},
                    "location": {"line": 88}
                }
            ]
        }
    ]
}
```

Benefits:

- One nesting model across both formats.
- Tools that consume Xemes consume Jasmine logs (and vice versa).
- The least-good-result rule applies uniformly.

**Status (2026-05-17): proposed, not yet applied.** [jasmine.md](../../jasmine/jasmine.md)
still describes the current shape with `calls` and the `{"function":
"...", "entry": {...}}` wrapper. The alignment above is a sketch
for a future revision of Jasmine; until that revision lands, the
two formats remain structurally different.

---

<a id="trimming"></a>
## 7 Trimming

A test run that mostly passes produces a tree full of successful
leaves you don't usually care about. **Trimming** is a defined
operation that removes successful leaves, leaving behind only the
parts of the tree that surface failures (or `null` non-verdicts).

The example:

Before:

```json
{
    "success": false,
    "nested": [
        {"success": true},
        {
            "success": false,
            "nested": [
                {"success": true},
                {"success": false}
            ]
        }
    ]
}
```

After:

```json
{
    "success": false,
    "nested": [
        {
            "success": false,
            "nested": [
                {"success": false}
            ]
        }
    ]
}
```

The successful leaves are gone. The failed leaf survives, along
with its ancestors.

<a id="rules"></a>
### 7.1 Rules

Applied bottom-up to a resolved Xeme tree:

- **Leaf with `success: true`** — remove.
- **Leaf with `success: false`** — keep.
- **Leaf with `success: null`** — keep (no-verdict results are
  informational and worth surfacing).
- **Group** — recursively trim its children first, then:
  - If all children were trimmed away **and** the group's
    `success` is `true` — remove the group entirely.
  - Otherwise — keep the group. If the trimmed `nested` is empty,
    drop the `nested` field (per the "keep Xemes small" rule).

<a id="specific-scenarios"></a>
### 7.2 Specific scenarios

- **Everything passed.** The whole tree trims to a single Xeme
  `{"success": true}`. Still valid, still meaningful — "the suite
  ran and everything passed."
- **Group with explicit `success: false` and all-true children**
  (the explicit-fail case). The children trim away; the group
  stays as `{"success": false}` with no `nested`. Still
  meaningful — the producer wanted to mark it failed.

<a id="what-trimming-preserves"></a>
### 7.3 What trimming preserves

Trimming is a **reduction**, not a transformation. It doesn't
change any `success` values, doesn't rewrite fields, doesn't
add anything. The trimmed tree is a strict subset of the
original. A producer that emits a full tree and a consumer that
trims it agree on every value that's still there.

---

<a id="streaming-and-partial-xemes"></a>
## 8 Streaming and partial Xemes

A Xeme can be emitted incrementally. A test runner can write a
parent Xeme with `success: null` and `nested: []`, append children
as they arrive, then resolve at the end. Consumers reading the
final form see the resolved structure.

(Streaming protocols, partial-Xeme exchange formats, etc. are
not specified at this level. The basic format supports them but
doesn't define the wire protocol.)

---

<a id="icons"></a>
## 9 Icons

A canonical **icon set** ships with the Xeme spec under
[`icons/`](icons/). Each Xeme `class` maps to an SVG (or GIF) at
the corresponding path in the icon tree. Icons aren't immediately
load-bearing — most Bryton output is text — but they make result
visualization dramatically more readable in UIs that surface
them, so the set is considered a **core part of the spec**.

<a id="layout"></a>
### 9.1 Layout

The icon set splits at the top level into three directories:

- **`icons/tests/`** — icons for the test-node class hierarchy
  (the `class` field on the Xeme itself: groups, files, etc.).
- **`icons/results/`** — icons for verdict-state classes (the
  classes used in `errors`/`nulls` entries: success, failure,
  failure subtypes, null reasons).
- **`icons/ui/`** — non-class UI helper icons (filter buttons,
  sort indicators, spinners, etc.).

For a Xeme's class lookup, the runner walks under `tests/`. For a
failure-cause or null-reason class (entries inside `errors` or
`nulls`), the lookup walks under `results/`.

For a Xeme with `class: "group/file/rb"`, the class-icon lookup
tries:

1. `icons/tests/group/file/rb.svg`
2. `icons/tests/group/file.svg`
3. `icons/tests/group.svg`
4. `icons/tests/generic.svg`

For a failure entry with `class: "bryton/runtime/crashed"`,
the result-icon lookup tries:

1. `icons/results/failure/runtime/crashed.svg`
2. `icons/results/failure/runtime.svg`
3. `icons/results/failure.svg`

First match wins. Walking up the class path means a missing
specific icon falls back to a sensible parent automatically.

<a id="whats-in-the-set"></a>
### 9.2 What's in the set

**Under `tests/`** (Xeme class icons):

- **Top-level** — `generic.svg`, `unknown.svg`, `test.svg`.
- **`group/`** — group types: `dir.svg`, `file.svg`,
  `remote.svg`, `timer.svg`. Language-specific file icons under
  `group/file/`: `charlie.svg`, `rb.svg`, `js.svg`, `py.svg`,
  `java.svg`. (The `charlie.svg` icon is a placeholder — not the
  official Charlie logo yet.)
- **`group.svg`** — group catch-all.

**Under `results/`** (verdict-state icons):

- **Top-level** — `success.svg`, `failure.svg`, `null.svg`.
- **`failure/runtime/`** — runtime failure classes: `crashed.svg`,
  `exception.svg`, `missing.svg`, `not-executable.svg`,
  `not-hash.svg`, `timedout.svg`, `unparseable.svg`.
- **`null/`** — null-state reasons: `promise.svg`, `skipped.svg`.

**Under `ui/`** (non-class):

- `filter.svg`, `note.svg`, `spinner.gif`, `trimmed.svg`,
  `warning.svg`.
- `sort/up.svg`, `sort/down.svg`, `sort/none.svg`.

<a id="why-it-ships-with-the-spec"></a>
### 9.3 Why it ships with the spec

Letting each consumer ship its own icon set would lead to
inconsistent visual representation of the same Xeme classes
across tools. Shipping a canonical set with the spec means every
Bryton dashboard, every IDE plugin, every result viewer can use
the same icons for the same things, even if they choose to
override individual ones.

Most projects won't think about icons day-to-day. The set is
here when it's wanted.

<a id="what-xeme-is-not"></a>
## 10 What Xeme is not

- **Not a programming-language class.** Xeme is a data format.
  Bryton or any consumer can wrap it in a builder class for
  convenience, but the canonical form is JSON.
- **Not an event system.** Pub/sub on success changes is a
  consumer concern, not part of the format.
- **Not a UUID-bearing thing by default.** If a use case needs
  UUIDs (Jasmine does), put them in conventional fields the
  producer adds. The base Xeme format doesn't include them.

---

<a id="examples"></a>
## 11 Examples

<a id="simplest"></a>
### 11.1 Simplest

```json
{"success": true}
```

<a id="test-failure-with-errors"></a>
### 11.2 Test failure with errors

```json
{
    "success": false,
    "class": "myorg.com/test/integration",
    "errors": [
        {
            "class": "bryton/assertion",
            "message": "expected user.email == 'foo@example.com', got null",
            "details": {
                "expected": "foo@example.com",
                "actual": null
            }
        }
    ],
    "meta": {
        "name": "test_user_creation",
        "run_time": 0.034
    }
}
```

<a id="runner-level-result-tree"></a>
### 11.3 Runner-level result tree

```json
{
    "success": false,
    "class": "bryton/group/dir/runner",
    "meta": {
        "name": "tests",
        "run_time": 2.1,
        "timestamp": "2026-05-13T18:42:00.123Z"
    },
    "nested": [
        {
            "success": true,
            "class": "bryton/group/file",
            "meta": {"name": "auth_test.charlie", "run_time": 0.4}
        },
        {
            "success": false,
            "class": "bryton/group/file",
            "meta": {"name": "db_test.charlie", "run_time": 1.2},
            "nested": [
                {
                    "success": false,
                    "meta": {"name": "test_connection"},
                    "errors": [{"class": "bryton/connection_refused"}]
                }
            ]
        }
    ]
}
```

<a id="runtime-crash"></a>
### 11.4 Runtime crash

```json
{
    "success": false,
    "class": "bryton/test",
    "errors": [
        {"class": "bryton/runtime/crashed"}
    ],
    "meta": {"name": "broken_test.charlie"},
    "io": {"stderr": "Traceback..."},
    "exit_code": 1
}
```

<a id="missing-test"></a>
### 11.5 Missing test

```json
{
    "success": false,
    "class": "bryton/test",
    "errors": [
        {"class": "bryton/runtime/missing"}
    ],
    "meta": {"name": "expected_test_that_doesnt_exist.charlie"}
}
```

(`exit_code` is a producer-namespaced field — not reserved, so
Bryton can use it directly on the Xeme.)
