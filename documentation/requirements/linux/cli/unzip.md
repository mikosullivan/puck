# unzip

*Wraps the `unzip` CLI utility — PKZIP-format archive extractor. Class at `caspian.uno/linux/cli/unzip`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_unzip",
	"role": "spec for the unzip class at caspian.uno/linux/cli/unzip — command-builder wrapper around the `unzip` CLI utility. Priority 5 in the CLI wrappers list. Extraction companion to zip.md.",
	"status": "stub — method surface, list-vs-extract split, encrypted-archive handling TBD",
	"audience": "developers extracting .zip archives; the unzip wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-l`** — list contents without extracting.
- **`-d <dir>`** — extract into `<dir>`.
- **`-o`** — overwrite without prompting.
- **`-n`** — never overwrite.
- **`-q`** — quiet.
- **`-P <password>`** — password for encrypted archives.

## Method surface

TBD. Builder with `archive`, `into`, `list_only`, `overwrite` (tri-state: `:prompt` / `:always` / `:never`), `password`. The list-vs-extract split is prominent enough to warrant either two methods (`.list` and `.extract`) or a mode property.

Passwords surfaced through this wrapper should route through the [Password class](https://puck.uno/documentation/requirements/secure-memory/password/) rather than being handed as plain strings on the argv (the argv is visible in `ps` for the duration of the call — a real leak).

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [zip](zip) — creation companion.
