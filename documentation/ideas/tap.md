# `tap` method

~~~json
{"vibecode": {
	"doc": "tap",
	"role": "Ruby-style tap method on Caspian objects for inline side effects in chains; placement settled on .object.tap with the block receiving the underlying value (not the helper) and the helper returning the underlying value so chains survive",
	"key_concepts": ["tap_method", "ruby_style_chaining", "side_effect_in_chain",
		"object_meta_helper_placement", "helper_returns_underlying_value"],
	"status": "brainstorm — placement settled 2026-05-27; not in V1 core"
}}
~~~

Ruby's `tap` pattern: receive a value in a block, run side-effecting
logic on it, return the value unchanged so the chain continues.

In Caspian, `tap` lives on the `.object` meta-helper, not on the value
directly. The block receives the underlying value, and `.object.tap`
returns the underlying value (not the helper) so chains survive:

```caspian
$foo.object.tap do($same_as_foo)
    log($same_as_foo)
end.do_more     # continues on $foo
```

The main method namespace stays clean, and chain ergonomics are
preserved. Cost: one extra `.object.` in the syntax compared to
Ruby's bare `.tap`.

<a id="use-case"></a>
## Use case

Brief use of a value without breaking a chain or assigning to
a throwaway variable:

```caspian
do_something.object.tap do($x)
    log($x)
end.do_more
```

Returns the value `do_something` produced; the `log` call is a
side-effect inserted into the chain.

<a id="placement"></a>
## Placement: `.object.tap`

Two readings were considered:

- **On the value directly** (`$foo.tap`). Matches Ruby exactly but adds
  `tap` to every object's main method namespace, where it competes with
  domain methods on every class.
- **On the `.object` meta-helper** (`$foo.object.tap`). Keeps the main
  method namespace clean — `.object` is where meta-operations live.

The objection raised against `.object.tap` was that "the chain continues
from `.object`, not from `$foo`" — but that's only true if the helper's
methods return the helper. They don't have to. **`.object.tap` returns
the underlying value**, not the helper. Chains survive.

So the placement is `.object.tap`. Main namespace stays clean, chain
ergonomics preserved, cost is one extra `.object.` in the syntax.

<a id="block-receives"></a>
## What the block receives

The block receives the **underlying value** — the same value the chain
will continue on:

```caspian
$foo.object.tap do($same_as_foo)
    log($same_as_foo)
end
```

Not the `.object` helper. The helper exists to host the `tap` method;
inside the block, you want the actual value.

<a id="status"></a>
## Status

Not in V1 core. Placement and block semantics settled 2026-05-27.
Trivial to add when wanted; filed here so the discussion isn't lost.
