# Hash deletion shortcut

Speculative — filed for future consideration. The canonical form
is `$hash.delete($key)`; this idea is about whether a shorter
syntax would carry its weight.

## Candidates

- **`$hash -= $foo`** — assignment-style. Scales to arrays
  naturally: `$hash -= ['a', 'b', 'c']` for batch removal.
  Parallels set difference. Mild ambiguity with numeric
  subtraction in theory, but `$hash` is a hash so unambiguous
  in practice.
- **`$hash-[$foo]`** — visually compact. Unambiguous because
  no other operator combines `-` and `[`. Could extend to
  batch form (`$hash-{a, b}`?) but the shape is less obvious
  than the `-=` version.
- **`delete $hash[$foo]`** — keyword prefix, familiar from
  Python and Perl. Verbose but readable; zero ambiguity.
- **`$hash[$foo].delete`** — chained postfix. Works today via
  the element-object API (`$hash.elements.find_by_key($foo).delete`),
  but a direct `$hash[$foo].delete` would need `[]` to return
  an Element rather than a value.

## Recommendation (not committed)

`$hash -= $foo` is the cleanest; the batch form falls out for
free and the syntax has set-theory roots that scale to other
collection types if wanted.

## Status

Not in v1. The standard `$hash.delete($key)` covers the use case;
this is purely about ergonomics. Revisit if hash deletion proves
to be a hot enough operation in real code to justify dedicated
syntax.
