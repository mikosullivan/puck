# bzip2

*Wraps the `bzip2` CLI utility — single-file Burrows-Wheeler compressor / decompressor. Class at `caspian.uno/linux/cli/bzip2`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_bzip2",
	"role": "spec for the bzip2 class at caspian.uno/linux/cli/bzip2 — command-builder wrapper around the `bzip2` CLI utility. Priority 14 in the CLI wrappers list. Same shape family as gzip; a single class handles both compress and decompress via a mode flag (bzip2 doesn't split into two commands the way gzip / gunzip do).",
	"status": "stub — method surface, mode-selection shape, `-t` test-only mode TBD",
	"audience": "developers producing / consuming .bz2 files; the bzip2 wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-z`** — compress (default when the command is `bzip2`).
- **`-d`** — decompress.
- **`-k`** — keep the source file (default replaces it).
- **`-{1..9}`** — compression / block-size level (`-9` slowest / smallest / most memory).
- **`-c`** — write to stdout.
- **`-t`** — test integrity without writing anything.
- **`-f`** — force overwrite of existing output.

## `bzip2` vs `bunzip2`

`bunzip2` is a synonym for `bzip2 -d`. The wrapper collapses both under the one `bzip2` class with a `mode` property (`:compress` / `:decompress` / `:test`), rather than splitting into two classes the way gzip / gunzip do. The one-command-two-modes shape matches how bzip2's own manpage presents it.

## Method surface

TBD. Builder with `input`, `output`, `mode` (`:compress` — default / `:decompress` / `:test`), `keep`, `level`, `to_stdout`, `force`; plus a one-shot `.compress_bytes` / `.decompress_bytes` for streaming.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [gzip](gzip), [gunzip](gunzip) — sibling compressors; two-class split there vs one-class-two-modes here reflects the underlying command shapes.
- [7z](7z) — multi-format tool that includes bzip2 support.
