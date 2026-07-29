# uname

*Wraps the `uname` CLI utility — OS / architecture / kernel identification. Class at `caspian.uno/linux/cli/uname`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_uname",
	"role": "spec for the uname class at caspian.uno/linux/cli/uname — command-builder wrapper around the `uname` CLI utility. Priority 10 in the CLI wrappers list. Cheap and side-effect-free; the natural default is a single all-fields call returning a structured record.",
	"status": "stub — method surface (all-fields structured record vs per-flag getters) TBD",
	"audience": "developers detecting host OS / architecture; the uname wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-a`** — all fields at once (the default the wrapper probably wants).
- **`-s`** — kernel name (e.g. `Linux`).
- **`-n`** — hostname.
- **`-r`** — kernel release.
- **`-v`** — kernel version.
- **`-m`** — machine hardware (e.g. `x86_64`, `aarch64`).
- **`-p`** — processor type.
- **`-i`** — hardware platform.
- **`-o`** — operating system (e.g. `GNU/Linux`).

## Method surface

TBD. Simplest useful shape: `.info` returns a record `{kernel, hostname, release, version, machine, processor, platform, os}` from one `uname -a` call, plus individual accessors (`.machine`, `.os`, etc.) that call the same info under the hood and return a single field. No builder needed for a one-shot read like this.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [Installation § OS checks](https://puck.uno/requirements/installation/os-checks/) — the install-time consumer that most cares about kernel/OS.
