# Trilean (idea — not in core)

> **Status**: 2026-05-17 — moved from `documentation/charlie/built-in-classes/`
> to `documentation/ideas/`. Charlie's core primitive for two-valued logic is
> `boolean`, not `trilean`. Three-valued logic is an idea preserved here for
> possible future revisit but is not part of the language. The text below
> describes what trilean *would* be if introduced.

---

`puck.uno/trilean` is the home for **three-valued logic** in Charlie. It provides
the standard operators (`and`, `or`, `not`, `nand`, `nor`, `xor`, `xnor`,
`implies`, `eq`) under a model where any operand can be `null` ("unknown") in
addition to `true` and `false`.

Default Charlie operators (`&&`, `||`, `not`, `==`) keep their strict-Boolean
semantics — null is treated as falsey, just like in most languages. The trilean
class is **opt-in**: code that wants three-valued logic explicitly calls into it.

<a id="status"></a>
## 1 Status

~~~json
{"vibecode": {
	"section": "status",
	"priority": "low",
	"target_release": "first_production",
	"implementation": "pure_charlie_in_stdlib"
}}
~~~

Low priority but slated for the first production release. Will be implemented in
**pure Charlie** as part of the standard library — partly because three-valued
logic is genuinely useful, partly because it makes a good real-world test case for
the language runtime. Implementation will live at `code/charlie/stdlib/trilean.charlie`.

---

<a id="the-model"></a>
## 2 The Model

~~~json
{"vibecode": {
	"section": "the_model",
	"name": "Kleene three-valued logic",
	"alias": "K3 strong Kleene",
	"used_by": "SQL WHERE clause evaluation",
	"key_concepts": ["null_means_unknown", "result_depends_on_operand_dominance"]
}}
~~~

The three values are `true`, `false`, and `null`. `null` represents "could be true,
could be false, we don't know."

Trilean operators classify each operand by reading `.object.bool` on it (see
[object.md](object.md)). The result is one of three categories: `true` for any
truthy value (the boolean `true`, the number `1`, a non-empty string, etc.),
`false` for the boolean `false` value (and other strictly-falsy values like
`0`, empty strings, etc.), or `null` for null values.

```
$tri.or(1, null)         # true   (1 is truthy)
$tri.and(1, null)        # null   (1 is truthy AND null is unknown)
$tri.and(0, null)        # false  (0 is falsy; falsy dominates AND)
```

Operators always **return** one of the strict values `true`, `false`, or `null`,
regardless of operand types.

The general rule for every operator: ask whether the result depends on what the
unknown actually turns out to be. If the result is the same regardless, return that
result. If the result depends on the unknown, return `null`.

Examples:
- `false && unknown` → result is `false` regardless of the unknown → `false`
- `true && unknown` → result depends on the unknown → `null`
- `true || unknown` → result is `true` regardless of the unknown → `true`
- `false || unknown` → result depends on the unknown → `null`
- `not unknown` → result depends on the unknown → `null`

This matches SQL's WHERE-clause evaluation (the same model is sometimes called
strong Kleene logic, K3, or SQL three-valued logic).

---

<a id="operators"></a>
## 3 Operators

~~~json
{"vibecode": {
	"section": "operators",
	"role": "documents the full set of three-valued operators with their truth tables"
}}
~~~

All operators are static methods on the `puck.uno/trilean` class, called as
`%puck['trilean'].<op>(...)`.

<a id="nota"></a>
### 3.1 `not(a)`

| `a` | result |
|---|---|
| `true` | `false` |
| `false` | `true` |
| `null` | `null` |

<a id="anda-b"></a>
### 3.2 `and(a, b)`

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `true` | `false` | `null` |
| `false` | `false` | `false` | `false` |
| `null` | `null` | `false` | `null` |

`false` dominates AND. `null` poisons unless `false` is present.

<a id="ora-b"></a>
### 3.3 `or(a, b)`

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `true` | `true` | `true` |
| `false` | `true` | `false` | `null` |
| `null` | `true` | `null` | `null` |

`true` dominates OR. `null` poisons unless `true` is present.

<a id="nanda-b-notanda-b"></a>
### 3.4 `nand(a, b)` = `not(and(a, b))`

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `false` | `true` | `null` |
| `false` | `true` | `true` | `true` |
| `null` | `null` | `true` | `null` |

<a id="nora-b-notora-b"></a>
### 3.5 `nor(a, b)` = `not(or(a, b))`

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `false` | `false` | `false` |
| `false` | `false` | `true` | `null` |
| `null` | `false` | `null` | `null` |

<a id="xora-b-exclusive-or"></a>
### 3.6 `xor(a, b)` (exclusive or)

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `false` | `true` | `null` |
| `false` | `true` | `false` | `null` |
| `null` | `null` | `null` | `null` |

`null` always poisons XOR — there is no operand value that "dominates" XOR, so the
result always depends on the unknown.

<a id="xnora-b-notxora-b-equivalence-iff"></a>
### 3.7 `xnor(a, b)` = `not(xor(a, b))` (equivalence / iff)

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `true` | `false` | `null` |
| `false` | `false` | `true` | `null` |
| `null` | `null` | `null` | `null` |

True when both operands are the same boolean. Same null-poisoning rule as XOR.

<a id="impliesa-b-material-conditional-if-a-then-b"></a>
### 3.8 `implies(a, b)` (material conditional, "if a then b")

Defined as `or(not(a), b)`.

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `true` | `false` | `null` |
| `false` | `true` | `true` | `true` |
| `null` | `true` | `null` | `null` |

Note that `false implies anything` is always `true` — that's the standard
material-conditional rule (vacuous truth). When the antecedent is null, the
result depends on whether the antecedent turns out to be true or false.

<a id="prohibitsa-b-material-nonimplication-a-but-not-b"></a>
### 3.9 `prohibits(a, b)` (material nonimplication, "a but not b")

Defined as `and(a, not(b))`, equivalently `not(implies(a, b))`. The opposite of
`implies` — true only in the one case where an implication fails: `a` is true
but `b` is false.

| `a \ b` | `true` | `false` | `null` |
|---|---|---|---|
| `true` | `false` | `true` | `null` |
| `false` | `false` | `false` | `false` |
| `null` | `false` | `null` | `null` |

Reads naturally as "a prohibits b" — `a` being true is incompatible with `b`
being true. Useful for rule and constraint logic where you want to assert that
some condition forbids another.

<a id="eqa-b-alias-for-xnor"></a>
### 3.10 `eq(a, b)` (alias for `xnor`)

`eq` is a friendly alias for `xnor`. Both operators produce the same truth table
in trilean — they are the same function under two names. See the `xnor` section
above for the truth table and semantics.

The alias exists because "eq" reads more naturally at call sites where the intent
is "are these the same trilean value." Note this is **not** the place for
arbitrary value equality — use Charlie's regular `==` for that, with its standard
truthy-falsy semantics.

The SQL trap applies: `eq(null, null)` is `null`, not `true`. To check "is this
null?" use `$x.object.null?`, never `eq(x, null)`.

---

<a id="lazy-second-argument"></a>
## 4 Lazy Second Argument

~~~json
{"vibecode": {
	"section": "lazy_second_argument",
	"role": "documents the do-block form of binary trilean operators that defers evaluation of the second argument when the first short-circuits the result",
	"key_concepts": ["short_circuit_per_operator_family",
		"do_block_form_for_lazy_second_argument",
		"three_families_each_with_dominant_value"]
}}
~~~

Every binary trilean operator can short-circuit when its first argument has the
operator's **dominant value** — the value that fully determines the result without
needing to look at the second argument. The operators fall into three families:

| Family | Operators | Dominant value of `a` | Result on short-circuit |
|---|---|---|---|
| AND-family | `and`, `nand`, `prohibits` | `false` | `false`, `true`, `false` |
| OR-family | `or`, `nor`, `implies` | `true` | `true`, `false`, `true` |
| XOR-family | `xor`, `xnor`, `eq` | `null` | `null` (always) |

Only `not` (single argument) doesn't apply.

Both forms are supported. Eager — pass both values:

```
$result = $tri.and($a, $b)
```

Lazy — pass `b` as a `do` block, which is only invoked if `a` doesn't
short-circuit:

```
$result = $tri.and($a) do
    &expensive_check
end
```

If `$a` is `false`, the block is never called — the result is `false` directly.
Otherwise the block is called and its return value used as `b`.

The lazy form pays off when the second argument is expensive, has side effects,
or shouldn't be evaluated at all in the short-circuit case (e.g., a database
query that would fail or be wasteful when the result is already determined).

Worked examples for each family:

```
# AND-family: short-circuits on a == false
$tri.and($cheap_check) do
    &expensive_db_lookup
end

# OR-family: short-circuits on a == true
$tri.or($cached_result) do
    &fall_back_to_remote_query
end

# XOR-family: short-circuits on a == null
$tri.eq($maybe_null_value) do
    &compute_other_value_only_if_first_was_known
end
```

The block-form syntax is consistent with how other Charlie constructs accept
deferred work (`%utils.timeout`, `%forks.run`, etc.). The block runs in the caller's
chain frame, so `%chain` access and exception propagation behave normally.

---

<a id="branching-on-a-trilean-result"></a>
## 5 Branching on a Trilean Result

A trilean operator always returns one of three strict values: `true`, `false`, or
`null`. Branching on the result is straightforward — use direct comparisons or
the universal `.object.null?` / `.object.defined?` helpers (which live on every
value in Charlie, not just trileans):

```
$result = $tri.and($a, $b)

if $result == true
    # definitely true
elsif $result == false
    # definitely false
else
    # null — we don't know
end
```

Or equivalently:

```
if $result.object.null?
    # we don't know
elsif $result
    # definitely true (truthy)
else
    # definitely false
end
```

The second form takes advantage of Charlie's default truthy semantics, where
null is treated as falsy in an `if`. After the `null?` check has handled the
unknown case, ordinary `if $result` is safe.

The `.object.null?`, `.object.defined?`, `.object.truthy?`, and `.object.bool`
methods are universal — they are not specific to trilean. They are general-purpose
introspection available on any value. See [object.md](object.md) for the full
set.

---

<a id="usage"></a>
## 6 Usage

~~~json
{"vibecode": {
	"section": "usage",
	"role": "shows typical Charlie code calling into the trilean class"
}}
~~~

Constructing trilean expressions:

```
%vibecode <<~VIBECODE
{"class":"puck.uno/dogberry/page","method":"process","purpose":"shows trilean
operators in a representative scenario","args":["request","response"]}
VIBECODE

$tri = %puck['trilean']

$has_consent = %db.fetch_consent($user)        # true, false, or null (unknown)
$is_minor    = %db.fetch_is_minor($user)       # true, false, or null
$can_proceed = $tri.and($has_consent, $tri.not($is_minor))

if $can_proceed == true
    &grant_access
elsif $can_proceed == false
    &deny_access
else
    &request_more_information   # null — we don't know, ask the user
end
```

The default `&&`, `||`, `not` operators continue to treat null as falsey, so code
that doesn't care about the distinction (the common case) doesn't have to think
about three-valued logic at all.

---

<a id="why-pure-charlie"></a>
## 7 Why Pure Charlie

~~~json
{"vibecode": {
	"section": "why_pure_charlie",
	"role": "explains the choice to implement trilean in stdlib Charlie rather than the runtime"
}}
~~~

Two reasons:

- **The operations don't need engine-level support.** All trilean methods reduce
  to ordinary boolean operations and null checks — exactly the operations Charlie
  already has. Implementing in Charlie keeps the runtime smaller.
- **It's a useful real-world test of the language.** A short pure-Charlie module
  with a clear specification, plenty of edge cases (the truth tables), and
  well-defined behavior makes a good fixture for runtime testing. If the trilean
  module passes its own truth-table tests, that's evidence the runtime handles
  conditional logic, function definition, and null-comparison correctly.

The implementation lives at [code/charlie/stdlib/trilean.charlie](../../../code/charlie/stdlib/trilean.charlie).

---

<a id="notes"></a>
## 8 Notes

- **Operators stay strict-boolean.** Default Charlie `&&`, `||`, `not`, `==`
  treat null as falsey. Trilean is purely a library, not an operator overload.
- **Operators classify by truthiness, not strict class.** `$tri.and(1, true)`
  returns `true`; `$tri.or(0, "hello")` returns `true`. Any truthy non-null
  value is treated as `true`, any falsy non-null value as `false`, and null
  is null. The return value is always strict `true`, `false`, or `null`.
- **Use direct comparisons or `.object.null?` for branching.** A trilean
  result is one of three strict values, so `$result == true`, `$result == false`,
  and `$result.object.null?` are all unambiguous. Don't reach for trilean
  operators inside an `if` condition without remembering that the outer `if`
  will treat the resulting null as falsy — usually the intent, but worth
  being explicit about.
- **`eq` is null-poisoning.** Never use `eq(x, null)` to check for null; use
  `$x.object.null?`. This is the same trap SQL programmers learn the hard way.
- **No bare-word `tri_and` / `tri_or` aliases.** Keeping the operations
  namespaced under `puck.uno/trilean` avoids polluting the bare-word namespace
  and makes their three-valued semantics explicit at every call site.
