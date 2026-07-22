# Sandbox namespace round-trip prototype

Confirms that Caspian's [sandbox](https://puck.uno/documentation/ideas/caspian/sandboxing-primitives) design — same-process narrow, do work, restore — actually works on the running Linux kernel. No Caspian involvement; just C + syscalls.

## What it does

1. Saves `/proc/self/ns/mnt` and `/proc/self/ns/user` fds.
2. Reads `/etc/passwd` (baseline — should succeed).
3. `unshare(CLONE_NEWUSER | CLONE_NEWNS)` — enters a private user + mount namespace, same process.
4. Sets up UID/GID maps in the new user namespace (the setgroups-deny / uid_map / gid_map dance).
5. Marks `/` as private (defense against systemd's shared mounts).
6. `mount("tmpfs", "/etc", "tmpfs", ...)` — hides `/etc` behind an empty tmpfs.
7. Reads `/etc/passwd` (should fail — the file is now invisible).
8. `setns(saved_user_fd, CLONE_NEWUSER)` + `setns(saved_mnt_fd, CLONE_NEWNS)` — returns to the saved namespaces.
9. Reads `/etc/passwd` again (should succeed — original view restored).
10. Prints a per-check pass/fail summary and exits 0 on `PASS`, 1 on `FAIL`.

## Build and run

```sh
gcc -O2 -Wall -o sandbox main.c
./sandbox
```

No root required. Needs unprivileged user namespaces enabled — on hardened kernels this may be off (`kernel.unprivileged_userns_clone=0` or `CONFIG_USER_NS=n`), in which case Step 3 fails with `EPERM` and the program exits with a diagnostic.

## Expected output

```
Sandbox namespace round-trip prototype

Step 1: save initial namespace fds
  saved mnt fd=3, user fd=4

Step 2: baseline (before sandbox)
  baseline:                        /etc/passwd: visible, starts "root:x:0:0:root:/root:/bin/bash"

Step 3: unshare(CLONE_NEWUSER | CLONE_NEWNS)
  now in a private user + mount namespace

Step 4: set up UID/GID maps
  uid 1000 -> 0, gid 1000 -> 0 (inside the namespace)

Step 5: make / private (defense against systemd's shared mount)
  ok

Step 6: mount empty tmpfs over /etc — hides /etc/passwd
  ok

Step 7: verify sandbox is enforced
  inside sandbox:                  /etc/passwd: NOT visible (No such file or directory)

Step 8: setns back to saved namespaces
  restored

Step 9: verify full filesystem view restored
  after sandbox:                   /etc/passwd: visible, starts "root:x:0:0:root:/root:/bin/bash"

---
baseline:                   ok
sandbox hides /etc/passwd:  ok
view restored after exit:   ok
PASS — sandbox design is viable on this kernel.
```

## What a failure means

- **Step 3 unshare fails with EPERM** — unprivileged user namespaces disabled at the kernel level (`kernel.unprivileged_userns_clone=0` or `CONFIG_USER_NS=n`). Sandboxes will not work here.
- **Step 4 setgroups / uid_map write fails with EACCES or EPERM** — AppArmor restriction, not a kernel-level issue. Ubuntu 24.04+ ships with `kernel.apparmor_restrict_unprivileged_userns=1` by default, which blocks unprivileged processes from setting up user namespaces even though the kernel itself allows them. This restriction is enforced OUTSIDE of `kernel.unprivileged_userns_clone`, so both need to be checked. To bypass for testing: `sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` (runtime; not persistent). For production, either an AppArmor profile authorizing userns for the caspian binary or a persistent sysctl override.
- **Step 7 shows `/etc/passwd` still visible** — the mount over `/etc` didn't take. Most likely cause: `/` was not made private and the mount was diverted somewhere unexpected. Not observed on any tested modern distro.
- **Step 9 shows `/etc/passwd` still hidden** — `setns` back didn't move this thread out of the sandboxed mount namespace. Would break the whole design; investigate before proceeding.

## Observed on this machine

Running under Ubuntu with `kernel.apparmor_restrict_unprivileged_userns=1` (the default). The prototype gets through Step 3 (`unshare` succeeds — kernel permits user namespace creation) but fails at Step 4 (`/proc/self/setgroups` write returns EACCES — AppArmor intercepts the follow-on operations). The kernel-level userns feature is on; the AppArmor policy is what's blocking.

This is a real finding for the sandbox design: on Ubuntu ≥24.04, the OS-checks probe needs to look for AppArmor's userns restriction in addition to the kernel-level sysctl. A pass at `kernel.unprivileged_userns_clone` is necessary but not sufficient.

## Platforms worth confirming

- Debian ≥12
- Fedora ≥38
- Arch (rolling)
- Alpine
- Ubuntu LTS

Any target where this program prints `PASS` is a target where the sandbox design is viable. Any target where it doesn't is a target where sandboxes need a fallback strategy.

## Related

- [sandboxes design doc](https://puck.uno/documentation/ideas/caspian/sandboxing-primitives)
- [OS checks](https://puck.uno/documentation/requirements/caspian/installation/os-checks) — the install-time probes that map to what this prototype tests
