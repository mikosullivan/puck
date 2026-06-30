# `%engine.platform`
<!--index: 5 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_platform",
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

Programs that want to branch on platform (`if %engine.platform.os == 'linux' then …`) read this hash. Libraries that want to declare host requirements do the same.
