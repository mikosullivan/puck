# Puck blockchain (Ledger fetcher)
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_puck_discovery_blockchain",
	"role": "spec for the Puck blockchain fetcher — nickname Ledger — a fetcher class in %fetch.fetchers that resolves URLs by querying blockchain.puck.uno for signed endorsements of what should live at the URL. Covers the blockchain's high-level role (append-only ledger of signed endorsements linking URLs to artifact hashes, license, semver), the fetcher's use of the /v1/download endpoint (server fetches origin, verifies against signed hash, returns bytes plus the signed endorsement in a response header so the client can verify locally without a second round-trip), the /v1/endorsement endpoint for verification-only lookups, and the separate role the blockchain plays as a trust anchor for verifying content returned by any fetcher (not just Ledger). V1 scope note: Caspian ships the client, signing verification, and native support for the service interface, but does not ship the chain engine itself; that lives at blockchain.puck.uno as a Puck-run service.",
	"status": "draft — brought over from the requirements-old blockchain design; API endpoints, response contracts, and trust model settled at the sketch level; per-endpoint field details, semver interaction, and configuration surface all still to be filled in.",
	"audience": "developers who want to understand where Puck objects come from with signed provenance; anyone configuring the Ledger fetcher; class authors writing engine-side verification code; anyone thinking about the trust-anchor question independently from the fetcher question"
}}
~~~

The Puck blockchain is an append-only ledger of **signed endorsements** hosted at `blockchain.puck.uno`. Each endorsement binds a URL to a signed record of what should live at that URL — an artifact hash, a semver (when applicable), a license, an effective date, and any other endorsement-carrying fields the record type supports. The chain does **not** store the artifact bytes themselves. Bytes live at the origin URL (or in mirrors). The chain stores the cryptographic anchor that lets a fetcher — or any downstream verifier — confirm that a set of bytes truly is what was published under that URL.

Two orthogonal roles play out through this design, and it's important to keep them separate:

- **Fetcher role.** The blockchain service is a source of bytes. When queried for a URL, it fetches the origin, verifies the bytes against the signed hash, and returns them (or fails). This is the [Ledger](#the-ledger-fetcher) fetcher class described on this page.
- **Trust-anchor role.** Independent of where bytes come from, the blockchain determines *which chain's signatures are trusted*. This is spec'd separately (see [Trust anchor](#trust-anchor-separate-from-fetching) below).

Signatures are portable. Whichever fetcher returns the bytes for a URL, the engine verifies them against whichever chain is configured as the trust anchor — the two decisions come apart cleanly.

## The Ledger fetcher

Nickname: **Ledger.** A fetcher class in `%fetch.fetchers` that resolves URLs by querying `blockchain.puck.uno`. When the array-walk reaches Ledger, it:

1. Issues `GET /v1/download?url=<encoded-URL>` against `blockchain.puck.uno`.
2. The service looks up the signed endorsement for the URL, fetches the origin bytes, computes the hash, and compares against the signed value.
3. On match, the service returns the raw bytes with the artifact's own Content-Type in the HTTP response and includes the signed endorsement in a response header so the client can verify locally without a second round-trip.
4. On any failure (no endorsement, hash mismatch, origin unreachable), the service returns the appropriate error status and Ledger passes — the next fetcher in the array is tried.

Ledger sits in `%fetch.fetchers` alongside Wire, the Cache instances, and any host-specific translators. Its natural place is **after any local caches** (fast, offline) and **before Wire** (direct network) — a trip through the blockchain is a network round-trip, but it delivers verified bytes rather than raw ones.

## The service API

`blockchain.puck.uno` exposes two endpoints used by the Ledger fetcher and by any code that wants to verify a URL's endorsement directly.

### `GET /v1/download`

Returns the raw artifact bytes for a URL after server-side hash verification.

- **Query parameters:** `url` (required, URL-encoded). Optional filters: `semver=X.Y.Z` (exact-match version) and `at=YYYY-MM-DD` (latest endorsement on or before the date).
- **Success:** HTTP 200 with the artifact bytes in the body. The Content-Type header is the artifact's own type. Two custom response headers:
  - `Endorsement:` the endorsement block (the signed record) in JSON form, so the client can verify the signature without issuing a second call.
  - `Vibecode:` a pointer for cold-agent onboarding.
- **Failures:** the body is empty; HTTP status indicates the situation:
  - `404` — no endorsement exists for that URL.
  - `409` — endorsement exists but the origin bytes don't match the signed hash.
  - `502` — origin unreachable.
  - `501` — the endorsement uses a hash algorithm the service doesn't recognize.

### `GET /v1/endorsement`

Returns the signed endorsement block for a URL, without fetching or hashing the artifact bytes. Used when a caller wants to inspect what the chain says about a URL — for example, to verify a locally-cached copy against the chain, or to decide whether to trust a URL before pulling bytes through a different fetcher.

- **Query parameters:** same as `/v1/download` — `url` (required), optional `semver=` and `at=` filters.
- **Success:** HTTP 200 with `Content-Type: application/json` and a body of the shape `{"success": true, "endorsement": {...}}`.
- **Failure:** HTTP 4xx with `Content-Type: application/json` and a body of the shape `{"success": false, "status": <int>, "resource": "<url>", "message": "<string>"}`.

### Query endpoints

Since a signer may post many endorsements for the same URL over time, and since consumers frequently want to inspect the full history rather than just resolve a single claim, the service exposes query endpoints that return **collections** of chain blocks rather than a single resolved value. Exact endpoint shapes are TBD, but the queries expected at V1:

- **All blocks related to a URL** — returns every chain block that references a given URL (endorse blocks targeting it, deprecate blocks against it, revoke blocks against endorsements about it, and so on). Ordered newest-first.
- **All blocks from a signer** — returns every chain block signed by a given signer (their authority block, plus everything they've endorsed, delegated, deprecated, or revoked). Ordered newest-first.
- **All blocks from a signer about a URL** — the intersection of the two above. The common case for "what does signer S say about URL U?" resolution.

Each query returns JSON with the same `success` boolean contract as the other JSON endpoints. Filters (`semver`, `at`, endorsement type, intent) may be applied to narrow the result set.

*(Full endpoint shapes, pagination behavior, and filter semantics are TBD.)*

### General contract

Both endpoints respect the [content-types spec](https://puck.uno/requirements/content-types) for their responses. The JSON endpoint always returns JSON, even on error, always includes a top-level `success` boolean, and always responds to `Accept` correctly. The byte endpoint is deliberately byte-oriented — success means bytes, failure means an empty body and an HTTP status.

## Endorsements

An endorsement is a **signed record** binding a URL to what the chain believes should be at that URL. Every record carries the URL, the artifact's hash (required; SHA-256 by default), the artifact's license (required), an **endorsement type** naming what the endorsement asserts, and optional metadata (semver, effective date, human-readable name, publisher metadata). The full record structure and the catalog of endorsement types live at [ledger § Endorsement structure](./ledger#endorsement-structure).

Each endorsement is signed with Ed25519. The signing key belongs to the endorser: the URL's own publisher endorses their own artifact; third parties post additional endorsements against an existing record by referencing its `record_hash`. A signer may post any number of endorsements for the same URL over time — later endorsements override earlier ones for whichever claim types they carry, and consumers walk the chain newest-first when looking up a specific claim. See [ledger § Endorsement structure](./ledger#endorsement-structure) for the full resolution model.

The engine ships with a baked-in public key for the Puck-run chain, so signature verification of Ledger responses works out of the box without external key distribution.

## Trust anchor (separate from fetching)

Configuring the chain as a fetcher (via `%fetch.fetchers`) and configuring it as a trust anchor (via a separate setting — working name `%fetch.blockchain`) are **independent choices**. A caller can:

- Fetch through Ledger and verify against Puck's default chain — the common configuration.
- Fetch from a private mirror (a Cache or Wire against an internal URL) and still verify against Puck's default chain — the signature travels with the bytes.
- Fetch from anywhere and verify against a *different* trusted chain (`%fetch.blockchain = 'https://blockchain.example.com'`) — useful for organizations running their own endorsement chains.
- Disable verification entirely (`%fetch.blockchain = null` or `false`) — the escape hatch for developer situations where signature checks get in the way.

The **default** is to verify against Puck's own chain: `%fetch.blockchain = true`.

Details of `%fetch.blockchain` — its exact shape, the semantics of each accepted value, and how it composes with per-fetcher and per-URL overrides — are spec'd separately as they get worked out.

## V1 scope

The V1 Puck ecoverse ships:

- The Ledger fetcher (client code that queries `blockchain.puck.uno` and handles responses).
- Engine-side signature verification with the baked-in Puck public key.
- Configuration surfaces for `%fetch.fetchers` and `%fetch.blockchain`.
- The API contract at `blockchain.puck.uno` — service interface, endpoint shapes, response formats.

The V1 Puck ecoverse **does not** ship the chain engine itself. The append-only ledger lives at `blockchain.puck.uno` as a Puck-run public service; individual Caspian installations do not run their own chain nodes in V1. Third-party chain implementations may be built later, and the trust-anchor mechanism is designed to accommodate them without further Caspian changes.

## Testing

- **Ledger issues `GET /v1/download`** — a Ledger fetch against a URL sends a request to `blockchain.puck.uno/v1/download?url=<encoded-URL>`.
- **URL is URL-encoded in the query string** — a URL containing reserved characters (spaces, `?`, `&`) is percent-encoded before being sent.
- **Ledger returns bytes on 200** — a successful `/v1/download` response with body bytes and `Content-Type` yields those bytes to `%fetch` with the artifact's Content-Type.
- **`Endorsement:` response header is captured** — the endorsement JSON is available for local verification without a second call.
- **`Vibecode:` response header is captured** — the vibecode pointer is preserved for downstream cold-agent onboarding.
- **404 causes Ledger to pass** — a `no endorsement exists` response causes Ledger to pass and the walk continues.
- **409 causes Ledger to pass** — an `origin bytes don't match` response causes Ledger to pass.
- **502 causes Ledger to pass** — an `origin unreachable` response causes Ledger to pass.
- **501 causes Ledger to pass** — an `unknown hash algorithm` response causes Ledger to pass.
- **`semver` query parameter narrows lookup** — a fetch with a `semver` constraint sends `?semver=X.Y.Z` in the query and receives the exact-match endorsement or a 404.
- **`at` query parameter narrows lookup** — a fetch with an `at=YYYY-MM-DD` constraint receives the latest endorsement effective on or before that date.
- **`GET /v1/endorsement` returns endorsement JSON on 200** — the response body has `{"success": true, "endorsement": {...}}`.
- **`GET /v1/endorsement` returns failure JSON on 4xx** — the body has `{"success": false, "status": ..., "resource": ..., "message": ...}`.
- **Signature verifies against baked-in Puck key** — a returned endorsement's Ed25519 signature verifies against the engine's built-in public key.
- **Signature mismatch raises** — a tampered endorsement (any byte changed after signing) fails verification and raises.
- **Locally-verified endorsement matches server-verified bytes** — the SHA-256 the client computes over the response body matches the `artifact_hash` in the endorsement.
- **Content-Type in `Endorsement` header does not override response Content-Type** — the response's own `Content-Type` is what `%fetch` returns.
- **All-blocks-by-URL query returns entries newest-first** — for a URL with multiple endorsements over time, the returned array has the newest block at index 0.
- **All-blocks-by-signer query returns everything the signer posted** — for a given signer, the query returns their authority block plus every endorse/delegate/deprecate/revoke they signed.
- **Intersection query returns blocks-by-signer-about-URL** — the intersection endpoint is equivalent to filtering all-blocks-by-URL to a specific signer.
- **`%fetch.blockchain = true` verifies against Puck's chain** — bytes returned by any fetcher are verified against Puck's default chain.
- **`%fetch.blockchain = null` disables verification** — bytes returned by any fetcher are not verified; the caller accepts them as-is.
- **`%fetch.blockchain = 'https://...'` verifies against a private chain** — signatures are checked against the chain at the given URL, not Puck's default.
- **Ledger fetch verified against a different trust anchor works** — Ledger returns the bytes, but `%fetch.blockchain` determines which chain's signature is treated as authoritative.
- **Ledger position is after caches and before Wire** — the default fetcher array places Ledger after cache entries and before Wire.
- **Non-`user` role reading `%fetch.blockchain` — spec-driven test placeholder** — behavior TBD as the trust-anchor surface is spec'd.

## Related

- [fetch-discovery](./) — the parent page describing the `%fetch.fetchers` array and the fetcher classes Ledger is one of.
- [cache-dir](https://puck.uno/requirements/cache-dir) — Cache-format directories, another fetcher class in the array. `meta.json`'s stored endorsement (when present) is what lets a Cache-served version be verified against the trust anchor.
- [content-types](https://puck.uno/requirements/content-types) — Content-Type strings the blockchain service uses in responses.
- [`%fetch`](https://puck.uno/requirements/fetch) — the gateway that walks `%fetch.fetchers`.
