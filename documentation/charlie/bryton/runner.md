# Bryton Runner

The Bryton runner walks a tree of test files, executes them, and
assembles the results as a [Xeme](xeme/xeme.md) tree.

This doc focuses on **test aggregation** and **dynamic directory
configuration**. The runner's full behavior (concurrency,
fail-fast, env var handling, etc.) will be filled in across other
runner-spec sections.

---

<a id="brytonjson-per-directory"></a>
## 1 `bryton.json` per directory

Any directory in the test tree may contain an optional
`bryton.json` file with per-directory configuration.

The most common use is the **`files` hash**, which controls:

- **What gets run** in the directory.
- **The order** in which entries are run.
- **Whether listed entries** are skipped explicitly.

```json
{
    "files": {
        "simple.charlie": true,
        "foo.rb": false,
        "details": true
    }
}
```

<a id="files-semantics"></a>
### 1.1 `files` semantics

- **Order** — entries in `files` run in their listed (JSON-object)
  order. So `simple.charlie` runs first, then `details/` (a
  directory) runs second.
- **`true`** — run this entry.
- **`false`** — **explicitly skipped.** This produces a Xeme with
  `meta.skipped: true` so the report shows what was skipped. Not
  silent omission — the developer's choice is visible.
- **Files and directories listed uniformly** — `details` (a
  subdirectory) sits alongside `simple.charlie` (a file) and is
  ordered the same way.
- **Unlisted entries run after listed ones**, in undefined order
  (unless `explicit: true` is set — see below).

<a id="per-file-overrides"></a>
### 1.2 Per-file overrides

A file's value in `files` can be a hash instead of `true`/`false`,
allowing the file to override specific settings for that one
file:

```json
{
    "files": {
        "foo.charlie": {
            "fail_fast": true
        }
    }
}
```

**The allowed per-file overrides are a strict subset** of the
directory-propagating settings, currently just:

- **`fail_fast`** — this one file's fail-fast behavior overrides
  the directory's default.
- **`trim`** — this one file's trim behavior overrides the
  directory's default.

That's it. Other propagating settings (like `bryton_env`) aren't
per-file overrideable; their hash-merging semantics make per-file
overrides awkward. Per-directory-only settings (`files`,
`explicit`, `parallel`, `timeout`, `tmp_dir`) likewise aren't
per-file overrideable — they describe how a directory handles
its children, not how a file runs.

**Why so restrictive:** the Ruby Bryton equivalent grew the
per-file override surface incrementally, and the cumulative
N × M (settings × files) configuration became hard to reason
about. Keeping the per-file set to two boolean settings keeps the
mental model simple.

If a future need surfaces a setting that genuinely should be
per-file overrideable, it joins the list deliberately — additions
to settled specs go through review, not casual accretion.

<a id="explicit-true-only-run-whats-listed"></a>
### 1.3 `explicit: true` — only run what's listed

By default, unlisted entries run after listed ones. Setting
`explicit: true` at the same level as `files` changes that:
**only the entries in `files` run; everything else in the
directory is ignored.**

```json
{
    "explicit": true,
    "files": {
        "foo.bar": true
    }
}
```

In this example, only `foo.bar` runs. Any other executable file
or subdirectory in the same directory is skipped entirely (no
Xeme produced, no entry in the report).

**Practical notes:**

- **`dev.*` files stay silently ignored** even under
  `explicit: true`. The dev convention handles in-progress files;
  explicit handles scope.
- **`explicit` doesn't propagate** to subdirectories. Each
  subdirectory makes its own per-directory choice.
- **`explicit: true` with empty `files`** means run nothing in
  this directory. Valid — the developer explicitly chose to
  suppress everything.
- **Missing listed files** still produce missing-file results as
  with regular `files` entries. Explicit doesn't change that
  behavior.

<a id="why-false-produces-an-explicit-skip"></a>
### 1.4 Why `false` produces an explicit skip

A file marked `false` isn't silently dropped — it's a deliberate
skip, and the report says so. This is the *slob pattern* at work
(companion to the no-nanny principle in
[overview.md](../../overview.md)): the developer's choice is
respected (file doesn't run), but the choice is **visibly
recorded** (skip appears in the Xeme tree). The developer can
audit "what didn't run" without having to remember.

If a developer has many non-test files in a test directory,
that's sloppy organization, and the framework noting it isn't
punishment — it's accountability. See the `dev.*` exception below
for files that aren't tests yet.

---

<a id="dev-files-silent-ignore"></a>
## 2 `dev.*` files — silent ignore

Executable files whose name starts with `dev.` are **silently
ignored** by the runner. They don't appear in the test tree at
all.

```
dev.scratch.charlie      # ignored
dev.experiment.rb        # ignored
dev.new_idea.charlie     # ignored
```

This is the workflow-friendly exception to the
"skips-must-be-visible" rule. Developers commonly start a test as
`dev.something.rb`, iterate on it, then rename it when ready —
without that intermediate file being treated as a failed/skipped
test.

The filename itself is the explicit record: anyone reading the
directory listing sees `dev.foo.charlie` and knows "this is
in-development, not a test yet." The convention is the
acknowledgment.

**Two complementary mechanisms:**

| Want to... | Use |
|---|---|
| Mark an in-progress, not-yet-a-test file | `dev.` prefix |
| Deliberately skip a finished test | `files: { "name": false }` in `bryton.json` |

---

<a id="aggregator-directories"></a>
## 3 Aggregator directories

A directory can serve as an **aggregator** by listing test trees
that live elsewhere on the filesystem. Paths in `files` are
resolved **relative to the directory containing `bryton.json`**;
absolute paths reach anywhere on disk.

```json
{
    "files": {
        "/home/miko/projects/foo/working/test": true,
        "/home/miko/projects/bar/working/test": true,
        "../baz/test": true
    }
}
```

The runner walks each listed path in turn (with all the usual
`bryton.json` discovery applied recursively at each one) and
assembles their results into the aggregator's Xeme tree as
nested children.

The Xeme tree pattern makes this work cleanly because nested
children are just nested children — the runner doesn't care where
they came from on disk. Resolution propagates failures from any
external tree up through the aggregator, the same way it does for
local children.

<a id="use-cases"></a>
### 3.1 Use cases

- A meta-test directory pulling together test trees from multiple
  sibling projects in a monorepo.
- A "full system test" suite that aggregates project-specific
  test trees.
- Dynamically assembled aggregators (see below) that find test
  roots via convention rather than hand-maintained lists.

---

<a id="dynamic-configuration-via-executable-bryton"></a>
## 4 Dynamic configuration via executable `bryton.*`

A directory's effective config can be **generated dynamically** by
an executable file matching the pattern `bryton.*` (e.g.,
`bryton.rb`, `bryton.sh`, `bryton.charlie`).

<a id="lookup-order"></a>
### 4.1 Lookup order

When the runner enters a directory, it determines that directory's
config in this order:

1. **First executable `bryton.*` found** — execute it; use its
   `stdout` (parsed as JSON) as the effective config.
2. **`bryton.json`** — if no executable found, parse this file as
   the effective config.
3. **Empty hash** — if neither exists, the directory has no
   configuration.

The first executable wins. **Multiple `bryton.*` executables in
one directory is sloppy**; the runner doesn't try to disambiguate.
If you have more than one, clean them up.

<a id="use-case-dynamic-aggregation"></a>
### 4.2 Use case: dynamic aggregation

The motivating example: writing an aggregator that finds test
directories by convention rather than hand-maintaining a list.

A developer adds a marker field to each project's `bryton.json`:

```json
{
    "all-tests": true
}
```

Then writes a script (say, `bryton.rb`) in the aggregator
directory that scans the filesystem for `bryton.json` files
containing that marker, builds a `files` hash from the matching
paths, and outputs the result as JSON:

```json
{
    "files": {
        "/home/miko/projects/foo/working/test": true,
        "/home/miko/projects/bar/working/test": true,
        "/home/miko/projects/baz/working/test": true
    }
}
```

When the runner reaches the aggregator directory, it runs the
script and uses the generated config. New test directories get
picked up automatically — no manual maintenance.

The `all-tests` marker convention is **not standardized**; it's
just an example of what a developer might do with dynamic config.
The Bryton spec doesn't define any particular marker convention;
that's up to the developer.

<a id="why-this-is-worth-the-cost"></a>
### 4.3 Why this is worth the cost

Static-config alternatives (a hand-maintained `bryton.json`
listing every test root) get stale as projects move around.
External-script alternatives (running a script that writes a
`bryton.json` before tests) involve generated-file management and
"sometimes generated, sometimes hand-edited" confusion.

The executable-`bryton.*` mechanism delegates to the shell —
something developers already know — and produces JSON config the
same shape as a static file. The lookup rule is one extra step;
the rest of the runner doesn't care whether the config came from
a static file or a script.

<a id="security-considerations"></a>
### 4.4 Security considerations

The runner executes a script in any directory it walks that has a
`bryton.*` executable. This is no worse than executing test files
themselves (which the runner also does), but it's worth being
aware of: don't run Bryton against untrusted directory trees.

---

<a id="fail-fast"></a>
## 5 Fail-fast

Setting `fail_fast: true` in any `bryton.json` tells the runner
to **stop launching new tests as soon as one fails or returns no
verdict.**

```json
{
    "fail_fast": true
}
```

<a id="what-triggers-fail-fast"></a>
### 5.1 What triggers fail-fast

A child Xeme triggers fail-fast when its `success` is not `true`.
That covers two cases:

- **`success: false`** — a real failure (assertion failed,
  exception raised, etc.).
- **`success: null`** — no verdict reached (test crashed, timed
  out, couldn't parse result, etc.).

Only `success: true` lets the run continue. **Skipped Xemes
(`meta.skipped: true`) are excluded** — they don't contribute to
the verdict, so they don't trigger fail-fast either, regardless
of their `success` value.

<a id="propagation"></a>
### 5.2 Propagation

`fail_fast` propagates down the directory chain. Set it once at
the root of the test tree and it applies to every subdirectory.

```json
// bryton.json at the test-tree root
{
    "fail_fast": true
}
```

A subdirectory can override by setting `fail_fast: false`
explicitly — useful when you want a particular subtree to run to
completion (collecting all failures) even though the overall run
is fail-fast.

<a id="fail_fast-children-split-behavior"></a>
### 5.3 `fail_fast: "children"` — split behavior

A third value, `"children"`, gives the directory split behavior:

```json
{
    "fail_fast": "children"
}
```

- **At this directory's level:** no fail-fast. All children run,
  even after one fails.
- **For each child:** they get `fail_fast: true` and apply it
  internally within their own subtrees.

**Use case:** isolated test groups (subdirectories) should stop
on the first failure within each group, but you still want every
group to run so you see the state of all of them — not just up to
the first failing group.

A child can still override its inherited `fail_fast: true` by
setting `fail_fast: false` (or another `"children"`) explicitly,
same as with the regular boolean form.

<a id="what-stops-means"></a>
### 5.4 What "stops" means

When fail-fast fires, the runner **stops launching new tests**.
Tests already in progress run to completion. (In the v1
single-process model, this just means the current test finishes
and no new one starts.) The final Xeme reflects all tests that
ran up to that point.

<a id="mode-interaction-with-parallel-future"></a>
### 5.5 Mode interaction with parallel (future)

When parallel execution lands, fail-fast adapts to the
fork-pool model. The rule:

- **As soon as the first finished fork reports `success` !=
  `true`,** the runner stops launching new forks.
- **All forks already in flight run to completion**, and their
  results are recorded into the final Xeme tree.
- **No in-flight cancellation.** Killing running forks would
  waste resources already spent and discard useful information.

This means the final tree from a fail-fast parallel run can
contain **more than one failure** — every test that was already
running at the moment of first-fail finishes and reports. The
"first" in fail-fast refers to launching, not to completion or
discovery.

Consequences worth knowing:

- The final Xeme tree might surface several independent failures,
  not just one. That's a feature: parallel runs often reveal more
  than serial ones would.
- Completion order isn't launch order isn't report order. Reports
  that present results in tree order (via Xeme's natural
  structure) stay readable; reports that show "as they came in"
  get jumbled.
- "Stop launching new work" is the only contract; everything
  else (in-flight handling, draining, reporting) follows from
  that.

<a id="inside-test-scripts"></a>
### 5.6 Inside test scripts

Fail-fast should be respected **inside individual test files**
too — not just by the runner between files. A test script that
runs multiple assertions should stop on the first failure when
fail-fast is in effect, rather than running every assertion in
the file.

The exact mechanism (how the language-specific Bryton utilities
read the setting and short-circuit subsequent assertions) belongs
in the testing-tools spec; flagged here so the runner-side and
script-side behaviors stay coordinated.

---

<a id="what-counts-as-a-successful-script-execution"></a>
## 6 What counts as a successful script execution

For the runner to treat a script execution as successful, **two
rules must both be met**:

1. **The script must exit with status 0.** Non-zero indicates a
   runtime failure — the script crashed, was killed, or raised an
   uncaught exception.
2. **The trailing stdout must contain an explicitly-successful
   Xeme.** The last parseable JSON object in stdout must have
   `success: true` — not absent, not null, not false. Anything
   else is a failure.

   **Stdout only has to *end* with the Xeme.** Anything else
   (print statements, debug logs, progress messages) can come
   before, and the runner ignores it. Developers benefit from the
   leniency — they can litter their scripts with `print` while
   debugging without breaking how Bryton picks up the result. The
   runner reads from the tail backward until it finds a parseable
   JSON object; that's the Xeme.

Combined outcome modes:

| What happens | Treated as | Verdict |
|---|---|---|
| File listed in `bryton.json` doesn't exist | Runtime failure — entry in `errors` with `class: "bryton/runtime/missing"` | `success: false` |
| File can't be executed at all (no exec bit, no interpreter) | Runtime failure — `class: "bryton/runtime/not-executable"` | `success: false` |
| Exit non-zero | Runtime failure — `class: "bryton/runtime/crashed"` | `success: false` |
| Exit zero, no parseable JSON at tail | Runtime failure — `class: "bryton/runtime/unparseable"` | `success: false` |
| Exit zero, trailing JSON parses but isn't a hash | Runtime failure — `class: "bryton/runtime/not-hash"` | `success: false` |
| Exit zero, Xeme `success: false` | The Xeme's declared failure (passed through) | `success: false` |
| Exit zero, Xeme `success: null` | The Xeme's declared null verdict (passed through) | `success: null` |
| Exit zero, Xeme `success: true` | **The only success case** | `success: true` |

In failure cases the runner wraps the script's output (stdout, stderr,
exit code) into the resulting Xeme's `io` field and runtime-class
fields so that downstream consumers see what happened. The original
script-emitted Xeme (if any) is preserved when it makes sense.

The "explicitly successful" rule is deliberate: silent success is
not a success. A script that outputs nothing isn't a passing
test, it's a broken test. A script that exits zero with the
trailing Xeme `{"success": null}` is signaling "I didn't reach a
verdict" — and the runner treats that honestly rather than
guessing.

---

<a id="test-script-output-xeme-vs-human"></a>
## 7 Test script output: Xeme vs human

A test script needs to output two different things depending on
context:

- **Run directly at the CLI** — output should be human-readable
  (`[success]` on pass; warnings/errors listed on fail).
- **Run by the Bryton runner** — output should be a Xeme JSON
  structure that the runner can parse and assemble into the
  result tree.

<a id="the-in_run-flag"></a>
### 7.1 The `in_run` flag

The runner signals "I'm invoking you" by setting **`in_run: true`
inside BRYTON** before invoking each test script. The script
checks this flag and switches output mode:

```
if BRYTON.in_run
    # output Xeme JSON to stdout
else
    # output human-readable summary
end
```

**Only the runner sets `in_run: true`.** A developer's shell-set
BRYTON (used for default values) won't have it, so direct CLI
invocations get human output as expected.

<a id="why-a-flag-not-brytons-presence"></a>
### 7.2 Why a flag, not BRYTON's presence

A natural-seeming alternative — "if BRYTON env var exists, output
Xeme" — would break the workflow where a developer sets BRYTON in
their shell to provide defaults across runs. With the
presence-as-signal approach, every direct test invocation would
silently switch to Xeme output, confusing the developer.

The explicit `in_run` flag is the conservative choice: BRYTON can
hold whatever the developer wants for defaults; the runner-vs-CLI
distinction is signaled by one specific key that only the runner
sets.

<a id="what-human-readable-output-looks-like"></a>
### 7.3 What "human-readable" output looks like

- **Success:** the literal string `[success]` (or similar — exact
  format spec'd by the testing-tools layer).
- **Failure:** human-readable rendering of the Xeme — typically
  warnings and errors listed in order with context.
- **No verdict reached:** human-readable note of why
  (timeout, crash, etc.).

The runner's `in_run: true` mode bypasses all of this — the
script emits Xeme JSON regardless of failure/success state.

---

<a id="the-runner-ignores-any-pre-existing-bryton"></a>
## 8 The runner ignores any pre-existing `BRYTON`

When the runner starts, it **ignores whatever `BRYTON` was set
in the invoking shell**. It builds BRYTON entirely from the
accumulated `bryton.json` chain (with propagation) and passes
that to each test process.

This means:

- **`bryton.json` is authoritative.** No env var can sneak in and
  override the test tree's configuration.
- **Reproducibility.** Running `bryton.charlie` produces the same
  behavior regardless of whatever the developer had set in their
  shell. CI and local behavior match.
- **Shell defaults still work for direct invocation.** A
  developer who sets `BRYTON=...` in their shell for use during
  standalone script runs still sees those values when running a
  test file directly — the runner just doesn't honor them.

The runner's behavior is the same as if the env var hadn't been
set in the first place. The developer's "I want defaults at the
shell level" workflow is unaffected for direct runs and silently
ignored for runner-driven runs.

---

<a id="personal-config-configbrytonconfigjson"></a>
## 9 Personal config: `~/.config/bryton/config.json`

A developer can set **personal defaults** for how scripts run
when invoked directly at the CLI. These live in
**`~/.config/bryton/config.json`** (XDG-style location).

The initial standardized shape:

```json
{
    "fail_fast": true,
    "trim": true
}
```

This says: "when I run a test directly, default to fail-fast and
trimmed output."

<a id="tags"></a>
## 10 Tags

Tags are per-node metadata used for selective test runs. A node
(directory or file) can declare its tags via the `tags` field:

```json
{
    "tags": {
        "integration": true,
        "slow": {"timeout_hint": 60},
        "experimental": "still rough"
    }
}
```

<a id="value-semantics"></a>
### 10.1 Value semantics

| Value | Meaning |
|---|---|
| Truthy (anything non-null and non-false) | Node has this tag; the value is opaque metadata |
| Falsy or absent | Node does NOT have this tag |

Bryton uses only the **keys** for filtering. The values are
developer metadata that Bryton ignores. The falsy form is handy
when juggling many tags in active editing — set a value to
`false` to temporarily disable a tag without deleting the entry.

<a id="per-node-not-propagated"></a>
### 10.2 Per-node, not propagated

**Tags are strictly per-node.** They do not propagate down the
directory chain. A directory tagged "integration" describes
THAT directory; files inside don't inherit the tag.

This matches the general posture across Xeme and Bryton: **node
metadata describes the node, not its contents.** Same as `class`,
`errors`, `location`, `name`. Tags follow the same rule.

<a id="tag-based-selection"></a>
### 10.3 Tag-based selection

When the runner is invoked with a tag filter (mechanism TBD — CLI
flag, env var, or similar), it walks the tree and runs nodes
whose own tags match. Running a tagged node runs its entire
subtree, just as if the developer had invoked the runner on that
directory directly.

The runner doesn't transitively expand the tag to descendants —
it just identifies the matching nodes and runs them. The
directory structure already provides scope; the tag adds
orthogonal metadata for which subtrees to include.

<a id="tags-travel-with-results"></a>
### 10.4 Tags travel with results

When a tagged node produces a Xeme, **its tags are included in
the Xeme's `location.tags`** (see
[Xeme § Location tags](xeme/xeme.md#location-tags)). Tags live in
`location` because that's where they came from — declared at the
source of the test, carried through to the result.

Consumers can group, filter, or report by tag — "show all failing
tests tagged 'integration'," "summarize performance per tag,"
etc.

Only the effective tag set is included (falsy declarations are
omitted from output, even if they were in the source
`bryton.json`).

Tags don't propagate in the Xeme tree any more than they do in
`bryton.json` — a tagged directory's Xeme carries the tags, but
its children's Xemes don't automatically inherit them.

<a id="which-brytonjson-keys-propagate"></a>
## 11 Which bryton.json keys propagate

The settings that flow down from a parent directory's
`bryton.json` to its subdirectories (the **allow-list**):

- **`fail_fast`** — see [Fail-fast](#fail-fast). Tree-context;
  parent's value applies to subtree unless a child overrides.
- **`bryton_env`** — by design; shallow-merged with deeper
  values overriding shallower keys.
- **`trim`** — see [Trim propagation](#trim-propagation) below.

Settings **not** on the allow-list are directory-local:

- `files`, `explicit`, `parallel`, `timeout`, `tmp_dir` — runner
  behavior for this directory only.
- Custom developer top-level fields — local by default; put
  inside `bryton_env` if propagation is wanted.

<a id="trim-propagation"></a>
### 11.1 Trim propagation

The `trim` setting (default `false`) tells consumers to **remove
successful leaves** from the Xeme tree — see
[Xeme § Trimming](xeme/xeme.md#trimming) for the rules.

When `trim: true` propagates down the chain, two things happen:

- **Test scripts emit trimmed output.** Successful tests don't
  bother including their full Xeme; the script's library trims
  before emitting.
- **Directory nodes trim incrementally.** As each child's Xeme
  comes in, the runner trims it before adding to the directory's
  result. A directory of 10,000 passing tests doesn't have to
  hold 10,000 successful-leaf Xemes in memory — it ends up with
  `{"success": true}` for the whole directory.

This is the memory-efficiency benefit of `trim` at scale. A
massive successful test run collapses to a tiny final Xeme, and
the intermediate state stays small throughout.

The default stays `false` because most workflows want to see all
results during development — trim is for production CI runs and
mass-testing scenarios where only failures matter.

<a id="official-precedence-building-bryton"></a>
## 12 Official precedence: building BRYTON

BRYTON is built by overlaying layers in a fixed precedence order.
Lowest layer first; each subsequent layer overrides the previous
(via shallow merge):

1. **factory** — built-in defaults (currently `{}`).
2. **personal config** — `~/.config/bryton/config.json`, if
   present.
3. **bryton.json at the test-tree root** — the project's base
   configuration.
4. **bryton.json at each subsequent directory level** — deeper
   directories override shallower ones, walking down toward the
   script being invoked.

The result is the BRYTON passed to the script.

**Critically: the developer's shell-set BRYTON is NOT in the
chain.** It's ignored entirely. Reproducibility comes from the
chain being built fresh on each run from project-controlled and
user-controlled sources, not from whatever happened to be in the
shell.

<a id="examples"></a>
### 12.1 Examples

**Direct CLI invocation (no runner):**

Only factory + personal config apply. No bryton.json is in play
because no runner is walking a tree.

```
factory:          {}
personal config:  {"fail_fast": true, "trim": true}
                         ↓
effective BRYTON: {"fail_fast": true, "trim": true}
```

**Runner invocation:**

All four layers apply.

```
factory:                  {}
personal config:          {"fail_fast": true, "trim": true}
bryton.json (root):       {"bryton_env": {...}, "fail_fast": false}
bryton.json (current):    {"bryton_env": {"foo": "bar"}}
in_run injected by runner: true
                                  ↓
effective BRYTON:         {
                              "fail_fast": false,
                              "trim": true,
                              "bryton_env": {..., "foo": "bar"},
                              "in_run": true
                          }
```

Notice that the root `bryton.json` overrode the personal config's
`fail_fast` setting — the project's stated preference wins over
the developer's. But `trim` survived because no bryton.json
contradicted it. **Projects enforce what they care about;
personal config fills the rest.**

<a id="why-this-resolves-the-can-of-worms"></a>
### 12.2 Why this resolves the can of worms

- **One precedence chain** that applies in both direct and
  runner-driven cases. No special cases.
- **No per-key propagation policy** — the layering itself is the
  policy. Settings flow down through layers; the bryton.json
  allow-list still governs what propagates between *directories*
  inside layer 4, but the cross-layer precedence is uniform.
- **Reproducibility where the project demands it.** A bryton.json
  setting beats personal config; a developer with quirky
  preferences can't accidentally change CI behavior because CI
  reads the same bryton.json.
- **Personal preferences where the project allows them.** Gaps in
  bryton.json are filled by personal config; developers get their
  preferred defaults without polluting the repo.
- **Shell BRYTON is out of the picture entirely.** Whatever's in
  the shell doesn't affect runner behavior; runner output depends
  only on the project's tree and the developer's personal config.

The per-language Bryton library (when used) reads the appropriate
sources and presents the result through a single BRYTON-reading
API. From the script's perspective, the settings come from the
same place regardless of which layers contributed.

The standardized field set starts small (`fail_fast`, `trim`) and
grows deliberately as new tests-affecting defaults emerge.
Additions go through review, not casual accretion.

<a id="three-tiers-of-configuration"></a>
### 12.3 Three tiers of configuration

| Tier | Where | Scope | Who reads it |
|---|---|---|---|
| **Project** | `bryton.json` in test tree | This project | Runner (always); scripts via BRYTON when run by runner |
| **Personal** | `~/.config/bryton/config.json` | This developer | Scripts when run directly at CLI |
| **Built-in** | Hard-coded defaults | Universal | Everyone, as final fallback |

<a id="resolution-order"></a>
### 12.4 Resolution order

- **Run by the runner** (`in_run: true` in BRYTON): use BRYTON
  settings. Personal config is **ignored** by the runner — same
  reproducibility reasoning as for the shell BRYTON rule.
- **Run directly** (no `in_run`): script's testing-tools library
  reads personal config and applies its defaults.
- **No personal config present**: built-in defaults apply.

<a id="per-language-reading-tools"></a>
### 12.5 Per-language reading tools

Each language used for Bryton tests (Charlie, Ruby, Python,
JavaScript, etc.) will have a small utility/library that reads
`~/.config/bryton/config.json` and exposes its values to the test
script. The reading logic is the same across languages — just
parse the JSON and expose the values — so the per-language work
is minimal.

**Important: these libraries are optional.** See below.

---

<a id="scripts-dont-need-libraries"></a>
## 13 Scripts don't need libraries

**The first-contact promise: a script that emits Xeme JSON to
stdout IS a Bryton test, period.** No library imports, no
boilerplate, no setup. Anyone with any language that can write
JSON can write a Bryton test.

```bash
#!/usr/bin/env bash
echo '{"success": true}'
```

That's a complete, working Bryton test. No `require 'bryton'`, no
`import bryton`, no nothing. The runner sees the trailing JSON,
parses it, and assembles it into the result tree.

<a id="what-the-libraries-add-when-present"></a>
### 13.1 What the libraries add (when present)

The per-language libraries are **convenience**, not requirement.
They give scripts that opt in:

- Assertion helpers (`assert`, `refute`, etc.) that build a
  proper Xeme.
- Fail-fast support (read the `fail_fast` flag and short-circuit
  remaining assertions in this script).
- Personal-config reading (apply `~/.config/bryton/config.json`
  defaults when not in a runner).
- Auto-generation of UUIDs, timestamps, locations.
- Pretty human-readable output when not in a runner.

<a id="what-bare-bones-scripts-give-up"></a>
### 13.2 What bare-bones scripts give up

A script that doesn't use a library:

- Can't easily honor `fail_fast` (no library hook to check).
- Doesn't auto-read personal config.
- Has to emit its own Xeme JSON manually.
- Doesn't get the human-vs-Xeme dual-output behavior unless it
  implements it itself.

That's all fine. The script still runs. It still produces a
valid Xeme. It still works in the runner.

<a id="why-this-matters"></a>
### 13.3 Why this matters

Bryton is **first-contact territory** — one of the surfaces where
a developer encounters Puck before deciding whether to commit to
more of it. Forcing a library import before they can write a test
would be a friction tax at the wrong moment. The promise "just
print JSON" is real, and the libraries are strictly value-add.

The per-language libraries get richer over time as Bryton's
needs grow; the bare-bones contract stays the same forever.
