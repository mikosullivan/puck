# Number Methods

## Overview (Emperor Georgiou)

```
vibecode: {
	"section": "overview",
	"type": "number",
	"unified": true,
	"notes": ["single_class_for_integers_and_floats",
		"integer_only_methods_raise_if_called_on_float"]
}
```

KScript uses a single Number class for all numeric values, integer and floating-point
alike. Methods that only make sense for integers (such as `even?` and `odd?`) are defined
on Number but raise an error if called on a non-integer value.

### Numeric literals

Underscores in numeric literals are ignored by the lexer. Use them freely as digit
separators for readability:

```
1_000_000       # same as 1000000
3.141_592_653   # same as 3.141592653
0xFF_FF         # same as 0xFFFF
```

Leading and trailing underscores are invalid. Double underscores are allowed.

---

## Arithmetic (Su'Kal)

```
vibecode: {
	"section": "arithmetic",
	"operators": ["+", "-", "*", "/", "%", "**"],
	"returns": "Number"
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `+` | Number | Addition |
| `-` | Number | Subtraction |
| `*` | Number | Multiplication |
| `/` | Number | Division |
| `%` | Number | Modulo |
| `**` | Number | Exponentiation. `2 ** 10` → 1024 |

---

## Comparison (Aurellio)

```
vibecode: {
	"section": "comparison",
	"operators": ["==", "!=", "<", "<=", ">", ">="],
	"returns": "Boolean"
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `==` | Boolean | True if both values are equal |
| `!=` | Boolean | True if values differ |
| `<` | Boolean | Less than |
| `<=` | Boolean | Less than or equal |
| `>` | Boolean | Greater than |
| `>=` | Boolean | Greater than or equal |

---

## Testing (Hugh Mirror)

```
vibecode: {
	"section": "testing",
	"methods": ["zero?", "positive?", "negative?", "integer?", "even?", "odd?",
		"finite?", "infinite?", "nan?"],
	"returns": "Boolean",
	"notes": ["even_and_odd_raise_if_not_integer", "finite_infinite_nan_for_float_safety"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `zero?` | Boolean | True if the value is 0 |
| `positive?` | Boolean | True if the value is greater than 0 |
| `negative?` | Boolean | True if the value is less than 0 |
| `integer?` | Boolean | True if the value has no fractional part |
| `even?` | Boolean | True if the value is divisible by 2. Raises an error if not an integer. |
| `odd?` | Boolean | True if the value is not divisible by 2. Raises an error if not an integer. |
| `finite?` | Boolean | True if the value is a finite number (not infinity, not NaN) |
| `infinite?` | Boolean | True if the value is positive or negative infinity |
| `nan?` | Boolean | True if the value is Not a Number (NaN) |

---

## Rounding (Ash Tyler)

```
vibecode: {
	"section": "rounding",
	"methods": ["round", "round_up", "round_down"],
	"param": "multiple",
	"param_default": 1,
	"midpoint_rule": "half_away_from_zero",
	"notes": ["multiple_must_be_nonzero", "passing_0_raises_error"]
}
```

All rounding methods operate on **multiples**. The `multiple` parameter specifies the
step to round to. If omitted, it defaults to `1`.

| Method | Returns | Description |
|--------|---------|-------------|
| `round(multiple: 1)` | Number | Nearest multiple. Midpoint rounds away from zero. |
| `round_up(multiple: 1)` | Number | Smallest multiple ≥ the value (ceiling relative to the multiple). |
| `round_down(multiple: 1)` | Number | Largest multiple ≤ the value (floor relative to the multiple). |

`multiple` must be a non-zero number. Passing `0` raises an error.

### Midpoint rule

When a value falls exactly halfway between two multiples, KScript rounds half away from
zero:

```
5.round(multiple:10)   -> 10
-5.round(multiple:10)  -> -10
```

### Examples

```
$foo = 2.5

$foo.round                    -> 3
$foo.round(multiple: 10)      -> 0
$foo.round_up(multiple: 10)   -> 10
$foo.round_down(multiple: 10) -> 0
```

```
$foo = 12.25

$foo.round(multiple: 0.2)     -> 12.2 or 12.4 (midpoint rule applies)
$foo.round_up(multiple: 0.2)  -> 12.4
$foo.round_down(multiple: 0.2) -> 12.2
```

```
$foo = -2.5

$foo.round                    -> -3
$foo.round(multiple: 10)      -> 0
$foo.round_up(multiple: 10)   -> 0
$foo.round_down(multiple: 10) -> -10
```

---

## Bitwise (Voq Tyler)

```
vibecode: {
	"section": "bitwise",
	"method": "bitwise",
	"returns": "Bitwise object",
	"notes": ["see_bitwise_md_for_full_api"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `bitwise` | Bitwise object | Returns a bitwise object wrapping this number. See [bitwise.md](bitwise.md). |

---

## Math (Tyler)

```
vibecode: {
	"section": "math",
	"methods": ["abs", "square_root", "√"],
	"returns": "Number",
	"notes": ["sqrt_symbol_is_alias_for_square_root"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `abs` | Number | Absolute value |
| `square_root` | Number | Square root |
| `√` | Number | Alias for `square_root`. `$foo.√` |

---

## Conversion (Madame X)

```
vibecode: {
	"section": "conversion",
	"methods": ["to_string", "to_integer"],
	"notes": ["to_integer_truncates_toward_zero"]
}
```

| Method | Returns | Description |
|--------|---------|-------------|
| `to_string` | String | Convert to string representation |
| `to_string(base: $n)` | String | Convert to string in the given base. `255.to_string(base: 16)` → `'ff'`. `255.to_string(base: 8)` → `'377'`. |
| `to_integer` | Number | Truncate toward zero to a whole number |
| `to_hex` | String | Convert to lowercase hexadecimal string. `255.to_hex` → `'ff'`. |
| `to_oct` | String | Convert to octal string. `255.to_oct` → `'377'`. |
| `commafy` | String | Format with comma thousands separators and period decimal point. `1_000_000.commafy` → `'1,000,000'`. `1_234_567.89.commafy` → `'1,234,567.89'`. |
| `dotify` | String | Format with period thousands separators and comma decimal point. `1_000_000.dotify` → `'1.000.000'`. `1_234_567.89.dotify` → `'1.234.567,89'`. |

---

## Iteration (Leland)

Numeric iteration helpers (`.times`, `.upto`, `.downto`) live in
[loops.md § Numeric iteration helpers](../loops.md#numeric-iteration-helpers).

---

## Open Questions (Section 31 Leland)

- Should `sqrt` of a negative number raise an error or return a special value?
- Should `to_string` accept a format argument (e.g. number of decimal places)?
- Floating-point precision: implementations should account for floating-point
  representation limits, particularly in rounding operations with small multiples.
