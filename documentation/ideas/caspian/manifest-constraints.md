# Manifest as a constraints file

*Deferred from V1.0. Idea: the JSON shape that `%engine.manifest` emits could also be authored by hand and checked into a project as a constraints file — a declaration of what versions and capabilities the code expects to run on.*

~~~vibecode
{"vibecode": {
	"doc": "idea_manifest_constraints",
	"role": "design sketch for using the %engine.manifest JSON shape as an author-written constraints file; deferred from V1.0 because the lifecycle/loading/enforcement model wasn't worth pinning down for the initial slice",
	"status": "deferred_from_v1_revisit_later",
	"v1_decision_date": "2026-06-03",
	"v1_decision_rationale": "juice_not_worth_squeeze_lifecycle_underspecified",
	"related_spec": "https://puck.uno/documentation/requirements/caspian/engine/manifest"
}}
~~~

## Status

**Deferred from V1.0** on 2026-06-03. The `%engine.manifest` report stays in V1.0 as a runtime introspection tool. The constraints-file half — authoring a manifest by hand to declare acceptable environments — is moved here until the use case justifies the lifecycle design work.

## The idea

`%engine.manifest` emits a JSON hash describing the running process: OS, engine, Caspian version, loaded libs. The same hash structure could be written by hand and committed to a project as a constraints file declaring "this code expects to run on environments matching this shape." The two uses share one format:

- **Runtime report** (what the engine emits): concrete values for every field. *What's actually happening, observed.*
- **Constraints file** (author-written): same field structure, plus optional **`range`** fields expressing acceptable version ranges for libraries, the engine, the OS, and Caspian itself. *What would also be acceptable, declared.*

A `range` is a sibling of the concrete value it constrains. Example:

```json
"engine": {
    "name": "Lua",
    "version": "3.302.29",
    "range": { ... }
}
```

The engine never emits ranges — it reports actuals. Ranges are author intent.

## Why deferred

The shape was well-defined. The **lifecycle** wasn't. Open questions at the time of deferral:

- **Where does the file live?** Project root? Beside the script? Specific filename convention?
- **Who reads it?** The engine at startup? The script via explicit call? An external tool only?
- **When is the check?** Process start? On every `%puck[uns]` lookup? On demand?
- **What happens on mismatch?** Raise? Warn? Refuse to start?
- **What's the `range` syntax?** Single bound, lower/upper, semver-style expression, set-of-allowed-values?

Plausible lifecycle models (none settled):

1. **Engine auto-discovers and enforces.** Looks for a conventional filename at startup, raises on mismatch. Magic-but-low-friction.
2. **Script explicitly loads constraints.** `%engine.constraints("path")` near the top of the program. Verbose but visible.
3. **External tool only.** Engine never reads the file; CI/IDE/package-manager handles validation against `%engine.manifest` output. Engine stays unaware.
4. **Hybrid.** External tools do the validation by default; engine optionally warns on mismatch but doesn't refuse to run.

Each model has different ergonomics, different failure modes, and a different blast radius for getting it wrong. Pinning the wrong one down too early would lock in friction.

## What relevance looks like in practice

For most Caspian programs, the only constraints worth expressing are **Caspian + Caspian libraries**. The language is designed so programs depend on Caspian and its loaded libs, not on the host underneath. So the typical constraints file would have just a `caspian` section.

Minority cases (host-FFI consumers, engine-specific extensions, OS-dependent code) would also use `os` and/or `engine` sections. The shared shape leaves room for these without forcing them on programs that don't need them.

`process` (runtime, steps) is never a deployment constraint — it's observation, not requirement. Constraints files wouldn't carry it.

## When to revisit

Pick this back up when one of these becomes true:

- Multiple V1.0 users report wanting to express version constraints for libraries and don't have a workable workaround.
- The library-resolution layer (`%puck.sources`, fetcher routing) lands and starts surfacing version-skew bugs that constraints would catch earlier.
- Tooling demand (CI, IDE warnings, deploy-time checks) accumulates around "is this code compatible with this environment."

Until one of those forcing functions appears, the deferral holds.

## See also

- [`%engine.manifest`](https://puck.uno/documentation/requirements/caspian/engine/manifest) — the runtime report half, which stays in V1.0.
- [Caspian versioning](https://puck.uno/documentation/requirements/caspian/versioning/) — how a program selects which version of a library to look up. Adjacent to the constraints-file concern.
- [Downloads / `%puck` sources](https://puck.uno/documentation/requirements/caspian/downloads/) — the fetch-and-cache layer where library version choices manifest at runtime.
