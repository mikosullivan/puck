#!/usr/bin/env python3
"""Rebuild the Kiera blockchain simulation from scratch.

Deletes chain.db and reposts all blocks using grammar v1.0 intent values.
Writes blockchain.json when done.
"""

import base64, hashlib, json, sqlite3
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding, NoEncryption, PrivateFormat, PublicFormat, load_pem_private_key
)

SIMDIR = Path(__file__).parent
DB_PATH = SIMDIR / "chain.db"
KIERA_KEY_PATH = SIMDIR / "private.pem"
KIERA_PUB_PATH = SIMDIR / "public.pem"
HORATIUS_KEY_PATH = SIMDIR / "horatius_private.pem"
HORATIUS_PUB_PATH = SIMDIR / "horatius_public.pem"
FUDDLE_KEY_PATH = SIMDIR / "fuddle_private.pem"
FUDDLE_PUB_PATH = SIMDIR / "fuddle_public.pem"
TODAY = datetime.now(timezone.utc).strftime('%Y-%m-%d')


def sorted_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


def sha256_hex(s):
    return hashlib.sha256(s.encode()).hexdigest()


def load_or_create_key(key_path, pub_path, label):
    if key_path.exists():
        return load_pem_private_key(key_path.read_bytes(), password=None)
    key = Ed25519PrivateKey.generate()
    key_path.write_bytes(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    pub_path.write_bytes(key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    print(f"  Generated {label} key pair.")
    return key


def front_key(obj, key):
    """Recursively reorder dicts so `key` comes first wherever it appears."""
    if isinstance(obj, list):
        return [front_key(item, key) for item in obj]
    if isinstance(obj, dict):
        reordered = {k: front_key(v, key) for k, v in obj.items()}
        if key in reordered:
            return {key: reordered[key], **{k: v for k, v in reordered.items() if k != key}}
        return reordered
    return obj


def sign_and_insert(db, key, intent, signer, payload):
    row = db.execute("SELECT record_hash FROM records ORDER BY id DESC LIMIT 1").fetchone()
    prev_hash = row[0] if row else None
    posted = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    to_sign = {"intent": intent, "payload": payload, "posted": posted,
               "prev_hash": prev_hash, "signer": signer}
    sig = base64.b64encode(key.sign(sorted_json(to_sign).encode())).decode()

    full = {"intent": intent, "payload": payload, "posted": posted,
            "prev_hash": prev_hash, "signature": sig, "signer": signer}
    record_hash = sha256_hex(sorted_json(full))

    db.execute(
        "INSERT INTO records (intent, prev_hash, posted, signer, payload, signature, record_hash)"
        " VALUES (?,?,?,?,?,?,?)",
        (intent, prev_hash, posted, signer, sorted_json(payload), sig, record_hash)
    )
    db.commit()
    return record_hash


def post(db, key, intent, signer, payload, label=None):
    h = sign_and_insert(db, key, intent, signer, payload)
    tag = label or f"{intent}/{signer}"
    print(f"  {tag:<42} -> {h}")
    return h



KIERA_PRIMER = (
    "Kiera is a distributed object system. Objects are identified by UNS addresses "
    "(domain/path format, e.g. borg.com/parser). Classes define typed fields and callable "
    "methods. Any domain can publish objects over HTTPS. The Kiera blockchain provides "
    "immutable signed provenance records. Ed25519 signatures, SHA-256 hash chaining. "
    "No mining, no gas. MIT licensed."
)

PACKAGES = [
    {
        "uns": "borg.com/parser", "version": "2.1.0", "license": "MIT",
        "description": "Parses structured text into a normalised output hash.",
        "tags": {"kiera.uno/tag/kscript-library": True, "kiera.uno/tag/parser": True},
        "artifact_hash": "sha256:8f2a3b7d1e9c4a5f6b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a",
        "artifact_url": "https://borg.com/parser/2.1.0.kscript",
    },
    {
        "uns": "syntex.io/validator", "version": "1.4.2", "license": "Apache-2.0",
        "description": "Validates JSON documents against a Kiera schema object.",
        "tags": {"kiera.uno/tag/kscript-library": True, "kiera.uno/tag/validation": True},
        "artifact_hash": "sha256:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b",
        "artifact_url": "https://syntex.io/validator/1.4.2.kscript",
    },
    {
        "uns": "netbridge.dev/http-client", "version": "3.0.1", "license": "MIT",
        "description": "Async HTTP client with retry, timeout, and TLS support.",
        "tags": {"kiera.uno/tag/http": True, "kiera.uno/tag/kscript-library": True, "kiera.uno/tag/networking": True},
        "artifact_hash": "sha256:2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d",
        "artifact_url": "https://netbridge.dev/http-client/3.0.1.kscript",
    },
    {
        "uns": "quanta.systems/crypto", "version": "2.0.0", "license": "Apache-2.0",
        "description": "Ed25519 signing, AES-256-GCM encryption, and SHA-2 hashing primitives.",
        "tags": {"kiera.uno/tag/cryptography": True, "kiera.uno/tag/kscript-library": True, "kiera.uno/tag/security": True},
        "artifact_hash": "sha256:3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e",
        "artifact_url": "https://quanta.systems/crypto/2.0.0.kscript",
    },
    {
        "uns": "meridian.tech/logger", "version": "1.1.0", "license": "MIT",
        "description": "Structured JSON logger with configurable levels, sinks, and redaction rules.",
        "tags": {"kiera.uno/tag/kscript-library": True, "kiera.uno/tag/logging": True, "kiera.uno/tag/observability": True},
        "artifact_hash": "sha256:4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f",
        "artifact_url": "https://meridian.tech/logger/1.1.0.kscript",
    },
]


def main():
    DB_PATH.unlink(missing_ok=True)

    db = sqlite3.connect(DB_PATH)
    db.execute("""
        CREATE TABLE records (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            intent       TEXT NOT NULL,
            prev_hash    TEXT,
            posted       TEXT NOT NULL,
            signer       TEXT NOT NULL,
            payload      TEXT NOT NULL,
            signature    TEXT NOT NULL,
            record_hash  TEXT NOT NULL UNIQUE
        )
    """)

    print("Keys:")
    kiera_key = load_or_create_key(KIERA_KEY_PATH, KIERA_PUB_PATH, "kiera.uno")
    horatius_key = load_or_create_key(HORATIUS_KEY_PATH, HORATIUS_PUB_PATH, "horatius.com")
    fuddle_key = load_or_create_key(FUDDLE_KEY_PATH, FUDDLE_PUB_PATH, "fuddle.com")
    kiera_pub = kiera_key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()
    horatius_pub = horatius_key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()
    fuddle_pub = fuddle_key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()

    print("\nBlocks:")

    # 1. Grammar
    grammar_hash = post(db, kiera_key, "grammar", "kiera.uno", {
        "notes": "Defines the Kiera blockchain block grammar version 1.0. All subsequent blocks reference this block by hash.",
        "tags": {"kiera.uno/tag/core": True, "kiera.uno/tag/grammar": True},
        "description": "Kiera blockchain block grammar version 1.0",
        "envelope": {
            "fields": ["intent", "prev_hash", "posted", "signer", "payload", "signature"],
            "required": ["intent", "prev_hash", "posted", "signer", "payload", "signature"]
        },
        "grammar": {"hash": "self", "version": "1.0"},
        "intent": "grammar",
        "intent_values": ["authority", "grammar", "endorse", "mirror", "delegate", "deprecate", "revoke"],
        "payload_common": {
            "encouraged": ["vibecode"],
            "fields": ["intent", "grammar", "vibecode"],
            "notes": "grammar is {hash, version}; use hash:self for the grammar block itself",
            "required": ["intent", "grammar"]
        },
        "endorsement_values": [
            "canonical", "provenance", "license-verified", "security", "audit"
        ],
        "version": "1.0",
        "vibecode": {"intent": "grammar", "signer": "kiera.uno", "version": "1.0"}
    }, label="grammar/kiera.uno")

    # 2. Kiera authority
    post(db, kiera_key, "authority", "kiera.uno", {
        "notes": "Kiera.uno root authority block. Establishes the signing key for all Kiera-signed records.",
        "tags": {"kiera.uno/tag/authority": True, "kiera.uno/tag/root": True},
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "authority",
        "kiera_primer": KIERA_PRIMER,
        "public_key": kiera_pub,
        "vibecode": {
            "ecoverse": "kiera",
            "entity": "kiera.uno",
            "intent": "authority",
            "role": "root-authority",
            "verification": "blockchain.kiera.uno"
        }
    }, label="authority/kiera.uno")

    # 3. Kiera endorsement of grammar block
    post(db, kiera_key, "endorse", "kiera.uno", {
        "notes": "Kiera.uno endorses the grammar block as both its author (provenance) and as the canonical grammar for the chain.",
        "tags": {"kiera.uno/tag/core": True, "kiera.uno/tag/endorse": True},
        "endorsements": [
            {"endorsement": "provenance", "notes": "kiera.uno authored and published this grammar"},
            {"endorsement": "canonical", "notes": "this is the authoritative grammar for the Kiera blockchain"}
        ],
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "endorse",
        "target_hash": grammar_hash,
        "vibecode": {"intent": "endorse", "signer": "kiera.uno", "target_hash": grammar_hash}
    }, label="endorse/grammar")

    # 4. Horatius authority
    horatius_auth_hash = post(db, horatius_key, "authority", "horatius.com", {
        "notes": "Horatius Security root authority block — establishes signing authority for federal compliance endorsements on the Kiera blockchain.",
        "tags": {"fedramp.gov/authorized": True, "kiera.uno/tag/authority": True, "kiera.uno/tag/security-auditor": True},
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "authority",
        "kiera_primer": KIERA_PRIMER,
        "public_key": horatius_pub,
        "vibecode": {
            "contact": "horatius.com",
            "description": "Horatius Security — independent auditor for US federal government compliance",
            "ecoverse": "kiera",
            "entity": "horatius.com",
            "intent": "authority",
            "role": "security-auditor",
            "standards": ["fedramp-moderate", "fedramp-high", "fips-140-2"],
            "trust": "all Horatius endorsements are signed with this key",
            "verification": "blockchain.kiera.uno"
        }
    }, label="authority/horatius.com")

    # 5. Kiera delegates provenance trust to Horatius
    post(db, kiera_key, "delegate", "kiera.uno", {
        "notes": "Kiera endorses Horatius provenance claims only. Security ratings are not covered by this delegation.",
        "tags": {"kiera.uno/tag/delegation": True, "kiera.uno/tag/provenance": True},
        "endorsements": ["provenance"],
        "entity": "horatius.com",
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "delegate",
        "target_hash": horatius_auth_hash,
        "vibecode": {
            "endorsements": ["provenance"],
            "entity": "horatius.com",
            "intent": "delegate",
            "target_hash": horatius_auth_hash
        }
    }, label="delegate/horatius.com")

    # 6. Kiera delegates deprecation authority to Horatius
    post(db, kiera_key, "delegate", "kiera.uno", {
        "notes": "Kiera endorses all deprecations posted by Horatius.",
        "tags": {"kiera.uno/tag/delegation": True, "kiera.uno/tag/deprecation": True},
        "entity": "horatius.com",
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "delegate",
        "intents": ["deprecate"],
        "target_hash": horatius_auth_hash,
        "vibecode": {
            "entity": "horatius.com",
            "intent": "delegate",
            "intents": ["deprecate"],
            "target_hash": horatius_auth_hash
        }
    }, label="delegate/horatius.com/deprecations")

    # 7-11. Provenance endorsements (artifact lives off-chain; chain stores hash + URL)
    for pkg in PACKAGES:
        post(db, kiera_key, "endorse", "kiera.uno", {
            "notes": f"Kiera.uno posts provenance for {pkg['uns']} version {pkg['version']}.",
            "tags": pkg["tags"],
            "effective_date": TODAY,
            "endorsements": [
                {
                    "endorsement": "provenance",
                    "class": "kiera.uno/class",
                    "description": pkg["description"],
                    "artifact_hash": pkg["artifact_hash"],
                    "artifact_url": pkg["artifact_url"],
                    "language": "kiera.uno/software/kscript",
                    "license": pkg["license"],
                    "name": pkg["uns"],
                    "version": pkg["version"]
                }
            ],
            "grammar": {"hash": grammar_hash, "version": "1.0"},
            "intent": "endorse",
            "target_hash": "self",
            "uns": pkg["uns"],
            "version": pkg["version"],
            "vibecode": {
                "intent": "endorse",
                "license": pkg["license"],
                "endorsement": "provenance",
                "signer": "kiera.uno",
                "uns": pkg["uns"],
                "version": pkg["version"]
            }
        }, label=f"endorse/{pkg['uns']}")

    # 10. Horatius: bottle provenance + security endorsement
    post(db, horatius_key, "endorse", "horatius.com", {
        "notes": "Horatius posts provenance and FedRAMP Moderate security endorsement for bottle 0.13.2.",
        "tags": {"fedramp.gov/moderate": True, "kiera.uno/tag/python-package": True, "kiera.uno/tag/web-framework": True},
        "effective_date": TODAY,
        "endorsements": [
            {
                "endorsement": "provenance",
                "artifact_hash": "sha256:e3b0c44298fc1c149afb4c8996fb92427ae41e4649b934ca495991b7852b855",
                "artifact_url": "https://github.com/bottlepy/bottle/archive/refs/tags/0.13.2.tar.gz",
                "description": "Fast, simple and lightweight WSGI micro web-framework for Python.",
                "language": "kiera.uno/software/python",
                "license": "MIT",
                "name": "github.com/bottlepy/bottle",
                "version": "0.13.2"
            },
            {
                "endorsement": "security",
                "notes": "Reviewed 2026-05-07. bottle 0.13.2 meets FedRAMP Moderate requirements for input validation, session management, and output encoding. No known CVEs present in this version.",
                "security": {"fedramp-moderate": True}
            }
        ],
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "endorse",
        "target_hash": "self",
        "uns": "github.com/bottlepy/bottle",
        "version": "0.13.2",
        "vibecode": {
            "intent": "endorse",
            "license": "MIT",
            "signer": "horatius.com",
            "uns": "github.com/bottlepy/bottle",
            "version": "0.13.2"
        }
    }, label="endorse/github.com/bottlepy/bottle")

    # 12. Fuddle authority
    fuddle_auth_hash = post(db, fuddle_key, "authority", "fuddle.com", {
        "notes": "Fuddle.com root authority block.",
        "tags": {"kiera.uno/tag/authority": True},
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "authority",
        "kiera_primer": KIERA_PRIMER,
        "public_key": fuddle_pub,
        "vibecode": {
            "ecoverse": "kiera",
            "entity": "fuddle.com",
            "intent": "authority",
            "role": "publisher",
            "verification": "blockchain.kiera.uno"
        }
    }, label="authority/fuddle.com")

    # 13. Fuddle posts code
    post(db, fuddle_key, "endorse", "fuddle.com", {
        "notes": "Fuddle.com posts provenance for fuddle.com/cache version 1.0.0.",
        "tags": {"kiera.uno/tag/cache": True, "kiera.uno/tag/kscript-library": True},
        "effective_date": TODAY,
        "endorsements": [
            {
                "endorsement": "provenance",
                "class": "kiera.uno/class",
                "description": "Fast in-memory key-value cache with TTL and LRU eviction.",
                "artifact_hash": "sha256:5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a",
                "artifact_url": "https://fuddle.com/cache/1.0.0.kscript",
                "language": "kiera.uno/software/kscript",
                "license": "MIT",
                "name": "fuddle.com/cache",
                "version": "1.0.0"
            }
        ],
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "endorse",
        "target_hash": "self",
        "uns": "fuddle.com/cache",
        "version": "1.0.0",
        "vibecode": {
            "endorsement": "provenance",
            "intent": "endorse",
            "license": "MIT",
            "signer": "fuddle.com",
            "uns": "fuddle.com/cache",
            "version": "1.0.0"
        }
    }, label="endorse/fuddle.com/cache")

    # 14. Horatius deprecates all fuddle.com blocks
    post(db, horatius_key, "deprecate", "horatius.com", {
        "notes": "Horatius deprecates all blocks from fuddle.com following discovery of malicious code in published packages.",
        "tags": {"kiera.uno/tag/deprecation": True, "kiera.uno/tag/security-risk": True},
        "endorsements": "*",
        "entity": "fuddle.com",
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "deprecate",
        "reason": "fuddle.com packages found to contain malicious code. All blocks from this authority are deprecated.",
        "target_hash": fuddle_auth_hash,
        "vibecode": {
            "endorsements": "*",
            "entity": "fuddle.com",
            "intent": "deprecate",
            "target_hash": fuddle_auth_hash
        }
    }, label="deprecate/fuddle.com")

    # Write blockchain.json
    rows = db.execute(
        "SELECT id, intent, prev_hash, posted, signer, payload, signature, record_hash"
        " FROM records ORDER BY id"
    ).fetchall()
    chain = []
    for r in rows:
        payload = front_key(front_key(json.loads(r[5]), "notes"), "endorsement")
        notes = payload.pop("notes", None)
        record = {"id": r[0]}
        if notes:
            record["notes"] = notes
        record["intent"]      = r[1]
        record["prev_hash"]   = r[2]
        record["posted"]      = r[3]
        record["signer"]      = r[4]
        record["payload"]     = payload
        record["signature"]   = r[6]
        record["record_hash"] = r[7]
        chain.append(record)
    out_path = SIMDIR.parent / "blockchain.json"
    out_path.write_text(json.dumps(chain, indent=2))
    print(f"\nWrote {out_path} ({len(chain)} records, {out_path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
