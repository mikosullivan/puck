# Bryton

~~~vibecode
{"vibecode": {
	"doc": "bryton",
	"role": "overview of Bryton, Puck's language-agnostic testing framework; introduces the runner, Xeme result format, and per-language helper libraries",
	"key_concepts": ["language_agnostic_runner", "xeme_results", "per_language_helpers",
		"first_contact_surface", "json_emitting_tests"]
}}
~~~

Bryton is a software testing framework. It's the primary testing
tool for Caspian and is **language-agnostic at the runner level**
— it can execute and aggregate tests written in any language that
can emit JSON.

Bryton is also a **first-contact surface** for the Puck
ecoverse: someone can write a useful Bryton test in any language
without buying into anything else. A shell script that `echo`s a
JSON line is a complete, working Bryton test.

---

<a id="architecture"></a>
## Architecture

Bryton consists of three cooperating parts:

- **The runner** — language-agnostic. Walks a tree of test files,
  executes them, collects their Xeme output, and assembles the
  results into a final result tree.
  See [runner.md](runner.md).
- **Xeme** — the JSON-based result format. Tests emit Xemes; the
  runner consumes them; tools that display, filter, or analyze
  test results read them. Language-agnostic.
  See [xeme/index.md](xeme/index.md).
- **Per-language helper libraries** — optional. Assertion helpers
  (`assert`, `refute`, etc.), personal-config readers, fail-fast
  short-circuiting, human-vs-Xeme output switching. Convenience,
  not requirement.

Test scripts produce Xemes. The runner walks directory trees,
runs scripts, and assembles their results. The Xeme format is
the contract between them.

---

<a id="core-principles"></a>
## Core principles

<a id="tests-are-runnable-scripts"></a>
### Tests are runnable scripts

Every test file is an ordinary executable. You can run it
directly at the CLI like any script — no special runner, no
special tooling. The runner is for batch execution; it's not
required for running one.

```bash
./test_foo.casp            # works
bryton.casp ./test_foo.casp   # also works
bryton.casp path/to/dir    # runs everything in a directory
```

<a id="test-files-dont-need-a-library"></a>
### Test files don't need a library

**A script that emits Xeme JSON to stdout IS a Bryton test.** No
imports, no boilerplate, no setup. This is the first-contact
promise — the absolute minimum to participate in Bryton is one
line of JSON output.

```bash
#!/usr/bin/env bash
echo '{"success": true}'
```

Per-language libraries (when present) make scripts richer:
assertion helpers, fail-fast support, personal config reading,
human-readable output for direct invocations. **All optional.**

<a id="tree-shaped-results-from-tree-shaped-tests"></a>
### Tree-shaped results from tree-shaped tests

Tests live in a directory tree. Each file produces a Xeme; each
directory produces a Xeme that contains its children's Xemes via
`nested`. Failures propagate upward via the
[resolution rule](xeme/index.md#resolution); the runner walks the
tree from the test-tree root (marked by `bryton.root`) outward.

The structure of the result tree mirrors the structure of the
test tree. Run a single file → one Xeme. Run a directory → one
Xeme with nested results. Same data shape, different scope.

<a id="bottom-up-scaling"></a>
### Bottom-up scaling

The development workflow Bryton is designed for:

1. Fix a specific bug; run the test for that bug.
2. Once it passes, run the immediate directory of related tests.
3. Once those pass, run the directory above.
4. Continue until the whole tree passes.

Each step is just executing an existing file or directory at
broader scope. No reconfiguration, no menu of test-runner
incantations. The hierarchy of investigation matches the
hierarchy of the filesystem.

---

<a id="configuration"></a>
## Configuration

Three layers, in precedence order (lowest to highest):

1. **Factory defaults** — built-in, `{}`.
2. **Personal config** — `~/.config/bryton/config.json`. The
   developer's preferences (fail_fast, trim, etc.) for direct
   invocations.
3. **`bryton.json` chain** — per-directory configuration,
   shallow-merged through the test tree from root to leaf. The
   project's deliberate testing config.

The runner overlays these to produce the **BRYTON env var** that
each test script reads. The runner **ignores any shell-set
BRYTON** — the chain is built from scratch every run.

See [runner.md § Official precedence](runner.md#official-precedence-building-bryton)
for the full chain.

---

<a id="priorities-from-initial-design-discussion"></a>
## Priorities (from initial design discussion)

- **Ordered testing** ✅ — via `files` hash in
  [bryton.json](runner.md#brytonjson-per-directory).
- **BRYTON env var, designed cleanly this time** ✅ — see the
  [precedence chain](runner.md#official-precedence-building-bryton)
  and [scripts-don't-need-libraries](runner.md#scripts-dont-need-libraries).
- **Fail-fast** ✅ — see [Fail-fast](runner.md#fail-fast),
  including the `"children"` split-behavior form and the
  parallel-ready model.
- **Parallel-ready architecture** (without v1 implementation) ✅
  — fail-fast specifies parallel semantics; result-assembly
  doesn't assume order. Actual parallel execution comes later.

---

<a id="what-ships-in-v1"></a>
## What ships in v1

- The runner (language-agnostic).
- Xeme spec + canonical icon set.
- Caspian helper library (assertion primitives, personal-config
  reading, fail-fast support, human-output formatting).
- The standardized Bryton field set in `bryton.json` and
  `BRYTON`:
  - `files`, `explicit`, `tags`, `bryton_env`
  - `fail_fast`, `trim` (propagating)
  - `dev.*` file convention (silent ignore)
  - Executable `bryton.*` config-providers (dynamic config)
  - Aggregator support (absolute and relative paths in `files`)

What's deferred to future versions:

- Parallel execution (the architecture is ready; the
  implementation isn't there).
- Per-language libraries beyond Caspian (Ruby, Python, JS, etc.
  — small per-language work to ship).
- Test analytics and reporting tools that consume Xeme output.

---

<a id="where-to-read-more"></a>
## Where to read more

- **[Xeme](xeme/index.md)** — the JSON result format. Required
  reading for anyone writing tools that produce or consume
  Bryton results.
- **[Runner](runner.md)** — directory walking, bryton.json,
  fail-fast, tag-based selection, dynamic config, the BRYTON
  precedence chain.
- **[Icons](https://github.com/mikosullivan/puck/tree/main/documentation/caspian/packages/bryton/xeme/icons/)** — the canonical icon set shipping with
  the Xeme spec.
