# Puck cache directory format
<!--index: 16-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_cache_dir",
	"role": "spec for how a Puck cache directory is laid out on disk. A cache holds multiple versions of Puck-fetched objects per URL, with bytes in a file literally named `content` and per-version metadata in `meta.json` (url, sha256, content-type), both grouped under a reserved `+versions/` subdirectory. The `url` field in meta.json is authoritative when present — the CLI uses it in preference to reconstructing the URL from the disk path, guarding against case-sensitivity mismatches and hand-edited renames. URLs are canonicalized per RFC 3986 before being mapped to disk (lowercase scheme/host, percent-encoding normalization, dot-segment resolution, doubled-slash collapse, fragment strip) — query strings are deliberately not canonicalized. The canonical URL structure maps onto the directory tree in this order: scheme (`https/`, `http/`, ...), then domain, then each path segment — each URL component becomes its own filesystem directory. Each component is normalized independently by percent-encoding unreserved RFC 3986 characters and encoding everything else. Domain-position ports use `~` as the separator (`foo.bar~8080`) since DNS forbids `~` in real domain names, making the split unambiguous and more readable than percent-encoding. Version subdirs are named by ISO 8601 timestamps in a dot-form canonical (`2008-12-03T14.30.00.123-05.00`) that avoids the colons Windows filenames forbid; strict ISO with colons is also accepted where the filesystem allows it. A cache-root `+config.json` carries per-cache settings; `require_sha256` defaults to `true`. Sits as one node in %fetch's search path — a miss falls through to the next node rather than raising.",
	"status": "spec — on-disk layout, normalization, reserved markers, timestamp grammar, meta and config file semantics all settled. Unknown-extension fallback in content-type resolution and additional meta.json fields (fetched_at, HTTP headers, byte count, etc.) still open.",
	"audience": "developers who host or synchronize local Puck caches; CLI implementers who read caches when resolving %fetch fetches; anyone reasoning about how time-based version queries land on disk"
}}
~~~

A **Puck cache directory** is a locally-managed on-disk store of Puck-fetched objects. Unlike a plain URL-mapped directory (which serves exactly one file per URL), a cache directory can hold **multiple versions** of the same URL and answer version-constrained queries — including timestamp-based queries like "give me this object as it was at time T."

Cache directories are one of the nodes in `%fetch`'s search path. When `%fetch` resolves a URL fetch, it walks its search path in order; if a cache directory is in that path, `%fetch` queries it and takes the response as it would any other search-path node. A **miss on the cache does not raise** — the fetch continues along `%fetch`'s search path to the next node.

## Practical guidance

The cache handles arbitrary RFC 3986 URLs, but everything works most smoothly when URLs stay ordinary: **ASCII characters** in domains and path segments, **path segments in the same ballpark as normal filenames** (well under 255 characters after percent-encoding), and **no unusual percent-encoding** in the source URL. Within those bounds, the disk layout looks like the URL you'd write, `ls` on the cache is readable, hand-authoring is straightforward, and none of the finer rules spec'd elsewhere on this page come into play. URLs that push against the corners of RFC 3986 — very long segments, non-ASCII content, elaborate percent-encoding — will still cache correctly, but the disk names get harder to read and the situation-specific rules start to matter.

## Top-level layout

The URL structure maps onto the directory tree in this order: **scheme**, then **domain**, then **each path segment**. A URL like `https://foo.bar/gup/widget.casp` lands at `cache/https/foo.bar/gup/widget.casp/`. Inside the URL's directory, a reserved `+versions/` subdirectory carries one timestamped subdirectory per cached version. Each version subdirectory holds two files: `content` (the bytes, literally named `content`) and `meta.json` (per-version metadata).

~~~
cache/
    +config.json                                     <- cache-level settings
    https/
        foo.bar/
            +versions/                               <- versions of https://foo.bar/
                2008-12-03T14.30.00Z/
                    content                          <- always literally "content"
                    meta.json                        <- always literally "meta.json"
            gup/
                widget.casp/
                    +versions/                       <- versions of https://foo.bar/gup/widget.casp
                        2026-01-15T00.00.00Z/
                            content
                            meta.json
                        2026-06-01T09.30.00-05.00/
                            content
                            meta.json
            hello%20world/
                +versions/                           <- versions of https://foo.bar/hello world
                    2025-12-30T00.00.00Z/
                        content
                        meta.json
    http/
        localhost~3000/
            api/
                +versions/                           <- versions of http://localhost:3000/api
                    2026-01-15T00.00.00Z/
                        content
                        meta.json
~~~

## Scheme

Every cached URL lives under a top-level scheme directory: `cache/https/...` for `https:` URLs, `cache/http/...` for `http:` URLs, and one directory per additional scheme the cache handles. The scheme directory sits directly below `cache/` and above the domain.

**No default scheme.** A URL served via `http:` and the same URL served via `https:` end up in two different subtrees. That's the correct behavior when the two schemes genuinely serve different content, or when a local development server is intentionally on `http:` while its production counterpart is on `https:`.

**Scheme normalization.** The scheme is written in lowercase and stripped of the trailing `:` and any following `//`. `https://foo.bar/` → `cache/https/foo.bar/`; a URL written as `HTTPS://foo.bar/` normalizes to the same location.

**Reserved-marker safety.** Scheme names are simple alphabetic tokens (`https`, `http`, `ftp`, `ws`, `wss`, ...) — none of them start with `+`, so there is no collision with `+config.json` at the cache root or with `+versions/` further down.

## URL canonicalization

Before a URL is mapped to a filesystem path, the CLI **canonicalizes it per RFC 3986**. This ensures URLs that differ syntactically but refer to the same resource land at the same cache location, and it strips out weird-but-legal URL forms so they never surface in the disk layout. Canonicalization runs at both write time (when a fetch is stored) and read time (when a fetch is resolved), so a mismatched-but-equivalent URL still finds the entry.

Steps, in order:

1. **Lowercase the scheme and host.** Scheme and DNS host are case-insensitive, so `HTTPS://Foo.Bar/x` becomes `https://foo.bar/x`. Path segments and query strings retain their case (URL paths are case-sensitive).
2. **Percent-encoding normalization.** Uppercase any percent-encoded hex (`%3f` → `%3F`) and decode any percent-encoded character that's in the RFC 3986 unreserved set (`%7E` → `~`, `%2D` → `-`, and so on). The canonical URL uses percent-encoding only where actually required.
3. **Resolve dot segments in the path.** Per RFC 3986 § 5.2.4, `./` and `../` segments are resolved against the path. `https://foo.bar/gup/../widget.casp` becomes `https://foo.bar/widget.casp`.
4. **Strip trailing slashes and collapse empty path segments.** In the cache, slashes are **separators between segments**, not part of the path. Any trailing slash is stripped, and any empty middle segment from doubled slashes (`//`) is collapsed. `https://foo.bar/gup/widget.casp/` becomes `https://foo.bar/gup/widget.casp`, and `https://foo.bar//gup/widget.casp` becomes `https://foo.bar/gup/widget.casp`. URLs with and without a trailing slash always map to the same cache entry; the domain-root URL `https://foo.bar/` and `https://foo.bar` both land at the same location (no path segments in either case).
5. **Strip the fragment.** URL fragments (`#red`) are not part of Puck's object identity and are stripped before caching.

Query strings are **not** canonicalized. See [No query canonicalization](#no-query-canonicalization) below.

Only after canonicalization does the URL map onto the directory tree — the sections below describe that per-component encoding step.

## URL-to-path normalization

**Paths in the cache are a lookup mechanism, not a URL representation.** The URL structure informs the directory tree because it makes caches human-readable and hand-authorable, but the mapping goes one way only: URL → path. Reading a URL back from the disk path is done through [`meta.json`'s `url` field](#meta-json) when software writes the cache; a cache built or edited by hand doesn't get that guarantee. Because of this asymmetry, **developers hand-authoring caches should stick to plain domains and simple paths** — ASCII, no percent-encoded characters, unambiguous case — situations where the disk path is unambiguously reconstructible into the URL. The rules below describe what the disk layout looks like for those clean cases; situations where the mapping might round-trip poorly are either handled at the meta.json layer (via `url`) or documented as undefined.

Each URL component below the scheme — domain and each path segment — is normalized independently before being written to disk. This runs after [canonicalization](#url-canonicalization) above.

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
| `foo.bar:8080` | `foo.bar~8080` (see [Ports](#ports) below) |
| `+versions` (in a URL segment) | `%2Bversions` |

**Ports.** A domain with a port has its `:` separator written as `~` on disk — `foo.bar:8080` becomes `foo.bar~8080`. `~` is used because DNS labels are restricted to letters, digits, and hyphens, so `~` cannot appear in a legitimate domain name; that guarantees the split between host and port is unambiguous. The port digits themselves need no encoding. This is a domain-position rule — path segments still percent-encode `:` in the general way (see the table above).

**Query strings.** A URL's query portion — everything from `?` onward — is appended to the leaf path segment before normalization. The `?` and everything inside the query get percent-encoded like any other reserved characters: `?` → `%3F`, `=` → `%3D`, `&` → `%26`. Same URL always maps to the same disk location; different query strings produce different leaf directory names.

Example. `https://foo.bar/api/search?q=widget&limit=10` maps to:

~~~
cache/https/foo.bar/api/search%3Fq%3Dwidget%26limit%3D10/+versions/...
~~~

When the URL has no path (just `/`) but does have a query, the query becomes its own leaf segment directly under the domain. `https://foo.bar/?q=x` maps to `cache/https/foo.bar/%3Fq%3Dx/+versions/...`.

**No query canonicalization.** The cache treats the URL string as identity. `?q=1&r=2` and `?r=2&q=1` are logically equivalent but different byte sequences; they map to two different leaf directories. The cache does not sort, dedupe, or otherwise canonicalize query parameters before mapping to disk — that's the caller's responsibility if they want equivalent URLs to share a cache entry.

**Case sensitivity is undefined for case-only collisions.** URL paths are case-sensitive per RFC 3986, and Linux filesystems (ext4, XFS, and other V1 targets) are too, so the encoding above round-trips cleanly on Linux. On case-insensitive filesystems (macOS APFS default, Windows NTFS default), two cache entries that differ **only** by case in some component — say `/API/x.casp` and `/api/x.casp` — would collide, and **the resulting behavior is undefined**. The OS decides whether the second write fails with "already exists," silently overwrites, or resolves to the first entry; the cache spec makes no promise. Guidance: avoid URLs that differ from each other only by case within the same host. This is expected to be rare enough in practice that no formal enforcement is warranted.

## Limits

### Character set

Input URLs may contain any characters legal in RFC 3986 URIs — the full 7-bit ASCII range plus percent-encoded bytes representing any 8-bit value or Unicode via UTF-8. After the normalization rules above, **all on-disk directory and file names are ASCII**: unreserved characters (`0-9`, `A-Z`, `a-z`, `-`, `_`, `.`, `~`) pass through unchanged; every other byte becomes a `%XX` percent-encoded pair.

### Length limits

The cache does not impose its own name-length limits — the underlying filesystem's limits apply directly:

- **Per-component limit** (any single directory name or filename): **`NAME_MAX`** — typically **255 characters** on Linux ext4/XFS and comparable filesystems. This is the limit that shows up in practice; a URL segment longer than 255 characters after percent-encoding fails to write.
- **Total path limit** (full absolute path from filesystem root to the leaf file): **`PATH_MAX`** — typically **4096 characters** on Linux. Rarely hit; would require pathologically deep or long URLs.

### Percent-encoding expansion

Percent-encoding can grow a URL component substantially before it hits disk. A 100-byte segment made entirely of ASCII unreserved characters stays 100 characters on disk. A 100-byte UTF-8 segment where every character is a multi-byte non-unreserved code point (typical for Japanese, Chinese, Cyrillic, or emoji-heavy content) can expand to 300+ characters after percent-encoding — three characters (`%XX`) per byte of the source. The effective per-component limit for Unicode-heavy content is therefore lower than the raw 255-character cap.

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

- **`content`** — the object's bytes, in a file **literally named `content`** (no extension). The name is fixed by the cache format; the file's content-type is not derived from its own name (see [Content-type resolution](#content-type-resolution) below).
- **`meta.json`** — per-version metadata. See [meta.json](#meta-json) below.

**Symlinks are followed transparently.** Either file can be a symbolic link to a target elsewhere on the filesystem; the engine reads through the link with no special handling. This makes it easy to point a version at content living outside the cache (a shared large file, a file under version control elsewhere) or to share bytes across multiple cache entries without duplicating them.

## meta.json

A per-version JSON file carrying metadata about the cached content. All fields below are optional, but the cache-level [`+config.json`](#config-json) may require some of them (notably `sha256`).

| Field | Type | Description |
|---|---|---|
| `url` | string | The canonical URL this cache entry represents. When present, the CLI uses `url` as the **authoritative** URL identity of the entry — a guard against case-sensitivity mismatches on non-case-sensitive filesystems, hand-edited directory renames, or any other case where reconstructing the URL from the disk path could go wrong. When absent, the CLI reconstructs the URL from the path per the [URL-to-path normalization](#url-to-path-normalization) rules. Software should always write this field; hand-authored caches can omit it if the disk path is authoritative. |
| `sha256` | string | Hex-encoded SHA-256 hash of `content`'s bytes. When present, the CLI verifies the content against this hash on read; a mismatch raises. When absent, the CLI skips the check — but a cache with `require_sha256: true` in `+config.json` rejects entries that omit it. |
| `content_type` | string | The content's HTTP-style Content-Type, e.g. `text/x-caspian` or `text/x-caspianj`. When present, `content_type` wins over any hint from the URL's file extension. See [Content-type resolution](#content-type-resolution) below. |

*(Additional fields — `fetched_at`, original HTTP response headers, byte count, and so on — are TBD. This spec keeps the required surface minimal; extensions can be added without breaking readers, since JSON tolerates unknown fields.)*

## Content-type resolution

When the CLI reads a cached version, it needs to know the content-type to hand back to `%fetch`. Resolution order:

1. **`meta.json`'s `content_type` field.** If present, it wins outright — including when it disagrees with any extension the URL might carry.
2. **The URL's own file extension**, mapped through [content-types](https://puck.uno/requirements/content-types). A URL ending in `.casp` implies `text/x-caspian`; `.caspj` implies `text/x-caspianj`. This is the extension of the URL's leaf path segment, preserved as the leaf subdirectory name after normalization.
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

## Pre-transpiled norm sidecar for Caspian source

~~~vibecode
{"vibecode": {
	"section": "norm_sidecar",
	"role": "spec addition: for cached versions whose content is Caspian source (text/x-caspian), the cache may store a pre-transpiled norm-CaspJ file `norm.caspj` alongside `content`, tagged with the transpiler version that produced it. Purpose is to make the engine's load path `json.decode + walk` instead of source-lex-parse-transpile per import. On engine load, the cache checks `norm.caspj`'s transpiler-version tag against the current transpiler; on match, serves norm; on mismatch or absence, re-transpiles from `content` and rewrites `norm.caspj`.",
	"key_concepts": ["norm_caspj_sidecar", "transpiler_version_tag", "source_is_authoritative", "cache_fill_pipeline"]
}}
~~~

When a cached version's `content` is Caspian source (`text/x-caspian`), the cache **may** store a **norm-CaspJ sidecar** in the same version directory: a file `norm.caspj` holding the source pre-transpiled to [norm CaspJ](https://puck.uno/requirements/caspianj#norm). The sidecar exists to make the engine's per-import load path essentially `json.decode + walk` — no lex, no parse, no normalize.

### Layout

Inside a version directory, `norm.caspj` sits alongside `content` and `meta.json`:

~~~
+versions/
    2026-06-01T09.30.00Z/
        content              <- Caspian source bytes (authoritative)
        meta.json            <- version metadata
        norm.caspj           <- pre-transpiled norm CaspJ (optional accelerator)
~~~

`content` remains authoritative. `norm.caspj` is a derived, invalidatable artifact — the engine can always regenerate it from `content`.

### Version tagging

`norm.caspj` carries a top-level `transpiler` field identifying the transpiler that produced it — either a version string or a content-hash of the transpiler's source. On engine load:

- **Fresh** (tag matches the current transpiler) — the engine loads `norm.caspj` directly.
- **Stale** (tag doesn't match) or **absent** — the engine re-transpiles from `content` via [`normalize(transpile(source, {lines: true}))`](https://puck.uno/requirements/caspianj#the-transpiler-api) and rewrites `norm.caspj` with the current tag.

The transpiler-version tag guarantees the norm on disk matches the atom vocabulary the engine expects. A missing tag is treated as stale.

### What the sidecar carries

The sidecar is norm CaspJ with **line info kept** (default for cached norm — see [caspianj](https://puck.uno/requirements/caspianj)). Line info survives normalization because runtime error messages need it. Comments, pipe atoms, base annotations, and `dq` flags all drop as part of normalization.

### When the sidecar does not apply

- Cached versions whose `content_type` is not `text/x-caspian` (e.g. `text/x-caspianj` — the fetched content already IS CaspJ; no sidecar needed).
- Non-Caspian content-types (`application/json`, `text/plain`, images, etc.) — nothing to transpile.
- Caches configured to skip the sidecar (a future `+config.json` setting; the default is TBD).

## Testing

- **Simple URL maps to scheme/domain/segment tree** — a fetch and store of `https://foo.bar/widget.casp` lands at `cache/https/foo.bar/widget.casp/+versions/<timestamp>/content`.
- **Scheme is lowercased** — `HTTPS://foo.bar/x` and `https://foo.bar/x` share the same cache entry.
- **Host is lowercased** — `https://Foo.Bar/x` and `https://foo.bar/x` share the same cache entry.
- **Path case is preserved** — `https://foo.bar/API` and `https://foo.bar/api` cache to two different locations on a case-sensitive filesystem.
- **Percent-encoded hex is uppercased** — a URL written with `%3f` is stored under a canonicalized form with `%3F`.
- **Percent-encoded unreserved chars are decoded** — a URL with `%7E` is stored as `~`; a URL with `%2D` is stored as `-`.
- **Dot segments in the path are resolved** — `https://foo.bar/gup/../widget.casp` caches at the location of `https://foo.bar/widget.casp`.
- **Trailing slash is stripped** — `https://foo.bar/gup/widget.casp/` caches at the same location as `https://foo.bar/gup/widget.casp`.
- **Domain root with and without trailing slash coincide** — `https://foo.bar` and `https://foo.bar/` cache to the same location.
- **Doubled slashes in the path are collapsed** — `https://foo.bar//gup/widget.casp` shares its cache entry with `https://foo.bar/gup/widget.casp`.
- **URL fragments are stripped** — `https://foo.bar/x#red` and `https://foo.bar/x` share their cache entry.
- **Space in a segment is percent-encoded** — `https://foo.bar/hello world` produces a directory named `hello%20world`.
- **Non-ASCII segment is percent-encoded byte-by-byte** — `résumé` in a segment produces `r%C3%A9sum%C3%A9` on disk.
- **Port uses `~` on disk** — `https://foo.bar:8080/x` produces a directory named `foo.bar~8080`.
- **Unreserved characters pass through unchanged** — a segment made of ASCII letters, digits, `-`, `_`, `.`, `~` produces an identical on-disk name.
- **`+versions/` collision with a real segment is impossible** — a URL segment `+versions` writes on disk as `%2Bversions`, not `+versions`.
- **Query string is appended to the leaf segment and percent-encoded** — `https://foo.bar/api/search?q=widget&limit=10` produces a leaf directory `search%3Fq%3Dwidget%26limit%3D10`.
- **Query-only root URL is a leaf under the domain** — `https://foo.bar/?q=x` produces a leaf directory `%3Fq%3Dx` directly under the domain.
- **Query-parameter reorder does not share a cache entry** — `?q=1&r=2` and `?r=2&q=1` produce two different leaf directories.
- **Segment longer than `NAME_MAX` raises on write** — a URL segment exceeding the filesystem's per-component length limit after percent-encoding fails to store.
- **Version subdir named in dot form is accepted** — a version subdirectory named `2008-12-03T14.30.00Z` is enumerable and readable.
- **Version subdir named in colon form is accepted where the filesystem allows** — `2008-12-03T14:30:00Z` is enumerable on filesystems that permit `:` in names.
- **Fractional seconds are honored** — `2008-12-03T14.30.00.123-05.00` compares distinctly from `2008-12-03T14.30.00-05.00`.
- **Bare timestamp is interpreted as local time** — a version subdir with no offset is compared using the reader's local timezone.
- **Same-moment collision across offsets raises** — coexisting `2026-06-01T14.30.00Z` and `2026-06-01T09.30.00-05.00` under the same `+versions/` raises during read.
- **Year-only precision covers the full year** — a version subdir `2008` satisfies a query for any moment in 2008 and is superseded by any finer-precision entry that also covers the target.
- **Latest-covering-version wins on query** — a query for time T resolves to the version whose timestamp is the smallest >= T.
- **Non-ISO date strings raise** — a version subdir named `12/03/2008` or `Dec 3 2008` is rejected during scan.
- **`content` file is read verbatim** — the bytes returned to the caller are byte-identical with the `content` file's contents.
- **`content` symlink is followed transparently** — a `content` symlink to an external file returns the target's bytes.
- **`meta.json`'s `url` field is authoritative** — when `url` is present, the CLI treats the entry's identity as that URL, ignoring the reconstructed disk-path URL.
- **`sha256` mismatch raises** — reading an entry whose `content` bytes don't hash to the stored `sha256` raises.
- **`sha256` absent with `require_sha256: true` raises** — an entry missing `sha256` under a config that requires it is rejected on read.
- **`sha256` absent with `require_sha256: false` reads without raising** — same content served without verification.
- **`content_type` in `meta.json` overrides URL extension** — a `.casp` URL whose `meta.json` says `content_type: text/x-caspianj` is treated as a CaspianJ tree.
- **URL extension resolves content-type when `meta.json` omits it** — a `.casp` cache entry with no `content_type` yields `text/x-caspian` to the caller.
- **Unknown extension with no `content_type` — TBD-marked test placeholder** — pending spec resolution.
- **Missing `+config.json` yields defaults** — a cache with no config file behaves as if `require_sha256: true`.
- **Cache miss falls through, does not raise** — a fetch of a URL not present in the cache continues to the next node in `%fetch`'s search path.
- **Two caches on the same machine have independent settings** — one cache configured `require_sha256: true` and another `require_sha256: false` behave differently for the same URL.
- **Case-only collision on case-insensitive filesystem — undefined behavior sentinel** — `/API/x.casp` vs `/api/x.casp` on APFS/NTFS does not need to succeed; test simply asserts it doesn't corrupt other entries.
- **Fresh norm sidecar is loaded directly** — a `norm.caspj` whose `transpiler` tag matches the current transpiler is decoded and returned without touching `content`.
- **Stale norm sidecar is re-transpiled** — a `norm.caspj` with a mismatched `transpiler` tag is regenerated from `content` and rewritten with the current tag.
- **Missing norm sidecar is created on first load** — a version directory with `content` but no `norm.caspj` transpiles from `content` and writes the sidecar.
- **Norm sidecar keeps line info** — a runtime error in cached code reports its source line via the annotations preserved through normalization.

## Related

- [local-loading](https://puck.uno/requirements/local-loading) — the direct local-file mechanisms (`local:` URLs and URL mapping) that a cache complements. A URL mapping ties a prefix to one directory with no versioning; a cache directory is the versioning-capable equivalent.
- [content-types](https://puck.uno/requirements/content-types) — the canonical Content-Type strings for Caspian source and CaspianJ tree files. Used both as the target values of `meta.json`'s `content_type` field and as the mapping for URL-extension fallback.
- [non-caspian-mime-types](https://puck.uno/requirements/non-caspian-mime-types) — how the engine handles content types other than Caspian and CaspianJ, including the empty-content rules that apply when the cache serves a stored version back to a caller.
- [caspianj](https://puck.uno/requirements/caspianj) — the two CaspJ formats (full and norm), the `transpile` / `normalize` API pair, and what the norm sidecar in a cache version directory actually contains.
- [`%fetch`](https://puck.uno/requirements/fetch) — the Caspian-side gateway for fetches. `%fetch`'s search path (spec'd elsewhere) is where a cache directory sits.
