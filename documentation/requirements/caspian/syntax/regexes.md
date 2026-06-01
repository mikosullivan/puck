# Patterns

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"role": "introduces Caspian pattern matching using Lua patterns by default",
	"key_concepts": ["Lua_patterns", "default_engine", "no_alternation", "no_named_captures",
		"no_quantifier_range", "restructure_in_caspian"]
}}
~~~

Caspian uses [LPeg](../../development/v1/details/lua-dependencies.md#lpeg)
as the default pattern engine. PEG (Parsing Expression Grammar) is strictly
more powerful than traditional regex: it supports alternation (`|`),
recursion, named captures, and arbitrary lookahead. ~50 KB in the install.

Lua's built-in patterns are available as a lightweight engine option for
space-constrained deployments — they cover character classes, quantifiers,
captures, and anchors, but lack alternation, named captures, lookahead, or
`{n,m}` quantifiers. With Lua patterns active, restructure the logic in
Caspian rather than reaching for a more powerful pattern language.

<a id="pattern-engine"></a>
## Pattern Engine

~~~json
{"vibecode": {
	"section": "pattern_engine",
	"role": "documents the swappable central pattern engine object and available alternative engines",
	"v1_default": "lpeg",
	"v1_lightweight_alternative": "lua_patterns_built_in",
	"key_concepts": ["swappable_engine", "central_engine_object", "lpeg",
		"lua_patterns", "PCRE2", "RE2", "named_captures",
		"transparent_routing"]
}}
~~~

The pattern engine is not hardwired. A central engine object tracks which pattern library
is in use, and all pattern operations (`match`, `match?`, etc.) route through it. Code
that calls `$string.match(...)` does not need to know which engine is active.

Design around this object from the start: when adding pattern-related features, direct
them through the engine object rather than calling the active library's pattern
functions directly. This keeps the engine swappable.

<a id="available-engines"></a>
### Available engines

| Engine | Size | Alternation (`\|`) | Named captures | Lookahead | Notes |
|---|---|---|---|---|---|
| **LPeg** (default in V1) | ~50 KB | Yes | Yes | Yes | PEG library; strictly more powerful than regex. See [lua-dependencies.md § LPeg](../../development/v1/details/lua-dependencies.md#lpeg). |
| Lua patterns (built-in) | 0 KB additional | No | No | No | Lua's own pattern library. Limited but free — already part of every Lua install. |
| PCRE2 | ~500 KB | Yes | Yes | Yes | Full Perl-compatible regex. Pluggable when full PCRE syntax is wanted. |
| RE2 | ~1–2 MB | Yes | Yes | No (by design) | Google's linear-time-guaranteed regex. Pluggable when DOS-resistance matters. |

**V1 ships LPeg as the default engine.** Lua patterns are still available
as the lightweight fallback when the program / runtime is space-constrained
and `|` (alternation) isn't needed. PCRE2 and RE2 are plugin options for
environments with no install-size constraint.

Features available depend on which engine is active. With LPeg, you get
alternation, recursion, and full PEG expressiveness. With Lua patterns, you
get character classes and basic quantifiers — restructure logic in Caspian
for anything that would need `|`. Plug in PCRE2 or RE2 for richer regex
features.

<a id="pattern-syntax"></a>
### Pattern syntax

**Open: the canonical Caspian pattern syntax isn't pinned yet.** With
LPeg as the V1 default engine, there are two paths:

1. **Caspian regex syntax** — define a regex-style string syntax
   (resembling PCRE: `.`, `*`, `+`, `?`, `|`, `[...]`, `(...)`,
   `\d`/`\w`/`\s` etc.) that we compile to LPeg patterns internally.
   Users get familiar regex; LPeg powers it under the hood. Requires a
   ~100–200 line regex-to-LPeg compiler.
2. **Native LPeg syntax** — expose LPeg's own pattern language directly.
   Very powerful but unfamiliar to users coming from regex; uses `/` for
   alternation, not `|`.

Path (1) is the more user-friendly default and aligns with "we want
good regular expressions." Path (2) is the smallest implementation
surface. Decide before V1 ships.

The syntax table below is the **Lua-patterns engine** reference (still
available as the lightweight alternative — see [Available engines](#available-engines)):

| Pattern | Meaning |
|---|---|
| `%a` | Letters |
| `%d` | Digits |
| `%l` | Lowercase letters |
| `%u` | Uppercase letters |
| `%s` | Whitespace |
| `%w` | Alphanumeric |
| `%p` | Punctuation |
| `.` | Any character |
| `*` | 0 or more (greedy) |
| `+` | 1 or more (greedy) |
| `-` | 0 or more (lazy) |
| `?` | 0 or 1 |
| `^` | Anchor to start |
| `$` | Anchor to end |
| `[set]` | Character set |
| `()` | Capture |
| (no alternation) | use multiple `.match?` calls or switch engines |

---

<a id="methods"></a>
## Methods

~~~json
{"vibecode": {
	"section": "methods",
	"role": "documents match, match?, and chaining methods on strings",
	"key_concepts": ["match", "match_boolean", "chaining", "negation", "null_safe_navigation", "Match_object"]
}}
~~~

<a id="stringmatchpattern"></a>
### `$string.match(pattern)`

Returns a `Match` object if the pattern matches, or `null` if it does not. Use safe
navigation to handle the null case:

```
$string.match('pattern')&.text
```

<a id="stringmatchpattern-1"></a>
### `$string.match?(pattern)`

Returns a boolean. Does not allocate a match object — use this when you only need to
know whether the pattern matched:

```
if $string.match?('%d+')
end
```

<a id="chaining"></a>
### Chaining

`.match()` can be chained. Each call narrows the result, operating on the text of the
previous match:

```
$string.match('blah blah').match('blue')
```

<a id="negation"></a>
### Negation

```
$string.match('pattern', not:true)
```

---

<a id="match-object"></a>
## Match Object

~~~json
{"vibecode": {
	"section": "match_object",
	"role": "documents all properties of the Match object returned by string.match",
	"key_concepts": ["Match.text", "Match.start", "Match.end", "Match.groups", "Match.matches",
		"Match.count", "string_conversion"]
}}
~~~

| Property | Description |
|---|---|
| `$match.text` | The full matched string |
| `$match.start` | Start position in the original string |
| `$match.end` | End position in the original string |
| `$match.groups` | Array of captured groups, empty if none |
| `$match.groups[0]` | First captured group by position |
| `$match.matches` | All matches as an array of Match objects |
| `$match.count` | Number of matches |

<a id="string-conversion"></a>
### String Conversion

A `Match` object converts to its matched text when used in a string context:

```
$string = 'abc123def'
$match = $string.match('%d+')

puts $match    # "123"

$result = 'value: ' + $match
# "value: 123"
```

If `$match` is `null`, it behaves according to standard `null` string conversion rules.
