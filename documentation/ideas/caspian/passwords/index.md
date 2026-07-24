# Passwords

> **Archived.** The Password class spec is now at [requirements/secure-memory/password/](../../../requirements/secure-memory/password/). The vault mechanics and Touchstone-walkthrough content have been folded into the sibling [secure-memory pages](../../../requirements/secure-memory/) — see `vault`, `process-security`, and `ui` there. The sibling `passkeys.md` has been promoted to [requirements/secure-memory/passkey/](../../../requirements/secure-memory/passkey/). This file is kept as design-history.

~~~vibecode
{"vibecode": {
	"doc": "passwords",
	"role": "ARCHIVED design brainstorm — the Password class, vault mechanics, and Touchstone walkthrough have all been folded into requirements/secure-memory/ (Password → secure-memory/password/, vault → secure-memory/vault, process-security → secure-memory/process-security, developer surface → secure-memory/ui). Sibling passkeys.md has been promoted to secure-memory/passkey/. Kept here as design-history for the reasoning trail.",
	"status": "archived — content promoted to requirements/secure-memory/; retained for design context",
	"audience": "design historians; anyone tracing the reasoning trail from the initial design to the promoted spec",
	"related": ["passkeys.md (sibling archive, also promoted — see requirements/secure-memory/passkey/)"]
}}
~~~

A `Password` is a Caspian object whose plaintext is never reachable from user code. The constructor takes plaintext, immediately stores the bytes in a protected vault region of engine memory, and discards every reachable copy. The object the constructor returns is just a handle — its bucket holds a vault ID, and its methods (`verify`, `hash_for_storage`) delegate to gateway operations that act on the vault contents without ever returning them.

The design has two pillars: a libsodium-backed **vault** for storage, and a bounded operational discipline called **protected mode** that brackets every code path with access to raw secret bytes. The walkthrough at the end of this doc shows them working together for the canonical HTTP login case.

## Algorithm

A single `Password` class. The algorithm name lives in a field on the instance.

~~~caspian
$pw = Password.new(plaintext: $input)
$pw.algorithm                    # 'argon2id'
$pw.verify(plaintext: $candidate)
$pw.needs_rehash?                # true if algorithm or params are below current standard
~~~

Default algorithm: **argon2id**, via libsodium's `crypto_pwhash`. Per-instance random salt generated via libsodium's CSPRNG at construction time, stored alongside the hash. The `needs_rehash?` predicate returns true when the algorithm or its parameters are below the current standard — application code checks it after a successful verify and re-constructs the Password (with the new defaults) before re-storing.

Other algorithms (bcrypt, scrypt, etc.) plug in as additional internal handlers behind the same class API, identified by the `algorithm` field on each instance. Application code doesn't usually care which is in use; the class encapsulates the algorithm-switch logic.

## Part 1: Storing secrets with libsodium and protected mode

~~~vibecode
{"vibecode": {
	"part": "1",
	"role": "explains how Caspian keeps raw secret bytes out of reach: a libsodium-backed vault for storage, sodium_malloc plus Linux memory-protection mechanics for the buffer-level protection, and the protected-mode discipline that brackets the few code paths permitted to handle raw bytes"
}}
~~~

### The vault

The vault is an engine-managed storage region for sensitive bytes — separate from Drinian's `objects` hash, invisible to anything reachable from user code. Each vault entry is keyed by an internal vault ID and holds raw bytes inside a sodium_malloc'd buffer. The vault is accessed only through a narrow gateway whose methods are **operation-oriented** — never a `vault.get(id)` that returns bytes:

~~~
vault.store(bytes) → vault_id          # writes bytes; returns the handle
vault.verify_password(id, stored_hash) # constant-time compare; returns true/false
vault.hash_for_storage(id, params)     # returns the argon2 hash string for the DB
vault.sign(id, message)                # for future use with signing keys
vault.erase(id)                        # explicit cleanup
~~~

The Password class is a thin handle: its bucket holds the vault ID, and its methods delegate to these gateway operations. User code (and Caspian-the-language) interacts with the vault only via the gateway.

**Why this works.** The gateway never returns plaintext or any function of plaintext that reveals it. User code can't extract. Aliasing the handle (passing it around, storing it in fields, copying it to other variables) is harmless because every alias points at the same vault entry; the bytes don't propagate, only the ID does. And the engine doesn't manage any cryptographic key of its own — the vault is access-controlled memory, not a crypto provider.

**Lifecycle.** Caspian's GC is deterministic — when the last reference to a Password object goes away, the engine's `on_close` hook for `puck.uno/password` fires at a predictable point and calls `vault.erase(@vault_id)`. The vault entry disappears with the handle, no waiting. For earlier cleanup (before the handle's enclosing scope exits), application code can call `$pw.destroy` directly.

The accumulation case to watch for is reference *retention*, not GC timing. A Password whose handle is captured by a long-lived closure or stored in a long-lived hash will keep its vault entry alive as long as that capturing structure does — the cleanup point is still deterministic, but it's deferred to whenever the capturer itself releases. The bytes don't leak (they're still vault-protected) but vault entries can accumulate when applications retain handles past their useful lifetime. The vault supports a size cap and an audit endpoint (`vault.audit`) for catching accumulation early.

### sodium_malloc and Linux memory protection

The vault's buffers are allocated with libsodium's `sodium_malloc`. This section walks through what that does at the OS level on Linux. (Other platforms — macOS, BSD, Windows — have equivalents; libsodium abstracts them.)

**The libsodium API surface the vault uses:**

| Function | Purpose |
|---|---|
| `sodium_init()` | One-time engine-startup initialization. Required before any other libsodium call. |
| `sodium_malloc(size_t n)` | Allocate `n` bytes inside a protected region. Returns a pointer to the user-accessible area. |
| `sodium_free(void *p)` | Zero the bytes and release the protected region. |
| `sodium_memzero(void *p, size_t n)` | Explicitly zero a memory range. Used on any temporary buffer that held secret bytes. |
| `sodium_mlock(void *p, size_t n)` | Pin `n` bytes in physical RAM (no swap). For regular allocations that need swap protection without the full guard-page treatment. |
| `sodium_munlock(void *p, size_t n)` | Unpin and zero. |
| `sodium_mprotect_noaccess(void *p)` | Mark a `sodium_malloc`'d region as inaccessible — any read/write hits a segfault. |
| `sodium_mprotect_readonly(void *p)` | Mark it readable. Used briefly when the gateway reads the bytes for an operation. |
| `sodium_mprotect_readwrite(void *p)` | Mark it readable and writable. Used briefly when the gateway writes new bytes in. |

**What `sodium_malloc(n)` actually does on Linux:**

A single call expands into roughly six steps:

1. **Round up to page size.** Linux pages are typically 4 KB; `sodium_malloc` allocates whole pages. If `n` is 50 bytes, the allocation still uses a full page.
2. **`mmap` three contiguous regions.** A guard page before the user area, the user-accessible page(s), and a guard page after. The result is a memory layout like:
   ```
   [guard page] [user buffer page(s)] [guard page]
        ↑              ↑                    ↑
   PROT_NONE      PROT_READ|WRITE       PROT_NONE
   ```
3. **Mark the guards inaccessible.** `mprotect(guard_page, page_size, PROT_NONE)` on each guard. Any code that overruns the user buffer hits the guard and segfaults — buffer-overflow detection.
4. **Fill the user area with a canary pattern.** A known byte sequence (libsodium uses `0xdb`). Detects use-after-free: if the canary appears where real data should be after a write, something wrote then was freed then was re-used.
5. **`mlock` the user pages.** `mlock(user_buffer, n)` syscall — pins the pages in physical RAM, prevents Linux from swapping them out. The bytes will never hit the disk via the swap mechanism.
6. **`madvise(MADV_DONTDUMP)`.** Marks the pages as exclude-from-coredump. If the process crashes, the user buffer's contents won't appear in the coredump file. (Linux-specific; libsodium calls it when available.)

Return value: a pointer to the start of the user-accessible buffer, just past the leading guard page. The caller has `n` writable bytes of secured memory.

**The mprotect dance during gateway operations:**

After `sodium_malloc`, the buffer is left in PROT_READWRITE state so the caller can write the initial bytes in. The vault's gateway then immediately calls `sodium_mprotect_noaccess` — the buffer becomes unreadable to all in-process code, including the engine itself, until needed.

When a gateway operation needs the bytes (e.g., `vault.verify_password` running argon2):

~~~
sodium_mprotect_readonly(buf)    # grant read access
// inside this window:
//   argon2id_verify(buf, len, stored_hash, salt, params, ...)
//   constant-time compare
sodium_mprotect_noaccess(buf)    # back to unreadable
return result
~~~

The window between mprotect calls is the only time the bytes are readable from regular code paths. Outside that window, any code reading the page address triggers SIGSEGV.

**What Linux's mlock actually guarantees:**

- The pages stay in physical RAM. They are not eligible for the kernel's page-replacement / swap mechanism.
- The contents will not be written to the swap partition or swap file under normal operation.
- This survives memory pressure: even if the system would otherwise swap to free RAM, mlocked pages stay put.

What it doesn't guarantee:

- Pages can still be written to disk by other mechanisms: hibernation (suspend-to-disk), coredumps (unless `MADV_DONTDUMP` is set), explicit `mmap`-to-file writes.
- mlock requires either `CAP_IPC_LOCK` capability, root, OR fitting within `RLIMIT_MEMLOCK` (the per-process limit on lockable memory).

**The `RLIMIT_MEMLOCK` constraint and what to do about it:**

`getrlimit(RLIMIT_MEMLOCK)` returns the soft limit on locked memory. Defaults vary:

- Most desktop Linux: 64 KB (very small)
- Most server Linux: 16 MB (still small)
- Systemd services often inherit a low default
- Some distros and containers set higher defaults

A vault holding many password entries can easily exceed 64 KB. If `mlock` fails, libsodium's `sodium_malloc` returns NULL — the engine's vault-store operation has to handle this.

Engine responsibilities:

- **Check return values.** `sodium_malloc` returning NULL means out-of-secure-memory. Don't silently fall back to regular allocation — that would put plaintext in unprotected memory and violate the contract.
- **Raise the limit at startup if possible.** If the engine has `CAP_SYS_RESOURCE`, call `setrlimit(RLIMIT_MEMLOCK, ...)` to raise the soft limit to something like 64 MB. Otherwise, expect operators to raise it via `ulimit -l`, systemd `LimitMEMLOCK=`, or `/etc/security/limits.conf`.
- **Fail loudly at startup if neither.** The engine should refuse to start (or refuse to enable the vault) rather than silently degrading to insecure storage. A startup-time error with a clear message — "secure memory unavailable; raise RLIMIT_MEMLOCK or run with CAP_IPC_LOCK" — is the right behavior.

**The full lifecycle of a vault entry:**

~~~
vault.store(bytes):
    buf = sodium_malloc(len(bytes))                # allocate guarded+locked region
    memcpy(buf, bytes, len(bytes))                 # copy plaintext in
    sodium_memzero(source_bytes, len(bytes))       # wipe the source buffer
    sodium_mprotect_noaccess(buf)                  # lock it down (PROT_NONE)
    vault_id = generate_id()
    engine.vault[vault_id] = (buf, len)            # register in vault hash
    return vault_id

vault.verify_password(vault_id, stored_hash):
    (buf, len) = engine.vault[vault_id]
    sodium_mprotect_readonly(buf)                  # grant read
    result = argon2id_verify(buf, len, stored_hash, salt, params)
    sodium_mprotect_noaccess(buf)                  # lock back down
    return result

vault.erase(vault_id):
    (buf, len) = engine.vault[vault_id]
    sodium_free(buf)                               # zeros and unmaps
    delete engine.vault[vault_id]
~~~

The plaintext bytes spend the vast majority of their lifetime in `PROT_NONE` pages, briefly transitioning to `PROT_READ` only for the duration of a gateway operation.

**What an attacker is up against:**

- **Reading the page from another part of the engine:** segfaults via `PROT_NONE`. Even malicious code that knows the page address can't read it.
- **Forcing swap-to-disk:** mlock prevents.
- **Inspecting a coredump:** `MADV_DONTDUMP` excludes the page.
- **Memory scanners walking `/proc/PID/mem`:** can attempt, but the kernel respects `mprotect` — `PROT_NONE` pages return read errors.
- **Buffer overflow from neighboring engine code:** the guard pages catch the overflow and segfault.
- **Use-after-free:** the canary pattern detects post-free reads; `sodium_free`'s explicit zero leaves nothing recoverable.

What still beats sodium_malloc:

- **Debugger attached via `ptrace`.** `ptrace` can modify page protections of the traced process, bypass mprotect, read everything. Same-process debugger is fully unprotected. Linux mitigations include `prctl(PR_SET_DUMPABLE, 0)` (which also prevents most ptrace) and Yama's `ptrace_scope` sysctl set to 2 or 3. Worth setting at engine startup.
- **Side-channel attacks** (Spectre, Meltdown, Rowhammer, cache-timing). Not addressed by any in-process memory protection.
- **In-process memory-disclosure bugs.** A bug in the engine itself that returns memory contents to user code could leak vault bytes during a `PROT_READ` window. The narrow window helps; the bug should still be fixed.
- **Hibernation to disk.** The whole RAM image gets written to disk during suspend. mlock doesn't prevent that. Mitigations: encrypted swap, encrypted hibernation, or disabling hibernation on hosts that handle secrets.

**Linux-specific extras worth setting at engine startup:**

- **`prctl(PR_SET_DUMPABLE, 0)`** — prevents the process from being coredumped at all, and tightens `ptrace` restrictions per Yama. Tradeoff: makes engine debugging harder for legitimate operators. Default OFF; opt-in via engine config.
- **`mlockall(MCL_CURRENT | MCL_FUTURE)`** — locks the entire process memory in RAM, not just the vault. Heavier hammer; appropriate for security-critical deployments. Tradeoff: requires generous `RLIMIT_MEMLOCK`; can cause OOM issues under memory pressure.
- **Disable swap entirely** at the OS level for hosts that handle secrets, if that's operationally acceptable.

**Cross-platform note.** libsodium abstracts the OS-specific calls, so the same code works on macOS (using Darwin's mlock/mprotect), the BSDs, and Windows (using `VirtualAlloc`/`VirtualLock`/`VirtualProtect`). The Caspian engine doesn't have to write Linux-specific code — sodium_malloc behaves the same way on every supported platform, with the same threat model. Operational concerns like `RLIMIT_MEMLOCK` are Linux-specific names for an issue that exists in some form everywhere.

### Protected mode

~~~vibecode
{"vibecode": {
	"section": "protected_mode",
	"role": "the concrete state of the engine holding a sodium_malloc'd buffer of raw secret bytes; defined by the lifetime of that buffer; bracketed by specific entry and exit operations on it"
}}
~~~

**Protected mode is a duration in the process during which the engine has a specific sodium_malloc'd buffer alive that contains raw secret bytes.** It begins with the `sodium_malloc` call that allocates the buffer and ends with one of two specific actions: handing the buffer to the vault, or `sodium_free`-ing it. While the buffer exists, the engine is "in protected mode" with respect to that buffer; before allocation and after disposal, it isn't.

There's no global engine flag; the "mode" is just the lifetime of a particular protected buffer. The engine can have several protected-mode windows happening at different times (one for body parsing, one for a vault verify, etc.), each with its own buffer and its own lifetime. They don't interact.

**Concretely, entering protected mode looks like:**

~~~c
buf = sodium_malloc(size);          // protected mode begins for this buf
// buf is PROT_READWRITE; engine code writes secret bytes into it
~~~

**Exiting protected mode is one of two specific actions on that buffer:**

Either hand it to the vault for long-term storage:

~~~c
vault_id = vault.store_buffer(buf, size);   // vault takes ownership;
                                            // immediately PROT_NONEs the buffer
                                            // and registers it under vault_id
// protected mode ends for buf; the bytes now live in the vault
~~~

…or wipe and free it:

~~~c
sodium_memzero(buf, size);
sodium_free(buf);                   // zeros (again) and unmaps
// protected mode ends for buf; the bytes are gone
~~~

There is no third option. A buffer that contains secret bytes must end its life either as a vault entry or as freed memory. It cannot become a regular long-lived allocation, get copied into a Caspian string, get passed to logging code, or otherwise outlive its enclosing protected-mode window. The engine code that runs between entry and exit is the only code with read/write access to the bytes (and only briefly — sodium_mprotect transitions cover the moments when it's actively reading/writing).

**Where protected-mode windows happen in Caspian:**

A short, well-defined list of engine code paths open protected-mode windows:

- **HTTP body parsing for declared password fields.** The Touchstone pre-pass (see Part 2) allocates a protected buffer, reads the body bytes into it, hands password-field bytes to the vault, and frees the buffer on exit.
- **Environment-variable bootstrap for declared secrets.** At engine startup, declared-secret env vars get read into a protected buffer, handed to the vault, and the source env-var string gets wiped.
- **Secrets-file readers.** Same pattern: allocate, read, hand to vault, free.
- **Vault gateway operations themselves.** `vault.verify_password`, `vault.sign`, etc. each open a brief protected-mode window: mprotect the vault's stored buffer to readable, run the cryptographic primitive, mprotect back to PROT_NONE, return.

Adding a new entry point is a deliberate engine change. The complete set of code paths that enter protected mode is small enough to enumerate, audit, and review individually.

**Properties this gives you:**

- **Bounded.** Every `sodium_malloc` for a protected buffer is matched by either `vault.store_buffer` or `sodium_free`. No protected buffer leaks past its enclosing window.
- **Auditable.** "What engine code reads raw secret bytes?" has a tight answer: the code between protected-mode entry and exit. Reviewing that set is reviewing the whole attack surface.
- **Opt-in per use.** Routes without password fields never trigger a protected-mode window. The engine pays no protected-mode cost when nothing requires it.
- **Independent.** Two protected-mode windows running concurrently (different requests, different operations) have separate buffers and don't share state. One window's exit doesn't affect another's.

**The invariant:**

> When a protected-mode window exits, its buffer has either (a) been transferred to the vault, where it lives under `PROT_NONE` until a gateway operation needs it, or (b) been wiped and freed via `sodium_memzero` + `sodium_free`. There is no other exit.

Outside any protected-mode window, no engine code reads raw secret bytes directly. The Password class's user-facing methods are outside protected mode entirely — they call vault gateway operations, and those gateway operations open their own short protected-mode windows internally to do the work.

## Part 2: Touchstone walkthrough — handling a login request

~~~vibecode
{"vibecode": {
	"part": "2",
	"role": "concrete walkthrough showing the vault, sodium_malloc, and protected mode working together to handle an HTTP login request; from raw socket bytes to a user-code Password object with the plaintext never touching a user-reachable value"
}}
~~~

The canonical case: a browser POSTs a login form with `id` and `pw` fields to a Caspian web app. Touchstone (the HTTP front-end) receives the request and dispatches to the route handler. The walkthrough below shows how Touchstone uses the vault and protected mode to ensure that by the time user code sees `$request['pw']`, it's already a Password object with the plaintext sealed in the vault.

### Schema declaration

The route's schema declares the password field as class `Password`. This is what opts the route into the protected-mode pre-pass:

~~~caspian
route '/login' do
    field :id, class: :string
    field :pw, class: 'puck.uno/password'
end

handler do |$request|
    $user = $users.find_by_id($request['id'])

    if $request['pw'].verify($user.stored_hash)
        # authenticated
    end
end
~~~

If a route's schema has no `Password` field, none of the protected-mode machinery runs for that route — zero overhead. Driving the opt-in from the schema (rather than from a request header) is the right default: the application controls the schema, attackers don't.

### Request flow

The flow from raw socket bytes to a user-code Password object:

~~~
Raw socket bytes arrive
    ↓
Touchstone identifies the route (URL match against route table)
    ↓
The route's schema declares a Password field, so:
    Enter protected mode:
        Allocate a sodium_malloc'd buffer; copy raw body bytes in
        Parser walks the body, finds the declared password field's value bytes
        vault.store(field_bytes) → vault_id
            (vault.store opens its own internal protected-mode window
            to copy bytes into a sodium_malloc'd vault buffer, then
            transitions the vault buffer to PROT_NONE)
        Record (field_name → vault_id) in a sidecar map
        The password field in the body is redacted to the same length as sent
        sodium_memzero the parse buffer; sodium_free it
    Exit protected mode
    ↓
Touchstone parses the redacted body normally (no password content remains in the body)
    ↓
$request is constructed; sidecar map overlays the password field as a Password object
    ↓
Route handler runs; $request['pw'] is a Password from the first moment user code can see it
~~~

Step-by-step in plain language:

1. **Raw bytes arrive at the socket.** Touchstone reads them into a regular engine buffer (per normal HTTP handling).
2. **Route lookup.** Touchstone matches the URL against the route table and finds the `'/login'` route. The route's schema declares a `Password` field, so the protected-mode pre-pass is required.
3. **Enter protected mode.** Touchstone allocates a sodium_malloc'd buffer big enough to hold the request body. Copies the raw bytes from the engine buffer into the sodium_malloc'd buffer. Wipes the engine buffer (so the raw bytes don't linger anywhere else).
4. **Parser pass.** A schema-aware parser walks the body inside the protected-mode window. As it identifies fields, it dispatches their bytes:
   - For the declared password field: hand the bytes to `vault.store`, which copies them into its own vault buffer (in its own short protected-mode window), transitions the vault buffer to `PROT_NONE`, and returns a vault_id. The parser records `("pw" → vault_id)` in a sidecar map.
   - For non-password fields: handle normally — these will be re-parsed from the redacted body after protected mode exits, so the parser just notes them without producing Caspian values yet.
5. **Exit protected mode.** sodium_memzero the parse buffer (wipe any remaining bytes), sodium_free it (release the memory). The protected-mode window closes. From this point on, the only place the password bytes exist in memory is inside the vault, under PROT_NONE.
6. **Normal request processing.** Touchstone produces the `$request` object using ordinary parsing on the redacted body (which has the password field's value replaced by the placeholder string `"####"`). It overlays the sidecar map: for each entry, it constructs a Password object whose bucket holds the vault_id and assigns it to the corresponding field on `$request`.
7. **Handler runs.** From the first moment user code can touch `$request['pw']`, it's already a Password — there's no point in the request lifecycle where user code can reach a plaintext string for that field.
8. **Verify.** The handler calls `$request['pw'].verify($user.stored_hash)`. The Password method delegates to `vault.verify_password(@vault_id, stored_hash)`, which opens its own internal protected-mode window: mprotects the vault buffer to PROT_READONLY briefly, runs argon2id_verify with the stored hash's salt+params, constant-time compares, mprotects back to PROT_NONE. Returns true/false. No plaintext crosses any user-reachable boundary.
9. **Lifecycle.** When the handler returns and `$request` goes out of scope, the Password's `on_close` hook fires, calls `vault.erase(@vault_id)`, and the vault entry is freed (sodium_free zeros and releases). If the handler had finished with the Password earlier, it could call `$pw.destroy` explicitly for immediate cleanup.

### Redaction via sidecar map

The redacted body has the password field's value replaced with the string `"####"`. So a form-encoded body `id=picard&pw=secret` becomes `id=picard&pw=####`; a JSON body `{"id": "picard", "pw": "secret"}` becomes `{"id": "picard", "pw": "####"}`. The actual mapping from field name to vault entry rides on a separate sidecar map, not in the body itself.

Using `"####"` rather than an empty string or null serves three purposes: it's visually obvious in any log or debug context that the slot was deliberately redacted (not a missing field, not a user-submitted blank); it keeps the field non-empty so post-parse code that checks "did the user supply this field?" still sees something; and the same literal works across body formats — form, JSON, multipart — without per-format placeholder logic.

**Length-tracking metadata has to be reset after redaction.** Replacing the password value almost always changes the body's byte count, which means several things have to be recomputed before the redacted body is handed off:

- **`Content-Length` HTTP header.** Must match the new body length, or the main parser (and any downstream code that reads the header) will be off-by-N. This is the most common case to get wrong.
- **Chunked transfer-encoding chunk sizes.** If the body arrived chunked and a password's bytes spanned (or were inside) a chunk, the chunk's size header has to be rewritten to the post-redaction length. Multi-chunk bodies that contain passwords may need to be re-chunked entirely.
- **Multipart-form boundary positions and any per-part counters.** Each part's size moves when the password value inside it changes length; any boundary offsets the engine tracks have to be recomputed.
- **Any engine-internal byte counts** the pre-pass hands to the main parser. If the protected-mode pre-pass passes a "this body is N bytes" hint along with the redacted bytes, N has to be the post-redaction length, not the original.

The protected-mode pre-pass is responsible for all of this. Touchstone code outside the window should never see a length number tied to the original body — only the redacted body and its post-redaction lengths.

This keeps the main parser oblivious to the Password class. It just sees the string `"####"` where the password used to be. The sidecar map is what reconstitutes the Password reference when `$request` is constructed.

Two reasons to use a sidecar map rather than in-body placeholders:

- **The main parser stays simple.** It doesn't need to know about Password as a value type, doesn't need to recognize a placeholder syntax, doesn't need to perform any vault interaction itself. Strictly normal parsing on strictly normal bytes.
- **The placeholder syntax isn't a thing.** Inventing a syntax like `<<VAULT:abc-123>>` to mean "this slot is in the vault, look up abc-123" would mean every parser (form-encoded, JSON, multipart, etc.) has to recognize it AND every place a redacted body might end up (logs, debug dumps, proxies) might display the placeholder confusingly. The sidecar map avoids this entirely.

### The two-parser risk

If the pre-pass parser inside protected mode and the post-protected-mode main parser interpret the body differently, an attacker can craft a body where the pre-pass thinks the password is at byte range X but the main parser reads it from byte range Y. The pre-pass redacts X, leaving Y intact — and the main parser sees the password as a plain string. This is the same bug class that hit early Rails, ModSecurity, and many other frameworks: two-parser disagreement is an attacker's playground.

Two ways to prevent it, in order of cleanliness:

1. **One parser, two output sinks.** The parser runs once, inside protected mode. As it identifies each field, it dispatches the bytes to the right destination: vault for declared password fields, normal field map for everything else. No second parse, no redacted body, no sidecar map needed at the parser level — though the sidecar pattern is still useful as the interface between the protected-mode pre-pass and the rest of Touchstone's `$request`-construction code. One parser is the only way to guarantee no divergence.
2. **Same parser code, two passes.** If for some reason a one-pass implementation is infeasible (e.g., streaming bodies where pre-decisions about field allocation can't be made before content is seen), run the parser twice with the same code, once in protected mode for password extraction and once outside for everything else. Identical parsing logic per call guarantees no divergence between the two passes. Pays the cost of a second parse per request with passwords.

The reference implementation uses option 1. Option 2 is documented as the fallback if streaming or other architectural constraints make the one-pass approach impractical for some body format.

### What this guarantees and what it doesn't

What it guarantees, end-to-end:

- The password plaintext never exists as a `puck.uno/string` or any other user-reachable Caspian value.
- The plaintext exists in engine memory only inside protected-mode windows, under sodium_malloc protection.
- Logs, debug snapshots, exception traces, worldlet serialization, and any other place user code might dump request state see the Password object — never the plaintext.
- Verification works without ever materializing the plaintext outside a brief, mprotect-bracketed window inside vault.verify_password.

What it doesn't guarantee:

- **TLS termination is upstream of Caspian.** If the deployment terminates TLS at Cloudflare or nginx, the plaintext is in that upstream's memory before it reaches Caspian. The protected-mode pre-pass starts at the bytes-in-engine-memory boundary; whatever happened before that is the upstream's responsibility.
- **Processes with `ptrace` access (debugger, root) can bypass mprotect.** The protection is against in-process accidents and unauthorized memory reads, not against privileged inspection of the process. The Linux-specific mitigations from Part 1 (`prctl(PR_SET_DUMPABLE, 0)`, `ptrace_scope` sysctl) raise that bar but don't eliminate it.
- **Side-channel attacks** (cache timing, Spectre/Meltdown, Rowhammer) are out of scope for in-process memory protection.

## See also

- [passkeys.md](passkeys.md) — how the vault + protected-mode model applies (and where it simplifies) for passkey-based authentication; sketches a Passkey class for both the relying-party and authenticator sides.
