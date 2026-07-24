# UI

~~~vibecode
{"vibecode": {
	"doc": "requirements_secure_memory_ui",
	"role": "spec for the Caspian-code developer interface to the secure-memory subsystem — the code a developer actually writes to hold, verify, and manage secrets. Covers the Password class API (constructor, verify, hash, needs_rehash?, destroy), declaring password/passkey fields in HTTP route schemas so Touchstone's protected-mode pre-pass kicks in, engine-config entries for process-security settings, anti-patterns and what you deliberately cannot do, and a worked login-route example. The vault (storage) and process-security (OS hardening) primitives are spec'd in the sibling pages; this file is the surface a developer touches.",
	"status": "spec — API surface and configuration surface settled; specific Drinian on_snapshot behavior for handles and full sidecar-map wiring pending",
	"audience": "Caspian developers writing code that handles passwords, passkeys, or other secrets; anyone reviewing the developer-visible surface of the secure-memory subsystem"
}}
~~~

How Caspian developers actually use the secure-memory subsystem in their code. The [vault](vault) and [process-security](process-security) pages spec the mechanics under the hood; this page is the surface a developer touches.

## The Password class

The primary developer-visible interface. A `Password` is a Caspian object whose bucket holds a vault ID — the plaintext bytes live in the [vault](vault) and are never reachable from Caspian code.

### Constructing

Most Password instances arrive via the HTTP path (see next section) and no manual construction is involved. When you do need one directly:

~~~caspian
$pw = Password.new plaintext: $bytes
~~~

The constructor immediately stores the bytes in a fresh vault entry and discards every reachable copy. The `$bytes` source string, if it originated from Caspian code, is on the caller — the constructor can't wipe it because Caspian strings are immutable and may be aliased. Prefer arranging for the plaintext to arrive from an engine-managed path (HTTP body, env var, secrets file) that enters via a protected-mode window and never becomes a Caspian string in the first place.

### Methods

| Method | Purpose |
|---|---|
| `.verify candidate` | Constant-time compare against a candidate password (given as bytes or another `Password`). Returns `true`/`false`. |
| `.hash_for_storage params` | Returns the encoded hash string suitable for storing in a database (e.g. an argon2id-encoded string with algorithm, params, salt, and hash all in one field). |
| `.needs_rehash?` | Returns `true` if the algorithm or its parameters are below the current standard. Application code calls this after a successful `.verify` and reconstructs the Password (with new defaults) before re-storing. |
| `.destroy` | Immediate cleanup: calls `vault.erase(@vault_id)`, marks the handle as spent. Subsequent method calls raise. |
| `.algorithm` (field) | The algorithm name for this instance (`'argon2id'` by default). |

`.destroy` is a manual trigger for callers who want early release. Under normal use, Caspian's deterministic GC fires the `on_close` hook when the last handle goes out of scope, calling `vault.erase` automatically.

## Declaring password fields in HTTP routes

The main way passwords arrive at Caspian code is through HTTP. Declare the field's class in the route schema:

~~~caspian
route '/login' do
	field :id, class: :string
	field :pw, class: 'puck.uno/password'
end

handler do($request)
	$user = $users.find_by_id $request['id']

	if $request['pw'].verify $user.stored_hash
		# authenticated
	end
end
~~~

The `class: 'puck.uno/password'` declaration opts the route into Touchstone's protected-mode pre-pass (see [index § Driving use case](./#driving-use-case-http-password-intake) and [vault § The HTTP intake flow](vault#the-http-intake-flow) for the mechanics). Effects visible to the developer:

- **`$request['pw']` is a `Password` from the first moment user code can touch it.** There is no earlier state where it exists as a plaintext string.
- **The request body has `"#####"` where the password value was.** Safe to log, forward downstream, or feed to other parsers.
- **Routes without a `Password` field pay no protected-mode cost.** The pre-pass only runs when the schema declares one.

Same pattern applies to passkeys and any other secret-typed field — the class in the schema is what drives the pre-pass.

## Explicit protected-mode blocks

For cases outside the HTTP path — CLI tools, script bootstrap, anything reading secrets from files or stdin — Caspian code opens a protected-mode window explicitly with `%process.malloc do ... end`. Inside the block, allocations live in `sodium_malloc`'d secure memory. On block exit, that memory is zeroed and freed. Vault-backed handles (like `Password`) created inside the block **survive past exit**, because the vault owns their storage separately.

Simple example:

~~~caspian
$pw = null

%process.malloc do
	$pw = %('caspian.uno/password/hash').new 'secret password'
end

$pw   # a Password object
~~~

The `'secret password'` bytes exist only inside the block. When the block exits, the secure buffer is wiped. `$pw` retains its Password handle — the plaintext it wrapped is in the vault, not in the (now-freed) block buffer, and never in ordinary heap memory.

### Objects that survive past the block

Normal Caspian scoping applies inside the block. Variables declared inside go out of scope at the end; objects survive if a wider-scope variable holds them. Two shapes to be aware of:

- **Vault-backed handles** (like `Password`) are safe to hold past the block. Their bytes live in the vault, not in the block's secure buffer, so nothing has to move — the handle just keeps working after the block exits.
- **Non-vault objects** (plain strings, tables, anything without vault backing) that get referenced by an outer variable **migrate to regular memory** at block exit. No nanny check: if the developer holds a plaintext string in an outer variable and lets it survive past the block, they now have plaintext in ordinary heap memory. That's the developer's responsibility, not the system's. For anything sensitive that needs to persist, use a vault-backed handle.

### The HTTP intake is built on this primitive

The HTTP password intake described earlier ([route-schema-declares-Password-field](#declaring-password-fields-in-http-routes)) isn't a black box — it's the same `%process.malloc` primitive, at scale. Sketch of the shape underneath:

~~~caspian
$socket = [a socket listening on a port]
$request = null

%process.malloc do
	$raw = $socket.read
	$request = [parse $raw]
	$request['pw'] = %('caspian.uno/password/protected/').new $request['pw']
end

$request['pw']   # protected Password object
~~~

Real Touchstone code is more elaborate — route matching, schema-driven field dispatch, body redaction with the `"#####"` placeholder, sidecar map for reconstitution when `$request` is materialized — but this is the primitive underneath. The socket bytes are read into the protected buffer, parsed inside the window, and the sensitive field is converted to a Password (vault-backed). When the block exits, the parse buffer is wiped; the plaintext exists only in the vault from that point.

The developer using the route-schema form never has to touch `%process.malloc` themselves — Touchstone opens the window for them. The primitive is there for cases where the developer needs explicit control (CLI tools, script bootstrap, custom protocols, or anything outside the HTTP path).

## Engine configuration for process-level protections

The [process-security](process-security) settings are configured in the engine's config file, not touched by user code:

~~~
{
	"secure_memory": {
		"mlockall": true,
		"prctl_dumpable": true,
		"require_ptrace_scope": 2
	}
}
~~~

Application code doesn't reach these — they're operator-controlled at deployment time. See [process-security § Engine configuration](process-security#engine-configuration) for the meaning of each.

## What you deliberately cannot do

The following are absent by design. Attempts to work around them are code smells and usually indicate the developer wants a different pattern:

- **No `.plaintext` accessor.** A `Password` cannot yield its plaintext to user code. If you need to run a cryptographic operation on the bytes, add a `vault.*` gateway operation for it (engine change, deliberate review) — don't try to export.
- **No string coercion.** `Password` doesn't respond to `.to_string` or automatic string interpolation. Attempts print as `<Password>`.
- **No serialization.** Drinian's `on_snapshot` hook for `Password` erases the handle rather than emit anything to the snapshot. A snapshot with a `Password`-holding object surfaces as a handle whose vault entry is gone; the receiver has to re-acquire (re-prompt, re-fetch) to use it again.
- **No logging.** Standard logging paths recognize `Password` and redact. Custom loggers that stringify objects will still just see `<Password>`.
- **No copy-out.** `$new = Password.new plaintext: $pw.something` doesn't compile if `$pw.something` is trying to reach the underlying bytes. The only way to make a new `Password` is to construct from plaintext arriving from an approved engine path.

## Worked example: full login route

~~~caspian
route '/login' do
	field :id, class: :string
	field :pw, class: 'puck.uno/password'
end

handler do($request)
	$user = $users.find_by_id $request['id']
	if $user == null
		%return 401
	end

	if not $request['pw'].verify $user.stored_hash
		%return 401
	end

	# Password was correct. Check if the stored hash is using outdated params
	# and re-hash if so.
	if $request['pw'].needs_rehash?
		$user.stored_hash = $request['pw'].hash_for_storage
		$user.save
	end

	# Issue session, redirect, etc.
	%session.start $user
	%return 302, location: '/dashboard'
end
~~~

What the developer never sees or has to think about:

- The socket-to-parse-buffer copy that happens in Touchstone.
- The protected-mode window that wraps the parse.
- The `vault.store_buffer` call, the sidecar map, the redacted-body reconstitution.
- The `mprotect` transitions inside `vault.verify_password` when `.verify` runs.
- The `on_close` hook that calls `vault.erase` when `$request` goes out of scope at end of handler.

All of that happens under the surface. The developer writes ordinary Caspian code against a `Password` handle and gets the security properties for free.

## Related

- [vault](vault) — how the storage actually works.
- [process-security](process-security) — the OS-level protections that surround the vault.
- [index § Driving use case](./#driving-use-case-http-password-intake) — the HTTP intake flow from the outside.
