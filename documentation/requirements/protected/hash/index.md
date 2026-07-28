# `core:protected/hash`

<span class="tag">protected-hash</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected_memory_hash",
	"role": "spec for `core:protected/hash` — Caspian's write-only key/value container. Values live in C-allocated protected memory (`mlock`, `madvise(MADV_DONTDUMP)`, `explicit_bzero` on free); Caspian's surface offers write-only access; only a small allow-listed set of engine-internal Lua modules can read via a separate trusted binding. Base class for every secret-carrying primitive: Password, `core:protected/hash/http` (used by `core:auth/api`), and future encryption / TLS key classes all build on it. Accessed via `%('core:protected/hash')`; loaded from JSON via `.read(file)` which parses directly into protected memory without touching Caspian-visible heap. Values may be any JSON type — string, number, boolean, null, nested hash, nested array — all stored recursively in protected memory. Subclasses may add stricter constraints (e.g. `hash/http` requires flat scalar values with HTTP-sanitary bytes).",
	"status": "spec — write-only Caspian surface, native-Lua read path, base-class role for secret-carrying primitives, and nested-value support all settled",
	"audience": "developers writing Caspian classes that need to hold secret data; engine implementers building the secret-storage infrastructure; anyone auditing the trusted-path boundary"
}}
~~~

`core:protected/hash` is Caspian's write-only secret container. Values you put in are stored in C-allocated protected memory; from Caspian code, there is no way to read them back out. Only a small allow-listed set of engine-internal Lua modules (via a separate trusted binding) can read.

It's the base primitive that every other secret-carrying class ([Password](../password), [`core:auth/api`](../auth/api) via the [`http`](http) subclass, future encryption / TLS key classes) is built on. Anything that needs to hold bytes safely uses `core:protected/hash` for storage and adds its own domain-specific methods on top.

Accessed via the `core:` URL scheme: `%('core:protected/hash')`.

## Caspian-side surface

The whole external API from Caspian is deliberately minimal — one write operation, one file-load operation, and nothing else.

~~~caspian
$hsh = %('core:protected/hash').new

$hsh['token']  = 'sk_live_abc123...'      # write string
$hsh['scheme'] = 'bearer'
$hsh['config'] = {retry: 3, timeout: 30}  # write nested hash

$hsh['token']                             # RAISES
~~~

**What works:**

- `$hsh[key] = value` — set a value. Overwrite is allowed (rotation). Values may be any JSON type: string, number, boolean, null, hash, or array. Nested structures are recursively copied into protected memory.
- `$hsh.delete(key)` — remove a key. Zeros the underlying bytes for the entire subtree.
- `%('core:protected/hash').read($file)` — construct a `protected/hash` by reading a JSON file. See [File loading](#file-loading) below.

**What raises:**

- Any read attempt: `$hsh[key]`, `$hsh.keys`, `$hsh.has?(key)`, `$hsh.size`, `$hsh.each_key`, `$hsh.each`, `$hsh.equals?($other)`.
- Any serialization: `$hsh.to_string`, `$hsh.to_json`, string interpolation `"#{$hsh}"`.
- Any conversion or comparison against a plain value.

Nothing about the hash is inspectable from Caspian. Zero visible state. This is deliberate: any inspection surface — even "how many keys are set" — is a potential attack signal, and there's no proven need. If a specific inspection operation turns out to be genuinely needed later, we'll add it then. Taking inspection away later is impossible.

## Subclasses

Subclasses may add stricter constraints on the write path. The current subclass:

- **[`core:protected/hash/http`](http)** — flat-only (no nested hashes or arrays), keys must be HTTP `tchar`-set only, values must be HTTP-sanitary bytes. Used by [`core:auth/api`](../auth/api) for outbound HTTP credential storage.

A subclass rejects violating input at set time; the base class itself has no such restrictions.

## File loading

`%('core:protected/hash').read($file)` reads a JSON file and constructs a `protected/hash` from its top-level structure. The parse happens in **native code** — the JSON is never materialized as a Caspian string or a plain Lua string. Values land directly in protected memory.

~~~caspian
$hsh = %('core:protected/hash').read('/etc/caspian/stripe-creds.json')
~~~

Where `stripe-creds.json` is:

~~~json
{
	"scheme": "bearer",
	"token": "sk_live_abc123..."
}
~~~

Rules on the file:

- **Top level must be a JSON object.** A file whose top-level value is an array or scalar raises at load — there are no keys to hash on.
- **Nested values may be any JSON type.** Nested hashes and arrays are recursively copied into protected memory. Subclass `.read` may enforce narrower rules (`hash/http` rejects nested structures and non-string values).
- **Parse is atomic.** Either the whole file lands in protected memory or the load raises; no partial-load state.
- **File access is subject to normal `%engine.fs` capability rules** — the caller must have read permission on the path.

## Storage layer (native-side)

Values live in **C-allocated memory**, not Lua tables. The Lua-side handle to a `protected/hash` is a userdata carrying an opaque pointer to the C backing buffer; the actual bytes are unreachable from Lua's `debug` library or any table walk.

The C-side implementation applies four defenses:

1. **`mlock()` on the backing pages.** Prevents the OS from paging secret bytes to swap.
2. **`madvise(MADV_DONTDUMP)` on the backing pages.** Excludes those pages from any core dump the process might produce. Normal debugging still works for other memory regions; secret pages are silently absent from the dump.
3. **`explicit_bzero()` on free.** Zeroes the bytes when a value is overwritten, deleted, or when the whole `protected/hash` is garbage-collected. Uses `explicit_bzero` (not `memset`) so the compiler can't optimize it away.
4. **Zero on GC.** When the Caspian handle to a `protected/hash` becomes unreachable and the GC runs, the C-side backing (including all nested subtrees) is freed with a full zero-out.

Optional stricter posture (deployment-level, not default): **`prctl(PR_SET_DUMPABLE, 0)`** at engine startup. Disables all core dumps for the process AND disables non-root `ptrace` attachment. Kills developer debuggability of the running engine; use only for production deployments where the trade is worth it. Toggled via an engine-config flag.

Deeper hardening (encryption-at-rest in memory via libsodium's `sodium_mprotect_*`, etc.) is possible but not part of the V1 default — the four defenses above cover everything short of root-level attackers, and stronger measures have diminishing returns against attackers who already have root.

## Trusted-path Lua binding

The C module for `core:protected/hash` exposes **two Lua bindings** at different visibility:

- **Public binding** — `require("caspian.core.protected.hash")`. Available to any Lua code in the engine. Exposes `.new`, `[]=`, `.delete`, `.read`. No read function.
- **Trusted binding** — `require("caspian.core.protected.hash_trusted")`. Also exposes `.read(handle, key)` returning the value as a Lua string / number / table / etc. Loader-gated: on `require`, the C module inspects the caller's chunk name via `lua_getinfo(L, "S", ...)` and raises unless the caller's source path is in a small allow-list.

The allow-list is baked into the engine build. It includes only files that legitimately need to read secret bytes to do their job — the `core:auth/api` implementation, the HTTP transport's auth-injection code, the Password class's verify path, the encryption primitives' key path. Every other Lua file (engine-internal or downloaded) can only get the public binding.

Adding a new allow-listed file is an engine change reviewed like any other engine change — no downloaded class or user-loaded Lua can extend the allow-list at runtime.

## `debug.*` restrictions

Lua's `debug` library (`debug.getlocal`, `debug.getupvalue`, `debug.sethook`, etc.) can inspect any Lua-heap value — including local variables inside functions that briefly hold decrypted secret bytes during a signing operation. To prevent inspection from within the same VM:

- **Trusted engine Lua** keeps `debug.*` for its own uses (stack traces on error, etc.).
- **Any Lua context that runs downloaded / user-loaded Lua code** has `debug.*` removed or heavily restricted at VM initialization. Downloaded classes cannot hook trusted engine functions.

Enforced practically by separate Lua states (one for trusted engine code, one per untrusted-context boundary) or by removing the `debug` global from the environment before untrusted code runs.

## Base class for secret-carrying primitives

`core:protected/hash` is the base class for every other secret-carrying primitive in Caspian. Subclasses inherit all the storage / safety machinery for free and add their own domain-specific methods on top.

- **[Password](../password)** — a `protected/hash` with one conventionally-keyed value (`'password'` or `'hash'`), plus password-specific methods (`.verify(plain_input)` with constant-time compare, `.hash_algorithm` accessor, `.needs_rehash?`).
- **[`core:protected/hash/http`](http)** — a `protected/hash` restricted to flat scalar values with HTTP-sanitary keys and values. The credential container used by [`core:auth/api`](../auth/api) for outbound API authentication. Sibling `core:auth/*` classes cover other auth flavors (user login, session, OAuth).
- **Future subclasses** — encryption keys (`.encrypt(bytes)` / `.decrypt(bytes)`), TLS private keys (`.tls_context()`), signing keys (`.sign(bytes)`) — all can subclass `core:protected/hash` for the storage layer and add the specific operations that use the value without exposing it.

The name `hash` reflects the general shape (multi-key container of protected values). Subclasses that hold a single value — like Password — are "a `protected/hash` with one key," and that convention is documented on the subclass rather than requiring a separate single-value primitive.

## Relationship to the vault

The [vault](tag:vault) is the underlying protected-memory primitive — libsodium-backed `sodium_malloc`'d regions with guard pages, `PROT_NONE` by default, operation-oriented gateway. It's an engine-internal Lua module, not a Caspian class. `core:protected/hash` is at a higher layer: it uses vault-shaped storage internally (or equivalent mechanism), but presents a **key/value hash surface** with a different access model — the vault's operation-oriented gateway (`.verify_password`, `.sign`, `.erase`) is per-operation and specific; `protected/hash`'s access model is trusted-file-only reads.

Both live under `core:protected/`. The vault is a lower-level primitive; `protected/hash` is the higher-level base class most Caspian code will interact with (directly or via Password / `core:auth/api` / etc.).

## Testing

- **Write then read raises** — `$hsh = %('core:protected/hash').new; $hsh['k'] = 'v'; $hsh['k']` raises.
- **Overwrite allowed** — `$hsh['k'] = 'v1'; $hsh['k'] = 'v2'` does not raise; the old value is zeroed.
- **Delete allowed** — `$hsh.delete('k')` does not raise; the value is zeroed.
- **`.keys` raises** — `$hsh.keys` raises; no key enumeration from Caspian.
- **`.has?` raises** — `$hsh.has?('k')` raises.
- **`.size` raises** — `$hsh.size` raises.
- **Iteration raises** — `$hsh.each_key`, `$hsh.each` both raise.
- **Equality raises** — `$hsh.equals?($other)` raises.
- **String interpolation raises** — `"got: #{$hsh}"` raises when the interpolation attempts to stringify `$hsh`.
- **`.to_string` raises** — direct call raises.
- **`.to_json` raises** — direct call raises.
- **Nested value accepted** — `$hsh['config'] = {retry: 3}` does not raise; subsequent read of `$hsh['config']` still raises (nested structure lives in protected memory but read is forbidden).
- **File load into protected memory** — `%('core:protected/hash').read('creds.json')` returns a `protected/hash`; subsequent reads on it raise per the surface rules; the JSON string never appears in Caspian memory (verified at the engine layer, not from Caspian).
- **Nested JSON accepted at base** — file with `{"a": {"b": "c"}}` loads successfully; nested structure is stored recursively in protected memory.
- **Top-level non-object JSON raises** — file with `[1, 2, 3]` or `"scalar"` at top level raises at load.
- **Zero-on-GC** — after the last Caspian reference goes out of scope, the C backing (including nested subtrees) is freed with a full zero-out (verified at the engine layer).
- **Public Lua binding lacks read** — `require("caspian.core.protected.hash")` returns a module with no `.read(handle, key)` function.
- **Trusted binding loader-check raises from disallowed file** — a Lua file not on the allow-list attempting `require("caspian.core.protected.hash_trusted")` raises.
- **Subclass inherits protection** — Password's underlying `protected/hash` cannot be inspected from Caspian even if the Password instance is captured and probed via its Caspian surface.

## Related

- [vault](tag:vault) — the lower-level protected-memory primitive `core:protected/hash` builds on (engine-internal Lua module).
- [`core:protected/hash/http`](http) — the HTTP-scoped subclass; flat scalars, tchar keys, HTTP-sanitary values.
- [Password](../password) — a subclass with one conventional key plus password-specific methods.
- [process-security](../process-security) — process-level hardening (`mlockall`, `PR_SET_DUMPABLE`, Yama) that complements the per-secret defenses `core:protected/hash` applies.
