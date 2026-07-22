# Sandboxes

~~~vibecode
{"vibecode": {
	"doc": "ideas_sandboxes",
	"role": "proposal for 'sandboxes' — a Caspian mechanism for running a block inside a temporarily-replaced world, where the entire filesystem view IS the specified directory. Sandboxes are entered via `%fs['/path'].sandbox do ... end`, run the block with that dir as the visible root, and on block exit restore the process's original filesystem view. Same process throughout, so return values and exceptions propagate normally. Kernel-enforced via Linux mount + user namespaces + setns, so Lua libraries and subprocess shellouts inside the sandbox are bound by it too.",
	"status": "deferred until after V1 — API shape and mechanism settled, prototype at prototypes/sandbox/ confirmed the design works at the kernel level. Ubuntu ≥24.04 blocks the follow-on setgroups/uid_map writes via AppArmor by default (kernel.apparmor_restrict_unprivileged_userns=1), which means sandbox availability on Ubuntu requires either a shipped AppArmor profile (needs root at install) or a user sysctl override. Rather than solve that tension for V1, the whole feature is deferred; revisit post-V1."
}}
~~~

A **sandbox** is a block-scoped, temporary replacement of the entire filesystem view. Inside a sandbox, the specified directory IS the world — everything outside is invisible. When the block exits, the process's original filesystem view is restored and code continues normally.

## API

~~~caspian
%fs['/tmp/foo'].sandbox do
	# Inside the block, /tmp/foo/ IS the whole filesystem.
	# The block sees a world rooted at /tmp/foo and nothing outside it.
	# Any Lua library called here, any subprocess shelled out — all bounded.
	&do_stuff
end

# Back outside the block, %fs sees the full filesystem again.
&do_other_stuff
~~~

The block returns a value like any other block. Exceptions raised inside propagate out. Same process throughout — no fork, no IPC.

## Under the hood

The mechanism is Linux mount + user namespaces with `setns()` for the return trip.

**At Caspian engine startup**, the engine opens and holds two file handles: `/proc/self/ns/mnt` and `/proc/self/ns/user`. These are the "here's the original view" bookmarks used to return home later.

**On `.sandbox do ... end` entry:**

1. `unshare(CLONE_NEWUSER | CLONE_NEWNS)` — kernel gives this process a private copy of the filesystem-view table and user table. The process does NOT fork; it's the same process, now with a private view only it can see or modify.
2. Restructure the mount table so the specified directory becomes root — either `pivot_root` into it, or mount a fresh tmpfs at `/` and bind the specified directory over it. Also set up minimal `/proc/self`, minimal `/dev` (null, zero, urandom, tty), and whatever else the design pins down. Nothing else from the outside filesystem is visible.
3. Run the block body. Every filesystem call — Caspian's own `%fs`, Lua libraries via `%lua[...]`, shellouts via `.execute`, any C extension calling libc directly — sees only what's in the sandbox. The kernel enforces this at the syscall level.

**On block exit (normal OR exception):**

4. `setns(saved_user_fd, CLONE_NEWUSER)` and `setns(saved_mnt_fd, CLONE_NEWNS)`. Kernel moves this process back to the original filesystem view. Same process. The sandbox's private view is discarded once no fd holds it open.
5. Execution continues after the block with full filesystem access, as if the block had never happened.

## OS requirements

Sandboxes are a Linux-only mechanism. The kernel needs:

- **Mount namespaces** — Linux 2.4+. Universal on any current distro.
- **User namespaces + `setns()`** — Linux 3.8+ (2013). Universal on any current distro.
- **Unprivileged user namespaces enabled** — the sysctl `kernel.unprivileged_userns_clone=1`, or the equivalent kernel build option (`CONFIG_USER_NS=y` plus no runtime restriction). Enabled by default on most distros; some hardened kernels ship it disabled.
- **`pivot_root(2)` available** — has been in Linux since ≈1998. Universal.

The mechanism does NOT need:

- **Root.** Everything happens through the unprivileged user-namespace path.
- **External binaries** (bubblewrap, bwrap, unshare(1), nsenter). Caspian wraps the syscalls directly.
- **SELinux, cgroups, or seccomp.** None participate in sandbox semantics. They may be present or absent independently.

## Passing data in and out

Two channels, both natural:

- **Return value.** The block returns a value like any other block. Whatever the last expression evaluates to (or `%call.return`s) flows out to the caller.
- **Files.** The sandbox's root directory existed before entry and exists after exit. Files written inside persist. Callers can inspect the directory from outside after the block returns to see what was created.

If the caller needs a specific outside file visible INSIDE the sandbox, the simplest posture is: copy it into the sandbox's dir before entering. A future extension could add a `bind:` kwarg for read-only bind-mounts of specific outside paths, but that's not V1.

## What Caspian has to build

One small C helper — probably 200-400 lines, wrapping the namespace syscalls into "enter sandbox" and "leave sandbox" primitives. Ships as a Cache-tier `lua-sandbox` (or similar) file at ≈25 kb compiled and stripped. The Caspian-level API — `%fs['/path'].sandbox do ... end` — is a thin wrapper around that helper.

Alternative rejected: shell out to [`bwrap`](https://github.com/containers/bubblewrap). Zero bundled cost, but the block body would run in a child process, breaking the same-process return-value semantics that make sandboxes cleaner than fork-on-entry.

## Prototype worth spinning before spec

Before promoting to a formal spec, confirm end-to-end on current Linux:

1. Small C program (or a Lua-via-luaposix script) that: opens `/proc/self/ns/{mnt,user}`; calls `unshare(CLONE_NEWUSER|CLONE_NEWNS)`; sets up the UID map; mounts a tmpfs and bind-mounts one directory over it; forks a subprocess that tries to read `/etc/passwd` (should fail — no longer visible); then calls `setns()` back to the saved namespaces; forks another subprocess that reads `/etc/passwd` (should succeed — visible again).
2. If step 1 works on Debian ≥12, Fedora ≥38, Arch, and Alpine, the design is viable. If it fails on any of those for reasons we don't understand, back to the drawing board.
3. If step 1 works, measure enter-exit latency on realistic hardware. Ballpark expectation is tens of microseconds. Anything above ≈1 ms is worth investigating.

## Open questions

- **Threading.** `setns()` on a mount namespace requires the calling thread to be single-threaded in its thread group. Caspian is single-threaded by default, so this fits — but it forbids `.sandbox` inside code that's using OS threads via a Lua library.
- **PID namespace is one-way.** Don't unshare it. Only mount + user are needed for sandbox semantics, and both round-trip cleanly.
- **`/proc`, `/dev`, `/sys` visibility.** A sandbox probably wants `/proc/self`, minimal `/dev` (null, zero, urandom, tty), and no `/sys` or other-process `/proc` entries. Standard container-setup work; needs spec.
- **Signal handling.** Signals sent to the process from outside its sandbox are unaffected (signals don't respect namespaces the way filesystem calls do).
- **Enter + exit cost.** A handful of syscalls plus mount setup. Expected on the order of tens of microseconds.
- **What if the specified dir doesn't exist?** Raise on entry, or auto-create with a kwarg? Design decision.
- **Nested sandboxes.** `.sandbox` inside a `.sandbox`. Straightforward with save-fd-per-level; needs spec.
- **Which roles can create a sandbox.** Undecided.
- **Injecting outside files into the sandbox.** Copy-in-before-entry is simplest; a `bind:` kwarg for read-only bind-mounts is a future option.

## Related tooling

- **[bubblewrap](https://github.com/containers/bubblewrap)** — reference implementation of the unprivileged-user + mount-namespace sandbox pattern. Used by Flatpak. Small C codebase, MIT licensed. Reading its source is the fastest way to see correct namespace setup.
- **[libseccomp](https://github.com/seccomp/libseccomp)** — syscall filtering. Complementary defense-in-depth, not a replacement.
- **[crun](https://github.com/containers/crun)** — an OCI runtime in C. Overkill for direct use, but its code is a reference for namespace-setup edge cases.

## Related

- [nanny-methods](nanny-methods) — the broader "how much protection is Caspian responsible for" discussion.
- [browser-caspian-sandbox](browser-caspian-sandbox) — the browser-target sandbox story; different mechanism (WASM has its own sandbox), same-shaped concern.
