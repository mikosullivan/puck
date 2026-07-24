# sort

*Wraps the `sort` CLI utility — line-oriented sort with numeric / key-based / reverse variants. Class at `caspian.uno/linux/cli/sort`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_sort",
	"role": "spec for the sort class at caspian.uno/linux/cli/sort — command-builder wrapper around the `sort` CLI utility. Priority 8 in the CLI wrappers list. Useful for bulk external sorts (larger than fits comfortably in memory) — small in-memory sorts are Array.sort's job.",
	"status": "stub — method surface, key-syntax translation (`-k <start>[.<char>][,<end>[.<char>]]` is a small DSL of its own), locale-collation-off default TBD",
	"audience": "developers sorting large text files; the sort wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-n`** — numeric sort.
- **`-r`** — reverse.
- **`-u`** — unique (drop adjacent duplicates in the output).
- **`-k <field-spec>`** — sort by a specific field / key range.
- **`-t <char>`** — field separator.
- **`-h`** — human-readable numeric sort (`1K`, `2M`, `3G`).
- **`-V`** — version-string sort (`1.2.10` after `1.2.9`).
- **`--stable`** — stable sort.
- **`-o <file>`** — write result to file (safe with the same file as input).

## Method surface

TBD. Builder with `input`, `output`, `numeric`, `reverse`, `unique`, `key`, `separator`, `mode` (`:default` / `:human` / `:version` / `:month`), `stable`. The `-k` key syntax is a small DSL of its own and needs a Caspian shape (probably `{field: N, char: N, end_field: N, end_char: N}` per key entry).

**Locale note.** `sort`'s default collation is locale-sensitive — running under `C` / `en_US.UTF-8` / a different locale produces different orderings for the same input. The wrapper should default to `LC_ALL=C` for byte-value sort unless the caller opts in to locale collation, because "sort the file" without further qualifier usually means "predictable byte order."

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [uniq](uniq) — common downstream companion.
- [cut](cut) — often runs upstream of sort.
