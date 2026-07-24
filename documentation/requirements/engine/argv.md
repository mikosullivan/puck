# `%engine.argv`
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_engine_argv",
	"role": "spec for %engine.argv — the array of command-line arguments the host passed to the engine when the program was invoked",
	"shape": "array of strings"
}}
~~~

`%engine.argv` is the array of command-line arguments the program was invoked with, as supplied by the host. The first element is the first user-supplied argument — the launcher binary's own name is not included.

When the host is a CLI runner, `%engine.argv` reflects the shell tokens that came after the program file path. When the host is an embedded runtime (Python, JavaScript, a test harness), the host decides what to place here — typically the analogous list of program arguments if there's one, or an empty array.

Every element is a string. The array may be empty.

## Testing

- **`%engine.argv` is an array** — the return value's class is the array class.
- **Empty argv is an empty array, not null** — invoking the engine with no user-supplied arguments yields `%engine.argv` equal to `[]`.
- **Argv omits the launcher binary's name** — invoking `caspian prog.casp foo bar` gives `%engine.argv` equal to `['foo', 'bar']`, not `['caspian', 'prog.casp', 'foo', 'bar']`.
- **First user argument is index 0** — after `caspian prog.casp first second`, `%engine.argv[0]` is `'first'`.
- **Argv preserves invocation order** — after `caspian prog.casp a b c d`, `%engine.argv` equals `['a', 'b', 'c', 'd']` in exactly that order.
- **Every element is a string** — even when a shell token looks numeric, `%engine.argv[0]` after `prog.casp 42` is the string `'42'`, not the number.
- **Unicode arguments round-trip as UTF-8** — passing `--name Zoë` gives `%engine.argv[1]` equal to `'Zoë'`.
- **Argument with embedded spaces** — a single quoted shell token `'a b c'` becomes one element `'a b c'`.
- **Empty-string argument survives** — passing `""` on the shell gives `%engine.argv[0]` equal to `''` (empty string), not omitted.
- **Very long argv preserves every element** — 1000 shell tokens produce a 1000-element array.
- **Argv elements are role-tagged with the argv faucet's role** — `%engine.argv[0].object.role` is the argv faucet's role, distinct from `user`.
- **Argv is read-only** — `%engine.argv.push('x')` (or any mutating call) raises.
- **Argv cannot be reassigned** — `%engine.argv = []` raises; the slot is not settable.
- **Non-user role reading `%engine.argv` raises** — a method on a non-user-owned class attempting the read raises the `%engine`-blanket runtime error.
- **Non-user role reading `%engine['argv']` (bracket form) raises identically** — the gate applies regardless of accessor syntax.
- **Embedded host with no argv concept exposes `[]`** — a test harness or embedded runtime with no notion of args exposes an empty array, not null.
- **Reading `%engine.argv` multiple times returns equal values** — successive reads inside one process see the same elements.
- **`%engine.argv.length` matches the invocation** — after `caspian prog.casp a b c`, `.length` is `3`.
- **Argv elements' contributors list contains the argv faucet role** — provenance survives into `contributors`.
