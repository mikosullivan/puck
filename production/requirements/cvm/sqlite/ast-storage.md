# AST storage: JSON, not JSONB

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm_ast_storage",
	"role": "design note pinning the frame_ast column's storage format at JSON text rather than SQLite JSONB, with the rationale for that choice given how the engine actually accesses the column. Applies to objects.frame_ast — biconditional with control = 'f', so every frame row carries the code it's executing.",
	"status": "V1 spec"
}}
~~~

CVM stores CaspM ASTs as **JSON text**, not SQLite's binary [JSONB](https://sqlite.org/jsonb.html) format.

## Access pattern

The engine's access to a `frame_ast` blob is once-per-frame-lifetime, not query-heavy:

1. Frame is pushed (an `objects` row with `control = 'f'` and `frame_ast` set).
2. Engine reads the ast blob once (`select frame_ast from objects where object_pk = ?`).
3. Engine decodes it into a Lua-native representation and walks that representation for the frame's lifetime.
4. Frame pops.

No SQL-side JSON operations (`json_extract`, `json_type`, etc.) fire against the ast. Nothing at the SQL layer queries "does this ast contain an `if` atom" — that's engine-side logic operating on the decoded Lua tables.

## Where JSON wins under this pattern

- **One fewer decoding hop in Lua.** `select frame_ast from objects where object_pk = ?` returns text; `dkjson.decode(text)` produces the Lua table. JSONB requires `select json(frame_ast) from objects ...` to convert to text first, then decode — the SQLite-side conversion is pure overhead when the destination is Lua anyway.
- **Inspectable via `sqlite3` CLI.** `select frame_ast from objects where …` prints readable JSON directly. With JSONB, the CLI shows a binary blob unless the query wraps in `json(frame_ast)`.

## Where JSONB would win, but doesn't apply here

- **Storage size** — JSONB is typically 5-10% smaller. Real but small at the AST sizes we'll see.
- **Repeated SQL-side JSON access** — JSONB avoids the reparse-per-call cost of text JSON when the same blob is queried many times at the SQL layer. Caspian's pattern reads the blob once per frame; no compounding.

The storage savings are not worth the extra decoding step + loss of CLI inspectability. If a future feature actually queries into `frame_ast` blobs from SQL (e.g., "find every callable that references function `foo`" via `json_extract`), JSONB becomes worth reconsidering. Not before.

## Column type

Declared as `text` in the schema, not `blob`. Both work — SQLite's type affinity accepts JSON either way — but `text` documents intent (this is text-format JSON) and makes SQLite's CLI display readable.

Applies to `objects.frame_ast` — biconditional with `control = 'f'`: every frame row carries the CaspM tree it's executing; every non-frame row leaves it null. Functions and closures store their CaspM in their bucket (as plain `base = 'o'`, `control = null` objects), not in a `frame_ast` column of their own; calling one creates a fresh `control = 'f'` row and copies the CaspM into its `frame_ast`.
