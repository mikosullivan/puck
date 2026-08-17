# cut

*Wraps the `cut` CLI utility — column / field / byte extraction from line-oriented text. Class at `caspian.uno/linux/cli/cut`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_cut",
	"role": "spec for the cut class at caspian.uno/linux/cli/cut — command-builder wrapper around the `cut` CLI utility. Priority 7 in the CLI wrappers list. Useful for extracting columns from delimited text without pulling in a full CSV parser.",
	"status": "stub — method surface, range-syntax translation (Caspian arrays / ranges vs cut's `1,3,5-7`), delimiter-handling defaults TBD",
	"audience": "developers slicing columns out of TSV / CSV / whitespace-delimited text; the cut wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-f <list>`** — extract fields (comma / range list).
- **`-d <char>`** — field delimiter (default is TAB).
- **`-c <list>`** — extract character positions.
- **`-b <list>`** — extract byte positions.
- **`--complement`** — invert the selection (keep everything NOT listed).
- **`--output-delimiter=<char>`** — override the output separator.

## Method surface

TBD. Builder with `fields` (array of integers, or a range), `delimiter`, `mode` (`:field` / `:char` / `:byte`), `complement`, `output_delimiter`. Range translation: `1..3` maps to `1-3`; discontinuous `[1, 3, 5..7]` maps to `1,3,5-7`.

For heavy CSV work, prefer a real CSV class ([downloads/csv](https://puck.uno/requirements/downloads/csv)) — `cut` doesn't understand quoted fields.

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [sort](sort) / [uniq](uniq) — common downstream companions.
