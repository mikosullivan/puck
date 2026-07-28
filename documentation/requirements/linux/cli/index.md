# Linux CLI wrappers

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli",
	"role": "index and pattern spec for Caspian classes that wrap Linux command-line utilities. Every wrapper lives at caspian.uno/linux/cli/{name}, calls .execute internally, and does NOT link native libraries — the utility itself does the work. Individual wrapper specs live as siblings in this directory (tar, gzip, gunzip, zip, unzip, file, cut, sort, uniq, uname, pandoc, convert, 7z, bzip2, ...).",
	"status": "spec — the namespace and pattern are settled; individual wrapper specs land as sub-pages",
	"audience": "developers reaching for a CLI-utility class; authors writing new wrapper specs; the ecoverse-maintenance team"
}}
~~~

**Every Caspian class that wraps a standard Linux command-line utility lives under `caspian.uno/linux/cli/{name}`.** This directory is the specs tree that shadows that URL space — one sub-page per wrapper. The general model (invoking executables via `.execute`, structured results, no shell) lives in [linux-support](https://puck.uno/documentation/requirements/linux-support/); this dir focuses on the per-wrapper specs.

## What a CLI wrapper is

A CLI wrapper is an ordinary Caspian class distributed at a `caspian.uno/linux/cli/{name}` URL that:

- **Wraps one utility.** One class per utility. `tar` and `zip` are separate wrappers even though both are archivers; the wrapper's name matches the underlying command.
- **Delegates all work to the utility itself.** The wrapper builds argv, calls `.execute`, and interprets the result. It does NOT link `libtar`, `libarchive`, or any C library. If the utility isn't installed on the host, the wrapper raises — it doesn't ship a fallback.
- **Never shells out.** `.execute` runs the utility directly (no `sh -c`); the wrapper composes argv arrays, not command strings. See [linux-support § Executing files](https://puck.uno/documentation/requirements/linux-support/#executing-files) for why.
- **Is user-role only.** `.execute` is user-only in V1 (see [linux-support § Executing from a directory](https://puck.uno/documentation/requirements/linux-support/#executing-from-a-directory)); wrappers inherit that restriction. Non-user roles can't invoke a wrapper at all, granted or not.

## Naming and URL layout

- **URL:** `caspian.uno/linux/cli/{name}` — bare name, matches the underlying command exactly (`tar`, `gzip`, `7z`). No prefix, no version, no `-wrapper` suffix.
- **Class:** the class object at that URL. Instantiate with `.new`.
- **Doc path:** this spec tree at [linux/cli/{name}](./) mirrors the URL structure.
- **File name on disk:** the command name is the file name — `tar.md`, `gzip.md`, `7z.md`.

Commands whose names collide with Caspian reserved words (rare, but conceivable) get a trailing underscore in the class name; the URL stays bare. Not currently blocking anything.

## Command-builder shape

The default shape for a wrapper is a **command builder** — instantiate, configure via property assignment, hand the built instance to `.execute`. Same pattern as the tar wrapper:

~~~caspian
$gzip = %('caspian.uno/linux/cli/gzip').new
$gzip.input = 'archive.txt'
$gzip.keep = true               # -k
$gzip.level = 9                 # -9

%fs.cwd.execute_in $gzip
~~~

Property names map to the utility's flags; the wrapper's design pass picks readable names for each. Boolean properties turn flags on when truthy; string / integer properties supply values for `-flag value` forms. Wrappers may also expose one-shot convenience methods (e.g. `.new.compress_string($bytes)` for gzip) when a common use case doesn't need the full builder.

Some wrappers deviate — a utility with a fundamentally different shape (streaming filter, stdin-heavy, no argv beyond mode selection) gets whatever shape fits it best. The command-builder pattern is the default; the design pass per wrapper documents any deviation.

## Prerequisite check

A wrapper doesn't check for the utility's presence eagerly. `%fs.execute` (or the dirjail's `.execute`) does the lookup by name; if the utility isn't installed, the resulting raise names it. Wrappers that want a friendlier error may probe `%fs.which('{name}')` (see [fs-additions](https://puck.uno/documentation/requirements/global-methods/fs-additions/)) at construction and raise with a package hint, but that's optional per wrapper.

## Wrapper index — priority order

Priority is the order the wrappers land in V1. Sub-pages are stubs until each gets its design pass; see each page for status.

1. [tar](tar) — archive create/extract with optional gzip/bzip2/xz compression.
2. [gzip](gzip) — single-file compression.
3. [gunzip](gunzip) — single-file decompression, symmetric with gzip.
4. [zip](zip) — multi-file zip-archive create.
5. [unzip](unzip) — zip-archive list/extract.
6. [file](file) — file type / MIME detection.
7. [cut](cut) — column extraction from tabular text.
8. [sort](sort) — line sort with numeric / reverse / key-based variants.
9. [uniq](uniq) — adjacent-duplicate collapse, with count / only-unique / only-repeated variants.
10. [uname](uname) — OS / architecture / kernel info.
11. [pandoc](pandoc) — document format converter (markdown / html / docx / pdf / etc.).
12. [convert](convert) — ImageMagick image format converter and transformer.
13. [7z](7z) — 7-Zip archive create / extract (multi-format).
14. [bzip2](bzip2) — bzip2 compression / decompression, symmetric with gzip.

### Outside the priority list

- [openssl](openssl) — ES256 / RS256 signature verify for the [Passkey subsystem](https://puck.uno/documentation/requirements/protected/passkey/). Predates the priority list; migrated in from `linux-support/` as the namespace consolidated.

## Prior-art notes

Two wrapper stubs also exist under [downloads/](https://puck.uno/documentation/requirements/downloads/) for [gzip](https://puck.uno/documentation/requirements/downloads/gzip) and [zip](https://puck.uno/documentation/requirements/downloads/zip); those flagged an unresolved Ships-tier decision (core vs download). This dir is where the per-wrapper specs live regardless of the eventual Ships tier.

## Related

- [linux-support](https://puck.uno/documentation/requirements/linux-support/) — general `.execute` model; the low-level primitive every wrapper here delegates to.
- [fs-additions](https://puck.uno/documentation/requirements/global-methods/fs-additions/) — `%fs.which`, `%fs.execute`, and related search-path surfaces the wrappers can use.
- [concepts § Lean on installed Linux utilities when they're better](https://puck.uno/documentation/requirements/concepts#lean-on-installed-linux-utilities-when-theyre-better) — the design principle these wrappers embody.
