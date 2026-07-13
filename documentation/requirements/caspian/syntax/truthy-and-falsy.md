# Truthy and falsy
<!--index: 6-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_truthy_and_falsy",
	"role": "spec for Caspian's truthy/falsy rule — only `null` and `false` are falsy; everything else including 0, '', [], {} is truthy",
	"model": "ruby (only null and false are falsy)",
	"audience": "developers writing Caspian conditionals; anyone porting logic from other languages"
}}
~~~

Two values are falsy: **`null`** and **`false`**. Everything else is truthy — including `0`, `''`, `[]`, and `{}`. This matches the Ruby model.

~~~caspian
if ''
	# runs — empty string is truthy
end

if null
	# does not run
end

if 0
	# runs — zero is truthy
end
~~~

## Testing

- **`null` is falsy in `if`** — `if null; 'a'; else; 'b'; end` returns `'b'`.
- **`false` is falsy in `if`** — `if false; 'a'; else; 'b'; end` returns `'b'`.
- **`true` is truthy in `if`** — `if true; 'a'; else; 'b'; end` returns `'a'`.
- **`0` is truthy in `if`** — `if 0; 'a'; else; 'b'; end` returns `'a'`.
- **Negative zero is truthy** — `if -0; 'a'; else; 'b'; end` returns `'a'`.
- **Positive number is truthy** — `if 1; 'a'; else; 'b'; end` returns `'a'`.
- **Empty string `''` is truthy** — `if ''; 'a'; else; 'b'; end` returns `'a'`.
- **Non-empty string is truthy** — `if 'hi'; 'a'; else; 'b'; end` returns `'a'`.
- **Empty array `[]` is truthy** — `if []; 'a'; else; 'b'; end` returns `'a'`.
- **Non-empty array is truthy** — `if [1]; 'a'; else; 'b'; end` returns `'a'`.
- **Empty hash `{}` is truthy** — `if {}; 'a'; else; 'b'; end` returns `'a'`.
- **Non-empty hash is truthy** — `if {a: 1}; 'a'; else; 'b'; end` returns `'a'`.
- **`unless null` runs** — `unless null; 'a'; end` returns `'a'`.
- **`unless false` runs** — `unless false; 'a'; end` returns `'a'`.
- **`unless 0` does not run** — `unless 0; 'a'; end` returns `null`.
- **`while` with `null` condition never runs body** — `while null; $ran = true; end` leaves `$ran` undeclared.
- **`while` with `false` condition never runs body** — same.
- **`while` with `0` condition runs body** — `0` is truthy; body runs (test with an escape or bounded counter).
- **Ternary treats `null` as falsy** — `null ? 'a' : 'b'` returns `'b'`.
- **Ternary treats `false` as falsy** — `false ? 'a' : 'b'` returns `'b'`.
- **Ternary treats `0` as truthy** — `0 ? 'a' : 'b'` returns `'a'`.
- **Ternary treats `''` as truthy** — `'' ? 'a' : 'b'` returns `'a'`.
- **`and` short-circuits on `null`** — `null and $side_effect` does not evaluate `$side_effect`; result is `null`.
- **`and` short-circuits on `false`** — `false and $side_effect` does not evaluate `$side_effect`; result is `false`.
- **`and` continues on `0`** — `0 and 'x'` evaluates the right and returns `'x'`.
- **`or` short-circuits on truthy** — `'left' or $side_effect` returns `'left'` without evaluating `$side_effect`.
- **`or` continues on `null`** — `null or 'right'` returns `'right'`.
- **`or` continues on `false`** — `false or 'right'` returns `'right'`.
- **`or` returns `0` when left is falsy** — `null or 0` returns `0`.
- **`!null` is `true`** — the `not` operator (or `!`) applied to `null` returns `true`.
- **`!false` is `true`** — applied to `false` returns `true`.
- **`!0` is `false`** — applied to `0` returns `false`.
- **`!""` is `false`** — applied to empty string returns `false`.
- **`![]` is `false`** — applied to empty array returns `false`.
- **`!{}` is `false`** — applied to empty hash returns `false`.
