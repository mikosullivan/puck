#!/bin/sh
# Post the grammar v1.0 block to Falstaff.
# Signs with the Ed25519 key at /data/private.pem using openssl CLI.
set -e

DB=/data/falstaff.db
KEY=/data/private.pem

PREV=$(sqlite3 "$DB" "SELECT record_hash FROM records ORDER BY id DESC LIMIT 1")
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Payload — keys in sorted order (recursively) to match util.sorted_json.
PAYLOAD='{"block_types":["root","grammar","registry_entry","endorsement","deprecation","revocation","delegation"],"description":"Kiera blockchain block grammar version 1.0","envelope":{"fields":["type","prev_hash","ts","signer","payload","signature"],"required":["type","prev_hash","ts","signer","payload","signature"]},"grammar":{"hash":"self","version":"1.0"},"inherits":null,"intent":"define-grammar","intent_values":["establish-authority","endorse","delegate","define-grammar"],"payload_common":{"encouraged":["vibecode"],"fields":["intent","grammar","vibecode"],"notes":"grammar is {hash, version}; use hash:self for the grammar block itself","required":["intent","grammar"]},"scope_values":["provenance","license-verified","security:fedramp-moderate","security:fedramp-high","security:fips-140-2","audit"],"version":"1.0","vibecode":{"description":"Kiera blockchain block grammar version 1.0","signer":"falstaff","type":"grammar","version":"1.0"}}'

# Record to sign — fields sorted: payload, prev_hash, signer, ts, type.
TO_SIGN='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signer":"falstaff","ts":"'"$TS"'","type":"grammar"}'

# Sign with Ed25519 (write to temp file — openssl pkeyutl needs seekable input).
printf '%s' "$TO_SIGN" > /tmp/fs_to_sign.dat
SIG=$(openssl pkeyutl -sign -inkey "$KEY" -rawin -in /tmp/fs_to_sign.dat | base64 -w0)
rm -f /tmp/fs_to_sign.dat
if [ -z "$SIG" ]; then echo "Signing failed"; exit 1; fi

# Full record for hashing — fields sorted: payload, prev_hash, signature, signer, ts, type.
FULL='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signature":"'"$SIG"'","signer":"falstaff","ts":"'"$TS"'","type":"grammar"}'

printf '%s' "$FULL" > /tmp/fs_to_hash.dat
HASH=$(openssl dgst -sha256 -r /tmp/fs_to_hash.dat | cut -d' ' -f1)
rm -f /tmp/fs_to_hash.dat

sqlite3 "$DB" "INSERT INTO records (type, prev_hash, ts, signer, payload, signature, record_hash)
  VALUES ('grammar', '$PREV', '$TS', 'falstaff', '$PAYLOAD', '$SIG', '$HASH')"

echo "Grammar block posted."
echo "record_hash: $HASH"
