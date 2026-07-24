# Syntax
<!--index: 9-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_syntax",
	"role": "hub page for Caspian's surface syntax. Each area (comments, sigils, variables, operators, truthy/falsy, control flow, blocks, callable definitions, calls, classes, system-method sigils, pipes) is its own sub-page. Deeper areas (full parameter metadata, exceptions, regex, DSL, class inheritance, string interpolation, CaspianJ mapping) get their own sub-pages as they land.",
	"status": "basic syntax split across sub-pages; deeper areas TBD",
	"audience": "developers writing Caspian; tooling authors building lexers, parsers, formatters, syntax highlighters, and language-server implementations"
}}
~~~

This section covers Caspian's surface syntax — what a programmer actually types. Semantics (what constructs DO) live in the concept docs (roles, chain, plumbing, etc.); the CaspianJ tree (what the parser produces) has its own doc.

## Basic syntax

- [Comments and whitespace](https://puck.uno/documentation/requirements/syntax/comments-and-whitespace) — line comments and lexical whitespace rules.
- [Trailing commas](https://puck.uno/documentation/requirements/syntax/trailing-commas) — allowed only inside `[]`, `{}`, and `()`; paren-less call positions reject.
- [Sigils](https://puck.uno/documentation/requirements/syntax/sigils) — `$`, `&`, `@`, `%` and what each names.
- [Variables and assignment](https://puck.uno/documentation/requirements/syntax/variables-and-assignment) — `=`, compound operators, assignment targets, scope.
- [Subscripts](https://puck.uno/documentation/requirements/syntax/subscripts) — `recv[k]`, multi-key `recv[k1, k2, ...]` walking nested containers, auto-vivify on assignment, trailing `?` for null-safe.
- [Operators](https://puck.uno/documentation/requirements/syntax/operators) — arithmetic, comparison, logical, ternary. No precedence table.
- [Truthy and falsy](https://puck.uno/documentation/requirements/syntax/truthy-and-falsy) — only `null` and `false` are falsy.
- [if and unless](https://puck.uno/documentation/requirements/syntax/if-unless) — `if`/`elsif`/`else`, `unless`, and the `as $conditional` chain-exit binding.
- [Loops](https://puck.uno/documentation/requirements/syntax/loops) — `while`, `until`, `begin ... while` / `begin ... until`, `.each`, numeric helpers, `as $loop`, `break`/`break N`, structural blocks.
- [Bare blocks](https://puck.uno/documentation/requirements/syntax/bare-blocks) — `begin ... end` for grouping and scoping; `as $block` controller with `.return`.
- [Clause slots](https://puck.uno/documentation/requirements/syntax/clause-slots) — the `body` / `before` / `between` / `after` / `noloop` / `ensure` clauses any block-carrying construct (loops, `begin`, callables) can have, including scope rules and the iterator-method convention.
- [Classes](https://puck.uno/documentation/requirements/syntax/classes) — nameless `class`, inline `# label` convention, `&init`, instantiation.
- [System-method sigils](https://puck.uno/documentation/requirements/syntax/system-method-sigils) — `%self`, `%call`, `%chain`, `%engine`, and the six bare-`%X` shortcuts.
- [Pipes](https://puck.uno/documentation/requirements/syntax/pipes) — `|` passes the left result as the first arg to the right; `|&` adds sticky null-propagation.

## Not covered here yet

Sub-pages will fill these in as they get written:

- **Full parameter metadata** — inline `{lazy: true, optional: true, ...}` blocks, `*rest`, `**opts`, class constraints.
- **Regex literals** — the syntax for pattern literals.
- **Exceptions** — raise and the catch mechanism.
- **DSL / bwc entries** — the block-word-callable mechanism that lets libraries register keywords (like `break` and `next` inside loops).
- **Class inheritance** — how one class inherits from another.
- **String interpolation** — the mechanism for embedding expressions in string literals.
- **CaspianJ mapping** — the transformation the parser produces, section by section.

## Where semantics live

- [roles](https://puck.uno/documentation/requirements/roles/), [chain](https://puck.uno/documentation/requirements/chain/), [plumbing](https://puck.uno/documentation/requirements/plumbing/) — what the constructs DO.
- [global-methods](https://puck.uno/documentation/requirements/global-methods/) — per-method spec of the `%X` surfaces.
- [chain/methods/](https://puck.uno/documentation/requirements/chain/methods/) — per-method spec of each `%chain.X`.
