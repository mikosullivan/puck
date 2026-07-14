# Linux utils

*Brainstorm for how Caspian scripts and classes invoke standard Linux command-line utilities. Surfaced by the tar.gz-extraction question in the [self-test spec](../requirements/caspian/installation/self-test/download-and-run) — we punted on "how" by hand-waving at native extraction, but the general problem is bigger: developers writing real-world Caspian code will regularly want to run `tar`, `curl`, `git`, `ffmpeg`, `jq`, and whatever else is already on the box. Bundling every capability natively doesn't scale.*

~~~vibecode
{"vibecode": {
	"doc": "idea_linux_utils",
	"role": "brainstorm for how Caspian scripts and classes invoke standard Linux command-line utilities (calling executables directly, not literally starting a shell) so we don't have to spec/bundle every OS-adjacent capability natively. Surfaced by the self-test tar.gz extraction question in installation/self-test/download-and-run.md.",
	"status": "brainstorm — collecting design notes"
}}
~~~

## Notes

- **The CLI by default sends the full system tree.** When Caspian is invoked from the shell, `%chain.root` defaults to the whole filesystem (`/`) — not a jailed subset. The user is running their own machine; giving their own script access to their own files is the sensible default. Sandboxed callees further down the chain still get default-deny per the usual chain rules.

- **The CLI grants execute permission by default too.** Not just read/write — the user can run executables anywhere in the tree. Combined with the full-tree default above, this means a Caspian script launched from the shell can invoke any system command (`tar`, `curl`, `git`, ...) without extra ceremony.

- **`%chain.root` should expose a `cwd` method.** By default, `%chain.root.cwd` returns the directory the CLI was launched in. That's the mental model users have when they type `caspian foo.casp` — the script cares about the directory they ran it from. Currently no method surfaces this.

## Executing files

File System Objects (class pending) expose an `execute` method:

~~~caspian
$result = $myfile.execute $param, $param

$result.status   # exit code — hopefully zero
$result.stdout
$result.stderr
# ... other handy stuff
~~~

Execution is a method on the file itself, not a global `exec` primitive — fits Caspian's object-model instincts. Callers get the file handle via `%chain.root` (or wherever), then call `.execute` with args. The result is a structured object, so scripts inspect `status` / `stdout` / `stderr` directly rather than parsing captured output.

**Not literally shelling out.** Despite the vernacular ("shell out to `tar`"), `.execute` doesn't start a shell process and hand it a command string. It `exec`s the target file directly with the given argv — same posture as Python's `subprocess.run([...])` or Ruby's `Process.spawn(*argv)`. No shell parses the arguments, so quoting bugs and injection risks that plague `system("foo " + user_input)` don't apply. This is a safety property worth stating out loud, since the vocabulary invites confusion.

## The search path

The `$myfile.execute` pattern above works when you already have a file handle. For invocations by bare name (`tar`, `gunzip`, `curl`, ...) the caller doesn't know the path — that's what a search path is for.

`%chain.root` carries one — an array, populated from the system's `$PATH` when the engine starts:

~~~caspian
%chain.root.path   # => ['/usr/local/bin', '/usr/bin', '/bin', ...]
~~~

The array is fully mutable — push, unshift, splice, replace, whatever — but **only from the `user` role**:

~~~caspian
%chain.root.path.push '/opt/myapp/bin'
%chain.root.path.unshift '/home/me/scripts'
%chain.root.path = ['/only/this']
~~~

`%chain.root` isn't passed down the chain to non-user callees by default — untrusted code has no `%chain.root` at all unless the user explicitly grants it. Even when the user does grant it, **`.path` stays invisible to the callee** — the search path is user-only, no read and no write. The callee holds a dirjail handle for filesystem access but has no way to see or influence which directories `%chain.root` searches for bare-name executables.

When a lookup by bare name is requested (exact API shape TBD — likely `%chain.root.execute 'tar', ...` for the one-shot case, and possibly `%chain.root.find 'tar'` for a reusable file handle), `%chain.root` walks the path array in order and uses the first match. If no entry matches, the call raises.

## Executing from a directory

Directories (dirjail handles) also expose `.execute`. First param is the program name; the rest are its args. The dir becomes the process's working directory.

~~~caspian
$dir.execute 'tar', '-xvzf', 'archive.tar.gz'
~~~

**Still not shelling out.** Same posture as `$myfile.execute` — Caspian finds the target file and `exec`s it directly. No shell parses the arguments, no globbing, no expansion.

How the first argument resolves:

- **Bare name** (`'tar'`) — looked up through `%chain.root.path` (the search path).
- **Relative path** (`'./foo.casp'`) — resolved against `$dir`.
- **Absolute path** (`'/usr/bin/tar'`) — used directly.

So `$dir.execute './foo.casp'` runs `foo.casp` from `$dir` with `$dir` as its cwd.

Concrete case: `%chain.root` is itself a dir handle, so `%chain.root.execute 'blah'` runs `blah` with `/` as the working directory. To run in the directory the CLI was launched from, chain through `.cwd`:

~~~caspian
%chain.root.cwd.execute 'blah'
~~~
