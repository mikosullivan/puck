# Linux support

*Spec for how Caspian scripts and classes invoke standard Linux command-line utilities — the general model that Linux-utility wrapper classes build on. Executables are invoked directly (no shell process), argv is passed as an array, the result is a structured object, and shell features like pipes/globs/redirection are not applicable. Also covers the [`%fs`](../global-methods/fs) defaults, the search path, and the user-only rule for `.execute` / `.execute_in`. Per-utility wrapper specs live under [linux/cli/](https://puck.uno/requirements/linux/cli/) — `tar`, `openssl`, and the growing list of others all delegate to the primitives covered here.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_support",
	"role": "index page for linux-support/ — how Caspian scripts and classes invoke standard Linux command-line utilities. Calling executables directly (no shell), argv-array in, structured result out. Covers %fs defaults (full-tree access + execute for CLI-launched user code), .cwd, the two exec surfaces (.execute on a file / .execute_in on a directory — the _in suffix signals that the dir becomes the child's cwd and argv paths resolve against it), search path model, the user-only rule, and the general wrapper pattern. Per-utility wrapper specs live under linux/cli/ (tar, openssl, gzip, ..., growing list).",
	"status": "spec — defaults, execute model on files/dirs, search path, user-only rule, and wrapper pattern all settled; execute-permission delegation to non-user roles deferred to a separate design"
}}
~~~

## Notes

- **The CLI by default sends the full system tree.** When Caspian is invoked from the shell, `%fs.root` defaults to the whole filesystem (`/`) — not a jailed subset. The user is running their own machine; giving their own script access to their own files is the sensible default. Sandboxed callees further down the chain still get default-deny per the usual chain rules.

- **The CLI grants execute permission by default too.** Not just read/write — the user can run executables anywhere in the tree. Combined with the full-tree default above, this means a Caspian script launched from the shell can invoke any system command (`tar`, `curl`, `git`, ...) without extra ceremony.

- **`%fs` should expose a `cwd` method.** By default, `%fs.cwd` returns the directory the CLI was launched in. That's the mental model users have when they type `caspian foo.casp` — the script cares about the directory they ran it from. Currently no method surfaces this.

## Executing files

File System Objects (class pending) expose an `execute` method:

~~~caspian
$result = $myfile.execute $param, $param

$result.status   # exit code — hopefully zero
$result.stdout
$result.stderr
# ... other handy stuff
~~~

Execution is a method on the file itself, not a global `exec` primitive — fits Caspian's object-model instincts. Callers get the file handle via `%fs.root` (or wherever), then call `.execute` with args. The result is a structured object, so scripts inspect `status` / `stdout` / `stderr` directly rather than parsing captured output.

**Not literally shelling out.** Despite the vernacular ("shell out to `tar`"), `.execute` doesn't start a shell process and hand it a command string. It `exec`s the target file directly with the given argv — same posture as Python's `subprocess.run([...])` or Ruby's `Process.spawn(*argv)`. No shell parses the arguments, so quoting bugs and injection risks that plague `system("foo " + user_input)` don't apply. This is a safety property worth stating out loud, since the vocabulary invites confusion.

## The search path

The `$myfile.execute` pattern above works when you already have a file handle. For invocations by bare name (`tar`, `gunzip`, `curl`, ...) the caller doesn't know the path — that's what a search path is for.

`%fs` carries one — an array, populated from the system's `$PATH` when the engine starts:

~~~caspian
%fs.path   # => ['/usr/local/bin', '/usr/bin', '/bin', ...]
~~~

The array is fully mutable — push, unshift, splice, replace, whatever — but **only from the `user` role**:

~~~caspian
%fs.path.push '/opt/myapp/bin'
%fs.path.unshift '/home/me/scripts'
%fs.path = ['/only/this']
~~~

`%fs` isn't passed down the chain to non-user callees by default — untrusted code has no `%fs` at all unless the user explicitly grants it. Even when the user does grant it, **`.path` stays invisible to the callee** — the search path is user-only, no read and no write. The callee holds a dirjail handle for filesystem access but has no way to see or influence which directories `%fs` searches for bare-name executables.

When a lookup by bare name is requested — `%fs.execute 'tar', ...` for the one-shot case, `%fs.which 'tar'` for a reusable file handle (see [fs-additions](../global-methods/fs-additions)) — `%fs` walks the path array in order and uses the first match. If no entry matches, the call raises.

## Executing from a directory — `.execute_in`

Directories (dirjail handles) expose `.execute_in`. First param is the program name; the rest are its args. The dir becomes the process's working directory.

~~~caspian
$dir.execute_in 'tar', '-xvzf', 'archive.tar.gz'
~~~

**Why `_in`.** The method name says out loud what the dir is doing: the child runs INSIDE `$dir`. Every relative path in argv — `'archive.tar.gz'` above — resolves against `$dir`, not against the calling script's cwd. That's POSIX-standard behavior (the child sees `$dir` as its own cwd and opens paths relative to that), but reading `$dir.execute` without the `_in` suffix, it was too easy to mistake the argv paths as being relative to the caller's frame. The rename makes the intent visible at every call site.

**Prefer absolute paths in argv** when the file's location isn't obviously `$dir`. `$other_dir.execute_in 'tar', '-xvzf', $archive.absolute_path` reads unambiguously; `$other_dir.execute_in 'tar', '-xvzf', 'archive.tar.gz'` looks like it references the caller's `archive.tar.gz` but actually references one under `$other_dir`. Same convention as Python's `subprocess.run(cwd=...)` / Ruby's `Process.spawn(chdir: ...)` — always resolve paths yourself when they're not obviously relative to the exec dir.

**Still not shelling out — no shell features.** Same posture as `$myfile.execute`: Caspian finds the target file and `exec`s it directly. That means:

- **No pipes.** `.execute_in 'ls | grep foo'` doesn't work — there's no shell to parse the `|`.
- **No globs.** `.execute_in 'rm', '*.txt'` passes the literal string `*.txt` to `rm`.
- **No `$VAR` substitution.** The string `$HOME` reaches the child verbatim.
- **No redirection.** `>`, `<`, `>>`, `2>&1` — all shell syntax, not applicable.
- **No `$(...)`, backticks, `&&`, `||`, `;`** — all shell operators.

If you need any of these, compose them in Caspian instead: call `.execute_in` multiple times and wire streams, use dirjail glob methods, expand variables in your own strings before passing them.

**External commands aren't sandboxed by the dirjail.** When `$dir.execute_in 'tar', ...` runs, the `tar` process has the user's normal OS permissions — it can read `/etc/passwd`, write to `~/`, connect to the network, whatever the user could do at the shell. The dirjail restricts what Caspian code can access via the handle; it does not restrict spawned processes. That's why **`.execute_in` is user-only**: non-user roles can't call it at all, granted or not. A dirjail passed down the chain is therefore genuinely contained — the callee simply has no way to spawn external programs from it. A future strategy for controlled delegation is a separate design; not in V1.

**Post-V1: a `.shell_in` method may come.** For the cases where you really do want a shell to parse a command string (running user-supplied commands, one-liners that lean on pipes), we may add a `.shell_in` variant later. Not in V1 — `.execute_in` is the only way in.

## Building libraries for Linux utils

The `.execute` / `.execute_in` primitives are deliberately low-level — argv in, structured result out. Real Caspian code will often want an ergonomic wrapper around a common utility: a class that builds argv, translates exit codes to structured returns or raises, and parses output into Caspian objects where useful, rather than callers hand-rolling all of that at every callsite.

These wrappers are just normal Caspian classes. Nothing special about them beyond convention — they call `.execute_in` (or the file-form `.execute`) internally. They do **not** link native libraries for the utility they wrap; the utility itself does the work.

Distributed via `%fetch` like any other class. Over time the ecoverse can grow a canonical set — hosted at whatever URLs the maintainers land on. Third parties can publish alternatives at their own domains.

Per-utility wrapper specs live at [linux/cli/](https://puck.uno/requirements/linux/cli/) — the index there carries the priority-ordered V1 list (tar, gzip, gunzip, zip, unzip, file, cut, sort, uniq, uname, pandoc, convert, 7z, bzip2) plus [openssl](https://puck.uno/requirements/linux/cli/openssl) for the Passkey subsystem. Each is a separate design pass; this page just covers the general `.execute_in` model they all delegate to.

How the first argument resolves:

- **Bare name** (`'tar'`) — looked up through `%fs.path` (the search path).
- **Relative path** (`'./foo.casp'`) — resolved against `$dir`.
- **Absolute path** (`'/usr/bin/tar'`) — used directly.

So `$dir.execute_in './foo.casp'` runs `foo.casp` from `$dir` with `$dir` as its cwd.

Concrete case: `%fs.root` is a dir handle at `/`, so `%fs.root.execute_in 'blah'` runs `blah` with `/` as the working directory. To run in the directory the CLI was launched from, chain through `.cwd`:

~~~caspian
%fs.cwd.execute_in 'blah'
~~~
