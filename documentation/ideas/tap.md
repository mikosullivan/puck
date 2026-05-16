# `tap` method

Speculative. Filed for future consideration. Ruby's `tap`
pattern — receive the value in a block, run side-effecting
logic on it, return the value unchanged.

## Use case (Drex II)

Brief use of a value without breaking a chain or assigning to
a throwaway variable:

```
do_something.tap do($x)
    log($x)
end.do_more
```

Returns the value `do_something` produced; the `log` call is a
side-effect inserted into the chain.

## Open: where does it live? (Sirella II)

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
object (since every KScript object inherits a root that can
carry it). Receiver in, receiver out. Matches Ruby exactly and
preserves chain ergonomics.

## Open: what does the block receive? (Brunt)

- The receiver itself — natural and useful.

(If `tap` lives on `.object` instead, the block could receive
either the original value or the object helper — another reason
the on-the-value placement is simpler.)

## Status (Zek)

Not in v1 core. Trivial to add when wanted. Filed here so the
discussion isn't lost.
