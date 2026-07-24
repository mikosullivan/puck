# When newlines are significant in Caspian

> **Policy landed as spec** at [syntax/comments-and-whitespace](../../requirements/syntax/comments-and-whitespace) — newlines are generally not significant; the parser figures out statement boundaries from context; semicolons are command separators (with redundant ones ignored); exceptions like heredocs are called out per-page. This ideas doc retains the case analysis and reasoning that led to the policy.

~~~vibecode
{"vibecode": {
	"doc": "ideas_newline_significance",
	"role": "exploration of where newlines are (or should be) significant in Caspian syntax — the question of when newline functions as a statement / expression separator vs when it's ignorable. Not specifically about pipes; the general question came up during pipe-scoping discussion but applies across the language. Surveys the cases where newlines matter, identifies which are unambiguous and which need a rule, and recommends a coherent policy across the language.",
	"status": "exploration with recommendations — cases surveyed, one rule proposed (newlines are statement separators; trailing operator continues; leading operator does not; delimited contexts suppress newline-significance); alternative Ruby-style leading-operator continuation flagged as a consideration",
	"audience": "Miko; anyone working on Caspian's parser / tokenizer or reasoning about the surface syntax's boundary rules"
}}
~~~

## The question

Most of Caspian's syntax is unambiguous about statement / expression boundaries without newlines being special — braces, parens, keywords like `end` bound expressions cleanly, so a compiler could plausibly treat the source as a stream of tokens with whitespace (including newlines) as non-significant.

But two shapes come up where newlines look significant:

**Two adjacent calls on one line vs on separate lines:**

~~~caspian
&foo 'blah'
&bar
~~~

reads clearly as two statements. Now the same tokens on one line:

~~~caspian
&foo 'blah' &bar
~~~

Sloppy, yes — but should it be a syntax error, or a valid Caspian call with two arguments?

**Line-leading operator that looks structurally attached:**

~~~caspian
&foo('blah')
| &bar
~~~

The leading `|` on the second line reads like continuation of a pipe chain — but formally, is it a continuation or an invalid statement start?

Both scenarios generalize past their specific tokens. The underlying question is: **what role do newlines play in Caspian source?**

## Case survey

Each case below shows what shape it takes, what a reasonable reader might expect, and what the parser rule needs to decide.

### Case 1 — Two calls, no separator

~~~caspian
&foo 'blah' &bar
~~~

Three possibilities:

- **Two statements.** `&foo 'blah'` then `&bar`. Requires the parser to guess where one call ends and the next begins.
- **One call, two args.** `&foo` called with `'blah'` and `&bar` as positional arguments — the way Ruby's parens-optional call would read it in some contexts.
- **Syntax error.** Statements need explicit separators.

The problem with option 1 is the parser needs a rule for "where does a call end?" — bare-name calls with unknown-arity would need a heuristic (probably ugly). Option 2 conflates two statements as a two-arg call — silent misinterpretation is the worst outcome. Option 3 keeps the language predictable but requires developers to always write a separator between statements on the same line.

### Case 2 — Leading operator on next line

~~~caspian
&foo('blah')
| &bar
~~~

Three possibilities:

- **Continuation.** The `|` at line start is a signal that this expression continues the pipe chain from the previous line. Ruby handles method chains this way (leading `.`).
- **Syntax error.** Statements can't start with a binary operator; the developer meant to write the pipe with trailing `|` on the previous line.
- **Two statements** — the previous line is a complete expression, and the line starting with `|` is a new (invalid) statement.

Option 1 (leading-operator continuation) is convenient but requires the parser to look ahead — after every line's final token, check if the next line's first non-whitespace token is a continuation-marker.

Option 2 is simpler: only **trailing operator** implies continuation. Developer writing multi-line pipes puts `|` at the end of each continuing line. If someone writes leading `|`, they get a clear error.

### Case 3 — Trailing operator continuation

~~~caspian
$result = &foo() |
	&bar |
	&baz
~~~

Widely established convention (Ruby, some others). Line ending in binary operator = continues onto the next line. Cleanly parseable without look-ahead — the trailing operator is a token the parser can see when processing the current line.

**Recommended as the canonical multi-line form** regardless of what we decide about Case 2.

### Case 4 — Multiple statements, one per line

~~~caspian
&foo 'blah'
&bar
~~~

Two statements, clearly separated by a newline. This is the shape everyone expects. Universally supported by any reasonable rule.

### Case 5 — Delimited contexts: parens, brackets, braces

~~~caspian
&outer(
	&inner('a'),
	&inner('b')
)

$hash = {
	key1: 'value1',
	key2: 'value2'
}

$array = [
	1,
	2,
	3
]
~~~

Newlines inside `()`, `[]`, `{}` should not terminate the expression — the delimiters bound the expression and newlines are just whitespace. This is universal in modern languages.

### Case 6 — Blocks and `end`

~~~caspian
if $cond
	&do_a
	&do_b
end
~~~

Newlines separate statements inside the block; `end` closes it. Same-line form uses `then` or is disallowed:

~~~caspian
if $cond then &do_a end
~~~

Block boundaries don't need a "newline is significant" rule specifically — the keywords carry the structure. Newlines only matter here for the statement separation inside the block, which reduces to Case 4.

### Case 7 — Method chains across lines

~~~caspian
$result = $obj
	.method1()
	.method2()
~~~

This is Case 2 with `.` instead of `|`. Same question, same three options: continuation, error, or two statements. Same recommended answer: prefer the trailing-operator form:

~~~caspian
$result = $obj.method1().
	method2()
~~~

Or use parens to allow leading `.`:

~~~caspian
$result = ($obj
	.method1()
	.method2())
~~~

## The core question

Every case above reduces to a choice about **what a newline means at expression / statement boundaries**. Three coherent policies, in order of permissiveness:

### Policy A — Strict: newlines are separators; only trailing operators continue

- A newline outside any delimited context (`()`, `[]`, `{}`, block body) ends the current expression / statement.
- To continue an expression across lines, end the current line with a binary operator (`|`, `+`, `.`, `&&`, `||`, `,`).
- A line starting with a binary operator (leading `|`, `+`, `.`) is a syntax error.
- Multiple statements on one line require an explicit separator (`;`) — `&foo() &bar()` is invalid.

Predictable, parseable without look-ahead. Rejects the "sloppy but readable" shapes as syntax errors.

### Policy B — Middle: leading OR trailing operators continue

- Same as A, plus: a line that starts with a binary operator continues the previous line's expression.
- Same as A on same-line multiple statements — still requires `;`.
- The parser looks ahead one line at every statement boundary.

Accepts leading-operator continuation like `&foo()\n| &bar`. Still rejects `&foo() &bar()` on one line.

### Policy C — Permissive: whitespace is generally non-significant

- Newlines are just whitespace at statement-boundary level. Two statements on the same line don't need `;`, and continuation across newlines works whether operators are trailing OR leading.
- Both `&foo 'blah' &bar` (two statements, one line, no separator) and `&foo()\n| &bar` (leading-operator continuation) are legal.
- The parser figures out expression boundaries from context — matched delimiters, keyword scopes, operator precedence.

Miko's stated preference. Every example shape in the survey above parses as valid Caspian under this policy.

## Recommendation: Policy C

Recommend Policy C — permissive whitespace, all example shapes valid.

Miko has marked every example in the survey as valid syntax, which means:

- `&foo 'blah' &bar` on one line — two statements, no separator required.
- `&foo()\n| &bar` — leading `|` continues the pipe chain.
- `&foo() |\n &bar` — trailing `|` continues the pipe chain (still works).
- `$obj\n .method()` — leading `.` continues the method chain.
- Multi-line calls, hash literals, method chains all work naturally.

The rule is essentially "if it can be parsed unambiguously from the tokens, it's valid." Developers write what reads naturally; the parser is generous about accepting it.

### Reasons this works

- **Reads how developers already think.** A leading `|` on the next line is visually attached; forcing the developer to move it to the previous line is a discipline that has to be taught and enforced.
- **Consistent with Caspian's no-nanny-code posture** ([concepts § No nanny code](https://puck.uno/documentation/requirements/concepts#no-nanny-code)). Rejecting sloppy-but-parseable syntax is the parser saying "you can't because I think you shouldn't." Permissive parsing lets the developer decide.
- **Same-line juxtaposition is rare in practice.** `&foo 'blah' &bar` reads as sloppy code and most developers won't write it. But if someone does, the parser accepts it rather than rejecting it as an error.
- **Fewer rules to teach.** No "trailing operator vs leading operator" rule to memorize. Fewer edge cases in style guides.

### Concerns worth stating for the record

- **Ambiguity in call arity.** `&foo 'blah' &bar` — is this two statements (`&foo('blah'); &bar()`) or one two-arg call (`&foo('blah', &bar)`)? The parser needs a rule. Cleanest: **without commas, positional arg lists end at the first non-argument token** (a newline, another call, or a statement-level construct). So `&foo 'blah' &bar` is two statements. `&foo 'blah', &bar` (with explicit comma) is one call with two args.
- **Look-ahead complexity.** Both continuation forms (trailing and leading operators) require the parser to consider what's on the next line before finalizing the current expression. Non-trivial for the parser, but well-understood technique.
- **Silent misreads become possible.** A statement intended to be new but starting with an operator gets absorbed into the previous statement. Mitigation: developers who care about clarity can always add `;` or leave a blank line to be explicit.

None of these are blockers, but the parser needs to answer each of them precisely.

## Concrete rules

If Policy C is adopted, these rules follow:

1. **Statement boundaries are determined from context**, not fixed to newlines or `;`. Newlines, `;`, and juxtaposition of expressions can all serve as statement separators.
2. **Explicit `;` still works** for clarity: `&foo(); &bar()`. It doesn't cause anything to change; it's just a way to be explicit.
3. **Trailing operator continues.** A line ending in a binary operator (`|`, `|&`, `+`, `-`, `*`, `/`, `%`, `.`, `,`, `&&`, `||`, `==`, `!=`, `<`, `>`, `<=`, `>=`) continues onto the next line.
4. **Leading operator on next line also continues.** A line starting with a binary operator continues the previous line's expression. Both forms parse identically.
5. **Delimited contexts (`()`, `[]`, `{}`, multi-line strings) suppress newline significance** as usual.
6. **Bare-name argument lists end at the first non-argument token.** Without a comma, `&foo 'blah' &bar` is two statements. With one, `&foo 'blah', &bar` is one call with two args. The comma is the "keep going" signal for argument lists.
7. **Blocks use their existing keyword-based structure.** `if $cond ... end`, `while $cond ... end`, `class ... end`. Statement separation inside blocks follows the same permissive rules.

## Consequences for existing docs

Under Policy C:

- **Pipes** — [syntax/pipes](https://puck.uno/documentation/requirements/syntax/pipes) currently documents multi-line pipes with trailing `|`. Under Policy C, both trailing-`|` AND leading-`|` on next line work. Doc could note this or leave the recommendation as-is (trailing) with the understanding that leading-`|` also parses.
- **Method chains** — same shape as pipes; leading `.` or trailing `.` for continuation both work.
- **Arithmetic** — same rule: `$a + $b` on one line, or split across lines with the operator at either end.
- **Function calls with many args** — args span lines inside paren-bound lists (unchanged) or via comma continuation.

## Alternative if permissive proves problematic

Policy A (strict) is available as a fallback if Policy C creates real problems in practice — parser bugs, developer confusion around silent-misread cases, or tooling difficulty. Policy A trades permissiveness for parser simplicity and clearer error messages. The choice is reversible if issues emerge.

## Related

- [syntax/pipes](https://puck.uno/documentation/requirements/syntax/pipes) — pipe operators, which raised this question during design.
- [syntax/](https://puck.uno/documentation/requirements/syntax/) — the hub for surface syntax specs; wherever this policy lands, it lives there.
