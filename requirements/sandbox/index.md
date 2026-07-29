# Sandboxes

*Block-scoped, temporary replacement of the process's filesystem view. Inside the block, a specified directory IS the whole filesystem; on block exit the original view is restored. Same process throughout — no fork, no IPC. Kernel-enforced via Linux mount + user namespaces, so Lua libraries and subprocess shellouts inside the block are bound by it too.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_sandbox_index",
	"role": "spec for sandboxes — block-scoped filesystem-view replacement. Enter with %fs['/path'].sandbox do ... end; on entry, the specified directory becomes the visible root and everything outside vanishes for the block's duration. Kernel mechanism is mount + user namespaces + setns; the process holds saved-view file handles from engine startup and setns() back on block exit. Availability check runs at startup and silently sets %engine.can_sandbox? to true or false; feature works when true, raises a specific install-me error when attempted while false. AppArmor profile install is a sudo step at Caspian install time.",
	"status": "spec — API (.sandbox do ... end), availability model (startup check + %engine.can_sandbox? boolean + specific install-error on use), install-posture (Caspian does NOT wrap the install; developer runs sudo cp + apparmor_parser directly, per issue 1278), and mechanism (mount+user namespaces, setns roundtrip) settled. Exact AppArmor profile file contents deferred. Sibling ideas doc at ideas/caspian/sandboxing-primitives holds the mechanism proof-of-concept and prototype notes."
}}
~~~

## API

Sandboxes are entered as a block on a `%fs` directory handle:

~~~caspian
vibecode <<EOF
{"role": "run untrusted code with only /tmp/foo visible"}
EOF
%fs['/tmp/foo'].sandbox do
	# Inside: /tmp/foo IS the whole filesystem.
	# %fs, Lua libraries called through %lua[...], and shellouts via .execute
	# all see only what's rooted at /tmp/foo.
	&do_stuff
end

# Back outside: %fs sees the full filesystem again.
&do_other_stuff
~~~

The block returns a value like any other block. Exceptions raised inside propagate out. Same process throughout — no fork, no IPC.

Sandboxes nest. Entering a second sandbox from inside a first narrows the visible root further (never widens). Exiting each block restores the immediate parent's view.

## Availability

Sandbox support depends on kernel features and, on some distros, a small operator install step (see [Install](#install) below). At engine startup, the runtime probes for the necessary capabilities and stores a boolean at `%engine.can_sandbox?`. Programs that need to adapt read that flag; programs that don't touch sandboxing never see the difference.

### Startup probe

**Runs unconditionally, silently, at engine startup.** The probe:

- Opens `/proc/self/ns/mnt` and `/proc/self/ns/user` and holds the handles for the lifetime of the process — these are the "here's the original view" bookmarks used to return from a sandbox.
- Attempts an `unshare(CLONE_NEWUSER | CLONE_NEWNS)` in a throwaway child (or a dry-run equivalent) to confirm the kernel actually permits unprivileged user namespaces on this host.
- Sets `%engine.can_sandbox?` to true on success, false on any failure.

**Silent on failure.** The engine does not log, warn, or print anything when the probe fails. Programs that don't sandbox pay no attention cost.

**Small startup cost.** The probe adds a few hundred microseconds to engine startup. Programs sensitive to cold-start latency (`caspian --version`-shaped short scripts) pay this once. Acceptable at this budget.

### The `%engine.can_sandbox?` flag

A read-only boolean. Programs check it before making structural decisions that hinge on sandboxing:

~~~caspian
if %engine.can_sandbox?
	%fs[$isolate_dir].sandbox do
		&run_untrusted $source
	end
else
	# Fall back to a lower-trust mode, or refuse to run untrusted code.
	&refuse "sandboxing not available on this host"
end
~~~

Programs that always require sandboxing don't need the check — they can call `.sandbox do ... end` directly and let the runtime raise if unavailable.

### Error at use when unavailable

Calling `.sandbox` when `%engine.can_sandbox?` is false raises `puck.uno/sandbox/error/unavailable`. The error names what needs to be installed and points at the upstream docs. It does NOT wrap the install in a Caspian subcommand — the developer runs the install commands directly, the same way they'd install any other host utility:

~~~
Sandboxing is not available on this host.

Caspian ships an AppArmor profile at:
	/usr/share/caspian/apparmor/caspian.profile

To enable, install it:
	sudo cp /usr/share/caspian/apparmor/caspian.profile /etc/apparmor.d/
	sudo apparmor_parser -r /etc/apparmor.d/caspian.profile

Background: Ubuntu 24.04+ blocks unprivileged user namespace calls
by default (kernel.apparmor_restrict_unprivileged_userns=1). The
shipped profile carves out an exception for Caspian without loosening
the systemwide setting.

AppArmor documentation:
	https://ubuntu.com/server/docs/apparmor
	https://gitlab.com/apparmor/apparmor/-/wikis/home
~~~

The exact wording is settled by the developer-error-message pass. Requirements: name the file to install, give the exact `cp` + `apparmor_parser` commands, explain what the profile does, link to AppArmor's official docs.

## Install

Sandbox availability requires two host-level conditions:

- **Kernel supports mount + user namespaces + `setns()`.** Universal on any Linux 3.8+ (2013).
- **The kernel or its LSM (AppArmor, SELinux, Yama) permits unprivileged user namespace calls from the Caspian binary.** Universal on most distros; **not** default on Ubuntu 24.04+, which sets `kernel.apparmor_restrict_unprivileged_userns=1`.

Where the LSM restricts unprivileged userns, Caspian ships an AppArmor profile that grants Caspian the specific capability. The profile file lives at `/usr/share/caspian/apparmor/caspian.profile` after a Caspian install. The developer installs it themselves — Caspian does NOT wrap the install in a helper subcommand:

~~~
sudo cp /usr/share/caspian/apparmor/caspian.profile /etc/apparmor.d/
sudo apparmor_parser -r /etc/apparmor.d/caspian.profile
~~~

That's it. Two commands, both standard `cp` and `apparmor_parser` — nothing Caspian-specific about the mechanism. Developers already know how to run sudo; they don't need a wrapper. For background on AppArmor profile management, see [Ubuntu's AppArmor docs](https://ubuntu.com/server/docs/apparmor) or the [upstream AppArmor wiki](https://gitlab.com/apparmor/apparmor/-/wikis/home).

Distros without AppArmor (or where `kernel.unprivileged_userns_clone=1` is already set) don't need the install step; the startup probe succeeds without it.

### Verifying the install

~~~
caspian --self-test sandbox
~~~

Runs under the [self-test](https://puck.uno/requirements/installation/self-test/) framework — non-privileged, read-only, no side effects. Prints:

- **`sandbox: available`** if the startup probe would succeed.
- **`sandbox: unavailable — <reason>`** with a specific reason if it wouldn't. Reasons: `apparmor profile not installed`, `unprivileged userns disabled at kernel`, `mount namespace unavailable`, etc.

Exit code 0 for available, non-zero for unavailable — usable in shell scripts and CI setup.

`--self-test sandbox` is a **probe**, not an installer — it does not modify the system. Any actual install is a separate developer action following the `cp` + `apparmor_parser` recipe above.

## Mechanism

Discussed in detail at [ideas/caspian/sandboxing-primitives](https://puck.uno/ideas/caspian/sandboxing-primitives). Summary of what the engine does:

**On `.sandbox do ... end` entry:**

1. `unshare(CLONE_NEWUSER | CLONE_NEWNS)` — kernel gives this process a private copy of the filesystem-view and user tables. No fork; same process, private view.
2. Restructure the mount table so the target directory becomes root (`pivot_root` or bind-mount over a tmpfs at `/`). Set up minimal `/proc/self`, minimal `/dev` (null, zero, urandom, tty), and whatever else the design pins down.
3. Run the block body. Every filesystem call — Caspian's `%fs`, Lua libraries via `%lua[...]`, shellouts via `.execute`, C extensions calling libc directly — sees only what's in the sandbox. Kernel-enforced at the syscall boundary.

**On block exit (normal or exception):**

4. `setns(saved_user_fd, CLONE_NEWUSER)` and `setns(saved_mnt_fd, CLONE_NEWNS)` — kernel moves the process back to the original view. Same process. Private view is discarded once no fd holds it open.
5. Execution continues after the block with full filesystem access.

## What sandboxing is not

- **Not a full-syscall sandbox.** Sandbox restricts filesystem view only. A block inside a sandbox can still open network sockets, run subprocesses, allocate memory. Constraining those is the role of [grants](https://puck.uno/requirements/roles/) and `%chain`, which compose with sandboxing but are separate concerns.
- **Not a security boundary against the same-process attacker.** A malicious Lua library called from inside the sandbox that finds a kernel escape or manipulates the engine's saved fds is not stopped by this mechanism. Sandboxes give a bounded filesystem view; they don't turn user code into hostile-code territory.
- **Not a resource cap.** No CPU limit, no memory limit, no wall-clock limit. Cgroups is a separate mechanism; not part of the sandbox surface.
- **Not cross-platform.** Linux-only. macOS and Windows have different sandboxing primitives (`sandbox_init` on macOS, AppContainer on Windows); if Caspian ever targets them, the abstraction may broaden, but for V1 the surface is Linux-native.

## Design decisions

Documented so future readers see what was decided vs. what was left open.

- **AppArmor is V1's LSM story.** SELinux and Landlock exist and could each be a bring-along path — SELinux for hosts running enforcing mode, Landlock as a kernel-native alternative that doesn't need a policy install. V1 ships an AppArmor profile only. Post-V1, either can be added.
- **Silent fail at startup.** Alternative was log-at-DEBUG. Silent wins because the vast majority of Caspian programs never touch sandboxing; a debug log line about the availability check is noise. Programs that care read `%engine.can_sandbox?`.
- **Startup handle acquisition is unconditional.** Alternative was lazy — open the handles on first `.sandbox` call. Unconditional wins because the handles must reflect the process's *original* mount/user view, and grabbing them lazily after an arbitrary amount of prior code has run risks capturing a later state. Cheap.
- **No Caspian-wrapped install helper.** Alternatives were a `sudo caspian install-sandbox` subcommand or an apt-package (`apt install caspian-sandbox`). Rejected in favor of telling the developer to run `sudo cp` + `sudo apparmor_parser -r` directly. Developers know sudo; wrapping standard host-admin commands in a Caspian subcommand is nanny code. Caspian's responsibility ends at shipping the profile file and pointing at AppArmor's docs for the mechanism.

## Open questions

- **AppArmor profile file contents.** The profile carves out the specific `unshare(CLONE_NEWUSER)` path for Caspian. Exact rules pending review — probably `abi <abi/4.0>` header, `include <tunables/global>`, then a profile block targeting the caspian binary's install path.
- **Handling multiple Caspian versions installed on the same host.** If two Caspians are installed (e.g. system-wide and per-user), do they share the profile or does each have its own? Probably shared, keyed by absolute binary path — but the install command must handle "profile already exists at target path" without failing.
- **What lives at `%fs['/tmp/foo'].sandbox`.** The `%fs['path']` handle already exists as the [dirs](https://puck.uno/requirements/filesystem/dirs/) surface. Adding `.sandbox` as a block-taking method on it is straightforward, but the interaction with existing `%fs` methods called on the same handle from outside the block needs to be pinned down. (Nothing should break; just needs the test cases.)
- **Uninstall path.** Rolling back the profile is `sudo rm /etc/apparmor.d/caspian.profile` followed by `sudo apparmor_parser -R /etc/apparmor.d/caspian.profile` (upper-case `-R` to remove). Same "developer runs it themselves" posture as install; no wrapping subcommand.
- **Bwrap and Landlock as alternate mechanisms.** V1 is AppArmor + user namespaces. Whether the same `%fs['/path'].sandbox do ... end` surface can dispatch to bwrap or Landlock behind the scenes on hosts where those are the right fit — settled post-V1.

## Related

- [ideas/caspian/sandboxing-primitives](https://puck.uno/ideas/caspian/sandboxing-primitives) — mechanism proof-of-concept and prototype notes.
- [concepts § Lean on installed Linux utilities](https://puck.uno/requirements/concepts#lean-on-installed-linux-utilities-when-theyre-better) — the design principle this fits under (kernel is the "utility", AppArmor is the profile that lets Caspian reach it).
- [roles](https://puck.uno/requirements/roles/) — the grant model that composes with sandboxing for full-surface confinement.
- [filesystem/dirs](https://puck.uno/requirements/filesystem/dirs/) — the `%fs['/path']` handle that carries the `.sandbox` method.
- [linux/cli/openssl](https://puck.uno/requirements/linux/cli/openssl) — parallel case of a Caspian feature that leans on host-provided infrastructure.
