# AST storage: JSON, not JSONB

~~~vibecode
{"vibecode": {
	"doc": "requirements_mvm_ast_storage",
	"role": "design note pinning the ast column's storage format at JSON text rather than SQLite JSONB, with the rationale for that choice given how the engine actually accesses the column. Applies to objects.ast (callable definitions) and to any frame-local ast column the design lands.",
	"status": "V1 spec"
}}
~~~

MVM stores CaspM ASTs as **JSON text**, not SQLite's binary [JSONB](https://sqlite.org/jsonb.html) format.

## Access pattern

The engine's access to an ast blob is once-per-frame-lifetime, not query-heavy:

1. Frame is pushed.
2. Engine reads the ast blob once (`select ast from ...`).
3. Engine decodes it into a Lua-native representation and walks that representation for the frame's lifetime.
4. Frame pops.

No SQL-side JSON operations (`json_extract`, `json_type`, etc.) fire against the ast. Nothing at the SQL layer queries "does this ast contain an `if` atom" — that's engine-side logic operating on the decoded Lua tables.

## Where JSON wins under this pattern

- **One fewer decoding hop in Lua.** `select ast from frames` returns text; `dkjson.decode(text)` produces the Lua table. JSONB requires `select json(ast) from frames` to convert to text first, then decode — the SQLite-side conversion is pure overhead when the destination is Lua anyway.
- **Inspectable via `sqlite3` CLI.** `select ast from objects where …` prints readable JSON directly. With JSONB, the CLI shows a binary blob unless the query wraps in `json(ast)`.

## Where JSONB would win, but doesn't apply here

- **Storage size** — JSONB is typically 5-10% smaller. Real but small at the AST sizes we'll see.
- **Repeated SQL-side JSON access** — JSONB avoids the reparse-per-call cost of text JSON when the same blob is queried many times at the SQL layer. Caspian's pattern reads the blob once per frame; no compounding.

The storage savings are not worth the extra decoding step + loss of CLI inspectability. If a future feature actually queries into ast blobs from SQL (e.g., "find every callable that references function `foo`" via `json_extract`), JSONB becomes worth reconsidering. Not before.

## Column type

Declared as `text` in the schema, not `blob`. Both work — SQLite's type affinity accepts JSON either way — but `text` documents intent (this is text-format JSON) and makes SQLite's CLI display readable.

Applies to:

- `objects.ast` — CaspM tree for callables. Nullable (non-callable rows have null).
- Any future frame-local ast column that lands under this design.
