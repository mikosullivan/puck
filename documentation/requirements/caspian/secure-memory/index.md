# Secure memory

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_secure_memory",
	"role": "index for requirements/caspian/secure-memory/ — Caspian's story for keeping sensitive raw bytes out of reach. Two layers: (1) a libsodium-backed per-secret vault (sodium_malloc'd guarded pages, PROT_NONE by default, narrow operation-oriented gateway) for the specific known secrets, and (2) whole-process OS-level hardening (mlockall, PR_SET_DUMPABLE, Yama ptrace) as deployment-level opt-in for security-critical hosts. The two are independent and complementary. Consumers of these primitives (Password class, future signing-key class, etc.) live in their own docs and reference this section for the mechanism.",
	"status": "spec — two-layer model settled, individual page details firm; engine-config schema and specific opt-in defaults deferred to implementation",
	"audience": "Caspian engine implementers building the secure-memory subsystem; security reviewers; operators deploying Caspian on security-critical hosts"
}}
~~~

Caspian's secure-memory story has two layers, solving different problems:

- **[Vault](vault)** — libsodium-backed per-secret storage. Each entry lives in a `sodium_malloc`'d region with guard pages, `mlock`'d into RAM, `PROT_NONE` by default. Access only through a narrow operation-oriented gateway (`vault.verify_password`, `vault.sign`, `vault.erase` — never a `.get()` that returns raw bytes). Always in play whenever the engine holds sensitive material.
- **[Process security](process-security)** — OS-level hardening applied to the entire engine process: `mlockall` to prevent any swap-to-disk, `PR_SET_DUMPABLE` to block coredumps and tighten ptrace, Yama `ptrace_scope` requirements, encrypted-swap and no-hibernation posture. Deployment-level opt-in — not on by default because each setting has real operational tradeoffs.

The two are independent but complementary. The vault handles the specific bytes we know are sensitive. Process-level hardening blocks whole classes of attacks (swap, coredumps, `ptrace` inspection) that would bypass in-process protections regardless of what the vault does.

## Driving use case: HTTP password intake

The concrete need that shaped this whole subsystem: parse an HTTP request containing a password or passkey **without the plaintext ever existing as a normal string in main memory**. At no point should there be a plaintext value that could end up in a coredump, get accidentally written to a log, or persist in some intermediate buffer that never gets zeroed.

Sketch of the flow:

1. HTTP request arrives at Caspian (login form, key upload, etc.).
2. Route lookup identifies the request as having a declared password / passkey field in its schema.
3. Body parsing runs **inside a protected-mode window** — a `sodium_malloc`'d buffer holding the raw bytes (see [vault § Protected mode](vault#protected-mode)).
4. The parser identifies the password field's bytes and hands them to [`vault.store`](vault#gateway-operations). The bytes are copied into a `PROT_NONE`'d vault entry; a `vault_id` comes back.
5. The parser writes a placeholder (`"#####"` or similar) into the body position where the password was.
6. Protected mode exits: the parse buffer is `sodium_memzero`'d and `sodium_free`'d. From this point on, the plaintext exists **only** in the vault, under `PROT_NONE`.
7. Normal request processing continues with the modified body — safe to log, further parse, forward downstream. A sidecar map ties field name → `vault_id`, so when `$request` is constructed, the password field appears as a `Password` object holding the vault handle.
8. User code sees `$request['pw']` as a `Password` from the first moment it can touch anything. Verification (`$request['pw'].verify(hash)`) delegates to `vault.verify_password(id, hash)` — briefly `PROT_READONLY` inside the vault, constant-time compare, back to `PROT_NONE`. Plaintext never crosses a user-reachable boundary.

**End state after all of this:**

- **Vaulted password** available via the `Password` handle in `$request`.
- **Modified request body** (with placeholder) safe to serialize, log, forward downstream.

**How each piece contributes:**

- **The [vault](vault)** provides the `sodium_malloc`'d storage, the operation-oriented gateway (`vault.store`, `vault.verify_password`, `vault.erase`), and the protected-mode discipline that bounds which engine code paths ever touch raw bytes. See [vault § The HTTP intake flow](vault#the-http-intake-flow) for the parser-level details.
- **[Process security](process-security)** provides the surrounding hardening: `mlockall` ensures pre-vaulting bytes can't be swapped; `PR_SET_DUMPABLE` prevents a coredump during the protected-mode window from exposing them; the ptrace restrictions prevent an unprivileged local attacker from attaching a debugger. See [process-security § How this supports the HTTP intake use case](process-security#how-this-supports-the-http-intake-use-case).

Together they make the airtight claim: **the plaintext exists in memory only inside a `sodium_malloc`'d region, only briefly (during parsing → vault transfer, and during vault gateway operations), and is protected against every leakage path the OS gives us tools for.**

## When each applies

- **A specific secret exists** (password, API token, private key). → The vault. Always.
- **The whole process handles sensitive material broadly**, or the deployment target has strict compliance requirements. → Turn on process-security settings on top of the vault.
- **You need defense-in-depth without enterprise-grade hardening.** → Vault only. Process-security has real deployment tradeoffs (`RLIMIT_MEMLOCK` requirements, OOM risk under memory pressure).

## In this section

- [vault](vault) — the per-secret storage primitive: `sodium_malloc` internals, gateway operations, protected-mode discipline, `RLIMIT_MEMLOCK` handling, threat model.
- [process-security](process-security) — whole-process OS-level hardening: `mlockall`, `PR_SET_DUMPABLE`, Yama ptrace, hibernation and swap concerns, engine configuration knobs.
- [password](password/) — the Password class spec: argon2id default, method contracts, aliasing / destroy semantics, lifecycle.
- [passkey](passkey/) — the Passkey class spec: two roles (server-side relying party, authenticator-side signer), class API for both, exception classes, CBOR decoder as the one new engine dependency.
- [ui](ui) — the developer-facing surface: `Password` class API, declaring password fields in HTTP route schemas, `%process.malloc` explicit blocks, engine-config for process-security settings, anti-patterns.

## Consumers

- **[Password](password/)** — uses the vault to hold plaintext passwords. The class itself is a thin handle whose bucket holds a vault ID; methods delegate to vault gateway operations. Argon2id by default via libsodium.
- **[Passkey](passkey/)** — authenticator-side uses the vault to hold WebAuthn / FIDO2 private keys; signs through `vault.sign`. Server-side (relying party) doesn't need the vault — nothing in its bucket is secret.
- **Future signing-key class, session-token class, etc.** — same pattern. Any Caspian object type whose bytes must never be reachable from user code uses the vault.
