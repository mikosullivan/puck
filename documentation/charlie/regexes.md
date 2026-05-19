# Patterns

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"role": "introduces Charlie pattern matching using Lua patterns by default",
	"key_concepts": ["Lua_patterns", "default_engine", "no_alternation", "no_named_captures",
		"no_quantifier_range", "restructure_in_charlie"]
}}
~~~

Charlie uses Lua's built-in pattern matching by default. Lua patterns cover the common
use cases cleanly — character classes, quantifiers, captures, anchors — without the
complexity of full regular expressions.

Lua patterns do not support alternation (`|`), named captures, lookahead, or `{n,m}`
quantifiers. If you need those features, restructure the logic in Charlie rather than
reaching for a more powerful pattern language.

<a id="pattern-engine"></a>
## Pattern Engine

~~~json
{"vibecode": {
	"section": "pattern_engine",
	"role": "documents the swappable central pattern engine object and available alternative engines",
	"key_concepts": ["swappable_engine", "central_engine_object", "RE2", "PCRE2", "named_captures", "transparent_routing"]
}}
~~~

The pattern engine is not hardwired. A central engine object tracks which pattern library
is in use. The default is Lua's built-in patterns, but a different engine — RE2, PCRE2,
or any other — can be plugged in by replacing the engine object.

All pattern operations (`match`, `match?`, etc.) route through this central object. Code
that calls `$string.match(...)` does not need to know which engine is active.

Design around this object from the start: when adding pattern-related features, direct
them through the engine object rather than calling Lua's pattern functions directly. This
keeps the engine swappable.

Named captures and other RE2-specific features are not supported with the default Lua
engine. If a richer engine is plugged in, those features become available automatically
— no changes to the calling code required.

<a id="pattern-syntax"></a>
### Pattern syntax

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

puts($match)    # "123"

$result = 'value: ' + $match
# "value: 123"
```

If `$match` is `null`, it behaves according to standard `null` string conversion rules.
