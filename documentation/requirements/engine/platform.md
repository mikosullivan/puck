# `%engine.platform`
<!--index: 5 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_platform",
	"role": "spec for %engine.platform — host platform information (operating system, engine implementation, architecture); has no global form so the %engine prefix is required"
}}
~~~

`%engine.platform` describes the host the engine is running on — operating system, CPU architecture, engine implementation, and version. It's a read-only hash; the engine fills it in at startup from what the host reports.

This is one of the slots that has no global form: there's no `%platform` shortcut. Code that needs platform information names it explicitly as `%engine.platform`.

Typical fields (more may be added as new portability concerns surface):

| Field | Meaning |
|---|---|
| `os` | Operating system name — `linux`, `darwin`, `windows`, etc. |
| `arch` | CPU architecture — `x86_64`, `aarch64`, etc. |
| `engine` | Engine implementation — `lucy` for the Lua reference engine; other names for other implementations. |
| `caspian_version` | The Caspian language version this engine implements. |

Programs that want to branch on platform (`if %engine.platform.os == 'linux' then …`) read this hash. Downloaded objects that want to declare host requirements do the same.

## Testing

- **`%engine.platform` returns a hash** — with `os`, `arch`, `engine`, and `caspian_version` fields.
- **`%engine.platform.os` is lowercase** — `'linux'`, `'darwin'`, `'windows'`; never mixed case.
- **`%engine.platform.arch` is lowercase** — `'x86_64'`, `'aarch64'`; never `'X86_64'`.
- **`%engine.platform.engine` names the implementation** — `'lucy'` for the Lua reference engine.
- **`%engine.platform.caspian_version` is a version string** — the Caspian spec the engine implements.
- **`%engine.platform` has no global shortcut** — `%platform` (bare) is not defined; only `%engine.platform` reaches this hash.
- **`%engine.platform` is read-only** — `%engine.platform.os = 'other'` raises.
- **Values are stable within a process** — reading `%engine.platform.os` at different times yields the same value.
- **Non-user role reading `%engine.platform` raises** — the blanket `%engine` gate applies.
- **Platform matches the underlying OS** — running on Linux, `.os == 'linux'` is true; on macOS, `.os == 'darwin'` is true; on Windows, `.os == 'windows'` is true.
- **`.engine == 'lucy'` on the Lua reference engine** — the engine field names the implementation, not the host language.
- **Reading the same field twice returns `==` true** — value-comparable.
- **`%engine.platform` hash object identity is stable** — successive reads return the same object.
- **New platform fields may be added over time** — a program relying on a specific field should treat missing fields as absent rather than as an error.
- **`%engine.platform` does not overlap with `%engine.manifest.os`** — they're separate surfaces with different shapes; `platform` is the flat top-level view, `manifest.os` is the richer per-OS detail.
- **`%engine.platform.engine` differs from `%engine.manifest.engine.name`** — both name the codename; the `platform` field is flat, `manifest.engine` is a hash.
