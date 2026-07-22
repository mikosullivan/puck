# Zip

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_v1_downloads_zip",
	"role": "spec for the Zip class at `caspian.uno/linux/zip.casp` — Ships: no, Day 1: yes. Wrapping-style shellout around the `zip` / `unzip` Linux utilities (same posture as `caspian.uno/linux/tar.casp`, which ships in core rather than as a download).",
	"status": "stub — needs class-surface design",
	"audience": "developers packaging/unpacking .zip archives; anyone writing the Zip class spec"
}}
~~~

Stub. First-party download at `caspian.uno/linux/zip.casp` — read and write zip archives. Wraps the standard `zip` / `unzip` Linux utilities, matching the shellout style used by [tar](https://puck.uno/documentation/requirements/caspian/linux-support/tar) in core.

## What zip is

TBD. Ubiquitous archive-plus-compression format; better than tar for cross-platform (Windows users expect it), worse than tar for streaming (central directory sits at the end of the file).

## Method surface

TBD. Mirrors tar's class shape as closely as makes sense — `.create`, `.extract`, `.list`, entry iteration.

## Testing

TBD.

## Related

- [Tar](https://puck.uno/documentation/requirements/caspian/linux-support/tar) — same shellout-wrapper pattern, in core rather than as a download.
