# `core:protected/password`

<span class="tag">protected-password</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected_memory_password",
	"role": "spec for `core:protected/password` — a Caspian built-in that SUBCLASSES `core:protected/hash`. The plaintext bytes live in the inherited `core:protected/hash` storage under one conventional key (`'password'`); the storage machinery (C-allocated protected memory, mlock, madvise(MADV_DONTDUMP), explicit_bzero on free, write-only Caspian surface, trusted-Lua-only read path) all comes from `core:protected/hash`. `core:protected/password` adds domain-specific methods on top: .verify (constant-time compare against a candidate), .hash_for_storage (encoded hash string for a database), .needs_rehash? (algorithm-upgrade signal), .destroy (immediate wipe). Algorithm choice (argon2id default via libsodium) and lifecycle (deterministic GC + on_close) are password-specific. The underlying vault (engine-internal Lua module) still runs at the lowest layer — `core:protected/hash` uses vault-shaped storage internally. Also available as the bareword `Password` for ergonomics; the URL identifier is authoritative.",
	"status": "spec — algorithm default, method contracts, lifecycle, and `core:protected/hash`-subclass relationship settled; alternative-algorithm plug-in mechanism and versioning-via-needs_rehash? design pending implementation",
	"audience": "Caspian developers using the Password class; anyone implementing or auditing the class itself"
}}
~~~

`core:protected/password` is a Caspian class that **subclasses [`core:protected/hash`](tag:protected-hash)**. The plaintext bytes it wraps live in the inherited `core:protected/hash` storage — one conventional key (`'password'`) holds the value; from Caspian, there is no way to read it back. The safety machinery (C-allocated protected memory, `mlock`, `madvise(MADV_DONTDUMP)`, `explicit_bzero` on free, write-only Caspian surface, trusted-Lua-only read path) all comes from `core:protected/hash`. `core:protected/password` adds password-specific methods on top: `.verify`, `.hash_for_storage`, `.needs_rehash?`, `.destroy`.

Accessed via `%('core:protected/password')`; the bareword `Password` is a shortcut for the same class.

Under the hood, `core:protected/hash` uses the [vault](tag:vault) primitive for the actual protected-memory backing — same libsodium-based storage the vault has always provided, just accessed via the higher-level `core:protected/hash` API. Password's methods that need to read the plaintext bytes reach for them through `core:protected/hash`'s trusted Lua binding (never through the Caspian surface, which raises on read).

The mechanics of how bytes get INTO the storage (HTTP intake, [`core:protected/memory`](tag:protected-memory) block, engine env-var bootstrap) are in the sibling `protected/` pages. The developer-facing surface (constructor, verify, destroy, HTTP route-schema declaration) is in [ui](tag:protected-ui). **This page is the class spec** — algorithm choice, method contracts, lifecycle.

## Algorithm

A single `Password` class. The algorithm name lives in a field on the instance.

~~~caspian
$pw = Password.new plaintext: $input
$pw.algorithm                    # 'argon2id'
$pw.verify $candidate
$pw.needs_rehash?                # true if algorithm or params are below current standard
~~~

**Default: argon2id** via libsodium's `crypto_pwhash`. Per-instance random salt generated via libsodium's CSPRNG at construction time, stored alongside the hash. Chosen for:

- Memory-hardness against GPU / ASIC attacks.
- Widely-audited implementation.
- Direct libsodium support — no extra dependency, no bump against the floppy budget.

The `needs_rehash?` predicate returns true when the algorithm or its parameters are below the current standard. Application code calls this after a successful verify and reconstructs the Password (with the new defaults) before re-storing.

**Other algorithms** (bcrypt, scrypt, PBKDF2) plug in as additional internal handlers behind the same class API, identified by the `algorithm` field on each instance. Application code doesn't usually care which is in use — the class encapsulates the algorithm-switch logic. Call `.verify` on any Password and it dispatches to the right handler based on the instance's algorithm field.

**The standard upgrade path:** verifying a legacy-algorithm password succeeds → `needs_rehash?` returns true → reconstruct with the current default → re-store. Done incrementally as users log in; no forced bulk migration.

## Class API

### Constructor

~~~caspian
$pw = Password.new plaintext: $bytes
~~~

Takes plaintext bytes, immediately writes them into the inherited `core:protected/hash` storage under key `'password'`, and discards every reachable copy. Returns a Password handle whose backing `core:protected/hash` holds the value in C-allocated protected memory.

The `$bytes` source is caller-owned. The constructor cannot wipe it (Caspian strings are immutable and may be aliased). Prefer arranging for the plaintext to arrive from an engine-managed path that never becomes a Caspian string in the first place — HTTP intake (see [HTTP intake flow](tag:http-intake-flow)), env-var bootstrap, [`core:protected/memory`](tag:protected-memory) block reading from stdin or a file.

**Optional keyword arguments** (post-V1):

- `algorithm: 'argon2id'` — override the default. Default is the current-standard algorithm; explicit override is for interop with existing hashes (bcrypt from a migrated database, etc.).
- `params: {...}` — override the algorithm's parameters (memory cost, time cost, parallelism for argon2id). Default is current-standard.

### Instance methods

| Method | Signature | Behavior |
|---|---|---|
| `.verify` | `$pw.verify $candidate → bool` | Constant-time compare against a candidate. `$candidate` may be raw bytes, another Password, or a stored hash string (algorithm-dispatched). Reads the stored plaintext through the inherited `core:protected/hash` trusted Lua binding; performs the comparison in native code so no cleartext ever appears on the Caspian stack. |
| `.hash_for_storage` | `$pw.hash_for_storage → string` | Returns the encoded hash string suitable for storing in a database (e.g. `$argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>`). Computes the hash from the `core:protected/hash`-stored plaintext via the trusted Lua path; the salt lives alongside the plaintext under a sibling key on the same `core:protected/hash`. |
| `.needs_rehash?` | `$pw.needs_rehash? → bool` | True if the instance's algorithm or parameters are below the current default. Reads `.algorithm` — no plaintext access needed. |
| `.destroy` | `$pw.destroy` | Immediate cleanup: deletes all keys on the inherited `core:protected/hash` (which zeros the underlying bytes), marks the handle as spent. Subsequent method calls raise. Idempotent — calling twice is safe (the second call is a no-op). |

### Fields

- `.algorithm` (read-only) — the algorithm name for this instance (`'argon2id'` by default).

## Lifecycle

Caspian's GC is deterministic. When the last reference to a Password goes out of scope, the engine's `on_close` hook fires and the inherited `core:protected/hash` is freed. Underlying `sodium_malloc`'d bytes are wiped and released — the standard `core:protected/hash` zero-on-GC behavior applies.

For earlier cleanup — before the enclosing scope exits — call `.destroy` directly.

### Aliasing

Passing a Password around, storing it in fields, copying it to other variables is harmless — every alias points at the same underlying `core:protected/hash`; the bytes don't propagate, only the handle does.

- **GC-triggered erase fires when the LAST reference releases.** Handle aliases keep the `core:protected/hash` alive as long as any one of them is reachable.
- **Explicit `.destroy` on one alias releases the `core:protected/hash` for all of them.** Subsequent method calls on other aliases raise "Password already destroyed." This is a deliberate simplification — Caspian doesn't refcount `core:protected/hash` entries, so early `.destroy` is authoritative and any co-held aliases become dead.

### Serialization

Drinian's `on_snapshot` hook for Password erases the handle rather than emit anything to the snapshot. See [ui § What you deliberately cannot do](tag:ui-cannot-do). A snapshot containing a Password-holding object surfaces post-revival as a handle whose underlying `core:protected/hash` is gone; the receiver has to re-acquire (re-prompt, re-fetch) to use it again.

## Related

- [`core:protected/hash`](tag:protected-hash) — the base class this class extends. All storage / safety machinery lives there.
- [vault](tag:vault) — the lower-level protected-memory primitive `core:protected/hash` uses internally.
- [process-security](tag:process-security) — the OS-level hardening around the process (`mlockall`, `PR_SET_DUMPABLE`, Yama).
- [ui](tag:protected-ui) — developer-facing usage patterns (`Password.new`, HTTP schema declaration, [`core:protected/memory`](tag:protected-memory) block).
- [protected/ index](tag:protected) — the umbrella overview.
