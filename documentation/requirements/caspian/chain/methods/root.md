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

## Nested dirjails

Any code holding a dirjail (or a subdirectory reachable through one) can construct a **nested dirjail** — a narrower view rooted at that subdirectory:

~~~caspian
$bar = %chain.root['foo']['bar']
$bar_jail = $bar.dirjail
~~~

`$bar_jail` is a first-class dirjail object rooted at `/foo/bar` (from the perspective of the code that made it). Code holding `$bar_jail` cannot use it to reach `/foo/` or anything outside `/foo/bar` — the parent path is invisible through this handle. Reads and writes work relative to the nested root only.

### Constraining the nested dirjail

Optional kwargs on `.dirjail(...)` restrict what the nested view permits:

| Kwarg | Effect |
|---|---|
| `readonly: true` | Nested dirjail supports reads only. Any write raises. |

More kwargs may arrive as concrete use cases surface; the shape is intentionally minimal at V1.

### Nested dirjails don't get their own role

Values read through a nested dirjail carry the **original engine-provided dirjail's** role, not a role belonging to the nested view. A file read from `$bar_jail` is owned by `%chain.root`'s role, same as if it had been read directly through `$root`. This is the [narrowed-faucets rule](https://puck.uno/documentation/requirements/caspian/pipes/faucets/#narrowed-faucets-dont-add-roles) applied concretely.

The dirjail object itself (`$bar_jail`) is owned by whichever role created it — normal creator-owns for the container — but that ownership is separate from the ownership of values read through it.

### Passing a nested dirjail around

Because a nested dirjail is a first-class object, it can be passed as an argument, stored, captured in a closure. Recipients act on it under the constraints set at creation — a `readonly: true` nested dirjail stays readonly for everyone who holds it, regardless of the holder's role.

Escape isn't possible: no method on `$bar_jail` reaches paths outside its root. Handing a nested dirjail to untrusted code exposes only what's below the nested root, with only the permissions set on creation.

## Capability gating

`%chain.root` is **off by default**. The host must grant filesystem access at launch — typically via a flag like `--allow-fs` — for the surface to be present. Without the grant, `%chain.root` is `null`; code that wants to be portable across grant levels should guard with `if %chain.root`.

## `%engine` counterpart

[`%engine.dir`](../../engine/dir) is the user-only access to the program's working directory at startup. `%chain.root` is the broader filesystem surface that's reachable from other roles when granted.
