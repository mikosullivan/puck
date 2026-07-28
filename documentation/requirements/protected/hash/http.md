# `core:protected/hash/http`

<span class="tag">protected-hash-http</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected_memory_hash_http",
	"role": "spec for `core:protected/hash/http` — subclass of `core:protected/hash` scoped to HTTP-safe credential storage. Adds three constraints on top of the base: (1) flat-only — nested hashes and arrays raise at set; (2) keys must be nonempty and match the RFC 9110 `tchar` field-name character set (ASCII alphanumerics plus `!#$%&'*+-.^_`|~`); (3) values must be strings whose bytes are all in the HTTP-sanitary set (VCHAR 0x21-0x7E plus SP 0x20 plus HTAB 0x09). All validation is allow-list based; the allow-list IS the spec, no parallel deny-list needed. Rejection is immediate at the `[]=` call, not deferred to load or header composition. Same rules apply on file load via `.read(path)`. Used by `core:auth/api` for outbound HTTP credential storage — the tight validation guarantees that credential bytes cannot inject rogue headers when substituted into HTTP header templates.",
	"status": "spec — inherited machinery, added constraints, and fail-fast posture all settled",
	"audience": "Caspian developers constructing outbound API auth credentials; `core:auth/api` implementers; anyone auditing the HTTP-injection defense line"
}}
~~~

`core:protected/hash/http` is a subclass of [`core:protected/hash`](.) scoped to HTTP-safe credential storage. Every value it holds is guaranteed to be a byte sequence that can be substituted into an HTTP header value without opening a header-injection vector — no CR, no LF, no NUL, no other bytes an HTTP transport might refuse.

It's the credential container used by [`core:auth/api`](../auth/api). By pushing validation down to the container's write path, invalid credentials fail at load time — not at request-composition time, when the developer is deep in unrelated code and the error message would point at the transport rather than at the bad byte.

Accessed via `%('core:protected/hash/http')`.

## What it inherits

Everything from the base class, unchanged:

- **Write-only Caspian surface.** Any read attempt raises. See [`core:protected/hash` § Caspian-side surface](.#caspian-side-surface).
- **Trusted-Lua-only read path.** Engine-internal consumers (the HTTP transport's auth-injection code) reach values via `require("caspian.core.protected.hash_trusted")`. See [`core:protected/hash` § Trusted-path Lua binding](.#trusted-path-lua-binding).
- **C-allocated protected memory.** `mlock`, `madvise(MADV_DONTDUMP)`, `explicit_bzero` on delete / overwrite / GC. See [`core:protected/hash` § Storage layer (native-side)](.#storage-layer-native-side).

## What it adds

Three constraints, enforced at set time.

### Flat only

Values must be scalar. Nested hashes and nested arrays raise at set:

~~~caspian
$hsh = %('core:protected/hash/http').new

$hsh['token']  = 'sk_live_abc123...'     # OK
$hsh['config'] = {retry: 3}              # RAISES — nested hash not allowed
$hsh['scopes'] = ['read', 'write']       # RAISES — nested array not allowed
~~~

### Key validation

Keys must be nonempty and every byte must be in the HTTP `tchar` character set from RFC 9110 § 5.6.2:

- ASCII letters `A-Z` and `a-z`
- ASCII digits `0-9`
- These 15 specials: `!` `#` `$` `%` `&` `'` `*` `+` `-` `.` `^` `_` `` ` `` `|` `~`

Any other byte — space, tab, colon, control chars, high-bit bytes, or an empty string — raises at set. The rule is stated as an allow-list; the implementation walks each byte and raises on the first byte not in the allowed set.

~~~caspian
$hsh['token']            = 'x'    # OK
$hsh['x-custom-header']  = 'x'    # OK — hyphen is tchar
$hsh['bearer_secret']    = 'x'    # OK — underscore is tchar
$hsh['auth token']       = 'x'    # RAISES — space not in tchar
$hsh['auth:token']       = 'x'    # RAISES — colon not in tchar
$hsh['']                 = 'x'    # RAISES — empty key
~~~

### Value validation

Values must be strings, and every byte of the string must be in the HTTP-sanitary character set:

- HTAB `0x09`
- SP `0x20`
- VCHAR `0x21-0x7E` (printable ASCII)

Non-string values (numbers, booleans, null, hashes, arrays) raise; strings containing any other byte (CR, LF, NUL, other C0 controls, DEL, or high-bit / obs-text bytes) raise. Same posture as key validation — the allow-list IS the spec.

~~~caspian
$hsh['token']   = 'sk_live_abc123...'          # OK
$hsh['token']   = 'Bearer abc def'             # OK — space is allowed
$hsh['token']   = "sk_live\r\nX-Evil: pwned"   # RAISES — CR/LF
$hsh['token']   = "sk_live_\0abc"              # RAISES — NUL
$hsh['token']   = "sk_live_\xC3\xA9"           # RAISES — high-bit (UTF-8 é)
$hsh['count']   = 42                           # RAISES — non-string value
$hsh['enabled'] = true                         # RAISES — non-string value
~~~

For credentials that legitimately need non-ASCII content (rare in practice), encode them into an ASCII-safe form at the source — base64, hex, percent-encoding — before storing.

## Belt-and-suspenders check for injection bytes

Before the general allow-list walk, an explicit early check runs for the highest-risk injection bytes: CR `0x0D`, LF `0x0A`, and NUL `0x00`. Bytes rejected by this check produce a targeted error message that names the specific attack pattern:

~~~
value at key `token` contains prohibited byte 0x0D (CR) at position 24 — HTTP header injection vector
~~~

Bytes rejected by the general allow-list walk (high-bit obs-text, other control chars) produce a generic message:

~~~
value at key `token` contains prohibited byte 0xC3 at position 12 — outside HTTP-sanitary allow-list (VCHAR + SP + HTAB)
~~~

The same set of bytes fails either way. The early check exists solely to produce a better error message for the most common attack pattern; it's not an additional deny-list to maintain in parallel with the allow-list.

## Fail immediately

Rejection happens at the `[]=` call, not later. A bad byte written into a credential surfaces at the exact line that wrote it — not at request-composition time when the developer is deep in unrelated code, and not at HTTP transport time when the error message would point at the transport rather than at the offending byte.

Same holds for `.read(path)`: file-load validation applies the same rules to every top-level key/value pair. A JSON file with a nested value, a bad key, or a bad value byte raises at the `.read` call with a message that identifies the offending path.

## File loading

`%('core:protected/hash/http').read($file)` accepts JSON files whose contents pass the same rules that the in-memory set path enforces:

~~~caspian
$hsh = %('core:protected/hash/http').read('/etc/caspian/stripe-creds.json')
~~~

- **Top level must be a JSON object** (same as base).
- **All values must be JSON strings** — numbers, booleans, null, nested objects, and nested arrays raise at load.
- **All keys must be tchar-set** — as with in-memory set, empty or malformed keys raise at load.
- **All value bytes must be HTTP-sanitary** — CR, LF, NUL, or obs-text in any value raises at load.
- **Parse is atomic** — a file where any key or value fails validation produces no partial `hash/http`; the whole `.read` call raises.

## Testing

- **Base surface inherited** — write-then-read raises; iteration raises; serialization raises; `.delete` and overwrite succeed. See [`core:protected/hash` § Testing](.#testing).
- **Nested hash value raises** — `$hsh['k'] = {a: 1}` raises with "nested hash not allowed."
- **Nested array value raises** — `$hsh['k'] = [1, 2]` raises with "nested array not allowed."
- **Non-string scalar raises** — `$hsh['k'] = 42`, `$hsh['k'] = true`, `$hsh['k'] = null` all raise with "value must be a string."
- **Empty key raises** — `$hsh[''] = 'x'` raises.
- **Key with space raises** — `$hsh['a b'] = 'x'` raises.
- **Key with colon raises** — `$hsh['a:b'] = 'x'` raises.
- **Key with control byte raises** — `$hsh["a\tb"] = 'x'` raises.
- **Key with high-bit byte raises** — `$hsh["a\xC3\xA9b"] = 'x'` raises.
- **Value with CR raises** — `$hsh['k'] = "x\r"` raises with the injection-vector error message.
- **Value with LF raises** — `$hsh['k'] = "x\n"` raises with the injection-vector error message.
- **Value with NUL raises** — `$hsh['k'] = "x\0"` raises with the injection-vector error message.
- **Value with other C0 raises** — `$hsh['k'] = "x\x01"` raises with the generic allow-list error message.
- **Value with DEL raises** — `$hsh['k'] = "x\x7F"` raises with the generic allow-list error message.
- **Value with obs-text raises** — `$hsh['k'] = "x\xC3\xA9"` raises with the generic allow-list error message.
- **Value with SP accepted** — `$hsh['k'] = 'a b c'` does not raise.
- **Value with HTAB accepted** — `$hsh['k'] = "a\tb"` does not raise.
- **Value with all VCHAR accepted** — a value containing every byte from `0x21` through `0x7E` does not raise.
- **File-load nested value raises** — `.read` on a file with `{"config": {"retry": 3}}` raises at load.
- **File-load non-string value raises** — file with `{"port": 5432}` raises at load with "value at key `port` must be a JSON string."
- **File-load bad-key raises** — file with `{"auth token": "x"}` raises at load.
- **File-load bad-value byte raises** — file with `{"token": "x\r\ny"}` raises at load with the injection-vector error message.
- **File-load atomic on mixed validity** — a file with one bad value and several good ones produces no partial handle; the whole `.read` call raises.
- **Subclass identity preserved** — the returned handle is a `core:protected/hash/http`, not a plain `core:protected/hash`, for `.class` / `.is_a?` checks.

## Related

- [`core:protected/hash`](.) — the base class; all storage / safety machinery lives there.
- [`core:auth/api`](../auth/api) — the primary consumer; uses this class to hold API credentials that get substituted into HTTP header templates.
- [vault](tag:vault) — the lower-level protected-memory primitive `core:protected/hash` builds on (engine-internal Lua module, not a Caspian class).
