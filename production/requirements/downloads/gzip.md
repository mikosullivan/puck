# Gzip

~~~vibecode
{"vibecode": {
	"doc": "requirements_v1_downloads_gzip",
	"role": "spec for the Gzip class at `caspian.uno/linux/gzip.casp` — Ships: no, Day 1: yes. Wrapping-style shellout around the `gzip` / `gunzip` Linux utilities. Same posture as zip. NOTE: the stdlib-suggestions review currently lists gzip as Ships=yes (core class); moving it to a v1-download is a scope reduction that needs your confirmation.",
	"status": "stub — needs class-surface design AND a Ships-tier decision (core vs download)",
	"audience": "developers gzipping / gunzipping byte streams and files; anyone writing the Gzip class spec"
}}
~~~

Stub. First-party download at `caspian.uno/linux/gzip.casp` — gzip compress/decompress helpers on strings, byte sequences, and file handles.

## Ships-tier call to make

TBD. The stdlib-suggestions review currently has gzip at `Ships: yes` (in the core binary). Putting it under v1-downloads implies moving it to `Ships: no`. Both are viable:
- **Ships: yes (core).** Gzip is small, everywhere, and rides on the same utility any Caspian install already has via `tar -z`. Bundling costs almost nothing.
- **Ships: no (download).** Consistent with zip's posture; keeps the core binary lean; the byte-cache handles the on-demand fetch once.

## What gzip is

TBD. The universal single-file compressor. Wrap format around the DEFLATE algorithm.

## Method surface

TBD. String → String round-trip; file → file; streaming variant for large data.

## Testing

TBD.

## Related

- [Zip](zip) — same shellout-wrapper pattern, same tier.
- [Tar](https://puck.uno/requirements/linux/cli/tar) — related shellout wrapper.
