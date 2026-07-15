# `%fs`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_fs",
	"role": "spec for %fs — the user-only filesystem namespace. %fs itself is a namespace, not a dir: use %fs.root to reach the actual root dir handle (a dirjail rooted at wherever the host configured). Informally %fs is sometimes talked about as if it were the root dir; that's a fine shorthand in prose, but %fs.root is the correct way to get the dir handle in code. Non-user code has no %fs at all (role-level hard rule, not chain-mediated). Non-user code reaches the filesystem only through dir / dirjail objects the user hands over as ordinary values — no chain-propagation machinery involved."
}}
~~~

**User-only.** Only code running in the `user` role can call `%fs`. Non-user roles have no `%fs` at all — a call raises. This is a hard rule of the role system, distinct from chain-mediated capability propagation: `%fs` is not on the chain, doesn't propagate through frames, isn't grantable via `%chain`.

`%fs` is the user-only **filesystem namespace**. It carries the filesystem access surface (dirjail rooted at wherever the host has configured) plus a handful of filesystem-adjacent methods that don't live on ordinary dirs. To reach the actual root dir handle, use `%fs.root`:

~~~caspian
$root = %fs.root
$file = $root['some/path.txt']
~~~

Informally, prose sometimes talks about `%fs` as if it were the root dir itself — that shorthand is fine in narrative and doesn't cause problems, but in code you go through `%fs.root` to get the dir handle.

For non-user code to reach the filesystem, the user constructs a **dirjail** (via `%fs.root`, or nested via a dirjail's `.dirjail` method) and hands the dirjail to the callee as an ordinary value. Dirjails are plain Caspian objects — passing them is normal parameter passing; no chain machinery is involved. The callee holds a reference; when the reference goes out of scope, that's the end of that access path.

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
$bar = %fs.root['foo']['bar']
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

Values read through a nested dirjail carry the **original engine-provided dirjail's** role, not a role belonging to the nested view. A file read from `$bar_jail` is owned by `%fs`'s role, same as if it had been read directly through `$root`. This is the [narrowed-faucets rule](https://puck.uno/documentation/requirements/caspian/pipes/faucets/#narrowed-faucets-dont-add-roles) applied concretely.

The dirjail object itself (`$bar_jail`) is owned by whichever role created it — normal creator-owns for the container — but that ownership is separate from the ownership of values read through it.

### Passing a nested dirjail around

Because a nested dirjail is a first-class object, it can be passed as an argument, stored, captured in a closure. Recipients act on it under the constraints set at creation — a `readonly: true` nested dirjail stays readonly for everyone who holds it, regardless of the holder's role.

Escape isn't possible: no method on `$bar_jail` reaches paths outside its root. Handing a nested dirjail to untrusted code exposes only what's below the nested root, with only the permissions set on creation.

## Host-level enabling

The host can choose whether `%fs` is present at all — typically via a launch-side flag (`--allow-fs` or equivalent, exact naming TBD). When the host doesn't enable filesystem access, `%fs` is `null` even in user code; portable programs should guard with `if %fs`. This is a launch-time posture, orthogonal to the user-only rule above (which applies whenever `%fs` is present).

## `%engine` counterpart

**`%fs` is a shortcut for `%engine.fs`.** The engine-side slot is the actual thing; `%fs` is the short-form sugar that matches the `%net` / `%stdout` / `%puck` short-form family. Both are user-only; both reach the same underlying dirjail. See [engine § One slot per chain surface](../../engine/#one-slot-per-chain-surface).

(The older name `%engine.root` is retired.)

## Testing

- **`%fs` is `null` when the host hasn't enabled filesystem access** — with the launch-side enabling absent, `%fs` is `null` even in user code.
- **`%fs` raises when called from a non-user role** — a non-user frame that touches `%fs` raises; the surface is user-only regardless of any granting.
- **Non-user code with a dirjail can still use it** — a dirjail passed as a value to non-user code works from that role, subject to the constraints set at creation. The role-level rule is on `%fs` itself, not on dirjail objects the user has voluntarily handed over.
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
- **Nested dirjail rooted at subdir** — `%fs.root['foo'].dirjail` is a first-class dirjail whose root is `/foo` from its holder's perspective.
- **Nested dirjail cannot reach parent** — `$bar_jail['../']` raises; the parent path is invisible.
- **Deeper nesting** — a nested dirjail can itself be nested further; the same escape rules hold.
- **`readonly: true` — writes raise** — every write method on a `readonly: true` nested dirjail raises.
- **`readonly: true` persists across holders** — passing a readonly nested dirjail to code holding a different role does not make it writable.
- **Values read through nested dirjail carry the original root's role** — bytes read via `$bar_jail` carry the role tag of `%fs`, not a new role belonging to the nested holder.
- **Nested dirjail object owned by its creator** — the container's role is the creator's; distinct from the role of values read through it.
- **Dirjail handed to non-user code retains its constraints** — a `readonly: true` nested dirjail passed to a callee stays readonly regardless of the holder's role.
