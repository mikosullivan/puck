# Chroot dirjails

*Strengthening dirjails with OS-level `chroot` enforcement (via unprivileged user namespaces, `bwrap`-style). Currently dirjails are Caspian-level — the runtime checks paths but spawned processes have the user's normal OS access. A real OS chroot would apply to processes spawned via `.execute`, so external programs like `tar` couldn't escape the jail via absolute paths in argv. Deferred to post-V1; complexity makes it a whole subsystem.*

~~~vibecode
{"vibecode": {
	"doc": "idea_chroot_dirjails",
	"role": "brainstorm for OS-level chroot enforcement of dirjails, via unprivileged user namespaces on Linux (à la bwrap). Would close the hole where processes spawned via .execute can escape a Caspian dirjail through absolute-path argv. Surfaced during self-test tar-extraction design. Deferred post-V1 due to subsystem complexity — namespace setup, bind-mounts for reachable binaries, portability.",
	"status": "brainstorm — flagged during self-test tar-extraction design; deferred post-V1"
}}
~~~

## Hurdles to name when we come back

- `chroot(2)` needs `CAP_SYS_CHROOT` (root) — unprivileged user namespaces (Linux 3.8+) are the modern path.
- Only affects spawned processes; a running Caspian can't be chrooted mid-execution.
- The invoked program has to be reachable inside the chroot (bind-mount the search path, copy the binary in, or `fexecve`-style open-fd exec).
- Linux-only; macOS/Windows would need different mechanisms.

## API sketch options

- **Opt-in per call:** `$tmp.execute 'tar', args..., chroot: true`.
- **Chroot-by-default when `.execute` runs on a dirjail:** silent hardening, but forces always-bind-mounting the search path.
- **Separate method:** `$tmp.execute_isolated 'tar', args...`. Two methods, caller picks the tradeoff.
