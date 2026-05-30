# Passkeys

~~~json
{"vibecode": {
	"doc": "passkeys",
	"role": "implementation sketch for WebAuthn / FIDO2 passkeys in Caspian; assumes the reader knows the protocol and is asking what the class shape, engine primitives, and integration points look like",
	"status": "speculative — not a current implementation target; documented so the design is ready when it becomes one",
	"related": ["index.md (parent security model — vault, protected mode, libsodium memory protection)"],
	"audience": "Caspian implementers"
}}
~~~

## Executive summary

Two `Passkey` classes for the two WebAuthn roles:

- **Server side (relying party):** holds credential metadata in regular bucket fields; verifies assertions via libsodium signature primitives. No vault needed — nothing in the bucket is crypto-secret.
- **Authenticator side:** holds the private key in the vault; signs through `vault.sign` gateway operations. Uses the existing vault + protected-mode model (see [index.md](index.md)).

Both are user-space Caspian classes. The only genuinely new engine dependency is a **CBOR decoder** for COSE_Key parsing and attestation/assertion objects. Everything else (CSPRNG, signature primitives, vault) is already on the roadmap for unrelated reasons.

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
| `.verify(assertion, expected_challenge, expected_origin)` | true / raises | Validates clientData (challenge, origin, type), authenticatorData (rpIdHash, user-present flag), sign_count progression, signature against the stored public key. Mutates `@sign_count` and `@last_used_at` on success. Raises specific exception classes per failure mode. |
| `.id` | string | The credential ID. |
| `.algorithm_name` | string | Human-readable alg name. |
| `.transports`, `.aaguid`, `.user_handle` | various | Accessors for the corresponding fields. |
| `.label` / `.label=(value)` | string | Read/set the user-supplied nickname. |
| `.is_backed_up?` / `.is_backup_eligible?` | boolean | Sync-state predicates. |
| `.created_at`, `.last_used_at` | timestamp | Timestamps. |
| `.to_storage_hash` | hash | Serialize for DB storage. |
| `.matches_aaguid?(known_aaguid_list)` | boolean | Convenience for authenticator-model policy checks. |

### Class methods

| Method | Returns | Notes |
|---|---|---|
| `Passkey.generate_challenge` | bytes | Fresh random via libsodium CSPRNG. |
| `Passkey.parse_registration(attestation_object, client_data_json, expected_challenge, expected_origin, expected_rp_id)` | Passkey instance | Validates attestation; extracts and caches the public key. |
| `Passkey.parse_assertion(assertion_object, client_data_json)` | hash | Returns `{credential_id, authenticator_data, client_data_json, signature, user_handle}` so the caller can look up the matching Passkey by `credential_id` and call `.verify` on it. |
| `Passkey.from_storage(hash)` | Passkey instance | Reconstruct from `.to_storage_hash`. |

### Exception classes raised by `.verify`

| Class | Cause |
|---|---|
| `puck.uno/passkey/error/challenge_mismatch` | clientData.challenge ≠ expected_challenge |
| `puck.uno/passkey/error/origin_mismatch` | clientData.origin ≠ expected_origin |
| `puck.uno/passkey/error/type_mismatch` | clientData.type ≠ `"webauthn.get"` |
| `puck.uno/passkey/error/rp_id_mismatch` | authenticatorData.rpIdHash ≠ SHA-256(expected_rp_id) |
| `puck.uno/passkey/error/user_not_present` | UP flag not set in authenticatorData |
| `puck.uno/passkey/error/user_not_verified` | UV flag required but not set |
| `puck.uno/passkey/error/sign_count_regression` | assertion's sign_count ≤ stored sign_count |
| `puck.uno/passkey/error/signature_invalid` | cryptographic signature verification failed |

### Why no vault

Every bucket field is non-secret. Public keys, credential IDs, sign counts, and metadata can live in regular DB columns without protection. The vault and protected-mode machinery aren't engaged on the server side.

## Authenticator-side Passkey class

Used when Caspian holds private keys (server-to-server passkey-style auth, hosted passkey provider service, CI/CD signing agent).

### Bucket fields

| Field | Type | Purpose |
|---|---|---|
| `vault_id` | string | Handle to the private key in the vault. |
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
| `.sign(message)` | signature bytes | Calls `vault.sign(@vault_id, message)`. The vault gateway opens a protected-mode window, mprotects the buffer readable, runs the signing primitive, mprotects back. |
| `.public_key` | bytes (COSE_Key) | Cached public half. |
| `.credential_id`, `.algorithm`, `.algorithm_name`, `.relying_party_id`, `.sign_count` | various | Accessors. |
| `.sign_count_increment!` | new count | Bump the local counter after each successful sign. |
| `.export_attestation(challenge, rp_id, ...)` | attestation object | Produce a registration response (when registering with a new RP). Internally signs through the vault gateway. |
| `.destroy` | nil | Erase the vault entry. |

### Class methods

| Method | Returns | Notes |
|---|---|---|
| `Passkey.generate(algorithm:, relying_party_id:, user_handle:)` | Passkey instance | Generates a keypair via libsodium, extracts the public key (cached in the bucket), pipes the private key into `vault.store`, returns the instance. The plaintext private key never reaches a regular Caspian value. |
| `Passkey.from_storage(hash, vault_id)` | Passkey instance | Reconstruct at startup. Caller is responsible for populating the vault entry separately (usually via a startup loader that reads encrypted key material from disk through `vault.store`). |

### What's never exposed

- The private key bytes. No accessor returns them; `.sign` and `.export_attestation` are the only operations.
- The vault ID is exposed (as `@vault_id`) but it's useless without the engine's gateway.

## Required engine primitives

| Primitive | Status | Use |
|---|---|---|
| libsodium CSPRNG | exists | Challenge generation; salt generation. |
| libsodium signature verify (Ed25519) | exists | EdDSA assertion verify. |
| libsodium / OpenSSL signature verify (ES256, RS256) | depends on algorithm support already present in the engine | ES256 / RS256 assertion verify. |
| libsodium key generation | exists | Authenticator-side keypair generation. |
| `vault.sign` gateway operation | planned for general signing-key support | Authenticator-side signing. |
| CBOR decoder | **new** | COSE_Key parsing; attestation/assertion object parsing. |

The CBOR decoder is the only genuinely new dependency. Options:

- C-binding to an existing library (cn-cbor, tinycbor).
- Pure-Caspian implementation. WebAuthn touches a small subset of CBOR; a focused implementation is feasible.

The lean is a C-binding for performance and correctness (CBOR has subtle edge cases — duplicate keys, integer canonicalization, indefinite-length encodings — and existing libraries have already worked them out).

## Open: packaging

Whether `Passkey` ships in core, in a standard-library package, or as third-party Caspian code is a packaging call, not a security one. Reasonable to defer until passkey support is a live implementation priority. The class is straightforward Caspian code once the primitives above are in place.
