# `%engine.coverage`
<!--index: 10 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_coverage",
	"role": "spec for %engine.coverage — line-level coverage tracking. Off by default. V1 has only the property form (sets retention for the rest of the process). A block form was considered and deferred.",
	"default": "off"
}}
~~~

`%engine.coverage` is line-level coverage tracking — which lines of which Caspian files ran, and how many times. It's off by default.

## Property form

`%engine.coverage = <value>` enables tracking for the rest of the process. The assigned value controls retention — what's kept in the report:

| Value | What's retained |
|---|---|
| `true` | Only **uncovered** lines (the gaps — lines that never ran). The common case: a test suite wants to know what's missing. |
| integer `N` | Lines with hit count ≤ `N`. Filters down to lines that ran rarely or not at all. |
| `:all` | Every executable line, with its hit count. Full detail for hot-path analysis. |

The retention setting controls **what's kept in the report**, not what's tracked — the engine instruments every loaded `.caspian` file (user code plus all downloaded objects) regardless. The setting just decides which lines survive into the [`%engine.manifest`](manifest) `coverage` section.

## Where the output goes

Coverage data lives in the `coverage` section of [`%engine.manifest`](manifest). The section is absent entirely when coverage is off — opting into tracking via `%engine.coverage` is what makes the section appear; no separate manifest option is needed. Turning coverage off resets the recorded data; turning it back on starts fresh.

## Manifest field inventory

The `coverage` section is a hash keyed by file identifier (local path for user code; URL for downloaded objects). Each entry carries a `lines` hash mapping line number to hit count:

~~~json
"coverage": {
	"src/main.casp": {
		"lines": {
			"12": 4,
			"13": 4,
			"27": 0
		}
	},
	"https://example.com/widget": {
		"lines": {
			"3":  1,
			"18": 0
		}
	}
}
~~~

- Keys under `coverage` are the file's identity — a local path for source in the user's tree, a URL for anything downloaded via [`%puck`](https://puck.uno/documentation/requirements/chain/methods/puck).
- Each entry has a single field, `lines` — a hash whose keys are line numbers (as strings, per JSON) and whose values are hit counts. Only executable lines appear; blank lines, comments, and non-executable syntax are omitted.
- Which lines are retained in `lines` depends on the retention value passed to `%engine.coverage`:
    - `true` — only lines with hit count `0`.
    - integer `N` — lines with hit count ≤ `N`.
    - `:all` — every executable line.
- Files with zero retained lines are omitted from the section entirely.

## Post-V1

V1 commits to the process-wide property form only. Finer-grained scoping (per-block, per-call, per-file, time-windowed, etc.) is on the table for post-V1 once the V1 surface has been used enough to know which granularity actually pays for its complexity. The deferred block form is one candidate; others may be added as use cases emerge.

## Testing

- **Coverage is off by default** — with no assignment to `%engine.coverage`, `%engine.manifest` has no `coverage` section.
- **Assigning `true` enables uncovered-only retention** — after `%engine.coverage = true`, the manifest's `coverage` section shows only lines with hit count `0`.
- **Assigning integer `N` retains lines with hit count ≤ `N`** — after `%engine.coverage = 3`, lines that ran 4 or more times are omitted; lines with 0, 1, 2, or 3 hits appear.
- **Assigning `0` retains only lines with zero hits** — equivalent to `true` retention.
- **Assigning `:all` retains every executable line** — every executable line in every loaded file appears with its hit count.
- **Blank lines never appear in the report** — regardless of retention setting.
- **Comment-only lines never appear in the report** — regardless of retention setting.
- **Hit counts increment per execution** — a line inside a loop running 5 times reports `5` under `:all` retention.
- **Turning coverage off resets recorded data** — assigning `false` or `null` after `:all` erases the report; re-enabling starts fresh.
- **`coverage` section is absent when off** — the key is missing, not present-as-null or present-as-empty.
- **Local files are keyed by path** — `%engine.manifest.coverage['src/main.casp']` returns a `lines` hash.
- **Downloaded objects are keyed by URL** — `%engine.manifest.coverage['https://example.com/widget']` returns a `lines` hash.
- **Line numbers in `lines` are string keys** — JSON forces string keys; `.lines['12']` (string) reaches the hit count, not `.lines[12]`.
- **Files with zero retained lines are omitted from `coverage`** — a file where every line ran once under `true` (uncovered-only) retention doesn't appear.
- **Coverage instruments downloaded objects** — a `%[url]` load produces coverage entries for the downloaded file when coverage is on.
- **Coverage tracks both user files and dependencies** — a run loading two user files and three downloaded objects has entries for all five under `:all`.
- **Only executable lines appear** — a line containing only `#comment` never shows up.
- **A line that never runs has hit count `0`** — appears under `true` and `:all` retention, absent under `N` when `N` is negative (which raises).
- **A line inside a conditional branch that didn't run has hit count `0`** — a raised branch is not executed.
- **Assigning `%engine.coverage` from a non-user role raises** — the blanket `%engine` gate.
- **Assigning an unrecognized value raises** — `%engine.coverage = 'sometimes'` raises; accepted values are `true`, integer, `:all`, `false`, or `null`.
- **Assigning `false` turns coverage off** — the manifest section becomes absent; state is reset.
- **Assigning `null` also turns coverage off** — equivalent to `false`.
- **Retention setting applies process-wide** — a nested block does not restrict the setting to that block; the last assignment holds.
- **The last assignment wins** — successive assignments overwrite retention setting; only the last one determines the shape of subsequent reports.
- **A file loaded before coverage was enabled still gets tracked if it runs afterward** — instrumentation is per-line-execution, not per-file-load.
- **`%engine.manifest.coverage` for a file never loaded is absent** — no phantom entries.
- **Hit count is an integer, not a float** — `.lines['12']` returns an integer.
- **Empty file (no executable lines) produces no coverage entry** — the file doesn't appear.
- **A subsequent `%engine.manifest` call after further execution shows updated counts** — the manifest is a snapshot; new hits appear in later snapshots.
