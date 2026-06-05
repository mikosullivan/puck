# Look up an endorsement

*The block-info endpoint on blockchain.puck.uno. Returns the signed block for a given artifact URL as JSON.*

~~~json
{"vibecode": {
	"doc": "blockchain_api_endorsement",
	"role": "spec for the GET endorsement-lookup endpoint on blockchain.puck.uno — returns the signed block as JSON for a given artifact URL; sibling of the fetch endpoint which returns the actual bytes",
	"endpoint": "GET /v1/endorsement?url=<url-encoded-url>",
	"returns_on_success": "json_signed_block_with_seal_and_payload",
	"returns_on_error": "json_body_with_success_false_per_api_wide_contract"
}}
~~~

## A simple GET request

Suppose someone published a Caspian class on GitHub at:

```
https://raw.githubusercontent.com/borg/classes/main/borg.casp
```

To look up what blockchain.puck.uno has on file for that URL, the engine sends a GET to:

```
https://blockchain.puck.uno/v1/endorsement?url=https%3A%2F%2Fraw.githubusercontent.com%2Fborg%2Fclasses%2Fmain%2Fborg.casp
```

The `url` query parameter carries the URL-encoded artifact address (the same encoding rules as any HTTP query string — `:` becomes `%3A`, `/` becomes `%2F`, etc.).

If blockchain.puck.uno has a signed block for that URL, the response (HTTP 200) returns the chain block, wrapped in the API's `success` flag:

```json
{
    "comment": "Puck.uno posts provenance for borg.casp at github.com/borg/classes.",
    "success": true,
    "index": 8,
    "prev_hash": "3ebe6d218b9992839a726fe1d900a8ba2ae1a6ab336bfc06431edda7d6cdeadf",
    "posted": "2026-05-08T20:54:44Z",
    "signer": "puck.uno",
    "payload": {
        "effective_date": "2026-05-08",
        "endorsements": [
            {
                "comment": "Borg collective class definitions for Caspian.",
                "endorsement": "provenance",
                "artifact_hash": "sha256:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b",
                "artifact_url": "https://raw.githubusercontent.com/borg/classes/main/borg.casp",
                "signature_algorithm": "ed25519",
                "license": "Apache-2.0",
                "name": "borg/classes",
                "semver": "2.3.12"
            }
        ],
        "grammar": {
            "hash": "c32d8aaab9a50388cadd7e5d92357da2bd360f11f58ac7384b34c5e6dba1ced5",
            "version": "1.0"
        },
        "intent": "endorse",
        "tags": {
            "puck.uno/tag/caspian-library": true
        },
        "target_hash": "self",
        "uns": "borg/classes",
        "semver": "2.3.12",
        "vibecode": {
            "endorsement": "provenance",
            "intent": "endorse",
            "license": "Apache-2.0",
            "signer": "puck.uno",
            "uns": "borg/classes",
            "semver": "2.3.12"
        }
    },
    "signature": "pVNzTw9nwl3kyC6diCbvrT5c+hXJTqujkqrziyrmrBj5DA+3SuRitBXsq1CXWh69Dwa2+T4JoXoQbc2yV4o+CA==",
    "record_hash": "f723c3bb6cf762d7f33a25b0e72ffa941dcfab929db12cdc539c82a8ccb7ef88"
}
```

The response **is** the chain block, with `success: true` added at the top per the [API-wide contract](index.md#contract-guarantees). The `payload` is what was actually signed; `signer` and `signature` together let the client verify it against the corresponding authority's public key. `prev_hash` and `record_hash` support chain-integrity walking. Each entry in `payload.endorsements` carries a `signature_algorithm` field that the API copies in from the relevant authority block as a convenience — clients don't need to fetch the authority block just to learn which algorithm to verify with.

## A 404 response

When no signed block exists for a given URL, the endpoint returns the API-wide error shape (`success: false` plus details — see the [contract guarantees in the API index](index.md#contract-guarantees)):

```json
{
    "success": false,
    "status": "not_found",
    "resource": "https://raw.githubusercontent.com/borg/classes/main/borg.casp",
    "message": "No provenance block on file for this URL."
}
```

## Future endorsement types

- **`tested`** — would indicate that an artifact passed all of its own tests. Mechanism TBD (who runs the tests, what counts as "all," how results are recorded on-chain).
- **Third-party test endorsements** — anyone (not just the original publisher) could publish their own test suite against an existing class and post an endorsement saying "this artifact passed my tests." Same class could accumulate test endorsements from many independent parties. Mechanism TBD; the endorsement would presumably reference both the artifact URL and the test-suite URL.

**Neither is locked in for V1.0** — captured here so the ideas aren't lost.

## See also

- [Blockchain API (index)](index.md) — API-wide contract guarantees and endpoint list.
- [Fetch an artifact](fetch.md) — the sibling endpoint that returns the actual bytes after hash verification.
- [Blockchain implementation](../blockchain-implementation/) — chain design, signing scheme, authority blocks.
