# Pluggable syntax

*Custom parsers registered against a command name. When the parser hits the command, it hands the character stream to the command's own parser, which reads until it decides it's done and then returns control. Deferred until after V1.*

~~~vibecode
{"vibecode": {
	"doc": "idea_pluggable_syntax",
	"role": "captures the design idea that Caspian could let commands register their own parsers — the main parser yields to a command-owned parser at a well-known point, the command consumes characters until it decides it's done, and control returns to the main parser. Includes the surface Miko sketched, the mechanism's existing precedents in other languages, the concerns that make it post-V1, and the motivating use cases.",
	"status": "idea_captured_deferred_until_after_v1",
	"deferred_because": "the mechanism serves more than regex; committing to it for one caller locks in that caller's assumptions; and its blast radius on tooling (highlighter, formatter, LSP) is significant",
	"related": ["ideas/regexes.md (the concrete case that surfaced this idea — the regex(/.../) surface currently ships as a hardcoded lexer special case, not through this mechanism)"]
}}
~~~

## The idea

Certain commands own their own syntax. When the main parser reaches such a command, the command's parser takes over the character stream, reads until it decides it's done, and returns control. Sketched shape:

~~~caspian
#                [             ] <- handled by regex object
$str.match(regex(/whatever(e|$)/))
~~~

The main parser sees `regex(`, recognizes it as a pluggable-syntax command, and hands the remaining characters to `regex`'s own parser. That parser reads `/whatever(e|$)/`, decides it's done at the closing `/`, and returns whatever it built (a compiled `Regex` object) to the main parser, which continues with the `)`.

Once the mechanism exists, adding a new special syntax is just registering a class that owns a parser: `xml_regex(...)`, `sql(...)`, `json_path(...)`, `cron(...)`, `math(...)`, whatever the ecoverse wants — all fall out of the same hook.

## It already exists in other languages

The pattern has a long lineage under multiple names:

- **Common Lisp reader macros.** The canonical case. A character or sequence is registered with a reader function; the parser hands the stream to the reader when it hits that character; the reader reads until done and returns a value. `#|...|#`, `#(...)`, `#'x` — all reader macros. Users can register their own.
- **Racket.** Reader macros plus `#reader ...` to specify a whole-file custom reader. More disciplined than Common Lisp.
- **Elixir sigils.** `~r/foo/i` (regex), `~w[a b c]` (word-list), `~D[2026-07-08]` (dates). Users define their own with `sigil_x` functions. Probably the closest living example to Miko's sketch.
- **Julia macros.** `r"pattern"` (regex), `raw"..."`, `md"..."` (markdown). Each string-macro parses its content however it wants.
- **Rust procedural macros.** `sqlx::query!("SELECT * FROM users")`. The SQL is parsed by the macro, not by rustc. The `!` marks the hand-off.
- **Perl 5 source filters, Raku slangs.** More extreme forms — whole sub-grammars.

## Why post-V1

Five concerns argue for deferring until we have real data on what several special-syntax constructs actually need:

- **Editor tooling explosion.** Syntax highlighters, formatters, and LSPs currently know one language. Every pluggable reader is a source of confusion — an unknown reader's contents render as garbage in any tool that doesn't ship code for that specific reader. Elixir mostly avoids this by restricting sigils to single letters and a small delimiter set (`(){}[]<>"'/|`). Whatever surface Caspian picks needs a comparable discipline.
- **Grep-hostility.** `regex(/foo/)` is greppable — the parens balance, the delimiters are conventional. A reader that uses `<<<...>>>` or invents its own escape rules breaks every text tool that assumes parens balance and quotes pair.
- **Semantics of the reader name.** Is `regex` a value you can pass around? A function you can call? A syntactic marker with no first-class identity? Each choice has consequences for the language surface. This wants a settled answer before the mechanism ships.
- **Discoverability.** Where does a reader author learn what readers exist? "Unknown reader" is fine at development time; "did I import the right library?" is a class of confusion Caspian doesn't currently have.
- **Debug-time cost.** When a reader-produced value causes a problem, the source range is inside the reader's territory. Error messages pointing at the right byte range across the boundary are non-trivial.

## Additional Caspian-specific concerns

- **Compile-time availability.** Caspian classes are downloaded through `%puck`. A reader has to be available at *parse* time — before user code runs. That's chicken-and-egg for anything not shipped with the engine. Do readers live in a separate namespace? Are they pre-declared? A separate `%puck.readers` grant? Unresolved.
- **Editor extension story.** Caspian's tooling (VS Code extension, syntax highlighter) has to know how to render reader contents. That means each reader ships not just runtime code but tooling annotations — an editor plugin per reader. Doable, but real.
- **First special-syntax case doesn't need the mechanism.** `regex(/.../ )` ships as a hardcoded lexer special case in V1. The XML-regex idea can ship as a plain `%puck`-downloaded builder that produces `Regex` values through the normal method surface — no custom parser required. Neither of the current motivating cases forces the general feature.

## When to revisit

Once we have real experience with several special-syntax candidates — `regex`, XML-regex, SQL, JSON path, whatever else surfaces — we'll have the data to pick a shape. The concerns above are addressable, but each answer is easier to get right when there are three or four cases to test it against, not one.

Until then: hardcode special cases (as `regex` does for V1), or ship them as normal `%puck`-downloaded builders (as the XML-regex form does).

## Related

- [ideas/regexes.md](regexes.md) — the concrete case that surfaced this idea. Both the `regex(/.../ )` surface and the XML-regex format could be pluggable-syntax users; neither requires the mechanism to ship.
