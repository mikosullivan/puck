# `tap` method

~~~json
{"vibecode": {
	"doc": "tap",
	"role": "speculative note exploring a Ruby-style tap method on Caspian objects for inline side effects in chains; open question is whether it lives on every object or on the .object meta-helper",
	"key_concepts": ["tap_method", "ruby_style_chaining", "side_effect_in_chain",
		"object_meta_helper_placement"],
	"status": "brainstorm"
}}
~~~

Speculative. Filed for future consideration. Ruby's `tap`
pattern — receive the value in a block, run side-effecting
logic on it, return the value unchanged.

<a id="use-case"></a>
## Use case

Brief use of a value without breaking a chain or assigning to
a throwaway variable:

```
do_something.tap do($x)
    log($x)
end.do_more
```

Returns the value `do_something` produced; the `log` call is a
side-effect inserted into the chain.

<a id="open-where-does-it-live"></a>
## Open: where does it live?

Two reasonable readings:

- **On the value directly** (`$foo.tap`). Receiver in, receiver
  out, matches Ruby semantics. Chains naturally:
  ```
  do_something.tap do($x); log($x); end.do_more
  ```

- **On `.object` (the meta-helper)** (`$foo.object.tap`).
  Discipline choice — keeps the regular method namespace clean.
  But chaining loses the original value (the chain continues
  from `.object`, not from `$foo`), which weakens the main
  reason for tap.

Recommendation (not committed): put `tap` directly on every
object (since every Caspian object inherits a root that can
carry it). Receiver in, receiver out. Matches Ruby exactly and
preserves chain ergonomics.

<a id="open-what-does-the-block-receive"></a>
## Open: what does the block receive?

- The receiver itself — natural and useful.

(If `tap` lives on `.object` instead, the block could receive
either the original value or the object helper — another reason
the on-the-value placement is simpler.)

<a id="status"></a>
## Status

Not in v1 core. Trivial to add when wanted. Filed here so the
discussion isn't lost.
