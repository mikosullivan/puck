# String
<!--index: 1-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_built_in_string",
	"role": "spec for Caspian's built-in string class — the class every string literal materializes into. Covers the four literal forms (single-quoted, double-quoted, leading-colon symbol notation, trailing-colon key notation in hashes/params — Caspian has no separate Symbol type), the immutability rule (every mutating-shaped operation returns a new string), the sequence-of-characters model, and the guaranteed method surface (comparison, concatenation, length, slicing, formatting, encoding).",
	"status": "draft — literal forms (all four), immutability rule, and starter method set (upper, lower, length) spec'd; full method surface still growing",
	"audience": "developers writing Caspian; engine implementers building the string runtime; tooling authors"
}}
~~~

A **string** represents a sequence of Unicode characters. Every string literal in Caspian source materializes into an instance of this class.

## Literal forms

Four forms, all producing string instances:

- **Single-quoted:** `'hello'` — literal; never interpolates.
- **Double-quoted:** `"hello, #{$name}"` — always interpolates. Expressions inside `#{...}` are evaluated and their results injected. See [Interpolation](#interpolation) below.
- **Symbol notation (leading colon):** `:hello` — compact form for identifier-shaped strings, valid anywhere an expression is expected.
- **Key notation (trailing colon):** `hello:` — the key form inside hash literals and parameter lists.

The quoted forms support the usual escape sequences: `\n`, `\t`, `\'`, `\"`, `\\`. In double-quoted strings, `\#{` escapes the interpolation opener — writes a literal `#{`.

### Interpolation

Double-quoted strings interpolate; single-quoted strings do not. The interpolation form is `#{expr}`:

~~~caspian
$name = 'Alice'
$greeting = "hello, #{$name}"           # 'hello, Alice'
$math = "total is #{$price + $tax}"     # any expression, not just a variable
$literal = 'hello, #{$name}'            # literal — single-quoted, no interpolation
~~~

**Inside `#{...}` is a full expression.** Any expression that returns a value: a variable, an arithmetic expression, a method call, a nested string literal — anything that produces a value works.

**The result is stringified.** If the expression returns a string, it's inserted as-is. If it returns any other value, the runtime calls the value's stringification (per the [Object § to_string](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/#to-string) hook) and inserts the resulting string. There is no "must be a string" restriction; any value is legal, and the runtime handles the conversion.

**Escaping the opener.** To write a literal `#{` in a double-quoted string, escape the `#`: `"\#{not interpolated}"` produces `#{not interpolated}`. In single-quoted strings no escape is needed — `'#{foo}'` is already literal.

**Escaping the closer.** The interpolation ends at the matching `}` — the parser tracks brace depth inside `#{...}` so nested braces (as in a hash literal) work: `"count: #{{a: 1, b: 2}.length}"` produces `count: 2`. A literal `}` outside interpolation is fine on its own; only the paired form matters.

The symbol and key notations are purely syntactic sugar for identifier-shaped string literals. **Caspian does not have Ruby-style symbols.** `:hello` and `'hello'` produce indistinguishable strings — `:hello == 'hello'` is `true`, both are `String` instances, neither carries any special interning or identity semantics. Ruby users should note that this notation is a shorthand only, not a separate type or optimization.

Since Caspian doesn't intern primitives (every literal materializes a fresh instance — see [primitive-buckets](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitive-buckets)), `:hello` written twice in source produces two distinct String instances that compare `==` (same value) but are separate objects. This is exactly the same as writing `'hello'` twice.

### Allowed character set

Both notation forms accept the same character shape: **an identifier — a letter or underscore, followed by letters, digits, or underscores — optionally ending with `?` or `!`.** Anything outside that shape (spaces, hyphens, dots, punctuation, leading digits, interpolation) requires a quoted form.

~~~caspian
:hello                     # string 'hello'
:hello_world               # string 'hello_world'
:hello?                    # string 'hello?'
:empty!                    # string 'empty!'

'hello world'              # only quoted forms allow spaces
'hello-world'              # hyphens too
"hello, #{$name}"          # and interpolation
~~~

### Inside hash literals and parameter lists

All four forms produce identical results:

~~~caspian
$config = {display: true, color: :red}
# equivalent to:
$config = {'display': true, 'color': 'red'}

func(name: 'Alice', kind: :admin)
# equivalent to:
func('name': 'Alice', 'kind': 'admin')
~~~

The trailing-colon form (`display:`) applies specifically to key positions in hash literals and parameter lists; the leading-colon form (`:red`) works in any expression position (value positions in a hash, arguments to a function, right-hand side of an assignment).

### The `:true` / `:false` / `:null` collision

The symbol notation and the unadorned keywords produce different values, not the same one. `:true`, `:false`, and `:null` are the **strings** `'true'`, `'false'`, `'null'`; the unadorned `true`, `false`, `null` are the corresponding `True`, `False`, `Null` instances. Both spellings are legal — the language never guesses at intent — but they produce distinct values, and the choice matters.

~~~caspian
{foo: true}                # foo value is an instance of True (the boolean)
{foo: :true}               # foo value is the string 'true'
{foo: 'true'}              # same as :true — the string
~~~

Callers reading `:true` in someone else's code should read it as the literal string `'true'`. If the code needs the boolean, it has to be spelled `true`.

## Immutability

**Strings are immutable.** Once a string instance exists, its character sequence never changes. Every method that has a "modify the string" shape — case folding, trimming, replacement, concatenation, slicing — returns a **new** string instance rather than mutating the original.

~~~caspian
$name = 'alice'
$name.upper                # returns 'ALICE'; $name is still 'alice'

$greeting = $name + '!'    # returns a new string 'alice!'; $name is unchanged
~~~

This is a load-bearing property: passing a string across a role boundary is safe by default because the recipient can't alter it. Provenance stays intact (the role tag on the string is set at creation and never changes; see [roles § Objects also have roles](https://puck.uno/documentation/requirements/caspian/roles/#objects-also-have-roles)).

## Method surface

The guaranteed methods so far:

| Method | Purpose |
|---|---|
| `.upper` | Returns a new string with all characters upper-cased. |
| `.lower` | Returns a new string with all characters lower-cased. |
| `.length` | Returns the number of characters as a [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/primitives/number/). |
| `.content_type` | Getter for the string's optional MIME-type annotation. Reads `%bucket['content_type']`; returns `null` if the bucket entry is absent. Set by [heredocs](heredocs#type-annotation) when the opener includes `(type)`, or explicitly via `.content_type=`. See [heredocs § Type annotation](heredocs#type-annotation). |
| `.content_type=` | Setter for the string's MIME-type annotation. `$str.content_type = 'text/html'` writes to `%bucket['content_type']`. No validation — any string value is accepted. |

More to come — comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`), `+` concatenation, slicing, trimming, replacement, formatting, encoding conversion, containment tests.

## Number conversion

Parse a string into a number. Each method parses the string's content (prefix-aware: `"0x..."`, `"0o..."`, `"0b..."` are recognized as their respective bases; no prefix is treated as decimal) and returns the result as the corresponding [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/) subclass:

| Method | Returns | Description |
|---|---|---|
| `.to_dec` | number | Parses the string and returns `Number::Decimal`. |
| `.to_num` | number | Alias for `.to_dec`. |
| `.to_bin` | number | Parses and returns `Number::Binary`. |
| `.to_oct` | number | Parses and returns `Number::Octal`. |
| `.to_hex` | number | Parses and returns `Number::Hex`. |

Prefix and method are independent — the prefix (if any) says how to interpret the string's digits; the method says which subclass to return.

~~~caspian
"255".to_num          # Number::Decimal(255)
"0xff".to_num         # Number::Decimal(255) — prefix parsed, result is Decimal
"255".to_hex          # Number::Hex(255)   — no prefix, parsed as decimal 255, returned as Hex
"0xff".to_hex         # Number::Hex(255)
"0b11111111".to_hex   # Number::Hex(255)
"0xff".to_bin         # Number::Binary(255)
~~~

Round-trip is exact:

~~~caspian
$n = 3.4028
$s = $n.to_hex.to_string     # "0x1.b38ef34d6a162p+1"
$m = $s.to_hex                # Number::Hex(3.4028)
$n == $m                      # true
~~~

**Unparseable strings raise.** If the string isn't a valid number in the recognized format (or the specified method's format when the prefix is absent), the parse raises. Examples that raise: `"abc".to_num`, `"0xzz".to_hex`, `"3.4".to_bin` (fractional binary literals must use the C99-extended `p`-exponent form; `"3.4"` isn't valid binary).

## Testing

### Literal forms

- **Single-quoted literal** — `'hello'` produces a String equal by value to `'hello'`.
- **Empty single-quoted string** — `''` is a String with `.length` 0.
- **Single-quoted string with escapes** — `'a\nb'` produces exactly `a\nb`... spec check: single quotes still process `\'` and `\\` but not `\n` — verify per lexer rule (`\n`, `\t`, `\'`, `\"`, `\\` are the documented escapes; test that these five work in single-quoted form or not per final lex spec).
- **Single-quoted does not interpolate** — `'#{$x}'` produces the literal 7-character `#{$x}`.
- **Double-quoted literal without interpolation** — `"hello"` equals `'hello'`.
- **Double-quoted interpolation with variable** — for `$name = 'Alice'`, `"hello, #{$name}"` produces `'hello, Alice'`.
- **Double-quoted interpolation with arithmetic expression** — for `$p = 3; $t = 4`, `"total is #{$p + $t}"` produces `'total is 7'`.
- **Double-quoted interpolation with method call** — `"#{[1,2,3].length}"` produces `'3'`.
- **Double-quoted interpolation stringifies non-string values** — `"#{42}"` produces `'42'`; `"#{true}"` produces `'true'`; `"#{null}"` produces the value's `to_string` output.
- **Double-quoted `\#{` escapes the interpolation opener** — `"\#{not interpolated}"` produces `#{not interpolated}`.
- **Double-quoted nested braces work** — `"count: #{{a: 1, b: 2}.length}"` produces `'count: 2'`.
- **Double-quoted escape sequences** — `"\n"`, `"\t"`, `"\\"`, `"\'"`, `"\""` produce the corresponding control/literal characters.
- **Symbol notation** — `:hello` equals `'hello'` and is a String.
- **Symbol notation with underscore** — `:hello_world` equals `'hello_world'`.
- **Symbol notation with trailing `?`** — `:hello?` equals `'hello?'`.
- **Symbol notation with trailing `!`** — `:empty!` equals `'empty!'`.
- **Symbol notation with space raises** — `:hello world` is a parse error.
- **Symbol notation with hyphen raises** — `:hello-world` is a parse error.
- **Symbol notation with leading digit raises** — `:1hello` is a parse error.
- **Key notation inside hash literal** — `{display: true}` is `{'display': true}`.
- **`:true` is the string `'true'`, not the boolean** — `{foo: :true}[:foo] == 'true'` is `true`; `{foo: :true}[:foo] == true` is `false`.
- **`:false` is the string `'false'`, not the boolean**.
- **`:null` is the string `'null'`, not null**.

### Fresh instance per literal (no interning)

- **Two `:hello` literals materialize distinct instances** that compare `==` but are not identity-equal.
- **Two `'hello'` literals materialize distinct instances**.
- **A downloaded method's bucket write on one `'hello'` does not affect another `'hello'` in source**.

### Immutability

- **`.upper` returns a new instance; receiver unchanged** — for `$s = 'alice'`, `$s.upper` returns `'ALICE'`; `$s` is still `'alice'`.
- **`.lower` returns a new instance; receiver unchanged**.
- **`+` concatenation returns a new instance** — `'a' + 'b'` returns `'ab'`; neither operand is mutated.
- **No method mutates the receiver's character sequence**.

### `.upper` / `.lower`

- **`.upper` upper-cases all letters** — `'Alice'.upper` returns `'ALICE'`.
- **`.upper` on empty returns `''`**.
- **`.upper` on all-upper returns a distinct-instance copy** — value equal.
- **`.upper` on non-letter characters is a no-op for those chars** — `'a1!'.upper` returns `'A1!'`.
- **`.upper` handles Unicode letters** — `'café'.upper` returns `'CAFÉ'` (locale-independent Unicode case folding).
- **`.lower` lower-cases all letters** — `'ALICE'.lower` returns `'alice'`.
- **`.lower` on empty returns `''`**.
- **`.lower` handles Unicode letters** — `'CAFÉ'.lower` returns `'café'`.

### `.length`

- **`.length` on `''` is `0`**.
- **`.length` counts characters, not bytes** — `'café'.length` is `4`, not `5`.
- **`.length` returns a `Number`**.
- **`.length` for combining characters** — spec whether combining marks count as separate characters or are collapsed; test accordingly.

### `.content_type` / `.content_type=`

- **`.content_type` on a plain string returns null** — no bucket entry, no default.
- **`.content_type=` writes the bucket entry** — after `$s.content_type = 'text/html'`, `$s.content_type` returns `'text/html'`.
- **`.content_type=` accepts any string** — no validation.
- **`.content_type=` accepts null** — sets the field to null, which is indistinguishable from unset for the getter.
- **`.content_type` is per-instance** — setting on one string does not affect another with the same value.
- **`.content_type=` returns null**.

### Number conversion

- **`.to_num` on decimal string** — `'255'.to_num` returns `Number::Decimal(255)`.
- **`.to_dec` is `.to_num`** — same behavior.
- **`.to_num` recognizes `0x` prefix** — `'0xff'.to_num` returns `Number::Decimal(255)`.
- **`.to_num` recognizes `0o` prefix** — `'0o377'.to_num` returns `Number::Decimal(255)`.
- **`.to_num` recognizes `0b` prefix** — `'0b11111111'.to_num` returns `Number::Decimal(255)`.
- **`.to_hex` on prefixless decimal** — `'255'.to_hex` returns `Number::Hex(255)`.
- **`.to_hex` on `0x`-prefixed string** — `'0xff'.to_hex` returns `Number::Hex(255)`.
- **`.to_hex` on `0b`-prefixed string** — `'0b11111111'.to_hex` returns `Number::Hex(255)`.
- **`.to_bin` on `0xff`** returns `Number::Binary(255)`.
- **`.to_oct` on decimal** returns `Number::Octal` with the same value.
- **Prefix is independent of method** — subclass reflects the method; value reflects the parsed input.
- **Round-trip through `.to_hex.to_string.to_hex` preserves value** — `$n == $n.to_hex.to_string.to_hex`.
- **`.to_num` on unparseable raises** — `'abc'.to_num` raises.
- **`.to_hex` on unparseable raises** — `'0xzz'.to_hex` raises.
- **Fractional binary without `p`-exponent raises** — `'3.4'.to_bin` raises.
- **Fractional decimal parses** — `'3.14'.to_num` returns `Number::Decimal(3.14)`.
- **Negative parses** — `'-5'.to_num` returns `Number::Decimal(-5)`.
- **Empty string raises** on any `.to_*`.
- **Whitespace-only string raises**.
- **Underscore digit separators in string parse** — `'1_000'.to_num` returns `1000` (if spec says the parse accepts them the same way source literals do; check parse spec).

## Related

- [heredocs](heredocs) — the multi-line string form; produces plain strings via `<<TERMINATOR ... TERMINATOR`.
- [regular-expressions](regular-expressions) — the pattern-matching surface strings expose via `.match`, `.matches`, etc.
- [Roles § Objects also have roles](https://puck.uno/documentation/requirements/caspian/roles/#objects-also-have-roles) — every string instance carries an owning role, set at creation.
