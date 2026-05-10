#!/bin/sh
# Post Horatius root authority block to Falstaff.
set -e

DB=/data/falstaff.db
GRAMMAR_HASH="c2c018a5a1bf2d6e0748ec73f9ea45901fdb5e587838a532d3f37e36f620da4f"

# Generate Horatius key pair if not already present.
if [ ! -f /data/horatius_private.pem ]; then
    openssl genpkey -algorithm Ed25519 -out /data/horatius_private.pem 2>/dev/null
    openssl pkey -in /data/horatius_private.pem -pubout -out /data/horatius_public.pem 2>/dev/null
    echo "Generated Horatius key pair."
fi

# Public key as a JSON string (actual newlines → literal \n).
PUB_JSON=$(awk '{printf "%s\\n", $0}' /data/horatius_public.pem)

PREV=$(sqlite3 "$DB" "SELECT record_hash FROM records ORDER BY id DESC LIMIT 1")
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Payload — all keys sorted alphabetically (recursively) to match util.sorted_json.
PAYLOAD='{"endorsements":[],"grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"establish-authority","kiera_primer":"Kiera is a distributed object system. Objects are identified by UNS addresses (domain/path format, e.g. borg.com/parser). Classes define typed fields and callable methods. Any domain can publish objects over HTTPS. The Kiera blockchain at blockchain.kiera.uno provides immutable signed provenance records. This chain uses Ed25519 signatures and SHA-256 hash chaining. No mining, no gas. Kiera is MIT licensed.","note":"Horatius Security root block — establishes signing authority for federal compliance endorsements on the Kiera blockchain","public_key":"'"$PUB_JSON"'","vibecode":{"contact":"horatius.com","description":"Horatius Security — independent auditor for US federal government compliance","ecoverse":"kiera","entity":"horatius.com","role":"security-auditor","standards":["fedramp-moderate","fedramp-high","fips-140-2"],"trust":"all Horatius endorsements are signed with this key","verification":"blockchain.kiera.uno"}}'

# Record to sign — fields sorted: payload, prev_hash, signer, ts, type.
TO_SIGN='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signer":"horatius.com","ts":"'"$TS"'","type":"root"}'

printf '%s' "$TO_SIGN" > /tmp/hs_sign.dat
SIG=$(openssl pkeyutl -sign -inkey /data/horatius_private.pem -rawin -in /tmp/hs_sign.dat | base64 -w0)
rm -f /tmp/hs_sign.dat
if [ -z "$SIG" ]; then echo "Signing failed"; exit 1; fi

# Full record for hashing — fields sorted: payload, prev_hash, signature, signer, ts, type.
FULL='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signature":"'"$SIG"'","signer":"horatius.com","ts":"'"$TS"'","type":"root"}'

printf '%s' "$FULL" > /tmp/hs_hash.dat
HASH=$(openssl dgst -sha256 -r /tmp/hs_hash.dat | cut -d' ' -f1)
rm -f /tmp/hs_hash.dat

sqlite3 "$DB" "INSERT INTO records (type, prev_hash, ts, signer, payload, signature, record_hash)
  VALUES ('root', '$PREV', '$TS', 'horatius.com', '$PAYLOAD', '$SIG', '$HASH')"

echo "Horatius root block posted."
echo "record_hash: $HASH"
echo ""
echo "Horatius public key:"
cat /data/horatius_public.pem
