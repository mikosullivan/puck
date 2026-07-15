# Process security

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_secure_memory_process_security",
	"role": "spec for whole-process OS-level hardening options on top of the per-secret vault: mlockall (prevent any swap), PR_SET_DUMPABLE (block coredumps + tighten ptrace), Yama ptrace_scope requirement, and encrypted/disabled swap/hibernation posture. All opt-in via engine config, not default — each has real operational tradeoffs. Companion to vault.md, which protects specific known secrets; this file protects against whole classes of attacks (swap, coredumps, ptrace) that could bypass in-process protections regardless of the vault.",
	"status": "spec — settings and semantics settled; exact config-schema field names and default-refusal thresholds deferred to implementation",
	"audience": "operators deploying Caspian on security-critical hosts; engine implementers wiring up the config knobs and startup checks"
}}
~~~

Whole-process OS-level hardening on top of the per-secret [vault](vault). Every setting on this page is **deployment-level opt-in** — the engine doesn't turn them on by default because each has real operational tradeoffs.

The vault protects specific known secrets. The settings here block whole classes of attacks (swap-to-disk, coredumps, `ptrace` inspection) that could bypass in-process protections regardless of what the vault does. For deployments where sensitive material is handled broadly, where compliance frameworks require defense in depth, or where the threat model includes an attacker with local (but unprivileged) access, turning these on is the right move.

## The settings

### `mlockall` — lock all process memory in RAM

`mlockall(MCL_CURRENT | MCL_FUTURE)` pins **all** of the engine process's memory in RAM — not just the vault's specific buffers. Currently-mapped pages AND any future allocations get locked.

**What it prevents.** Any swap-to-disk of any part of the process memory. Not just secrets stored in the vault, but also intermediate copies made during parsing, temporary variables holding fragments of secrets, libc heap fragments that still contain post-`free` bytes — none can be swapped out.

**Cost.** Requires generous `RLIMIT_MEMLOCK` — the engine's entire virtual memory footprint must fit under the limit, not just the vault. Can cause OOM issues under memory pressure since the kernel can't page anything out to free RAM. Not appropriate for deployments where the memory profile is unpredictable or where the host is memory-constrained.

### `PR_SET_DUMPABLE` — disable coredumps and tighten ptrace

`prctl(PR_SET_DUMPABLE, 0)` on the engine process.

**What it does:**

- Prevents the process from being coredumped at all (the kernel refuses).
- Tightens `ptrace` restrictions per Linux's Yama LSM. A process with `dumpable = 0` can't be `ptrace`-attached by any process that doesn't have `CAP_SYS_PTRACE` (typically only root).

**Cost.** Makes engine debugging harder for legitimate operators. Attaching `gdb`, `strace`, or a debugger to inspect a running Caspian process requires root when this is on. If someone needs to debug production, they now need elevated privilege — appropriate for security-critical deployments; overkill for dev.

### Yama `ptrace_scope`

`/proc/sys/kernel/yama/ptrace_scope` is a **system-wide** sysctl. Values:

- **0**: classic `ptrace` — any process can `ptrace` any other owned by the same user.
- **1**: default on modern Linux — `ptrace` only children by default, otherwise requires a `prctl`-declared tracer.
- **2**: `ptrace` only allowed with `CAP_SYS_PTRACE`.
- **3**: `ptrace` disabled entirely (requires reboot to change back).

Not something the engine can set (system-wide, requires root). Operators set it. Documented here so security-critical deployments know to bump it to 2 or 3. The engine can be configured to **refuse to start** if the sysctl is below a required level — see the config schema below.

### Hibernation and swap

`mlock` and `mlockall` prevent normal swap. They do **not** prevent:

- **Hibernation** (suspend-to-disk): the whole RAM image is written to disk. Anything in memory lands there.
- **Coredumps from other processes** (unlikely but possible in unusual setups).
- **Explicit `mmap`-to-file writes** by the process itself (which the engine wouldn't do, but bugs happen).

For hosts handling secrets:

- **Encrypted swap** — Linux `cryptswap` or LUKS on the swap partition. Even if secrets do reach swap somehow, they're at rest under encryption.
- **Encrypted hibernation** — the hibernation image goes to the encrypted swap partition.
- **Disable hibernation** — on server deployments, the simplest option. `systemctl mask hibernate.target hybrid-sleep.target suspend-then-hibernate.target`.
- **Disable swap entirely** — for hosts where the memory profile is well-known and swap isn't operationally required.

These are OS-level settings the operator applies, independent of engine config. Documented here so security-critical deployments know to configure them.

## Engine configuration

The engine exposes these as configuration knobs, not defaults. Sketch (exact schema deferred to the engine-config spec):

~~~
{
	"secure_memory": {
		"mlockall": false,
		"prctl_dumpable": false,
		"require_ptrace_scope": 0
	}
}
~~~

- **`mlockall: true`** — call `mlockall(MCL_CURRENT | MCL_FUTURE)` at engine startup. Fails startup if the syscall fails.
- **`prctl_dumpable: true`** — call `prctl(PR_SET_DUMPABLE, 0)` at engine startup.
- **`require_ptrace_scope: N`** — refuse to start if `/proc/sys/kernel/yama/ptrace_scope` is below N. `0` means don't check.

Defaults are all "off" / "don't check" (least restrictive). Operators opt in explicitly for security-critical deployments.

## How this supports the HTTP intake use case

The driving use case (see [index § Driving use case](./#driving-use-case-http-password-intake)) is parsing an HTTP request that contains a password without the plaintext ever existing as a normal string. The vault handles the storage of the password bytes; each process-security setting closes a leakage path that the vault alone can't cover:

- **`mlockall`** — the parse buffer inside a protected-mode window is `sodium_malloc`'d (already `mlock`'d individually). But *surrounding* memory (parser state, temporary variables, libc heap fragments freed during parsing) can hold bytes that briefly touched the plaintext. Without `mlockall`, those could be swapped to disk between allocation and vaulting. With `mlockall`, no part of the process memory can be swapped.
- **`PR_SET_DUMPABLE, 0`** — if the process crashes mid-parse (bad body format, OOM, engine bug), a coredump would contain the whole process's memory — including the protected-mode parse buffer and any transient copies. `MADV_DONTDUMP` on vault pages helps, but a whole-process `PR_SET_DUMPABLE, 0` closes the door on any accidental dump, including the parse buffer before it's vaulted.
- **Ptrace scope requirement** — an unprivileged local attacker attaching a debugger to the Caspian process could `PTRACE_POKEDATA` to overwrite the vault's `mprotect` settings, or read the parse buffer directly while it's still `PROT_READWRITE`. Yama `ptrace_scope >= 2` requires `CAP_SYS_PTRACE` (typically only root), blocking that vector.

Without these settings, the vault still protects against most attack vectors, but three leakage paths remain: swap, coredumps, and unprivileged-local `ptrace`. For deployments where the HTTP intake case is a real production surface — publicly-accessible login endpoints, key-upload APIs, anything that receives passwords or passkeys over the wire — turn all three settings on.

## When to turn each on

- **`mlockall`** — the process handles sensitive material broadly, and the memory profile is bounded (won't grow unpredictably under load).
- **`PR_SET_DUMPABLE`** — same profile as `mlockall`; also useful when regulatory frameworks (HIPAA, PCI-DSS) require it.
- **`require_ptrace_scope: 2` or `3`** — high-security deployments. Refusing to start if the OS isn't set strictly enough is the right posture — better to fail loudly than run on a laxly-configured host.
- **Encrypted swap / disable hibernation** — always sensible for hosts handling secrets. Independent of engine config; set by ops at OS level.

A typical security-critical deployment turns on all three engine settings and configures encrypted/disabled swap at the OS. A typical dev machine turns none on.

## What this does not do

- **Doesn't replace the vault.** Whole-process locking prevents swap, but doesn't prevent in-process memory-disclosure bugs from leaking bytes. The vault's `PROT_NONE`/gateway model is orthogonal and complementary — vault protects **specific** secrets from **specific** access patterns; process-security prevents whole categories of leakage.
- **Doesn't help with side-channel attacks.** Spectre, Meltdown, Rowhammer, cache-timing — not in scope for any in-process or process-level protection.
- **Doesn't protect against root or privileged inspection.** A root user with tools like `/proc/PID/mem`, or a bootloader-level attacker, can bypass most in-process and process-level protections. The threat model is unprivileged local attackers, accidental in-process disclosure, and OS-level leakage paths (swap, coredumps) — not a compromised root.

## Related

- [vault](vault) — per-secret storage primitive that these process-level settings sit on top of.
