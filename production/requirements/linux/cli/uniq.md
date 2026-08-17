# uniq

*Wraps the `uniq` CLI utility — adjacent-duplicate-line collapse, with count / only-unique / only-repeated variants. Class at `caspian.uno/linux/cli/uniq`.*

~~~vibecode
{"vibecode": {
	"doc": "requirements_linux_cli_uniq",
	"role": "spec for the uniq class at caspian.uno/linux/cli/uniq — command-builder wrapper around the `uniq` CLI utility. Priority 9 in the CLI wrappers list. Companion to sort — `uniq` only looks at ADJACENT duplicates, so it's almost always downstream of sort.",
	"status": "stub — method surface, mode selection (count / only-unique / only-repeated / show-all), field-skipping shape TBD",
	"audience": "developers deduplicating sorted line-oriented data; the uniq wrapper author"
}}
~~~

Stub.

## Common flags to expose

- **`-c`** — prefix each line with its occurrence count.
- **`-d`** — output only the lines that were repeated (drop uniques).
- **`-u`** — output only the lines that appeared exactly once.
- **`-i`** — case-insensitive compare.
- **`-f <n>`** — skip the first `n` fields before comparing.
- **`-s <n>`** — skip the first `n` characters before comparing.

## Method surface

TBD. Builder with `input`, `output`, `mode` (`:collapse` — default / `:count` / `:repeated` / `:unique`), `case_insensitive`, `skip_fields`, `skip_chars`.

**Adjacency-only reminder.** `uniq` doesn't sort — it collapses runs. Callers deduplicating an unsorted file need to `sort | uniq` in Caspian (or use `sort` with `-u`).

## Testing

TBD.

## Related

- [Linux CLI wrappers](./) — general pattern.
- [sort](sort) — upstream companion.
