# `%engine.coverage`
<!--index: 10 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_coverage",
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

The retention setting controls **what's kept in the report**, not what's tracked — the engine instruments every loaded `.caspian` file (user code plus all libraries) regardless. The setting just decides which lines survive into the [`%engine.manifest`](manifest) `coverage` section.

## Where the output goes

Coverage data lives in the `coverage` section of [`%engine.manifest`](manifest). The section is absent entirely when coverage is off — opting into tracking via `%engine.coverage` is what makes the section appear; no separate manifest option is needed. Turning coverage off resets the recorded data; turning it back on starts fresh.

## Post-V1

V1 commits to the process-wide property form only. Finer-grained scoping (per-block, per-call, per-file, time-windowed, etc.) is on the table for post-V1 once the V1 surface has been used enough to know which granularity actually pays for its complexity. The deferred block form is one candidate; others may be added as use cases emerge.
