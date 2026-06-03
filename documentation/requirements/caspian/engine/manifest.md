# `%engine.manifest`

~~~json
{"vibecode": {
	"doc": "engine_manifest",
	"role": "spec for the %engine.manifest method, which returns a hash describing the current process (os, engine, Caspian); the same JSON shape can also serve as an author-written constraints file declaring acceptable ranges",
	"key_concepts": ["report_of_actuals", "three_layers_os_engine_caspian",
		"libs_with_per_entry_metadata", "shape_doubles_as_constraints_file_with_range_fields"]
}}
~~~

`%engine.manifest` returns a hash describing the process this Caspian script is running in: the operating system underneath, the engine implementation, and the Caspian language version plus loaded libraries.

## Structure

Top-level sections:

- `process` — information about the running process itself (runtime so far, etc.).
- `os` — the operating system.
- `engine` — the engine implementation (the program that's executing Caspian).
- `caspian` — the Caspian language and its loaded libraries.

A `coverage` section also appears when code coverage is on (see [Coverage](#coverage) below).

## Example

This is `%engine.manifest os: true` — the call with the `os` option enabled, so all four sections are present. A no-argument call would omit the `os` block (see [Options](#options) below).

<a class="copy" href="#">copy</a>

```json
{
    "process": {
        "runtime": "some timestamp",
        "cycles":  3938238
    },

    "os": {
        "name":         "Linux",
        "distribution": "Redhat",
        "version":      "33.54.6"
    },

    "engine": {
        "name":    "Lua",
        "version": "3.302.29",

        "libs": {
            "lua-lib": {}
        }
    },

    "caspian": {
        "version": "3.2.1",
        "source":  "https://caspian.uno/3.2.1",

        "libs": {
            "foo.bar/gup": [
                {
                    "version":   "2.3.45",
                    "timestamp": "2023-08-12",
                    "file":      "...",
                    "line":      343,
                    "source":    "https://sdjf.ff/adf"
                }
            ]
        }
    }
}
```

## Sections

### process

Information about the running process itself.

- `runtime` — how long the process has been running. Format TBD (ISO 8601 duration, seconds, or formatted string).
- `cycles` — total Caspian-level steps executed in this process so far, using the same step unit as [`#cycles`](../utils/cycles.md) blocks (one count per `eval` or `exec_stmt` call). Deterministic and engine-independent.

**Origin.** At process start, the engine records a wall-clock timestamp and initializes a cycle counter to `0`. `runtime` is computed as the delta between the `%engine.manifest` call and that recorded start timestamp; `cycles` is whatever the counter has accumulated since startup. Both are zero or near-zero immediately after the process begins.

**Both values are advisory.** They report how the process *is* going, not how it has to. The natural use case is **calibration for timeouts**: run the program, observe `runtime` and/or `cycles`, then set a timeout comfortably above the observed value. `cycles` is the more stable number for that purpose because it's deterministic — the same program and inputs produce the same cycle count regardless of host machine. `runtime` adds the wall-clock dimension but inherits whatever variability the machine introduced (system load, CPU speed, etc.), so it's better as a sanity check than a sole bound.

### os

**Opt-in via `os: true`** — not in the default output (see [Options](#options) for why).

- `name` — operating-system name (`Linux`, `Darwin`, `Windows`).
- `distribution` — distribution name where relevant (`Redhat`, `Ubuntu`, etc.).
- `version` — operating-system version string.

### engine

- `name` — the engine implementation's name (`Lua` for the Lua reference engine).
- `version` — that engine's version string.
- `libs` — host-language libraries loaded into the engine, keyed by library name. Per-entry contents are host-specific and currently open.

### caspian

- `version` — the version of the Caspian language spec the running script is using.
- `source` — canonical URL for that version of the spec.
- `libs` — Caspian libraries currently loaded, keyed by UNS. Each value is an **array** because multiple versions of the same UNS can be loaded simultaneously in one process. Per-entry fields:
  - `version` — the lib's version string.
  - `timestamp` — load timestamp.
  - `file` — file path the lib was loaded from. (TBD: load-site path vs library source path.)
  - `line` — line associated with the load. (TBD: line in load site vs source.)
  - `source` — the URL the lib was fetched from.

<a id="coverage"></a>
### coverage

Appears when [`%engine.coverage`](index.md) is set to a non-off value. Shows what Caspian code did **not** run since coverage was turned on — the gaps. The use case is verifying that a test suite actually exercises everything in the system; the gaps are what's missing.

The section is absent entirely when coverage is off — opting into tracking via `%engine.coverage` is what makes it appear, no separate manifest option is needed. Turning coverage off resets the recorded data; turning it back on starts fresh.

**Scope.** Coverage always tracks every loaded `.caspian` file — user code plus all libraries. There is no user-only mode; once tracking is on, every executable line in every loaded file gets a hit count maintained against it.

**The value assigned to `%engine.coverage` controls what's retained in the report:**

| Setting | Retained in report |
|---|---|
| `true` | uncovered lines only (count = 0) |
| integer `N` (≥ 0) | lines whose final hit count is ≤ `N` |
| `:all` | every executable line, with its hit count |

A few notes on the integer form:

- `0` is equivalent to `true` — keep only count-0 lines (uncovered).
- `1` keeps uncovered lines plus cold paths that ran exactly once. Useful for finding marginally-tested code.
- Higher `N` reveals more of the hot/cold gradient. Pick `N` to match what counts as "cold enough to worry about" for your test suite.

The threshold is applied at report time using the same trim-to-threshold reduction as cover-band (see [Format](#cover-band-format) below) — every line that ran is counted internally; the setting just controls what survives into the manifest.

**Option for full detail.** An option (name TBD) on `%engine.manifest` itself can override the retention setting and produce every executable line with its hit count, regardless of what `%engine.coverage` was set to. Useful for hot-path analysis or tooling that wants the unreduced picture without changing the in-process coverage setting.

<a id="block-form"></a>
**Block-form: scoped tracking.** `%engine.coverage` can also be called with a block:

```
%engine.coverage do
    $foo.bar
end
```

Within the block, coverage tracks what's actually running. When the block exits, the captured data is what subsequent `%engine.manifest` calls report. The block form scopes tracking to a specific region of execution — useful when you want to know what some particular operation touched, without the noise of the rest of the program. The retention threshold (gaps only by default) applies to the block-captured data the same way.

<a id="cover-band-format"></a>
**Format: cover-band shape.** The data is organized as a two-level hash, modeled on the [cover-band](/home/miko/projects/oberon/cover-band) Ruby library:

```
{
    "<file_path>": {
        "<line_number>": <hit_count>,
        ...
    },
    ...
}
```

- **Outer level**: file path → per-line data for that file.
- **Inner level**: line number (as a string, JSON-friendly) → hit count (integer).
- **Only executable lines are stored.** Comments, blank lines, and non-statement declarations don't appear in the inner hash at all. Absent ≠ uncovered; absent means the line isn't an executable statement.
- **Hit count `0`** means an executable line that didn't run — the gap.
- **Hit count `N > 0`** means the line ran `N` times.

The default uncovered-lines report is this same shape, reduced: lines with `hit_count > 0` are dropped, then files that end up empty are dropped, so what's left is exactly the gaps. The full-detail option emits the unreduced form.

We'll make Caspian-specific adjustments to the file-path form and any other details as the feature lands.

<a id="options"></a>
## Options

`%engine.manifest` accepts a hash of options that toggle which fields are included. The default call returns most of what the manifest can carry; a few fields are **excluded by default** and require an explicit opt-in. Two reasons a field gets held out of the default:

- **Security** — fields that could leak information you wouldn't want accidentally published in a manifest committed to a repository or sent over the wire.
- **Expense** — fields whose collection costs noticeable time or resources, where you don't want to pay that cost on every call.

Known options:

| Option | What it enables | Why opt-in |
|---|---|---|
| `os: true` | Adds the `os` section. | Security: someone could accidentally publish their OS details. |

More options will be added as additional opt-in fields land. Each gets a row here with the security or expense reason that justifies keeping it off by default.

## Dual use: same shape as a constraints file

The JSON shape `%engine.manifest` returns can also be **authored by hand** and checked into a project as a constraints file — a declaration of what versions and capabilities the code expects to run on. The two uses share one format:

- **Runtime report** (what `%engine.manifest` emits): single concrete values for every field. One OS version, one engine version, one Caspian version, etc. This is *what's actually happening* in this process, observed.
- **Constraints file** (author-written): same field structure, plus optional **range** fields that express "anything in this set is acceptable" alongside (or in place of) a single concrete value. This is *what would also be acceptable*, declared.

For example, where the runtime report shows just a concrete version, a constraints file might carry both `version` (the preferred value) and a sibling `range` field describing the acceptable set:

```json
"engine": {
    "name":    "Lua",
    "version": "3.302.29",
    "range":   { ... }
}
```

### The engine never emits ranges

`%engine.manifest` reports *actuals* — what *is*, not what *would also be acceptable*. The engine doesn't know what range a particular author considers acceptable; that's a property of the program, not of the running process. So range fields appear only in author-written constraints files. The engine's output is always a strict subset of what the format permits.

### One format, two roles, no discriminator

The two uses share one format deliberately. The same shape means a single schema to learn, a single parser/validator, and a clean comparison story: checking "does this process satisfy these constraints?" is just walking the fields, comparing concrete values from the runtime report against the constraints' ranges and concrete values.

There's no top-level `mode` flag distinguishing report from constraints. A reader knows which they're looking at by where the JSON came from — `%engine.manifest` output is actuals, a manifest file checked into a project is constraints. The implicit signal of `range`-style fields appearing (or not) reinforces the distinction. If that ambiguity ever becomes a problem in practice, a discriminator can be added; for now it's not pulling weight.

### What's in `range`

The exact shape of a `range` field — single bound, lower/upper, set-of-allowed-values, semver expression, something else — is **TBD**. The mechanism gets pinned down as the constraints-file use settles. The principle is fixed: a `range` field is a sibling of the concrete value it constrains, and `%engine.manifest` never produces one.
