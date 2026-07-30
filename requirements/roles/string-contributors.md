# String contributors

~~~vibecode
{"vibecode": {
	"doc": "requirements_roles_string_contributors",
	"role": "spec for the `contributors` list every string carries — the set of roles that participated in producing the string. Under composition (concatenation, interpolation, substring, transformation), the resulting string's contributors list is the union of every input string's contributors. Multi-contributor strings are blocked from certain operations (notably disk writes) unless the caller explicitly allows the operation through. Similar in spirit to Perl's data tainting, but Caspian-native.",
	"status": "draft — mechanism (contributors list, union under composition) and the block-on-write posture settled at the sketch level; the exact set of blocked operations and the unblock mechanism still to be worked out.",
	"audience": "developers writing Caspian who need to reason about multi-role data flow; anyone thinking about supply-chain and provenance guarantees at the string level; security reviewers"
}}
~~~

Every string carries a **`contributors`** list — the set of roles that participated in producing the string. It sits alongside the string's ownership role (see [object-access](object-access)): ownership names the single role that produced the value, while `contributors` names every role whose data flowed into building it.

The two lists differ only for strings that are composed from other strings. A string minted from scratch by a single role has ownership equal to that role and `contributors` equal to `[that role]` — one entry. A string composed from other strings inherits the union of every input's `contributors`, so its `contributors` list can be longer than one.

## How contributors is populated

- **On creation.** A newly-minted string (a literal in source, a fresh construction from bytes) has `contributors = [creating_role]` — the role that ran the code that produced it.
- **Under composition.** Every operation that produces a new string from existing string inputs — concatenation (`+`), interpolation (`"hello, $name"`), substring, slicing, case-changing, formatting — sets the result's `contributors` to the **union** of every input string's `contributors`. Duplicate roles collapse (adding a role that's already present is a no-op).

Concatenation illustrates both:

~~~caspian
$owner_only = 'a' + 'b'          # contributors = [current role]
$mixed = $from_faucet_a + $from_faucet_b   # contributors = [faucet_a, faucet_b]
~~~

## Blocked operations for multi-contributor strings

A multi-contributor string (its `contributors` list has more than one entry) is treated as **tainted** for a set of operations that must not accept mixed-role data without an explicit acknowledgment. The current V1 posture: **writes to disk are blocked**. Additional operations may join the blocked set as concrete situations warrant.

- **Single-contributor** strings pass through freely — they came from one role, and using them in any operation is a purely single-role concern.
- **Multi-contributor** strings raise on a blocked operation. The exception surfaces the fact that the string has multiple contributors and names them, so the caller sees exactly which roles contributed.

The blocked posture is comparable to Perl's data tainting, adapted to Caspian's role model. Perl tainted a value when it came from user input; Caspian tags a string with every role that touched it and blocks based on cross-role composition specifically, not on the "did this come from outside" question.

## Unblocking a multi-contributor string

*(TBD — the mechanism for a caller to explicitly permit a multi-contributor string in a blocked operation is not yet spec'd. Candidates on the table: an explicit `.allow(:for_disk_write)`-style call on the string, a scoped-block form that authorizes disk writes for a specific set of contributor roles, or a signature-review-shaped approach where an authority endorsement lets a specific contributor combination through.)*

## Interaction with ownership

Ownership and contributors are **independent axes**:

- Ownership answers "who is responsible for this value?" — a single role, set by whichever frame created the value.
- Contributors answers "whose data went into this?" — a set of roles, potentially larger than one after composition.

Ownership never grows beyond a single role; the ownership rule (whoever created the value owns it) is unchanged from what [object-access](object-access) already spec's. Contributors is the additional axis that captures the composition history the ownership rule alone can't.

## Testing

- **A literal string has `contributors` equal to `[<creating role>]`** — one entry, the frame that ran the literal.
- **`.contributors` is always a non-empty list** — every string has at least one contributor.
- **A single-contributor string has `contributors.length == 1`** — one entry.
- **Concatenation of two same-role inputs yields one contributor** — `$a + $b` where both are user-owned yields `[user]`.
- **Concatenation of two different-role inputs yields two contributors** — `$net + $user_string` yields `[<net faucet role>, user]` (membership; order unspecified).
- **Interpolation contributes the interpolated values' roles** — `"hello, $name"` where `$name` is from a faucet includes the faucet role.
- **Substring inherits contributors** — `.slice`, `.substring` yield the same contributors as the input.
- **`.upper` and `.lower` inherit contributors** — case-change doesn't add contributors.
- **`.strip` and `.trim` inherit contributors** — whitespace ops preserve.
- **`.replace(...)` inherits contributors from both target and replacement** — the replacement's contributors join the result's list.
- **Duplicate roles collapse** — a concatenation whose inputs both contribute role `X` yields `[X]`, not `[X, X]`.
- **Order in `contributors` is unspecified but stable per identical inputs** — membership is what matters.
- **Ownership is a single role regardless of contributor count** — `.obj.role` is one role.
- **Ownership names the creating frame** — not any input role.
- **A multi-contributor string raises when written to disk** — V1 blocked posture.
- **The raised error names every contributing role** — the exception exposes the full list.
- **A single-contributor string is not blocked on disk write** — the same write succeeds.
- **A multi-contributor string can still be concatenated further** — composition is not blocked.
- **A multi-contributor string can still be printed to stdout in V1** — stdout is not blocked (V1).
- **A multi-contributor string can still be passed as an HTTP body in V1** — network writes are not blocked (V1).
- **Adding an already-present role via composition is a no-op** — list length doesn't grow.
- **An empty-string concatenation preserves the non-empty side's contributors** — `'' + $foo` matches `$foo` exactly.
- **`contributors` survives storage in a container** — reading `$hash['key']` returns the same string with the same list.
- **`contributors` survives passing across a role boundary** — the recorded list travels with the value.
- **`contributors` does not survive serialization** — a deserialized string is a new object; contributors is set fresh at the reader's role.
- **A newly-minted string via non-composition creation has one contributor** — bytes-to-string construction has `[creating role]`.
- **Contributors of the empty string equal `[creating role]`** — even the empty string is single-contributor.
- **Slicing zero characters yields a value with the same contributors** — no shortcut for empty-result-drop-contributors.
- **Comparing contributors of two derived strings** — two strings derived from the same inputs have equal (as sets) contributors lists.
- **A string's contributors is not settable** — mutation raises.
- **The blocked-operations set is minimal in V1: disk writes** — no other operations block in V1 (spec statement; verify by writing a multi-contributor string to non-disk sinks).

## Related

- [object-access](object-access) — the ownership rule (single-role) that this list complements.
- [built-in-classes/primitives/string](https://puck.uno/requirements/built-in-classes/primitives/string/) — where the string surface is spec'd.
- [roles/](./) — the role system that names both the ownership role and each contributor.
