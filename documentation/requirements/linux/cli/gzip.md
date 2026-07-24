# gzip

*Wraps the `gzip` CLI utility — single-file DEFLATE compressor. Class at `caspian.uno/linux/cli/gzip`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_gzip",
	"role": "spec for the gzip class at caspian.uno/linux/cli/gzip — command-builder wrapper around the `gzip` CLI utility. Priority 2 in the CLI wrappers list. Companion to gunzip.md (decompression is a distinct wrapper, matching the two-command Linux surface).",
	"status": "stub — method surface, streaming shape, and compression-level naming TBD",
	"audience": "developers gzipping files or byte streams; the gzip wrapper author"
}}
~~~

Stub. A prior sketch lives at [downloads/gzip](https://puck.uno/documentation/requirements/downloads/gzip) — it flags an unresolved Ships-tier decision (core binary vs downloadable class); this spec supersedes it once the design pass lands, regardless of tier.

## Common flags to expose

- **`-k`** — keep the source file (default is to replace it with the `.gz`).
- **`-{1..9}`** — compression level; `-9` is slowest / smallest, `-1` is fastest / largest.
- **`-c`** — write to stdout instead of replacing the file.
- **`-r`** — recurse into directories.

## Method surface

TBD. Likely a builder with `input`, `keep`, `level`, and a `to_stdout` toggle; plus a one-shot `.compress_bytes($bytes)` for streaming through the utility.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [gunzip](gunzip) — decompression companion.
- [downloads/gzip](https://puck.uno/documentation/requirements/downloads/gzip) — earlier stub, superseded here.
