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

`%engine.root` is the user-only access to the root filesystem dirjail at engine startup — spec'd on [engine](../../engine/#one-slot-per-chain-surface). `%chain.root` is the broader filesystem surface that's reachable from other roles when granted.

## Testing

- **`%chain.root` is `null` without the grant** — without the filesystem-access grant (e.g., `--allow-fs`), `%chain.root` is `null`.
- **Default-deny across role boundaries** — a non-user role does not see `%chain.root` until the capability is explicitly granted down the chain.
- **`$root[path]` returns a file handle** — for a file within the jail, `$root['some/path.txt']` returns a file-object handle.
- **`$root[path]` returns a nested dirjail for a directory** — for a subdirectory within the jail, indexing returns a dirjail-shaped object.
- **`.write(path, bytes)` writes bytes** — writing then reading returns the same bytes.
- **`.read(path)` reads bytes** — a file present in the jail is readable through the jail.
- **`.read` on missing path raises** — reading a file that does not exist raises.
- **`.each` iterates entries** — every entry directly under the jail is yielded.
- **`.glob(pattern)` matches entries** — glob patterns behave per the filesystem-spec (e.g., `*.md`).
- **Path traversal blocked** — `$root['../etc/passwd']` raises; does not escape the jail.
- **Absolute path escape blocked** — an absolute path pointing outside the jail raises.
- **Symlink escape blocked** — a symlink whose target is outside the jail is not followed.
- **Unicode file names round-trip** — writing then reading a file whose name contains non-ASCII code points works.
- **Empty file** — `.read` on an empty file returns empty bytes; `.write` of empty bytes creates an empty file.
- **Nested dirjail rooted at subdir** — `%chain.root['foo'].dirjail` is a first-class dirjail whose root is `/foo` from its holder's perspective.
- **Nested dirjail cannot reach parent** — `$bar_jail['../']` raises; the parent path is invisible.
- **Deeper nesting** — a nested dirjail can itself be nested further; the same escape rules hold.
- **`readonly: true` — writes raise** — every write method on a `readonly: true` nested dirjail raises.
- **`readonly: true` persists across holders** — passing a readonly nested dirjail to code holding a different role does not make it writable.
- **Values read through nested dirjail carry the original root's role** — bytes read via `$bar_jail` carry the role tag of `%chain.root`, not a new role belonging to the nested holder.
- **Nested dirjail object owned by its creator** — the container's role is the creator's; distinct from the role of values read through it.
- **`%chain.root` differs from `%engine.root`** — `%chain.root` is the broader surface reachable from other roles; `%engine.root` is the user-only surface at engine startup.
- **Revoke clears the surface** — after `%chain.root` is revoked in a nested block, it is `null` inside that block and reverts on block exit.
