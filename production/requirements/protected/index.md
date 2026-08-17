# Protected memory

<span class="tag">protected</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected",
	"role": "landing page for the `core:protected/*` URL namespace and its adjacent classes. Namespace table (hash, hash/http, password, memory) — four classes Caspian developers construct via `%('core:protected/...')`. Adjacent-classes table for related pages in this folder (passkey, core:auth/api, process-security, ui). No narrative content — each class documents itself; the HTTP-intake flow lives on the vault Lua-module spec; developer-facing usage patterns live on `ui.md`; process-level OS hardening lives on `process-security.md`. The vault (engine-internal Lua module that provides protected storage under the hood) is spec'd separately at `requirements/lua/vault.md` — not a Caspian class, so not listed here.",
	"status": "spec — namespace membership settled",
	"audience": "anyone looking for a class in the `core:protected/*` namespace, or the adjacent classes that share this folder"
}}
~~~

## The `core:protected/*` namespace

| Class | Description |
|---|---|
| [`core:protected/hash`](hash/) | Write-only key/value protected-memory container. |
| [`core:protected/hash/http`](hash/http) | HTTP-scoped subclass of `hash`; flat scalars, tchar keys, HTTP-sanitary values. |
| [`core:protected/password`](password) | Password class; subclass of `hash` with argon2id hashing, constant-time `.verify`, `.hash_for_storage` for database persistence. |
| [`core:protected/memory`](memory) | Caspian-side entry point to protected-mode windows via `.run do ... end`. |

## Adjacent classes and subsystems

Not in `core:protected/*`, but living in this folder for co-location:

| Page | Description |
|---|---|
| [`core:auth/api`](auth/api) | Outbound API authentication. Composes a `core:protected/hash/http` for credentials and adds `.allowed_headers`, `.allowed_domains`, an HTTP-header-template mechanism. |
| [Passkey](passkey/) | WebAuthn / FIDO2 authentication. Two roles: server-side relying party, authenticator-side signer. Authenticator-side uses the vault to hold private keys. |
| [process-security](process-security) | OS-level hardening of the engine process (`mlockall`, `PR_SET_DUMPABLE`, Yama ptrace, encrypted-swap and no-hibernation posture). Complements the per-secret protections above. |
| [ui](ui) | Developer-facing usage patterns: `Password.new`, declaring password fields in HTTP route schemas, `core:protected/memory` explicit blocks, engine-config for process-security settings. |
