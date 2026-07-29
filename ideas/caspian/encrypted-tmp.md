# Encrypted temp directories

~~~vibecode
{"vibecode": {
	"doc": "encrypted_tmp",
	"role": "design report on making %tmp directories encrypted at rest with an in-process key so abandoned temp dirs (process crash, kill, etc.) remain unreadable to anyone else on the host. Recommends a scheme, sketches the residual risks, and proposes a phased plan.",
	"status": "brainstorm — recommendations are concrete but the whole thing wants a security review before going into the canonical spec"
}}
~~~

The current `%tmp` story relies on OS temp-dir cleanup to limit how long an abandoned temp dir lingers on disk. That's the standard Unix posture — fine for most use cases, but the dir's contents are readable to anyone who can read `/tmp` until the sweep catches it.

The ask: make the contents unreadable to anyone except the process that created the dir, including after the process is gone. The proposed mechanism: encrypt the dir's contents with a key held only in process memory.

This report walks through the threat model, design options, a recommended scheme, residual risks, and a phased plan.

## Threat model

Concrete scenarios we want to defend against:

1. **Process crash leaves temp dir on disk.** The Caspian program creates `/tmp/abc123/` and writes sensitive data (uploaded video being transcoded, intermediate state of a database export, decrypted user blob). The process crashes before cleanup runs. The dir sits on disk for minutes-to-hours until the OS sweep. During that window, anyone with read access to `/tmp` can read the abandoned contents.

2. **Concurrent process inspects temp dir.** Another process running as the same Unix user (or as root) tries to read `/tmp/abc123/` while the Caspian process is still using it. Standard Unix permissions limit this — the dir is mode 0700 owned by the user — but a coresident process running as the same user has read access. In multi-tenant or cloud contexts this is a real risk.

3. **Stolen disk / forensic recovery.** The host's storage is acquired by an attacker after the fact. Even if `/tmp` was cleaned, deleted file blocks may be recoverable. Encrypted-at-rest contents stay opaque.

4. **OS-level snapshots.** Many cloud environments snapshot `/tmp`-bearing volumes for backup, debugging, or audit. Sensitive data in `/tmp` ends up in the snapshot whether the program wants it to or not. Encryption defangs the snapshot.

Out of scope (residual risk, addressed later):

- **Process memory dump.** If an attacker can `gdb` the process or read its memory, the key leaks. Mitigations exist (mlock, no-coredump) but the boundary is real.
- **Side channels.** File sizes, file counts, modification times, directory tree shape — all leak information even when contents are encrypted.

## Design options

### Option A — FUSE-backed encrypted filesystem

Mount a userspace encrypted filesystem at the temp location (gocryptfs, cryfs, EncFS). The Caspian process holds the master key and uses it to mount; the kernel's FUSE layer presents a normal filesystem that transparently encrypts/decrypts.

**Pros.** Well-known crypto, OS-level integration, files appear normal to the rest of the Caspian filesystem layer.

**Cons.** Requires FUSE installed and the user having permission to mount. Mount/unmount is heavyweight (process spawn, syscalls, kernel state). Doesn't work in containers without privileged mode. Adds a Caspian-side dependency on whichever FUSE tool. Cleanup on crash is complex — the mount can survive the process and become a confusing orphan.

### Option B — application-level encryption per file

The Caspian filesystem layer encrypts on write and decrypts on read. The on-disk dir contains encrypted blobs at encrypted-filename paths.

**Pros.** Portable (no FUSE, no special OS permissions). Works in containers and minimal environments. Single layer of code to audit. Cleanup is straightforward — the encrypted blobs are just files.

**Cons.** Every file open goes through the encryption layer; non-trivial perf cost for large or many-small-file workloads. Metadata leaks more than the FUSE option (FUSE can also hide file sizes via padding; app-level requires us to build that).

### Option C — single encrypted blob

The whole `%tmp` dirjail is backed by one encrypted blob on disk. In-memory, the dirjail is a virtual filesystem (Caspian classes pointing into the blob).

**Pros.** Filenames are completely hidden — the blob is just bytes. Maximum metadata protection (no per-file timestamps, no file-count leak).

**Cons.** Scale doesn't work. The motivating use case for `%tmp` is "I need scratch space for a huge file" (uploaded videos, multi-gigabyte intermediate data); making that a single blob means we'd need to either load the whole blob into memory or build a complex on-disk paging layer.

### Option D — hybrid

Small files in-memory; large files encrypted on disk; filenames encrypted. Tries to balance perf and protection by routing based on size.

**Pros.** Best of both — small files never hit disk; large files are encrypted.

**Cons.** Two code paths to audit. Threshold ("how small is small?") is yet another knob.

## Recommendation

**Option B with thoughtful filename and metadata handling.**

The reasoning:

- Portability matters. `%tmp` needs to work in containers, in cloud environments without elevated mount permissions, on developer laptops, on the test rig. FUSE excludes too many of those.
- Per-file encryption is well-trodden cryptographic ground — every file uses **AEAD** with a per-file nonce. The crypto is straightforward to audit.
- Cleanup is just `rm -rf` of the encrypted directory — same as the current model.

### What "AEAD" means

AEAD stands for **Authenticated Encryption with Associated Data** — a category of ciphers that do two jobs at once on every operation:

1. **Encrypt** the payload so it's unreadable to anyone without the key (confidentiality).
2. **Authenticate** the payload with a short tag (typically 16 bytes) so any tampering after the fact is detected (integrity). If even one bit of the ciphertext is flipped between write and read, decryption fails loudly instead of producing garbage.

The "Associated Data" half is optional metadata that's authenticated but **not** encrypted — usually a small header or context string the program wants to confirm wasn't swapped out. For `%tmp` we mostly don't need it; the file path can serve as associated data (so a ciphertext written for `foo.txt` can't be moved to `bar.txt` and still decrypt).

Concrete schemes used in the recommendation:

- **ChaCha20-Poly1305** — the standard AEAD construction for streaming bulk data. Fast (1-2 GB/s on a modern CPU), no hardware acceleration required, well-analyzed. Used for file contents.
- **AES-SIV-256** — a special AEAD variant that's **deterministic** (same plaintext + same key always produces the same ciphertext). Used for filenames so lookups by name still work. Pays a small perf cost for the determinism but is what makes the filename-encryption story workable.

The "non-AEAD" alternative would be plain ChaCha20 or AES-CTR plus a separate HMAC-SHA-256 over the ciphertext. AEAD wraps both operations into one primitive with a single key, which is why every modern cipher choice for data-at-rest is AEAD: fewer ways for the application to assemble the pieces wrong.
- The perf cost of per-file AEAD is real but bounded. For the dominant use case (large scratch files written once, read once), the overhead is one streaming encryption pass on each side.

The remaining design surface is how to handle filenames and metadata, addressed below.

## The recommended scheme

### Master key

Each engine instance generates a 32-byte master key `K` at startup using libsodium's `randombytes_buf`. `K` lives in process memory only — never written to disk, never logged, never serialized.

The buffer holding `K` is:

- `mlock()`ed so the kernel can't swap it.
- Allocated with `MADV_DONTDUMP` (or the equivalent) so coredumps skip it.
- Zeroed on engine shutdown (best-effort; obviously useless if the process is killed -9).

The engine also calls `prctl(PR_SET_DUMPABLE, 0)` at startup when the engine starts using `K` so the process can't be coredumped or `ptrace()`'d by other processes of the same user.

### Per-dirjail key derivation

Each `%tmp` access generates a fresh subdir-key `K_d = HKDF-SHA256(K, "caspian:tmp:" + dirjail_uuid)`. The dirjail UUID is also held in memory; the on-disk dir is named by some non-revealing identifier (a random hex string).

Using a derived key per dirjail means:

- The master key never touches files. Compromise of any single file's content (broken AEAD, theoretical CCA attack) doesn't compromise other dirjails.
- Multiple concurrent `%tmp` dirjails are cryptographically independent.
- The master key's lifecycle is decoupled from any particular dirjail's lifecycle.

### File contents

Each file's content is encrypted with **ChaCha20-Poly1305** (AEAD). Per-file random 24-byte nonce. The on-disk file layout:

~~~
[24-byte nonce][ciphertext + 16-byte auth tag]
~~~

The AEAD tag prevents tampering — if an attacker modifies a byte, decryption fails. The nonce is random and 24 bytes, so collision probability is negligible (XChaCha20 specifically uses 24-byte nonces for this safety margin).

**Streaming.** Large files don't fit in memory. The encryption layer streams in fixed-size chunks (say 64 KiB), each chunk independently AEAD-encrypted with its own nonce derived from a per-file base nonce + chunk index. Same scheme libsodium's `crypto_secretstream` already implements; we'd use that directly.

### Streaming reads and random access

**Sequential streaming.** Native to the scheme. The reader processes one encrypted chunk at a time, decrypts it, hands the plaintext bytes upward, drops the chunk, and moves on. Constant memory for a file of any size — the same shape as reading a plaintext file through a buffered reader.

**Random reads — seeking to byte offset O and reading N bytes.** Supported, with **chunk-boundary granularity** as the overhead. The reader:

1. Computes which chunk(s) `[O, O+N)` falls into. With 64 KiB chunks, byte 100,000 lives in chunk 1 at intra-chunk offset 34,464.
2. Reads each spanning chunk, decrypts it (the AEAD tag is over the whole chunk; you can't skip the tag verification), and extracts the requested slice of plaintext.
3. Returns the assembled slice.

Cost: the smallest meaningful unit of decryption is one chunk. Reading 1 byte at offset 100,000 of a 1 GB file requires reading and decrypting 64 KiB of disk content. Reading 1,000 bytes that span a chunk boundary requires decrypting two chunks. Caching recently-decrypted chunks in memory (LRU, bounded) absorbs the cost when access patterns are localized.

Chunk size is the knob:

| Chunk size | Sequential overhead | Random-read amplification | Use case |
|---|---|---|---|
| 4 KiB | Higher (more per-byte crypto) | Low (≤4 KiB per random read) | Database-style random-access workloads. |
| 64 KiB | Moderate | Moderate (~64 KiB per random read) | Default — balances both. |
| 1 MiB | Low (efficient streaming) | High (≤1 MiB wasted per random read) | Pure sequential (transcoded video, etc.). |

Default `%tmp(chunk_size: 65536)` is a fine starting point; programs that know their access pattern can tune.

**Random writes — overwriting bytes at offset O.** Also supported, with per-chunk granularity. Modifying any byte means re-encrypting the chunk containing it: decrypt → mutate plaintext → re-encrypt with a **fresh** nonce → write back. Nonce reuse would break ChaCha20-Poly1305, so the re-encrypt must generate a new random nonce and rewrite the whole chunk header.

The cost is similar to random reads — chunk-sized work per write, regardless of how many bytes were modified within the chunk. Programs that update bytes hot would benefit from a write-back cache that batches updates within a chunk before re-encrypting.

**Append.** Straightforward — encrypt the new bytes as new chunks (or extend the partially-filled last chunk after decrypt + re-encrypt) and write to disk. No global re-encryption needed; existing chunks stay untouched.

**Truncate.** Straightforward at a chunk boundary; mid-chunk truncation requires decrypt + re-encrypt of the partial trailing chunk.

**What this means for the Caspian file-class API.** The standard file methods (`.read`, `.write`, `.seek`, `.size`, `.truncate`) all map cleanly onto these operations. Programs that worked with plaintext `%tmp` files continue to work with encrypted ones; the only observable difference is per-chunk crypto overhead on small random accesses.

### Filenames

Filenames need to be encrypted so the on-disk dir doesn't leak "salaries.csv" or "uploaded_passport.jpg". But filenames also need to be **deterministically** encrypted — when the user code says `$dir['report.pdf']`, the layer needs to map that to the same on-disk filename every time.

Use **AES-SIV-256** (synthetic IV mode): a deterministic AEAD that produces the same ciphertext for the same plaintext-under-the-same-key. The encrypted filename is `hex(AES-SIV-256(plaintext_name, K_d))`. Same name always maps to same on-disk filename, so lookup by name works.

This leaks **equality** of filenames within a dirjail (two files with the same plaintext name produce the same ciphertext name — but that's already true because filesystems don't allow duplicates). It does **not** leak filename content across dirjails (different `K_d` per dirjail).

### Subdirectories

Each subdirectory's name is encrypted the same way as filenames, using its parent's `K_d`. The subdirectory has its own `K_d'` derived from its parent's `K_d` plus the encrypted-subdirectory-name. This way the parent-child structure on disk matches the logical tree, but no name is in plaintext.

### File sizes

This is the unsolvable-without-cost residual leak. Mitigations:

- **Round file sizes to block boundaries.** Always store files at sizes that are multiples of (say) 4 KiB. Pads files less than 4 KiB up to that. Adds at most 4 KiB of overhead per file.
- **No padding.** Accept the leak. Reasonable when the threat model doesn't include adversaries who can analyze sizes (most cases).

I'd recommend **no padding by default**, with an opt-in for size-padded mode for cases where the threat model warrants it. Padding everything costs space for limited gain in typical use.

### Cleanup

The encrypted dirjail's lifecycle is unchanged: deleted on scope exit, block exit, explicit close, or process death. Cleanup is just `rm -rf`. After deletion, the on-disk bytes are encrypted blobs that nobody can read; forensic recovery of blocks yields opaque ciphertext.

## Residual risks

| Risk | Mitigation | Status |
|---|---|---|
| Process memory dump leaks `K` | mlock, no-dump, no-ptrace, zero-on-exit | Mitigated to the OS limit |
| Attacker reads disk during process run | Encryption + per-file AEAD | Fully addressed |
| Abandoned dir after crash | Encryption + per-file AEAD | Fully addressed |
| Forensic recovery from deleted blocks | Same — bytes are encrypted | Fully addressed |
| File sizes leak | Optional padding | Trade-off; off by default |
| Filename length leaks | Could pad encrypted filenames | Likely overkill |
| File count leaks | No mitigation | Accepted |
| Modification times leak | Could mask times | Likely overkill |

The big remaining concern is **memory dump**. If the host is compromised at the kernel level, no in-process encryption scheme protects anything — the attacker can read process memory directly. We're defending the disk; we're not defending against the kernel being owned.

## Performance posture

Per-file ChaCha20-Poly1305 streaming runs at ~1-2 GB/s on modern CPUs with libsodium's optimized implementation. For the "large scratch file" use case (videos, archives), encryption is rarely the bottleneck — disk I/O is. For "many tiny files" workloads, the per-file fixed cost (key setup, nonce, AEAD tag) shows up; not a typical `%tmp` workload but worth noting.

AES-SIV filename encryption is similarly fast — fractions of a microsecond per name.

Padding to 4 KiB blocks costs ≤4 KiB per file plus the I/O to write it. Negligible for large files; meaningful overhead for many-tiny-files cases. Hence the opt-in.

## Phased implementation plan

**Phase 1: ground truth.**

- Add `K` generation, `mlock`, no-dump, no-ptrace at engine startup.
- Implement libsodium binding usage in the Lua reference engine.
- Smoke tests verifying key isn't in coredumps or `/proc/<pid>/mem` (with appropriate kernel settings).

**Phase 2: per-file content encryption.**

- Implement streaming AEAD wrapper around file read/write in `%tmp` dirjails.
- Filenames remain in plaintext for this phase.
- Benchmark perf overhead vs. current `%tmp`.

**Phase 3: filename and subdir encryption.**

- AES-SIV deterministic filename encryption.
- Subdir tree under encrypted names.
- Lookup-by-name through the encrypted-filename mapping.

**Phase 4: opt-in padding.**

- File-size padding to 4 KiB blocks.
- Kwarg on `%tmp` to enable (e.g., `%tmp(padded: true)`).

**Phase 5: spec migration.**

- The encrypted-tmp story moves out of `ideas/` into `requirements/chain/methods/tmp.md` as the canonical behavior.
- Document the threat model and residual risks in that canonical doc.
- Update `%tmp` user-facing docs to mention the security guarantee.

## Open questions

- **Should this be the default, or opt-in via a kwarg?** Default-encrypted is more secure; opt-in is more compatible with "I want to inspect what's in `/tmp` while debugging." I lean toward default-encrypted with a kwarg `plain: true` for the dev-inspection case. The asymmetry (secure by default, insecure by explicit opt-in) is the right shape per "no dangerous defaults."

- **What about cross-process sharing?** If a Caspian program forks and the child wants to write to the parent's `%tmp` dirjail, the child needs `K_d`. The fork mechanism would have to explicitly hand the key to the child. This is a real piece of the fork story we'd need to spec; probably as a capability `tmp_share` that the parent grants on fork.

- **Filesystem implementation detail.** Should the encryption layer be at the Caspian-class level (dirjail/file classes do the crypto) or at a lower level (libsodium-backed file wrapper that the dirjail uses)? Lower-level is more reusable for other Caspian filesystem layers; class-level keeps the security knob visible in the spec for `%tmp` specifically. I lean lower-level — the dirjail's filesystem class wraps an encryption-aware backend that other surfaces can also use.

- **Test mode.** Tests need to be able to inspect what got written. The `test` role (per [roles/index.md](../requirements/roles/index.md)) could legitimately get the decryption capability for the dirjail it owns. Aligns with the broader "test gets things production code doesn't" framing.

## See also

- [`%tmp`](../requirements/chain/methods/tmp) — the current `%tmp` spec (unencrypted).
- [`%chain.encryption`](https://puck.uno/requirements/chain/methods/encryption) — the Ed25519/SHA encryption primitives spec (does NOT include symmetric primitives; this proposal would add ChaCha20-Poly1305 and AES-SIV to that surface or to a lower-level crypto layer).
- [`%random`](../requirements/chain/methods/random) — for libsodium-backed key/nonce generation, already specified.
