# Object Signing and the Blockchain Registry

~~~json
{"vibecode": {
	"doc": "blockchain",
	"role": "design spec for Puck's object-signing and blockchain registry: how UNS-addressed objects prove provenance and integrity",
	"key_concepts": ["object_signing", "uns_provenance", "authority_blocks",
		"third_party_endorsement", "engine_chain_settings"]
}}
~~~

<a id="contents"></a>
## 1 Contents

- [Status](#status)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Design Principles](#design-principles)
- [The Open Ledger](#the-open-ledger)
- [Authority Blocks](#authority-blocks)
- [Trust Delegation](#trust-delegation)
- [How Puck Vouches for an Object](#how-puck-vouches-for-an-object)
- [The Blockchain as Registry](#the-blockchain-as-registry)
- [Chain Design](#chain-design)
- [Record Types — Grammar v1.0](#record-types-grammar-v10)
- [The Signing Scheme](#the-signing-scheme)
- [Trust Tiers](#trust-tiers)
- [What Each Party Manages](#what-each-party-manages)
- [API](#api)
  - [Submit (domain owner → Puck)](#submit-domain-owner-puck)
  - [Fetch (engine → Puck)](#fetch-engine-puck)
  - [Root block](#root-block)
- [Versioning](#versioning)
  - [Effective Date](#effective-date)
  - [Tombstone and Birthstone](#tombstone-and-birthstone)
  - [Dependency Resolution](#dependency-resolution)
- [Use Case: Third-Party Endorsement](#use-case-third-party-endorsement)
  - [Collaboration: Puck Delegates to Castle Security](#collaboration-puck-delegates-to-castle-security)
  - [Partnership Goal](#partnership-goal)
- [Design Notes](#design-notes)
- [Open Issues](#open-issues)

---

<a id="status"></a>
## 2 Status

The blockchain design described here will ship as part of the
V1 Puck ecoverse. Puck.uno will provide a public interface for the
blockchain. Charlie will natively know about that service. We won't
actually ship blockchain technology in the core product.

<a id="the-problem"></a>
## 3 The Problem

Puck is a distributed object system. Objects (classes, capabilities, etc.) are identified
by UNS addresses like `borg.com/foo`. When a Charlie engine fetches and uses an object, it
needs confidence that:

1. **The object really came from `borg.com`** — not from someone who injected a fake
   object with that UNS address.
2. **The object has not been modified** — what the engine received is exactly what was
   published.

A UNS string alone proves neither. It is just a name.

<a id="the-solution"></a>
## 4 The Solution

Software authors publish their packages at URLs they control, served
over HTTPS. The TLS certificate they already have is the only
credential they need.

When they want to publish a snapshot of their package, they tell a
service at Puck.uno to record it. Puck.uno does two things:

- **Signs** the snapshot and posts the signature to a public
  blockchain — provenance any engine can verify against Puck's
  baked-in public key.
- **Caches** the bytes and serves them via a public download
  service — so engines can fetch the snapshot even if the author's
  site goes down.

---

<a id="design-principles"></a>
## 5 Design Principles

**Puck.uno holds one private key.** That is the only cryptographic key in the system
that Puck manages. Everything flows from it.

**Domain owners manage nothing.** A publisher like `borg.com` does not need keys,
registration, or any special setup. They serve their objects over HTTPS. The TLS
certificate they already have is sufficient proof of domain ownership.

**Puck server operators manage nothing.** They store and distribute bytes. Trust and
verification are not their concern.

**Engines ship with Puck's public key baked in.** That single key is sufficient to
verify the entire system.

---

<a id="the-open-ledger"></a>
## 6 The Open Ledger

The Puck blockchain is an open, append-only ledger of signed records about objects
in the Puck distributed object system. Its purpose is to provide independently
verifiable provenance. Anyone can confirm that a given object was fetched from
its UNS address at a specific time and signed by a specific key.


---

<a id="authority-blocks"></a>
## 7 Authority Blocks

An **authority block** is the anchor of a trust chain on the ledger.
It's a signed record that establishes a public key as a known
identity — every endorsement, delegation, or provenance record
signed by that key chains back to its authority block.

**Trust is determined by whose authority block you choose to trust**,
not by who is allowed to write to the ledger. The ledger is the
record; the trust model is layered on top.

Anyone can post an authority block. Puck.uno posts the first one (its
key is baked into engines), but a security auditor, a partner
organisation, or a company running internal Charlie infrastructure
can post their own and build an independent trust chain rooted in
their own key. Engines can be configured to trust multiple authority
blocks — Puck's for public libraries, an internal root for private
ones.

---

<a id="trust-delegation"></a>
## 8 Trust Delegation

A `delegate` block extends trust to another entity. Puck.uno can post a `delegate` block
that says: "I trust this entity's endorsements." The delegation references the trusted
entity's authority block by `target_hash` and lists the endorsement types it covers.

A delegation covers all blocks signed by the trusted entity from the time of their
authority block onward — including blocks posted before the delegation itself was written.
The order on the chain is not what matters; the anchor is the authority block. A consumer
reading the chain should apply a delegation retroactively to any block signed by that
entity after their authority block, regardless of whether the delegation appeared before
or after those blocks.

This allows Puck.uno to hand off stewardship — to a regional maintainer, a successor
organisation, or any trusted party — without breaking anything for engines that already
trust the authority block. The delegation is on the chain, permanent and auditable.

Delegated trust can be chained: Puck trusts Entity A, Entity A trusts Entity B, and so
on. Engines following the chain extend trust transitively.

---

<a id="how-puck-vouches-for-an-object"></a>
## 9 How Puck Vouches for an Object

Signing is not automatic. The fact that a domain serves objects over HTTPS does not mean
Puck will sign them. The domain owner must explicitly request signing through puck.uno.
They are in charge of which objects get submitted and when.

1. The domain owner submits their object through puck.uno
2. Puck fetches the object from their domain over HTTPS — TLS proves it is talking to
   the real domain owner
3. Puck posts an `endorse` block with `endorsement: "provenance"`, embedding the object's
   fields directly in the endorsement entry


When an engine needs `borg.com/foo`, it queries Puck's API, receives the signed block, and
verifies Puck's signature using the baked-in public key. If the signature is valid, the
object is trusted.

The object must include a valid open source license. Any
[SPDX license identifier](https://spdx.org/licenses/) is
accepted.The license is exposed as a `license` field on the object
served at its UNS URL:

```json
{
    "name":    "borg.com/foo",
    "version": "1.2.0",
    "license": "MIT",
    ...
}
```

---

<a id="chain-design"></a>
## 11 Chain Design

The Puck blockchain is an **open** append-only ledger. There is no mining, no
proof-of-work, and no gas. Anyone can post a record. Trust in a given record comes
from trusting its signer
(see [Authority Blocks](#authority-blocks)).

Each record in the chain is a JSON object with the following envelope fields:

- `intent` — the block's intent; well-known values: `authority`, `grammar`, `endorse`,
  `delegate`, `deprecate`, `revoke`
- `prev_hash` — SHA-256 hash of the previous record (hex); `null` for the first block
- `posted` — ISO 8601 UTC timestamp of when the record was written to the ledger
- `signer` — UNS address of the signing entity
- `payload` — the record-specific data (see Record Types below)
- `signature` — Ed25519 signature (base64) over the record with the `signature` field
  omitted, keys sorted alphabetically, minified JSON

Records are never modified or deleted.

---

<a id="record-types-grammar-v10"></a>
## 12 Record Types — Grammar v1.0

All blocks must include a `grammar` field in their payload referencing a grammar block
by hash and version string:

```json
"grammar": {"hash": "a3f9c2...", "version": "1.0"}
```

Grammar blocks will help keep the block syntax consistent while
allowing for evolution in the syntax. Puck.uno will post the first
grammar block.

---

<a id="authority-blocks"></a>
## 12 Authority blocks

**authority** — anchor of trust; establishes a signer's identity and public key on the
chain. Any entity may post their own authority block.

Required payload fields:

- `intent` — always `"authority"`
- `grammar` — reference to the grammar block
- `note` — one-line description of this authority
- `public_key` — the Ed25519 public key (PEM) for this authority's signatures
- `puck_primer` — a complete self-contained introduction to the Puck distributed object
  system; the authoritative cold-start reference for any agent or tool encountering the
  chain with no prior knowledge of Puck; required on all authority blocks
- `vibecode` — compact machine-readable summary of the authority and its role

The content of `puck_primer` and `vibecode` for the production chain will be supplied
by Miko. Both must be present before the authority block is posted to any production chain.

---

**endorse** — a claim made by the signer about a target. The target may be another block
(referenced by `target_hash`) or content embedded within this block (`target_hash: "self"`).

**The chain does not store software bodies.** A provenance endorsement signs an artifact
by referencing it cryptographically — the artifact itself is hosted off-chain (the
publisher's HTTPS server, a package registry, a content-addressed store, etc.). The
on-chain record carries the artifact's hash so anyone can verify a fetched copy matches
what was signed.

To publish provenance for software, post an `endorse` block with `endorsement: "provenance"`
and include the artifact metadata directly in the endorsement entry alongside `endorsement`.
The required cryptographic anchor is `artifact_hash`. Additional endorsement entries in
the same block — or in a later block by a third party — can assert security, license, or
other claims.

Provenance endorsement (signed by the publisher):

```json
{
  "intent": "endorse",
  "grammar": {"hash": "...", "version": "1.0"},
  "target_hash": "self",
  "uns": "borg.com/parser",
  "version": "2.1.0",
  "effective_date": "2026-05-07",
  "endorsements": [
    {
      "endorsement": "provenance",
      "name": "borg.com/parser",
      "description": "Parses structured text into a normalised output hash.",
      "language": "puck.uno/software/charlie",
      "license": "MIT",
      "version": "2.1.0",
      "artifact_hash": "sha256:...",
      "artifact_url": "https://borg.com/parser/2.1.0.tar.gz"
    }
  ]
}
```

Third-party security endorsement (references a prior provenance block by hash):

```json
{
  "intent": "endorse",
  "grammar": {"hash": "...", "version": "1.0"},
  "target_hash": "a3f9c2...",
  "endorsements": [
    {"endorsement": "security", "security": {"fedramp-moderate": true}, "notes": "Reviewed 2026-05-07"},
    {"endorsement": "license-verified", "notes": "Confirmed MIT via SPDX scan"}
  ]
}
```

Fields:

- `target_hash` — `record_hash` of the block being endorsed; `"self"` when endorsed
  content is embedded within this block
- `uns` — UNS address of the software being endorsed (when applicable)
- `version` — the specific version being endorsed
- `effective_date` — date from which this endorsement applies; may differ from `posted`
  for historical objects
- `endorsements` — array of claims; each entry is a flat object whose fields are:
  - `endorsement` — what is being claimed; open-ended string; well-known values:
    `canonical` (the signer asserts this is the authoritative reference for its kind),
    `provenance` (fetched from the stated UNS at the stated time),
    `license-verified` (stated license confirmed accurate),
    `security` (see below),
    `audit` (general security review); third parties may define their own values
  - artifact fields — for `provenance` entries, the artifact's metadata (`name`,
    `description`, `language`, `license`, `version`, `artifact_hash`, `artifact_url`,
    etc.) appears directly in the entry alongside `endorsement`. `artifact_hash` and
    `license` are required. Software bodies are not stored on the chain — `artifact_hash`
    is the cryptographic anchor and the artifact itself lives off-chain at `artifact_url`
    or another resolvable location.
  - `security` — present when `endorsement` is `security`; an object whose keys are
    standard identifiers and whose values are booleans (pass/fail); e.g.
    `{"fedramp-moderate": true, "fips-140-2": true}`; well-known keys include
    `fedramp-moderate`, `fedramp-high`, `fips-140-2`
  - `notes` — free-form elaboration on this specific claim

---

**mirror** — declares that the signer hosts a copy of an artifact at an alternate URL.
Mirror blocks make code resilient to takedowns or upstream outages: if the original
publisher's URL goes away, consumers can fetch the same bytes from any mirror that
matches the artifact's hash.

```json
{
  "intent": "mirror",
  "grammar": {"hash": "...", "version": "1.0"},
  "target_hash": "<provenance block record_hash>",
  "uns": "borg.com/parser",
  "version": "2.1.0",
  "artifact_hash": "sha256:8f2a3b7d1e9c4a5f...",
  "mirror_url": "https://archive.example.org/puck/borg.com/parser/2.1.0.charlie",
  "notes": "Mirror of borg.com/parser 2.1.0 hosted by archive.example.org."
}
```

Fields:

- `target_hash` — `record_hash` of the original provenance block being mirrored
- `uns` and `version` — duplicated at the top level for cheap filtering ("all mirrors of
  this UNS at this version") without descending into the target block
- `artifact_hash` — duplicated from the target block. Lets consumers verify a mirror's
  bytes without first fetching the target, and keeps the mirror honest: if the bytes at
  `mirror_url` don't hash to this value, the mirror is broken or lying
- `mirror_url` — URL where the signer hosts the copy. Distinct from the original block's
  `artifact_url` because the signer here is the mirror operator, not the publisher

The signer is the mirror operator and must have their own authority block on chain.
Mirror blocks fall under intent-level trust delegation: consumers who trust an entity
for `mirror` intents (via a delegate block listing `intents: ["mirror"]`) accept mirror
blocks signed by that entity automatically.

Original publishers can also post mirror blocks for their own artifacts — e.g. if
`borg.com` puts the parser on a CDN, they can sign a mirror block pointing at the CDN URL.
The mechanism is the same; no special case for self-mirrors.

---

**delegate** — grants another entity trusted endorser status for a specified set of
endorsement types. The delegation is scoped to the entity's authority block via
`target_hash` and covers all blocks that entity has signed or will sign from that
authority block onward.

```json
{
  "intent": "delegate",
  "grammar": {"hash": "...", "version": "1.0"},
  "entity": "castlesecurity.com",
  "endorsements": ["provenance", "security"],
  "target_hash": "<castlesecurity.com authority block record_hash>",
  "note": "..."
}
```

Fields:

- `entity` — UNS address of the entity being trusted
- `endorsements` — allowlist of endorsement types covered by this delegation; blocks
  from the entity with other endorsement types are not covered
- `target_hash` — `record_hash` of the entity's authority block; the delegation covers
  all blocks signed by that entity from that anchor onward, including blocks posted
  before this delegation was written

---

**deprecate** — marks a UNS or version range as deprecated. Does not invalidate the record;
consumers decide how to respond.

```json
{
  "intent": "deprecate",
  "grammar": {"hash": "...", "version": "1.0"},
  "uns": "borg.com/parser",
  "version": "1.0.0",
  "reason": "superseded by 2.0.0"
}
```

---

**revoke** — invalidates a previously posted record (e.g. due to key compromise or bad data).

```json
{
  "intent": "revoke",
  "grammar": {"hash": "...", "version": "1.0"},
  "target_hash": "a3f9c2...",
  "reason": "key compromise"
}
```

---

<a id="the-signing-scheme"></a>
## 13 The Signing Scheme

To sign a record:

1. Construct the record as a JSON object with all fields except `signature`
2. Serialize to minified JSON with all keys sorted alphabetically at every level
3. Sign the UTF-8 bytes using Ed25519
4. Base64-encode the signature and add it as the `signature` field

To verify, remove the `signature` field, re-serialize with sorted keys, and run Ed25519
verify against that string using the signer's public key (found in their authority block).

The `record_hash` is the SHA-256 hex digest of the fully serialized record including the
`signature` field, keys sorted alphabetically.

---

<a id="trust-tiers"></a>
## 14 Trust Tiers

| Source | Trust level |
|--------|-------------|
| Blockchain (via Puck API) | Highest — Puck signed it, immutable |
| Puck server over HTTPS | High — TLS verified, but object could change |
| Other HTTPS source | Policy-dependent |
| Unsigned | Rejected |

---

<a id="what-each-party-manages"></a>
## 15 What Each Party Manages

| Party | Responsibility |
|-------|---------------|
| `borg.com` | Serve objects over HTTPS. Nothing else. |
| Puck.uno | One private key. Fetch, sign, post to blockchain. |
| Puck server operators | Store and serve bytes. Nothing else. |
| Charlie engines | Puck's public key baked in. Verify on fetch. |

---

<a id="api"></a>
## 16 API

All blockchain services are hosted at `blockchain.puck.uno`.

The Puck Lua library does not include routines for querying the blockchain directly.
By default it operates through the API at `blockchain.puck.uno`. The endpoints below
describe the intended shape; the final API spec will be a separate document.

<a id="submit-domain-owner-puck"></a>
### 16.1 Submit (domain owner → Puck)

`POST https://blockchain.puck.uno/v1/submit`

Domain owner submits a UNS address. Puck fetches, signs, and posts a provenance
endorsement block.

This endpoint is idempotent. If Puck fetches the object and finds it identical to
the most recently posted version, it returns the existing block rather than posting
a new one.

Request:
```json
{"uns": "borg.com/foo", "fetch_url": "https://borg.com/foo"}
```

Response:
```json
{"status": "posted", "uns": "borg.com/foo", "record_hash": "..."}
```

<a id="fetch-engine-puck"></a>
### 16.2 Fetch (engine → Puck)

`GET https://blockchain.puck.uno/v1/object/<uns>`

Returns the latest provenance endorsement block for a UNS address. The engine verifies
the signature client-side using the baked-in public key.

`GET https://blockchain.puck.uno/v1/object/<uns>?version=2.1.0` — exact version match.

`GET https://blockchain.puck.uno/v1/object/<uns>?at=2026-01-01` — latest version whose
`effective_date` is on or before the given date.

<a id="root-block"></a>
### 16.3 Root block

`GET https://blockchain.puck.uno/v1/authority`

Returns Puck's authority block. Used during engine setup to verify the baked-in public
key matches the chain.

---

<a id="versioning"></a>
## 17 Versioning

The Puck ecoverse uses **date-pinned versioning** as its general model — a single
cutoff timestamp governs the entire library tree, set on `%chain.cutoff` at the top of
the call chain. The general model is documented in [versioning.md](../versioning.md);
this section describes how the blockchain anchors dates when it is in play.

Every block on the Puck blockchain carries a `posted` timestamp assigned at insertion.
This is not set by the submitter — it is canonical and tamper-evident.

**Default behaviour: latest within range.** When you request an object with no version
constraint, you get the most recently posted version. When you request with a date range,
you get the most recently posted version that falls within that range.

<a id="effective-date"></a>
### 17.1 Effective Date

A signer may set an `effective_date` on an endorsement to declare the date that
should be used for version ordering in place of `posted`. This allows historical objects
to be correctly ordered — a library released ten years ago can be posted to the chain
today with `effective_date` set to its original release date.

`effective_date` is optional. Omitting it means `posted` governs.

<a id="tombstone-and-birthstone"></a>
### 17.2 Tombstone and Birthstone

A **tombstone** is an upper bound: "give me the latest version on or before this date."
Setting a tombstone pins resolution to a point in time — useful for reproducible builds.

A **birthstone** is a lower bound: "do not give me anything older than this date."
Useful for excluding objects published before a known-good baseline.

```json
{"uns": "borg.com/parser", "tombstone": "2025-06-01T00:00:00Z", "birthstone": "2024-01-01T00:00:00Z"}
```

<a id="dependency-resolution"></a>
### 17.3 Dependency Resolution

Each object may declare its own dependencies — by UNS name — along with an optional
date range per dependency. When the gateway resolves a request, it traverses the
dependency graph and applies the outer request range at every node.

If an object declares a narrower range for one of its dependencies, the system
intersects that range with the outer range. The narrower of the two wins. If the
intersection is empty, resolution fails rather than silently selecting something outside
the intended range.

---

<a id="use-case-third-party-endorsement"></a>
## 18 Use Case: Third-Party Endorsement

**Scenario:** Castle Security is a security auditing company. A government contractor needs
to verify that `borg.com/parser` meets NIST 800-53 security requirements before
deploying it. Castle Security reviews the library and posts an endorsement to the chain.

A collaboration between Puck and Castle Security could be a mutually beneficial arrangement.

**Step 1 — Puck vouches for provenance.**

`borg.com` submits their library through puck.uno. Puck fetches it over HTTPS and
posts a provenance endorsement block with the object embedded in the `bucket`:

```json
{
  "intent": "endorse",
  "prev_hash": "...",
  "posted": "2026-05-04T09:00:00Z",
  "signer": "puck.uno",
  "payload": {
    "intent": "endorse",
    "grammar": {"hash": "...", "version": "1.0"},
    "target_hash": "self",
    "uns": "borg.com/parser",
    "version": "2.1.0",
    "effective_date": "2026-05-04",
    "endorsements": [
      {
        "endorsement": "provenance",
        "name": "borg.com/parser",
        "fields": {"input": "string", "output": "string"},
        "license": "MIT"
      }
    ]
  },
  "signature": "base64..."
}
```

This block answers one question: *did this object really come from borg.com?* Nothing more.

---

**Step 2 — Castle Security establishes its identity.**

Castle Security has its own Ed25519 key pair. It posts its own authority block to the chain,
establishing its identity independently of Puck. No permission from Puck is required.

```json
{
  "intent": "authority",
  "prev_hash": "...",
  "posted": "2026-05-04T10:00:00Z",
  "signer": "castlesecurity.com",
  "payload": {
    "intent": "authority",
    "grammar": {"hash": "...", "version": "1.0"},
    "note": "Castle Security security audit authority — independent assessments for government contractors",
    "public_key": "-----BEGIN PUBLIC KEY-----\n...",
    "puck_primer": "..."
  },
  "signature": "base64..."
}
```

---

**Step 3 — Castle Security reviews and endorses.**

Castle Security fetches Puck's provenance block, reviews the `bucket` contents, and posts
an endorsement referencing that block by its `record_hash`. Castle Security does not re-fetch
from `borg.com` and does not re-post the source — they are endorsing the specific block
Puck already verified.

```json
{
  "intent": "endorse",
  "prev_hash": "...",
  "posted": "2026-05-04T11:00:00Z",
  "signer": "castlesecurity.com",
  "payload": {
    "intent": "endorse",
    "grammar": {"hash": "...", "version": "1.0"},
    "target_hash": "<record_hash of Puck's provenance block>",
    "endorsements": [
      {
        "endorsement": "security",
        "security": {"fedramp-moderate": true},
        "notes": "Reviewed 2026-05-04. borg.com/parser meets all applicable NIST 800-53 controls for input validation and output sanitization."
      }
    ]
  },
  "signature": "base64..."
}
```

---

**Step 4 — The contractor's engine checks both.**

The engine fetches `borg.com/parser`. It verifies:

1. Puck's signature on the provenance block — origin confirmed, object unmodified
2. Castle Security's endorsement referencing that same block — security criteria met

Both checks are independent. The engine trusts Puck's public key (baked in) and
Castle Security's public key (configured by the contractor). Neither party needed to
coordinate with the other. The shared ledger is what ties them together.

<a id="collaboration-puck-delegates-to-castle-security"></a>
### 18.1 Collaboration: Puck Delegates to Castle Security

Although Puck and Castle Security can operate completely independently,
collaborating could be a mutually beneficial arrangement.

Puck posts a `delegate` block naming Castle Security as a trusted endorser:

```json
{
  "intent": "delegate",
  "prev_hash": "...",
  "posted": "...",
  "signer": "puck.uno",
  "payload": {
    "intent": "delegate",
    "grammar": {"hash": "...", "version": "1.0"},
    "entity": "castlesecurity.com",
    "endorsements": ["provenance", "security"],
    "target_hash": "<castlesecurity.com authority block record_hash>",
    "note": "Puck delegates provenance and security trust to Castle Security."
  },
  "signature": "base64..."
}
```

With this delegation in place, Castle Security can fetch objects from domains over HTTPS
and post provenance endorsements signed with their own key. Engines that trust Puck's
authority block follow the delegation chain and accept Castle Security's blocks as trusted
provenance — exactly as they would accept blocks signed by Puck directly.

This offloads the fetch-and-sign work from Puck entirely. Castle Security becomes an
operational partner: they fetch, they sign, they post, and they add their security
endorsement in the same pass.

This removes friction for developers who need to ship within government specifications.
They do not need to know anything about the partner's internal processes or query a
separate API. The blockchain.puck.uno response tells them everything: where the object
came from, that it hasn't been modified, and whether it meets the security criteria they
care about.

The broader opportunity is significant. The Puck blockchain is not limited to Charlie
objects — it can store Python libraries, Go modules, or any signed artifact. A company
like Castle Security, trusted by Puck and trusted by governments, could position itself as
a leading authority on security-cleared open source across languages and ecosystems.
Any engine or toolchain that knows how to read the chain gains access to that trust
infrastructure with no additional setup.

<a id="partnership-goal"></a>
### 18.2 Partnership Goal

Puck is actively seeking a partner in this space — a company analogous to Castle Security
whose endorsements and deprecations would be surfaced directly through the
`blockchain.puck.uno` API.

---

<a id="design-notes"></a>
## 19 Design Notes

**Ed25519 is the right choice.** 64-byte signatures, fast verification, no parameter
choices that can be misconfigured, widely supported in every language runtime Puck is
likely to encounter.

**Alphabetically sorted canonical JSON.** Signing uses minified JSON with all keys sorted
alphabetically at every level. This is deterministic regardless of the order in which
fields were constructed, and is compatible with RFC 8785 (JCS). All Puck tooling must
sort keys before signing or verifying.

**Hash chaining.** Each record's `prev_hash` is the SHA-256 of the preceding record's
full serialized form (including its `signature`). This makes the chain tamper-evident:
altering any record invalidates every subsequent `prev_hash`.

**Revocation and caching.** A revoked object in cache should be re-fetched immediately.
Recommended strategy: on any object use, check for a `revoke` block covering that
`record_hash` with a short-lived local TTL (e.g. 5 minutes). If revoked, discard cache
and re-fetch.

**Grammar versioning.** The grammar is expected to evolve slowly — a handful of base
revisions and at most a few hundred DSL grammars in the most ambitious scenario. A block
referencing an unrecognised grammar hash is not automatically invalid; consumers decide
whether to accept or reject it.

**Mirror resolution.** Because `artifact_hash` is the cryptographic anchor, any URL
serving matching bytes is functionally equivalent to the original. This decouples trust
from location: a consumer can prefer mirrors over the original — for latency, geographic
proximity, internal-cache policy, or operator reputation — without weakening the
verification guarantee. The chain records availability ("here's a copy at this URL"); the
ranking policy belongs in the engine or fetch library, not in block grammar.

---

<a id="open-issues"></a>
## 20 Open Issues

**Software namespace identifier bloat.** As `puck.uno/software` grows (programming
languages, DBMSs, frameworks), putting every identifier on the chain would bloat it.
Most identifiers are just namespace declarations and don't need provenance or revocation
the way published artifacts do. Do software identifiers belong on the chain at all, or
should the chain only carry records that reference them?

