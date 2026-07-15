# Password

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_secure_memory_password",
	"role": "spec for the Password class — a Caspian built-in whose bucket holds a vault ID; the plaintext it wraps lives in the vault (see ../vault) under PROT_NONE and is never reachable from user code. Methods delegate to vault gateway operations. This page covers the class contract: algorithm choice (argon2id default via libsodium), the method surface (.verify, .hash_for_storage, .needs_rehash?, .destroy), the lifecycle (deterministic GC + on_close), and aliasing/destroy semantics. Mechanics of getting bytes into the vault live in the sibling secure-memory pages; the developer-facing usage patterns are in ../ui.",
	"status": "spec — algorithm default, method contracts, and lifecycle settled; alternative-algorithm plug-in mechanism and versioning-via-needs_rehash? design pending implementation",
	"audience": "Caspian developers using the Password class; anyone implementing or auditing the class itself"
}}
~~~

A `Password` is a Caspian class backed by the [vault](../vault). Its bucket holds an internal vault ID; the plaintext bytes it wraps live in the vault under `PROT_NONE` and are never reachable from user code. Methods on Password delegate to vault gateway operations that act on the bytes without ever returning them.

The mechanics of how bytes get INTO the vault (HTTP intake, `%process.malloc` block, engine env-var bootstrap) are in the parent secure-memory pages. The developer-facing surface (constructor, verify, destroy, HTTP route-schema declaration) is in [ui](../ui). **This page is the class spec** — algorithm choice, method contracts, lifecycle.

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

Takes plaintext bytes, immediately stores them in a fresh vault entry, discards every reachable copy. Returns a Password handle whose bucket holds the vault_id.

The `$bytes` source is caller-owned. The constructor cannot wipe it (Caspian strings are immutable and may be aliased). Prefer arranging for the plaintext to arrive from an engine-managed path that never becomes a Caspian string in the first place — HTTP intake (see [driving use case](../#driving-use-case-http-password-intake)), env-var bootstrap, `%process.malloc` block reading from stdin or a file.

**Optional keyword arguments** (post-V1):

- `algorithm: 'argon2id'` — override the default. Default is the current-standard algorithm; explicit override is for interop with existing hashes (bcrypt from a migrated database, etc.).
- `params: {...}` — override the algorithm's parameters (memory cost, time cost, parallelism for argon2id). Default is current-standard.

### Instance methods

| Method | Signature | Behavior |
|---|---|---|
| `.verify` | `$pw.verify $candidate → bool` | Constant-time compare against a candidate. `$candidate` may be raw bytes, another Password, or a stored hash string (algorithm-dispatched). Delegates to `vault.verify_password`. |
| `.hash_for_storage` | `$pw.hash_for_storage → string` | Returns the encoded hash string suitable for storing in a database (e.g. `$argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>`). Delegates to `vault.hash_for_storage`. |
| `.needs_rehash?` | `$pw.needs_rehash? → bool` | True if the instance's algorithm or parameters are below the current default. |
| `.destroy` | `$pw.destroy` | Immediate cleanup: calls `vault.erase(@vault_id)`, marks the handle as spent. Subsequent method calls raise. Idempotent — calling twice is safe (the second call is a no-op). |

### Fields

- `.algorithm` (read-only) — the algorithm name for this instance (`'argon2id'` by default).

## Lifecycle

Caspian's GC is deterministic. When the last reference to a Password goes out of scope, the engine's `on_close` hook fires and calls `vault.erase(@vault_id)`. The vault entry disappears; the `sodium_malloc`'d bytes are wiped and freed.

For earlier cleanup — before the enclosing scope exits — call `.destroy` directly.

### Aliasing

Passing a Password around, storing it in fields, copying it to other variables is harmless — every alias points at the same vault entry; the bytes don't propagate, only the ID does.

- **GC-triggered erase fires when the LAST reference releases.** Handle aliases keep the vault entry alive as long as any one of them is reachable.
- **Explicit `.destroy` on one alias releases the vault entry for all of them.** Subsequent method calls on other aliases raise "Password already destroyed." This is a deliberate simplification — Caspian doesn't refcount vault entries, so early `.destroy` is authoritative and any co-held aliases become dead.

### Serialization

Drinian's `on_snapshot` hook for Password erases the handle rather than emit anything to the snapshot. See [ui § What you deliberately cannot do](../ui#what-you-deliberately-cannot-do). A snapshot containing a Password-holding object surfaces post-revival as a handle whose vault entry is gone; the receiver has to re-acquire (re-prompt, re-fetch) to use it again.

## Related

- [vault](../vault) — the storage primitive this class delegates to.
- [process-security](../process-security) — the OS-level hardening around the vault.
- [ui](../ui) — developer-facing usage patterns (`Password.new`, HTTP schema declaration, `%process.malloc` block).
- [secure-memory index](../) — the umbrella overview and the HTTP-intake driving use case.
