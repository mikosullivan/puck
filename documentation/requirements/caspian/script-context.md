# Script context

~~~vibecode
{"vibecode": {
	"doc": "script_context",
	"role": "catalog of what the engine passes INTO a running Caspian script via %engine. Opens with a single flat list of every standard %engine.X slot, with each slot name linking to its detailed entry below. Plus the %engine[<key>] escape hatch for arbitrary engine-passed values.",
	"audience": "Caspian developers asking 'what does the engine put in my script's hands?'",
	"scope_boundary": "what_engine_actively_binds_via_percent_engine; does_NOT_cover_sugar_apis_like_percent_net_percent_utils_percent_chain_or_predefined_classes_reachable_via_percent_puck",
	"layout": "single_glance_list_at_top_with_links_to_details_below",
	"key_concepts": ["percent_engine_is_the_only_passing_in_surface",
		"single_flat_list_with_links_to_details",
		"standard_slots_plus_bracket_access_escape_hatch",
		"user_role_only_top_level_only"]
}}
~~~

The engine binds `%engine` as the user script's gateway to host resources. This doc catalogs every standard slot on `%engine` plus the arbitrary-value escape hatch.

`%engine` is **user-role-only** and **top-level only** — only user code can reach `%engine`; nested libraries and other roles cannot. Capabilities flow down the chain by being passed as parameters, never by reaching back up to `%engine`. See [roles.md](roles.md).

Out of scope here: sugar APIs like `%net`, `%utils`, `%chain` (those wrap engine slots and are documented in their own specs), classes reachable via `%puck['...']` lookup (those are looked up, not passed in), and context-specific bindings inside blocks (`$request`, `$hash`, etc. — each documented at its feature's home).

---

<a id="at-a-glance"></a>
## All slots at a glance

> ⚠ **Only user code can access `%engine.*`.** Every slot in the table below is **user-role-only**. Nested libraries and other roles cannot reach `%engine` at all. Idiomatic code uses the [global form](#) (rightmost column) when one exists; `%engine.*` is reserved for the few capabilities where there's no global, or where user code is the only role that should ever touch the surface.

| Slot | Type | One-line purpose | Global form |
|---|---|---|---|
| [`%engine.root`](#root) | dirjail | Root filesystem dirjail | `%utils.file_system` |
| [`%engine.tmp`](#tmp) | dirjail (fresh per access) | Each access returns a new temp dirjail; auto-deletes when out of scope | `%utils.tmp` |
| [`%engine.stdin`](#streams) | stream | Standard input | `%stdin` |
| [`%engine.stdout`](#streams) | stream | Standard output | `%stdout` |
| [`%engine.stderr`](#streams) | stream | Standard error | `%stderr` |
| [`%engine.network`](#network) | object | Overall network surface | `%net` |
| [`%engine.network.http_client`](#network-http-client) | factory | Produces new HTTP client instances | `%net.http_client` (plus `%net.fetch` sugar) |
| [`%engine.network.sockets`](#network-sockets) | namespace | Raw socket constructors (`tcp`, `ssl`, `udp`) | `%net.tcp`, `%net.udp`, `%net.ssl`, `%net.tcp_listen`, `%net.udp_listen` |
| [`%engine.network.uds`](#network-uds) | namespace | Unix-domain-socket server constructor | `%utils.network.uds` |
| [`%engine.network.puck`](#network-puck) | object | The Puck interface — class lookup, registration, deletion | `%puck` (plus `%[url]` shorthand) |
| [`%engine.env`](#env) | hash-shaped | Environment-variable accessor | `%utils.env` |
| [`%engine.argv`](#argv) | array of strings | Command-line arguments | `%utils.argv` |
| [`%engine.now`](#now) | timestamp | Current timestamp | `%utils.now` |
| [`%engine.random`](#random) | namespace | `uuid`, `number`, `string` — random-data primitives | `%utils.random` |
| [`%engine.random.uuid`](#random-uuid) | method | Fresh UUID | `%utils.random.uuid` |
| [`%engine.random.number`](#random-number) | method | Random number in a given range | `%utils.random.number` |
| [`%engine.random.string`](#random-string) | method | Random string of a given length/alphabet | `%utils.random.string` |
| [`%engine.pid`](#pid) | integer | OS process ID | (TBD — none yet; `%process.pid` possible) |
| [`%engine.platform`](#platform) | namespace | Container for `os` and `architecture` | no global form |
| [`%engine.platform.os`](#platform-os) | hash | OS family, distribution, version, kernel, etc. | no global form |
| [`%engine.platform.architecture`](#platform-architecture) | string | `x86_64`, `arm64`, etc. | no global form |
| [`%engine.encryption`](#encryption) | namespace | Container for `signing` and `sha` | `%utils.encryption` |
| [`%engine.encryption.signing`](#encryption-signing) | object | Ed25519 signing and verification | `%utils.encryption.signing` |
| [`%engine.encryption.sha`](#encryption-sha) | object | SHA-family hashing primitives | `%utils.encryption.sha` |
| [`%engine[<key>]`](#bracket-access) | any | Arbitrary engine-passed values (escape hatch) | (no global form — engine-direct only) |

**The pattern.** `%engine.X` is the user-only, top-level slot — direct access to the underlying capability. Most slots also have a **global form** under `%utils`, `%net`, `%puck`, or a dedicated top-level method like `%stdout`. The global forms are reachable from any role (subject to that role having been granted the capability); `%engine.X` access is restricted to top-level user code. Where a global form is `(TBD)`, the capability hasn't been given a non-user surface yet — either because it doesn't make sense for non-user roles, or because the sugar hasn't been designed.

---

<a id="details"></a>
## Detail

<a id="root"></a>
### `%engine.root`

Root filesystem dirjail. Often encompasses the entire local system; gated by `--allow-fs`.

Caspian doesn't have a meaningful **current-working-directory** concept. Filesystem access is by explicit dirjails granted by the engine, not relative to where the script was launched. Avoids the "what cwd is this script in?" class of surprises that bite shell-pipeline-launched programs.

**Global form:** `%utils.file_system`.

<a id="tmp"></a>
### `%engine.tmp`

Each access returns a fresh temp dirjail. See **[`%utils.tmp`](global-methods/utils/#utilstmp)** for the full API (direct-access, block form, explicit close, properties).

**Separable from broader filesystem access.** `%engine.tmp` is a narrower capability than `%engine.root`: a script can be granted access to scratch space (`%utils.tmp`) without being granted access to the rest of the filesystem (`%engine.root`). The two capabilities have separate permission grants (`--allow-tmp` vs `--allow-fs`, names TBD).

**Global form:** [`%utils.tmp`](global-methods/utils/#utilstmp).

<a id="streams"></a>
### `%engine.stdin` / `%engine.stdout` / `%engine.stderr`

Standard input, output, and error streams.

**Global forms:** `%stdin`, `%stdout`, `%stderr` (top-level system methods reachable from any role with the relevant capability; see [#630](https://github.com/mikosullivan/puck/issues/630) for the `.global = true` opt-in pattern).

<a id="network"></a>
### `%engine.network`

Overall network surface. Container for the sub-namespaces below. Gated by `--allow-net` and friends; see [network/index.md](network/index.md) for the full permission model.

**Global form:** `%net`.

<a id="network-http-client"></a>
### `%engine.network.http_client`

The HTTP client capability. Backing class is [`puck.uno/http/client`](network/http/client/); you don't reach for the class directly — you go through the global form.

Standard usage (via the global, which is what developers actually write):

```caspian
$resp = %net.http_client.get('https://foo.com/api')
```

For a configured, reusable client:

```caspian
$client = %net.http_client.new(
    timeout: 30,
    headers: {'User-Agent': 'my-script/1.0'}
)
$resp = $client.get('https://foo.com/api')
```

Each `.new()` returns an independent instance with its own configuration. `%net.fetch` is the further-shortened form for a one-shot default request.

`%engine.network.http_client` exists as the underlying user-only slot but is rarely used directly — examples and idiomatic code go through `%net.http_client` (or `%net.fetch`).

**Global form:** `%net.http_client` (plus `%net.fetch` sugar for one-shot requests).

<a id="network-sockets"></a>
### `%engine.network.sockets`

Raw socket constructors: `tcp`, `ssl`, `udp`. The foundational layer that the HTTP client and other protocol clients are built on. Most user code doesn't reach here directly.

**Global forms:** `%net.tcp`, `%net.udp`, `%net.ssl`, `%net.tcp_listen`, `%net.udp_listen` — each a sugar form for the underlying socket constructor.

<a id="network-uds"></a>
### `%engine.network.uds`

Unix-domain-socket server constructor (`%engine.network.uds.new`). Used to build local-only HTTP servers; the foundation of [`$uds.share`](network/uds/shared-hash.md) and [`$uds.mikobase`](network/uds/mikobase.md).

**Global form:** `%utils.network.uds` — same constructor surface, reachable from any role.

<a id="network-puck"></a>
### `%engine.network.puck`

The Puck interface — class lookup by URL, class registration, class deletion. Lives under `%engine.network` because remote-class lookup is one of the things resolved through the network fetcher chain. Working surface:

| Operation | Form |
|---|---|
| Look up a class by URL | `%engine.network.puck['foo.com/bar']` |
| Register a class under a URL | `%engine.network.puck['foo.com/bar'] = $class` |
| Delete a registration | `%engine.network.puck.delete('foo.com/bar')` |

`%puck` is the role-agnostic shorthand that points at the same underlying registry — any role can do `%puck['url']` to look up a class, but writes are gated by [creator-based ownership](puck/lookup.md) (the role that first assigned an entry owns it; other roles can't overwrite it). `%engine.network.puck` is the user's named access to the same surface; `%puck` is the universal handle reachable from any role.

The `%[url]` / `%puck[url]` shortform is sugar over `%puck['url']`.

**Global form:** `%puck` (plus `%[url]` shorthand).

<a id="env"></a>
### `%engine.env`

Environment-variable accessor (hash-shaped). Read environment variables that were set when the script was launched.

**Global form:** `%utils.env`.

<a id="argv"></a>
### `%engine.argv`

Command-line arguments after the script name, as an array of strings.

```caspian
$args = %utils.argv     # standard idiom — bind to a regular variable
```

`$args` is just a variable name the script chooses; it isn't an engine-provided global. Bind to whatever name reads cleanly in your script.

**Global form:** `%utils.argv`.

<a id="now"></a>
### `%engine.now`

Current timestamp from the engine-controlled clock. Engine-controlled rather than directly from the OS so that test harnesses can inject a fixed clock for deterministic runs.

**Global form:** `%utils.now`.

<a id="random"></a>
### `%engine.random`

Namespace for random-data primitives. Backed by the OS entropy source (e.g., `/dev/urandom` on Linux). Three named methods underneath: `uuid`, `number`, `string`.

**Global form:** `%utils.random`.

<a id="random-uuid"></a>
### `%engine.random.uuid`

Fresh UUID. See [uuid-generation.md](uuid-generation.md) for the canonical surface (version, format, etc.).

```caspian
$id = %utils.random.uuid
```

**Global form:** `%utils.random.uuid`.

<a id="random-number"></a>
### `%engine.random.number`

Random number drawn from a given range.

```caspian
$n = %utils.random.number(min: 0, max: 100)       # integer in [0, 100]
$f = %utils.random.number(min: 0.0, max: 1.0)     # float in [0.0, 1.0]
```

Type follows the range bounds (integer bounds → integer; float bounds → float). Exact kwarg shape TBD.

**Global form:** `%utils.random.number`.

<a id="random-string"></a>
### `%engine.random.string`

Random string of a given length, optionally from a specified alphabet.

```caspian
$token = %utils.random.string(length: 32)                          # default alphabet
$hex   = %utils.random.string(length: 16, alphabet: 'hex')         # hex characters
$pin   = %utils.random.string(length: 6,  alphabet: '0123456789')  # explicit alphabet
```

Default alphabet is TBD (likely alphanumeric or URL-safe base64). Exact kwarg shape TBD.

**Global form:** `%utils.random.string`.

<a id="pid"></a>
### `%engine.pid`

OS process ID of the running script.

**Global form:** none yet (TBD). `%process.pid` is the natural home if added later (`%process` already exists as a top-level system method).

<a id="platform"></a>
### `%engine.platform`

Container namespace for OS and CPU-architecture info. Two named slots underneath: `%engine.platform.os` and `%engine.platform.architecture`.

**Global form: none.** Platform info is only available through `%engine` — user-role concern only. Libraries that need it take what they need as a parameter from user.

<a id="platform-os"></a>
### `%engine.platform.os`

Hash of OS information — as much as the engine can cheaply pull together from the host. The exact fields vary by platform; the script can check for what it cares about with `.has_key?`. Common fields:

| Field | Type | Example | Notes |
|---|---|---|---|
| `family` | string | `'linux'`, `'macos'`, `'windows'`, `'freebsd'` | Always present |
| `name` | string | `'Ubuntu'`, `'macOS'`, `'Windows'` | Always present |
| `version` | string | `'22.04'`, `'13.5'`, `'11'` | Always present |
| `pretty_name` | string | `'Ubuntu 22.04.3 LTS'`, `'macOS Sonoma 14.5'` | Best human-readable form; assembled by the engine if not directly available |
| `kernel` | string | `'6.5.0-1-amd64'`, `'23.6.0'` | `uname -r` equivalent |
| `distro` | string | `'ubuntu'`, `'debian'`, `'fedora'` | Linux-specific; omitted on macOS/Windows |
| `codename` | string | `'jammy'`, `'bookworm'`, `'sonoma'` | Present where the platform has one; omitted otherwise |
| `build` | string | `'22631'` (Windows), `'23F79'` (macOS) | Build identifier where available |

Sources the engine pulls from (no special permission required):

- **Linux:** `/etc/os-release` (ID → `distro`, NAME → `name`, VERSION_ID → `version`, PRETTY_NAME → `pretty_name`, VERSION_CODENAME → `codename`); `uname -r` → `kernel`.
- **macOS:** `sw_vers` (ProductName → `name`, ProductVersion → `version`, BuildVersion → `build`); `uname -r` → `kernel`; codename derived from version (Ventura, Sonoma, etc.).
- **Windows:** Win32 API (`GetVersionEx` / registry) → `name`, `version`, `build`.

```caspian
$os = %engine.platform.os
if $os['family'] == 'linux' and $os['distro'] == 'ubuntu'
    # use the apt path
end

puts $os['pretty_name']    # "Ubuntu 22.04.3 LTS"
```

Engine reads these once at startup and caches; reading `%engine.platform.os` is cheap.

**Global form: none.**

<a id="platform-architecture"></a>
### `%engine.platform.architecture`

CPU architecture: `x86_64`, `arm64`, etc. Verbose name per the long-names-for-rare-methods principle — most scripts won't query this.

**Global form: none.**

<a id="encryption"></a>
### `%engine.encryption`

Container namespace for cryptographic primitives. Two named slots underneath: `%engine.encryption.signing` and `%engine.encryption.sha`. Both expose well-audited implementations backed by kernel/OS-level entropy.

**Global form:** `%utils.encryption`.

<a id="encryption-signing"></a>
### `%engine.encryption.signing`

Ed25519 signing and verification. Used by the [blockchain integration](downloads/blockchain/) for signed library endorsements, signed authority blocks, and signed records. Working surface:

| Method | Purpose |
|---|---|
| `.generate_keypair()` | Fresh Ed25519 keypair |
| `.sign($private_key, $bytes)` | Produce a signature |
| `.verify($public_key, $signature, $bytes)` | Check a signature; returns boolean |
| `.keypair_from_seed($seed)` | Deterministic keypair from a seed (reproducible test fixtures, KDF-derived keys) |
| `.import_key(...)` / `.export_key(...)` | PEM / DER / raw-bytes interchange |

NOT for password storage — passwords have their own spec at [ideas/caspian/passwords/](../../ideas/caspian/passwords/) (separate primitives, separate KDF).

**Global form:** `%utils.encryption.signing`.

<a id="encryption-sha"></a>
### `%engine.encryption.sha`

SHA-family hashing primitives. SHA-256 is the most common (blockchain content addressing, file fingerprinting, library-artifact hashes); SHA-512 and HMAC variants are also exposed.

| Method | Purpose |
|---|---|
| `.sha256($data)` | SHA-256 digest as a hex string |
| `.sha512($data)` | SHA-512 digest as a hex string |
| `.hmac_sha256($key, $data)` | HMAC-SHA-256 (keyed-MAC use cases) |
| `.hmac_sha512($key, $data)` | HMAC-SHA-512 |
| Streaming interface for large inputs | TBD shape (probably `.open(:sha256)` style for hashing a file without loading it all into memory) |

Slot is named `sha` rather than `hash` because it's the SHA family specifically. Other hash families (BLAKE2/3, etc.) would get their own slots if and when they're needed.

NOT for password storage — see [passwords/passkeys](../../ideas/caspian/passwords/) for the password story (uses a proper KDF like Argon2id or scrypt, TBD which).

**Global form:** `%utils.encryption.sha`.

<a id="bracket-access"></a>
### `%engine[<key>]` — arbitrary engine-passed values

Escape hatch for anything beyond the standard named slots above. The engine may bind arbitrary keys at startup for context-specific values: test-harness injections, agent-context data, plugin bindings, environment-specific configuration, anything else not deserving its own standard slot.

```caspian
$test_fixture = %engine['test_fixture']
$agent_context = %engine['puckai_agent_context']
```

`%engine.<name>` and `%engine['<name>']` access the same surface for valid-identifier keys. The bracket form is required for keys with special characters or for keys computed at runtime.

The standard slots above are documented; engine-injected keys via bracket access are open-ended. The script knows what to look for by convention (e.g., a test harness sets a known key; the script reads it).

**Global form:** none by design — the bracket-access escape hatch is engine-direct only. Capabilities passed through `%engine[<key>]` are scoped to the user-role script that owns the `%engine` reach; nothing surfaces them under `%utils` or other global namespaces.

---

## See also

- [Engine config](engine/config.md) — declarative resource requirements at the top of a script.
- [Roles](roles.md) — why `%engine` is user-only and how capabilities flow down.
- [Permission flags / `--allow-*`](../development/v1/caspian/frank.md#permission-flags) — how engine slots are gated at launch.
