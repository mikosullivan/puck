# The Puck ledger
<!--index: 3-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_puck_discovery_blockchain_ledger",
	"role": "spec for the on-chain format of the Puck blockchain — the linear append-only ledger of signed records that backs the Ledger fetcher (see fetch-discovery/blockchain/index.md) and the publishing flow (see fetch-discovery/blockchain/publishing.md). Covers the record envelope, the signing scheme (Ed25519 over RFC-8785-canonicalized JSON, SHA-256 hashes), the bootstrap sequence (Puck.uno authority block first, first grammar block second), the six block intents (authority, grammar, endorse, delegate, deprecate, revoke) with their payloads, the grammar system that lets block-format rules evolve, the endorsement structure and its latest-wins resolution rule, delegation semantics, and revocation with recommended engine caching behavior.",
	"status": "draft — brought over from the requirements-old blockchain-implementation spec. Envelope, signing, bootstrap, and the six block intents are settled at the sketch level; several details (key rotation, delegation-by-intent shape, `audit` endorsement payload, whether every software identifier belongs on-chain) are still open.",
	"audience": "implementers of blockchain.puck.uno; anyone verifying Ledger responses locally; class authors reading Ledger-returned data; anyone reasoning about the trust model that Ledger and %fetch.blockchain sit on top of"
}}
~~~

The Puck ledger is a **linear, append-only chain of signed JSON records**. Each record links to the previous one via a hash, records are never modified or deleted, and anyone can post a record. Trust is layered on top of the raw ledger through **authority blocks** (which anchor a signer's identity) and **delegation blocks** (which grant a signer's endorsement authority to others). There is no mining, no proof-of-work, no gas.

## Model

- **Linear**: records are ordered; each one references the previous by `prev_hash`.
- **Append-only**: never modified or deleted. A mistake, a compromised key, or an intent to withdraw a claim is expressed by posting a **revoke** or **deprecate** record — not by editing the ledger.
- **Open**: anyone can post any record type. The chain does not gate submissions.
- **Trust-layered**: engines ship with Puck.uno's public key baked in and trust records signed by that key at the root. Every other trusted signer traces back to a signer the caller has chosen to trust — either through direct configuration or through a delegation from a signer they already trust.

## Record envelope

Every record on the chain carries the same envelope fields, regardless of intent. Field names and their meanings:

| Field | Description |
|---|---|
| `intent` | The record's category. One of `authority`, `grammar`, `endorse`, `delegate`, `deprecate`, `revoke`. |
| `grammar` | `{"hash": "...", "version": "..."}` — points at the grammar block that defines the format this record conforms to. **Omitted on the two bootstrap records only** (see [Bootstrap](#bootstrap)). |
| `prev_hash` | SHA-256 hex of the previous record's fully-serialized form (including its `signature`). `null` on the very first record. |
| `posted` | ISO 8601 UTC timestamp, assigned canonically at insertion time (not chosen by the submitter). |
| `signer` | URL of the signing entity. The signer's authority block (elsewhere on the chain) carries the public key used to verify this record's `signature`. |
| `payload` | Record-specific data. Shape depends on `intent`; see [Block intents](#block-intents). |
| `signature` | Ed25519 signature over the record with `signature` removed and the remaining JSON canonicalized (see [Signing and hashing](#signing-and-hashing)). Base64-encoded. |
| `record_hash` | SHA-256 hex of the record's fully-serialized form **including** `signature`. Used as the target of any later block that references this one. |

## Signing and hashing

Both signing and hashing operate on the same **canonical JSON form** of a record:

- Minified (no whitespace).
- Keys sorted alphabetically **recursively** at every nesting level.
- Serialized as UTF-8 bytes.

This is compatible with RFC 8785 (JSON Canonicalization Scheme). Any implementation that produces the same canonical bytes will produce the same hash and verify the same signature.

**Hash algorithm.** SHA-256 for everything — `prev_hash`, `record_hash`, and any content hashes referenced in payloads. Hex-encoded (lowercase).

**Signature algorithm.** Ed25519. To sign a record: remove the `signature` field, canonicalize the remaining JSON, sign the UTF-8 bytes with the signer's Ed25519 private key. To verify: retrieve the signer's public key from their `authority` block (elsewhere on the chain), strip `signature` from the record being verified, re-canonicalize, verify the signature against the bytes.

**Public keys.** Stored on-chain inside authority blocks as PEM (`-----BEGIN PUBLIC KEY-----\n...`).

**`record_hash`.** SHA-256 of the full canonicalized record **including** `signature`. This distinguishes it from the signature input (which excludes `signature`) and is the hash any downstream record uses to reference this one.

## Bootstrap

The first two records on the chain are fixed by convention and are the only records that omit the `grammar` field:

1. **Position 1 — Puck.uno authority block.** Carries Puck.uno's public key (in PEM), a self-contained `puck_primer` string that introduces the whole system for a cold reader, and a `vibecode` string with a compact machine-readable summary. The public key from this block is **baked into every engine that ships with Caspian** — it's how consumers begin trusting anything on the chain without prior configuration.
2. **Position 2 — first grammar block.** Defines the block-format rules that every subsequent record refers to via its `grammar` field. It can self-reference (its own `grammar.hash` = `"self"`, or its own `record_hash`).

From position 3 onward, every record **must** carry a `grammar` field pointing at a grammar block. Multiple grammar blocks can coexist on the chain — they don't replace each other. Each record names the grammar it conforms to, and parsers apply that specific grammar's rules to that specific record.

Only Puck's public key is baked into engines. Every other trusted identity, every endorsement vocabulary, every future block-type definition is derivable from the chain itself, starting from position 1.

## Grammar

A `grammar` block defines the shape and validation rules for records that reference it. Referenced by `{"hash", "version"}` pairs, so:

- **Old grammars stay valid indefinitely.** A record from 2019 that references grammar A stays parseable and verifiable forever; parsers walk to that grammar block and apply its rules.
- **New grammars can appear at any time.** Anyone can post a new grammar block; new records referencing it become valid immediately. No cutoff, no chain-wide migration.
- **Unknown grammar hash is not automatic reject.** A consumer that encounters a grammar it doesn't recognize decides for itself whether to trust the record. Engines can be conservative or permissive.

Payload fields on a grammar block include `description`, `version`, `envelope` (envelope-field descriptor including required/optional per field), `payload_common` (fields all record types share), `intent_values` (the closed enum of legal `intent` values under this grammar), `endorsement_values` (the **list of well-known endorsement types**, not a closed enum — see below), and a `vibecode` string.

**`endorsement_values` is a known-good list, not a closed enum.** The `endorsement` string in an endorse claim is open-ended — anyone can post an endorsement carrying a new type name (`my-org/reproducible-build`, `example.com/carbon-audit`) without any grammar change. The grammar's `endorsement_values` records the types that are widely understood at the time the grammar is posted; consumers treat unknown values however they choose. Contrast with `intent_values`, which IS a closed enum — an unknown `intent` on a record is a signal the record doesn't fit under this grammar at all.

**Keep the grammar count small.** Even though the chain can carry any number of grammar blocks, a large proliferation is a design smell — every additional grammar is another shape parsers and verifiers must understand, another surface for interoperability bugs, and another decision-point for consumers on what to trust. The design target is **three or four grammar blocks total for the life of the chain**: one to bootstrap, one or two to accommodate structural changes the initial grammar could not have anticipated, and nothing else. Grammar additions are for structural evolution the format genuinely needs — not for adding well-known endorsement types (which can appear without a new grammar per the previous paragraph) and not for cosmetic changes.

## Block intents

Six intents. Each has a distinct payload shape.

### `authority`

Anchors trust for a signer. Every entity that wants to post other record types starts by posting an authority block that carries their public key.

Payload:

- `public_key` — Ed25519 public key in PEM form.
- `puck_primer` — self-contained string introducing the Puck system, suitable for a cold reader who has this block but nothing else.
- `vibecode` — compact machine-readable summary.
- `note` — free-form context.

No coordination with Puck is required to post an authority block — anyone can. Whether other parties trust that authority is a separate decision made by consumers.

### `grammar`

Defines the format and validation rules for records. See [Grammar](#grammar) above.

### `endorse`

The load-bearing block type — makes a signed claim about a URL. See [Endorsement structure](#endorsement-structure) below for the full payload shape and the latest-wins resolution rule.

### `delegate`

Grants an entity trusted-endorser status for a scoped set of endorsement types. Once a delegation is on the chain, the delegated entity's endorsements — of the covered types — are treated by consumers as if they came from the delegating signer.

Payload:

- `entity` — URL of the entity being granted the delegation.
- `target_hash` — the entity's authority block's `record_hash` — pins the delegation to a specific key.
- `endorsements` — array of endorsement types the delegation covers (e.g. `["security", "audit"]`).
- `note` — free-form context.

Delegations apply retroactively to every record the delegate has signed under the referenced authority block — chain order does not matter. Delegations are transitively chainable: A delegates to B; B delegates to C; C's endorsements are trusted by anyone who trusts A.

### `deprecate`

Marks a target as deprecated. **Soft** — the chain does not invalidate anything; deprecation is a signal for consumers to act on.

Payload:

- `url` — the URL being deprecated.
- `semver` — the version being deprecated (optional; when omitted, all versions).
- `reason` — free-form.

A deprecate block can also target an entire authority (by setting `entity` and using `target_hash` to name the authority block), signaling that the whole signer should no longer be trusted for new claims.

### `revoke`

Invalidates a specific prior record. **Hard** — this is the tool for handling a compromised key or a claim the signer needs to withdraw.

Payload:

- `target_hash` — the `record_hash` of the record being revoked.
- `reason` — free-form.

Recommended engine behavior: on any use of an object whose endorsement came from a chain record, check for a revoke of that record with a short local TTL (roughly 5 minutes). If revoked, discard cached content and re-fetch.

## Endorsement structure

Every `endorse` block's payload carries:

- `target_hash` — `record_hash` of the record being endorsed, or the literal string `"self"` for endorsements that are self-contained (the endorse block itself declares what it's endorsing).
- `url` — URL of the artifact being endorsed.
- `semver` — optional. SemVer 2.0 (`X.Y.Z`).
- `effective_date` — the date the endorsement applies to (may differ from the record's `posted` — allows endorsing historical artifacts).
- `endorsements` — array of one or more **claim objects**, each carrying a specific assertion.

Each claim object has:

- `endorsement` — a string naming what the claim asserts. Well-known values:
	- `provenance` — the artifact is authentically from the claimed publisher.
	- `license-verified` — the license claim has been checked.
	- `security` — a security audit was performed. Additional fields (see below).
	- `audit` — a broader audit was performed.
- **Artifact fields** (present alongside `provenance` claims and any other type that needs them): `name`, `description`, `language`, `license` (required — SPDX identifier), `semver`, **`artifact_hash`** (required — the cryptographic anchor tying this endorsement to specific bytes), `artifact_url` (off-chain location of the actual artifact bytes).
- **`security` field** (present on `security` claims): a hash mapping standard IDs (`fedramp-moderate`, `fedramp-high`, `fips-140-2`, ...) to booleans (or `null`). Three states are meaningful:
	- **`true`** — the endorser certifies the artifact **meets** this standard.
	- **`false`** — the endorser has verified the artifact **does not** meet this standard. This is a positive assertion of non-compliance, not the absence of information.
	- **`null`, or the standard omitted from the hash entirely** — the endorser makes no ruling about this standard. `null` and absent are equivalent — either way, the artifact may or may not comply and no checking has been asserted.

	The `true`/`false`/no-ruling split is what makes the hash form worth the extra shape over a simpler array: an audit that finds a file passes moderate but fails high is a real, distinct result from an audit that only checked moderate — and consumers verifying against compliance policies need to tell those two situations apart.
- `notes` — free-form.

**No uniqueness rule; latest wins.** The chain accepts any number of endorse blocks from the same signer for the same URL. There is no rejection at post time based on prior endorsements. Resolution is a **consumer-side concern**: when a consumer is looking for a specific endorsement type from a specific signer for a specific URL, they walk the chain newest-first and take the first matching claim. Older endorsements are still present on the chain (nothing is removed) but are superseded by newer ones for that specific claim.

This model has three practical consequences worth naming:

- **Overrides are free.** A signer who discovers a typo, a wrong hash, or a stale claim just posts a new endorsement. Consumers see the corrected value on their next lookup. No `revoke` ceremony is required for benign corrections.
- **Additive updates are also free.** A signer who wants to add a new certification (say, a fresh `security` claim) without touching prior claims just posts a new endorsement carrying only the new claim. Consumers walk back until they find each claim type they're looking for; older endorsements provide the older claim types, the new endorsement provides the new one.
- **Malicious overrides fall under key compromise.** A malicious override requires the signer's private key. That's a key-compromise problem, handled at the authority level with `revoke` (see [`revoke`](#revoke)) — not by uniqueness checks on individual endorse records.

**Third-party endorsements.** Anyone with an authority block can post an endorse block against another party's artifact by naming that party's endorsement in `target_hash`. Whether the third party's endorsement is trusted depends on the consumer's chain of trust — which may include a delegation.

## Open questions

- **Key rotation.** Not spec'd. The implicit path is: post a new authority block with the new key, then post a `revoke` against the old authority block. Whether that's the sanctioned mechanism or whether a dedicated rotation intent should exist is not yet settled.
- **Delegation by intent.** Delegation as spec'd above covers endorsement types. Whether a delegation should also be able to cover other intents (e.g. delegating the right to post `deprecate` records) is not yet settled.
- **`audit` payload.** `audit` appears as a well-known endorsement type, but the specific payload shape for an audit claim (findings, scope, standards referenced) is not yet spec'd.
- **Software-identifier bloat.** As `puck.uno/software/...` identifiers grow (languages, DBMSs, frameworks), whether every identifier belongs on the chain — or whether the chain should carry only records that reference identifiers — is a design decision affecting long-term chain size.
- **`mirror` intent.** A `mirror` value appears in grammar block enumerations without an accompanying section defining what it does. Either the enumeration is aspirational, or the intent needs its own spec.

## Testing

- **Every record carries the envelope fields** — `intent`, `grammar`, `prev_hash`, `posted`, `signer`, `payload`, `signature`, `record_hash` are present on every non-bootstrap record.
- **Bootstrap records omit `grammar`** — records at positions 1 and 2 have no `grammar` field; every subsequent record has one.
- **`grammar` present from position 3 onward** — a record at position 3+ without a `grammar` field is rejected during validation.
- **`prev_hash` chains records** — a record's `prev_hash` matches the previous record's `record_hash`.
- **`prev_hash` is null on record 1** — the first record's `prev_hash` is JSON `null`, not a string.
- **Broken chain link is detectable** — a record whose `prev_hash` doesn't match the predecessor's `record_hash` fails chain-integrity check.
- **`posted` is server-assigned, not signer-controlled** — a record accepted onto the chain has a `posted` value the service assigned; a submitter's proposed value is ignored.
- **Canonical JSON form is minified** — the canonicalized bytes contain no whitespace.
- **Canonical JSON sorts keys alphabetically at every level** — nested hashes have their keys sorted recursively.
- **RFC 8785 canonicalization is round-trip stable** — two implementations produce byte-identical canonical bytes for the same record.
- **Signature verifies against canonical bytes** — after stripping `signature`, canonicalizing, and verifying with the signer's public key, verification succeeds for a genuine record.
- **Tampered payload fails verification** — flipping any byte in `payload` after signing causes the Ed25519 verification to fail.
- **`record_hash` is SHA-256 of the full canonical form including `signature`** — recomputing SHA-256 over the full canonical bytes matches `record_hash`.
- **Public keys stored as PEM** — an authority block's `public_key` field is a PEM-formatted string starting with `-----BEGIN PUBLIC KEY-----`.
- **Position-1 authority block carries Puck.uno's key** — the baked-in engine key matches the `public_key` in the record at position 1.
- **Position-1 authority block carries `puck_primer` and `vibecode`** — both fields are present and non-empty.
- **Position-2 grammar block self-references** — its `grammar.hash` is `"self"` or its own `record_hash`.
- **Multiple grammar blocks coexist** — a chain that contains grammar records at positions 2, 500, and 900 permits records referencing any of the three grammars.
- **Old grammar references stay valid indefinitely** — a record referencing a grammar block posted long ago verifies against the same grammar block today.
- **Unknown grammar hash is consumer-decides** — encountering a grammar hash the engine doesn't recognize does not automatically reject; the consumer chooses posture.
- **`intent_values` is closed under a grammar** — a record with an `intent` not listed in the referenced grammar's `intent_values` is rejected as ill-formed for that grammar.
- **`endorsement_values` is open** — an endorse block claiming an endorsement type not in the referenced grammar's `endorsement_values` is still valid; consumers decide how to handle unknown types.
- **`authority` block requires `public_key`, `puck_primer`, `vibecode`, `note`** — a missing required field is rejected.
- **`grammar` block payload includes `description`, `version`, `envelope`, `payload_common`, `intent_values`, `endorsement_values`, `vibecode`** — missing required fields are rejected.
- **`endorse` block payload includes `target_hash`, `url`, `endorsements`** — missing required fields are rejected.
- **`endorse` with `target_hash: "self"` is valid** — a self-endorsement resolves without an external reference.
- **Endorsement claim carries `endorsement`, artifact fields, notes** — the well-known claim types each include the fields spec'd above.
- **Endorsement requires `license` (SPDX identifier)** — an endorse block missing a valid SPDX license is rejected.
- **Endorsement requires `artifact_hash`** — an endorse block missing `artifact_hash` is rejected.
- **`security` claim distinguishes `true`, `false`, and no-ruling** — a hash entry `{"fedramp-moderate": true}` differs from `{"fedramp-moderate": false}` differs from omission or `null`.
- **`security` claim `null` and omission are equivalent** — consumers can treat either as no-ruling with no observable difference.
- **Latest-wins per claim type** — for a signer/URL/claim-type triple, the newest matching endorse block is the resolved value.
- **Newer endorsement overrides older claim type** — a subsequent endorse block from the same signer for the same URL replaces the earlier value for the claim types it carries.
- **Additive endorsement leaves untouched claim types resolvable** — a new endorse block adding a `security` claim leaves an earlier `provenance` claim reachable via walk-back.
- **Older endorsements remain on the chain** — nothing is removed when superseded; the older records are still queryable.
- **Third-party endorsement is valid** — an endorse block whose `signer` differs from the URL's publisher is accepted; whether it's trusted is a consumer decision.
- **`delegate` block requires `entity`, `target_hash`, `endorsements`, `note`** — missing required fields are rejected.
- **Delegation is retroactive** — endorsements signed before the delegation block by the delegate under the same authority are trusted after the delegation is on chain.
- **Delegation is transitive** — A delegates to B; B delegates to C; C's endorsements of the covered types are trusted by anyone who trusts A.
- **Delegation is scoped by endorsement type** — C's endorsement of a type not in the delegation array is not trusted through A.
- **`deprecate` block is soft** — content is still resolvable after a deprecate; the block is a consumer-visible signal only.
- **`deprecate` without `semver` deprecates all versions** — omitting the `semver` field means the deprecation covers every version.
- **`deprecate` with `semver` deprecates that version only** — including `semver` narrows the deprecation to that specific version.
- **Authority deprecate targets the whole signer** — an authority-level deprecate signals that new claims from the signer should not be trusted.
- **`revoke` block hard-invalidates the target record** — after a revoke referencing a target `record_hash`, consumers treat that record as invalidated.
- **Recommended engine revoke-check TTL is ~5 minutes** — a fresh use of an object triggers a revoke check when the last check was more than about 5 minutes ago.
- **Revoked endorsement causes cache re-fetch** — an engine that had accepted an endorsement re-fetches on the next use after detecting a matching revoke.
- **Signer with no authority block is not trustable** — a record signed by an entity with no on-chain authority block cannot have its signature verified through a discoverable public key.
- **Chain integrity walkable from record 1** — starting at record 1 and following `prev_hash` in reverse from any target record produces an unbroken chain.

## Related

- [fetch-discovery/blockchain](./) — the parent page on how the blockchain is used at the fetcher-and-verification layer. Everything on this page describes what those responses actually contain.
- [publishing](../publishing) — how authors submit URLs to be endorsed. This page describes the ledger records their submission ultimately produces.
- [content-types](https://puck.uno/requirements/content-types) — Content-Type strings used in blockchain API responses.
