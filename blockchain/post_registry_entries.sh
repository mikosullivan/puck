#!/bin/sh
# Post five registry_entry blocks to Falstaff.
set -e

DB=/data/falstaff.db
KEY=/data/private.pem
GRAMMAR_HASH="c2c018a5a1bf2d6e0748ec73f9ea45901fdb5e587838a532d3f37e36f620da4f"
TODAY=$(date -u '+%Y-%m-%d')

sign_and_insert() {
    local UNS="$1"
    local PAYLOAD="$2"

    PREV=$(sqlite3 "$DB" "SELECT record_hash FROM records ORDER BY id DESC LIMIT 1")
    TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    TO_SIGN='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signer":"kiera.uno","ts":"'"$TS"'","type":"registry_entry"}'

    printf '%s' "$TO_SIGN" > /tmp/re_sign.dat
    SIG=$(openssl pkeyutl -sign -inkey "$KEY" -rawin -in /tmp/re_sign.dat | base64 -w0)
    rm -f /tmp/re_sign.dat
    if [ -z "$SIG" ]; then echo "Signing failed for $UNS"; exit 1; fi

    FULL='{"payload":'"$PAYLOAD"',"prev_hash":"'"$PREV"'","signature":"'"$SIG"'","signer":"kiera.uno","ts":"'"$TS"'","type":"registry_entry"}'

    printf '%s' "$FULL" > /tmp/re_hash.dat
    HASH=$(openssl dgst -sha256 -r /tmp/re_hash.dat | cut -d' ' -f1)
    rm -f /tmp/re_hash.dat

    sqlite3 "$DB" "INSERT INTO records (type, prev_hash, ts, signer, payload, signature, record_hash)
      VALUES ('registry_entry', '$PREV', '$TS', 'kiera.uno', '$PAYLOAD', '$SIG', '$HASH')"

    echo "$UNS -> $HASH"
}

# 1. borg.com/parser
sign_and_insert "borg.com/parser" '{"bucket":{"class":"kiera.uno/class","description":"Parses structured text into a normalised output hash.","kscript":"%vibecode <<~VIBECODE\n{\"class\":\"kiera.uno/class\",\"name\":\"borg.com/parser\",\"version\":\"2.1.0\"}\nVIBECODE\n\nfunction &parse($text, $options={}) {\n  # parse input text, return hash\n}\n\nfunction &validate($text) {\n  # return true if text would parse\n}\n\nfunction &reset {\n  # clear internal state\n}\n","name":"borg.com/parser","version":"2.1.0"},"effective_date":"'"$TODAY"'","grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"register","uns":"borg.com/parser","version":"2.1.0","vibecode":{"license":"MIT","signer":"kiera.uno","type":"registry_entry","uns":"borg.com/parser","version":"2.1.0"}}'

# 2. syntex.io/validator
sign_and_insert "syntex.io/validator" '{"bucket":{"class":"kiera.uno/class","description":"Validates JSON documents against a Kiera schema object.","kscript":"%vibecode <<~VIBECODE\n{\"class\":\"kiera.uno/class\",\"name\":\"syntex.io/validator\",\"version\":\"1.4.2\"}\nVIBECODE\n\nfunction &validate($doc, $schema) {\n  # validate doc against schema, return boolean\n}\n\nfunction &errors($doc, $schema) {\n  # return array of validation error messages\n}\n","name":"syntex.io/validator","version":"1.4.2"},"effective_date":"'"$TODAY"'","grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"register","uns":"syntex.io/validator","version":"1.4.2","vibecode":{"license":"Apache-2.0","signer":"kiera.uno","type":"registry_entry","uns":"syntex.io/validator","version":"1.4.2"}}'

# 3. netbridge.dev/http-client
sign_and_insert "netbridge.dev/http-client" '{"bucket":{"class":"kiera.uno/class","description":"Async HTTP client with retry, timeout, and TLS support.","kscript":"%vibecode <<~VIBECODE\n{\"class\":\"kiera.uno/class\",\"name\":\"netbridge.dev/http-client\",\"version\":\"3.0.1\"}\nVIBECODE\n\nfunction &get($url, $options={}) {\n  # perform GET, return response hash\n}\n\nfunction &post($url, $body, $options={}) {\n  # perform POST, return response hash\n}\n","name":"netbridge.dev/http-client","version":"3.0.1"},"effective_date":"'"$TODAY"'","grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"register","uns":"netbridge.dev/http-client","version":"3.0.1","vibecode":{"license":"MIT","signer":"kiera.uno","type":"registry_entry","uns":"netbridge.dev/http-client","version":"3.0.1"}}'

# 4. quanta.systems/crypto
sign_and_insert "quanta.systems/crypto" '{"bucket":{"class":"kiera.uno/class","description":"Ed25519 signing, AES-256-GCM encryption, and SHA-2 hashing primitives.","kscript":"%vibecode <<~VIBECODE\n{\"class\":\"kiera.uno/class\",\"name\":\"quanta.systems/crypto\",\"version\":\"2.0.0\"}\nVIBECODE\n\nfunction &sign($data, $private_key) {\n  # sign data with Ed25519 private key, return base64 signature\n}\n\nfunction &verify($data, $signature, $public_key) {\n  # verify Ed25519 signature, return boolean\n}\n\nfunction &sha256($data) {\n  # return hex SHA-256 digest\n}\n","name":"quanta.systems/crypto","version":"2.0.0"},"effective_date":"'"$TODAY"'","grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"register","uns":"quanta.systems/crypto","version":"2.0.0","vibecode":{"license":"Apache-2.0","signer":"kiera.uno","type":"registry_entry","uns":"quanta.systems/crypto","version":"2.0.0"}}'

# 5. meridian.tech/logger
sign_and_insert "meridian.tech/logger" '{"bucket":{"class":"kiera.uno/class","description":"Structured JSON logger with configurable levels, sinks, and redaction rules.","kscript":"%vibecode <<~VIBECODE\n{\"class\":\"kiera.uno/class\",\"name\":\"meridian.tech/logger\",\"version\":\"1.1.0\"}\nVIBECODE\n\nfunction &info($message, $fields={}) {\n  # log at INFO level\n}\n\nfunction &error($message, $fields={}) {\n  # log at ERROR level\n}\n\nfunction &set_sink($sink) {\n  # configure output destination\n}\n","name":"meridian.tech/logger","version":"1.1.0"},"effective_date":"'"$TODAY"'","grammar":{"hash":"'"$GRAMMAR_HASH"'","version":"1.0"},"intent":"register","uns":"meridian.tech/logger","version":"1.1.0","vibecode":{"license":"MIT","signer":"kiera.uno","type":"registry_entry","uns":"meridian.tech/logger","version":"1.1.0"}}'

echo ""
echo "Done. Chain state:"
sqlite3 "$DB" "SELECT id, type, signer, record_hash FROM records ORDER BY id"
