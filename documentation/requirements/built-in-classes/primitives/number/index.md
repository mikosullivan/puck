# Number
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_built_in_number",
	"role": "spec for Caspian's built-in number class — the class every numeric literal materializes into. One value shape for both integers and fractional values (the language does not distinguish); four subclasses (Decimal, Binary, Octal, Hex) that differ only in stringification, with fractional values represented via a C99-extended pattern uniformly across all four bases. Arithmetic across subclasses follows the left-operand rule (operators are methods on the left operand's class). Covers literal forms (including leading-dot `.5` and the trailing-dot-is-a-parse-error rule), the method-call disambiguation on numeric literals (`5.times` splits into number-then-method via single-char lookahead after digit-plus-dot), immutability, arithmetic, comparison, testing predicates, rounding-by-multiple, math methods, bitwise (via .bitwise), and conversion methods.",
	"status": "draft — most of the method surface spec'd; open questions at the bottom",
	"audience": "developers writing Caspian; engine implementers building the numeric runtime; tooling authors"
}}
~~~

A **number** represents a numeric value. Caspian does not distinguish between integers and fractional values — both are just numbers, and both are instances of this one class. Every numeric literal in Caspian source materializes into a number.

## Literal forms

- **Whole-value:** `0`, `42`, `-5`, `1_000_000`.
- **Fractional:** `3.14`, `-0.5`, `1e10`, `2.5e-3`.
- **Leading-dot fractional:** `.5` (== `0.5`), `-.75` (== `-0.75`). The `0` before the dot is optional.
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

### Numeric literals must end with a digit

A number literal **must end with a digit**. A trailing bare `.` (no fractional digits following) is a parse error, not a shorthand for `.0`:

~~~caspian
5.0     # ok
5       # ok
5.      # RAISES — bare trailing dot on numeric literal
~~~

Write `5` for the integer or `5.0` for the fractional form. The trailing-dot rejection matters for method-call disambiguation: `5.times` unambiguously splits into the integer `5` and the method call `.times` (see [§ Method calls on numeric literals](#method-calls-on-numeric-literals)), and that split rule needs the "no trailing dot on numbers" guarantee to work.

### Numbers do not have to start with a digit

The `0` in `0.5` is optional — `.5` is a valid numeric literal equal to `0.5`. Same for the signed form: `-.75` is `-0.75`. Both forms are equivalent; use whichever reads better at the site. The lexer recognizes `.` followed by a digit as the start of a numeric literal.

~~~caspian
$half   = .5
$dashed = -.75
$sum    = .1 + .2      # both operands leading-dot; result is 0.3 (rounding aside)
~~~

## Method calls on numeric literals

Numeric literals are ordinary values, and Caspian supports method calls on them directly — `5.times`, `3.14.floor`, `.5.ceiling`, `0xFF.to_string`, etc. The parser disambiguates the two roles of `.` (fractional-digit separator vs method-call operator) with a **single-character lookahead** after any digit-then-dot sequence:

| Pattern | Interpretation |
|---|---|
| `<digit>.<digit>` | Continue as a numeric literal — the second digit is the start of the fractional part. |
| `<digit>.<letter/underscore>` | Split. The digit sequence terminates as a number; the `.<name>` starts a method call. |

The rule relies on two other rules already in place:

- **Identifiers can't start with a digit.** So after a `.`, if the next character is a digit, it's a fractional continuation — never a method name (there's no such method name).
- **Numeric literals must end with a digit.** So there's no `5.` on its own to be ambiguous with — a bare trailing dot is a parse error.

With those two rules holding, disambiguation is deterministic and single-pass:

~~~caspian
5.5             # numeric literal — 5.5
5.times         # integer 5, then method call .times
5.5.ceiling     # numeric literal 5.5, then method call .ceiling — reads as (5.5).ceiling
.5.ceiling      # numeric literal .5 (== 0.5), then method call .ceiling
0xFF.to_string  # integer 0xFF, then method call .to_string
~~~

**Any receiver expression works.** The disambiguation only matters for bare numeric literals. Parenthesized expressions are unambiguous regardless: `(5).times`, `(5 + 1).abs`, `($count * 2).even?` all parse straightforwardly through the general method-call path.

## Integers and floats are both `number`

`42` and `3.14` are both instances of the same class: `number`. Caspian has no separate `integer` or `float` type at the language level. Arithmetic between any two numbers is just arithmetic — no int-vs-float promotion rules, no conversion methods (`.to_integer`, `.to_float`) to reach for. The internal representation the engine uses to store a number may still distinguish (an integer-shaped value can be stored more efficiently than a fractional one), but that's an implementation detail; from the language's perspective, everything is `number`.

Methods that only make sense for whole-value numbers **raise** when called on a non-integer. `.even?` and `.odd?` raise (a fractional number is neither even nor odd — those categories only apply to integers, and returning `false` for both would conflate "the question doesn't apply" with "the answer is no"). Bitwise operations raise on any number with a fractional part. Callers who don't know whether they're holding an integer should guard with `.integer?` first. See [Testing](#testing) and [Bitwise](#bitwise) below.

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

**Arithmetic never produces `-0`.** Any operation on numbers produces a plain `0` when the result is zero; the negation is only present when the caller wrote the literal `-0` in source. Even `.negate` on a zero-valued expression produces plain `0`:

~~~caspian
$i = 0
$i.negate      # 0 (not -0) — negation is arithmetic
~~~

Note: Caspian has no `-$i` unary-minus operator. To flip a number's sign, either call [`.negate`](#math) on it or multiply by `-1` (`$i *= -1`, or `$j = $i * -1`).

The one place `-0` differs from `0` is **[array indexing](https://puck.uno/documentation/requirements/built-in-classes/primitives/array/#zero-based-indexing-from-both-ends)**: `$arr[-0]` is the last element, while `$arr[0]` is the first. Every other consumer of the value — equality, hash keys, JSON serialization, comparison, `.to_string`, `.to_hex`, `.to_bin` — treats `-0` as `0`.

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

## Predicates

Boolean-returning methods for querying a value (return a [boolean](https://puck.uno/documentation/requirements/built-in-classes/primitives/boolean)):

| Method | Description |
|---|---|
| `.zero?` | True if the value is 0. |
| `.positive?` | True if the value is greater than 0. |
| `.negative?` | True if the value is less than 0. |
| `.integer?` | True if the value has no fractional part. |
| `.even?` | True if the value is divisible by 2. **Raises** on any non-integer — parity applies only to integers. Guard with `.integer?` first if the value could be fractional. |
| `.odd?` | True if the value is not divisible by 2. **Raises** on any non-integer, same rationale as `.even?`. |

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
| `.bitwise` | Returns a chainable [bitwise-wrapper object](https://puck.uno/documentation/requirements/built-in-classes/number/bitwise) around the number. |

Full method surface — `.or`, `.and`, `.xor`, `.not`, `.shift_left` (aliased `<<`), `.shift_right` (aliased `>>`), `.nand`, `.nor`, `.xnor` — is spec'd at [bitwise](https://puck.uno/documentation/requirements/built-in-classes/number/bitwise). Bitwise operations are only meaningful on whole-value numbers; `.bitwise` on any number with a fractional part raises.

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

Numeric iteration helpers — `.times`, `.upto`, `.downto` — live under [loops § Numeric helpers](https://puck.uno/documentation/requirements/syntax/loops#numeric-helpers-times-upto-downto).

## Open questions

- Should `.square_root` (and `.√`) of a negative number raise, return null (possibly with a flavor like `:undefined`), or something else?
- Should `.to_string` accept a format kwarg (number of decimal places, sign handling, etc.), or is that formatting a separate spec?
- Floating-point representation limits affect rounding operations with small multiples. Whether the spec calls out specific IEEE 754 corners (subnormals, infinity handling around midpoints) explicitly, or lets the implementation choose within reasonable bounds, is unresolved.

## Testing

### Literal forms

- **Whole-value decimal** — `0`, `42`, `-5` all materialize as `Number::Decimal` with the expected value.
- **Fractional decimal** — `3.14` materializes as `Number::Decimal(3.14)`.
- **Scientific notation** — `1e10` materializes as `10_000_000_000`; `2.5e-3` materializes as `0.0025`.
- **Hex literal** — `0xFF` materializes as `Number::Hex(255)`.
- **Octal literal** — `0o755` materializes as `Number::Octal(493)`.
- **Binary literal** — `0b1010` materializes as `Number::Binary(10)`.
- **Leading `-` produces negative** — `-5` is `Number::Decimal(-5)`.
- **Underscore digit separators** — `1_000_000` equals `1000000`; `0xFF_FF` equals `0xFFFF`; `3.141_592_653` equals `3.141592653`.
- **Doubled underscores between digits allowed** — `1__000` parses as `1000`.
- **Leading underscore invalid** — `_1000` is not a number literal (parses as an identifier or raises per lex spec).
- **Trailing underscore invalid** — `1000_` raises.
- **Every literal is a fresh instance** — two `5` literals materialize distinct Number objects; comparing them with `==` is `true`.

### Subclasses share method surface

- **Arithmetic works the same on all four subclasses** — `Decimal(5) + 1`, `Hex(5) + 1`, `Binary(5) + 1`, `Octal(5) + 1` all produce the same value.
- **Comparison equality across subclasses** — `0xFF == 255` is `true`; `0b11111111 == 0o377` is `true`.
- **`.to_string` differs by subclass** — `255.to_string` returns `'255'`; `0xFF.to_string` returns `'0xff'`; `0o377.to_string` returns `'0o377'`; `0b11111111.to_string` returns `'0b11111111'`.

### Left-operand-wins arithmetic

- **`Hex + Decimal` returns Hex** — `0xFF + 1` is `Number::Hex(256)` with `.to_string` `'0x100'`.
- **`Decimal + Hex` returns Decimal** — `1 + 0xFF` is `Number::Decimal(256)` with `.to_string` `'256'`.
- **`Binary + Hex` returns Binary** — `0b1010 + 0xFF` is `Number::Binary`.
- **`Octal + Decimal` returns Octal**.

### C99-extended fractional form

- **Decimal fractional stringifies plain** — `3.4028.to_string` returns `'3.4028'`.
- **Binary fractional uses `p`-exponent** — `3.4028.to_bin.to_string` returns `'0b1.1011001110000110000000101p+1'`.
- **Octal fractional uses `p`-exponent** — `3.4028.to_oct.to_string` returns `'0o1.5470736p+1'`.
- **Hex fractional uses `p`-exponent** — `3.4028.to_hex.to_string` returns `'0x1.b38ef34d6a162p+1'`.
- **Whole-value hex omits exponent** — `255.to_hex.to_string` returns `'0xff'`.
- **Whole-value binary omits exponent** — `255.to_bin.to_string` returns `'0b11111111'`.
- **Whole-value octal omits exponent** — `255.to_oct.to_string` returns `'0o377'`.

### Negative zero

- **`-0 == 0` is `true`**.
- **`0 * -1` returns `0`, not `-0`** — arithmetic strips the negation.
- **`-0 * -1` returns `0`**.
- **`0 + -0` returns `0`**.
- **`(-0).negate` returns `0`, not `-0`**.
- **`0.negate` returns `0`, not `-0`**.
- **`-0` as array index gives the last element** — `[1, 2, 3][-0]` is `3`; `[1, 2, 3][0]` is `1`.
- **`-0.to_string` returns `'0'`** — stringification treats it as `0`.
- **`-0` as hash key equals `0` as hash key** — `{}` write of `-0` and read of `0` return the same slot.
- **`-0` compares equal in JSON serialization contexts as `0`**.

### Immutability

- **`$x + 1` does not mutate `$x`** — for `$x = 5`, after `$y = $x + 1`, `$x` is still `5`.
- **`$x += 1` rebinds `$x` to a new number** — original `5` is unchanged; anyone holding a reference to it still sees `5`.
- **No arithmetic operation mutates any operand**.

### Arithmetic

- **`+`** — `2 + 3` is `5`; `-2 + 3` is `1`.
- **`-`** — `5 - 3` is `2`; `2 - 5` is `-3`.
- **`*`** — `3 * 4` is `12`; `0 * 5` is `0`.
- **`/`** — `10 / 2` is `5`; `10 / 3` is a fractional result (per spec, either `3.333...` decimal or exact rational — test the settled rule).
- **`/` by zero** — spec whether it raises, returns infinity, or a null-flavor; test the settled rule.
- **`%`** — `10 % 3` is `1`; `-10 % 3` — test the settled sign convention.
- **`%` by zero raises**.
- **`**`** — `2 ** 10` is `1024`; `2 ** 0` is `1`; `2 ** -1` is `0.5`.
- **`0 ** 0`** — spec whether it returns `1` (common convention) or raises; test the settled rule.

### Comparison

- **`==`** — `5 == 5` is `true`; `5 == 6` is `false`.
- **`!=`** — `5 != 6` is `true`; `5 != 5` is `false`.
- **`<`** — `3 < 5` is `true`; `5 < 3` is `false`; `5 < 5` is `false`.
- **`<=`** — `5 <= 5` is `true`.
- **`>`** — `5 > 3` is `true`.
- **`>=`** — `5 >= 5` is `true`.
- **Comparison across subclasses** — `0xFF < 256` is `true`; `0b1010 == 10` is `true`.
- **Fractional vs whole** — `5.0 == 5` is `true`.

### `.zero?`, `.positive?`, `.negative?`

- **`.zero?`** — `0.zero?` is `true`; `(-0).zero?` is `true`; `5.zero?` is `false`; `(-5).zero?` is `false`.
- **`.positive?`** — `5.positive?` is `true`; `0.positive?` is `false`; `(-5).positive?` is `false`.
- **`.negative?`** — `(-5).negative?` is `true`; `0.negative?` is `false`; `(-0).negative?` is `false`; `5.negative?` is `false`.
- **All three return Boolean** — result class is Boolean.

### `.integer?`, `.even?`, `.odd?`

- **`.integer?`** — `5.integer?` is `true`; `5.0.integer?` is spec-dependent (test the settled rule for float-valued whole numbers); `3.14.integer?` is `false`.
- **`.even?` on integer** — `4.even?` is `true`; `5.even?` is `false`; `0.even?` is `true`.
- **`.odd?` on integer** — `5.odd?` is `true`; `4.odd?` is `false`.
- **`.even?` on non-integer raises** — `3.14.even?` raises.
- **`.odd?` on non-integer raises** — `3.14.odd?` raises.
- **Negative integer parity** — `(-4).even?` is `true`; `(-5).odd?` is `true`.

### `.round`, `.round_up`, `.round_down`

- **`.round` default multiple 1** — `2.4.round` is `2`; `2.5.round` is `3` (half away from zero).
- **`.round(multiple: 10)`** — `5.round(multiple: 10)` is `10`; `4.round(multiple: 10)` is `0`.
- **Midpoint away from zero for positive** — `5.round(multiple: 10)` returns `10`.
- **Midpoint away from zero for negative** — `(-5).round(multiple: 10)` returns `-10`.
- **`.round_up(multiple: 10)`** — `5.round_up(multiple: 10)` is `10`; `1.round_up(multiple: 10)` is `10`; `10.round_up(multiple: 10)` is `10`.
- **`.round_down(multiple: 10)`** — `5.round_down(multiple: 10)` is `0`; `9.round_down(multiple: 10)` is `0`; `10.round_down(multiple: 10)` is `10`.
- **Fractional multiple** — `12.3.round(multiple: 0.2)` is `12.4` (midpoint away from zero).
- **Non-midpoint fractional multiple** — `12.25.round(multiple: 0.2)` is `12.2`.
- **Negative value rounding** — `(-2.5).round` is `-3`; `(-2.5).round_up(multiple: 10)` is `0`; `(-2.5).round_down(multiple: 10)` is `-10`.
- **`multiple: 0` raises**.
- **`multiple:` with a negative value** — spec whether it raises or is normalized to positive; test the settled rule.

### Math

- **`.absolute`** — `(-5).absolute` is `5`; `5.absolute` is `5`; `0.absolute` is `0`.
- **`.absolute_negative`** — `(-5).absolute_negative` is `-5`; `5.absolute_negative` is `-5`; `0.absolute_negative` is `0`.
- **`.negate`** — `5.negate` is `-5`; `(-5).negate` is `5`; `0.negate` is `0`.
- **`.negate` on `-0` returns `0`** — arithmetic strips the negation.
- **`.square_root`** — `9.square_root` is `3`; `2.square_root` is approximately `1.4142...`.
- **`.√` is alias for `.square_root`** — `9.√` is `3`.
- **`.square_root` on negative** — behavior per open question; test the settled rule.
- **`.square_root(0)` is `0`**.

### `.bitwise`

- **`.bitwise` returns the bitwise wrapper** on whole-value numbers.
- **`.bitwise` on a fractional number raises** — `3.14.bitwise` raises.
- **`.bitwise` return type is documented as `Bitwise` wrapper**, not `Number`.

### Conversion

- **`.to_dec` returns Decimal** — `0xFF.to_dec` is `Number::Decimal(255)`.
- **`.to_num` is alias for `.to_dec`**.
- **`.to_hex` returns Hex** — `255.to_hex` is `Number::Hex(255)`.
- **`.to_bin` returns Binary**.
- **`.to_oct` returns Octal**.
- **Conversion preserves value** — `$n == $n.to_hex`, `$n == $n.to_bin`, etc.
- **`.to_string`** — uses the instance's subclass form; `255.to_string` is `'255'`; `0xFF.to_string` is `'0xff'`.
- **`.to_integer`** — `3.7.to_integer` is `3`; `(-3.7).to_integer` is `-3` (truncate toward zero); preserves subclass.
- **`.to_integer` on already-integer** — returns a value equal to the receiver, still in the same subclass.
- **`.commafy`** — `1000000.commafy` is `'1,000,000'`; `1234567.89.commafy` is `'1,234,567.89'`.
- **`.commafy` on small value** — `5.commafy` is `'5'`; `123.commafy` is `'123'`.
- **`.commafy` on negative** — `(-1000).commafy` is `'-1,000'`.
- **`.dotify`** — `1000000.dotify` is `'1.000.000'`; `1234567.89.dotify` is `'1.234.567,89'`.
- **`.dotify` on small value** — `5.dotify` is `'5'`.
- **`.commafy` / `.dotify` return String** — not Number.
