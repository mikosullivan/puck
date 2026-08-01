# A procedural-language extension for SQLite, written in Lua

~~~vibecode
{"vibecode": {
	"doc": "ideas_sqlite_lua_procs",
	"role": "Idea for a SQLite loadable extension that provides a stored-procedure language (variables, IF, LOOP, exceptions, SQL bridge) — implemented in Lua embedded inside a C shim, distributed as a single .so/.dll. Two flavors: a generic Lua-procs surface for the wider SQLite world, and a Caspian-specific surface (PlCaspian) that brings Caspian's role-based security model and stdlib into SQL stored procedures. Fills a longstanding gap in SQLite's ecosystem; motivated by pain points from Fiona's trigger-body limitations.",
	"status": "idea — not scheduled, not planned as part of Fiona's V1",
	"scope": "hypothetical standalone project; would live outside the Caspian repo if pursued"
}}
~~~

## The gap this fills

SQLite has a minimalist philosophy — no stored procedures, no PL/pgSQL equivalent, no built-in scripting language. Its trigger bodies are limited to `INSERT` / `UPDATE` / `DELETE` / `SELECT` statements with no loops, no variables beyond `OLD`/`NEW`, and no control flow beyond `CASE`-in-`SELECT`.

That's a deliberate design choice — SQLite embeds into an application whose host language IS the procedural layer. But it leaves a real hole for cases where:

- Complex logic naturally belongs at the DB layer (integrity invariants that must hold regardless of caller).
- Multiple client languages need the same procedural behavior without each reimplementing.
- The DB is used through tools like the `sqlite3` CLI where there's no obvious "host language."

Postgres addresses this with PL/pgSQL and friends. SQLite has no equivalent, and after years of the extension mechanism being available, no one has built one that stuck.

## The idea

A single loadable SQLite extension (`.so` / `.dll`) that provides a stored-procedure language:

- `CREATE PROCEDURE name(args) LANGUAGE lua BODY $$ ... $$` (or similar syntax) — registers a procedure.
- `CALL name(args)` — invokes it from SQL.
- Callable from `SELECT` or from within trigger bodies for more expressive triggers.
- Standard procedural constructs: variables, `IF`/`THEN`/`ELSE`, `LOOP`/`WHILE`/`FOR`, exception raise + catch, SQL execution from within procedures with result access.

Under the hood, the extension embeds a Lua interpreter and stores procedure bodies as Lua code (or a small DSL that compiles to Lua). No fork of SQLite itself; just an extension anyone can `.load`.

## Alternative flavor: PlCaspian

The same architecture supports a Caspian-specific variant, modeled on Postgres' `PL/Perl`, `PL/Python`, `PL/V8`. Instead of a generic Lua proc-language, define stored procedures directly in Caspian:

~~~sql
CREATE PROCEDURE double_value(v INT)
LANGUAGE caspian
BODY $$
	return $v * 2
$$;

SELECT double_value(21);  -- 42
~~~

Since Caspian's engine is itself Lua-based, the extension is the same C shim + embedded Lua interpreter — just with Caspian's engine and stdlib loaded on top of Lua. Users who already know Caspian bring their language expertise into a database context.

**What Caspian brings that generic Lua doesn't:**

- **Role-based security model.** Procedures can run under specific roles; untrusted stored procs can be executed without giving them full database authority. Distinguishes PlCaspian from PL/Perl or PL/Python (which run with the DB user's authority — a real security concern for untrusted code).
- **Curated stdlib.** Caspian's built-in classes (Password, Passkey, JSON parsing, etc.) are available in procedures without additional setup.
- **The Puck object protocol.** Procedures can `%fetch` remote objects, letting DB procs call across systems in a first-class way.
- **Familiar syntax for Caspian users.** No context switch between application code and DB procedures.

**Same library, two surfaces?** Since both extensions embed a Lua interpreter and expose SQL-side procedure creation, they could be sibling projects or a single `.so` with two language dispatchers (`LANGUAGE lua` vs `LANGUAGE caspian`). Design decision if the project ever happens.

**Practical use case:** Fiona's own trigger complexity would evaporate. The arithmetic hop, the ordering-dependent naive UPDATE, the parking dance — all replaceable with straightforward Caspian procedures called from triggers. No unique-constraint choreography, no undocumented planner reliance. Fiona-in-Caspian would be a natural coupling.

## Architecture

~~~
[sqlite-lua-procs.so / .dll]
├── SQLite extension boilerplate (C, ~200 lines)
│    Registers the CALL / CREATE PROCEDURE surfaces as SQLite UDFs.
├── Statically-linked Lua interpreter (~200 KB compiled)
├── Thin C bridge — Lua ↔ SQLite C API (a few hundred lines)
│    Lets Lua code call sqlite3_prepare / step / finalize and get
│    results back as Lua tables.
└── Embedded Lua source, precompiled to bytecode:
     ├── proc runtime (parse, AST, interpret)
     ├── variable scoping / call stack
     ├── exception model
     └── SQL bridge helpers
~~~

At `.load` time, the C shim initializes a Lua state, loads the embedded proc runtime, and registers the SQL-facing entry points. All the language work happens in Lua code inside the .so.

## Why Lua-first (vs pure C)

- **Time to v1:** 2–3 months for a competent dev vs ≈12+ months for a pure-C implementation of the same shape. Language work is where Lua's productivity beats C most.
- **Binary size stays modest.** Full Lua runtime plus proc runtime lands around 300–500 KB. Under Fiona's own floppy-budget scale, this is a small dep.
- **Portability comes free.** Lua runs everywhere SQLite does.
- **Fixable.** Bugs in the proc runtime are bugs in Lua code inside the .so; fix cycle is short compared to C-level bugs.

## Trade-offs to name

- **Runtime overhead per proc call** — crossing the C ↔ Lua boundary and running interpreted code adds latency. Fine for typical stored-proc use; not competitive with pure-C UDFs for high-frequency SQL functions.
- **Debugging.** Mixed C-and-Lua stack traces on crash are less friendly than either pure-C or pure-Lua.
- **License compatibility.** Lua is MIT — compatible with everything commonly used with SQLite.
- **Not a fork.** Extensions can be loaded selectively per connection; no impact on SQLite users who don't want it.

## Prior art

- **PL/Python and PL/V8 for Postgres** — same architecture (embed a language interpreter, expose via extension). Widely used, well-understood pattern.
- **SQLite extensions in general** — the `.load` mechanism is stable and well-documented. Extensions like SQLean prove the ecosystem can support useful additions.
- **Fossil (SQLite team's own DVCS) uses Tcl** as an embedded scripting layer. The SQLite team is on record as friendly to "embed a scripting language" patterns.
- **lsqlite3 and other Lua SQLite bindings** exist but require client-side Lua wiring. This extension flips that around — Lua lives INSIDE the .so, no client-side setup.

## Effort estimate

- **v1** (basic constructs, works on Linux/macOS/Windows, decent error messages): 2–3 months for a competent dev familiar with both Lua and SQLite's C API.
- **Production quality** (thread safety, comprehensive error handling, test suite, docs): 6–12 months.
- **Ongoing maintenance:** Lua and SQLite are both very stable, so upkeep is minimal after v1.

## Realistic adoption path

SQLite users tend to stick with what ships, so a new extension takes time to gain traction. Realistic path:

1. Build v1 as an open-source project on GitHub (SQLite's community mostly lives on sqlite.org/forum, but discoverability for tooling is easier on GitHub).
2. Announce on the SQLite forum with clear framing: "here's a stored-procedure language, distributed as an extension, `.load` and go."
3. Publish binaries for common platforms. Users won't build from source.
4. Wait for word of mouth. If it solves real pain (and it should), a real user base shows up over 1–2 years.

## Relationship to Fiona

Motivated by Fiona's trigger-body pain (arithmetic hop, undocumented UPDATE ordering, no loops), but not a dependency. Fiona ships with Lua as its procedural layer via lsqlite3 — that already covers Fiona's own needs. This library would be its own project, potentially years of maintenance work, valuable to the wider SQLite ecosystem but not blocking Caspian in any way.

## Why this might be worth building

Beyond filling a gap in SQLite's ecosystem, several angles make PlCaspian specifically worth the investment (as opposed to the generic Lua-procs variant):

**The security angle is genuinely novel.** Every PL/* extension available today — PL/Perl, PL/Python, PL/V8, PL/Java — runs stored procedures with the database owner's authority. That's fine for trusted internal code but a real problem for anything untrusted. "Untrusted code as a stored proc with restricted role" isn't a solved problem in the PL/* space. Caspian's role model addresses it head-on. That's a differentiator that would matter to people who care (fintech, healthcare, multi-tenant SaaS).

**A distribution vehicle for Caspian itself.** Every SQLite user is a potential Caspian-curious developer. Compare "adopt this new language for your project" (huge ask) with "write your DB triggers in this expressive language" (small ask). Some percentage of PlCaspian users become Caspian users elsewhere. Puts Caspian in front of a much bigger audience than Caspian-standalone would reach in the same effort.

**The technical fit is unusually good.** Because Caspian's engine is already Lua-based, PlCaspian is mostly repackaging — not designing a new embedded language, just wrapping the existing one. Compare to a hypothetical "let's embed some other language" which would be much more work.

**Real-world exercise for Caspian-as-embedded-language.** Caspian is designed from the ground up to be embeddable — that's the whole reason engine.lua and the stdlib are split the way they are. But embedded-language design has failure modes that only surface under real usage in a real host: someone else's C runtime, someone else's threading model, someone else's memory constraints, someone else's error-handling conventions. PlCaspian would put Caspian in exactly the shape it's meant to run in and shake out issues that green-field Caspian projects wouldn't catch. **Even if PlCaspian never gains a user base, the shakedown value alone is worth doing.** It's a testbed disguised as a product.

**Existence as a selling point.** Some features earn their keep by being present rather than being used. Every prospective Caspian user who evaluates the ecosystem and sees "there's a stored-procedure language for SQLite based on Caspian" reads it as a signal: this ecosystem thought about the hard cases, extends to unusual environments, and treats embedding as a first-class concern. Most of them won't use PlCaspian. Its existence still moves the needle for how serious the ecosystem looks. Same shape as "Long descriptive names for rarely-used surfaces" — the point isn't heavy use; the point is that thoroughness is visible.

**Groundwork toward Fiona and PlCaspian as embeddable libraries.** The longer-term ambition is that both Fiona and PlCaspian become libraries that ANY project can pull in — not just Caspian projects. A C program, a Python service, a Go daemon, all could `.load` PlCaspian to get a stored-procedure engine, or link Fiona to get its two-table shape as a shared coordination store. Building PlCaspian as a self-contained loadable extension is exactly the discipline that gets us there. Success looks like Caspian and Fiona being reachable from wherever developers already are.

## Where to push back

- **Timing.** PlCaspian depends on Caspian being stable and self-contained enough to embed. Building it before Caspian V1 is premature; the right time is once the engine has proven itself in the standalone case first.
- **Adoption is slow, no matter what.** Even great extensions take years to gain traction in SQLite land. Not a reason not to build, but a reason not to expect fast returns.
- **Docs and support are a real commitment.** Great libraries with poor docs die. Someone has to shepherd it: answer forum questions, publish binaries for common platforms, keep up with Caspian and SQLite releases.
- **Single library vs sibling projects.** If PlCaspian and the generic Lua-procs share one `.so` with two dispatchers, less duplication but each flavor's issues surface in the other. If sibling projects, twice the maintenance surface. Trade-off worth being explicit about. I'd lean same-library with two dispatchers to minimize duplication.

## When to pursue

Not now. Fiona V1 doesn't need it; Caspian V1 doesn't need it. Worth capturing as an idea and revisiting if:

- Someone else builds it and we can just use it.
- Fiona's stakeholders (in real usage, post-V1) want procedural logic at the DB layer that doesn't fit in Lua.
- Someone with a few free months wants a well-scoped open-source project to work on.
