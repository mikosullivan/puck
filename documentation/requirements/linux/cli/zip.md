# zip

*Wraps the `zip` CLI utility — multi-file PKZIP-format archive creator. Class at `caspian.uno/linux/cli/zip`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_zip",
	"role": "spec for the zip class at caspian.uno/linux/cli/zip — command-builder wrapper around the `zip` CLI utility. Priority 4 in the CLI wrappers list. Companion to unzip.md — creation and extraction are separate wrappers, matching the two-command Linux surface.",
	"status": "stub — method surface, glob handling (Caspian expands globs, zip receives the expanded list), compression-level naming TBD",
	"audience": "developers producing .zip archives; the zip wrapper author"
}}
~~~

Stub. A prior sketch lives at [downloads/zip](https://puck.uno/documentation/requirements/downloads/zip); this spec supersedes it once the design pass lands.

## Common flags to expose

- **`-r`** — recurse into directories.
- **`-{0..9}`** — compression level (`-0` stores without compressing; `-9` slowest / smallest).
- **`-q`** — quiet.
- **`-u`** — update (add / replace only newer or missing entries).
- **`-x <patterns>`** — exclude patterns.

## Method surface

TBD. Builder with `archive`, `sources`, `recurse`, `level`, `update`, `exclude`. Glob expansion happens on the Caspian side before `.execute` runs — `zip` receives a concrete file list, not `*.txt` (`.execute` doesn't shell out, so globs would be literal otherwise).

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [unzip](unzip) — extraction companion.
- [downloads/zip](https://puck.uno/documentation/requirements/downloads/zip) — earlier stub, superseded here.
