# Fetch an artifact

*The download endpoint on blockchain.puck.uno. Returns the actual bytes of a published artifact, after verifying them against the signed block.*

~~~vibecode
{"vibecode": {
	"doc": "blockchain_api_fetch",
	"role": "spec for the GET download endpoint on blockchain.puck.uno that returns artifact bytes (the actual file content) after server-side hash verification against the signed block",
	"endpoint": "GET /v1/download?url=<url-encoded-url>",
	"returns_on_success": "raw_artifact_bytes_with_artifacts_own_content_type",
	"returns_on_error": "empty_body_with_http_status_code_byte_oriented_endpoint_not_json",
	"verification": "server_fetches_artifact_hashes_bytes_compares_to_signed_artifact_hash"
}}
~~~

## A simple GET request

Suppose someone wants to download the Caspian class at:

```
https://raw.githubusercontent.com/borg/classes/main/borg.casp
```

The client sends a GET to:

```
https://blockchain.puck.uno/v1/download?url=https%3A%2F%2Fraw.githubusercontent.com%2Fborg%2Fclasses%2Fmain%2Fborg.casp
```

If blockchain.puck.uno has a signed block for that URL AND the bytes still match the signed `artifact_hash`, the response (HTTP 200) returns the raw artifact bytes in the body, with the endorsement metadata and a cold-agent onboarding pointer in headers:

```http
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8
Content-Length: 105
UNS: {"download.puck.uno": {"endorsement": { ...chain block, see endorsement.md... }}}
VIBECODE: {"spec": "https://puck.uno/", "skills": ["https://puck.uno/ai/skills/puck-basics"]}

class
	field 'designation', class: :string, required: true

	method &greet()
		'We are Borg.'
	end
end
```

(Standard noise like `Date`, `Server`, `Connection`, etc. omitted for clarity. On the wire, the `UNS:` and `VIBECODE:` JSON values are minified to a single line each; the example above is conceptually formatted for readability.)

The two custom headers:

- **`UNS:`** carries structured metadata namespaced by service. Here it's under `download.puck.uno`, with an `endorsement` field holding the chain block for this artifact — the same shape the [endorsement endpoint](endorsement.md) returns, minus the `success` wrapper (since the HTTP 200 already conveys success). A client that wants to verify the bytes hashes them and compares to `endorsement.payload.endorsements[0].artifact_hash`; no second round-trip needed.
- **`VIBECODE:`** is a small, stable pointer carrying enough for a cold agent (one with no prior context) to figure out what Puck is and where to learn more. The value is essentially the same on every Puck response — small enough to inline, stable enough for intermediaries to cache.

A client that doesn't care about verification or onboarding can simply ignore both headers. The body is the file; everything else is metadata.

The content-type matches whatever the artifact actually is — `.casp` files are plain text, but binary artifacts (a font, an image, a compiled library) would carry their own content-type.

## What the service does on a download

When the request comes in, blockchain.puck.uno:

1. Looks up the signed block for the given URL.
2. Fetches the artifact bytes from the artifact's URL (or a cached mirror).
3. Hashes the bytes using the algorithm declared in the signed block (e.g., SHA-256).
4. Compares the computed hash against the signed `artifact_hash`.
5. If they match: returns the bytes to the client.
6. If they don't match: refuses to serve (returns an error response — see below).

The hash check is what makes going through blockchain.puck.uno different from a direct fetch. A direct fetch from the artifact's URL gets the bytes whether they've been modified or not. This endpoint gets the bytes **only if they still match what was signed**.

### Version selection

By default the endpoint returns the bytes signed under the most recent block for that URL. To pin a specific version:

```
GET /v1/download?url=<url>&semver=2.1.0
```
Returns the bytes signed under that exact semver.

```
GET /v1/download?url=<url>&at=2026-01-01
```
Returns the latest version signed on or before the given date.

These mirror the equivalent parameters on the [endorsement endpoint](endorsement.md). The UNS header on the response carries the endorsement metadata for whichever version was served.

## Error responses

Unlike the [endorsement endpoint](endorsement.md) and other JSON-returning endpoints, fetch is **byte-oriented** — success returns raw artifact bytes, errors return an **empty body** and rely on the HTTP status code to convey what went wrong. There's no JSON envelope here, no `success` boolean — the status code is the entire error signal.

Expected error cases:

- **404 Not Found** — no signed block on file for that URL.
- **409 Conflict** — the artifact bytes have drifted from the signed `artifact_hash`. Refused to serve.
- **502 Bad Gateway** — the artifact's URL is unreachable and no mirror is available.
- **501 Not Implemented** — the signed block names a hash algorithm the service doesn't support.

The exact status code for some cases (e.g., is hash-mismatch a 409, a 410, or something else?) is TBD.

## Open questions

- **Version selection.** ~~Resolved~~: the fetch endpoint supports the same `?semver=` and `?at=` query params as the [endorsement endpoint](endorsement.md). `GET /v1/download?url=...&semver=2.1.0` returns the bytes signed under that exact semver; `GET /v1/download?url=...&at=2026-01-01` returns the latest version signed on or before that date. Symmetric with endorsement's surface.
- **Streaming.** ~~Resolved~~: the server can stream freely. Verification is **client-side** — the client gets the signed `artifact_hash` from the `UNS:` response header (which arrives before the body), buffers the bytes (to disk or in-memory; see the [caching spec](https://puck.uno/documentation/requirements/caspian/downloads/caching/#signature-verification)), then verifies before committing to use. The signature is portable, so the same verification works regardless of byte source.
- **Caching.** Should responses carry Cache-Control headers keyed to the `artifact_hash`? Hash-based content addressing makes immutable caching trivial.
- **Direct-fetch fallback.** ~~Resolved~~: the server doesn't need to mirror. The client's [`%puck.sources`](https://puck.uno/documentation/requirements/caspian/downloads/) fetcher chain provides resilience — if blockchain.puck.uno can't serve, the engine moves to the next fetcher (direct origin, private mirror, local cache). The signature is portable; whichever fetcher eventually returns bytes, the client verifies them against the same signature.

## See also

- [Look up an endorsement](endorsement.md) — the sibling endpoint that returns the signed block as JSON without fetching the bytes.
- [Blockchain API (index)](index.md) — API hub with contract guarantees and the endpoint list.
- [Blockchain implementation](../blockchain-implementation/) — chain design, signing scheme, authority blocks.
