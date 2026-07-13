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

## Testing

### Access

- **`.bitwise` on a whole-value number returns the wrapper** — `123.bitwise` is a `Bitwise` instance.
- **`.bitwise` on a fractional number raises** — `3.14.bitwise` raises.
- **`.bitwise` on negative whole values works** — `(-5).bitwise` returns a wrapper.
- **`.bitwise` on zero works** — `0.bitwise` returns a wrapper.
- **`.bitwise` on each subclass works** — `0xFF.bitwise`, `0b1010.bitwise`, `0o755.bitwise`, `255.bitwise` all succeed.

### Each operation returns a plain number

- **Return of `.or($n)` is a Number** — not a wrapper; `.and`, `.xor`, `.nand`, `.nor`, `.xnor`, `.not`, `.shift_left`, `.shift_right` all return Number.
- **No implicit chaining** — `123.bitwise.or(456).and(0xFF)` raises (the returned number has no `.and`); must be written `123.bitwise.or(456).bitwise.and(0xFF)`.

### `.or($n)`

- **Basic OR** — `0b1100.bitwise.or(0b1010)` is `0b1110` (14).
- **OR with zero** — `0b1100.bitwise.or(0)` is `0b1100`.
- **OR with all-ones (at width)** — result is all-ones for that width.
- **OR with itself** — `$n.bitwise.or($n)` equals `$n`.
- **OR is commutative** — `$a.bitwise.or($b)` equals `$b.bitwise.or($a)`.

### `.and($n)`

- **Basic AND** — `0b1100.bitwise.and(0b1010)` is `0b1000` (8).
- **AND with zero is zero** — `0b1100.bitwise.and(0)` is `0`.
- **AND with itself** — `$n.bitwise.and($n)` equals `$n`.
- **AND is commutative**.

### `.xor($n)`

- **Basic XOR** — `0b1100.bitwise.xor(0b1010)` is `0b0110` (6).
- **XOR with zero** — `$n.bitwise.xor(0)` equals `$n`.
- **XOR with itself is zero** — `$n.bitwise.xor($n)` is `0`.
- **XOR is commutative**.

### `.nand($n)`

- **NAND is NOT of AND** — `$a.bitwise.nand($b)` equals `$a.bitwise.and($b).bitwise.not` at the same width.
- **NAND with zero** — result is all-ones (per width).
- **NAND with itself** — `$n.bitwise.nand($n)` equals `$n.bitwise.not`.

### `.nor($n)`

- **NOR is NOT of OR** — `$a.bitwise.nor($b)` equals `$a.bitwise.or($b).bitwise.not` at the same width.
- **NOR with zero** — `$n.bitwise.nor(0)` equals `$n.bitwise.not`.

### `.xnor($n)`

- **XNOR is NOT of XOR** — `$a.bitwise.xnor($b)` equals `$a.bitwise.xor($b).bitwise.not` at the same width.
- **XNOR with itself** — `$n.bitwise.xnor($n)` is all-ones for that width.

### `.not`

- **`.not` inverts all bits within the operating bit width** — width behavior per the settled rule (open question).
- **`.not.not` is identity** — `$n.bitwise.not.bitwise.not` equals `$n`.
- **`.not(0)` is all-ones for the chosen width**.
- **`.not(all-ones)` is `0`**.

### `.shift_left($k)` / `<<`

- **`.shift_left(1)` multiplies by 2** for whole values — `0b0001.bitwise.shift_left(1)` is `0b0010`.
- **`.shift_left(0)` is identity**.
- **`.shift_left($k)` drops bits shifted off the top** — width-sensitive per the settled rule.
- **`<<` alias** — `$n.bitwise << 3` equals `$n.bitwise.shift_left(3)`.
- **`<<` returns a plain number**.

### `.shift_right($k)` / `>>`

- **`.shift_right(1)` divides by 2** for whole values (assuming non-negative under the settled width rule) — `0b0100.bitwise.shift_right(1)` is `0b0010`.
- **`.shift_right(0)` is identity**.
- **`>>` alias** — `$n.bitwise >> 3` equals `$n.bitwise.shift_right(3)`.

### Bit-flag manipulation (integration)

- **Set a bit** — starting from `0b0000_0000`, `.bitwise.or(0b0000_0001)` gives `0b0000_0001`.
- **Test a bit** — `$flags.bitwise.and(0b0001_0000) != 0` tests bit 4.
- **Mask a low byte** — `$word.bitwise.and(0xFF)` returns the low byte.
- **Clear a bit** — set-and-XOR pattern per the settled width rule.

### Width sensitivity (open — test the settled rule)

- **`.not`, `.shift_left`, `.shift_right` behavior at the chosen default width** — tests should exercise the boundary bits.
- **`bits:` kwarg overrides width** if the fixed-default option lands — e.g., `.not(bits: 8)` operates in an 8-bit window.
- **Bit-width rule choice reflected consistently** — same operand under the same width gives the same result for all three width-sensitive methods.

## Related

- [Number](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/number/) — the parent class; `.bitwise` is a method on every whole-value number.
- The [number § Predicates](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/number/#predicates) — `.integer?`, `.even?`, `.odd?` — often paired with bitwise operations.
