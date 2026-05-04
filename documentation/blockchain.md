# Object Signing and the Blockchain Registry

## Status

Blockchain is an official part of the Kiera ecoverse. The details of this design are
still being worked out. This document is a proposal being sent to Stuart for review.

Note to Stuart: you might want to start with [Use Case: Third-Party Endorsement](#use-case-third-party-endorsement).

---

## The Problem

Kiera is a distributed object system. Objects (classes, capabilities, etc.) are identified
by UNS addresses like `borg.com/foo`. When a KScript engine fetches and uses an object, it
needs confidence that:

1. **The object really came from `borg.com`** — not from someone who injected a fake
   object with that UNS address.
2. **The object has not been modified** — what the engine received is exactly what was
   published.

A UNS string alone proves neither. It is just a name.

---

## Key Design Decisions

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

## Trust Delegation

A block can extend trust to another entity on the chain. Kiera.uno can post a block that
says: "I trust this entity's blocks." From that point, objects signed by the trusted
entity are treated as if Kiera signed them.

This allows Kiera.uno to hand off stewardship — to a regional maintainer, a successor
organisation, or any trusted party — without breaking anything for engines that already
trust the root block. The delegation is on the chain, permanent and auditable.

Delegated trust can be chained: Kiera trusts Entity A, Entity A trusts Entity B, and so
on. Engines following the chain extend trust transitively.

---

## Independent Webs of Trust

Any entity can post their own root block and establish their own web of trust, completely
independent of Kiera. A company running internal KScript infrastructure could run their
own chain, publish their own libraries, and configure their engines to trust their own
root block instead of (or in addition to) Kiera's.

This is a powerful feature. The blockchain model is not Kiera-specific — it is a general
mechanism for establishing decentralised trust. Kiera.uno's web of trust is the default
that ships with every engine, but it is not the only one possible.

Engines can be configured to trust multiple root blocks, enabling hybrid models: trust
Kiera for public libraries, trust an internal root for private ones.

---

## The Root Block and Web of Trust

Kiera.uno posts a single block to the blockchain once. This is the **root block** — the
anchor for the entire trust system. It establishes Kiera's identity on the chain and
contains Kiera's public key.

KScript engines trust this root block by default. It is the one thing baked into every
compliant engine. Participants who choose not to trust it are opting out of the Kiera
trust model entirely.

Every subsequent block that Kiera posts — each signed object, each domain verification,
each revocation — is cryptographically linked back to the root block. Because the
blockchain is append-only and the root block cannot be altered, this chain of blocks
forms a **web of trust**: any engine that trusts the root block can follow the chain
forward and trust everything Kiera has vouched for, with the blockchain itself as the
tamper-evident witness.

The root block is the only thing an engine needs to bootstrap trust. From there, the
entire history of what Kiera has published and verified is auditable by anyone.

---

## Opt-In Only

Signing is not automatic. The fact that a domain serves objects over HTTPS does not mean
Kiera will sign them. The domain owner must explicitly request signing through kiera.com.
They are in charge of which objects get submitted and when.

This keeps the blockchain from becoming a free-for-all. Only objects whose owners have
deliberately chosen to participate are signed and posted.

---

## How Kiera Vouches for an Object

1. The domain owner submits their object through kiera.com
2. Kiera fetches the object from their domain over HTTPS — TLS proves it is talking to
   the real domain owner
3. Kiera signs the object with its private key
4. Kiera posts the signed object to the blockchain

When an engine needs `borg.com/foo`, it queries Kiera's API, receives the object, and
verifies Kiera's signature using the baked-in public key. If the signature is valid, the
object is trusted.

---

## The Blockchain as Registry

The blockchain serves as the permanent, decentralized registry for published objects.
Once an object is posted, it is available forever regardless of what happens to any
specific server. No single server going offline can make a published library unavailable.

This is not the only way to obtain objects — objects can also be fetched directly from
Kiera servers or other sources — but it is the highest-trust path. An object on the
blockchain was verified by Kiera at the time of posting and cannot be silently altered.

Kiera provides an API over the blockchain so engines do not need to interact with the
chain directly. The API handles lookup by UNS address and returns the signed object.

---

## The Signing Scheme

Each object is a JSON hash. To sign it:

1. Delete the `signature` field if present
2. Serialize to minified JSON, preserving insertion key order (Kiera hashes have
   significant key order — this makes serialization deterministic)
3. Sign the UTF-8 bytes using Ed25519 with Kiera's private key
4. Base64-encode the signature
5. Add a `signature` field to the hash

```json
{
    "name": "borg.com/foo",
    "fields": {"rank": "string"},
    "signature": {
        "algorithm": "Ed25519",
        "value": "base64encodedsignature..."
    }
}
```

To verify, the engine removes the `signature` field, re-serializes to minified
insertion-order JSON, and runs Ed25519 verify against that string using Kiera's public
key.

---

## Trust Tiers

| Source | Trust level |
|--------|-------------|
| Blockchain (via Kiera API) | Highest — Kiera signed it, immutable |
| Kiera server over HTTPS | High — TLS verified, but object could change |
| Other HTTPS source | Policy-dependent |
| Unsigned | Rejected |

---

## What Each Party Manages

| Party | Responsibility |
|-------|---------------|
| `borg.com` | Serve objects over HTTPS. Nothing else. |
| Kiera.uno | One private key. Fetch, sign, post to blockchain. |
| Kiera server operators | Store and serve bytes. Nothing else. |
| KScript engines | Kiera's public key baked in. Verify on fetch. |

---

## Use Case: Third-Party Endorsement

**Scenario:** ChainGuard is a security auditing company. A government contractor needs
to verify that `borg.com/parser` meets NIST 800-53 security requirements before
deploying it. ChainGuard reviews the library and posts an endorsement to the chain.

A collaboration between Kiera and ChainGuard could be a mutually beneficial arrangement.

**Step 1 — Kiera vouches for provenance.**

`borg.com` submits their library through kiera.com. Kiera fetches it over HTTPS, signs
it, and posts it to the chain.

```json
{
    "record_type": "registry_entry",
    "uns": "borg.com/parser",
    "version": 1,
    "fetched_from": "https://borg.com/parser",
    "fetched_at": "2026-05-04T09:00:00Z",
    "bucket": {
        "name": "borg.com/parser",
        "fields": {"input": "string", "output": "string"}
    },
    "signer": "kiera.uno",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "base64..."
    }
}
```

**Fabric key:** `obj:borg.com/parser:1`

This entry answers one question: *did this object really come from borg.com?* Nothing
more.

---

**Step 2 — ChainGuard establishes its identity.**

ChainGuard has its own Ed25519 key pair. It posts its own root block to the chain,
establishing its identity independently of Kiera.

```json
{
    "record_type": "root",
    "signer": "chainguard.dev",
    "public_key": {
        "algorithm": "Ed25519",
        "value": "<ChainGuard public key>"
    },
    "overview": "ChainGuard security audit registry. Entries here represent independent security assessments.",
    "created_at": "2026-05-04T10:00:00Z",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "base64..."
    }
}
```

**Fabric key:** `root:chainguard.dev`

ChainGuard does not need any permission from Kiera to do this. They join the Fabric
network as a member and post their root block. Anyone can post a root block.

---

**Step 3 — ChainGuard reviews and endorses.**

ChainGuard fetches `obj:borg.com/parser:1` from the chain, reviews the `bucket`
contents, and posts an endorsement referencing Kiera's entry by its Fabric key.
ChainGuard does not re-fetch from `borg.com` and does not re-post the source — they
are endorsing the specific object Kiera already verified.

```json
{
    "record_type": "endorsement",
    "target_key": "obj:borg.com/parser:1",
    "target_uns": "borg.com/parser",
    "target_version": 1,
    "endorser": "chainguard.dev",
    "criteria": "us-gov/nist-800-53",
    "verdict": "pass",
    "body": "Reviewed 2026-05-04. borg.com/parser meets all applicable NIST 800-53 controls for input validation and output sanitization.",
    "assessed_at": "2026-05-04T11:00:00Z",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "base64..."
    }
}
```

**Fabric key:** `endorse:chainguard.dev:obj:borg.com/parser:1`

The `target_key` is the chain of trust made explicit. ChainGuard is saying: "I reviewed
the object Kiera fetched and signed, and I vouch for it under these criteria."

---

**Step 4 — The contractor's engine checks both.**

The engine fetches `borg.com/parser`. It verifies:

1. Kiera's signature on the registry entry — provenance confirmed, object unmodified
2. ChainGuard's endorsement referencing that same entry — security criteria met

Both checks are independent. The engine trusts Kiera's public key (baked in) and
ChainGuard's public key (configured by the contractor). Neither party needed to
coordinate with the other. The shared ledger is what ties them together.

### Collaboration: Kiera Delegates to ChainGuard

Although Kiera and ChainGuard can operate completely independently, there is a deeper
collaboration available through trust delegation.

Kiera posts a trust delegation entry naming ChainGuard as a trusted fetcher:

```json
{
    "record_type": "trust_delegation",
    "delegated_by": "kiera.uno",
    "delegated_to": "chainguard.dev",
    "delegate_public_key": {
        "algorithm": "Ed25519",
        "value": "<ChainGuard public key>"
    },
    "scope": "registry_entry",
    "created_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "base64..."
    }
}
```

With this delegation in place, ChainGuard can fetch objects from domains over HTTPS
and post registry entries signed with their own key. Engines that trust Kiera's root
block follow the delegation chain and accept ChainGuard's registry entries as trusted
provenance — exactly as they would accept entries signed by Kiera directly.

This offloads the fetch-and-sign work from Kiera entirely. ChainGuard becomes an
operational partner: they fetch, they sign, they post, and they add their security
endorsement in the same pass. Kiera's role shrinks to maintaining the root block and
the delegation record.

The broader opportunity is significant. The Kiera blockchain is not limited to KScript
objects — it can store Python libraries, Go modules, or any signed artifact. A company
like ChainGuard, trusted by Kiera and trusted by governments, could position itself as
a leading authority on security-cleared open source across languages and ecosystems.
Any engine or toolchain that knows how to read the chain gains access to that trust
infrastructure with no additional setup.

### Partnership Goal

Kiera is actively seeking a partner in this space — a company analogous to ChainGuard
whose endorsements and deprecations would be surfaced directly through the
`blockchain.kiera.uno` API. When such a partnership is in place, a developer calling
the fetch endpoint would receive not just Kiera's provenance record but also the
partner's security assessment in the same response — one API call, one result,
government-grade confidence included.

This removes friction for developers who need to ship within government specifications.
They do not need to know anything about the partner's internal processes or query a
separate API. The blockchain.kiera.uno response tells them everything: where the object
came from, that it hasn't been modified, and whether it meets the security criteria they
care about.

As Stuart says, this scratches an itch.

---

## AWS Implementation

**Service: Amazon Managed Blockchain — Hyperledger Fabric**

The chain is a shared append-only ledger. Any entity — Kiera.uno, a partner org, a
company running its own internal web of trust, anyone who wants to publish signed
libraries — can join as a Fabric member and post entries. Nothing executes on the chain;
it stores signed JSON documents and nothing more. The trust model determines which
entries an engine follows; the chain itself imposes no restriction on who writes.

Hyperledger Fabric fits precisely:

- **No mining, no gas** — Fabric uses RAFT consensus. Since nothing executes on-chain,
  we need only an ordered append-only ledger, not a computation platform.
- **Open to multiple writers** — any org can join the network and post entries under
  their own identity and key. Kiera.uno is one participant, not the gatekeeper.
- **Append-only** — chaincode enforces no deletes, no updates to existing entries.
- **Fully managed** — AWS handles node provisioning, TLS, and availability.
- **Auditable** — the full ledger is readable by anyone with read access.

**Network topology:**

- One Fabric network; Kiera.uno is the founding org and orderer operator
- One orderer node (RAFT; additional orderer nodes can be added as other orgs join)
- One or two peer nodes per participating org
- One channel: `kiera-registry`
- One chaincode: `kiera-registry-cc` (handles all entry types)

Fabric channels are isolated ledgers. A single channel for all registry entries keeps
the implementation simple and allows all participants to share one auditable history.
If a participant needs a private channel (e.g., an internal-only web of trust), an
additional channel can be created later.

---

## On-Chain Data Structures

Every entry on the chain is a JSON document stored as a Fabric state entry. Each entry
type has a `record_type` field so chaincode can route queries without scanning all
entries.

### Root Block

Posted once. Establishes Kiera's identity and public key. Self-signed.

```json
{
    "record_type": "root",
    "signer": "kiera.uno",
    "public_key": {
        "algorithm": "Ed25519",
        "value": "<base64-encoded public key>"
    },
    "overview": "<Kiera ecoverse overview — content to be supplied>",
    "created_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    }
}
```

The `signature` covers all fields except itself (delete `signature`, serialize, sign).
Engines bootstrapping from this block verify the signature using the embedded public key.

**`@overview` content is pending.** The root block will include a human-readable
overview of the Kiera ecoverse in the `overview` field. That text will be supplied
before the root block is posted. Stuart should leave the placeholder above and not post
the root block until the content arrives.

**Fabric key:** `root:kiera.uno`

### Registry Entry

One entry per signed object version. Immutable once posted.

```json
{
    "record_type": "registry_entry",
    "uns": "borg.com/foo",
    "version": 1,
    "fetched_from": "https://borg.com/foo",
    "fetched_at": "<ISO 8601>",
    "bucket": {
        "name": "borg.com/foo",
        "fields": {"rank": "string"}
    },
    "signer": "kiera.uno",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    }
}
```

The `signature` covers the `bucket` field only (not the envelope). Engines that cache
the raw `bucket` can re-verify it without needing the full envelope.

**Fabric key:** `obj:<uns>:<version>` e.g. `obj:borg.com/foo:1`

The latest active version is tracked in a separate lightweight index entry:

```json
{
    "record_type": "uns_head",
    "uns": "borg.com/foo",
    "latest_version": 3,
    "active_version": 3,
    "updated_at": "<ISO 8601>"
}
```

**Fabric key:** `head:<uns>`

### Trust Delegation

Posted by a trusted signer to extend trust to another entity.

```json
{
    "record_type": "trust_delegation",
    "delegated_by": "kiera.uno",
    "delegated_to": "partner.org",
    "delegate_public_key": {
        "algorithm": "Ed25519",
        "value": "<base64-encoded public key>"
    },
    "scope": "all",
    "created_at": "<ISO 8601>",
    "expires_at": null,
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    }
}
```

`scope` may be `"all"` or a UNS prefix like `"partner.org/"` to restrict what the
delegate may sign.

**Fabric key:** `trust:<delegated_by>:<delegated_to>`

### Revocation

Marks a specific version of an object as untrusted. Does not delete it.

```json
{
    "record_type": "revocation",
    "target_uns": "borg.com/foo",
    "target_version": 1,
    "reason": "object content was incorrect at time of signing",
    "revoked_at": "<ISO 8601>",
    "revoked_by": "kiera.uno",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    }
}
```

When a revocation exists for the active version, the `uns_head` entry's `active_version`
is updated to point to the most recent non-revoked version (or null if all versions are
revoked). Engines receiving a revoked object from cache must re-fetch.

**Fabric key:** `revoke:<uns>:<version>`

### Endorsement

A third-party assessment of a specific registry entry. Posted by any entity that has
established its own identity on the chain. Does not require any involvement from Kiera.

```json
{
    "record_type": "endorsement",
    "target_key": "obj:borg.com/parser:1",
    "target_uns": "borg.com/parser",
    "target_version": 1,
    "endorser": "chainguard.dev",
    "criteria": "us-gov/nist-800-53",
    "verdict": "pass",
    "body": "Reviewed 2026-05-04. Meets all applicable NIST 800-53 controls.",
    "assessed_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "<base64-encoded signature>"
    }
}
```

`target_key` is the Fabric key of the registry entry being endorsed. `criteria` is a
namespaced identifier for the standard or ruleset applied. `verdict` is `"pass"` or
`"fail"` — a fail endorsement is still useful as a published record of a negative
assessment.

The signature is verified against the endorser's public key, found in their own root
block on the chain. Kiera's key plays no role.

**Fabric key:** `endorse:<endorser>:<target_key>`

### Deprecation

A security or quality warning posted by any entity against one or more versions of an
object. Unlike revocation, deprecation is a third-party assessment — it does not require
Kiera's involvement and does not affect the integrity of the original entry. The
deprecated object remains on the chain; consumers decide how to respond.

Deprecation targets are expressed using the same tombstone/birthstone model as version
requests. Three targeting modes:

**Single version** — deprecate one specific entry:

```json
{
    "record_type": "deprecation",
    "target_uns": "borg.com/parser",
    "target_version": 3,
    "posted_by": "chainguard.dev",
    "notes": {},
    "posted_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "<base64-encoded signature>"
    }
}
```

**Bounded time span** — deprecate all versions within a date range:

```json
{
    "record_type": "deprecation",
    "target_uns": "borg.com/parser",
    "target_birthstone": "2024-01-01T00:00:00Z",
    "target_tombstone": "2025-03-01T00:00:00Z",
    "posted_by": "chainguard.dev",
    "notes": {},
    "posted_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "<base64-encoded signature>"
    }
}
```

**Open deprecation** — deprecate all versions up to (or from) an open-ended boundary.
Omit `target_tombstone` to deprecate everything before a date with no upper bound, or
omit `target_birthstone` to deprecate everything from a date forward:

```json
{
    "record_type": "deprecation",
    "target_uns": "borg.com/parser",
    "target_tombstone": "2025-06-01T00:00:00Z",
    "posted_by": "chainguard.dev",
    "notes": {},
    "posted_at": "<ISO 8601>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "chainguard.dev",
        "value": "<base64-encoded signature>"
    }
}
```

The `notes` field structure is TBD. It will carry human-readable and structured
information about the deprecation — CVE references, severity, remediation guidance, etc.

When the gateway resolves a version and finds a deprecation covering that version from a
trusted source, it includes the deprecation in the response. Whether to treat the
deprecation as a hard error or a warning is a consumer-side decision.

**Fabric key:** `deprecate:<posted_by>:<target_uns>:<uuid>` — a UUID suffix allows
multiple deprecations from the same poster against the same UNS.

---

## The Kiera Blockchain Gateway

**All blockchain services are hosted at `blockchain.kiera.uno`.**

**The Kiera Lua library does not include routines for querying the blockchain directly.**
By default it operates through the API at `blockchain.kiera.uno`. That API is not yet
fully specified. The endpoints below describe the intended shape; the final API spec will
be a separate document.

Engines do not interact with Fabric directly. They call the Kiera API. The gateway runs
as a set of AWS Lambda functions behind API Gateway.

### Submit (domain owner → Kiera)

`POST https://blockchain.kiera.uno/v1/submit`

Domain owner submits a UNS address. Kiera fetches, signs, and posts.

**This endpoint is idempotent.** If Kiera fetches the object and finds it identical to
the most recently signed version, it returns the existing signed entry rather than
posting a new one. The response is the same either way — the caller does not need to
know or care whether a new entry was posted. The mechanism for deduplication (how Kiera
determines "identical") is to be specified.

Request:
```json
{
    "uns": "borg.com/foo",
    "fetch_url": "https://borg.com/foo",
    "owner_contact": "ops@borg.com"
}
```

Response (success, whether newly posted or already exists):
```json
{
    "status": "posted",
    "uns": "borg.com/foo",
    "version": 2,
    "fabric_tx_id": "<Fabric transaction ID>",
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    }
}
```

### Fetch (engine → Kiera)

`GET https://blockchain.kiera.uno/v1/object/<uns>`

Returns the latest active signed object for a UNS address. The engine verifies the
signature client-side using the baked-in public key.

Response:
```json
{
    "uns": "borg.com/foo",
    "version": 2,
    "bucket": {"name": "borg.com/foo", "fields": {"rank": "string"}},
    "signature": {
        "algorithm": "Ed25519",
        "signer": "kiera.uno",
        "value": "<base64-encoded signature>"
    },
    "fetched_at": "<ISO 8601>",
    "revoked": false
}
```

`GET https://blockchain.kiera.uno/v1/object/<uns>/<version>` fetches a specific version.

### Revocation check

`GET https://blockchain.kiera.uno/v1/revocation/<uns>/<version>`

Returns `{"revoked": false}` or `{"revoked": true, "revoked_at": "..."}`. Engines can
poll this to detect newly revoked cached objects.

### Root block

`GET https://blockchain.kiera.uno/v1/root`

Returns the root block. Used during engine setup to verify the baked-in public key
matches the chain.

---

## Chaincode Design

The Fabric chaincode (`kiera-registry-cc`) exposes four functions:

**`PostEntry(entry_json)`** — validate the record type, verify the signature against
the known signer's public key (looked up from a prior `trust_delegation` or the root
block), write to the ledger. For `registry_entry`, also upsert the `uns_head` index.

**`GetEntry(key)`** — return a ledger entry by Fabric key.

**`GetHead(uns)`** — return the `uns_head` entry for a UNS address.

**`GetRevocation(uns, version)`** — return a revocation entry if one exists.

The chaincode does not enforce anything about Kiera's business logic (fetch-from-HTTPS,
opt-in, etc.) — that is the gateway's job. The chaincode enforces structural integrity:
valid JSON, required fields present, valid signature, no overwrites of immutable entries.

---

## Implementation Phases

**Phase 1 — Network and chaincode**

1. Provision Managed Blockchain network (`kiera-uno` org, RAFT orderer, one peer)
2. Create `kiera-registry` channel
3. Write and deploy `kiera-registry-cc` chaincode
4. Write integration tests: post root block, post a registry entry, fetch it back,
   post a revocation, verify revocation is returned

**Phase 2 — Key management**

1. Generate Ed25519 key pair for Kiera.uno
2. Store private key in AWS Secrets Manager (never in code, never in env vars)
3. Post root block to the chain
4. Document the public key — this is what will be baked into engines

**Phase 3 — Gateway API**

1. Lambda: `submit` — fetch from HTTPS, sign, call `PostEntry`
2. Lambda: `fetch` — call `GetHead` then `GetEntry`, return signed object
3. Lambda: `revocation_check` — call `GetRevocation`
4. Lambda: `root` — call `GetEntry("root:kiera.uno")`
5. Wire all four to API Gateway
6. Add API key auth on `submit` (domain owners authenticate; engine reads are open)

**Phase 4 — Engine integration**

1. Bake Kiera's public key into the KScript engine
2. Implement fetch-from-Kiera-API with signature verification
3. Implement cache invalidation on revocation (periodic poll or webhook)
4. Test end-to-end: submit object, engine fetches, engine verifies

**Phase 5 — Trust delegation (deferred)**

Trust delegation is architecturally specified above but not needed for the initial
launch. Implement when there is a concrete delegatee.

---

## Versioning

Every object published on the Kiera blockchain carries a timestamp. The timestamp is
not set by the submitter — it is the block timestamp assigned by the Fabric orderer
when the entry is committed. This makes timestamps canonical and tamper-evident.

**Default behaviour: latest within range.** When you request an object with no version
constraint, you get the most recently posted version. When you request with a date
range, you get the most recently posted version that falls within that range.

### Tombstone and Birthstone

A **tombstone** is an upper bound on the timestamp: "give me the latest version of this
object on or before this date." Setting a tombstone pins the entire resolution to a
point in time — useful for reproducible builds or auditing what was deployed on a given
date.

A **birthstone** is a lower bound: "do not give me anything older than this date."
Useful for excluding objects published before a known-good baseline, such as a security
audit date.

Either, both, or neither can be set. With neither, you get the latest version of
everything.

```json
{
    "uns": "borg.com/parser",
    "tombstone": "2025-06-01T00:00:00Z",
    "birthstone": "2024-01-01T00:00:00Z"
}
```

### Dependency Resolution

Each object may declare its own dependencies — by UNS name — along with an optional
date range per dependency. When the gateway resolves a request, it traverses the
dependency graph and applies the outer request range at every node.

If an object declares a narrower range for one of its dependencies, the system
intersects that range with the outer range. The narrower of the two wins. If the
intersection is empty — no version of the dependency exists within both ranges — an
exception is raised. The resolution fails rather than silently selecting something
outside the intended range.

Example: the outer request has a tombstone of 2025-06-01. Object A declares that it
depends on `borg.com/utils` with a tombstone of 2025-01-01. The effective tombstone
for `borg.com/utils` is 2025-01-01 — A's constraint is tighter and takes precedence.
If `borg.com/utils` has no version on or before 2025-01-01, the resolution fails.

Dependency declarations live inside the object's `bucket`. The gateway reads the
`bucket` at each node to discover dependencies, then recurses. Dependency graphs
for libraries are finite; resolution terminates.

### Relationship to Semantic Versioning

Timestamp-based versioning handles the common case — pin a date, get a reproducible
dependency tree — with no coordination required between publishers. Semantic versioning
is available as an additional layer for publishers who need to express compatibility
constraints (e.g. "requires borg.com/utils >= 2.0.0"). The two systems can be combined:
a semver constraint narrows which versions are candidates; the timestamp range selects
the latest candidate within that set.

---

## Design Notes

**Ed25519 is the right choice.** 64-byte signatures, fast verification, no parameter
choices that can be misconfigured, widely supported in every language runtime Kiera is
likely to encounter. No reason to prefer anything else for this use case.

**Insertion-order canonical JSON.** RFC 8785 (JCS) sorts keys alphabetically, which
breaks Kiera's key-order semantics. The solution is to document that signing always
uses insertion-order minified JSON, and require that all Kiera tooling preserves key
order when serializing. Engines sign and verify using the same serializer — as long as
the serializer is consistent, verification is reliable. This is non-standard but
self-consistent.

**Versioning.** Each new submission creates a new `registry_entry` with an incremented
version. The `uns_head` index tracks the current active version. This is standard
immutable-log versioning — no prior art needed. Engines should store both UNS and
version in their cache so they know which entry to check for revocations.

**Revocation and caching.** A revoked object in cache should be re-fetched immediately.
The recommended strategy: on any object use, check the revocation endpoint with a
short-lived local TTL (e.g., 5 minutes). If revoked, discard cache and re-fetch. A
future webhook push model (Kiera notifies subscribed engines) can replace polling once
the network grows.

**Fabric over QLDB.** Amazon QLDB (append-only ledger database, also AWS-managed) was
an alternative, but AWS ended support for QLDB in July 2025. Hyperledger Fabric on
Amazon Managed Blockchain is the current AWS-recommended path for append-only
verifiable ledgers.
