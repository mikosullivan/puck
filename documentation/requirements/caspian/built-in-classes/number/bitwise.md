# Bitwise
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_number_bitwise",
	"role": "spec for the bitwise wrapper accessed via .bitwise on a number. The wrapper keeps the number class uncluttered, makes bitwise intent explicit at the call site, and frees the top-level `|` and `&` characters for other uses (pipe and function-call sigil respectively). Each bitwise method returns a plain number — no implicit chaining; each operation requires its own `.bitwise` accessor.",
	"status": "draft — method surface spec'd; bit-width mechanics for width-sensitive ops (not, shift_left, shift_right) noted as open",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

Bit-level operations on numbers are exposed through a dedicated **wrapper object** accessed via `.bitwise`. This keeps the [number class](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/) uncluttered, makes bitwise intent explicit at the call site, and frees the top-level operators (`|` used for pipe, `&` used as the call sigil) for their more common meanings.

## Access

Call `.bitwise` on any whole-value number to get the wrapper, then call a bitwise method on it:

~~~caspian
$n = 123
$result = $n.bitwise.or(456)
~~~

Calling `.bitwise` on a number with a fractional part raises — bit-level operations are only defined for whole-value numbers.

## Each operation returns a plain number

**Every bitwise method returns a plain number**, not another wrapper. Multiple bitwise operations don't chain — each one needs its own `.bitwise` accessor:

~~~caspian
# Right — each bitwise operation gets its own `.bitwise`.
$result = 123.bitwise.or(456).bitwise.and(0xFF).bitwise.xor(7)

# Wrong — assumes chaining. `.or(456)` returns a number; the number
# doesn't have `.and` on its surface directly.
$result = 123.bitwise.or(456).and(0xFF).xor(7)
~~~

Each `.bitwise` at the call site is a deliberate "I mean bitwise" marker. Nothing silently propagates a "bitwise mode" through subsequent method calls.

## Methods

Every method returns a plain [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/). Where a method takes a right-hand operand, it's a plain number.

| Method | Alias | Description |
|---|---|---|
| `.or($n)` | | Bitwise OR. |
| `.and($n)` | | Bitwise AND. |
| `.xor($n)` | | Bitwise XOR. |
| `.nand($n)` | | Bitwise NAND (NOT AND). |
| `.nor($n)` | | Bitwise NOR (NOT OR). |
| `.xnor($n)` | | Bitwise XNOR (NOT XOR). |
| `.not` | | Bitwise NOT — inverts all bits within the operating bit width. Unary. |
| `.shift_left($k)` | `<<` | Shift bits left by `$k` positions. Bits shifted off the top are dropped. |
| `.shift_right($k)` | `>>` | Shift bits right by `$k` positions. |

The alias forms let the wrapper participate in operator-position syntax: `$n.bitwise << 3` is equivalent to `$n.bitwise.shift_left(3)`. Both return a plain number.

## Worked example

Bit-flag manipulation. Each set/test operation is written explicitly with its own `.bitwise`:

~~~caspian
$flags = 0b0000_0000

$flags = $flags.bitwise.or(0b0000_0001)   # set bit 0 → 0b0000_0001
$flags = $flags.bitwise.or(0b0001_0000)   # set bit 4 → 0b0001_0001

$has_bit_4 = $flags.bitwise.and(0b0001_0000) != 0   # test bit 4

$mask = 0xFF
$low_byte = $some_word.bitwise.and($mask)
~~~

## Bit-width mechanics

For **AND**, **OR**, **XOR**, **NAND**, **NOR**, **XNOR**, the bit width doesn't matter — the result is defined bit-by-bit regardless of how many bits each operand has.

For **NOT** and the **shift** operations, the answer depends on how many bits are being operated on. `.not(1)` could return `-2` (in two's-complement at any width) or `0xFFFF_FFFE` (32-bit width) or `0xFFFF_FFFF_FFFF_FFFE` (64-bit width). The three width-sensitive operations need a rule.

**Open — the bit-width rule.** Two candidate directions:

- **Fixed default (e.g., 64-bit two's-complement) with a `bits:` kwarg to override.** `.not(bits: 32)` operates in a 32-bit window; the default of 64 covers the common case. Predictable; the caller opts in to alternate widths.
- **Width determined by the operand's minimum representation.** `.not` on `0b0101` operates in the 4-bit window of the input; results are compact. Less predictable for callers used to fixed-width integers.

The first is more familiar to programmers coming from C-family languages; the second is more Caspian-native (numbers don't have a fixed width in Caspian's data model). Waiting for a decision.

## Related

- [Number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/) — the parent class; `.bitwise` is a method on every whole-value number.
- The [number § Testing](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/#testing) predicates — `.integer?`, `.even?`, `.odd?` — often paired with bitwise operations.
