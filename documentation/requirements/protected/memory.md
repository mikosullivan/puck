# `core:protected/memory`

<span class="tag">protected-memory</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected_memory_memory",
	"role": "spec for `core:protected/memory` — the Caspian-side entry point to protected-mode windows. `.run do ... end` block form; entering the block opens a protected-mode window (sodium_malloc'd buffer, mlock'd, MADV_DONTDUMP'd); code inside can allocate protected buffers, hand them to vault-backed persistent storage (Password, core:protected/hash, Passkey authenticator-side), or let them be automatically zeroed and freed at block exit. Lives in the `core:protected/*` namespace alongside its siblings hash, hash/http, and password. The engine-internal 'protected mode' discipline (spec'd on the vault Lua module) is the same mechanism at the C layer; `core:protected/memory` is the Caspian-visible entry point that opens one of those windows on demand.",
	"status": "spec — API surface (`.run` block, auto-cleanup, vault-backed-handle survival, nesting) settled; specific method surfaces for reading directly into a protected buffer from privileged sources pending",
	"audience": "Caspian developers writing CLI tools, script bootstrap, or any code that needs to hold raw secret bytes briefly before handing them to a vault-backed class; engine implementers wiring the Caspian-side entry point to the C-layer protected-mode discipline"
}}
~~~

`core:protected/memory` is the Caspian-side entry point to a **protected-mode window**. Enter the window with a `.run do ... end` block; inside the block, allocations land in `sodium_malloc`'d protected memory; at block exit, any bytes not handed to a persistent protected-storage class are automatically zeroed and freed.

The engine already runs a protected-mode discipline internally — see [vault § Protected mode](tag:vault-protected-mode). This class exposes that discipline to Caspian code so a developer can open a window on demand (for CLI tools, script bootstrap, custom protocols — anything outside the HTTP path where the engine opens the window automatically as part of Touchstone's schema-driven pre-pass).

Accessed via `%('core:protected/memory')`.

## The `.run do` block

The primary interface:

~~~caspian
%('core:protected/memory').run do
	# inside a protected-mode window
end
~~~

- **Entering the block** opens a protected-mode window: a `sodium_malloc`'d buffer with guard pages, `mlock`'d into RAM, `MADV_DONTDUMP`'d. See [vault § sodium_malloc: what a vault entry looks like](tag:sodium-malloc-anatomy).
- **Inside the block**, ordinary Caspian scoping applies. Allocations that would normally land in the Caspian heap land in the protected buffer instead.
- **On block exit**, the protected buffer is zeroed (`sodium_memzero`) and freed (`sodium_free`). Any Caspian value that lived in the buffer is wiped.
- **Vault-backed handles** (Password, `core:protected/hash` entries, direct vault entries) constructed inside the block **survive past exit**, because their storage is vault-owned separately from the block's buffer. The handle stays valid; the bytes it wraps live in the vault, not in the (now-freed) block buffer.

The block's return value is whatever the block's last expression evaluates to (Caspian standard).

## Example: reading a password from a file

~~~caspian
$pw = %('core:protected/memory').run do
	$bytes = %fs.read '/etc/caspian/db-password'
	return Password.new plaintext: $bytes
end

$pw   # a Password handle — plaintext lives in the vault, not in Caspian heap
~~~

The file's contents land in the protected buffer via `%fs.read` (which, inside a `.run` block, allocates into the protected buffer rather than the regular heap). The `Password.new` constructor moves those bytes into the vault. When the block exits, the protected buffer is wiped — `$bytes` is gone, `$pw` remains, and the plaintext exists only in vault-owned memory.

## Example: reading from stdin

~~~caspian
$pw = %('core:protected/memory').run do
	return Password.new plaintext: %stdin.read
end
~~~

Same shape. `%stdin.read` inside the block reads into the protected buffer.

## Rules on what survives the block

Two categories:

- **Vault-backed handles** — Password, `core:protected/hash`, `core:protected/hash/http`, Passkey (authenticator-side), and future secret-carrying classes. Safe to hold past the block. Their bytes live in the vault (or vault-backed storage), not in the block's protected buffer. Handles stay valid after the block exits.
- **Plain values** — strings, numbers, hashes, arrays. Ordinary Caspian scoping applies. A plain value assigned to a variable declared inside the block goes out of scope at block exit. A plain value assigned to an outer-scope variable is copied into ordinary heap memory before the block's buffer is freed — the copy is unprotected from that point on.

No nanny check on the second case. If a developer assigns a plaintext string to an outer variable and lets it survive past the block, they've told the system to keep the bytes, and the system honors that by copying the value out of the protected buffer before the buffer is freed. The developer's choice, the developer's responsibility. For anything sensitive that must persist past the block, use a vault-backed handle.

## Nesting

Blocks can nest. Each `.run do` opens its own protected-mode window with its own buffer. The inner block's buffer is freed when the inner block exits; the outer block's buffer is freed when the outer block exits.

~~~caspian
%('core:protected/memory').run do
	$outer_secret = %fs.read '/etc/caspian/master-key'

	%('core:protected/memory').run do
		$inner_secret = %fs.read '/etc/caspian/db-password'
		# inner buffer holds $inner_secret
		# outer buffer still holds $outer_secret
	end

	# inner buffer freed here — $inner_secret gone
	# outer buffer still alive — $outer_secret still readable
end

# outer buffer freed here — everything gone
~~~

Nesting is safe but rarely needed in practice. A single top-level `.run do` handles the common case.

## Exit runs on exception

If code inside the block raises, the block-exit cleanup still runs. The protected buffer is zeroed and freed before the exception propagates to the caller.

~~~caspian
%('core:protected/memory').run do
	$bytes = %fs.read '/etc/caspian/db-password'

	raise 'something went wrong'
	# buffer is still zeroed and freed before the raise propagates
end
~~~

No leak past the block boundary regardless of how the block exits — normal return, early return, or raise.

## Where developers actually use this

- **HTTP intake for password fields** — Touchstone opens the window automatically as part of its schema-driven pre-pass. User code declares the field as a `Password`; the window opens under the hood. See [ui § Declaring password fields in HTTP routes](ui#declaring-password-fields-in-http-routes).
- **CLI tools** — a Caspian script that reads a password from stdin or a keyfile before doing something with it opens `.run do`, reads, constructs a Password, lets the block close.
- **Script bootstrap** — reading secrets from files or environment variables at startup.
- **Custom protocols** — any request-response handling not going through Touchstone's HTTP path.

The primitive is deliberately exposed at the developer level so any code path that needs the protected-mode discipline can open its own window without depending on Touchstone.

## Relationship to the vault

The C-layer "protected mode" discipline is spec'd on the [vault Lua module § Protected mode](tag:vault-protected-mode). `core:protected/memory` is not a new mechanism — it's the Caspian-side entry point to the same mechanism. Every `.run do` block is a protected-mode window in the sense the vault spec defines; the block form gives Caspian code a lexical boundary that matches the buffer lifetime.

The vault owns per-secret persistent storage; `core:protected/memory` owns the short-lived window in which bytes live long enough to be handed to a persistent-storage class.

## Testing

- **Empty block runs successfully** — `%('core:protected/memory').run do end` returns without error.
- **Block returns last expression** — `%('core:protected/memory').run do 42 end` returns `42`.
- **Vault-backed handle survives** — `$pw = %('core:protected/memory').run do return Password.new plaintext: 'x' end`; `$pw` is a valid Password handle after the block.
- **Plain value migrates to unprotected heap** — `$s = %('core:protected/memory').run do return 'plaintext' end`; `$s` holds `'plaintext'` in ordinary heap after the block. Deliberate; no error raised.
- **Nested blocks each get their own buffer** — outer and inner allocations are cleaned at their respective block exits (verified at the engine layer).
- **Block exit zeroes buffer** — after block exit, the protected buffer's memory has been `sodium_memzero`'d and `sodium_free`'d (verified at the engine layer).
- **Guard pages catch overflow** — code inside the block that overflows the protected buffer segfaults on the guard (verified at the engine layer).
- **Block exit runs on exception** — if code inside the block raises, the block-exit cleanup runs before the exception propagates; the buffer is still freed.
- **Vault-backed handle survives independent of buffer freeing** — a Password handle constructed inside still verifies correctly after block exit; the plaintext lives in the vault, unaffected by the block's buffer being freed.
- **Vault-backed handle constructed inside then discarded is properly cleaned** — a Password constructed inside and NOT assigned to an outer-scope variable has its vault entry freed when the block exits (the handle went out of scope; the GC runs; the vault entry is erased).

## Related

- [vault](tag:vault) — the C-layer protected-mode discipline this class exposes; the persistent-storage primitive that handles constructed inside a `.run` block hand off to.
- [`core:protected/hash`](hash/) — the write-only key/value protected-storage class; instances constructed inside a `.run` block survive past exit.
- [`core:protected/hash/http`](hash/http) — the HTTP-scoped subclass; same survival behavior.
- [Password](password) — the canonical vault-backed handle safely constructed inside a `.run` block.
- [ui](ui) — developer-facing usage patterns for password fields on HTTP routes; the intake path Touchstone opens automatically instead of the developer opening `.run do` themselves.
