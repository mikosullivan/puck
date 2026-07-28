# Passkey

<span class="tag">passkey</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_secure_memory_passkey",
	"role": "spec for Caspian's Passkey classes (WebAuthn / FIDO2). Two roles: server-side relying party (holds non-secret credential metadata, verifies assertions via libsodium signature primitives) and authenticator-side (holds the private key in the vault, signs through vault.sign gateway operations). Both are Caspian classes built on top of the [vault](tag:vault) — no new memory-protection primitives needed. The only genuinely new engine dependency is a CBOR decoder for COSE_Key and attestation/assertion parsing.",
	"status": "spec — class shape, method surface, and exception model settled from the design pass; CBOR-decoder packaging (C binding vs pure-Caspian implementation) and exact algorithm support (ES256/EdDSA/RS256) pending implementation-time decisions",
	"audience": "Caspian developers implementing WebAuthn login flows or passkey-style server-to-server authentication; anyone building or auditing the Passkey classes themselves"
}}
~~~

Caspian's Passkey classes for WebAuthn / FIDO2 authentication. Two roles, two classes:

- **Server-side (relying party):** holds credential metadata in regular bucket fields; verifies assertions via libsodium signature primitives. No vault needed — nothing in the bucket is crypto-secret.
- **Authenticator-side:** holds the private key in the [vault](tag:vault); signs through `vault.sign` gateway operations. Uses the vault + protected-mode model spec'd in the sibling protected/ pages.

Both are Caspian classes. The only genuinely new engine dependency is a **CBOR decoder** for COSE_Key parsing and attestation / assertion objects. Everything else (CSPRNG, signature primitives, vault) is already available or on the roadmap for unrelated reasons.

## Server-side Passkey class

### Bucket fields

| Field | Type | Purpose |
|---|---|---|
| `credential_id` | bytes (base64url string for storage) | DB-lookup key during auth. |
| `public_key` | bytes (COSE_Key CBOR) | The credential's public key. |
| `algorithm` | integer | COSE alg identifier (`-7` ES256, `-8` EdDSA, `-257` RS256). |
| `sign_count` | integer | Monotonic counter; updated on each successful verify. |
| `transports` | array of strings | `usb` / `nfc` / `ble` / `internal`. |
| `user_handle` | bytes | RP's reference to the user. |
| `aaguid` | bytes (16) | Authenticator model identifier. |
| `backup_eligible`, `backup_state` | boolean | Sync state. |
| `created_at`, `last_used_at` | timestamp | Lifecycle timestamps; `last_used_at` updated on verify. |
| `user_label` | string | Optional user-supplied nickname. |

### Instance methods

| Method | Returns | Notes |
|---|---|---|
| `.verify assertion, expected_challenge, expected_origin` | true / raises | Validates clientData (challenge, origin, type), authenticatorData (rpIdHash, user-present flag), sign_count progression, signature against the stored public key. Mutates `@sign_count` and `@last_used_at` on success. Raises specific exception classes per failure mode (see below). |
| `.id` | string | The credential ID. |
| `.algorithm_name` | string | Human-readable alg name. |
| `.transports`, `.aaguid`, `.user_handle` | various | Accessors for the corresponding fields. |
| `.label` / `.label=` | string | Read/set the user-supplied nickname. |
| `.is_backed_up?` / `.is_backup_eligible?` | boolean | Sync-state predicates. |
| `.created_at`, `.last_used_at` | timestamp | Timestamps. |
| `.to_storage_hash` | hash | Serialize for DB storage. |
| `.matches_aaguid? known_aaguid_list` | boolean | Convenience for authenticator-model policy checks. |

### Class methods

| Method | Returns | Notes |
|---|---|---|
| `Passkey.generate_challenge` | bytes | Fresh random via libsodium CSPRNG. |
| `Passkey.parse_registration attestation_object, client_data_json, expected_challenge, expected_origin, expected_rp_id` | Passkey instance | Validates attestation; extracts and caches the public key. |
| `Passkey.parse_assertion assertion_object, client_data_json` | hash | Returns `{credential_id, authenticator_data, client_data_json, signature, user_handle}` so the caller can look up the matching Passkey by `credential_id` and call `.verify` on it. |
| `Passkey.from_storage hash` | Passkey instance | Reconstruct from `.to_storage_hash`. |

### Exception classes raised by `.verify`

| Class | Cause |
|---|---|
| `puck.uno/passkey/error/challenge_mismatch` | `clientData.challenge` ≠ `expected_challenge` |
| `puck.uno/passkey/error/origin_mismatch` | `clientData.origin` ≠ `expected_origin` |
| `puck.uno/passkey/error/type_mismatch` | `clientData.type` ≠ `"webauthn.get"` |
| `puck.uno/passkey/error/rp_id_mismatch` | `authenticatorData.rpIdHash` ≠ SHA-256(`expected_rp_id`) |
| `puck.uno/passkey/error/user_not_present` | UP flag not set in `authenticatorData` |
| `puck.uno/passkey/error/user_not_verified` | UV flag required but not set |
| `puck.uno/passkey/error/sign_count_regression` | assertion's `sign_count` ≤ stored `sign_count` |
| `puck.uno/passkey/error/signature_invalid` | cryptographic signature verification failed |

### Why no vault on the server side

Every bucket field is non-secret. Public keys, credential IDs, sign counts, and metadata can live in regular DB columns without protection. The vault and protected-mode machinery aren't engaged on the server side — the server never possesses any bytes that need to be hidden from user code.

## Authenticator-side Passkey class

Used when Caspian holds private keys — server-to-server passkey-style auth, hosted passkey-provider services, CI/CD signing agents, etc.

### Bucket fields

| Field | Type | Purpose |
|---|---|---|
| `vault_id` | string | Handle to the private key in the [vault](tag:vault). |
| `credential_id` | bytes | Assigned at registration. |
| `public_key` | bytes (COSE_Key CBOR) | Cached public half — kept in the bucket since it's public. |
| `algorithm` | integer | COSE alg identifier. |
| `relying_party_id` | string | The RP this key serves. |
| `user_handle` | bytes | RP's user reference. |
| `sign_count` | integer | Local counter. |
| `created_at` | timestamp | Generation timestamp. |

### Instance methods

| Method | Returns | Notes |
|---|---|---|
| `.sign message` | signature bytes | Calls `vault.sign(@vault_id, message)`. The vault gateway opens a protected-mode window, `mprotect`s the buffer readable, runs the signing primitive, `mprotect`s back. |
| `.public_key` | bytes (COSE_Key) | Cached public half. |
| `.credential_id`, `.algorithm`, `.algorithm_name`, `.relying_party_id`, `.sign_count` | various | Accessors. |
| `.sign_count_increment!` | new count | Bump the local counter after each successful sign. |
| `.export_attestation challenge, rp_id, ...` | attestation object | Produce a registration response (when registering with a new RP). Internally signs through the vault gateway. |
| `.destroy` | nil | Erase the vault entry. |

### Class methods

| Method | Returns | Notes |
|---|---|---|
| `Passkey.generate algorithm:, relying_party_id:, user_handle:` | Passkey instance | Generates a keypair via libsodium, extracts the public key (cached in the bucket), pipes the private key into `vault.store`, returns the instance. The plaintext private key never reaches a regular Caspian value. |
| `Passkey.from_storage hash, vault_id` | Passkey instance | Reconstruct at startup. Caller is responsible for populating the vault entry separately (usually via a startup loader that reads encrypted key material from disk through `vault.store`). |

### What's never exposed

- **The private key bytes.** No accessor returns them; `.sign` and `.export_attestation` are the only operations that use them, and both go through the vault gateway. Same guarantee as [Password](../password) — the class is a handle, not a container.
- **The vault ID is exposed** as `@vault_id`, but it's useless without the engine's gateway.

## Required engine primitives

| Primitive | Status | Use |
|---|---|---|
| libsodium CSPRNG | exists | Challenge generation; salt generation. |
| libsodium signature verify (Ed25519) | exists | EdDSA assertion verify. |
| `openssl` subprocess (ES256, RS256) | new — via the [linux/cli/openssl](https://puck.uno/documentation/requirements/linux/cli/openssl) wrapper class; operator-provided | ES256 / RS256 assertion verify. |
| libsodium key generation | exists | Authenticator-side keypair generation. |
| `vault.sign` gateway operation | planned for general signing-key support (see [vault § Gateway operations](tag:vault-gateway-ops)) | Authenticator-side signing. |
| CBOR decoder | new — fetched on first passkey use via `%(caspian.uno/cbor.casp)` (V1 download, spec deferred) | COSE_Key parsing; attestation / assertion object parsing. |

The CBOR decoder is the only genuinely new dependency. It is a **V1 download requirement** — fetched via `%(caspian.uno/cbor.casp)` on the first passkey call, then cached locally like any other `%fetch` object. The specific implementation (pure-Caspian decoder, C binding, or something else) is deferred; the requirement V1 commits to is that passkey code reaches it through the puck.uno URL, not that a specific library ships in the core install. Zero install-download cost; small first-use fetch when a program actually touches passkeys.

CBOR has subtle rules around duplicate keys, integer canonicalization, and indefinite-length encodings that a well-audited library has already worked out. Correctness matters here — sloppy CBOR handling has been the root of several WebAuthn implementation vulnerabilities, and a mature library is the right dependency to bring in rather than reinvent.

## Implementation split

Per [concepts § Caspian is written in Caspian](../../concepts#caspian-is-written-in-caspian), the Passkey implementation keeps the host-language (Lua / C) surface as small as possible; everything above the primitive line is Caspian.

### Lua / C (new)

- **CBOR decoder** (`%(caspian.uno/cbor.casp)`, V1 download requirement, spec deferred). Takes bytes, returns a Caspian hash. All downstream COSE_Key, authenticatorData, and attestation-object walking then happens on that hash in Caspian.

### Lua / C (existing, reused)

- **Ed25519 signature verify** via libsodium (in-process).
- CSPRNG for challenge and salt generation.
- SHA-256 for `rpIdHash` computation.
- Key generation (authenticator-side registration).
- `vault.sign` and `vault.store` gateway operations — planned for the vault subsystem generally.

### External utility (subprocess)

- **ES256 and RS256 signature verify** via the operator-installed `openssl` binary. The [linux/cli/openssl](https://puck.uno/documentation/requirements/linux/cli/openssl) wrapper class serializes the public key from COSE_Key form into PEM, feeds message and signature via stdin / mode-600 temp files (never argv — that would leak to `ps`), reads the exit code. `openssl` is a documented Passkey prerequisite in the same posture as `luarocks` and `tar`; if it's not on the search path, the Passkey subsystem doesn't initialize and a clear error surfaces the first time user code touches it.

### Caspian

- Both Passkey class definitions (server-side and authenticator-side): fields, method surface, exception classes.
- All method bodies — `.verify`, `.sign`, `.export_attestation`, `.destroy`, accessors, `.sign_count_increment!`.
- All assertion-validation logic — challenge / origin / type / rpIdHash checks, UP / UV flag checks, sign_count progression, dispatch to the right signature-verify primitive.
- clientData JSON parsing (Caspian JSON is native).
- authenticatorData binary walking (fixed-layout structure).
- COSE_Key and attestation-object walking (after CBOR-decode returns a hash).
- All eight exception classes as regular Caspian classes.
- Class methods — `Passkey.generate_challenge`, `Passkey.parse_registration`, `Passkey.parse_assertion`, `Passkey.from_storage`, `Passkey.generate` — each Caspian code calling primitives where needed.

### Does security survive this split?

Yes.

- **Server-side:** no secrets are ever in play. Every field the server holds is public or metadata. Signature verification runs in a hardened C library either way — libsodium for Ed25519 (in-process), `openssl` for ES256 / RS256 (subprocess) — with constant-time comparison guaranteed. The Caspian layer only decides which primitive to call and what exception to raise on failure. Correctness of the assertion-validation logic matters, but that logic being in Caspian makes it easier to audit, not harder.
- **Authenticator-side:** the private key lives in the [vault](tag:vault) under `PROT_NONE`. The Caspian Passkey code holds a `vault_id` and calls `vault.sign` — same handle-not-container pattern as [Password](../password). Raw private-key bytes never reach the Caspian layer, so keeping the class above the primitive line changes nothing about the key's protection.

The vault gateway is the security boundary in both cases. Everything the Passkey classes do sits above that gateway — Caspian code running under the same rules any user program runs under.

## Packaging

The CBOR-decoder dependency is a **V1 download requirement** reached via `%(caspian.uno/cbor.casp)` — fetched lazily on first passkey use, then cached locally. Removed from the core install download to preserve floppy budget; the specific implementation (pure-Caspian, C binding, etc.) is deferred and spec'd separately. Programs that never touch passkeys pay zero install-download cost and zero runtime cost.

The Passkey classes themselves are Caspian code and are part of the Caspian engine + stdlib bundle in the Executable tier — no separate download.

**ES256 / RS256 signature verify** calls the operator-installed [`openssl`](https://puck.uno/documentation/requirements/linux/cli/openssl) binary directly via `.execute` — subprocess invocation, no shell involved (see [linux-support § Executing files](https://puck.uno/documentation/requirements/linux-support/#executing-files)). Zero bundled bytes; treated as a Caspian prerequisite in the same posture as `luarocks` (third-party Lua libs) and `tar` (self-test tarball extraction). Widely available on every mainstream Linux distro and on macOS. Documented in [linux/cli/openssl](https://puck.uno/documentation/requirements/linux/cli/openssl).

## Related

- [vault](tag:vault) — the storage primitive the authenticator-side Passkey uses via `vault.sign`.
- [password](../password) — the sibling secret-holding class. Same handle-not-container pattern.
- [protected/ index](../) — the umbrella overview.
- [linux/cli/openssl](https://puck.uno/documentation/requirements/linux/cli/openssl) — the wrapper class that invokes the operator-installed `openssl` binary directly for ES256 / RS256 signature verify.
