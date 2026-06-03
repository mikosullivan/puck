# Caching

*Official spec for Caspian's on-disk library cache.*

~~~json
{"vibecode": {
	"doc": "caching_spec",
	"role": "canonical spec for Caspian's on-disk library cache — flat root with integer-named subdirs, per-library versions/<timestamp>/ subdirs each holding meta.json plus source.casp and/or source.caspj, single source file per library for V1.0",
	"audience": ["Caspian programmers and operators reasoning about library caching",
		"implementers of the cache layer"],
	"key_concepts": ["on_disk_directory_only",
		"flat_root_with_index_txt_and_integer_named_subdirs",
		"per_library_versions_subdir",
		"version_dir_name_is_iso8601_with_colon_to_dash_substitution",
		"meta_json_is_authoritative_on_conflict",
		"prefer_caspj_over_casp_at_retrieval",
		"single_source_file_per_library_for_v1"]
}}
~~~

A **cache** in this context is an on-disk directory containing objects downloaded through the Puck ecoverse. Not a database, not a remote API — a plain filesystem directory. Other caching mechanisms exist in Caspian; this spec covers the on-disk cache only.

---

<a id="top-level-layout"></a>
## Top-level layout

The root of a cache directory holds:

- **`index.txt`** — a plain text file mapping each cached UNS to its on-disk directory name.
- **One subdirectory per cached UNS**, named with an integer.

The layout is **flat**: every cached library sits as a single subdirectory directly under the root, regardless of how deep its UNS is. The UNS hierarchy is not mirrored in the filesystem.

```
my-cache/
├─ index.txt
├─ 1/
├─ 2/
├─ 100/
└─ ...
```

<a id="index-txt"></a>
### `index.txt` format

Each line maps one UNS to its directory name, space-separated:

```
borg.com/parser 100
syntex.io/validator 101
foo.bar/gup 102
```

`index.txt` is the authoritative lookup. The file is consulted to translate a UNS into a filesystem path; the directory's existence is not enough on its own.

<a id="integer-naming"></a>
### Integer directory names

Each library directory is named with an integer. New entries get **`max + 1`** (one greater than the current largest integer in the cache). Gaps from deletions stay as gaps — the sequence keeps extending, never reuses old IDs.

Integers as directory names avoid the awkwardness of treating UNS strings (which contain `/` and may have other filesystem-unfriendly characters) as filenames. The `index.txt` mapping is what makes the UNS-to-directory translation work.

---

<a id="per-library-layout"></a>
## Per-library layout

Inside each integer-named directory:

```
100/
└─ versions/
   ├─ 2026-05-07T14-30-00Z/
   │  ├─ meta.json
   │  ├─ source.casp        (when distributed as Caspian source)
   │  └─ source.caspj       (when distributed as CaspianJ, or generated locally)
   │
   └─ 2026-05-12T09-00-00Z/
      └─ ...
```

Every library directory has a `versions/` subdirectory, even if it currently holds only one version. Multiple versions of the same library coexist as sibling subdirectories under `versions/`.

A library is a **single source file** for V1.0. Multi-file libraries are a possible future expansion, not in scope here.

<a id="version-directory-name"></a>
### Version directory name

Each version is a subdirectory named with the artifact's **timestamp** — the chain's `effective_date` (falling back to `posted` when no `effective_date` is set).

The directory name format is **standard ISO 8601 with `:` replaced by `-`** for filesystem compatibility:

| Form | Example |
|---|---|
| Standard ISO 8601 | `2026-05-07T14:30:00Z` (uses `:`, problematic on Windows) |
| Cache directory form | `2026-05-07T14-30-00Z` (`-` substituted, safe everywhere) |

Reversal is mechanical: find `T`, swap `-` for `:` in everything between `T` and `Z`. Two-character lossless transform either direction.

**UTC only.** The round-trip assumes the `Z` suffix. Non-UTC offsets like `-08:00` would break reversibility (`-` would mean both "colon substitute" and "timezone sign" in the same string). The blockchain mandates UTC for `posted`; `effective_date` is a calendar date; cache timestamps mirror those. Local offsets are not permitted in cache directory names.

Sub-second granularity extends naturally: `2026-05-07T14-30-00.123Z`.

The directory name and `meta.json.timestamp` are the same value, kept as a redundant pair for browsability. On conflict, [`meta.json` is authoritative](#meta-json) and the directory name is re-derivable from it.

<a id="version-files"></a>
### Files inside a version directory

At most three files:

- **`meta.json`** — version metadata. Always present.
- **`source.casp`** — the original Caspian source. Present when the library was distributed as Caspian source; absent when it was distributed as CaspianJ.
- **`source.caspj`** — the transpiled CaspianJ. Present when the library was distributed as CaspianJ, or when it has been generated locally from `source.casp` (see [Retrieval](#retrieval)).

---

<a id="meta-json"></a>
## `meta.json`

Per-version metadata, formatted as JSON. Recognized fields:

| Field | Type | Notes |
|---|---|---|
| `source` | object | Where the bytes came from. Shape: `{"url": "...", "downloaded_at": "..."}`. `downloaded_at` uses standard ISO 8601 with `:` separators. |
| `signature` | string | The blockchain signature for this version's download. **Required when `%puck.blockchain` is set at fetch time**; absent only when the entry was written with no chain verification active. See [Signature verification](#signature-verification) below for the read-time check. |
| `semver` | string | Optional. The semver string for this version, when the artifact declares one. |
| `timestamp` | string | Standard ISO 8601 (`:` separators). The artifact's timestamp — same value as the directory name (modulo the `:`↔`-` substitution). |

`meta.json` is the authoritative metadata source. If the directory name and `meta.json.timestamp` disagree, `meta.json` wins. The directory name is treated as a presentation/browsability artifact derivable from `meta.json`.

Timestamps stored inside `meta.json` use **standard ISO 8601** (`:` separators) — the `-` substitution is a filesystem-layer concession that lives only at the directory-name layer.

---

<a id="retrieval"></a>
## Retrieval routine

When the engine needs to load a library version:

1. **Prefer `source.caspj` if present.** Skip the lex/parse/transpile pipeline entirely.
2. **If `source.caspj` is absent**, parse `source.casp`. (This implies the library was distributed as Caspian source.)
3. **If the process has write permission to the cache**, write the transpiled CaspianJ to `source.caspj` so subsequent runs take the fast path.
4. **If the process lacks write permission**, use the in-memory transpile result and don't persist. No error — read-only cache is a supported state.

If a library was originally distributed as CaspianJ (no `source.casp` present), the routine always takes the fast path. The cache never manufactures a `source.casp` from a `source.caspj` — there is no reverse transpile.

<a id="distribution-forms"></a>
### Distribution forms

The cache accommodates two ways a library can be distributed:

- **Caspian source distribution** — `.casp` present, `.caspj` may or may not be present (generated locally on first use when the cache is writable).
- **CaspianJ distribution** — `.caspj` present (downloaded that way), `.casp` absent and never created.

The runtime retrieval routine handles both transparently.

---

<a id="signature-verification"></a>
## Signature verification

When [`%puck.blockchain`](../service/index.md#puck-blockchain) is set on the process, every cache hit goes through a signature check.

**Capture at write time.** When a library is first fetched (any source — the blockchain.puck.uno mirror, the publisher's HTTPS endpoint, anywhere) and written to the cache, the engine queries the configured blockchain for that artifact's signature and stores it in `meta.json.signature`. This adds one extra HTTP request per cache miss when blockchain verification is active.

**Verify at read time, locally.** Cache reads check `meta.json.signature` against the configured chain's baked-in public key. No network call on a cache hit — the verification is purely local, microsecond-scale, deterministic, works offline. The signature was captured against a known chain; verifying it against that chain's public key needs no further communication.

**On verification failure** (signature missing, signature for a different key, signature corrupt, etc.):

1. **Raise a warning** through Caspian's [warning system](../../packages/jasmine/index.md#logger-failure-cascade) — operators see the integrity event.
2. **If the cache is writable**, delete the bad entry. The next lookup re-fetches; the new download captures a fresh signature and stores it.
3. **If the cache is read-only**, bypass the entry without deletion. The lookup falls through to the next fetcher in the search path, where the re-fetch (and re-capture) happens in memory.

**Cached-without-signature entries.** A cache entry written before `%puck.blockchain` was enabled — or written by a process that didn't have it enabled — has no `signature` field. With verification active, those entries are treated the same as verification failures (warn, delete-if-writable, re-fetch). The first run with verification enabled effectively rebuilds any pre-existing cache contents with their signatures.

**Verification scope is universal.** This applies to every library load, including ones the application has already used in the current process — the verification fires at the cache-access boundary, not at first-use boundary. Once `%puck.blockchain` is set, nothing the engine loads bypasses the check.

---

<a id="timestamp-uniqueness"></a>
## Timestamps and uniqueness

Library timestamps are at least **second-granularity** (finer is fine; coarser is not). The blockchain rejects an endorse block whose timestamp duplicates an existing one for the same UNS. That guarantees that within any library's `versions/` subdirectory, no two child directories can share a name — name collisions on the cache side are impossible by upstream construction.

---

<a id="security-postures"></a>
## Security postures the cache supports

Two postures the on-disk cache directly enables, beyond its performance role:

- **Cache-only, network-isolated.** Give a process only a pre-populated cache directory and forbid network access at the host level. `%puck[uns]` lookups succeed when the library is in the cache and fail otherwise — there's no fallback path. Useful for air-gapped deployments, reproducible builds, regulated environments where the auditor wants a single artifact (the cache directory) to point at. Complementary to the [provenance-allowlist machinery](../service/index.md); a deployment that can simply forbid network access doesn't need the allowlist.
- **Read-only cache.** Mount the cache directory read-only for the process. The retrieval routine still works — first-miss libraries are parsed in memory and used; the engine just doesn't persist the transpile result. Lets one writable populating process feed many read-only consumers.

---

<a id="open-items"></a>
## Open items (not in this spec)

These are known design questions to settle when the situation forces them:

- **Engine-version invalidation for locally generated `source.caspj`.** Transpiler output format may change between engine versions; an old `.caspj` could be incompatible with a newer engine. Options: stamp `engine_version` inside the `.caspj` (or in `meta.json`) and re-generate on mismatch; or guarantee CaspianJ format stability across engine versions. The retrieval routine as written doesn't enforce either.
- **Concurrent writes to `source.caspj`.** Multiple processes parsing the same source and racing to write the cache. Atomic temp-file + rename, plus the fact that the same engine version produces identical CaspianJ, means last-writer-wins is harmless — but the spec doesn't yet state this.
- **Eviction policy.** When cached entries get removed, who decides, what triggers it.
- **Multi-file libraries.** Single source file per library for V1.0. The directory layout would need a `src/` subdir or similar to grow into multi-file later.

---

<a id="see-also"></a>
## See also

- [Versioning](../../versioning/) — the version-constraint surfaces (era, per-UNS, per-call) that decide which cached version a lookup picks.
- [Downloads service (blockchain.puck.uno)](../service/) — one source of cache contents; mirror + chain-verified signatures.
- [Blockchain](../service/blockchain/) — defines `posted`, `effective_date`, `semver`, the timestamp-uniqueness rule, and the signing scheme `signature` references.
