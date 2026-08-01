# `%engine.manifest`
<!--index: 8 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_manifest",
	"role": "spec for %engine.manifest — a hash describing the current process. Serves two purposes: (1) debug and introspection surface for answering 'what's happening in this process right now?'; (2) engine-launch configuration file, the intended vehicle for project-level settings applied once at startup (parser registrations, faucet/sink setup, chain seeding, and other engine-level state) rather than repeated in every script."
}}
~~~

`%engine.manifest` returns a hash describing the running process: the operating system underneath, the engine implementation, the Caspian language version, the objects downloaded so far, and timing data. It's a debug and introspection tool — a developer asking "what's happening in this process right now?" calls `%engine.manifest` to get the answer.

Each call returns a fresh hash representing state at the moment of the call — the manifest is not a live view.

**One purpose of the manifest is to serve as a configuration file for the engine.** Beyond its role as a runtime introspection surface, the manifest is also the intended vehicle for engine-launch configuration — settings that a project applies once at startup rather than repeating in every script. Examples of what configuration might live in the manifest include [`%fetch.parsers`](https://puck.uno/requirements/non-caspian-mime-types#the-parser-registry) registrations for non-Caspian MIME types, faucet and sink setup, initial capability grants, and any other engine-level state a project wants applied automatically. This dual role — read-in configuration plus read-out state — is intentional: the same shape describes what the engine will run and what it is running. Concrete details of the configuration surface will be filled in as it stabilizes.

## Sections

The manifest has five top-level sections: `process`, `os`, `engine`, `caspian`, and `downloads`.

| Section | What it covers |
|---|---|
| `process` | Process-level metadata — timing and step count for the running process. |
| `os` | Operating system the engine is running on. |
| `engine` | Engine implementation identity — codename, version, host VM. |
| `caspian` | Caspian language version this engine implements. |
| `downloads` | Every object downloaded by this process via [`%fetch`](https://puck.uno/requirements/fetch), keyed by URL. |

## Field inventory

Every section is a hash; the fields inside each are as follows.

### `process`

~~~json
"process": {
	"time": {
		"start": "<ISO 8601 timestamp>",
		"stop": "<ISO 8601 timestamp>",
		"run": "<float seconds>"
	},
	"steps": "<integer>"
}
~~~

The engine records a wall-clock timestamp at process start (this becomes `time.start`) and initializes the step counter at `0`. When `%engine.manifest` is called, the engine captures the current wall-clock timestamp (`time.stop`), computes `time.run` as the delta, and reads the current step counter. All values are stable for a given call — they reflect the moment of the manifest call, not whatever happens between accessing the returned hash and reading its fields. <!-- STALE: step-semantics doc reference — the old %chain.steps has no current home; migration target TBD when the feature is re-defined. -->

### `os`

The exact field set under `os` **depends on the operating system**. Some fields are universal — every OS reports them — and the rest are platform-specific. `os.kernel` names the platform; which additional fields appear depends on that value.

Universal fields (present on every platform):

- `kernel` — lowercase kernel identifier (`linux`, `darwin`, `windows`, etc.). Lowercase so string comparisons in Caspian code work without case handling.
- `arch` — lowercase architecture identifier (`x86_64`, `arm64`, etc.).

Platform-specific fields fill in what makes sense for that OS. Two examples:

~~~json
"os": {
	"kernel": "linux",
	"arch": "x86_64",
	"version": "6.8.0-124-generic",
	"distro": "ubuntu",
	"distro_version": "24.04"
}
~~~

~~~json
"os": {
	"kernel": "windows",
	"arch": "x86_64",
	"product": "Windows 11 Pro",
	"product_version": "10.0.22631"
}
~~~

Platforms may add fields as it's useful to expose them. Consumers should treat missing platform-specific fields as absent rather than as an error — code doing `os.kernel == 'linux' and os.distro == 'ubuntu'` is the intended shape, not code that assumes any particular non-universal field is always present.

### `engine`

~~~json
"engine": {
	"name": "lucy",
	"version": "0.01",
	"host_vm": {
		"name": "lua",
		"version": "5.4.6"
	}
}
~~~

- `name` — engine codename (`lucy` for the Lua reference).
- `version` — engine's own version string.
- `host_vm.name` and `host_vm.version` — the host language the engine is written in. Nested rather than combined into one string so consumers can compare either half without parsing.

### `caspian`

~~~json
"caspian": {
	"version": "0.01"
}
~~~

Currently only `version` — the Caspian language spec version the engine implements. Kept as a hash rather than a scalar for consistency with the other sections and for future additions.

### `downloads`

~~~json
"downloads": {
	"https://example.com/foo": [
		{
			"version": {
				"semantic": "1.2.3",
				"timestamp": "<ISO 8601 timestamp>"
			},
			"fetched_at": "<ISO 8601 timestamp>",
			"bytes": 12345,
			"sha256": "<hex signature of the fetched bytes>",
			"via": {
				"url": "https://blockchain.puck.uno/?url=https://example.com/foo",
				"cache": true
			}
		}
	],

	"https://other.com/bar": [
		{
			"fetched_at": "<ISO 8601 timestamp>",
			"bytes": 512,
			"sha256": "<hex signature of the fetched bytes>"
		}
	]
}
~~~

- Keyed by the **object URL** — the identity the program asked for. The same process may end up fetching several different versions of the same object; each URL therefore maps to an **array of download entries**, one per distinct fetch.
- `version` — hash with two optional sub-fields. Either, both, or neither may be present:
    - `semantic` — a semver-style string when the object publishes one.
    - `timestamp` — an ISO 8601 timestamp naming the object version by moment. **This is the preferred way to state a version** for Puck objects; semantic versions are supported for objects that already use them, but timestamp versions are the recommended default.

    When neither can be resolved, the `version` field itself is omitted.
- `fetched_at` — wall-clock timestamp when the fetch completed.
- `bytes` — size of the fetched payload.
- `sha256` — signature of the fetched bytes. Present on every entry.
- `via` — optional. Records where the bytes were **actually** fetched from when the source differs from the object URL. `via.url` is the fetch endpoint; `via.cache` is a boolean saying whether the intermediary served the bytes from its own cache (`true`) or re-fetched fresh on our behalf (`false`). When the fetch came directly from the object URL, `via` is omitted.

Objects don't always come directly from the URL they live at. A separate provider layer (the blockchain registry, spec'd in its own doc [TBD]) can return a cached or intermediated copy from a different URL — the manifest records that path via the `via` field so the actual provenance is inspectable.

## Declaring requirements

A second purpose of the manifest, beyond runtime introspection, is to **declare what a script needs to run**. A script's manifest names the resources it requires — the `stdout`, `net`, `tmp` capabilities, specific downloaded objects with version constraints, a particular engine version, etc. — and an engine starting that script reads the declared requirements and decides whether it can provide all of them. If it can't, it refuses to start rather than running the script partway and failing mid-execution against a missing capability.

The same data structure expresses both purposes: the manifest a running script EXPOSES (introspection — what's actually here right now) and the shape a script would DECLARE up front (requirements — what it needs in order to be willing to run). Same field set, same nesting, same conventions. Specifying the structure once covers both sides.

The mechanism for how a script declares its requirements (manifest header in the source file, `%engine.require`-style accumulation, a separate `manifest.casp` companion file, etc.) is still settling. The runtime-introspection side is what's spec'd today; the requirement-declaration side folds into the same structure as the design firms up.

## Testing

- **`%engine.manifest` returns a hash** — the top-level value is a hash object.
- **Manifest has five sections** — `process`, `os`, `engine`, `caspian`, `downloads`.
- **Each call returns a fresh hash** — mutating one manifest hash and then calling `%engine.manifest` again returns unmutated data.
- **Manifest is a snapshot, not a live view** — a returned hash does not update when program state changes afterward.
- **`process.time.start` is set at process start** — the value doesn't change across manifest calls within one run.
- **`process.time.stop` reflects the moment of the manifest call** — two calls at different times see two different `stop` values.
- **`process.time.run` equals `stop` minus `start`** — a float in seconds.
- **`process.steps` is an integer** — the step count.
- **`process.steps` grows monotonically across manifest calls** — a later manifest has step count ≥ an earlier manifest in the same run.
- **`os.kernel` is lowercase** — on Linux, `'linux'`, not `'Linux'`.
- **`os.arch` is lowercase** — `'x86_64'`, not `'X86_64'`.
- **`os.kernel` and `os.arch` are present on every platform** — regardless of host OS.
- **On Linux, `os.distro` and `os.distro_version` may appear** — platform-specific extras.
- **On Windows, `os.product` and `os.product_version` may appear** — platform-specific extras.
- **Missing platform-specific fields are absent, not null** — code should test presence, not null.
- **`engine.name` is `'lucy'` on the Lua reference engine** — the codename.
- **`engine.version` is a string** — e.g., `'0.01'`.
- **`engine.host_vm.name` is `'lua'` on the reference engine** — the host language name.
- **`engine.host_vm.version` reports the actual Lua VM version** — e.g., `'5.4.6'`.
- **`caspian.version` is the Caspian spec version** — separate from `engine.version`.
- **`caspian` is a hash, not a bare string** — `%engine.manifest.caspian.version`, not `%engine.manifest.caspian`.
- **`downloads` is a hash keyed by URL** — `.downloads['https://example.com/foo']` returns the entry list.
- **Each `downloads` value is an array** — one entry per distinct fetch of that URL.
- **Fetching the same URL twice appends a second array entry** — the URL's array grows.
- **Each download entry has `sha256`** — always present.
- **Each download entry has `bytes` as an integer** — payload size.
- **Each download entry has `fetched_at` as an ISO 8601 string** — timestamp of the fetch.
- **`via` is absent when the fetch came directly from the object URL** — omitted, not null.
- **`via.url` names the intermediary endpoint when present** — e.g. a registry URL.
- **`via.cache` is boolean** — `true` when the intermediary served from cache; `false` when it re-fetched.
- **`version.semantic` present only for objects publishing a semver** — otherwise absent.
- **`version.timestamp` present only when the version can be resolved by timestamp** — otherwise absent.
- **When neither `version.semantic` nor `version.timestamp` resolves, `version` is omitted entirely** — not present-as-empty.
- **`downloads` is an empty hash when nothing has been downloaded** — not null.
- **`%engine.manifest` from a non-user role raises** — the blanket `%engine` gate.
- **Returned manifest hash is read-only** — mutating a field raises.
- **Reading `%engine.manifest` twice back-to-back returns different `process.time.stop`** — reflects distinct moments.
- **Reading `%engine.manifest` twice returns identical `process.time.start`** — the start is set once.
- **`downloads` reflects `%engine.require` calls** — a URL required at startup appears in `downloads` on first manifest read.
- **`downloads` reflects `%(url)` first-use loads** — objects loaded via first-use appear once fetched.
- **All values in the manifest are JSON-native** — usable directly for serialization.
