# Regular expressions

*Design brainstorm for Caspian's regex surface — engine choice, literal syntax, string-side methods, Match class shape, and the open sub-decisions to work through before it lands in `requirements/`.*

~~~vibecode
{"vibecode": {
	"doc": "idea_regexes",
	"role": "working brainstorm for Caspian's regex surface. Captures the settled points (LPeg as the engine, `regex(...)` keyword for literals, split `.match` / `.matches` on String, single-Match-per-hit) and the open sub-decisions (flags syntax, escaping, interpolation stance, Regex return-type name, and the pattern-facing method surface beyond match/matches).",
	"status": "brainstorming — main-line decisions settled through conversation; four sub-decisions and the full String method surface still open",
	"related": ["requirements/built-in-classes/primitives/string/regular-expressions (stub landing page pointing at LPeg's own docs)"]
}}
~~~

## Settled so far

**Engine: LPeg.** Caspian's regex surface is powered by LPeg — a PEG library, a strict superset of traditional regex, ~50 KB in the install. Pattern-syntax documentation defers to [LPeg's own reference](https://www.inf.puc-rio.br/~roberto/lpeg/) rather than re-documenting the pattern language. <!-- outbound-link-allowed -->

**Anchors: `^` and `$`.** Beginning-of-string and end-of-string are the standard PCRE-shaped anchors. That decision implies Caspian patterns are PCRE-shaped in the surface users write, compiled to LPeg underneath (rather than exposing LPeg's native pattern language, which has no `^`/`$`).

**No bare `/foo/` literals.** Dropped — the lexer cost of distinguishing `/foo/` (regex) from `a/b/c` (division) is too high, and modern languages that pay it (JavaScript, Perl) have famous failure modes because of it.

**`regex(...)` keyword instead.** The `regex(` prefix flags "here comes a pattern literal" and unlocks pattern-mode in the lexer. No division ambiguity, and patterns still get their own visual identity:

~~~caspian
$str.match(regex(/foo|bar/))
~~~

Compile-time-fixed patterns go through `regex(...)` and can be compiled once at parse time. String-form patterns (`.match('foo')`) still work for runtime-composed patterns; both feed the same LPeg engine.

**String-side entry points.**

- `$str.match(pattern)` returns a single `Match` object for the first hit, or `null` if none. Chainable — `.match('a').match('b')` narrows on the previous match's text. Null-safe navigation is the recommended idiom for the "may or may not match" case: `$str.match(regex(/x/))&.text`.
- `$str.matches(pattern)` returns an array of `Match` objects — one per hit, empty array if none. (The engine may or may not use a Caspian Array under the hood; the surface is array-shaped from the caller's view.)

Splitting the two is deliberate: the common case is "did we find one?" not "give me every one." Making the common case go through a collection wrapper would tax every call site to eliminate a distinction that mattered only at the API level. Also cleanly preserves the truthy-check idiom: `if $str.match(pattern)` works because `null` is falsy.

**No `.matches` / `.count` on the Match class.** Old requirements put a `.matches` array on the Match itself, which was inconsistent (a Match represents one match location; putting a collection on it made the shape ambiguous). Collection-shaped fields live on the result of `$str.matches(...)`, not on individual Matches.

**Match class shape.**

- **Content:** `.text` (matched substring), `.length`, `.source` (the full string the match was found in).
- **Position:** `.start`, `.end` (zero-based, half-open — so `.end - .start` == `.text.length`).
- **Captures:** `.groups` (array of positional captures, `.groups[0]` is the first `(...)`), `.captures` (hash of named captures, `.captures[:year]` reads `(?<year>...)`). Positional and named are kept in separate containers — no crossover, matching the "no aliasing" preference.
- **String-context conversion:** `puts $match` writes `.text`; `'x' + $match` concatenates `.text`. The Match becomes its matched text in string contexts.
- **Read-only.** No mutation; the Match is a snapshot at match time.
- **No re-execute.** A Match is a result, not a pattern. To run the pattern again, hold the Regex.

**Safe handling of untrusted strings — required.** The regex engine safely handles any string as input regardless of source. Concretely:

- **The subject string is always safe to match against.** A subject received from stdin, network, `%chain.env`, `%fetch`, or any other faucet cannot cause the engine to hang, panic, or misbehave — no ReDoS-style catastrophic backtracking, no unbounded memory growth, no crash on any byte sequence including malformed UTF-8, embedded nulls, or adversarial inputs designed to trip a naive engine. This is the property most regex engines quietly fail to provide (PCRE has famous exponential-blowup cases on innocuous-looking patterns and long inputs); Caspian guarantees it. LPeg's PEG execution model makes this achievable because PEG matching is deterministic — no backtracking-blowup class of failure exists at the engine level.
- **The pattern from untrusted source is a separate concern.** If a program passes a user-supplied string to `.match($user_pattern)`, the pattern itself is being treated as executable input — same category as `eval`. The engine still won't hang on a malformed pattern (parse errors raise cleanly), but "match what the user asked for" isn't a safety guarantee — it's the user's spec. Applications that accept user-supplied patterns should treat that surface with the same scrutiny they'd give any user-supplied executable input.
- **Pattern-parts from untrusted source must be escaped.** When user input becomes PART of a pattern via string concatenation (`.match('^' + $prefix + '\\d+$')`), a `.` in the user input silently becomes a wildcard. The safe form is `.literal($prefix)` in the [Regex class builder](#regex-class), which escapes automatically. This is the class of bug the string-form patterns invite and the builder eliminates.

## Open sub-decisions

### Flags syntax

Two candidates:

- **Perl-style trailing:** `regex(/foo/i)`. Compact, matches muscle memory; the lexer reads pattern between `/` delimiters, then optional flag letters until the closing `)`.
- **Keyword arg:** `regex(/foo/, flags: :i)` or `regex(/foo/, case_insensitive: true)`. More explicit, more verbose, harder to grep for.

Leaning Perl-style. Flag inventory to pin: `i` (case-insensitive), `s` (dotall — `.` matches newline). Not `g` — global-vs-first is settled at the method level (`.match` vs `.matches`), not on the pattern. **No `m` (multiline).** In most languages the `m` flag makes `^` and `$` match line boundaries; Caspian regex always applies to the whole string, so `^` and `$` are unambiguously start-of-string and end-of-string. To match a newline explicitly, put `\n` in the pattern. Dropping `m` removes a flag most users never fully internalize and eliminates the "did I remember to turn on multiline?" foot-gun. **No `/u`.** UTF-8 is the guaranteed ambient state for every Caspian string; character-class shorthands and code-point escapes are Unicode-aware by default. A `/u` flag would just encode a default that can't be turned off.

**Unrecognized flags raise.** `regex(/foo/z)` raises at parse time — no silent ignoring of typos or aspirational flags. This matches the general no-dangerous-defaults posture: an error the developer sees the first time beats a bug they trip over months later.

### Escaping and alternate delimiters

Standard: backslash-escape `/` inside a `/`-delimited pattern — `regex(/foo\/bar/)`. Ruby-style alternate delimiters (`%r{foo/bar}` or `regex({foo/bar})`) not needed at V1; defer until real code shows the escape gets painful.

### No interpolation in the literal

`regex(/^${x}/)` doesn't work — the literal is treated as literal text. If you need runtime interpolation, use the string form: `.match('^' + $x)`. Cleanly divides "compile-time-fixed pattern" from "runtime-composed pattern."

### Class name for the return of `regex(...)`

`Regex`, `Pattern`, or something else? Both are common in other languages. `Regex` is more discoverable; `Pattern` is more accurate (LPeg patterns aren't strictly regexes — they're PEGs — but the user-facing name is what the caller writes, so `Regex` may still be the right label). Undecided.

## Open — full method surface on String

Beyond `.match` and `.matches`, the pattern-consuming surface on String needs to be pinned. Candidates surfaced in earlier conversation:

- `.match?(pattern)` — boolean; no `Match` allocated. Zero-cost fast path for "does this string match?" checks.
- `.replace(pattern, replacement, scope: :all)` — pattern is string OR regex; `scope` is `:all`, `:first`, `:last`, or integer `1..N`. Returns original unchanged if nothing matched.
- `.replace_with(pattern, &block)` — replacement is a closure taking each `Match`, returning the replacement string. Programmatic-substitution surface.
- `.split(pattern, limit: null)` — split on regex; array of strings. `limit:` caps the number of pieces.
- `.partition(pattern)` — three-part array: `[before_match, match, after]`. `[$str, '', '']` if nothing matched.
- `.each_match(pattern) do($match) ... end` — block form; runs the block once per match. Pull-based counterpart to `.matches`.

Open: which of these are V1, which are deferred; whether `.starts_with?` / `.ends_with?` should accept regex; whether `.split` includes capturing groups in the output (Python-style yes, Ruby-style no).

## Regex builder

*To brainstorm.*

### XML format

Traditional regex is compact but cryptic — `^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})$` is dense enough that most developers can't read it fluently after a few weeks away from the codebase. An XML format for defining regexes trades brevity for legibility: each construct gets a named element, options become attributes, and the grammar's tree structure shows in the document's tree structure. It also picks up things traditional regex lacks or handles clunkily — native comments (`<!-- -->`), whitespace flexibility, and named subpatterns you can reference.

**Scope and delivery.** This is a **post-V1** feature and **not built into the language**. V1 ships with the string-form and `regex(/.../ )` surfaces described above, both compiled against LPeg. The XML format arrives (if it arrives) as a downloadable Puck object — same mechanism as any other library: pull it through `%fetch`, hold the returned builder, use it to construct `Regex` values that plug into `.match` / `.matches` / `.replace` / everything else the built-in surface accepts. Nothing about the built-in regex surface has to change to accommodate it; the XML form is just another way to produce a `Regex`.

#### Element vocabulary sketch

**Anchors:**

- `<start />` — matches beginning of string (`^`).
- `<end />` — matches end of string (`$`).
- `<word-boundary />` — matches at a word boundary (`\b`).

**Character matchers:**

- `<literal>hello</literal>` — matches the literal text between the tags.
- `<any />` — matches any single character (`.`).
- `<digit />` — matches a digit (`\d`).
- `<word-char />` — matches a word character (`\w`).
- `<whitespace />` — matches any whitespace character (`\s`).
- `<char-set>abc123</char-set>` — matches any one character in the set (`[abc123]`).
- `<char-range from="a" to="z" />` — matches any character in a range (`[a-z]`). Multiple `<char-range>` inside a `<char-set>` for compound sets.
- `<unicode-class name="Letter" />` — matches any character in a Unicode category (`\p{Letter}`).
- `<char code="0x1F600" />` — matches a specific code point (`\u{1F600}`).
- `<newline />`, `<tab />`, `<return />` — matches `\n`, `\t`, `\r` respectively.

**Negation:**

- `<not>...</not>` — inverts whatever's inside. `<not><digit /></not>` becomes `\D`; `<not><char-set>abc</char-set></not>` becomes `[^abc]`.

**Quantifiers:**

- `<optional>...</optional>` — 0 or 1 (`?`).
- `<zero-or-more>...</zero-or-more>` — 0 or more (`*`).
- `<one-or-more>...</one-or-more>` — 1 or more (`+`).
- `<repeat count="4">...</repeat>` — exactly N (`{4}`).
- `<repeat min="2" max="4">...</repeat>` — N to M (`{2,4}`).
- `<repeat min="2">...</repeat>` — at least N (`{2,}`).
- All quantifiers take an optional `greedy="false"` attribute for lazy behavior (default is greedy).

**Groups:**

- `<capture>...</capture>` — positional capture group (`(...)`); available on the Match as `.groups[N]`.
- `<capture name="year">...</capture>` — named capture (`(?<year>...)`); available as `.captures[:year]`.
- `<group>...</group>` — non-capturing group (`(?:...)`); use when you need to apply a quantifier to a sequence without capturing.

**Alternation:**

- `<any-of>...</any-of>` — each direct child is one alternative. `<any-of><literal>morning</literal><literal>afternoon</literal></any-of>` becomes `morning|afternoon`. Way cleaner than pipe-chained alternation, which visually competes with other pattern syntax.

**Lookaround:**

- `<followed-by>...</followed-by>` — positive lookahead (`(?=...)`).
- `<not-followed-by>...</not-followed-by>` — negative lookahead (`(?!...)`).
- `<preceded-by>...</preceded-by>` — positive lookbehind (`(?<=...)`).
- `<not-preceded-by>...</not-preceded-by>` — negative lookbehind (`(?<!...)`).

**Comments:**

Native XML comments (`<!-- -->`) work anywhere inside a `<pattern>`. Traditional regex only has the awkward `(?# comment)` extension, and most engines don't support inline comments at all.

#### Comparison example — an ISO date

Traditional:

~~~
^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})$
~~~

XML format:

~~~xml
<pattern>
	<start />
	<capture name="year">
		<repeat count="4"><digit /></repeat>
	</capture>
	<literal>-</literal>
	<capture name="month">
		<repeat count="2"><digit /></repeat>
	</capture>
	<literal>-</literal>
	<capture name="day">
		<repeat count="2"><digit /></repeat>
	</capture>
	<end />
</pattern>
~~~

Ten times the characters, but every construct is named and there's nothing you have to look up. The XML form is also diff-friendly — a change from `{4}` to `{2}` becomes a change from `count="4"` to `count="2"` on a specific line.

#### Named subpatterns

Because XML naturally accommodates definitions and references, subpatterns can be named at the top of the document and referenced multiple times:

~~~xml
<pattern>
	<define name="four-digits">
		<repeat count="4"><digit /></repeat>
	</define>
	<define name="two-digits">
		<repeat count="2"><digit /></repeat>
	</define>

	<start />
	<capture name="year">
		<use pattern="four-digits" />
	</capture>
	<literal>-</literal>
	<capture name="month">
		<use pattern="two-digits" />
	</capture>
	<literal>-</literal>
	<capture name="day">
		<use pattern="two-digits" />
	</capture>
	<end />
</pattern>
~~~

Beyond DRYing repeated groups, this gives large patterns a legible top-level structure — the shape reads as "match a year, then a dash, then a month, then a dash, then a day," with the definitions of what a year/month/day is separated out.

#### Call-site integration — open questions

Several loose ends about how the XML surface joins the rest of the language:

- **How does the caller pass it in?** `$str.match(regex_xml('<pattern>...</pattern>'))` (a builder that takes an XML string)? `regex(<pattern>...</pattern>)` (the lexer notices the leading `<` and switches into XML mode)? A dedicated keyword like `xml_regex`? Loading from a file via `%fetch` (patterns as first-class objects)?
- **How does it compose with `regex(/.../ )` and string-form patterns?** All three should probably produce the same underlying `Regex` object, differing only in how they're written.
- **Flags — same set (`i`, `s`) or attributes on `<pattern>`?** `<pattern case-insensitive="true">` reads naturally at the top of the document.
- **Whitespace and newlines in the XML source.** Ignored between elements, preserved inside `<literal>`. Standard XML rules.
- **Error surface for invalid XML.** Unknown element? Invalid attribute? Same "unrecognized flags raise" posture — parse errors surface at parse time, no silent ignoring.
- **Editor support.** Since it's real XML, any XML-aware editor gets syntax highlighting and validation for free. A schema (XSD or Relax NG) would give autocomplete and error checking. That's a real ergonomic win over pattern-strings, which no editor understands.

### Regex class

A **programmatic builder** on the Regex class — construct a pattern by calling methods that mirror the tree the XML form spells out. The starting point is instantiating the class:

~~~caspian
$rx = %('https://puck.uno/string/regex').new
~~~

The question is what shape the API takes from there. Sketch of one direction — a **block-form builder** whose method surface mirrors the XML element vocabulary 1:1:

~~~caspian
$rx = %('https://puck.uno/string/regex').new do($r)
	$r.start
	$r.capture('year') do($c)
		$c.digit.repeat(4)
	end
	$r.literal('-')
	$r.capture('month') do($c)
		$c.digit.repeat(2)
	end
	$r.literal('-')
	$r.capture('day') do($c)
		$c.digit.repeat(2)
	end
	$r.string_end
end
~~~

`.new do($r) ... end` takes a block; inside, `$r` is the builder receiver. Structural constructs (captures, groups, alternation, lookaround) take nested blocks; simple ones are single method calls. Repetition attaches to whatever came right before it — `$r.digit.repeat(4)` is "a digit, four times."

The result is a `Regex` instance equivalent to `regex(/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})$/)` — same underlying LPeg pattern, same input to `.match` / `.matches` / `.replace`.

#### Method surface (one-to-one with the XML elements)

Same vocabulary as the XML brainstorm, translated to method names:

| XML | Builder method |
|---|---|
| `<start />` | `.start` |
| `<end />` | `.string_end` (`.end` collides with the block-terminator keyword) |
| `<word-boundary />` | `.word_boundary` |
| `<literal>hello</literal>` | `.literal('hello')` |
| `<any />` | `.any` |
| `<digit />` | `.digit` |
| `<word-char />` | `.word_char` |
| `<whitespace />` | `.whitespace` |
| `<char-set>abc</char-set>` | `.char_set('abc')` |
| `<char-range from="a" to="z" />` | `.char_range('a', 'z')` |
| `<unicode-class name="Letter" />` | `.unicode_class('Letter')` |
| `<char code="0x1F600" />` | `.char(0x1F600)` |
| `<not>...</not>` | `.not do($n) ... end` |
| `<optional>...</optional>` | `.optional do ... end`, or `.optional` as a suffix on the previous element |
| `<zero-or-more>...</zero-or-more>` | `.zero_or_more do ... end`, or `.zero_or_more` as a suffix |
| `<one-or-more>...</one-or-more>` | `.one_or_more do ... end`, or `.one_or_more` as a suffix |
| `<repeat count="N">...</repeat>` | `.repeat(N)` as a suffix |
| `<repeat min="M" max="N">...</repeat>` | `.between(M, N)` as a suffix |
| `<capture>...</capture>` | `.capture do($c) ... end` (positional) |
| `<capture name="year">...</capture>` | `.capture('year') do($c) ... end` (named) |
| `<group>...</group>` | `.group do($g) ... end` (non-capturing) |
| `<any-of>...</any-of>` | `.any_of do($a) $a.alt do ... end; $a.alt do ... end end` |
| `<followed-by>...</followed-by>` | `.followed_by do ... end` |
| `<not-followed-by>...</not-followed-by>` | `.not_followed_by do ... end` |
| `<preceded-by>...</preceded-by>` | `.preceded_by do ... end` |
| `<not-preceded-by>...</not-preceded-by>` | `.not_preceded_by do ... end` |

#### Composability with variables — the real win

The XML form treats patterns as declarative documents; the builder treats them as computed values. That means variables and functions flow in naturally:

~~~caspian
$prefix = 'foo.bar'   # comes from anywhere at runtime

$rx = %('https://puck.uno/string/regex').new do($r)
	$r.start
	$r.literal($prefix)   # matches 'foo.bar' literally; the '.' is not a metacharacter
	$r.digit.one_or_more
	$r.string_end
end
~~~

`.literal($prefix)` handles escaping automatically — a `.` in `$prefix` matches a literal period, not any-character. That's the real safety win over `.match('^' + $prefix + '\d+$')`, where the prefix is silently interpreted as regex syntax and a `.` becomes a wildcard.

Higher-order composition works the same way — a Caspian function can return a builder-fragment closure:

~~~caspian
function &two_digits($r)
	$r.digit.repeat(2)
end

$rx = %('https://puck.uno/string/regex').new do($r)
	$r.start
	$r.capture('hour') do($c)
		&two_digits($c)
	end
	$r.literal(':')
	$r.capture('minute') do($c)
		&two_digits($c)
	end
	$r.string_end
end
~~~

#### Chain form vs. block form

Simple sequences read naturally as method chains:

~~~caspian
$rx.digit.repeat(4)          # four digits
$rx.word_char.one_or_more    # one or more word characters
~~~

Structural nesting (captures, alternation, groups, lookaround) needs blocks so children are grouped inside their parent:

~~~caspian
$rx.capture('year') do($c)
	$c.digit.repeat(4)
end
~~~

**A mixed surface probably reads better than either pure form.** Fully-chain form (`.repeat(4).of.digit`) is more uniform but reads backwards; fully-block form (`.repeat(4) do($r) $r.digit end`) is uniform but verbose. Mixing chain-for-modifiers with block-for-nesting matches the natural reading order and the pattern's tree shape.

#### Named subpatterns

Same idea as the XML `<define>` / `<use>`, expressed as builder methods:

~~~caspian
$rx = %('https://puck.uno/string/regex').new do($r)
	$r.define('four_digits') do($d)
		$d.digit.repeat(4)
	end
	$r.define('two_digits') do($d)
		$d.digit.repeat(2)
	end

	$r.start
	$r.capture('year')  do($c) $c.use('four_digits') end
	$r.literal('-')
	$r.capture('month') do($c) $c.use('two_digits') end
	$r.literal('-')
	$r.capture('day')   do($c) $c.use('two_digits') end
	$r.string_end
end
~~~

Or — since we're in real Caspian, not a declarative document — you can just use closures instead of the builder's own naming layer:

~~~caspian
function &two_digits($r)
	$r.digit.repeat(2)
end

$rx = %('https://puck.uno/string/regex').new do($r)
	$r.start
	$r.capture('year')  do($c) $c.digit.repeat(4) end
	$r.literal('-')
	$r.capture('month') do($c) &two_digits($c) end
	$r.literal('-')
	$r.capture('day')   do($c) &two_digits($c) end
	$r.string_end
end
~~~

Whether the builder needs its own `.define` / `.use` layer or should just lean on closures is an open call — Caspian-native closures are probably enough, and adding a parallel naming system is duplicate machinery.

#### Building without a block

The block form is one way in. A pure imperative form should also work — the builder is just an object:

~~~caspian
$rx = %('https://puck.uno/string/regex').new
$rx.start
$rx.digit.repeat(4)
$rx.literal('-')
$rx.digit.repeat(2)
$rx.literal('-')
$rx.digit.repeat(2)
$rx.string_end
~~~

Whether `$rx` here IS a Regex you can already call `.match` on, or is a builder that has to produce a Regex via `.build` / `.compile`, is a design call:

- **Direct use.** `$rx` is-a Regex; every method mutates its own pattern; `.match` at any point runs the current pattern. Zero ceremony but means the "builder" and the "compiled pattern" are the same object with mutable state.
- **Explicit finalize.** `$rx = %('puck.uno/string/regex').new(); ...build steps...; $pattern = $rx.compile`. Immutable Regex at the end; builder throws away. More ceremony but clearer separation.

Leaning direct-use for the block form (`.new do ... end` returns a completed Regex) and explicit-finalize for the imperative form (holding the builder past its build phase and reusing it invites bugs).

#### Open questions

- **`.start` / `.string_end` naming.** `.end` collides with the block-terminator keyword, so beginning-of-string and end-of-string can't share the same asymmetry. `.start` / `.string_end`, or `.line_start` / `.line_end`, or `.at_start` / `.at_end` — all workable, none perfect.
- **Repetition placement.** `.digit.repeat(4)` reads left-to-right ("digit, four times"); `.repeat(4) do $r.digit end` is uniform-with-blocks. Pick one convention or allow both.
- **Alternation ergonomics.** `.any_of do($a) $a.alt do ... end end` is clunky. Could accept an array of closures: `.any_of([function &($x) $x.literal('a') end, function &($x) $x.literal('b') end])`. Or a variadic block-list. Open.
- **How does it relate to `regex(/.../)` and string form?** Same underlying `Regex` class; three ways to construct it. Should the builder be reachable as `Regex.new` (built-in class exposed by name), `%('puck.uno/string/regex').new` (Puck-download form the user example uses), or both? Probably both — the same class, reachable through either surface.
- **Post-V1 or V1?** The XML form is post-V1 per the scope note above. The programmatic builder is more foundational — a real regex class in Caspian ought to be constructible programmatically from the start. Argues for V1 inclusion, at least in a minimal form.

## Related in-tree

- [built-in-classes/primitives/string/regular-expressions](https://puck.uno/requirements/built-in-classes/primitives/string/regular-expressions) — the stub in `requirements/` that pins LPeg as the engine and defers pattern-syntax docs to LPeg's own reference. Fills in with the settled-and-decided content from this brainstorm as pieces land.
