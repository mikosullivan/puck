~~~vibecode
{"doc": "sprint-index", "sprint": "end-to-end",
	"role": "Run an empty script end to end. No AST to run (or maybe an empty array), but the process goes to completion. Rewrite run() so the ast-walk is driven by reading + advancing stmt_idx in the DB rather than an in-memory Lua for-each loop, so 'frame done' becomes a discrete checkable point where the frame gets closed.",
	"status": "brainstorm"}
~~~

# end-to-end

Run an empty script end to end. There's no AST to run — or maybe it's an empty array — but the process goes to completion. We haven't done that yet.

Related, and required to make "completion" observable: the ast walk in `engine:run()` currently uses a Lua-side `for _, row in ipairs(cjson.decode(ast_json)) do` — the frame's entire ast gets decoded once into a Lua table and walked with a hidden Lua counter. The DB's `stmt_idx` column is never read or advanced. This sprint rewrites that walk to be `stmt_idx`-driven from the DB so "frame is done" becomes a discrete condition (stmt_idx past max) at which we close the frame.
