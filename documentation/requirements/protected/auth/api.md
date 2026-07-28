# `core:auth/api`

<span class="tag">auth-api</span>

~~~vibecode
{"vibecode": {
	"doc": "requirements_protected_auth_api",
	"role": "spec for `core:auth/api` — the class users construct to authenticate outbound API calls to third-party services. Bundles a credential (a `core:protected/hash/http`) with a policy (allowed_headers, allowed_domains) and a request factory. Primary API is `$auth.request(url)` which returns an HTTP request pre-configured with the auth's policy; the request's `.auth_headers` slot accepts template strings like `\"Bearer {field:token}\"`. Three placeholder forms are recognized: `{field:NAME}` (credential-hash lookup), `{lb}` (literal `{`), `{rb}` (literal `}`); the `field:` prefix reserves namespace for future placeholder types. Composition happens at send time inside a purpose-built C binding — the composed plaintext credential never exists as a Lua string, never in Caspian-visible memory.",
	"status": "spec — `.request(url)`, `.auth_headers` templates (string or array of strings; array elements emit one header line each on the wire), placeholder syntax (`{field:NAME}` / `{lb}` / `{rb}`), send-time composition mechanics, and cross-slot uniqueness (no header key in both `.auth_headers` and `.headers`, case-insensitive, value shape irrelevant) all settled; individual policy-field getters/setters (`.allowed_headers=`, `.allowed_domains=`, `.secret=`) pending their own section",
	"audience": "Caspian developers constructing outbound-API-authentication objects; SDK authors writing service-specific classes that consume them; engine implementers writing the trusted HTTP-transport C binding"
}}
~~~

`core:auth/api` is the class users construct to authenticate **outbound** API calls to third-party services — Stripe, AWS, GitHub, an internal microservice, whatever an SDK is talking to. It bundles a credential together with the policy that governs how that credential can be used: which HTTP headers it may inject, which URLs it's valid against. The credential itself lives in protected memory and is never readable from Caspian code; the policy fields are readable so callers can inspect what authority they're handing to a downstream SDK.

The typical pattern: the user constructs a fully-formed `$auth`, hands it to a service-specific SDK, and the SDK uses it internally when it makes requests. The SDK never touches the credential — the HTTP transport does that at request-composition time, from inside the trusted engine layer.

## Constructing an HTTP request

The primary API surface. From a fully-formed `$auth`, get back an HTTP request pre-configured with the auth's policy:

~~~caspian
$request = $auth.request 'https://api.stripe.com/v1/customers'
~~~

Returns an HTTP request object (the request class itself is spec'd elsewhere). The request carries a reference to `$auth` and inherits its policy: the target URL is validated against `$auth.allowed_domains` at `.request()` time, and the request's `.auth_headers` slot is scoped to `$auth.allowed_headers`.

A URL whose host isn't in `$auth.allowed_domains` raises immediately at `.request()`. This is the primary defense against a compromised SDK exfiltrating credentials to an attacker-controlled URL — the auth simply won't hand out a request pointed anywhere its owner didn't authorize.

## The `.auth_headers` slot

Every request handed out by `$auth.request(url)` carries an `.auth_headers` slot — a hash-like sub-object scoped specifically for authentication headers. It's separate from the request's general `.headers` slot (regular headers like `Content-Type`, `Accept`, `User-Agent` go there).

Set an auth header by writing a template to it. Values are template strings, or arrays of template strings for multi-value headers:

~~~caspian
$request.auth_headers['Authorization'] = "Bearer {field:token}"
$request.auth_headers['X-Signature']   = "id:{field:id}; sig:{field:secret}"
$request.auth_headers['X-Custom']      = ["{field:a}", "{field:b}"]
~~~

- **Single string** = one header line on the wire.
- **Array of strings** = one header line per element. On the wire, `["a", "b"]` produces two separate `X-Custom: a` / `X-Custom: b` lines. This is safer as a default than comma-joining (which is legal per RFC 9110 § 5.3 for combining-safe fields but requires per-header knowledge). The regular `.headers` slot on the request has the same shape.
- **Empty array `[]` raises at set time** — almost always a bug. To remove a header use `.delete(key)`.
- Placeholders in `{curly_braces}` are typed; the `field:NAME` form pulls a value from `$auth`'s credential container (a [`core:protected/hash/http`](tag:protected-hash-http)).
- The composed header is built at **send time**, inside the trusted HTTP transport — the plaintext credential never appears in Caspian-visible memory. See [§ Send-time composition](#send-time-composition) below.
- All set-time checks apply element-wise when the value is an array.

### Placeholder syntax

Three placeholder forms are recognized:

| Form | Meaning |
|---|---|
| `{field:NAME}` | Substituted at send time with the value at key `NAME` in `$auth`'s credential hash. |
| `{lb}` | Literal `{` in the composed output. |
| `{rb}` | Literal `}` in the composed output. |

Any other `{...}` content — including bare `{NAME}` without a `field:` prefix — raises at set time as an unknown placeholder. Forgotten prefixes and typos fail loud rather than silently passing through composition.

The `field:` prefix exists to reserve namespace for future placeholder types (e.g., `{env:VAR}`, `{now:iso8601}`, `{uuid}`) without breaking existing templates. Only `{field:...}` is recognized today; adding new prefix families is a spec change, not a breaking one.

### Set-time validation

Four checks run at the `.auth_headers[key] = template` call. If any fails, the set raises and `.auth_headers[key]` is unchanged.

1. **Key must be in `$auth.allowed_headers`.** If the auth doesn't grant this header name, the set raises. Primary scope check — an SDK holding an `$auth` can't inject headers outside its declared scope.
2. **Key must be HTTP `tchar`-set.** Belt-and-suspenders: even if `$auth.allowed_headers` was constructed with a malformed key, the set raises here. Catches a mis-constructed auth object at the last moment before a bad header would go out. Same character rule as [`core:protected/hash/http`](tag:protected-hash-http)'s key validation.
3. **Template placeholders must be recognized forms.** A single parse pass walks the template and matches every `{...}` run against the three forms listed above. Unknown syntax raises with `` unknown placeholder `{sekret}` — did you mean `{field:sekret}` for a credential substitution, or `{lb}sekret{rb}` for a literal? ``. For `{field:NAME}` specifically, the parser also checks that `NAME` exists as a key in `$auth`'s credential hash (via the trusted-Lua binding); a missing key raises `` template placeholder `{field:sekret}` does not match any key in $auth's credential hash — expected one of: `id`, `secret` ``.
4. **Template literal bytes must be HTTP-sanitary.** The non-placeholder portion of the template is checked byte-by-byte against the allow-list (VCHAR 0x21-0x7E + SP 0x20 + HTAB 0x09 — same rule as `core:protected/hash/http` value validation). Bad bytes raise: `` template literal contains prohibited byte 0x0D (CR) at position 12 — HTTP header injection vector ``.

### Validation, not sanitization

The auth/api layer never modifies template values silently. If a template contains bad bytes, the layer raises. It does not strip, escape, percent-encode, or otherwise repair the input. The developer's responsibility is to write valid templates; the system's job is to catch violations early and loudly, not to fix them.

### No cross-slot duplicates

A header key present in `.auth_headers` cannot also be present in `.headers`, and vice versa. On collision, the write raises:

~~~
header `Authorization` is already set in .headers; a request can't have `Authorization` in both .auth_headers and .headers
~~~

The check is bidirectional (writing to either slot inspects the other) and case-insensitive (`.headers['authorization']` collides with `.auth_headers['Authorization']`).

Two reasons: HTTP request headers like `Authorization`, `Content-Type`, `Cookie`, `Host` are singleton in practice — two same-named headers produce ambiguous transport behavior (some backends concatenate, some pick one, some reject). More importantly, allowing a cross-slot duplicate would let a developer bypass `$auth.allowed_headers` by writing a raw credential value into `.headers` under a name the auth object wouldn't have permitted. Fail-loud on collision closes both problems.

Overwrite within a single slot stays as ordinary hash semantics — writing to `.auth_headers['Authorization']` twice just rotates the template, not a competing header.

## Send-time composition

When `$request` fires, the auth-header composition happens inside the trusted HTTP transport (C code, not Lua strings). This is the mechanism that keeps the composed plaintext credential out of Caspian-visible — and out of Lua-visible — memory.

### The layers involved

Lua reaches HTTPS through two bundled libraries: **luasocket** (TCP) and **luasec** (TLS wrapper around OpenSSL). The trusted engine Lua orchestrates the outgoing request; Caspian never touches any of this directly.

### Step by step

1. **Trusted Lua sets up the connection.** `socket.tcp()` opens the raw TCP; `ssl.wrap(sock, tls_params)` from luasec wraps it in a TLS session (handshake, cert validation). Result: an SSL socket object.

2. **Trusted Lua writes the request line and non-auth headers the ordinary way:**

	~~~lua
	sock:send("GET /path HTTP/1.1\r\n")
	sock:send("Host: example.com\r\n")
	sock:send("Content-Type: application/json\r\n")
	~~~

	These are plain Lua strings — no secrets, safe to log.

3. **For each `.auth_headers` template (or each element of an array template), trusted Lua calls a purpose-built C binding** — something like `send_auth_header(ssl_ctx, template_lua_string, auth_hash_userdata)`. That C function:

	- `sodium_malloc`s a protected buffer.
	- Copies the template's literal bytes from the Lua string into the buffer.
	- For each recognized placeholder: `{field:NAME}` reads credential bytes directly from the vault-backed store (via the trusted-Lua binding on the protected hash) C-to-C into the buffer, no intermediate Lua string; `{lb}` / `{rb}` write the literal `{` / `}` byte.
	- Calls OpenSSL's `SSL_write(ssl_ctx, buffer, length)` on the buffer.
	- `sodium_memzero`s the buffer and `sodium_free`s it.

	Array-valued templates loop this call once per element — one header line per array element, each composed and transmitted through its own protected buffer.

4. **OpenSSL** takes the buffer, encrypts under the negotiated TLS session key, writes ciphertext to the underlying TCP socket.

5. **Trusted Lua finishes the request** — `sock:send("\r\n")` header terminator, `sock:send(body)` body.

### Where plaintext credential bytes exist at each layer

| Layer | Plaintext present? |
|---|---|
| Caspian code | Never — credential is in write-only protected hash |
| Trusted Lua stack | Never — trusted binding returns a userdata handle, not raw bytes into a Lua string |
| `send_auth_header` C function | Yes — briefly, in a `sodium_malloc`'d protected buffer |
| OpenSSL encrypt path | Yes — briefly, in OpenSSL's internal buffer during `SSL_write` |
| TCP socket / wire | Only as ciphertext (TLS) |

The plaintext credential exists as bytes ONLY inside the `sodium_malloc`'d buffer for the duration of one `SSL_write` call, then is zeroed. No Lua string ever holds it. No Caspian value ever references it. The Lua `debug` library can't see it because it's a C buffer, not a Lua-heap value.

### What NOT to do

The naive approach — compose the whole HTTP request into a single Lua string:

~~~lua
local full = "GET /path HTTP/1.1\r\n" ..
	"Host: example.com\r\n" ..
	"Authorization: Bearer " .. read_secret() .. "\r\n\r\n"
sock:send(full)
~~~

The `full` string lives on the Lua heap, is GC-visible, and is inspectable via `debug.*` from any Lua code with debug access. All the protected-memory work upstream is wasted the moment that concatenation happens.

The design premise: **the composed auth-header bytes must never exist as a Lua string.** Everything else about the request can be Lua strings; the auth-header line specifically has to be composed and transmitted from inside a single C function that owns its buffer end-to-end.

### Send-time re-validation

If the credential hash was modified between set time and send time (a key was deleted, the auth was rotated), send-time composition can find that a placeholder no longer resolves. The specialized C binding raises with a specific error: `` template placeholder `{secret}` was validated at set time but is missing at send time; credential hash was likely modified between construction and send ``.

## Testing

- **`.request(url)` returns a request object** whose policy reflects `$auth`.
- **Off-domain URL raises at `.request()`** — `$auth.request 'https://evil.example.com/api'` raises when `evil.example.com` isn't in `$auth.allowed_domains`.
- **Allowed header set succeeds** — `$request.auth_headers['Authorization'] = "Bearer {field:token}"` when `Authorization` is in `$auth.allowed_headers` and `token` is a key in `$auth`'s credential hash.
- **Non-allowed header raises** — `$request.auth_headers['X-Random'] = "..."` raises with `` header `X-Random` is not in $auth's allowed_headers list ``.
- **Malformed key raises** — even if the developer somehow lists `"bad key"` in `$auth.allowed_headers`, `.auth_headers['bad key']` raises the tchar check.
- **Missing credential key raises** — `$request.auth_headers['Authorization'] = "Bearer {field:sekret}"` raises when `$auth`'s credential hash doesn't contain `sekret`.
- **Bare `{name}` (no prefix) raises** — `$request.auth_headers['Authorization'] = "Bearer {token}"` raises with the "did you mean `{field:token}` or `{lb}token{rb}`?" message.
- **Unknown prefix raises** — `$request.auth_headers['Authorization'] = "Bearer {env:TOKEN}"` raises as unknown placeholder (only `field:`, `lb`, `rb` are recognized).
- **Literal brace passes** — `$request.auth_headers['X-Custom'] = "{lb}{field:token}{rb}"` accepted; composes at send time to `"{VALUE}"` where `VALUE` is the credential bytes.
- **Bad literal byte raises** — `$request.auth_headers['Authorization'] = "Bearer \r\ninjection"` raises with the injection-vector error message.
- **No silent modification** — a template with bad literal bytes is rejected outright; verify no strip, escape, or normalize happens on the template.
- **Valid template composes correctly at send time** — `"Bearer {field:token}"` with the credential hash carrying `token = 'sk_abc'` produces `"Bearer sk_abc"` as the outgoing HTTP header (verified at the transport layer, not from Caspian).
- **Plaintext credential never on Lua heap** — trace the send path with a Lua debug hook; assert no Lua string containing the credential bytes is ever created (verified in engine implementation tests).
- **Placeholder missing at send time raises** — set a template with `{field:secret}`, delete `secret` from the credential hash, send the request: raises with the send-time re-validation error message.
- **Cross-slot collision raises** — `$request.headers['Authorization'] = "raw value"` then `$request.auth_headers['Authorization'] = "Bearer {field:token}"` raises on the second call with the cross-slot collision message. Also true in reverse (set `.auth_headers` first, then `.headers`).
- **Cross-slot collision is case-insensitive** — `$request.headers['authorization'] = "..."` then `$request.auth_headers['Authorization'] = "..."` raises (differs only in case).
- **Overwrite within a slot allowed** — `$request.auth_headers['Authorization'] = "Bearer {field:token}"` then `$request.auth_headers['Authorization'] = "Bearer {field:new_token}"` does not raise; second write replaces the template.
- **Array value accepted** — `$request.auth_headers['X-Custom'] = ["{field:a}", "{field:b}"]` accepted when each element passes the four set-time checks; produces two `X-Custom:` header lines on the wire.
- **Array element with bad byte raises** — `$request.auth_headers['X-Custom'] = ["ok value", "bad \r\n injection"]` raises on the second element with the injection-vector error message (checks apply element-wise).
- **Empty array raises** — `$request.auth_headers['X-Custom'] = []` raises with "empty array; to remove a header use `.delete(key)`."
- **Array-valued cross-slot collision raises** — `$request.headers['X-Custom'] = ['a', 'b']` then `$request.auth_headers['X-Custom'] = "{field:val}"` raises regardless of value shape; collision is by key alone.

## Related

- [`core:protected/hash/http`](tag:protected-hash-http) — the credential container that `$auth` composes; validates keys and values at storage time so the send-time layer can trust the bytes.
- [vault](tag:vault) — the underlying protected-memory primitive that stores credential bytes.
- [`core:protected/memory`](tag:protected-memory) — the `.run do ... end` block form for reading credentials from files or env vars into protected memory during `$auth` construction.
