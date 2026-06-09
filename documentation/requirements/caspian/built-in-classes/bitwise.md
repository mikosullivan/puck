# Bitwise Object

<a id="overview"></a>
## Overview

~~~vibecode
{"vibecode": {
	"section": "overview",
	"concept": "bitwise_operations_via_dedicated_wrapper_object",
	"access": "$n.bitwise",
	"rationale": "keeps_Number_class_uncluttered_makes_intent_explicit"
}}
~~~

Bitwise operations are exposed through a dedicated bitwise object rather than as direct
methods on Number. This keeps the Number class uncluttered and makes bitwise intent
explicit at the call site.

<a id="access"></a>
## Access

~~~vibecode
{"vibecode": {
	"section": "access",
	"method": "bitwise",
	"returns": "Bitwise object",
	"example": "$n.bitwise.or(456)"
}}
~~~

Call `.bitwise` on any Number to get a bitwise object wrapping that value:

```
$n = 123
$n.bitwise.or(456)
```

---

<a id="open-questions"></a>
## Open Questions

- Do operations take a second Number argument, or does the bitwise object wrap the value
  and chain? e.g. `$a.bitwise.or($b)` vs `$a.bitwise.or($b).and($c)`
- What does `not` return for negative numbers? Behavior depends on the integer
  representation (two's complement assumed).
- Are bitwise operations defined only for integers? Should calling `.bitwise` on a
  non-integer raise an error?

---

<a id="methods"></a>
## Methods

~~~vibecode
{"vibecode": {
	"section": "methods",
	"methods": ["or", "and", "xor", "not", "shift_left", "shift_right",
		"nand", "nor", "xnor"],
	"aliases": {"shift_left": "<<", "shift_right": ">>"},
	"notes": ["not_is_unary", "assumes_twos_complement_for_negative_numbers"]
}}
~~~

| Method | Alias | Description |
|--------|-------|-------------|
| `or` | | Bitwise OR |
| `and` | | Bitwise AND |
| `xor` | | Bitwise XOR |
| `not` | | Bitwise NOT (unary; inverts all bits) |
| `shift_left` | `<<` | Shift bits left by N positions |
| `shift_right` | `>>` | Shift bits right by N positions |
| `nand` | | Bitwise NAND (NOT AND) |
| `nor` | | Bitwise NOR (NOT OR) |
| `xnor` | | Bitwise XNOR (NOT XOR) |
