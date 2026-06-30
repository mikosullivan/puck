# Encrypted `%tmp` — implementation report

~~~vibecode
{"vibecode": {
	"doc": "encrypted_tmp_implementation",
	"role": "implementation-focused companion to encrypted-tmp.md. Settles the file format, module layout, libsodium API choices, key lifecycle, error handling, and Lua reference engine specifics. Granular enough that someone could begin coding from this.",
	"status": "drafted from the approved design recommendation in encrypted-tmp.md — concrete enough to start implementing; security review still wanted before any of it goes into production code",
	"audience": "engine implementers, security reviewers, and anyone tracking what the V1+ encrypted-tmp surface will actually do under the hood"
}}
~~~

This report builds on the design recommendation in [encrypted-tmp](https://puck.uno/documentation/ideas/caspian/encrypted-tmp#recommendation). That doc said *what* to build (per-file AEAD, deterministic filename encryption, in-memory master key); this one says *how*.

The phased plan in the design report is the schedule; this report fleshes out each phase with concrete specifics. The structure here roughly follows that plan, but with all the layers visible so it's clear how the pieces fit before any one of them ships.

## Dependencies

**libsodium is already part of the core Caspian distribution** — it's what backs the existing `%chain.encryption` surface. Encrypted `%tmp` reuses that dependency and adds no new ones. Every cryptographic primitive used below is in stable libsodium; no custom crypto, no extra libraries.

Primitives used:

- ChaCha20-Poly1305 AEAD per chunk: `crypto_aead_xchacha20poly1305_ietf_*` (or `crypto_secretstream_xchacha20poly1305_*` for the pure-streaming case).
- HKDF for per-dirjail and per-chunk key/nonce derivation: `crypto_kdf_hkdf_sha256_*`.
- Keyed HMAC for deterministic filename mapping: `crypto_auth_hmacsha256_*`.
- Master-key RNG: `randombytes_buf`.
- Secure memory: `sodium_malloc`, `sodium_mlock`, `sodium_munlock`, `sodium_memzero`.

(Earlier drafts of this report wandered into "what if SIV isn't available" — moot. Core ships libsodium, the primitives we need are all in the version we ship, and the engine doesn't need a runtime version check or fallback path.)

## Module layout

All new code lives under `code/caspian/<host-lang>/encryption/` — a sibling of the existing `code/caspian/lua/` engine modules:

~~~
code/caspian/lua/
├─ encryption/
│  ├─ master_key.lua    -- K generation, lock, derive
│  ├─ aead.lua          -- chunk-streaming encrypt/decrypt wrapper
│  ├─ name_cipher.lua   -- deterministic filename mapping
│  ├─ dirjail.lua       -- encrypted-dirjail file class
│  └─ libsodium.lua     -- thin FFI binding (or wrapper around sodium-lua)
└─ ... (existing engine modules)
~~~

The Caspian-class surface (`%tmp.method`, file-class methods) lives in the existing engine module tree. The crypto wrapper is one indirection layer beneath: every read or write of a chunk goes through `aead.lua`, every filename lookup goes through `name_cipher.lua`. Caspian-side code doesn't reach into libsodium directly.

For other host languages (Python, JS engines), the same layout repeats with a host-appropriate libsodium binding (PyNaCl, libsodium-wrappers, etc.).

## Master key lifecycle

### Generation

At engine startup — before any user-program frame runs:

~~~lua
local sodium = require("encryption.libsodium")

-- 32 bytes of cryptographically strong random material.
local K = sodium.malloc_locked(32)
sodium.randombytes_buf(K)

-- Best-effort hardening: no coredumps, no ptrace by sibling processes.
sodium.prctl_set_dumpable(0)
~~~

`sodium.malloc_locked` is a thin wrapper over `sodium_malloc` followed by `sodium_mlock` and `MADV_DONTDUMP`. The buffer is the only place `K` ever lives.

### Use

`K` is **never** passed to user code, never serialized, never logged. The only operation user-program code triggers is `%tmp` dirjail creation, which derives a per-dirjail key (next section).

### Shutdown

On engine shutdown (clean or via `at_exit` handler):

~~~lua
sodium.memzero(K)
sodium.munlock(K)
sodium.free(K)
~~~

A `SIGKILL` skips this, of course — that's a residual risk acknowledged in the design report.

## Per-dirjail key derivation

Each `%tmp` access generates a fresh dirjail UUID (16 bytes from `randombytes_buf`) and derives a per-dirjail key `K_d`:

~~~lua
-- HKDF-SHA256(K, salt=dirjail_uuid, info="caspian:tmp:v1", length=32)
local K_d = sodium.kdf_hkdf_sha256(
    K,                          -- input keying material
    dirjail_uuid,               -- salt
    "caspian:tmp:v1",           -- info (versioning hook)
    32                          -- output length
)
~~~

The `"v1"` in the info string is the version token — if we ever change derivation, bump to `"v2"` and existing v1 dirjails just don't decrypt (they'd be unreadable garbage; cleanup proceeds anyway since deletion doesn't need the key).

`K_d` is held in another `sodium_malloc`-locked buffer alongside the dirjail handle. When the dirjail is closed (block exit, scope exit, explicit close), the buffer is `memzero`'d and freed.

The on-disk dir is named by a random hex string unrelated to the dirjail UUID (the UUID is in-memory only):

~~~
/tmp/caspian-<random-hex>/
~~~

This is intentional: the on-disk name leaks no information about which dirjail is which, and an attacker who finds the dir on disk can't even confirm whether it's still in use by a running process.

## File format

Every file in the dirjail is one of these blobs on disk:

~~~
[4-byte version magic][24-byte stream-init nonce][N x encrypted chunks]
~~~

Where each encrypted chunk is:

~~~
[2-byte chunk-payload length][chunk ciphertext + AEAD tag]
~~~

The `crypto_secretstream_xchacha20poly1305_*` primitives handle the chunking, per-chunk nonce derivation, and AEAD tag in a stream-friendly API. The 2-byte length prefix tells the reader how much to read into the next decryption call.

### Write flow

~~~lua
-- Open file for writing.
local handle = sodium.secretstream_init_push(K_d)
file:write(VERSION_MAGIC)                       -- 4 bytes
file:write(handle.header)                       -- 24-byte stream header

-- Each chunk:
local ciphertext = sodium.secretstream_push(
    handle, plaintext_chunk, associated_data, TAG_MESSAGE)
file:write(pack_uint16(#ciphertext))
file:write(ciphertext)

-- On close, write a final chunk with TAG_FINAL so the reader knows
-- it reached EOF rather than truncation.
local final = sodium.secretstream_push(handle, "", "", TAG_FINAL)
file:write(pack_uint16(#final))
file:write(final)
~~~

`TAG_FINAL` is critical — without it, a reader can't distinguish "file ended" from "file was truncated by an attacker." With it, missing TAG_FINAL means decryption fails loud rather than silently returning a prefix of the original data.

### Read flow

~~~lua
local version = file:read(4)
if version ~= VERSION_MAGIC then return error("bad magic / not encrypted") end
local header = file:read(24)
local handle = sodium.secretstream_init_pull(header, K_d)

repeat
    local len = unpack_uint16(file:read(2))
    local ciphertext = file:read(len)
    local plaintext, tag = sodium.secretstream_pull(handle, ciphertext, associated_data)
    if not plaintext then error("AEAD failure — file tampered or wrong key") end
    yield_chunk(plaintext)
until tag == TAG_FINAL
~~~

### Random access

The libsodium secretstream API is forward-sequential — chunks must be decrypted in order. For random reads (the design report covers the semantics), the implementation uses a separate scheme:

- Each file maintains an **in-memory chunk index** built on first open: `[chunk_offset_on_disk, plaintext_offset_at_start_of_chunk]` pairs.
- Random read at plaintext offset `O` for `N` bytes: binary-search the chunk index to find the spanning chunks, decrypt each, slice and concatenate.
- The chunk index is built lazily on first random-access call (sequential reads don't need it).

Random writes mutate one chunk at a time; the chunk is decrypted into a writable buffer, modified, re-encrypted with a **fresh nonce** (via `secretstream_init_push` for that single chunk), and written back. The version-magic + header at the file start is rewritten only if every chunk is rewritten; otherwise individual chunk headers handle the per-chunk key. (This is the trickiest part of the implementation — see Open implementation questions below.)

Alternatively, the random-access case can be solved by a simpler scheme: use `crypto_aead_xchacha20poly1305_ietf` per chunk with a deterministic per-chunk nonce (HKDF of the file key + chunk index). That avoids the secretstream's forward-sequential constraint at the cost of slightly more cryptographic discipline. **Recommendation: use per-chunk AEAD with a derived nonce for the file format; reserve secretstream for the streaming-only fast path if benchmarks show it matters.**

### Per-chunk AEAD format

Switching to per-chunk AEAD (recommended above), the on-disk format becomes:

~~~
[4-byte version magic][24-byte file-id salt][chunk 0][chunk 1]...[chunk N-1]
~~~

Where each chunk is the same fixed plaintext size (say 65,536 bytes), and the on-disk size is `plaintext_size + 16` (AEAD tag, no per-chunk nonce because nonce is derived):

~~~
nonce_i = HKDF-SHA256(K_d, salt=file_id, info="caspian:tmp:chunk:" + chunk_index, length=12)
ciphertext_i, tag_i = AEAD-encrypt(K_d, nonce_i, plaintext_chunk_i, associated_data=file_path)
~~~

`file_path` is associated-data so a chunk written for `report.pdf` can't be moved to `other.pdf` and still decrypt.

The trailing partial chunk is the same shape but with a shorter plaintext (the AEAD tag is still 16 bytes). The end of file is detected by EOF on the on-disk file — no explicit FINAL marker needed because chunk-level AEAD already catches truncation at chunk granularity. For finer truncation detection, store the plaintext file length as associated-data on chunk 0, or as a separate authenticated header field.

## Filename encryption

The deterministic-name requirement (so `$dir['report.pdf']` always maps to the same on-disk file) is satisfied by **keyed HMAC-SHA-256 truncated to a filesystem-safe length**, plus a separate per-name secret AEAD entry that recovers the plaintext name if needed:

~~~
on_disk_name = base32(HMAC-SHA256(K_name, plaintext_name)[:20])
~~~

`K_name = HKDF(K_d, info="caspian:tmp:names:v1", length=32)` — a separate derived key for filename mapping so the chunk-content keys aren't reused.

This is **not** reversible — the on-disk name doesn't decrypt back to the plaintext name. For dirjails that need plaintext-name reconstruction (e.g., listing a directory and getting back human-readable names), we additionally store a small per-dirjail manifest file:

~~~
.names.enc:
  AEAD-encrypted hash[on_disk_name -> plaintext_name]
~~~

The manifest is itself an AEAD blob, decryptable only with `K_name`. Reads of `$dir.entries` decrypt the manifest into a hash and return the plaintext names. Writes (new file) atomically append to the manifest (read → mutate → write back with fresh nonce). Deletes (file removed) similarly remove from the manifest.

If the design report's "no plaintext name reconstruction" simplification is acceptable (programs always know the names they're looking for), the manifest can be skipped entirely. **Default: ship the manifest; add a kwarg `%tmp(names_listable: false)` to skip it for callers who don't need listing.**

The HMAC vs AES-SIV trade: HMAC is in every libsodium build, has a simple deterministic mapping property, and doesn't need a separate cipher. AES-SIV's advantage is reversibility (an opaque "encrypted name" that can be decrypted) — but we get that via the separate manifest, which is decoupled from the on-disk-name mapping anyway.

## Subdirectory structure

Each subdirectory is a directory on disk named by the encrypted-name scheme above. The subdirectory has its own derived `K_d'`:

~~~
K_d' = HKDF(K_d, salt=subdir_on_disk_name, info="caspian:tmp:subdir:v1", length=32)
~~~

Plus a separate `K_name'` for that subdir's filename mapping, derived the same way from `K_d'`.

The parent-child tree on disk matches the logical structure (encrypted names, encrypted files, encrypted manifest in each dir). Walking the tree from the root requires only `K_d` — every child key derives from the parent.

## File-class API

The Caspian file class for encrypted-tmp files implements the standard surface (`.read`, `.write`, `.seek`, `.size`, `.truncate`, `.close`, etc.). From the user's perspective these behave identically to a plaintext file; the encryption layer is invisible.

Behind the scenes, each method routes through the chunk index:

| File method | Implementation |
|---|---|
| `.read(n)` from current position | Compute spanning chunks, decrypt, slice, advance position. |
| `.write(bytes)` at current position | Compute spanning chunks, decrypt-mutate-encrypt each, advance position. |
| `.seek(offset)` | Just updates the in-memory position; no I/O. |
| `.size` | Read from authenticated header (file length stored in chunk-0 AAD or a separate field). |
| `.truncate(n)` | Re-encrypt the chunk containing byte n; remove subsequent chunks. |
| `.close` | Flush any pending writes; `memzero` any decrypted-chunk buffers in memory. |

The handle holds a small LRU of recently-decrypted chunks (size: 4 chunks ≈ 256 KiB by default) so successive small reads in the same region don't re-decrypt.

## Error handling

| Failure | Behavior |
|---|---|
| AEAD tag mismatch on read | Raise `puck.uno/error/tmp/integrity` — file was tampered or wrong key. No partial data returned. |
| Disk write fails mid-chunk | Raise `puck.uno/error/tmp/write`; the partial chunk on disk is invalid (length prefix won't match what was written). On reopen, the file's last chunk fails AEAD and the file is reported as truncated. |
| Header magic missing | Raise `puck.uno/error/tmp/format` — file isn't an encrypted-tmp file. |
| Process killed mid-write | Same as disk-write-fail — last chunk is invalid on reopen. |
| Master key derivation fails | At engine startup, fatal — engine refuses to start. (Indicates a serious sodium build problem; libsodium is core so the failure mode is broken-install, not missing-dep.) |

Every error includes the dirjail UUID and chunk index for debugging, but **never** includes any plaintext or key material in the message.

## Lua reference engine specifics

### libsodium binding

The Lua reference engine reuses whatever libsodium binding the existing `%chain.encryption` surface uses — encrypted `%tmp` is one more consumer of the same binding, not a parallel one. The encryption layer's modules import `encryption.libsodium` and call into it like any other internal module.

If the existing binding doesn't yet expose the specific primitives encrypted `%tmp` needs (the AEAD chunk push/pull, HKDF, HMAC), the binding gets extended in place rather than forked.

### Memory pressure

Decrypted-chunk buffers are kept in `sodium_malloc`-locked memory and zeroed before release. Memory-locked allocations are limited per-process (RLIMIT_MEMLOCK); a large fleet of open encrypted files could hit that limit. The LRU cap (4 chunks per handle, configurable) keeps the total bounded.

If RLIMIT_MEMLOCK proves to be a real ceiling in practice, the cap becomes user-configurable per-dirjail and the engine surfaces a warning in `%engine.manifest` when chunks aren't getting mlock'd.

### Fork inheritance

When a Caspian program forks (`%forks.branch` etc.), the child inherits the parent's memory pages including `K` and any `K_d` for open dirjails. This is just how `fork(2)` works — the child can decrypt anything the parent could.

The design report's open question about cross-process sharing (`tmp_share` capability) becomes simpler in this light: any forked child already has access; the question is just whether the child SHOULD have access by default. **Recommendation: children inherit by default (matching the no-role-change-on-fork rule from [forks: no role change](https://puck.uno/documentation/requirements/caspian/roles/#forks-no-role-change)); a `%forks.branch(no_inherit_tmp: true)` opt-out is the escape hatch for the case where the parent wants the child sealed off.**

## Testing strategy

| Tier | Coverage |
|---|---|
| Unit | Per-primitive: HKDF derivation matches RFC test vectors; AEAD encrypt/decrypt round-trip; ciphertext tampering detected; per-chunk nonce derivation correct. |
| Integration | Full file write → close → reopen → read round-trip. Random read after random write. Truncate / append / overwrite. Subdir creation / nested derivation. |
| Persistence | Write file, kill process, restart engine, attempt to read → must fail (key gone). Confirms forward secrecy across process boundary. |
| Adversarial | Bit-flip a random byte in an encrypted file → AEAD must fail. Truncate a file mid-chunk → next read must fail. Swap two encrypted files between paths → AAD check must fail decrypt. |
| Performance | Sequential throughput vs plaintext (target: within 2x). Random-read latency on a 1 GB file (target: sub-millisecond for cached chunks). |
| Memory | `/proc/<pid>/maps` shows the K buffer is locked. Core-dump test confirms K isn't dumped. (Both gated on Linux; the test suite documents expected behavior on other platforms.) |

Test fixtures use a fixed test-key (NOT randomly generated) to make test runs reproducible. The fixed key is clearly labeled as test-only and not derived from any production code path.

## Open implementation questions

Real questions the implementation will surface that aren't fully settled:

- **AAD content.** Should the AEAD's associated-data be (file_path, chunk_index)? Or just file_path? Including chunk_index prevents chunk-swap-within-file attacks; just file_path is enough to prevent cross-file moves. **Lean: include both — the cost is zero and it tightens the integrity guarantee.**

- **Plaintext file size storage.** Where do we authenticate the plaintext file length so truncation at the file's end is detected? Options: (a) in chunk-0's associated-data, (b) in a dedicated authenticated trailer chunk, (c) infer from chunk count + last-chunk plaintext size. (a) is the cleanest if we make chunk 0 always exist (even for empty files); (b) requires walking to the end to verify; (c) is implicit but means a malicious truncate to a chunk boundary isn't detected. **Lean: (a) — store plaintext size in chunk 0's AAD.**

- **Manifest concurrency.** The names manifest is read-modify-write per name change. Two threads (or coroutines) modifying simultaneously could race. Solutions: (1) serialize all writes through a single per-dirjail mutex (simple, modest perf cost); (2) use append-only journal with periodic compaction (complex but better perf). **Lean: (1) — `%tmp` access is already serialized per the single-threaded Caspian default.**

- **Reopening across engine restarts.** A dirjail created in engine instance A and somehow persisted past A's shutdown can never be reopened — `K` is gone. The current design accepts this (each `%tmp` is per-engine-lifetime). If we ever want persistent encrypted dirjails (across restarts), we'd need a separate key-persistence story (filesystem-stored sealed key, OS keyring, etc.). **Out of scope for this report; the encrypted-tmp surface is engine-lifetime only.**

- **Throughput on the reference engine.** Per-chunk AEAD inside Lua may show overhead beyond what libsodium can deliver in C. The existing `%chain.encryption` surface already pays this cost for hashing and signing; encrypted `%tmp` adds streaming bulk crypto, where the per-call overhead is amortized over each chunk's bytes. **Action: phase-2 benchmark establishes whether the binding's per-call cost dominates the actual encryption — if it does, the binding adds a batched/streaming call that processes multiple chunks per FFI crossing.**

- **Where the encrypted-tmp surface attaches to the Caspian-class layer.** Two options: (a) `%tmp(encrypted: true)` returns an encrypted dirjail of the same class as the plaintext one; (b) `%tmp.encrypted` is a separate surface. **Lean: (a) — the user gets one consistent dirjail surface and the encryption is a configuration knob, not a type difference.**

## See also

- [encrypted-tmp](https://puck.uno/documentation/ideas/caspian/encrypted-tmp) — the design report this implementation realizes.
- [`%tmp`](https://puck.uno/documentation/requirements/caspian/chain/methods/tmp) — the current unencrypted `%tmp` spec; the encrypted surface will eventually fold into here per Phase 5.
- [`%chain.encryption`](https://puck.uno/documentation/requirements/caspian/chain/methods/encryption) — the encryption capability surface; the symmetric primitives introduced here (ChaCha20-Poly1305, HKDF, HMAC) would land here or in a lower-level crypto layer if surfaced to user code.
