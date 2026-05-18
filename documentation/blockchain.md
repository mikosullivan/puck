# Object Signing and the Blockchain Registry

<a id="status"></a>
## 1 Status

**Deferred from production.** Blockchain is an official part of the Kiera ecoverse and
the design properties documented here remain the intended target. However, no chain
implementation is in scope for the current development phase — Kiera will not run its
own blockchain server. Hosting will eventually be done by a third party (e.g. AWS or
similar). It will be a long time before any code in this repository touches a real chain.

This document continues to serve as the design specification for what the chain will
look like when it does ship.

<a id="future-engine-settings"></a>
### 1.1 Future engine settings

When the time comes, Kiera engines will accept configuration for **blockchain queries** —
which provider to consult, which authority blocks to trust as roots, cache TTLs, fallback
behavior, and so on. The exact shape of these settings is **TBD**. Nothing in the engine
or in any production component should assume a chain is reachable today.

<a id="note-to-stuart"></a>
### 1.2 Note to Stuart

You might want to start with [Use Case: Third-Party Endorsement](#use-case-third-party-endorsement).

---

<a id="the-problem"></a>
## 2 The Problem

Kiera is a distributed object system. Objects (classes, capabilities, etc.) are identified
by UNS addresses like `borg.com/foo`. When a Charlie engine fetches and uses an object, it
needs confidence that:

1. **The object really came from `borg.com`** — not from someone who injected a fake
   object with that UNS address.
2. **The object has not been modified** — what the engine received is exactly what was
   published.

A UNS string alone proves neither. It is just a name.

---

<a id="license"></a>
## 3 License

The Kiera distributed object system is released under the MIT License. This must be stated
in any overview or primer describing Kiera, including the `kiera_primer` field of authority
blocks.

Code distributed through the Kiera ecosystem is not considered distributable unless it
carries an explicit license. Provenance endorsements that sign a software artifact must
always include a `license` field. A provenance endorsement that omits `license` is invalid.

---

<a id="design-principles"></a>
## 4 Design Principles

**Kiera.uno holds one private key.** That is the only cryptographic key in the system
that Kiera manages. Everything flows from it.

**Domain owners manage nothing.** A publisher like `borg.com` does not need keys,
registration, or any special setup. They serve their objects over HTTPS. The TLS
certificate they already have is sufficient proof of domain ownership.

**Kiera server operators manage nothing.** They store and distribute bytes. Trust and
verification are not their concern.

**Engines ship with Kiera's public key baked in.** That single key is sufficient to
verify the entire system.

---

<a id="the-open-ledger"></a>
## 5 The Open Ledger

The Kiera blockchain is an open, append-only ledger of signed records about objects in the
Kiera distributed object system. Its purpose is to provide independently verifiable provenance
— anyone can confirm that a given object was fetched from its UNS address at a specific time
and signed by a specific key, without trusting Kiera.uno or any other central authority.

The chain is open. Anyone can post records, including creating their own authority blocks with
their own signing keys. An authority block is not a claim of ownership over the chain — it is
the anchor of a web of trust rooted in a particular key. Kiera.uno's authority block
establishes Kiera's own trust chain. A third party such as a security auditor or partner
organisation can post their own authority block and build an independent chain of endorsements,
delegations, and provenance records signed by their own key.

Trust is determined by whose authority block and signing key you choose to trust, not by who
is allowed to write to the ledger. The ledger is the record; the trust model is layered on top.

Any entity can post their own authority block and establish their own web of trust, completely
independent of Kiera. A company running internal Charlie infrastructure could run their own
chain, publish their own libraries, and configure their engines to trust their own authority
block instead of (or in addition to) Kiera's.

Engines can be configured to trust multiple authority blocks, enabling hybrid models: trust
Kiera for public libraries, trust an internal root for private ones.

---

<a id="trust-delegation"></a>
## 6 Trust Delegation

A `delegate` block extends trust to another entity. Kiera.uno can post a `delegate` block
that says: "I trust this entity's endorsements." The delegation references the trusted
entity's authority block by `target_hash` and lists the endorsement types it covers.

A delegation covers all blocks signed by the trusted entity from the time of their
authority block onward — including blocks posted before the delegation itself was written.
The order on the chain is not what matters; the anchor is the authority block. A consumer
reading the chain should apply a delegation retroactively to any block signed by that
entity after their authority block, regardless of whether the delegation appeared before
or after those blocks.

This allows Kiera.uno to hand off stewardship — to a regional maintainer, a successor
organisation, or any trusted party — without breaking anything for engines that already
trust the authority block. The delegation is on the chain, permanent and auditable.

Delegated trust can be chained: Kiera trusts Entity A, Entity A trusts Entity B, and so
on. Engines following the chain extend trust transitively.

---

<a id="how-kiera-vouches-for-an-object"></a>
## 7 How Kiera Vouches for an Object

Signing is not automatic. The fact that a domain serves objects over HTTPS does not mean
Kiera will sign them. The domain owner must explicitly request signing through kiera.uno.
They are in charge of which objects get submitted and when.

1. The domain owner submits their object through kiera.uno
2. Kiera fetches the object from their domain over HTTPS — TLS proves it is talking to
   the real domain owner
3. Kiera posts an `endorse` block with `endorsement: "provenance"`, embedding the object's
   fields directly in the endorsement entry

When an engine needs `borg.com/foo`, it queries Kiera's API, receives the signed block, and
verifies Kiera's signature using the baked-in public key. If the signature is valid, the
object is trusted.

---

<a id="the-blockchain-as-registry"></a>
## 8 The Blockchain as Registry

The blockchain serves as the permanent, decentralized registry for published objects.
Once a block is posted, it is available forever regardless of what happens to any
specific server. No single server going offline can make a published library unavailable.

This is not the only way to obtain objects — objects can also be fetched directly from
Kiera servers or other sources — but it is the highest-trust path. An object on the
blockchain was verified by Kiera at the time of posting and cannot be silently altered.

Kiera provides an API over the blockchain so engines do not need to interact with the
chain directly. The API handles lookup by UNS address and returns the signed block.

---

<a id="chain-design"></a>
## 9 Chain Design

The Kiera blockchain is a permissioned append-only ledger. There is no mining, no
proof-of-work, and no gas. Records are written directly by authorised signers. Validity
is determined by signature verification and hash chaining, not by computational work.

Each record in the chain is a JSON object with the following envelope fields:

- `intent` — the block's intent; well-known values: `authority`, `grammar`, `endorse`,
  `delegate`, `deprecate`, `revoke`
- `prev_hash` — SHA-256 hash of the previous record (hex); `null` for the first block
- `posted` — ISO 8601 UTC timestamp of when the record was written to the ledger
- `signer` — UNS address of the signing entity
- `payload` — the record-specific data (see Record Types below)
- `signature` — Ed25519 signature (base64) over the record with the `signature` field
  omitted, keys sorted alphabetically, minified JSON

Records are never modified or deleted. The chain is valid if every `prev_hash` matches
the SHA-256 of the preceding record.

---

<a id="record-types-grammar-v10"></a>
## 10 Record Types — Grammar v1.0

All blocks must include a `grammar` field in their payload referencing the grammar block
by hash. The hash is authoritative for machine verification; the version string is for
human readability:

```json
"grammar": {"hash": "a3f9c2...", "version": "1.0"}
```

A `grammar` field pointing to an unrecognised hash is valid — consumers that do not
recognise the grammar may choose to reject or accept such blocks at their discretion.

**grammar** — defines a block grammar version; posted first so all subsequent blocks
can reference it by `record_hash`.

```json
{
  "intent": "grammar",
  "version": "1.0",
  "description": "Kiera blockchain block grammar version 1.0",
  "grammar": {"hash": "self", "version": "1.0"},
  "envelope": {
    "fields": ["intent", "prev_hash", "posted", "signer", "payload", "signature"],
    "required": ["intent", "prev_hash", "posted", "signer", "payload", "signature"]
  },
  "payload_common": {
    "fields": ["intent", "grammar", "vibecode"],
    "required": ["intent", "grammar"],
    "encouraged": ["vibecode"]
  },
  "intent_values": ["authority", "grammar", "endorse", "mirror", "delegate", "deprecate", "revoke"],
  "endorsement_values": ["canonical", "provenance", "license-verified", "security", "audit"]
}
```

The grammar block uses `{"hash": "self", "version": "1.0"}` for its own `grammar` field
since it cannot reference itself before it exists. This is the only block that will ever
use `"self"`. A grammar may optionally include an `inherits` field pointing to a parent
grammar block, allowing domain-specific grammars (DSLs) to extend the base without
duplicating it.

The canonical posting order for any chain is: grammar block first, authority block second.
This eliminates all bootstrapping problems — every block from the authority onward has a
real grammar hash.

---

**authority** — anchor of trust; establishes a signer's identity and public key on the
chain. Any entity may post their own authority block.

Required payload fields:

- `intent` — always `"authority"`
- `grammar` — reference to the grammar block
- `note` — one-line description of this authority
- `public_key` — the Ed25519 public key (PEM) for this authority's signatures
- `kiera_primer` — a complete self-contained introduction to the Kiera distributed object
  system; the authoritative cold-start reference for any agent or tool encountering the
  chain with no prior knowledge of Kiera; required on all authority blocks
- `vibecode` — compact machine-readable summary of the authority and its role

The content of `kiera_primer` and `vibecode` for the production chain will be supplied
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
      "language": "kiera.uno/software/charlie",
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
  "mirror_url": "https://archive.example.org/kiera/borg.com/parser/2.1.0.charlie",
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
  "entity": "chainguard.dev",
  "endorsements": ["provenance", "security"],
  "target_hash": "<chainguard.dev authority block record_hash>",
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
## 11 The Signing Scheme

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
## 12 Trust Tiers

| Source | Trust level |
|--------|-------------|
| Blockchain (via Kiera API) | Highest — Kiera signed it, immutable |
| Kiera server over HTTPS | High — TLS verified, but object could change |
| Other HTTPS source | Policy-dependent |
| Unsigned | Rejected |

---

<a id="what-each-party-manages"></a>
## 13 What Each Party Manages

| Party | Responsibility |
|-------|---------------|
| `borg.com` | Serve objects over HTTPS. Nothing else. |
| Kiera.uno | One private key. Fetch, sign, post to blockchain. |
| Kiera server operators | Store and serve bytes. Nothing else. |
| Charlie engines | Kiera's public key baked in. Verify on fetch. |

---

<a id="api"></a>
## 14 API

All blockchain services are hosted at `blockchain.kiera.uno`.

The Kiera Lua library does not include routines for querying the blockchain directly.
By default it operates through the API at `blockchain.kiera.uno`. The endpoints below
describe the intended shape; the final API spec will be a separate document.

<a id="submit-domain-owner-kiera"></a>
### 14.1 Submit (domain owner → Kiera)

`POST https://blockchain.kiera.uno/v1/submit`

Domain owner submits a UNS address. Kiera fetches, signs, and posts a provenance
endorsement block.

This endpoint is idempotent. If Kiera fetches the object and finds it identical to
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

<a id="fetch-engine-kiera"></a>
### 14.2 Fetch (engine → Kiera)

`GET https://blockchain.kiera.uno/v1/object/<uns>`

Returns the latest provenance endorsement block for a UNS address. The engine verifies
the signature client-side using the baked-in public key.

`GET https://blockchain.kiera.uno/v1/object/<uns>?version=2.1.0` — exact version match.

`GET https://blockchain.kiera.uno/v1/object/<uns>?at=2026-01-01` — latest version whose
`effective_date` is on or before the given date.

<a id="root-block"></a>
### 14.3 Root block

`GET https://blockchain.kiera.uno/v1/authority`

Returns Kiera's authority block. Used during engine setup to verify the baked-in public
key matches the chain.

---

<a id="versioning"></a>
## 15 Versioning

The Kiera ecoverse uses **date-pinned versioning** as its general model — a single
cutoff timestamp governs the entire library tree, set on `%chain.cutoff` at the top of
the call chain. The general model is documented in [versioning.md](../versioning.md);
this section describes how the blockchain anchors dates when it is in play.

Every block on the Kiera blockchain carries a `posted` timestamp assigned at insertion.
This is not set by the submitter — it is canonical and tamper-evident.

**Default behaviour: latest within range.** When you request an object with no version
constraint, you get the most recently posted version. When you request with a date range,
you get the most recently posted version that falls within that range.

<a id="effective-date"></a>
### 15.1 Effective Date

A signer may set an `effective_date` on an endorsement to declare the date that
should be used for version ordering in place of `posted`. This allows historical objects
to be correctly ordered — a library released ten years ago can be posted to the chain
today with `effective_date` set to its original release date.

`effective_date` is optional. Omitting it means `posted` governs.

<a id="tombstone-and-birthstone"></a>
### 15.2 Tombstone and Birthstone

A **tombstone** is an upper bound: "give me the latest version on or before this date."
Setting a tombstone pins resolution to a point in time — useful for reproducible builds.

A **birthstone** is a lower bound: "do not give me anything older than this date."
Useful for excluding objects published before a known-good baseline.

```json
{"uns": "borg.com/parser", "tombstone": "2025-06-01T00:00:00Z", "birthstone": "2024-01-01T00:00:00Z"}
```

<a id="dependency-resolution"></a>
### 15.3 Dependency Resolution

Each object may declare its own dependencies — by UNS name — along with an optional
date range per dependency. When the gateway resolves a request, it traverses the
dependency graph and applies the outer request range at every node.

If an object declares a narrower range for one of its dependencies, the system
intersects that range with the outer range. The narrower of the two wins. If the
intersection is empty, resolution fails rather than silently selecting something outside
the intended range.

---

<a id="use-case-third-party-endorsement"></a>
## 16 Use Case: Third-Party Endorsement

**Scenario:** ChainGuard is a security auditing company. A government contractor needs
to verify that `borg.com/parser` meets NIST 800-53 security requirements before
deploying it. ChainGuard reviews the library and posts an endorsement to the chain.

A collaboration between Kiera and ChainGuard could be a mutually beneficial arrangement.

**Step 1 — Kiera vouches for provenance.**

`borg.com` submits their library through kiera.uno. Kiera fetches it over HTTPS and
posts a provenance endorsement block with the object embedded in the `bucket`:

```json
{
  "intent": "endorse",
  "prev_hash": "...",
  "posted": "2026-05-04T09:00:00Z",
  "signer": "kiera.uno",
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

**Step 2 — ChainGuard establishes its identity.**

ChainGuard has its own Ed25519 key pair. It posts its own authority block to the chain,
establishing its identity independently of Kiera. No permission from Kiera is required.

```json
{
  "intent": "authority",
  "prev_hash": "...",
  "posted": "2026-05-04T10:00:00Z",
  "signer": "chainguard.dev",
  "payload": {
    "intent": "authority",
    "grammar": {"hash": "...", "version": "1.0"},
    "note": "ChainGuard security audit authority — independent assessments for government contractors",
    "public_key": "-----BEGIN PUBLIC KEY-----\n...",
    "kiera_primer": "..."
  },
  "signature": "base64..."
}
```

---

**Step 3 — ChainGuard reviews and endorses.**

ChainGuard fetches Kiera's provenance block, reviews the `bucket` contents, and posts
an endorsement referencing that block by its `record_hash`. ChainGuard does not re-fetch
from `borg.com` and does not re-post the source — they are endorsing the specific block
Kiera already verified.

```json
{
  "intent": "endorse",
  "prev_hash": "...",
  "posted": "2026-05-04T11:00:00Z",
  "signer": "chainguard.dev",
  "payload": {
    "intent": "endorse",
    "grammar": {"hash": "...", "version": "1.0"},
    "target_hash": "<record_hash of Kiera's provenance block>",
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

1. Kiera's signature on the provenance block — origin confirmed, object unmodified
2. ChainGuard's endorsement referencing that same block — security criteria met

Both checks are independent. The engine trusts Kiera's public key (baked in) and
ChainGuard's public key (configured by the contractor). Neither party needed to
coordinate with the other. The shared ledger is what ties them together.

<a id="collaboration-kiera-delegates-to-chainguard"></a>
### 16.1 Collaboration: Kiera Delegates to ChainGuard

Although Kiera and ChainGuard can operate completely independently, there is a deeper
collaboration available through trust delegation.

Kiera posts a `delegate` block naming ChainGuard as a trusted endorser:

```json
{
  "intent": "delegate",
  "prev_hash": "...",
  "posted": "...",
  "signer": "kiera.uno",
  "payload": {
    "intent": "delegate",
    "grammar": {"hash": "...", "version": "1.0"},
    "entity": "chainguard.dev",
    "endorsements": ["provenance", "security"],
    "target_hash": "<chainguard.dev authority block record_hash>",
    "note": "Kiera delegates provenance and security trust to ChainGuard."
  },
  "signature": "base64..."
}
```

With this delegation in place, ChainGuard can fetch objects from domains over HTTPS
and post provenance endorsements signed with their own key. Engines that trust Kiera's
authority block follow the delegation chain and accept ChainGuard's blocks as trusted
provenance — exactly as they would accept blocks signed by Kiera directly.

This offloads the fetch-and-sign work from Kiera entirely. ChainGuard becomes an
operational partner: they fetch, they sign, they post, and they add their security
endorsement in the same pass. Kiera's role shrinks to maintaining the authority block
and the delegation record.

The broader opportunity is significant. The Kiera blockchain is not limited to Charlie
objects — it can store Python libraries, Go modules, or any signed artifact. A company
like ChainGuard, trusted by Kiera and trusted by governments, could position itself as
a leading authority on security-cleared open source across languages and ecosystems.
Any engine or toolchain that knows how to read the chain gains access to that trust
infrastructure with no additional setup.

<a id="partnership-goal"></a>
### 16.2 Partnership Goal

Kiera is actively seeking a partner in this space — a company analogous to ChainGuard
whose endorsements and deprecations would be surfaced directly through the
`blockchain.kiera.uno` API. When such a partnership is in place, a developer calling
the fetch endpoint would receive not just Kiera's provenance block but also the
partner's security assessment in the same response — one API call, one result,
government-grade confidence included.

This removes friction for developers who need to ship within government specifications.
They do not need to know anything about the partner's internal processes or query a
separate API. The blockchain.kiera.uno response tells them everything: where the object
came from, that it hasn't been modified, and whether it meets the security criteria they
care about.

As Stuart says, this scratches an itch.

---

<a id="design-notes"></a>
## 17 Design Notes

**Ed25519 is the right choice.** 64-byte signatures, fast verification, no parameter
choices that can be misconfigured, widely supported in every language runtime Kiera is
likely to encounter.

**Alphabetically sorted canonical JSON.** Signing uses minified JSON with all keys sorted
alphabetically at every level. This is deterministic regardless of the order in which
fields were constructed, and is compatible with RFC 8785 (JCS). All Kiera tooling must
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
## 18 Open Issues

**Software namespace identifier bloat.** As `kiera.uno/software` grows (programming
languages, DBMSs, frameworks), putting every identifier on the chain would bloat it.
Most identifiers are just namespace declarations and don't need provenance or revocation
the way published artifacts do. Do software identifiers belong on the chain at all, or
should the chain only carry records that reference them?
