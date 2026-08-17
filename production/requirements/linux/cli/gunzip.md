# gunzip

*Wraps the `gunzip` CLI utility — decompressor symmetric with gzip. Class at `caspian.uno/linux/cli/gunzip`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_gunzip",
	"role": "spec for the gunzip class at caspian.uno/linux/cli/gunzip — command-builder wrapper around the `gunzip` CLI utility. Priority 3 in the CLI wrappers list. Kept as a distinct class from gzip to mirror the two-command Linux surface.",
	"status": "stub — method surface, keep / to_stdout naming, and error surface TBD",
	"audience": "developers gunzipping files or byte streams; the gunzip wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-k`** — keep the `.gz` source file (default deletes it).
- **`-c`** — write to stdout instead of writing a file.
- **`-t`** — test integrity without extracting.
- **`-r`** — recurse into directories.

## Method surface

TBD. Likely a builder with `input`, `keep`, `to_stdout`, `test_only`; plus a one-shot `.decompress_bytes($bytes)` for round-tripping without touching disk.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [gzip](gzip) — compression companion.
