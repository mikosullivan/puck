# `%engine.manifest`
<!--index: 8 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_manifest",
	"role": "spec for %engine.manifest — a hash describing the current process. Debug and introspection surface for answering 'what's happening in this process right now?'"
}}
~~~

`%engine.manifest` returns a hash describing the running process: the operating system underneath, the engine implementation, the Caspian language version, the libraries loaded so far, timing data, and (when coverage is on) coverage results. It's a debug and introspection tool — a developer asking "what's happening in this process right now?" calls `%engine.manifest` to get the answer.

Each call returns a fresh hash representing state at the moment of the call — the manifest is not a live view.

## Sections

Top-level sections in the returned hash (the exact field set is still settling):

| Section | What it covers |
|---|---|
| `process` | Process-level metadata — start time, run time, step count. |
| `os` | Operating system block — kernel, architecture, hostname. |
| `engine` | Engine implementation — name (`lucy` etc.), version, host VM. |
| `caspian` | Caspian language version. |
| `downloads` | Every object downloaded by this process via [`%puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck), keyed by URL. Each entry carries the resolved version when one is available (URL-pinned, manifest-declared, or otherwise known); entries without a version available simply omit the field. |
| `coverage` | Coverage data. Present only when [`%engine.coverage`](https://puck.uno/documentation/requirements/caspian/engine/coverage) is set; absent when coverage is off. |

## Origin of timing fields

The engine records a wall-clock timestamp at process start (this becomes `time.start`) and initializes a step counter to `0`. When `%engine.manifest` is called, the engine captures the current wall-clock timestamp (`time.stop`), computes `time.run` as the delta, and reads the current step counter. All four values are stable for a given call — they reflect the moment of the manifest call, not whatever happens between accessing the returned hash and reading its fields.

## Declaring requirements

A second purpose of the manifest, beyond runtime introspection, is to **declare what a script needs to run**. A script's manifest names the resources it requires — `%chain.stdout`, `%chain.net`, `%chain.tmp`, specific downloaded objects with version constraints, a particular engine version, etc. — and an engine starting that script reads the declared requirements and decides whether it can provide all of them. If it can't, it refuses to start rather than running the script partway and failing mid-execution against a missing capability.

The same data structure expresses both purposes: the manifest a running script EXPOSES (introspection — what's actually here right now) and the shape a script would DECLARE up front (requirements — what it needs in order to be willing to run). Same field set, same nesting, same conventions. Specifying the structure once covers both sides.

The mechanism for how a script declares its requirements (manifest header in the source file, `%engine.require`-style accumulation, a separate `manifest.casp` companion file, etc.) is still settling. The runtime-introspection side is what's spec'd today; the requirement-declaration side folds into the same structure as the design firms up.
