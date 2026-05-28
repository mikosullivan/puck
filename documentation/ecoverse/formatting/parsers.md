# Parser and tokenizer systems for Puck

~~~json
{"vibecode": {"doc": "parsers",
"role": "research report revisiting the deferred decision in
parser-engine.md: should Puck adopt a common parser/tokenizer system
instead of hand-rolling a parser per language, and if so, which one",
"scope": "engine_and_server_side_parsing_only; not_about_vscode",
"status": "research_only_no_commitment_yet",
"supersedes_decision_in": "documentation/ideas/parser-engine.md",
"key_concepts": ["lpeg_native_fit", "tree_sitter_external_only",
"hybrid_model", "caspian_dsl_parser_engine",
"grammar_source_of_truth"],
"covered_tools": ["lpeg", "tree_sitter", "antlr", "pest",
"chevrotain", "lemon", "marpa"]}}
~~~

> **Scope clarification.** This report is about engine and server-side
> parsing — the Caspian engine, the Caspian CLI's `fmt` subcommand,
> Orlando's content rendering, Sammy's HTTP path. **The VSCode
> extension is out of scope** for this report. Per
> the V1 VSCode plan (in the separate [caspian-vscode repo](https://github.com/mikosullivan/caspian-vscode)), the
> extension contains no parser at all; it shells out to `caspian fmt`
> for formatting and uses VSCode's built-in TextMate engine for
> syntax highlighting. Nothing in this report changes that.

**Recommendation in one paragraph.** Standardise on **LPeg** as Puck's
internal parsing engine — it is already in the V1 dependency list,
Roberto Ierusalimschy maintains it, the runtime is Lua-native, and
the `re` sub-module gives a regex-style grammar syntax that is a
plausible surface to expose to Caspian programs as a future
`%engine.parser` or `%utils.peg` capability. Port the Caspian
lexer/parser, the JSON parser, and the planned CSS-selector parser
to LPeg incrementally; keep Uma's schema-driven HTML approach where
it is (a schema is not a grammar). For **external** languages where
Puck is a tool consumer rather than the language author — syntax
highlighting in Sammy, future Differ-style code-aware diffing, any
"parse a snippet of Python/Ruby/SQL" use case — adopt **Tree-sitter**
as a dev-time toolchain (not embedded in the engine), since its
grammar inventory is the only viable answer to "give me a parser for
the world's languages." The two roles do not compete: LPeg is the
embedded engine, Tree-sitter is the external-language asset pool.

<a id="the-state-today"></a>
## The state today

~~~json
{"vibecode": {"section": "state_today",
"role": "snapshot of what Puck parses today and the
parser-engine.md trigger condition"}}
~~~

The deferred plan in
[documentation/ideas/parser-engine.md](../../ideas/parser-engine.md)
set a numeric trigger: "revisit when we have 4 or 5 distinct
hand-rolled parsers and can see the curve bending." That threshold
has effectively arrived. Today Puck either has, or has committed to
build, parsers for:

- **Caspian** — hand-rolled lexer, parser, and transpiler in pure
  Lua at [lib/lua/caspian/](../../../lib/lua/caspian/). Roughly
  1750 lines across `lexer.lua` (~324), `parser.lua` (~917), and
  `transpiler.lua` (~510). This is the largest single parser in the
  codebase.
- **JSON** — a small hand-rolled parser at
  [lib/lua/caspian/json.lua](../../../lib/lua/caspian/json.lua),
  needed because the engine ships canonical CaspianJ as JSON and we
  do not want to drag in a separate C extension just for JSON.
- **HTML (Uma)** — schema-driven, ~1500 lines, with element shape
  supplied externally (`html5.json`). See
  [documentation/ideas/uma/index.md](../../ideas/uma/index.md). Uma
  already plans to lean on an existing Lua HTML library (likely
  gumbo) for the actual parse step, so Uma is partly a consumer of
  someone else's parser, not a fully hand-rolled one.
- **CSS selectors** — planned, ~200–400 lines, not yet written.
- **Markdown** — currently lunamark, a pure-Lua third-party library
  used inside Orlando (see
  [documentation/development/v1/details/lua-dependencies.md](../../development/v1/details/lua-dependencies.md)).

That is five distinct surfaces by the parser-engine.md count, and a
sixth is plausible: Caspian programs may eventually want to define
their own DSLs, which would require a parser capability exposed to
the language. The "revisit" trigger has fired.

The lua-dependencies doc also notes that the Caspian parser is
already written against LPeg, not by truly hand-rolling against
strings. So part of the consolidation has happened informally; this
report is partly about whether to lean into it.

<a id="whats-in-scope-for-puck"></a>
## What's in scope for Puck

~~~json
{"vibecode": {"section": "scope",
"role": "constraints that narrow the option space before any
tool comparison: Lua runtime, deployment story, self-hosting"}}
~~~

Three constraints rule out most of the field before we get to
feature comparison.

**Lua runtime at parse time.** Puck's reference engine is Lua plus
two accepted C extensions: libsodium-minimal and LPeg. The
deployment story is "drop-in pure Lua wherever possible." A parser
system whose runtime requires JavaScript, Java, Rust, or
distributing a generated C library is a non-starter for
engine-internal use. Tools that produce a parser at *dev time* and
emit something Lua can consume (or that run as a separate CLI for
syntax highlighting) are a different story and are evaluated on
their own terms.

**Self-hosting and Caspian DSLs.** If Puck adopts a parser engine
as part of the framework, the natural next step is exposing it to
Caspian programs as a runtime capability — something like
`%engine.parser` or `%utils.peg`. PEG-style grammars compose
cleanly as runtime values (you can build a grammar table, pass it
to the engine, get a parser back). LR/LALR generators, by contrast,
expect an offline code-generation step and do not naturally surface
as a runtime capability. This constraint pushes toward PEG over
LR/LALR.

**Existing-language coverage matters for some surfaces, not
others.** Caspian is Puck's own language, so we are always going to
write the grammar from scratch — there is no "off the shelf Caspian
parser." But for surfaces like syntax highlighting in Sammy
(planned), code-aware diff in a future Differ, or "show me the
shape of this Python file the user pasted into Puck," we want
parsers for languages we did not author and will not maintain. The
right answer there is "use what GitHub uses," which is Tree-sitter.

These three constraints lead to a hybrid model rather than a single
tool. The rest of this document walks the major contenders against
those constraints.

<a id="tree-sitter"></a>
## Tree-sitter

~~~json
{"vibecode": {"section": "tree_sitter",
"role": "evaluate Tree-sitter against Puck constraints; verdict
is external-language-asset-pool only, not engine-internal",
"home": "https://tree-sitter.github.io/tree-sitter/"}}
~~~

Tree-sitter (https://tree-sitter.github.io/tree-sitter/) is an
incremental parser generator with a pure-C11 runtime, no
dependencies, designed to parse on every keystroke in a text
editor. It powers GitHub's code navigation, Neovim, Helix, and
Zed. Grammars are written as JavaScript files (`grammar.js`), using
a small DSL of combinators — `seq()`, `choice()`, `repeat()`,
`optional()`, `prec()`, `field()`, `token()`. The `tree-sitter`
CLI consumes the JS grammar and emits a C source file; that C is
compiled into a per-language shared object the runtime loads.

The grammar inventory is Tree-sitter's defining advantage. Beyond
the 25+ first-party grammars (Python, JavaScript, Rust, Go, Java,
C, C++, TypeScript, Ruby, etc.), there are community grammars for
hundreds of languages — anything an editor wants to highlight has
likely been done. A Lua binding exists (`ltreesitter`,
https://github.com/euclidianAce/ltreesitter), recently maintained,
distributed via LuaRocks; it tracks current Tree-sitter releases
and offers parse, tree navigation, and query support.

**Where Tree-sitter fits in Puck.** External languages we want to
inspect but do not author. Specifically:

- Sammy's syntax highlighter (see
  [project_sammy_syntax_highlighting](../../../project_sammy_syntax_highlighting.md)
  in memory; Caspian is the priority language, but Sammy needs the
  longer tail too).
- Future code-aware Differ output.
- "User pasted a file, what is its shape" use cases.

**Where Tree-sitter does not fit.** Engine-internal parsing of
Caspian itself, JSON, or CSS selectors. Reasons:

1. The grammar source of truth would be a JavaScript file. Puck has
   no JavaScript dev dependency today, and pulling Node into the
   build for Caspian's own grammar is a large step.
2. Tree-sitter is a code generator: you regenerate a C parser when
   the grammar changes. That is a fine dev-time workflow for stable
   languages, but Caspian is still moving, and the regen-and-rebuild
   cycle adds friction without buying us much for a language we
   already parse fine.
3. Tree-sitter grammars do not naturally compose at Caspian runtime.
   A Caspian program that wants to define a small DSL cannot
   meaningfully construct a Tree-sitter grammar on the fly.

**Verdict for Tree-sitter.** Adopt as a dev-time asset pool for
external-language tooling. Don't use it for engine-internal parsing.

<a id="lpeg"></a>
## LPeg

~~~json
{"vibecode": {"section": "lpeg",
"role": "evaluate LPeg as the canonical engine-internal parser
toolkit; already in V1 dependency list",
"home": "http://www.inf.puc-rio.br/~roberto/lpeg/"}}
~~~

LPeg (http://www.inf.puc-rio.br/~roberto/lpeg/) is Roberto
Ierusalimschy's PEG library for Lua, MIT-licensed, around 50 KB
compiled. It is the de-facto Lua parsing toolkit; lunamark uses it,
the LPeg-based `re` module is itself ~270 lines of pure Lua, and
the Caspian engine already depends on it for regex alternation and
for the parser/JSON stack (per
[lua-dependencies.md](../../development/v1/details/lua-dependencies.md#lpeg)).

Grammars are Lua tables, with non-terminals declared via `lpeg.V`
and rules composed with the operators `*` (sequence), `+` (ordered
choice), `^` (repetition), `#` and `-` (positive and negative
lookahead), and `lpeg.B` (lookbehind). The capture model is rich:
simple captures, group captures, table captures, match-time
captures, and accumulator captures, all usable as Lua values. The
`re` sub-module gives a regex-style surface — `balanced <- "("
([^()] / balanced)* ")"` — translating to the underlying combinator
patterns at load time.

**Where LPeg fits in Puck.** Effectively everything engine-internal:

- The Caspian lexer/parser/transpiler (partly already on LPeg per
  the V1 dependency note, but the documented 1750 lines of
  hand-rolled Lua suggests there is consolidation still on the
  table).
- The JSON parser. lunamark proves LPeg can carry a small JSON-shaped
  grammar at acceptable size.
- CSS selectors when that work begins.
- A `%utils.peg` or `%engine.parser` capability exposed to Caspian
  programs, so a Caspian DSL author can write something like:

	~~~caspian
	$grammar = %utils.peg.compile('
	    rule <- "@" {name: [a-z]+} "(" {args: .*?} ")"
	')
	$tree = $grammar.parse($source)
	~~~

	The `re`-style surface here is plausible because `re` is itself
	a pure-Lua translator over LPeg; an analogous Caspian-facing
	surface is a small wrapper, not a new engine.

**The gap.** LPeg has very few off-the-shelf grammars. There is no
"LPeg parser for Python" you can plug in. If Puck wants to parse
external languages, LPeg is the wrong tool — that is the
Tree-sitter slot. LPeg's reach is "things we wrote the grammar
for," which is exactly the engine-internal set.

**Cost of porting the existing Caspian parser to LPeg.** Plausibly
moderate. The lexer and the JSON parser are clear wins (small, well
understood, LPeg shrinks them substantially). The parser itself is
the larger question — it carries Caspian's semantics, error
messages, and the things parser-engine.md flagged as
"grammar errors might surface awkwardly across the Caspian/Lua
boundary." A conservative path is to port the lexer first, keep the
hand-rolled parser, see how error messages survive the boundary,
and only port the parser if the result is genuinely better. This
matches the cheat-sheet preference for not bolting on additions
ahead of evidence.

**Verdict for LPeg.** Already adopted; commit to it as the canonical
engine-internal parser engine; port the JSON parser and any new
parser (CSS selectors) onto it first; revisit the Caspian parser
port after that gives us a real read on the boundary behaviour.

<a id="antlr"></a>
## ANTLR

~~~json
{"vibecode": {"section": "antlr",
"role": "evaluate ANTLR4; not a fit because no Lua target and the
runtime model is wrong for Puck"}}
~~~

ANTLR (https://www.antlr.org) is Terence Parr's parser generator,
BSD-licensed, with grammars in EBNF-style `.g4` files. ANTLR4 is
mature, well-documented, and has a strong industry track record
(Guido van Rossum and Twitter are cited on the home page). The tool
is written in Java; it generates parsers in **Java, C#, Python,
JavaScript, TypeScript, Go, C++, Swift, PHP, or Dart**. Per
https://github.com/antlr/antlr4/blob/master/doc/targets.md, **Lua is
not an official target.**

Even if a community Lua target existed, the runtime model is wrong
for Puck. ANTLR generates per-grammar parser source, expects a
build step, and expects a runtime library on the host side. None of
that is bad in itself, but it is a heavier shape than LPeg and
buys us nothing LPeg does not already offer for the engine-internal
case. The grammar surface (`.g4`) does not compose as runtime values
either, so the Caspian-DSL self-hosting use case is awkward.

**Verdict for ANTLR.** Not a fit. Mention it in this report for
completeness; do not pursue.

<a id="pest"></a>
## Pest

~~~json
{"vibecode": {"section": "pest",
"role": "evaluate Pest; Rust-only, so same disqualification path
as ANTLR"}}
~~~

Pest (https://pest.rs) is a Rust PEG parser generator with grammars
in standalone `.pest` files, automatic error reporting, and
performance comparable to nom and serde. It is technically
attractive — clean grammar surface, PEG-shaped, good error
diagnostics — but it is Rust-only. Puck has no Rust in its V1
dependency set, and adopting Rust for one parser would dwarf the
benefit. Pest is in the same disqualification bucket as ANTLR for
Puck-internal use, despite being a more elegant tool.

**Verdict for Pest.** Not a fit for Puck. Worth keeping an eye on
as a reference design — its `.pest` grammar surface is a clean
example of what a Puck-side PEG file format could look like if we
ever decide to store LPeg grammars in standalone `.peg` files
instead of inline Lua tables.

<a id="chevrotain"></a>
## Chevrotain

~~~json
{"vibecode": {"section": "chevrotain",
"role": "evaluate Chevrotain; JavaScript-only, mentioned for
completeness only"}}
~~~

Chevrotain (https://chevrotain.io) is a parser-building toolkit for
JavaScript, structured as an internal DSL inside JS — no code
generation, no separate grammar files. It is well-engineered (very
fast for JS, good error recovery, automatic syntax-diagram output)
but JS-only. The Puck engine cannot host it, and there is no
near-term reason to embed a JS runtime just for parsing.

**Verdict for Chevrotain.** Not a fit. Mentioned to confirm it was
considered.

<a id="lemon"></a>
## Lemon

~~~json
{"vibecode": {"section": "lemon",
"role": "evaluate Lemon; very small, C-only, used by SQLite, but
the LR/LALR model and C target rule it out"}}
~~~

Lemon (https://www.sqlite.org/lemon.html) is D. Richard Hipp's
LALR(1) parser generator, used by SQLite to generate the SQL
parser and the FTS5 parser. It is small, fast, reliable, reentrant,
and emits C only. The license is public-domain / SQLite-style,
which is permissive enough.

Lemon is interesting from a "minimum viable LR generator" angle,
but it has the same two problems as ANTLR: it generates C, not Lua;
and LALR grammars do not compose as runtime values for the
Caspian-DSL case. SQLite uses Lemon for exactly the right job —
embed a fixed grammar in a C library, never expose it to end users —
and Puck is not doing that job.

**Verdict for Lemon.** Not a fit, despite being a small and
admirable tool. Same disqualifier path as ANTLR.

<a id="marpa"></a>
## Marpa

~~~json
{"vibecode": {"section": "marpa",
"role": "evaluate Marpa; powerful Earley algorithm, Perl-first,
out of scope"}}
~~~

Marpa (https://jeffreykegler.github.io/Marpa-web-site/) is Jeffrey
Kegler's Earley-based parsing engine, with a C core (Libmarpa) and
a Perl distribution (Marpa::R2) as the reference frontend. Its
selling point is power: it parses anything expressible in BNF,
including ambiguous and left-recursive grammars, in linear time
for the unambiguous case. That is genuinely more powerful than PEG.

But Puck does not currently need ambiguous grammars. Caspian is
PEG-friendly. JSON is PEG-friendly. CSS selectors are
PEG-friendly. Markdown is famously ambiguous, but we already
delegate Markdown to lunamark (also LPeg-based) and have no current
reason to write our own. Adopting Marpa would be a significant
addition (C runtime, Perl-shaped reference docs, an algorithm few
Puck contributors will already know) in service of capability we
have not asked for.

**Verdict for Marpa.** Not now. Reconsider only if we hit a real
grammar that PEG cannot express, and the cost of disambiguating it
in PEG terms exceeds the cost of importing Marpa.

<a id="the-hybrid-model"></a>
## The hybrid model

~~~json
{"vibecode": {"section": "hybrid_model",
"role": "the proposed split: LPeg for engine-internal parsing,
Tree-sitter for external-language dev-time tooling, Uma's
schema-driven approach for tag-based markup",
"key_concepts": ["lpeg_internal", "tree_sitter_external_dev_time",
"uma_schema_unchanged"]}}
~~~

The decision is not one tool; it is three roles played by three
different mechanisms. None of them displace each other.

**Role 1: engine-internal parsing → LPeg.** Caspian, JSON, CSS
selectors, and any future Puck-authored mini-language. LPeg is
already in the V1 dependency list; the cost of "adopting" it is
mostly committing to it and porting the JSON parser as the first
concrete demonstration. The optional `re` surface gives a
regex-style grammar syntax if we ever want a non-table
representation.

**Role 2: external-language tooling → Tree-sitter.** Sammy's syntax
highlighter, future Differ code-aware diffs, anything that says
"parse a snippet of someone else's language and tell me its
shape." Tree-sitter ships as a dev-time toolchain — Node and the
`tree-sitter` CLI required only when building grammars; the
ltreesitter Lua binding requires the C runtime at parse time, but
that is a Sammy-side dependency, not an engine-core dependency.
Sammy doc work has not started yet, so this commitment can land at
that point.

**Role 3: tag-based markup → Uma's schema model, unchanged.**
[documentation/ideas/parser-engine.md](../../ideas/parser-engine.md)
already says "Uma's schema-driven approach stays the user-facing
way to define tag-based markup languages." That principle survives
this report. `html5.json` is not a grammar; it is a configuration.
The point of Uma is that the user does not need to learn PEG or
combinators to define a custom XML/HTML dialect. The schema model
lives independently of whatever the engine-internal parser engine
is.

**Caspian DSL self-hosting → LPeg via `%utils.peg`.** A Caspian
program that wants to parse its own DSL goes through the LPeg
surface, wrapped as a Caspian capability. The wrapper looks
something like the `re` module's translation layer: accept a
regex-style or table-style grammar in Caspian, compile to LPeg,
return a parser object. This is in scope for **after** V0.01; it is
listed here so we know what shape we are aiming at.

<a id="recommendation"></a>
## Recommendation

~~~json
{"vibecode": {"section": "recommendation",
"role": "concrete action items and ordering; minimal and
reversible"}}
~~~

The recommendation is the hybrid model above, sequenced as follows:

1. **Confirm LPeg as the canonical engine-internal parser engine.**
   This is mostly a paper move — LPeg is already in the V1
   dependency list — but the cheat sheet, the parser-engine.md
   "deferred" status, and the development plan should reflect it.
2. **Port the JSON parser
   ([lib/lua/caspian/json.lua](../../../lib/lua/caspian/json.lua))
   to LPeg first.** Small, well-understood, no semantic ambiguity.
   This is the proof-of-concept and the first concrete artifact.
3. **Use LPeg for the CSS-selector parser** when that work begins.
   No reason to hand-roll a fifth surface.
4. **Defer the Caspian-parser-to-LPeg port** until we have read on
   the JSON port and the CSS-selector parser. The current Caspian
   parser works; "works" is doing real load until we have a clearer
   picture of how LPeg-flavoured errors surface across the
   Caspian/Lua boundary.
5. **Plan Tree-sitter as a Sammy-era dev-time dependency**, not as
   part of V1 core. The Sammy syntax-highlighter design issue
   (mentioned in
   [project_sammy_syntax_highlighting](../../../project_sammy_syntax_highlighting.md))
   is the natural moment to commit. Note that ltreesitter is the
   intended Lua binding and is current.
6. **Sketch the `%utils.peg` Caspian capability** as a separate
   design doc, scoped post-V0.01. Probably looks like a Caspian-side
   thin wrapper over LPeg's `re`, returning a parser object the
   Caspian program can call.

This sequence is reversible at each step. Nothing in steps 1–3
commits us to step 5; nothing in step 5 commits us to step 6. If a
later step turns out to be a bad idea, the earlier work still
stands.

<a id="docs-to-update-if-this-lands"></a>
## Docs to update if this lands

~~~json
{"vibecode": {"section": "doc_updates",
"role": "concrete list of existing docs that would need edits if
the recommendation is accepted; lets the human reviewer scope the
follow-on work"}}
~~~

If the recommendation is accepted, these existing docs need edits:

- [documentation/ideas/parser-engine.md](../../ideas/parser-engine.md) —
  flip status from `deferred` to `superseded`; add a one-line
  pointer to this report. The "Bundle LPeg" option goes from
  hypothetical to adopted; the "Roll our own PEG" option is closed
  out.
- [documentation/development/v1/details/lua-dependencies.md](../../development/v1/details/lua-dependencies.md) —
  the LPeg entry already lists `caspian_regex_engine_alternation`,
  `caspian_parser`, and `caspian_json_parser` as users. Add the
  CSS-selector parser as a planned user; add a note that LPeg is
  the engine-internal parser engine going forward.
- [documentation/cheat-sheet.md](../../cheat-sheet.md) — add a
  short entry under whichever section covers framework
  dependencies: "engine-internal parsing → LPeg; external-language
  parsing → Tree-sitter (dev-time, Sammy onward); tag-based markup
  → Uma's schema model."
- [documentation/ideas/uma/index.md](../../ideas/uma/index.md) —
  no semantic change, but worth a one-sentence note clarifying that
  Uma's schema approach is intentionally not a grammar and is not
  replaced by the engine-internal parser engine decision.
- Sammy design work (not yet started) inherits the Tree-sitter
  recommendation when it begins. No doc to edit yet; the dependency
  will be declared in the Sammy index when that work lands.

A future doc, not edited here:

- A new design note for `%utils.peg` (the Caspian-facing PEG
  capability). Scope: post-V0.01. This report is the parent
  reference.
