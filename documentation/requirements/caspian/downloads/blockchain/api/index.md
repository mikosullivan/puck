# Blockchain API

All blockchain services are hosted at `blockchain.puck.uno`.

The Puck Lua library does not include routines for querying the blockchain directly.
By default it operates through the API at `blockchain.puck.uno`. The endpoints below
describe the intended shape; the final API spec will be a separate document.

<a id="submit-domain-owner-puck"></a>
## Submit (domain owner → Puck)

`POST https://blockchain.puck.uno/v1/submit`

Domain owner submits a URL. Puck fetches the artifact from that URL, signs it, and
posts a provenance endorsement block.

This endpoint is idempotent. If Puck fetches the artifact and finds it byte-identical
to the most recently posted version under the same URL, it returns the existing block
rather than posting a new one.

When the fetched artifact carries a `semver` field, the [semver duplicate-check rule](../blockchain/#semver-duplicate-check)
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
## Fetch (engine → Puck)

`GET https://blockchain.puck.uno/v1/object?url=<url-encoded-url>`

Returns the latest provenance endorsement block for the given URL. The engine verifies
the signature client-side using the baked-in public key.

`GET https://blockchain.puck.uno/v1/object?url=...&semver=2.1.0` — exact semver match.

`GET https://blockchain.puck.uno/v1/object?url=...&at=2026-01-01` — latest version whose
`effective_date` is on or before the given date.

<a id="root-block"></a>
## Root block

`GET https://blockchain.puck.uno/v1/authority`

Returns Puck's authority block. Used during engine setup to verify the baked-in public
key matches the chain.
