# Object Signing and the Blockchain Registry

## Status

Blockchain is an official part of the Kiera ecoverse. The details of this design are
still being worked out. This document is a proposal being sent to Stuart for review.

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

## Open Questions for Stuart

- **Ed25519 the right choice?** Modern, fast, 64-byte signatures, widely supported. Any
  reason to prefer something else?

- **Which blockchain?** Needs to store small JSON objects (KScript classes are compact),
  support lookup by a string key (UNS address), and be durable long-term. What fits
  best?

- **Data structure on the chain** — does each object get its own transaction, or are
  they batched? How is the UNS-to-object index maintained efficiently?

- **Versioning** — blockchain entries are immutable, so updates are new entries.
  `borg.com/foo@2` is separate from `borg.com/foo@1`. Is there prior art for versioned
  immutable registries on a blockchain?

- **Deterministic JSON serialization** — the scheme requires deterministic JSON. RFC 8785
  (JCS) sorts keys alphabetically, but Kiera hashes have significant insertion order so
  we cannot sort. Is there known prior art for insertion-order canonical JSON signing?

- **Revocation** — if a bad object was posted, how is it revoked? Since the blockchain
  is immutable, revocation must be a new entry. How should engines handle a revoked
  object they already cached?
