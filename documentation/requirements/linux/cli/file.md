# file

*Wraps the `file` CLI utility — content-based file type / MIME detection. Class at `caspian.uno/linux/cli/file`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_file",
	"role": "spec for the file class at caspian.uno/linux/cli/file — command-builder wrapper around the `file` CLI utility. Priority 6 in the CLI wrappers list. Distinct from filename-extension guessing — `file` inspects the actual bytes and matches against the libmagic database.",
	"status": "stub — method surface, MIME-vs-description mode selection, stdin-piping shape TBD",
	"audience": "developers detecting file types by content; the file wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`--mime-type`** — output the MIME type only (e.g. `text/plain`).
- **`--mime-encoding`** — output the encoding only (e.g. `utf-8`).
- **`-i` / `--mime`** — output MIME type and encoding together.
- **`-b` / `--brief`** — omit the filename prefix from the output.
- **`-`** — read from stdin.

## Method surface

TBD. Likely a one-shot `.type_of($path)` returning a structured result (`{mime, encoding, description}`) rather than the builder pattern — the common case is "give me the MIME type of this file" and doesn't benefit from the accumulate-and-execute shape.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [String § content_type](https://puck.uno/documentation/requirements/built-in-classes/primitives/string/) — the accessor consumers of `file`'s output populate.
