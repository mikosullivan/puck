# `%random`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_random",
	"role": "spec for %random — random-value primitives (UUID, number, string). All draw from libsodium → OS CSPRNG; cryptographically strong by default.",
	"source": "libsodium → OS CSPRNG"
}}
~~~

**Default-granted across role boundaries:** yes.  
**Shortcut:** `%random`.

`%random` is the namespace for random-value helpers. Every method here draws from libsodium, which uses the operating system's cryptographically-strong random number generator. There is no separate "fast but weaker" surface — `%random` is the random surface.

## `%random.uuid`

Returns a UUID v4 string. Each UUID is freshly generated per call — no caching, no PRNG state. Engine implementation guidance (one-C-function-per-call, hex lookup table) lives in the UUID-generation spec when it migrates.

## `%random.number(min, max, step: 1)`

Returns a random number in `[min, max]`, both ends inclusive, picked uniformly via libsodium's unbiased range function (no modulo bias).

~~~caspian
%random.number(1, 100)              # 1..100 inclusive
%random.number(1, 6)                # roll a six-sided die
%random.number(1, 100, step: 0.1)   # one of 1.0, 1.1, ..., 100.0
%random.number(0, 10, step: 3)      # one of 0, 3, 6, 9
~~~

`min` and `max` are required. `step` defaults to `1`. Bounds can be passed in either order; if `min > max`, they're swapped before use.

The result is always `min + k * step` for some non-negative integer `k`. If `max - min` isn't an exact multiple of `step`, the reachable maximum is `min + floor((max - min) / step) * step` — `number(0, 10, step: 3)` never returns `10`.

Error: `step <= 0`.

## `%random.string(length, from: :alphanum)`

Returns a random string of `length` characters, each drawn uniformly from a pool.

~~~caspian
%random.string(5)                       # 5 chars from :alphanum
%random.string(16, from: :hex)          # 16 hex chars
%random.string(5,  alphabet: 'abcde')   # custom pool
~~~

Choose the pool with one of two mutually-exclusive keywords:

- **`from:`** — a symbol naming a predefined alphabet (see table). Defaults to `:alphanum`.
- **`alphabet:`** — a string of the exact characters to draw from. Repeats weight the character (`'aaab'` weights `a` three times).

| Symbol | Characters |
|---|---|
| `:alphanum` | `a-z A-Z 0-9` (62 chars; default) |
| `:hex` | `0-9 a-f` (lowercase) |
| `:base64` | `a-z A-Z 0-9 + /` |
| `:base64url` | `a-z A-Z 0-9 - _` (URL-safe) |
| `:digits` | `0-9` |
| `:letters` | `a-z A-Z` |
| `:lower` | `a-z` |
| `:upper` | `A-Z` |

`length` is character count, not byte count. `string(16, from: :hex)` returns a 16-character string carrying 8 bytes of entropy. For N bytes of randomness encoded as hex, ask for `N*2` characters.

Errors: `length <= 0`; unknown `from:` symbol; empty `alphabet:` string; both `from:` and `alphabet:` passed in the same call.

## Source of randomness — Lua reference engine

The Lua reference engine implements every method on `%random` via [libsodium](https://github.com/jedisct1/libsodium). libsodium does not maintain its own PRNG state for this purpose; it [reads directly from the operating system's random number generator](https://libsodium.gitbook.io/doc/generating_random_data) on every call.

On Linux that source is the kernel's `getrandom(2)` system call (with `/dev/urandom` as the equivalent device interface), which produces values from a CSPRNG seeded by the kernel's entropy pool. See [`random(7)`](https://man7.org/linux/man-pages/man7/random.7.html) for the kernel-side details.

The Linux random source is **compliant with NIST SP 800-90A and SP 800-90B** — the United States federal standards covering deterministic random bit generators and entropy sources for cryptographic use. The compliance is documented in detail by [an external technical analysis](https://www.atsec.com/sp800-90a-and-sp800-90b-compliant-linux-random-number-generator/); the practical upshot is that `%random` on the Lua reference engine running on Linux can be relied on for cryptographic purposes (keys, signing nonces, salts, etc.).

On other operating systems libsodium uses the platform-appropriate CSPRNG — BCryptGenRandom on Windows, the kernel arc4random on Darwin/BSD, etc. Each is the standard cryptographically-strong source for its platform.

Other engines (a future Python-hosted engine, a wasm-hosted engine) are free to use a different implementation of `%random` provided they meet the same requirement: cryptographically-strong, unbiased, no per-process PRNG state observable through the API.
