# Vault

~~~vibecode
{"vibecode": {
	"doc": "requirements_secure_memory_vault",
	"role": "spec for the vault primitive — libsodium-backed per-secret storage that keeps raw sensitive bytes out of reach of anything reachable from user code. Each vault entry lives in a sodium_malloc'd region (guard pages + mlock + PROT_NONE + MADV_DONTDUMP) and is accessed only through a narrow operation-oriented gateway. Consumers (Password class, future key classes, etc.) hold vault IDs but never see raw bytes. Covers sodium_malloc internals, gateway operations, entry lifecycle, protected-mode discipline for the code paths that briefly hold raw bytes, RLIMIT_MEMLOCK handling, and threat model.",
	"status": "spec — mechanism settled; specific gateway operation list will grow as new secret types get spec'd",
	"audience": "Caspian engine implementers building the vault; security reviewers auditing the code paths that touch raw secret bytes"
}}
~~~

The vault is an engine-managed storage region for sensitive raw bytes — separate from ordinary Caspian memory, invisible to anything reachable from user code. Each entry is keyed by an internal vault ID, held inside a `sodium_malloc`'d buffer with guard pages, `mlock`'d into RAM, and marked `MADV_DONTDUMP`.

Access to the vault is through a narrow operation-oriented gateway — **never** a `vault.get(id)` that returns bytes. User code (and Caspian-the-language) interacts with the vault only via the gateway.

## Gateway operations

The gateway is operation-oriented. Callers hand in an operation ("verify this hash", "sign this message") and get back a result — never the raw bytes themselves:

- `vault.store(bytes) → vault_id` — writes bytes into a fresh entry; returns the handle.
- `vault.verify_password(id, stored_hash) → bool` — constant-time compare; returns true/false.
- `vault.hash_for_storage(id, params) → string` — returns the argon2 hash string for the DB.
- `vault.sign(id, message) → signature` — for future signing-key use.
- `vault.erase(id)` — explicit cleanup.

Each operation opens a brief internal protected window: `mprotect` the vault's stored buffer to `PROT_READONLY`, run the cryptographic primitive, `mprotect` back to `PROT_NONE`, return. Outside that window, the buffer is unreadable to all in-process code, including the engine itself.

Additional operations get added as new secret types get spec'd. Adding a gateway operation is a deliberate engine change — the complete list is small enough to enumerate, audit, and review.

**Why this works.** The gateway never returns plaintext or any function of plaintext that reveals it. User code can't extract bytes. Aliasing a handle (passing it around, storing it in fields) is harmless — every alias points at the same vault entry; the bytes don't propagate, only the ID does. And the engine doesn't manage any cryptographic key of its own — the vault is access-controlled memory, not a crypto provider.

## sodium_malloc: what a vault entry looks like

Each entry uses libsodium's `sodium_malloc`. On Linux, one `sodium_malloc(n)` call expands into roughly six steps:

1. **Round up to page size.** Linux pages are typically 4 KB; `sodium_malloc` allocates whole pages. A 50-byte allocation still uses a full page.
2. **`mmap` three contiguous regions** — a guard page before the user area, the user-accessible page(s), and a guard page after:

	~~~
	[guard page] [user buffer page(s)] [guard page]
	     ↑              ↑                    ↑
	PROT_NONE      PROT_READ|WRITE       PROT_NONE
	~~~

3. **Mark the guards inaccessible** via `mprotect(guard_page, page_size, PROT_NONE)`. Any code that overruns the user buffer hits a guard and segfaults — buffer-overflow detection built in.
4. **Fill the user area with a canary pattern** (libsodium uses `0xdb`). Detects use-after-free: if the canary appears where real data should be after a write, something wrote → freed → re-used.
5. **`mlock` the user pages** — pins them in physical RAM, preventing swap.
6. **`madvise(MADV_DONTDUMP)`** — excludes the pages from coredumps.

Return value: a pointer to the start of the user-accessible buffer, just past the leading guard page. The caller has `n` writable bytes of secured memory.

**Cross-platform note.** libsodium abstracts the OS-specific calls, so the same behavior applies on macOS (Darwin's `mlock`/`mprotect`), the BSDs, and Windows (`VirtualAlloc`/`VirtualLock`/`VirtualProtect`). Caspian's engine doesn't write Linux-specific code — `sodium_malloc` behaves the same on every supported platform, with the same threat model.

## The mprotect dance

After `sodium_malloc`, the buffer is left in `PROT_READWRITE` state so the caller can write initial bytes in. The vault's gateway then immediately calls `sodium_mprotect_noaccess` — the buffer becomes unreadable to all in-process code, including the engine itself.

When a gateway operation needs the bytes:

~~~
sodium_mprotect_readonly(buf)    # grant read access
// inside this window:
//   argon2id_verify(buf, len, stored_hash, salt, params, ...)
sodium_mprotect_noaccess(buf)    # back to unreadable
return result
~~~

Outside those `mprotect` transitions, any code reading the page address triggers `SIGSEGV`.

## Vault entry lifecycle

~~~
vault.store(bytes):
    buf = sodium_malloc(len(bytes))               # allocate guarded+locked region
    memcpy(buf, bytes, len(bytes))                # copy plaintext in
    sodium_memzero(source_bytes, len(bytes))      # wipe the source buffer
    sodium_mprotect_noaccess(buf)                 # lock down (PROT_NONE)
    vault_id = generate_id()
    engine.vault[vault_id] = (buf, len)           # register in vault hash
    return vault_id

vault.verify_password(vault_id, stored_hash):
    (buf, len) = engine.vault[vault_id]
    sodium_mprotect_readonly(buf)                 # grant read
    result = argon2id_verify(buf, len, stored_hash, salt, params)
    sodium_mprotect_noaccess(buf)                 # lock back down
    return result

vault.erase(vault_id):
    (buf, len) = engine.vault[vault_id]
    sodium_free(buf)                              # zeros and unmaps
    delete engine.vault[vault_id]
~~~

Bytes spend the vast majority of their lifetime under `PROT_NONE`, briefly transitioning to `PROT_READONLY` only for the duration of a gateway operation.

## Protected mode

Some engine code paths need to hold raw secret bytes briefly — long enough to copy them from an HTTP body into the vault, for example. **Protected mode** is the discipline that bounds those code paths.

**Protected mode is a duration during which the engine has a specific `sodium_malloc`'d buffer alive that contains raw secret bytes.** It begins with the `sodium_malloc` call that allocates the buffer and ends with one of two specific actions: handing the buffer to the vault, or `sodium_free`-ing it. There's no third option.

There's no global engine flag; "the mode" is just the lifetime of a particular protected buffer. The engine can have several protected-mode windows happening at different times, each with its own buffer and its own lifetime. They don't interact.

**Concretely, entering protected mode:**

~~~c
buf = sodium_malloc(size);          // protected mode begins for this buf
// buf is PROT_READWRITE; engine code writes secret bytes into it
~~~

**Exiting is one of two specific actions:**

Either hand it to the vault for long-term storage:

~~~c
vault_id = vault.store_buffer(buf, size);   // vault takes ownership; PROT_NONEs immediately
// protected mode ends; the bytes now live in the vault
~~~

Or wipe and free it:

~~~c
sodium_memzero(buf, size);
sodium_free(buf);                    // zeros (again) and unmaps
// protected mode ends; the bytes are gone
~~~

A protected buffer must end its life either as a vault entry or as freed memory. It cannot become a regular long-lived allocation, get copied into a Caspian string, get passed to logging code, or otherwise outlive its enclosing window.

**Where protected-mode windows happen.** A short, well-defined list of engine code paths open them:

- **HTTP body parsing for declared password fields** (the Touchstone pre-pass): allocate a protected buffer, read body bytes into it, hand password-field bytes to the vault, `sodium_free` the buffer.
- **Environment-variable bootstrap for declared secrets** at engine startup: declared-secret env vars get read into a protected buffer, handed to the vault, source env var wiped.
- **Secrets-file readers:** allocate, read, hand to vault, free.
- **Vault gateway operations themselves:** each opens a brief protected-mode window internally to `mprotect` its stored buffer to `PROT_READONLY`, run the primitive, `mprotect` back.

Adding a new entry point is a deliberate engine change. The complete set is small enough to enumerate, audit, and review individually.

**Properties this gives:**

- **Bounded.** Every `sodium_malloc` for a protected buffer is matched by either `vault.store_buffer` or `sodium_free`. No protected buffer leaks past its enclosing window.
- **Auditable.** "What engine code reads raw secret bytes?" has a tight answer: the code between protected-mode entry and exit.
- **Opt-in per use.** Routes without password fields never trigger a protected-mode window. The engine pays no protected-mode cost when nothing requires it.
- **Independent.** Two protected-mode windows running concurrently (different requests, different operations) have separate buffers and don't share state.

## The HTTP intake flow

The driving use case for this whole subsystem (see [index § Driving use case](./#driving-use-case-http-password-intake)) is parsing an HTTP request that contains a password or passkey without the plaintext ever existing as a normal string. The specialized protected-mode entry looks like this:

1. Touchstone's route lookup detects a declared password field in the schema.
2. **Enter protected mode:** allocate a `sodium_malloc`'d parse buffer; copy raw body bytes in; wipe the source engine buffer.
3. **Run the parser inside the window.** When it identifies the password field's bytes, call `vault.store_buffer(bytes, len)` — a specialized variant of `vault.store` that takes ownership of an already-protected buffer segment (no double-copy). Returns a `vault_id`.
4. Parser records `("pw" → vault_id)` in a sidecar map alongside the parsed body.
5. Parser writes a placeholder (`"#####"`) into the body position where the password value used to be.
6. **Exit protected mode:** `sodium_memzero` and `sodium_free` the parse buffer.
7. Touchstone constructs `$request` using ordinary parsing on the redacted body, then overlays the sidecar map — the password field becomes a `Password` object whose bucket holds the `vault_id`.

**Length-tracking metadata has to be reset after redaction.** Replacing the password value almost always changes the body's byte count, which means several things have to be recomputed before the redacted body is handed off:

- **`Content-Length` HTTP header** — must match the new body length, or downstream parsers will be off-by-N.
- **Chunked transfer-encoding chunk sizes** — if the body arrived chunked, chunk-size headers need rewriting; multi-chunk bodies containing passwords may need to be re-chunked entirely.
- **Multipart-form boundary positions** — each part's size moves when the password value inside it changes length.

The protected-mode pre-pass is responsible for all of this. No length tied to the original body should ever leave the window.

**The two-parser risk.** If the pre-pass parser (inside protected mode) and any subsequent parser disagree on where the password bytes are, an attacker can craft a body that gets redacted in one place but read from another — the second parser sees the plaintext. Same bug class that hit early Rails, ModSecurity, and many other frameworks: two-parser disagreement is an attacker's playground.

Two ways to prevent it, in order of cleanliness:

1. **One parser, two output sinks.** The parser runs once, inside protected mode. As it identifies each field, it dispatches the bytes to the right destination: vault for declared password fields, normal field map for everything else. No second parse, no divergence possible.
2. **Same parser code, two passes.** If a one-pass implementation is infeasible for some body format (streaming, etc.), run the parser twice with the identical code — once in protected mode for password extraction, once outside for everything else. Guarantees no divergence between the two passes; costs a second parse per request with passwords.

Reference implementation uses option 1. Option 2 is the documented fallback if streaming or other architectural constraints ever make one-pass impractical for some body format.

## Vault-entry lifecycle in Caspian

Caspian's GC is deterministic. When the last reference to a handle (e.g., a Password object) goes away, the engine's `on_close` hook fires and calls `vault.erase(@vault_id)`. The vault entry disappears with the handle, no waiting. For earlier cleanup, application code can call `.destroy` directly on the handle.

**Accumulation to watch for.** A handle whose reference is captured by a long-lived closure or stored in a long-lived hash keeps its vault entry alive as long as the capturer does. The bytes don't leak (still vault-protected) but vault entries can accumulate when applications retain handles past their useful lifetime. The vault supports a size cap and an audit endpoint (`vault.audit`) for catching accumulation early.

## RLIMIT_MEMLOCK

`sodium_malloc`'s `mlock` step requires the process to have sufficient locked-memory budget. `getrlimit(RLIMIT_MEMLOCK)` returns the soft limit. Defaults vary:

- Most desktop Linux: 64 KB (very small)
- Most server Linux: 16 MB (still small)
- systemd services often inherit low defaults
- Some distros and containers set higher defaults

A vault holding many entries can easily exceed 64 KB. If `mlock` fails, `sodium_malloc` returns NULL — the engine's vault-store operation has to handle this.

**Engine responsibilities:**

- **Check return values.** `sodium_malloc` returning NULL means out-of-secure-memory. Don't silently fall back to regular allocation — that would put plaintext in unprotected memory and violate the contract.
- **Raise the limit at startup if possible.** If the engine has `CAP_SYS_RESOURCE`, call `setrlimit(RLIMIT_MEMLOCK, ...)` to raise the soft limit to something like 64 MB. Otherwise, expect operators to raise it via `ulimit -l`, systemd `LimitMEMLOCK=`, or `/etc/security/limits.conf`.
- **Fail loudly at startup** if neither is possible and the limit is too small for a viable vault. Refusing to enable the vault (with a clear message — "secure memory unavailable; raise `RLIMIT_MEMLOCK` or run with `CAP_IPC_LOCK`") is the right behavior. Silent degradation to insecure storage is not.

## Threat model

**What the vault protects against:**

- **Reading the page from other engine code** — segfaults via `PROT_NONE`. Even malicious code that knows the page address can't read.
- **Forcing swap-to-disk** — `mlock` prevents.
- **Inspecting a coredump** — `MADV_DONTDUMP` excludes the page.
- **Memory scanners walking `/proc/PID/mem`** — the kernel respects `mprotect`; `PROT_NONE` pages return read errors.
- **Buffer overflow from neighboring engine code** — guard pages catch it.
- **Use-after-free** — canary pattern detects post-free reads; `sodium_free`'s explicit zero leaves nothing recoverable.

**What still beats the vault:**

- **Debugger attached via `ptrace`.** Can modify page protections, bypass `mprotect`, read everything. Mitigations at the process level are in [process-security](process-security).
- **Side-channel attacks** (Spectre, Meltdown, Rowhammer, cache-timing). Not addressed by in-process memory protection.
- **In-process memory-disclosure bugs.** A bug in the engine that returns memory contents to user code could leak vault bytes during a `PROT_READ` window. The narrow window helps; fix the bug.
- **Hibernation to disk.** RAM image gets written to disk during suspend. `mlock` doesn't prevent that. See [process-security](process-security).
