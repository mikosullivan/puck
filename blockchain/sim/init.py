#!/usr/bin/env python3
"""Initialize the Kiera blockchain simulation.

Creates chain.db, generates a key pair, and posts the grammar and authority blocks.
"""
import base64, hashlib, json, sqlite3, sys
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding, NoEncryption, PrivateFormat, PublicFormat, load_pem_private_key
)

SIMDIR = Path(__file__).parent
DB_PATH = SIMDIR / "chain.db"
KEY_PATH = SIMDIR / "private.pem"
PUB_PATH = SIMDIR / "public.pem"
SIGNER = "kiera.uno"


def sorted_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'))


def sha256_hex(s):
    return hashlib.sha256(s.encode()).hexdigest()


def load_or_create_key():
    if KEY_PATH.exists():
        return load_pem_private_key(KEY_PATH.read_bytes(), password=None)
    key = Ed25519PrivateKey.generate()
    KEY_PATH.write_bytes(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    PUB_PATH.write_bytes(key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    print("Generated key pair.")
    return key


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


def main():
    if DB_PATH.exists():
        print("chain.db already exists. Delete it first to reinitialize.")
        sys.exit(1)

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

    key = load_or_create_key()
    pub_pem = key.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()

    grammar_payload = {
        "description": "Kiera blockchain block grammar version 1.0",
        "envelope": {
            "fields": ["intent", "prev_hash", "posted", "signer", "payload", "signature"],
            "required": ["intent", "prev_hash", "posted", "signer", "payload", "signature"]
        },
        "grammar": {"hash": "self", "version": "1.0"},
        "intent": "grammar",
        "intent_values": ["authority", "grammar", "register", "endorse", "delegate", "deprecate", "revoke"],
        "payload_common": {
            "encouraged": ["vibecode"],
            "fields": ["intent", "grammar", "vibecode"],
            "notes": "grammar is {hash, version}; use hash:self for the grammar block itself",
            "required": ["intent", "grammar"]
        },
        "scope_values": [
            "provenance", "license-verified",
            "security:fedramp-moderate", "security:fedramp-high", "security:fips-140-2", "audit"
        ],
        "version": "1.0",
        "vibecode": {"intent": "grammar", "signer": "kiera.uno", "version": "1.0"}
    }
    grammar_hash = sign_and_insert(db, key, "grammar", SIGNER, grammar_payload)
    print(f"grammar    -> {grammar_hash}")

    authority_payload = {
        "grammar": {"hash": grammar_hash, "version": "1.0"},
        "intent": "authority",
        "kiera_primer": (
            "Kiera is a distributed object system. Objects are identified by UNS addresses "
            "(domain/path format, e.g. borg.com/parser). Classes define typed fields and callable "
            "methods. Any domain can publish objects over HTTPS. The Kiera blockchain provides "
            "immutable signed provenance records. Ed25519 signatures, SHA-256 hash chaining. "
            "No mining, no gas. MIT licensed."
        ),
        "note": "Kiera.uno root authority block",
        "public_key": pub_pem,
        "vibecode": {
            "ecoverse": "kiera",
            "entity": "kiera.uno",
            "intent": "authority",
            "role": "root-authority",
            "verification": "blockchain.kiera.uno"
        }
    }
    authority_hash = sign_and_insert(db, key, "authority", SIGNER, authority_payload)
    print(f"authority  -> {authority_hash}")

    print(f"\nDone. Grammar hash: {grammar_hash}")


if __name__ == "__main__":
    main()
