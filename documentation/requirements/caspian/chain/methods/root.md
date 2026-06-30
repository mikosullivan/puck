# `%chain.root`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_root",
	"role": "spec for %chain.root — filesystem access via dirjails and file objects. Capability-gated; absent or null without the grant."
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.root` is the program's filesystem access surface — a dirjail rooted at whatever path the host has configured as the program's filesystem root. Code holding the dirjail can read and write inside it but can't escape.

~~~caspian
$root = %chain.root
$file = $root['some/path.txt']
~~~

Operations (full spec to migrate from `requirements-old/caspian/built-in-classes/filesystem.md`):

| Operation | Purpose |
|---|---|
| `$dir[path]` | Get a file or sub-dirjail at the given relative path. |
| `$dir.write(path, bytes)` | Write bytes to a file. |
| `$dir.read(path)` | Read a file's bytes. |
| `$dir.each(...)` | Iterate entries. |
| `$dir.glob(pattern)` | Match entries by pattern. |

## Capability gating

`%chain.root` is **off by default**. The host must grant filesystem access at launch — typically via a flag like `--allow-fs` — for the surface to be present. Without the grant, `%chain.root` is `null`; code that wants to be portable across grant levels should guard with `if %chain.root`.

## `%engine` counterpart

[`%engine.dir`](../../engine/dir) is the user-only access to the program's working directory at startup. `%chain.root` is the broader filesystem surface that's reachable from other roles when granted.
