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

Ed25519 signing and verification. Used by the blockchain integration for signed library endorsements and signed records.

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
