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

- **Single-quoted:** `'hello'` — no interpolation.
- **Double-quoted:** `"hello, $name"` — supports interpolation (spec'd under [syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals)).
- **Symbol notation (leading colon):** `:hello` — compact form for identifier-shaped strings, valid anywhere an expression is expected.
- **Key notation (trailing colon):** `hello:` — the key form inside hash literals and parameter lists.

The quoted forms support the usual escape sequences: `\n`, `\t`, `\'`, `\"`, `\\`.

### There is no `Symbol` class

The symbol and key notations are purely syntactic sugar for identifier-shaped string literals. **Caspian does not have Ruby-style symbols.** `:hello` and `'hello'` produce indistinguishable strings — `:hello == 'hello'` is `true`, both are `String` instances, neither carries any special interning or identity semantics. Ruby users should note that this notation is a shorthand only, not a separate type or optimization.

Since Caspian doesn't intern primitives (every literal materializes a fresh instance — see [primitive-buckets](https://puck.uno/documentation/ideas/primitive-buckets)), `:hello` written twice in source produces two distinct String instances that compare `==` (same value) but are separate objects. This is exactly the same as writing `'hello'` twice.

### Allowed character set

Both notation forms accept the same character shape: **an identifier — a letter or underscore, followed by letters, digits, or underscores — optionally ending with `?` or `!`.** Anything outside that shape (spaces, hyphens, dots, punctuation, leading digits, interpolation) requires a quoted form.

~~~caspian
:hello                     # string 'hello'
:hello_world               # string 'hello_world'
:hello?                    # string 'hello?'
:empty!                    # string 'empty!'

'hello world'              # only quoted forms allow spaces
'hello-world'              # hyphens too
"hello, $name"             # and interpolation
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
| `.length` | Returns the number of characters as a [number](https://puck.uno/documentation/requirements/caspian/built-in-classes/number/). |

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

## Related

- [Syntax § Literals](https://puck.uno/documentation/requirements/caspian/syntax/literals) — the source-level literal forms.
- [Roles § Objects also have roles](https://puck.uno/documentation/requirements/caspian/roles/#objects-also-have-roles) — every string instance carries an owning role, set at creation.
