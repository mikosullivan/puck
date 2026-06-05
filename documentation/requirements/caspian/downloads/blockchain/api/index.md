# Blockchain API

*The HTTPS API for blockchain.puck.uno. Two endpoints today: look up an endorsement (returns the signed block as JSON), or fetch an artifact (returns the actual bytes after hash verification).*

~~~json
{"vibecode": {
	"doc": "blockchain_api_index",
	"role": "hub doc for the blockchain.puck.uno HTTPS API — links to per-endpoint specs and declares contract guarantees for JSON-returning endpoints (the byte-oriented fetch endpoint follows standard HTTP conventions instead)",
	"endpoints": ["endorsement_lookup", "artifact_fetch"],
	"host": "blockchain.puck.uno",
	"contract_for_json_endpoints": ["respects_accept_header", "json_body_on_every_response_including_errors", "top_level_success_boolean"],
	"fetch_endpoint_is_byte_oriented": "success_returns_artifact_bytes_errors_return_empty_body_with_status_code"
}}
~~~

## Endpoints

- **[Look up an endorsement](endorsement.md)** — `GET /v1/endorsement?url=<url-encoded-url>`. Returns the signed block for a given artifact URL as JSON.
- **[Fetch an artifact](fetch.md)** — `GET /v1/download?url=<url-encoded-url>`. Returns the actual artifact bytes after server-side hash verification against the signed block.

<a id="contract-guarantees"></a>
## Contract guarantees

The contract below applies to **JSON-returning endpoints** (today: [Look up an endorsement](endorsement.md)). The byte-oriented [Fetch an artifact](fetch.md) endpoint is the exception — it follows standard HTTP conventions, returning artifact bytes on success and an empty body with a status code on failure (no JSON envelope, no `success` boolean).

### For JSON endpoints

The endpoint **respects the `Accept` header** and **always returns a JSON body** — including on error responses. There is no scenario where a client gets a bare HTTP status with no body, no HTML error page, no plaintext message. A 404 carries a structured JSON object explaining what wasn't found, the same way a 200 carries a structured JSON object for what was found.

Every response carries a top-level **`success` boolean** — `true` when the lookup or operation completed normally, `false` for any error condition. Clients can branch on that without parsing the HTTP status code. Error responses additionally carry `status` (a short error code), `message` (a human-readable description), and `resource` (the URL the request was about, when applicable).

Clients can rely on parsing the body unconditionally; the `success` boolean is the canonical signal of whether the operation worked.

---

## Historical

*Earlier sketch of the API. Preserved for reference while the fresh design above is being settled. Not authoritative.*

All blockchain services are hosted at `blockchain.puck.uno`.

The Puck Lua library does not include routines for querying the blockchain directly.
By default it operates through the API at `blockchain.puck.uno`. The endpoints below
describe the intended shape; the final API spec will be a separate document.

<a id="submit-domain-owner-puck"></a>
### Submit (domain owner → Puck)

`POST https://blockchain.puck.uno/v1/submit`

Domain owner submits a URL. Puck fetches the artifact from that URL, signs it, and
posts a provenance endorsement block.

This endpoint is idempotent. If Puck fetches the artifact and finds it byte-identical
to the most recently posted version under the same URL, it returns the existing block
rather than posting a new one.

When the fetched artifact carries a `semver` field, the [semver duplicate-check rule](../blockchain-implementation/#semver-duplicate-check)
applies: a different artifact under an already-posted `url` + `semver` is rejected
(distinct from the content-identity coalescing above).

Request:
```json
{"url": "https://borg.com/foo"}
```

Response:
```json
{"status": "posted", "url": "https://borg.com/foo", "record_hash": "..."}
```

<a id="fetch-engine-puck"></a>
### Fetch (engine → Puck)

`GET https://blockchain.puck.uno/v1/object?url=<url-encoded-url>`

Returns the latest provenance endorsement block for the given URL. The engine verifies
the signature client-side using the baked-in public key.

`GET https://blockchain.puck.uno/v1/object?url=...&semver=2.1.0` — exact semver match.

`GET https://blockchain.puck.uno/v1/object?url=...&at=2026-01-01` — latest version whose
`effective_date` is on or before the given date.

<a id="root-block"></a>
### Root block

`GET https://blockchain.puck.uno/v1/authority`

Returns Puck's authority block. Used during engine setup to verify the baked-in public
key matches the chain.
