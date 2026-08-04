# DSL blocks

~~~vibecode
{"vibecode": {
	"doc": "ideas_dsl_blocks",
	"role": "brainstorm doc for how Caspian programs express block-shaped constructs on top of the DSL surface — the shape of user-defined multi-clause blocks, loop interstitials (before / between / after / noloop), any other block-adjacent surface a DSL author might reach for. Captures design candidates and their trade-offs before anything commits to the requirements/ tree.",
	"status": "landed 2026-08-04 (later same day) — reversed and adopted sigil-prefix form: `do` / `dofunc` stay as anonymous positional blocks; every other named block-attachment is written `~name` and fills a same-named slot"
}}
~~~

## Loop interstitials — flat form

Miko's decision, 2026-08-04. Loop interstitials are their own top-level blocks, siblings to the loop itself. Each block ends with `end` — no special sub-section syntax inside the loop:

~~~caspian
while(&foo)
end

before
end

after
end

between
end

noloop
end
~~~

### Under the hood: `before` / `between` / `after` / `noloop` join `do` and `dofunc`

Not a new language mechanism — they're four new keywords that participate in the existing block-attachment pattern `do` and `dofunc` already use. Every one of them attaches an anonymous closure to the immediately preceding call in the current scope, following the same rule the transpiler already applies to `do` / `dofunc` (see [transpiler.lua block-attachment path](../src/engine/transpiler.lua)).

So `while(&foo) end` above reads as one bwc call: `while` with condition `&foo` and an anonymous body-closure. The subsequent `before ... end`, `after ... end`, `between ... end`, `noloop ... end` each attach their own closure to the same `while` call. The whole loop construct is a single bwc with up-to-five attached closures.

The `{blocks: [...]}` envelope on the call carries them all — same shape `do` / `dofunc` produce today, just with more atom-key varieties:

| Source keyword | Attached-closure atom key | Semantic |
|---|---|---|
| `do` | `closure` | captures outer scope |
| `dofunc` | `function` | sealed scope |
| `before` | `before` | runs before iteration starts |
| `between` | `between` | per-iteration body / between iterations |
| `after` | `after` | runs after iteration completes |
| `noloop` | `noloop` | runs if zero iterations happened |

The runtime `while` construct decides what to do with each attached closure. Structurally the CaspJ / CaspM shape is uniform — every `{blocks: [...]}` entry is a `{<KIND>: {params, body, as?, ...}}` object; only the outer key changes.

### In-body clause support: dropped

Miko's decision, 2026-08-04. The transpiler currently allows `before` / `between` / `after` / `noloop` as clauses INSIDE a `do` / `dofunc` body (the `CALLABLE_CLAUSES` set in the parser). Under the new model these four are top-level attachment keywords ONLY — never in-body clauses. One mechanism, not two.

Implementation follow-up: the parser's `CALLABLE_CLAUSES` gate and the `do` / `dofunc` frame's clause-cursor mechanism need to drop the four names. Frame types like `while` and `until` that also reference `CALLABLE_CLAUSES` need the same trim. Fixtures that rely on the in-body form retire.

## Generalized block-keyword scheme — considered, not pursued

Spitballed 2026-08-04. The question: could the parser recognize arbitrary DSL-defined block-opener keywords (`where`, `on_success`, `middleware`, whatever a DSL author wants) alongside the six hardcoded ones? Angles considered:

- **Sigil prefix** (`~before`, `:before`, etc.) — parser recognizes any sigil'd bareword as a block-opener.
- **Required auxiliary word** (`before do ... end`) — every block-opener is followed by a fixed marker.
- **`end`-based lookahead** — any bareword whose statement is followed by an indented body and matching `end` is a block-opener.
- **Explicit DSL registration** — parser treats any bareword-plus-body-plus-`end` as a block-attachment; the receiving DSL raises at dispatch if it doesn't accept the name.
- **Namespaced names** (`while.before`) — DSL-scoped block-opener keywords.

Miko's call: none of the schemes gain enough over the hardcoded six to be worth adopting. Left tempted to prototype the concept inside a DSL rather than as a language mechanism, but not worth the effort right now. Page closed.

## Reversal: `~name` sigil form adopted

Miko's decision, 2026-08-04 (later same day, reopening the "Sigil prefix" option from the closed section above).

What changed in the framing: yesterday's sigil scheme was proposed as an ADDITION on top of the six hardcoded keywords — sigil-prefixed names would coexist with `before` / `after` / `between` / `noloop` as reserved words. This version REPLACES the four with the sigil mechanism. That shrinks the language instead of growing it. `do` and `dofunc` stay as their special-case anonymous-positional forms — they don't get a `~` prefix.

The four names lose their reserved-word status. Written as:

~~~caspian
$foo.each do($item)
	puts $item
end

~before
	puts '--- START ---'
end

~after
	puts '--- END ---'
end
~~~

Any DSL author can accept named blocks by declaring which `~name`s it recognizes. The four "loop interstitial" names are just the built-in ones the loop constructs know about.

At-most-one-per-name is structural: `~before` fills a slot named `before`; a second `~before` on the same call would be two writes to one slot. Parser rejects the second.

Sigil choice: `~` picked over the other single-char options that had no language use (`` ` ``, `^`, `?`-as-prefix) and the multi-char options (`::name`, `..name`). Only baggage on `~`: Miko avoids it in prose because it reads "approximately." Non-prose sigil use doesn't collide with that.
