# Skill: building a web server in Lua

~~~vibecode
{"vibecode": {
	"doc": "skill_lua_web_server",
	"role": "guidance document for AI assistants (primarily Claude Code) helping Miko build or extend a Lua-based web server. Captures the patterns that have worked in his existing servers, the preferences he holds about Lua and HTTP, and the shape of a competent V1 implementation. Read this file before starting to write server code so you don't fight against decisions that have already been made elsewhere.",
	"audience": "Claude Code sessions working on Miko's Lua web server projects. Also useful to Miko as a settled-decisions reference.",
	"status": "guidance — patterns from existing working servers, not a spec"
}}
~~~

Miko has a working Lua web server: [Orlando](https://puck.uno/documentation/) inside the puck project, at `orlando/lua/`. It serves puck.uno's rendered documentation, an issues dashboard, a search endpoint, and an inline edit surface. Read Orlando's code before starting anything new — most decisions have already been made and the patterns are proven.

## Lua version

**Use `lua5.4` explicitly, never bare `lua`.** On systems with multiple Lua versions installed, `lua` can resolve to an older interpreter and break things silently. Every launcher, every test-runner invocation, every shebang line: `lua5.4`.

Reference: the same rule appears in the puck project's CLAUDE.md.

## Server pattern: no framework

**No `openresty`, no `lapis`, no `sailor`, no framework layer.** Miko's servers use plain LuaSocket (or equivalent) and handle HTTP parsing directly. The reason: web frameworks add opinions and dependencies that are more expensive than the code they save. A Lua server that reads request lines and dispatches on path is 200 lines of Lua and stays understandable.

Orlando's shape:

- `orlando/lua/serve.lua` — command-line entry point. Sets `package.path`, then calls `orlando.server.serve(port)`.
- `orlando/lua/orlando/server.lua` — the request loop: accept, read, parse, dispatch, respond, close.
- `orlando/lua/orlando/route.lua` — path-to-handler dispatch.
- One module per major surface (`page.lua`, `search.lua`, `issues.lua`, `api.lua`, `random.lua`, etc.).

Prefer this shape unless there's a specific reason not to.

## HTTP handling

**Request parsing.** Read the request line (`GET /path HTTP/1.1`), then headers until a blank line, then body if `Content-Length` is set. Percent-decode the path. Split path from query string on `?`. This is boring code; write it directly.

**Response construction.** Build the response as `status_line + "\r\n" + headers + "\r\n\r\n" + body` and send in one write when practical. Content-Length is always set for finite responses.

**Content types.** Keep a small map from extension to MIME type (`html`, `css`, `js`, `json`, `svg`, `png`, `ico`, `woff2`, etc.). Fall back to `application/octet-stream`. Orlando's `content_type.lua` is the pattern.

## Static assets

Put static files under `client-assets/` (or equivalent) and serve them with a single handler that:

- Rejects paths escaping the assets directory (`..` handling).
- Rejects non-normalized paths (`//`, leading `/`).
- Reads the file, sets `Content-Type` from the extension, sets `Cache-Control` appropriately.
- Returns 404 on missing files.

Never serve arbitrary paths from the filesystem. Only whitelisted directories.

## Security posture

**Content Security Policy (CSP) is strict.** Miko's convention: `img-src 'self'; style-src 'self'; script-src 'self'`. That forbids inline `<style>`, inline `<script>`, `style="..."` attributes, and `onclick="..."` attributes. Everything visual lives in loaded CSS files under `client-assets/`; everything interactive lives in loaded JS files under `client-assets/`.

If you find yourself wanting to emit inline styles or scripts, stop. Add a class to a loaded stylesheet or extend a loaded JS file. This is a hard rule.

**No credentials in code or version control.** `settings.json` at the repo root is gitignored; DB credentials, API tokens, and any secrets live there. Never commit that file.

## Persistence patterns

**SQLite for structured data.** Miko has an active project (`sbarks`) using per-user SQLite databases. One file per user, atomic writes, no shared-DB coordination overhead. The pattern is well-suited to Lua (`luasql-sqlite3` or `lsqlite3` bindings work).

**File-based cache for small persistent state.** Orlando caches GitHub issues in `~/.orlando/issues-cache.json` — atomic write via `tmp file + rename`, in-memory copy loaded on first access. This pattern is simple and reliable for a single-process server.

**No database for what a file can do.** If the state is one JSON blob updated occasionally, use a file. If it's row-shaped with queries, use SQLite. Don't reach for Postgres or Redis unless there's a specific reason.

## Testing

**Custom minimal runner.** Orlando's pattern is `tests/support/runner.lua` + `tests/support/assert.lua` — three functions (`suite`, `test`, `report`), a handful of assertions (`equal`, `is_true`, `not_nil`, `count`, etc.). This is 60 lines of Lua and gives you what a test framework does without the layers.

**Run from repo root:**

```
lua5.4 tests/run.lua
```

`tests/run.lua` sets `package.path` to resolve `require("your_module")` against your source tree, then `require`s each test file, then calls `runner.report()`. Exit 0 on all-pass, 1 on any-fail.

**Two tiers if applicable.** Engine-level tests (fast, no network, no filesystem) plus integration tests (real requests to a running server). Keep them separate; run engine tests on every change, integration tests when the surface changes.

## Style preferences

These apply to any Lua code you write in one of Miko's projects. If the project has a `.claude/skills/format/` skill, that overrides — but these are the defaults:

- **Tabs for indentation.** Not spaces. Not mixed.
- **Multi-line blocks separated from surrounding code by blank lines** on both sides when the block sits inside a scope with sibling statements.
- **Explicit `return` from every function**, even when the value is `nil`. Implicit returns are for the last expression in a REPL, not in a function body.
- **Module header block** at the top of every Lua source file — a JSON literal in a Lua comment describing `role`, `exports`, `pipeline`, and dependencies. See any Orlando module for the shape.
- **Per-function header** describing `in`, `out`, `note` where the signature isn't self-explanatory.
- **Prefer hashes over arrays** when order matters AND each item might want metadata later.

## Things to avoid

- **Frameworks.** Lapis, Sailor, Orbit, etc. Miko has explicitly rejected them.
- **Nginx + OpenResty coupling.** Miko's servers run standalone under `nohup` on `127.0.0.1:<port>` behind a plain nginx proxy that only forwards — no Lua inside nginx.
- **Session-middleware libraries.** If you need sessions (cookie + login + per-request identity), implement them directly — a signed session cookie and a small lookup table is straightforward Lua. Framework layers add opinions and dependencies that aren't worth what they save.
- **Automatic form parsing frameworks.** Percent-decode the body directly. It's 20 lines.
- **Templating engines.** Miko's servers build HTML by direct string construction (through a small builder like Orlando's `quick_builder.lua` if useful). Templates add a compile step and a mental context switch.
- **ORM layers.** SQLite is fine. Direct queries are fine. `luasql-sqlite3` bindings are fine. Reach for ORMs only if the schema surface justifies it.

## When to break from Orlando's patterns

Orlando is a documentation server; it doesn't handle POST-heavy workloads, real user auth, or streaming responses. If you're building something with different constraints:

- **Real user login** — you'll need session tokens (signed JWTs or similar) and a login endpoint. Orlando doesn't have this; look elsewhere for reference.
- **Streaming or SSE** — Orlando reads the whole response into memory before sending. Streaming needs a different write pattern.
- **WebSockets** — Orlando has no WebSocket support. Adding it requires a real socket-upgrade path and frame-parsing.
- **File uploads** — Orlando accepts only tiny form-encoded POSTs. Multi-megabyte uploads need chunked reading.

Each of these is a real V1 concern for some projects. Note the shape when you hit it and ask Miko for the specific decision — don't just port whatever a framework would give you.

## Where to look

- Orlando source: `orlando/lua/` in the puck project.
- Miko's user-level preferences: [~/CLAUDE.md](file://home/miko/CLAUDE.md) — communication, workflow, and engineering principles that apply everywhere.
- Miko's formatter spec: [miko.json](https://puck.uno/documentation/ecoverse/formatting/miko.json) — indent, line rules, per-language overrides.
