# Number
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_number",
	"role": "spec for Caspian's built-in number class — the class every numeric literal materializes into. One value shape for both integers and fractional values (the language does not distinguish); four subclasses (Decimal, Binary, Octal, Hex) that differ only in stringification, with fractional values represented via a C99-extended pattern uniformly across all four bases. Arithmetic across subclasses follows the left-operand rule (operators are methods on the left operand's class). Covers literal forms, the immutability rule, arithmetic, comparison, testing predicates, rounding-by-multiple, math methods, bitwise (via .bitwise), and conversion methods.",
	"status": "draft — most of the method surface spec'd; open questions at the bottom",
	"audience": "developers writing Caspian; engine implementers building the numeric runtime; tooling authors"
}}
~~~

A **number** represents a numeric value. Caspian does not distinguish between integers and fractional values — both are just numbers, and both are instances of this one class. Every numeric literal in Caspian source materializes into a number.

## Literal forms

- **Whole-value:** `0`, `42`, `-5`, `1_000_000`.
- **Fractional:** `3.14`, `-0.5`, `1e10`, `2.5e-3`.
- **Hexadecimal:** `0xFF`, `0xFF_FF`.
- **Octal:** `0o755`.
- **Signed:** a leading `-` produces a negative value.
- **Underscore separators** are ignored by the lexer and can be used freely as digit separators for readability:

~~~caspian
$big = 1_000_000       # same as 1000000
$pi  = 3.141_592_653   # same as 3.141592653
$hex = 0xFF_FF         # same as 0xFFFF
~~~

Leading and trailing underscores are invalid. Doubled underscores between digits are allowed.

Full lexer rules live under [syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals).

## One class, not two

`42` and `3.14` are the **same class**. There is no separate `integer` or `float` type in Caspian source; there's just `number`, and it holds both. Arithmetic between any two numbers is just arithmetic — no int-vs-float promotion rules, no conversion methods (`.to_integer`, `.to_float`) to reach for. The internal representation the engine uses to store a number may still distinguish (an integer-shaped value can be stored more efficiently than a fractional one), but that's an implementation detail; from the language's perspective, everything is `number`.

Methods that only make sense for whole-value numbers handle non-integers each in a way that fits their shape: `.even?` and `.odd?` return false rather than raise (the number isn't even OR odd — those categories only apply to integers); bitwise operations raise on any number with a fractional part. See [Testing](#testing) and [Bitwise](#bitwise) below.

## Subclasses for stringification

Number has four subclasses, one per string-representation base:

| Subclass | `.to_string` produces |
|---|---|
| `Number::Decimal` | `"255"`, `"3.14"` (base 10; the default). |
| `Number::Binary` | `"0b11111111"`, `"0b1.1011001110000110000000101p+1"`. |
| `Number::Octal` | `"0o377"`, `"0o1.5470736p+1"`. |
| `Number::Hex` | `"0xff"`, `"0x1.b38ef34d6a162p+1"`. |

**All four share the same method surface** — arithmetic, comparison, testing predicates, bitwise, rounding, math, and iteration all behave identically. The only method that differs is `.to_string`. Value equality holds across subclasses: `0xFF == 255` is true; `.to_string` differs but the value is the same.

### Literal materialization

Each literal form materializes into the matching subclass:

~~~caspian
$a = 255             # Number::Decimal
$b = 0b11111111      # Number::Binary
$c = 0o377           # Number::Octal
$d = 0xFF            # Number::Hex

$a == $b == $c == $d   # all true — same value
$a.to_string           # "255"
$d.to_string           # "0xff"
~~~

### Arithmetic follows the left-operand's subclass

Because operators are methods on the left operand's class, arithmetic between different subclasses produces a result of the LEFT operand's subclass:

~~~caspian
0xFF + 1        # Number::Hex(256); .to_string returns "0x100"
1 + 0xFF        # Number::Decimal(256); .to_string returns "256"
0b1010 + 0xFF   # Number::Binary(265); .to_string returns "0b100001001"
~~~

No arithmetic-promotion table to memorize; this is the general Caspian rule — `a op b` desugars to `a.<op>(b)` — applied to number arithmetic. Same principle as `&` being a method on the class of the object you're calling it on.

### Fractional forms use a C99-extended pattern

For fractional values, all four subclasses use a uniform pattern extended from C99 hex-float literals:

    <prefix><integer-part>.<fractional-part>p<binary-exponent>

Where:

- Prefix is `0b`, `0o`, or `0x` (Decimal has no prefix).
- Mantissa is normalized so `1 ≤ mantissa < 2`; digits are in the base's alphabet.
- `p` is the separator (kept because `e`, `f`, `b`, `o` are valid mantissa characters in one or another base and would ambiguate).
- Exponent is a signed decimal integer meaning "multiply by 2^n." Always a binary shift, regardless of base — matches C99's hex-float convention and keeps IEEE 754 round-trip clean.

The value 3.4028 in all four subclass string forms:

~~~caspian
$n = 3.4028

$n.to_string             # "3.4028"                              (Decimal)
$n.to_bin.to_string      # "0b1.1011001110000110000000101p+1"    (Binary)
$n.to_oct.to_string      # "0o1.5470736p+1"                     (Octal)
$n.to_hex.to_string      # "0x1.b38ef34d6a162p+1"               (Hex)
~~~

Whole-value numbers use the compact form with no exponent:

~~~caspian
255.to_hex.to_string     # "0xff"
255.to_bin.to_string     # "0b11111111"
255.to_oct.to_string     # "0o377"
~~~

## Negative zero

Zero has a signed variant: `-0`. Arithmetically it equals `0`:

~~~caspian
-0 == 0        # true
0 * -1         # 0 (arithmetic strips the negation)
-0 * -1        # 0 (same)
0 + -0         # 0
~~~

**Arithmetic never produces `-0`.** Any operation on numbers produces a plain `0` when the result is zero; the negation is only present when the caller wrote the literal `-0` in source. Even unary minus on a zero-valued expression produces plain `0`:

~~~caspian
$i = 0
-$i            # 0 (not -0) — unary minus is arithmetic
~~~

The one place `-0` differs from `0` is **[array indexing](https://puck.uno/documentation/requirements/caspian/built-in-classes/array#zero-based-indexing-from-both-ends)**: `$arr[-0]` is the last element, while `$arr[0]` is the first. Every other consumer of the value — equality, hash keys, JSON serialization, comparison, `.to_string`, `.to_hex`, `.to_bin` — treats `-0` as `0`.

The internal representation carries a "sign-of-zero" slot on the number object that only matters for the array-indexing lookup. Every other read of the value ignores it. Cost is negligible; benefit is symmetric array indexing.

The pattern is likely to be unfamiliar — very few languages give `-0` a semantic meaning for integers. Documentation makes the convention explicit at the array-indexing surface where it applies.

## Immutability

**Numbers are immutable.** Every arithmetic operation returns a **new** number instance rather than mutating any of the operands.

~~~caspian
$x = 5
$y = $x + 1                # $y is 6; $x is still 5
$x += 1                    # $x is now 6; the "+=" compound-assignment rebinds
                           # $x to a new number, doesn't mutate the old one
~~~

Numbers being immutable is what makes them safe to share freely — passing a number to a downloaded object doesn't hand the recipient a way to alter your data.

## Arithmetic

| Operator | Returns | Description |
|---|---|---|
| `+` | number | Addition. |
| `-` | number | Subtraction. |
| `*` | number | Multiplication. |
| `/` | number | Division. |
| `%` | number | Modulo. |
| `**` | number | Exponentiation. `2 ** 10` returns `1024`. |

## Comparison

| Operator | Returns | Description |
|---|---|---|
| `==` | boolean | True if both values are equal. |
| `!=` | boolean | True if values differ. |
| `<` | boolean | Less than. |
| `<=` | boolean | Less than or equal. |
| `>` | boolean | Greater than. |
| `>=` | boolean | Greater than or equal. |

## Testing

Predicate methods (return a [boolean](https://puck.uno/documentation/requirements/caspian/built-in-classes/boolean)):

| Method | Description |
|---|---|
| `.zero?` | True if the value is 0. |
| `.positive?` | True if the value is greater than 0. |
| `.negative?` | True if the value is less than 0. |
| `.integer?` | True if the value has no fractional part. |
| `.even?` | True if the value is divisible by 2. Returns false for any non-integer. |
| `.odd?` | True if the value is not divisible by 2. Returns false for any non-integer. |
| `.finite?` | True if the value is finite (not infinity). |
| `.infinite?` | True if the value is positive or negative infinity. |

## Rounding

All three rounding methods operate on **multiples**. The `multiple:` kwarg specifies the step to round to; if omitted, it defaults to `1`.

| Method | Description |
|---|---|
| `.round(multiple: N)` | Nearest multiple. Midpoint rounds away from zero. |
| `.round_up(multiple: N)` | Smallest multiple ≥ the value (ceiling relative to the multiple). |
| `.round_down(multiple: N)` | Largest multiple ≤ the value (floor relative to the multiple). |

`multiple` must be a non-zero number; passing `0` raises.

### Midpoint rule

When a value falls exactly halfway between two multiples, Caspian rounds **half away from zero**:

~~~caspian
5.round(multiple: 10)          # returns 10
(-5).round(multiple: 10)       # returns -10
~~~

### Examples

~~~caspian
$foo = 2.5

$foo.round                     # returns 3
$foo.round(multiple: 10)       # returns 0
$foo.round_up(multiple: 10)    # returns 10
$foo.round_down(multiple: 10)  # returns 0
~~~

~~~caspian
$foo = 12.3    # exactly at the midpoint between 12.2 and 12.4

$foo.round(multiple: 0.2)      # returns 12.4 (midpoint rule — half away from zero)
$foo.round_up(multiple: 0.2)   # returns 12.4
$foo.round_down(multiple: 0.2) # returns 12.2
~~~

~~~caspian
$foo = 12.25   # NOT a midpoint — 12.25 is 0.05 from 12.2 and 0.15 from 12.4

$foo.round(multiple: 0.2)      # returns 12.2 (nearest multiple, unambiguously)
$foo.round_up(multiple: 0.2)   # returns 12.4
$foo.round_down(multiple: 0.2) # returns 12.2
~~~

~~~caspian
$foo = -2.5

$foo.round                     # returns -3
$foo.round(multiple: 10)       # returns 0
$foo.round_up(multiple: 10)    # returns 0
$foo.round_down(multiple: 10)  # returns -10
~~~

## Math

| Method | Description |
|---|---|
| `.absolute` | Absolute value \|x\|. Always returns a non-negative number. `(-5).absolute` returns `5`; `5.absolute` returns `5`; `0.absolute` returns `0`. |
| `.absolute_negative` | Negative absolute value -\|x\|. Always returns a non-positive number. `(-5).absolute_negative` returns `-5`; `5.absolute_negative` returns `-5`; `0.absolute_negative` returns `0` (arithmetic strips the negation — see [Negative zero](#negative-zero)). |
| `.negate` | Flips the sign. `5.negate` returns `-5`; `(-5).negate` returns `5`; `0.negate` returns `0` (arithmetic strips the negation). |
| `.square_root` | Square root. |
| `.√` | Alias for `.square_root`. Callable as `$foo.√`. |

## Bitwise

| Method | Description |
|---|---|
| `.bitwise` | Returns a chainable [bitwise-wrapper object](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/bitwise) around the number. |

Full method surface — `.or`, `.and`, `.xor`, `.not`, `.shift_left` (aliased `<<`), `.shift_right` (aliased `>>`), `.nand`, `.nor`, `.xnor` — is spec'd at [bitwise](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/bitwise). Bitwise operations are only meaningful on whole-value numbers; `.bitwise` on any number with a fractional part raises.

## Conversion

Between subclasses. Each of these returns a number with the same value but the target subclass — arithmetic and comparison are unaffected, `.to_string` changes format:

| Method | Returns | Description |
|---|---|---|
| `.to_dec` | number | Returns a `Number::Decimal` with the same value. |
| `.to_num` | number | Alias for `.to_dec`. |
| `.to_bin` | number | Returns a `Number::Binary` with the same value. |
| `.to_oct` | number | Returns a `Number::Octal` with the same value. |
| `.to_hex` | number | Returns a `Number::Hex` with the same value. |

Other conversions:

| Method | Returns | Description |
|---|---|---|
| `.to_string` | string | The string representation using this instance's subclass form. See [Subclasses for stringification](#subclasses-for-stringification) above. |
| `.to_integer` | number | Truncates toward zero to a whole-value number. Preserves the caller's subclass — `0xFF.to_integer` returns `Number::Hex(255)`. |
| `.commafy` | string | Format with comma thousands separators and period decimal point. `1_000_000.commafy` returns `'1,000,000'`; `1_234_567.89.commafy` returns `'1,234,567.89'`. |
| `.dotify` | string | Format with period thousands separators and comma decimal point. `1_000_000.dotify` returns `'1.000.000'`; `1_234_567.89.dotify` returns `'1.234.567,89'`. |

## Iteration

Numeric iteration helpers — `.times`, `.upto`, `.downto` — live under [syntax § Blocks and iteration](https://puck.uno/documentation/requirements/caspian/syntax/blocks-and-iteration).

## Open questions

- Should `.square_root` (and `.√`) of a negative number raise, return null (possibly with a flavor like `:undefined`), or something else?
- Should `.to_string` accept a format kwarg (number of decimal places, sign handling, etc.), or is that formatting a separate spec?
- Floating-point representation limits affect rounding operations with small multiples. Whether the spec calls out specific IEEE 754 corners (subnormals, infinity handling around midpoints) explicitly, or lets the implementation choose within reasonable bounds, is unresolved.
