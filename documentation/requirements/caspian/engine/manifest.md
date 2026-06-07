# `%engine.manifest`

*A debug/introspection tool. Returns a summary of the running Caspian process — what's underneath, what's loaded, how long it's been running.*

~~~json
{"vibecode": {
	"doc": "engine_manifest",
	"role": "spec for the %engine.manifest method, a debug and introspection tool that returns a summary hash describing the current process (process metadata, os, engine, Caspian and loaded libs)",
	"purpose": "debug_and_introspection_only",
	"key_concepts": ["debug_tool_not_enforcement_layer", "report_of_actuals_no_constraints",
		"four_sections_process_os_engine_caspian", "libs_with_per_entry_metadata",
		"coverage_subsection_when_coverage_is_on"]
}}
~~~

`%engine.manifest` is a **debug tool**. It returns a hash describing the running process — the operating system underneath, the engine implementation, the Caspian language version, and the loaded libraries — so a developer (or tooling on a developer's behalf) can answer "what's happening in this process right now?"

It is a *reporter*. It does not enforce anything, does not check anything against expectations, and has no opinion about whether the running process is correctly configured. Authoring expectations and checking compliance is a separate concern — see [Manifest as a constraints file](https://puck.uno/documentation/ideas/caspian/manifest-constraints) (deferred from V1.0).

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
        "steps": 3938238,
        "time": {
            "start": "2026-06-03T14:22:08.413Z",
            "stop": "2026-06-03T14:25:47.901Z",
            "run": "PT3M39.488S"
        }
    },

    "os": {
        "name": "Linux",
        "distribution": "Redhat",
        "version": "33.54.6"
    },

    "engine": {
        "name": "Lua",
        "version": "3.302.29",

        "libs": {
            "lua-lib": {},
            "libsodium": {"version": "1.0.20"}
        }
    },

    "caspian": {
        "version": "3.2.1",
        "source": "https://caspian.uno/3.2.1",

        "libs": {
            "foo.bar/gup": [
                {
                    "version": "2.3.45",
                    "timestamp": "2023-08-12",
                    "file": "...",
                    "line": 343,
                    "source": "https://sdjf.ff/adf",
                    "ranges": [{"ts_min": "2023-01-01"}, {"semver": "^2.3"}]
                }
            ]
        }
    }
}
```

## Sections

### process

Information about the running process itself.

- `time` — hash grouping the three time-related values:
  - `start` — wall-clock timestamp captured at process start. Format TBD (ISO 8601 instant most likely).
  - `stop` — wall-clock timestamp captured at the moment this manifest was generated. For a snapshot taken mid-run, this is "now"; for a manifest emitted at process exit (post-mortem), this is the actual end time. Same format as `start`.
  - `run` — duration between `start` and `stop`, pre-computed for convenience. Format TBD (ISO 8601 duration, seconds, or formatted string). Redundant with the two timestamps but saves consumers from doing date math when they just want to glance at how long things took.
- `steps` — total Caspian-level steps executed in this process so far, using the same step unit as [`%utils.steps`](../utils/steps.md) (one count per `eval` or `exec_stmt` call). Deterministic and engine-independent.

**Origin.** At process start, the engine records a wall-clock timestamp (which becomes `time.start`) and initializes a step counter to `0`. When `%engine.manifest` is called, the engine captures the current wall-clock timestamp (`time.stop`), computes `time.run` as the delta, and reads the current step counter. The three time values and the step count are stable for a given call — they reflect the moment of the manifest call, not whatever has happened in between accessing the returned hash and reading its fields.

**Both values are advisory.** They report how the process *is* going, not how it has to. The natural use case is **calibration for timeouts**: run the program, observe `runtime` and/or `steps`, then set a timeout comfortably above the observed value. `steps` is the more stable number for that purpose because it's deterministic — the same program and inputs produce the same step count regardless of host machine. `runtime` adds the wall-clock dimension but inherits whatever variability the machine introduced (system load, CPU speed, etc.), so it's better as a sanity check than a sole bound.

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
  - `ranges` — range expressions that selected this version. Empty `[]` = all contributing calls were unconstrained. Debug-only today; designed for the deferred [constraints files](https://puck.uno/documentation/ideas/caspian/manifest-constraints) feature.

~~~json
{"vibecode": {
	"field": "caspian.libs[].ranges",
	"type": "array_of_range_expressions",
	"appended_per_load_call": "each_puck_call_resolving_to_this_version_pushes_its_range_constraint",
	"entry_shape": "whatever_call_site_range_syntax_produces",
	"engine_role": "records_does_not_interpret",
	"primary_use_today": "debug_why_was_this_version_selected",
	"design_intent": "enables_deferred_constraints_files_feature_by_letting_tooling_derive_constraints_from_recorded_manifest",
	"deferred_until_then": "field_is_debug_only",
	"constraints_files_idea": "https://puck.uno/documentation/ideas/caspian/manifest-constraints"
}}
~~~

Load records are **process-level state**, not object-level — once loaded, entries persist for the life of the process regardless of scope/GC of whatever triggered them.

**Post-V1: dependency tree.** The `libs` section today is a flat hash — every loaded library appears, but the manifest doesn't say which library pulled which in. A post-V1 feature will add **dependency tracking**: for each entry, record which other entries triggered its load (the parent libraries) so callers can reconstruct the dependency tree from the manifest. Useful for supply-chain investigation, version-conflict diagnosis, and "why is this library here?" questions. Deferred from V1 because the cheap implementation depends on per-library role identity that the engine's role tracking hasn't matured into yet. Non-breaking when it lands — likely a per-entry `pulled_in_by` field or a sibling `lib_deps` hash. See [#539](https://github.com/mikosullivan/puck/issues/539) for the design sketch.

~~~json
{"vibecode": {
	"property": "load_records_are_process_level_state",
	"persistence": "lifetime_of_process",
	"decoupled_from": ["triggering_call_site_scope", "triggering_object_lifetime", "gc_of_either"],
	"survives": ["call_site_return", "local_var_scope_exit", "triggering_object_gc"],
	"records_retained": ["timestamp", "file_and_line_provenance", "accumulated_ranges"],
	"enables": "after_the_fact_debugging_of_what_was_loaded_when_from_where_under_which_constraints",
	"storage": "engine_maintains_load_records_registry_manifest_reads_from_it"
}}
~~~

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
**Format: cover-band shape.** The data is organized as a two-level hash, modeled on the cover-band Ruby library:

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

## See also

- [Manifest as a constraints file](https://puck.uno/documentation/ideas/caspian/manifest-constraints) — idea (deferred from V1.0): using the same JSON shape, authored by hand, as a project-checked-in declaration of acceptable versions/capabilities. Open lifecycle questions (where it lives, who reads it, when it's checked, what happens on mismatch) kept it out of V1.0.
