# Attached blocks and the `ensure` clause

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax_clause_slots",
	"role": "spec for the two block-attachment shapes in Caspian. Attached blocks — `do`, `dofunc`, and any sigil'd `~name` — hang off the immediately preceding call and fill a slot on that call: anonymous-positional for `do` / `dofunc`, name-keyed for `~name`. `ensure` is the one remaining in-body clause, exclusive to bare `begin ... end`.",
	"status": "spec — the mechanism is settled: `~name` sigil-prefix block-openers fill same-named slots on the immediately preceding call, at most one per name per call; `do` / `dofunc` are unchanged; `ensure` remains an in-body clause on `begin ... end` only; the parser makes no allowlist of `~name` identifiers — any bareword after `~` is accepted, and DSL methods decide at runtime which names they recognize",
	"audience": "developers writing loop hooks and DSL block-openers; DSL authors defining which `~name` blocks their construct accepts; transpiler / engine implementers realizing the attached-block and `ensure`-clause shapes; anyone reasoning about scope semantics across attached blocks"
}}
~~~

Caspian has two disjoint block-attachment mechanisms:

| Mechanism | Shape | Constructs |
|---|---|---|
| Attached blocks | Follow a call, each opens its own body and closes with its own `end` | `do`, `dofunc`, `~name` for any bareword `name` |
| The `ensure` clause | In-body clause | bare `begin ... end` only |

## Attached blocks

Any call can be followed by one or more attached blocks. Each attached block hangs off the immediately preceding call — the transpiler folds it into the call's `blocks` slot at parse time.

Three attachment forms:

| Form | Slot | Notes |
|---|---|---|
| `do (params) ... end` | positional | anonymous closure; captures the enclosing scope; multiple `do`s allowed per call |
| `dofunc (params) ... end` | positional | anonymous function; sealed scope; multiple `dofunc`s allowed per call |
| `~name (params) ... end` | name-keyed | anonymous closure; captures the enclosing scope; **at most one per `name` per call** |

`~name` is the sigil-prefix block form. The identifier after `~` becomes the slot name on the call. Any bareword may appear after `~`; the parser makes no allowlist. The four names the built-in loop constructs recognize (`~before`, `~between`, `~after`, `~noloop`) are just the ones the loop dispatchers look for. Any DSL method is free to accept its own set of `~name` slots.

### The four built-in loop-hook names

The built-in loop constructs (`while`, `until`, `.each`, `.times`, `.upto`, `.downto`, `begin ... while`, `begin ... until`) recognize four `~name` blocks and invoke them at the corresponding points in the iteration:

| Block | Runs when |
|---|---|
| `~before` | Once, before the first body invocation. |
| `~between` | Between each pair of body invocations — N−1 times when body runs N times. Skipped when body runs 0 or 1 times. |
| `~after` | Once, after the last body invocation, on the normal-completion path only. |
| `~noloop` | When body never ran (loop condition already false at entry, empty iterated collection, etc.). |

Example — `.each` with all four hooks:

~~~caspian
$total = 0
$items = [1, 2, 3, 4]

$items.each do($item)
	$total = $total + $item
end

~before
	puts '--- summing ---'
end

~between
	puts '---'
end

~after
	puts "total: #{$total}"
end

~noloop
	puts '(nothing to sum)'
end
~~~

The five constructs above are one bwc call: `.each` with its `do` body and four `~name` attachments. Each block ends with its own `end`.

### Attachment rule

An attached block attaches to the immediately preceding call in the current scope, skipping intervening comment lines. If the preceding element is not a call — a bare literal, an assignment target, nothing at all — the parser raises.

### At most one per `~name`

The parser rejects two `~name` blocks with the same name attached to the same call:

~~~caspian
$items.each do($x)
	puts $x
end

~before
	puts 'one'
end

~before                             # RAISES: `~before` already attached to `.each` above
	puts 'two'
end
~~~

Positional `do` / `dofunc` are unaffected — they may repeat on the same call.

### DSL methods and unknown `~name`s

A DSL method receives its attached blocks as data on the call. It decides at runtime which `~name` slots it accepts; unknown names raise from the receiving method, not from the parser. The parser's job is only to bind each attached block to the preceding call and enforce the at-most-one-per-name rule; it never validates which names a given call should accept.

## The `ensure` clause on `begin ... end`

`begin ... end` accepts one in-body clause: `ensure`. It runs on every exit path — normal completion, exception, controller `.return`, `break` — parallel to Ruby's `ensure` / Python's `finally`.

~~~caspian
begin
	$fh = %fs.open('data.csv')
	do_something $fh
ensure
	$fh.close
end
~~~

`begin ... end` runs its body exactly once, so the iteration-lifecycle blocks (`~before` / `~between` / `~after` / `~noloop`) would be dead weight. `ensure` is the only in-body clause it accepts.

`ensure` in any other position — inside a `function` body, following a call as an attached block, on a `while` loop — raises at parse time. The word is reserved for this one construct.

## Scope

Each attached block runs in its own fresh frame per invocation, and each captures the scope in which the attachment was written. Sibling attached blocks share that same enclosing scope, so they can pass state through captured variables:

~~~caspian
$sum = 0

$items.each do($item)
	$sum = $sum + $item
end

~after
	puts "sum: #{$sum}"
end
~~~

`~after` reads the `$sum` written by the `do` body — both captured the same enclosing scope. Iteration-local variables declared inside the body (like `$item`) are not visible from `~after`, since they live in the body-invocation frame that ended before `~after` fired.

`dofunc` follows the sealed-scope rule instead of capturing; that's the entire distinction between `do` and `dofunc`.

## CaspJ shape

The transpiler emits attached blocks in the existing `{blocks: [...]}` envelope on the call. Each entry is a `{<KIND>: {...}}` object; the outer key names the slot:

- `do` → `{closure: {params, body}}`
- `dofunc` → `{function: {params, body}}`
- `~name` → `{<name>: {params, body}}` — atom key is the sigil-stripped identifier

Example — the `.each` above (body payloads elided):

~~~json
{
	"call": ".each",
	"receiver": {"var": "items"},
	"blocks": [
		{"closure": {"params": ["item"], "body": [ /* $total = $total + $item */ ]}},
		{"before":  {"params": [], "body": [ /* ... */ ]}},
		{"between": {"params": [], "body": [ /* ... */ ]}},
		{"after":   {"params": [], "body": [ /* ... */ ]}},
		{"noloop":  {"params": [], "body": [ /* ... */ ]}}
	]
}
~~~

Ordering in `blocks` follows source order. The at-most-one-per-name rule is a parse-time check; CaspJ never carries duplicates.

`begin ... end` with an `ensure` clause carries the ensure as an in-body `ensure` field on the `begin_end` atom, not in `blocks`:

~~~json
{
	"begin_end": {
		"body":   [ /* main clause */ ],
		"ensure": [ /* ensure clause */ ]
	}
}
~~~

`ensure` is not an attached block — it lives in the same atom as its body.

## Related

- [bare-blocks](https://www.puck.uno/requirements/syntax/bare-blocks) — the `begin ... end` construct.
- [loops](https://www.puck.uno/requirements/syntax/loops) — where the four built-in loop-hook names are dispatched from.
