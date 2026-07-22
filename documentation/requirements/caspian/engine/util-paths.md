# `%engine.util_paths`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_util_paths",
	"role": "spec for %engine.util_paths — the curated hash of canonical absolute paths for non-POSIX system utilities (zip, unzip, openssl, curl, git, luarocks, systemctl, etc.). Backs %fs.util's lookup for utilities that confstr(_CS_PATH) doesn't cover. Ships with initial contents loaded from util-paths.json in the global-methods spec directory; user-mutable at runtime so programs and operators can pin or override paths per-utility without a config file. Has no global form — %util_paths is not defined; only %engine.util_paths reaches this hash."
}}
~~~

`%engine.util_paths` holds the curated table of canonical absolute paths for **non-POSIX system utilities** that `%fs.util` should be able to resolve without consulting `$PATH`. POSIX-blessed utilities (`tar`, `gzip`, `sh`, `sed`, `awk`, `find`, `sort`, and the other ≈160 commands in IEEE 1003.1-2017 Volume 3) are NOT in this hash — they're resolved at runtime via `confstr(_CS_PATH)`. This hash is only for the industry-standard-but-not-POSIX tail: `zip`, `unzip`, `openssl`, `curl`, `git`, `luarocks`, `systemctl`, and similar.

This is one of the slots that has no global form: there's no `%util_paths` shortcut. Code that reaches this table names it explicitly as `%engine.util_paths`.

## Shape

The hash is keyed by program name (`String`) → per-platform sub-hash (`Hash`). Each sub-hash is keyed by platform name (`String`, matching [`%engine.platform.os`](platform) values) → array of absolute paths (`Array` of `String`) in probe order:

~~~caspian
%engine.util_paths['zip']
# => { 'linux': ['/usr/bin/zip', '/usr/local/bin/zip'] }

%engine.util_paths['zip']['linux']
# => ['/usr/bin/zip', '/usr/local/bin/zip']
~~~

`%fs.util('zip')` walks the current platform's array, taking the first path that exists and is executable.

## Initial contents

At engine startup the hash is populated from [`util-paths.json`](../global-methods/util-paths.json), the shipped table in the global-methods spec directory. That file is the canonical initial data — the engine loads it once at startup, then hands the resulting hash to user code as `%engine.util_paths`.

## Mutation

The hash is **mutable by user code**. User programs and operators can add, replace, or delete entries:

~~~caspian
# Add a new utility.
%engine.util_paths['nmap'] = { 'linux': ['/usr/bin/nmap'] }

# Override a probe list to pin a specific binary.
%engine.util_paths['openssl']['linux'] = ['/opt/hardened/bin/openssl']

# Prepend an alternate path.
%engine.util_paths['zip']['linux'].unshift '/home/me/local-zip/bin/zip'

# Remove an entry entirely — subsequent %fs.util('rsync') raises.
%engine.util_paths.delete 'rsync'
~~~

Mutations take effect immediately for subsequent `%fs.util` calls. No config-file schema, no reload — the runtime hash IS the source of truth.

**User-only.** Consistent with the rest of `%engine`, mutations from non-user code raise. Non-user code that needs a specific binary path either accepts one passed by user code or relies on `%fs.util`'s POSIX-based lookup for standard utilities.

## Relationship to `%fs.util`

`%fs.util('name')` resolves in this order:

1. **POSIX-blessed** — walk `confstr(_CS_PATH)`, take first executable match. Handles ~160 utilities.
2. **Curated non-POSIX** — walk `%engine.util_paths['name']['linux']` (or whatever `%engine.platform.os` says), take first executable match.
3. **Neither** — raise.

Since `%engine.util_paths` is mutable, the "configured override" case is just a mutation of the hash — there's no separate override layer. To pin `%fs.util('openssl')` to a specific binary, mutate `%engine.util_paths['openssl']`.

## Testing

- **`%engine.util_paths` returns a hash** — keyed by program name.
- **Each entry is a hash keyed by platform name** — `linux`, `darwin`, etc., matching `%engine.platform.os` values.
- **Each platform value is an array of absolute paths** — probe order preserved from the shipped JSON.
- **Initial contents match the shipped table** — `%engine.util_paths['zip']['linux']` at engine startup equals the array in `util-paths.json`.
- **User can add a new utility** — `%engine.util_paths['foo'] = { 'linux': ['/opt/foo'] }` succeeds and `%fs.util('foo')` then finds it (given `/opt/foo` is executable).
- **User can replace a probe list** — `%engine.util_paths['zip']['linux'] = ['/opt/zip']` succeeds; subsequent `%fs.util('zip')` returns `/opt/zip` (or raises if not executable).
- **User can prepend to a probe list** — `.unshift` on the array adds a candidate ahead of the built-ins.
- **User can delete an entry** — `%engine.util_paths.delete 'zip'` removes it; subsequent `%fs.util('zip')` raises.
- **Mutations take effect immediately** — the next `%fs.util` call reflects the change; no reload needed.
- **`%engine.util_paths` has no global shortcut** — `%util_paths` (bare) is not defined; only `%engine.util_paths` reaches this hash.
- **Non-user role reading `%engine.util_paths` raises** — the blanket `%engine` gate applies.
- **Non-user role mutating `%engine.util_paths` raises** — the same gate.
- **`%engine.util_paths` does NOT include POSIX utilities** — `%engine.util_paths['tar']` is absent; `tar` is resolved via `confstr(_CS_PATH)` inside `%fs.util`.
- **`%fs.util('name')` consults this hash after the POSIX lookup fails** — verified by looking up a non-POSIX utility like `zip` or `openssl`.

## Related

- [util-paths.json](../global-methods/util-paths.json) — the shipped initial data.
- [`%fs.util`](../global-methods/fs-additions#util) — the lookup API this hash backs.
- [`%engine.platform`](platform) — supplies the `os` key that selects which platform array to walk.
