# `%fs` additional methods

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_fs_additions",
	"role": "spec for the methods that live on the %fs namespace beyond .root (the accessor for the underlying root dir spec'd on fs.md). Currently: .cwd (getter returns the current cwd dir; setter via %fs.cwd = $dir changes cwd — the general-dir equivalents .cd() / .cwd? live on dirs.md), .path (the executable search path), the bare-name form of .execute that walks .path, and .which for name-to-file lookup without running.",
	"status": "spec — additions catalog started; bare-name .execute exact API shape marked TBD until settled with implementation; .which name settled (named after the Unix `which` command); .cwd getter/setter settled with property-assignment on %fs, and the dir-side .cd() / .cwd? spec'd separately on dirs.md"
}}
~~~

`%fs` is the filesystem **namespace** — its primary accessor is [`%fs.root`](fs#) for the root dir handle, spec'd on [fs](fs). Beyond `.root`, `%fs` carries a small set of filesystem-adjacent methods that don't live on ordinary dirs — this page catalogs them.

All methods listed here are **user-only**, consistent with `%fs` itself.

## `.cwd`

`%fs.cwd` gets or sets the process's current working directory. The initial value is the directory the Caspian CLI was launched in.

**Reading:**

~~~caspian
$here = %fs.cwd                  # dir — the current process cwd
$config = $here['config.json']
~~~

**Setting** via property assignment on `%fs`:

~~~caspian
%fs.cwd = $some_dir              # changes the process cwd via chdir(2)
~~~

Equivalent shape on any dir is [`.cd()`](../dirs#cd) — `$some_dir.cd()` does the same thing. The property-assignment form here is the `%fs`-side idiom; the method-call form on any dir is the general-dir idiom. Two entry points, one underlying operation. See [dirs](../dirs) for `.cd()` and the sibling `.cwd?` predicate.

**User-only.** Assigning `%fs.cwd` is user-only (trivially, since `%fs` itself is user-only). The same rule applies to `$dir.cd()` on any dir — process cwd is process-global state, and letting non-user code redirect it is a privilege escalation vector. See [dirs § .cd()](../dirs#cd) for the full reasoning.

**Failure modes and process-global-scope note:** same as documented for [`.cd()`](../dirs#cd).

## `.path`

The **executable search path** — an array of directories walked, in order, when a bare-name executable lookup is requested. Populated at engine startup from the system's `PATH` environment variable.

~~~caspian
%fs.path   # => ['/usr/local/bin', '/usr/bin', '/bin', ...]
~~~

**User-only, and not exposed through derived dirjails.** `%fs` itself is user-only, so `.path` is trivially unreachable from non-user code. On top of that, a dirjail obtained from `%fs` (`%fs.root['foo'].dirjail`, or any nested view) does NOT carry `.path` at all — the search-path array is a property of `%fs` specifically, not of the filesystem in general. Non-user code that holds a passed-down dirjail can read and write files through it (subject to the dirjail's constraints) but has no way to see or influence which directories `%fs` searches for bare-name executables.

Mutation from the user role uses ordinary array operations:

~~~caspian
%fs.path.push '/opt/myapp/bin'
%fs.path.unshift '/home/me/scripts'
%fs.path = ['/only/this']
~~~

## `.execute` — bare-name form

Ordinary dir objects and file objects both have `.execute` for running an executable file (the argv-array, no-shell mechanics are spec'd on [linux-support](../../linux-support/#executing-files)). `%fs` adds a **bare-name form**: when the first argument is a bare name (no path separator), `%fs.execute` walks `.path` in order for the first match, then `exec`s it directly.

~~~caspian
$result = %fs.execute 'tar', '-xzf', 'archive.tar.gz'
~~~

Relative and absolute path arguments fall back to the ordinary resolution:

- **Bare name** (`'tar'`) — looked up via `%fs.path`.
- **Relative path** (`'./foo.casp'`) — resolved against `%fs.cwd`.
- **Absolute path** (`'/usr/bin/tar'`) — used directly.

If a bare-name lookup finds no match, the call raises.

Exact API shape TBD — the current sketch is `.execute 'name', args...`; naming and error-classing shake out with implementation.

## `.which`

Same lookup as bare-name `.execute`, but returns the file handle without running it. Useful when the caller wants to run the executable later from a specific working directory, hand it to a wrapper class, or invoke it repeatedly without re-searching:

~~~caspian
$tar_bin = %fs.which 'tar'
$build_dir.execute $tar_bin, '-xzf', 'archive.tar.gz'
~~~

If no path entry matches, the call raises.

Named after the Unix `which` command, which does exactly this — walks `PATH` and reports the first match without running it.

## Related

- [%fs](fs) — the base spec: `%fs` as a user-only dir object with the ordinary dir-object surface.
- [linux-support](../../linux-support/) — the `.execute` mechanism (subprocess-not-shell, argv-array, structured result) that these methods build on.
- [linux-support § The search path](../../linux-support/#the-search-path) — the search-path story from the executable-invocation angle.
