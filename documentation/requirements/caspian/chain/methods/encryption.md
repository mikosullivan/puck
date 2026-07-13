# `%chain.encryption`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_encryption",
	"role": "spec for %chain.encryption — cryptographic primitives. Ed25519 signing under .signing; SHA hashing and HMAC under .sha. NOT for password storage."
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.encryption` is the container for cryptographic primitives. Two sub-surfaces.

## `%chain.encryption.signing`

Ed25519 signing and verification. Used by the blockchain integration for signed object endorsements and signed records.

| Method | Purpose |
|---|---|
| `.generate_keypair()` | Fresh Ed25519 keypair. |
| `.sign($private_key, $bytes)` | Produce a signature over `$bytes`. |
| `.verify($public_key, $signature, $bytes)` | Check a signature; returns boolean. |
| `.keypair_from_seed($seed)` | Deterministic keypair from a seed. |
| `.import_key(...)` / `.export_key(...)` | PEM / DER / raw-bytes interchange. |

## `%chain.encryption.sha`

SHA-family hashing primitives.

| Method | Purpose |
|---|---|
| `.sha256($data)` | SHA-256 digest as a hex string. |
| `.sha512($data)` | SHA-512 digest as a hex string. |
| `.hmac_sha256($key, $data)` | HMAC-SHA-256. |
| `.hmac_sha512($key, $data)` | HMAC-SHA-512. |

The slot is named `sha` rather than `hash` because it's SHA-family specifically. Other hash families (BLAKE2/3, etc.) would get their own slots when needed.

## Not for password storage

Neither sub-surface is the right tool for password hashing. Passwords have their own separate spec covering Argon2id, salt management, and verification — see `ideas/caspian/passwords/` for the in-progress design.

## Testing

- **`%chain.encryption` is present by default** — no host grant is required; the surface is always populated.
- **Default-granted across role boundaries** — a role reached from user code sees `%chain.encryption` without an explicit grant.
- **Sub-surface separation** — `%chain.encryption.signing` and `%chain.encryption.sha` are distinct namespaces; `%chain.encryption.sha.sign` is undefined.
- **`.signing.generate_keypair` returns a fresh keypair** — two consecutive calls return distinct public keys.
- **`.signing.generate_keypair` shape** — the return value exposes a public key and a private key of the sizes Ed25519 mandates.
- **`.signing.sign` returns a 64-byte signature** — `sign($sk, $bytes)` returns Ed25519's fixed-length signature.
- **`.signing.verify` accepts a valid signature** — `verify($pk, $sig, $bytes)` returns `true` when the signature was produced by the matching private key over the same bytes.
- **`.signing.verify` rejects a tampered payload** — flipping a byte in `$bytes` causes `verify` to return `false`.
- **`.signing.verify` rejects a tampered signature** — flipping a byte in `$sig` causes `verify` to return `false`.
- **`.signing.verify` rejects a mismatched key** — verifying under a different public key returns `false`, never raises.
- **`.signing.keypair_from_seed` is deterministic** — the same seed produces the same keypair every call.
- **`.signing.keypair_from_seed` — different seeds diverge** — two distinct seeds produce distinct keypairs.
- **`.signing.sign` handles empty bytes** — signing `""` succeeds and produces a signature that `verify` accepts.
- **`.signing.sign` handles unicode bytes** — signing UTF-8 bytes of a non-ASCII string succeeds and verifies.
- **`.signing.sign` with a wrong-size private key raises** — passing a key whose length is not Ed25519's private-key length raises.
- **`.signing.import_key` / `.export_key` round-trip** — exporting a key and re-importing it yields a functionally identical key (signatures verify across the boundary).
- **`.signing.import_key` supports PEM, DER, and raw** — each of the three interchange forms round-trips correctly.
- **`.sha.sha256` known vector** — `sha256("")` returns `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- **`.sha.sha256` "abc" vector** — `sha256("abc")` returns `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
- **`.sha.sha256` returns a lowercase hex string** — no `0x` prefix, no uppercase, length 64.
- **`.sha.sha256` on unicode input** — hashing UTF-8 bytes of a non-ASCII string returns the SHA-256 of those bytes.
- **`.sha.sha512` known vector** — `sha512("")` returns the documented 128-hex-char digest.
- **`.sha.hmac_sha256` known vector** — matches RFC 4231 Test Case 1.
- **`.sha.hmac_sha512` known vector** — matches RFC 4231 Test Case 1.
- **`.sha.hmac_sha256` empty key** — produces the HMAC-SHA-256 of the data under a zero-length key without raising.
- **`.sha.hmac_sha256` empty data** — produces the HMAC-SHA-256 of an empty message under the given key without raising.
