# Puck cache directory format
<!--index: 16-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_cache_dir",
	"role": "spec for how a Puck cache directory is laid out on disk. A cache holds multiple versions of Puck-fetched objects per URL, with content and per-version metadata (sha256, content-type) grouped under a reserved `+versions/` subdirectory. URL path components — domain and each path segment — become filesystem directories, each normalized independently by percent-encoding unreserved RFC 3986 characters and encoding everything else. Version subdirs are named by ISO 8601 timestamps in a dot-form canonical (`2008-12-03T14.30.00.123-05.00`) that avoids the colons Windows filenames forbid; strict ISO with colons is also accepted where the filesystem allows it. A cache-root `+config.json` carries per-cache settings; `require_sha256` defaults to `true`. Sits as one node in %puck's search path — a miss falls through to the next node rather than raising.",
	"status": "spec — on-disk layout, normalization, reserved markers, timestamp grammar, meta and config file semantics all settled. HTTP vs HTTPS treatment, port-number encoding beyond default percent-encoding, unknown-extension fallback in content-type resolution, and additional meta.json fields (fetched_at, HTTP headers, byte count, etc.) still open.",
	"audience": "developers who host or synchronize local Puck caches; CLI implementers who read caches when resolving %puck fetches; anyone reasoning about how time-based version queries land on disk"
}}
~~~

A **Puck cache directory** is a locally-managed on-disk store of Puck-fetched objects. Unlike a plain URL-mapped directory (which serves exactly one file per URL), a cache directory can hold **multiple versions** of the same URL and answer version-constrained queries — including timestamp-based queries like "give me this object as it was at time T."

Cache directories are one of the nodes in `%puck`'s search path. When `%puck` resolves a URL fetch, it walks its search path in order; if a cache directory is in that path, `%puck` queries it and takes the response as it would any other search-path node. A **miss on the cache does not raise** — the fetch continues along `%puck`'s search path to the next node.

## Top-level layout

The URL structure maps onto the directory tree. A URL like `https://foo.bar/gup/widget` lands at `cache/foo.bar/gup/widget/`, with the domain as the top-level directory and each URL path segment as a nested subdirectory. Inside the URL's directory, a reserved `+versions/` subdirectory carries one timestamped subdirectory per cached version. Each version subdirectory holds two files: `file` (the content) and `meta.json` (per-version metadata).

~~~
cache/
    +config.json                                     <- cache-level settings
    foo.bar/
        +versions/                                   <- versions of https://foo.bar/
            2008-12-03T14.30.00Z/
                file
                meta.json
        gup/
            widget/
                +versions/                           <- versions of https://foo.bar/gup/widget
                    2026-01-15T00.00.00Z/
                        file
                        meta.json
                    2026-06-01T09.30.00-05.00/
                        file
                        meta.json
        hello%20world/
            +versions/                               <- versions of https://foo.bar/hello world
                2025-12-30T00.00.00Z/
                    file
                    meta.json
~~~

## URL-to-path normalization

Each URL component — domain and each path segment — is normalized independently before being written to disk.

**Rules.** For each component:

- Characters in the **RFC 3986 unreserved set** pass through unchanged: `0-9`, `A-Z`, `a-z`, `-`, `_`, `.`, `~`.
- Every other character is percent-encoded per RFC 3986 (`%XX` in uppercase hex; multi-byte UTF-8 is percent-encoded byte-by-byte).

**Plain names stay plain.** ASCII path segments made of unreserved characters map to identical directory names. A URL like `https://foo.bar/gup/widget` produces `cache/foo.bar/gup/widget/` with no encoding applied.

**Non-ASCII and reserved characters get encoded.**

| URL component | On disk |
|---|---|
| `foo.bar` | `foo.bar` |
| `gup` | `gup` |
| `widget` | `widget` |
| `hello world` | `hello%20world` |
| `résumé` | `r%C3%A9sum%C3%A9` |
| `例え.jp` | `%E4%BE%8B%E3%81%88.jp` |
| `foo.bar:8080` | `foo.bar%3A8080` |
| `+versions` (in a URL segment) | `%2Bversions` |

**Ports.** A domain with a port (`foo.bar:8080`) has its colon percent-encoded to `%3A` and lands as `foo.bar%3A8080`. Same rule as any other reserved character.

## Reserved marker: `+versions/`

The `+versions/` subdirectory is a **reserved name**: it is not a URL path segment. Under the normalization rules above, a real URL segment `+versions` would be percent-encoded to `%2Bversions`, so no legitimate URL segment can collide with the reserved marker. That safety property is why `+` was chosen — it's the specific character that guarantees non-collision under RFC 3986 percent-encoding.

`+versions/` contains one subdirectory per cached version of the URL, named by ISO 8601 timestamp (see below).

The domain-root URL (`https://foo.bar/`, no path) uses the same convention: `cache/foo.bar/+versions/` holds versions of the domain root itself.

## Timestamp format

Version subdirectories are named by ISO 8601 timestamps. The cache defines a **canonical dot form** that is Windows-safe (no colons), and also **accepts strict ISO 8601 with colons** on filesystems that allow them. Software should write the dot form; developers hand-authoring version subdirs may use either.

**Canonical dot form:**

~~~
YYYY-MM-DDThh.mm.ss[.fff][ZONE]
~~~

Where `ZONE` is either `Z` (UTC) or an offset in dot form (`+hh.mm` or `-hh.mm`). Examples:

- `2008-12-03T14.30.00Z`
- `2008-12-03T14.30.00.123-05.00`
- `2026-06-01T09.30.00+09.00`

**Colon form (also accepted where the filesystem allows):**

~~~
YYYY-MM-DDThh:mm:ss[.fff][ZONE]
~~~

Where `ZONE` is `Z`, `+hh:mm`, or `-hh:mm`. Examples:

- `2008-12-03T14:30:00Z`
- `2008-12-03T14:30:00.123-05:00`

**Only ISO 8601 and its dot variation.** The cache does not accept arbitrary date/time formats — no US-style `12/03/2008`, no month-name forms like `Dec 3 2008`, no locale-specific variants. Only strict ISO 8601 (with colons) and the cache's dot-form variation are recognized. A small amount of forgiveness applies inside those forms — for example, accepting both `Z` and `+00:00`, both `.` and `,` for fractional seconds, both compact (`+0900`) and extended (`+09:00`) offsets on filesystems that allow the colon. The exact edges of forgiveness are a **build-time** decision, not spec'd here; this section describes the target format, not every accepted variant. In practice the format space is deliberately narrow because ISO 8601 covers every representation a developer typically needs, and staying inside it keeps every reader (human or software) on the same page about what a version subdirectory name means.

**No fractional hours or minutes.** Strict ISO 8601 permits `14.5` (14.5 hours) or `14:30.5` (fractional minute), but the cache format restricts to `hh.mm.ss` with optional fractional **seconds** only. This restriction avoids the ambiguity between "dots as separators" and "dot as decimal" — under the cache's format, `14.5` alone is not a legal time.

**Bare timestamps use local time.** A version subdirectory with no timezone offset — no `Z`, no `+hh.mm`, no `-hh.mm` — is interpreted as the reader's local time. This is a convenience for hand-authored development caches where the developer wants to write "current time" without looking up an offset. Note that bare timestamps are not portable across timezones: the same string names different moments on machines in different timezones. For portable caches (shared with a team, checked into a repo, downloaded across machines), always include an explicit offset.

**UTC normalization.** The engine converts each version subdirectory's timestamp to UTC internally when deciding which version satisfies a query. Two subdirectories that resolve to the same moment — regardless of representation, form, or timezone offset — are treated as a collision and raise. Example collision:

- `2026-06-01T14.30.00Z` and `2026-06-01T09.30.00-05.00` are the same moment and cannot coexist in the same `+versions/` directory.

**On-disk name preserved.** The engine's UTC normalization only affects lookup logic — the directory name is preserved exactly as written. A developer writing `+0900` sees `+0900` in `ls`; the engine's internal comparison uses the UTC-normalized value but doesn't rewrite the disk name.

**Version timestamps as coverage boundaries.** Each version's timestamp marks the **latest moment** the version applies to. A query for time T is satisfied by the version whose timestamp is the smallest that's still >= T — the version that "covers" T with the closest bound. This is the semantic model behind the round-up rule for lower-precision timestamps below.

**Lower-precision timestamps.** Any precision is legal, from year-only up to full nanosecond resolution. The engine treats a shorter-precision timestamp as marking the **latest moment covered by that precision**, at the highest precision the underlying platform supports. Examples:

- `2008-12-03` (date only) is treated as `2008-12-03T23:59:59.999...` — the last representable moment before midnight Dec 4. A query for `2008-12-03T14.30.00` finds this version because 14:30:00 <= 23:59:59.999... .
- `2008-12` (year-month) covers all of December 2008.
- `2008` (year only) covers all of 2008.

**Best practice: date precision or finer.** Full year-month-day (`YYYY-MM-DD`) is the recommended minimum for cache subdir names. Year-only and year-month forms are legal but too coarse for most practical uses — they lump many versions together in ways that make cache management harder. Software should always write at date precision or finer; hand-authored caches should use at least date precision unless there's a specific reason to be coarser.

**Precision.** The engine records and compares timestamps at the precision the underlying platform supports. Filesystems, JSON parsers, and language runtimes vary in how many fractional-second digits they preserve; the cache does not attempt to standardize. Two subdirs that resolve to the same moment at the coarsest common precision are treated as colliding. In practice most cache activity operates at whole-second or millisecond granularity, so platform-precision differences rarely surface.

## Version directory contents

Each timestamped subdirectory holds exactly two files:

- **`file`** — the object's bytes, literally named `file` (no extension). The file's content-type is not derived from its own name; see [Content-type resolution](#content-type-resolution) below.
- **`meta.json`** — per-version metadata. See [meta.json](#meta-json) below.

## meta.json

A per-version JSON file carrying metadata about the cached content. Both fields below are optional, but the cache-level [`+config.json`](#config-json) may require some of them (notably `sha256`).

| Field | Type | Description |
|---|---|---|
| `sha256` | string | Hex-encoded SHA-256 hash of `file`'s bytes. When present, the CLI verifies the content against this hash on read; a mismatch raises. When absent, the CLI skips the check — but a cache with `require_sha256: true` in `+config.json` rejects entries that omit it. |
| `content_type` | string | The content's HTTP-style Content-Type, e.g. `text/x-caspian` or `text/x-caspianj`. When present, `content_type` wins over any hint from the URL's file extension. See [Content-type resolution](#content-type-resolution) below. |

*(Additional fields — `fetched_at`, original HTTP response headers, byte count, and so on — are TBD. This spec keeps the required surface minimal; extensions can be added without breaking readers, since JSON tolerates unknown fields.)*

## Content-type resolution

When the CLI reads a cached version, it needs to know the content-type to hand back to `%puck`. Resolution order:

1. **`meta.json`'s `content_type` field.** If present, it wins outright — including when it disagrees with any extension the URL might carry.
2. **The URL's own file extension**, mapped through [content-types](https://puck.uno/documentation/requirements/caspian/content-types). A URL ending in `.casp` implies `text/x-caspian`; `.caspj` implies `text/x-caspianj`. This is the extension of the URL's leaf path segment, preserved as the leaf subdirectory name after normalization.
3. **Neither present.** Raise. Silently defaulting could mask real problems, especially since Caspian source and CaspianJ trees are handled by different code paths.

**Unknown extension.** When the URL has an extension that isn't `.casp` or `.caspj` and `meta.json` carries no `content_type` — TBD.

## Cache-level configuration: `+config.json`

Every cache directory carries a top-level `+config.json` file with cache-wide settings. It uses the same reserved-name convention as `+versions/`: `+` percent-encodes in URL segments, so `+config.json` cannot collide with any URL-derived name.

Currently defined settings:

| Field | Type | Default | Description |
|---|---|---|---|
| `require_sha256` | boolean | `true` | If `true`, every cached version's `meta.json` must include a `sha256` field. On read, the CLI verifies the content against the stored hash; on write, it computes and stores the hash. If `false`, entries without `sha256` are permitted — useful for hand-authored development caches. |

A missing `+config.json` is equivalent to an empty one — all fields fall back to their defaults, which means the safe posture (hash-required) is what a cache with no config gets.

Different caches on the same machine may have different settings. A network cache in `~/.cache/caspian/` might have `require_sha256: true` (verified downloads); a development cache in `~/.local/share/caspian/` might have `require_sha256: false` (edit files freely).

## Related

- [local-loading](https://puck.uno/documentation/requirements/caspian/local-loading) — the direct local-file mechanisms (`local:` URLs and URL mapping) that a cache complements. A URL mapping ties a prefix to one directory with no versioning; a cache directory is the versioning-capable equivalent.
- [content-types](https://puck.uno/documentation/requirements/caspian/content-types) — the canonical Content-Type strings for Caspian source and CaspianJ tree files. Used both as the target values of `meta.json`'s `content_type` field and as the mapping for URL-extension fallback.
- [`%puck`](https://puck.uno/documentation/requirements/caspian/chain/methods/puck) — the Caspian-side gateway for Puck fetches. `%puck`'s search path (spec'd elsewhere) is where a cache directory sits.
