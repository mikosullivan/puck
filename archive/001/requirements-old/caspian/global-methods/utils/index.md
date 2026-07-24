# `%utils`

~~~vibecode
{"vibecode": {
	"doc": "utils",
	"role": "catalog of %utils, the engine-granted convenience-utility capability. Contains all the global forms of engine-exposed capabilities (forks, networking, file system, encryption, etc.) plus a few standalone utilities (memory, timer). Single flat list at the top; detail sections below; cross-links to canonical homes where they exist.",
	"key_concepts": ["utils_capability", "utils_role",
		"low_sensitivity_helpers",
		"global_form_of_engine_capabilities",
		"single_flat_list_with_links_to_details"]
}}
~~~

`%utils` is the engine-granted convenience-utility capability — a bag of common helpers, accessible from any role (subject to that role having been granted the capability).

Most surfaces under `%utils` are the **global form** of an `%engine.X` slot — see [script-context.md](../../script-context.md) for the engine-side view. A few (`%utils.memory`, `%utils.timer`, `%utils.timeout`) are utilities specific to `%utils` with no engine-slot counterpart.

Everything coming out of `%utils` is owned by the `utils` role.

---

## All `%utils` surfaces at a glance

| Surface | Purpose | Canonical home |
|---|---|---|
| [`%utils.argv`](#utilsargv) | Command-line arguments (array of strings) | [script-context § argv](../../script-context.md#argv) |
| [`%utils.broadcast`](#utilsbroadcast) | Broadcast an event to listeners | [events/](../../events/) |
| [`%utils.encryption`](#utilsencryption) | Cryptographic primitives (signing, hashing) | this doc |
| [`%utils.env`](#utilsenv) | Environment-variable accessor | this doc |
| [`%utils.file_system`](#utilsfilesystem) | Filesystem access (dirjails, file objects) | this doc |
| [`%utils.forks`](#utilsforks) | Spawn forked child processes | [forking/](../../forking/) |
| [`%utils.memory`](#utilsmemory) | Process memory introspection | this doc |
| [`%utils.network`](#utilsnetwork) | Networking — HTTP client, raw sockets, UDS | [network/](../../network/) |
| [`%utils.now`](#utilsnow) | Current timestamp | this doc |
| [`%utils.random`](#utilsrandom) | Random-value primitives (uuid, number, string) | this doc |
| [`%utils.register`](#utilsregister) | Register an event handler | [events/](../../events/) |
| [`%utils.steps`](#utilssteps) | Count Caspian-level steps around a block | [steps.md](steps.md) |
| [`%utils.timer`](#utilstimer) | Measure elapsed time around a block | this doc |
| [`%utils.timeout`](#utilstimeout) | Limit a block's wall-clock duration | this doc |
| [`%utils.tmp`](#utilstmp) | Fresh temp dirjail per access | this doc |

---

## `%utils.memory`

Read-only introspection of the current process's memory usage.

```
%utils.memory.used   # bytes currently used by this process
```

### Memory-management ideas (TBD)

A wider memory-management surface has been kicked around but is
not specified. Sketched ideas, recorded so the slot doesn't get
forgotten:

- A configured hard limit (`%utils.memory.limit`) and an
  `available` derivation from it.
- A settable soft threshold (working name `%utils.memory.raise`)
  that raises an exception when usage crosses it, so handlers can
  unwind gracefully under pressure.
- Engine-level enforcement (continuous, mid-allocation) rather
  than user-side polling.

None of the above is committed. Shape, names, and semantics are
open until a concrete use case drives the design.

---

## `%utils.tmp`

Each access to `%utils.tmp` returns a fresh dirjail backed by a new temp directory on disk. The dirjail is a [directory jail](../../built-in-classes/filesystem.md#the-directory-jail) — code that holds it can read and write inside but can't escape the directory.

Three lifetime patterns; choose the one that matches the scope you want.

### Direct access

```caspian
$dir = %utils.tmp
# use $dir as a regular directory handle
$dir.write 'scratch.txt', 'some bytes'
```

The dirjail is auto-deleted when `$dir` goes out of the surrounding scope (function returns, block ends, etc.). No cleanup boilerplate, no leak from a forgotten unlink.

### Block form

For lifetime tied to a specific block rather than the surrounding scope, pass a do-block:

```caspian
%utils.tmp do($dir)
    $dir.write 'scratch.txt', 'some bytes'
    # ... use $dir like any directory ...
end
# $dir is gone; the temp dir has been deleted
```

Created on block entry, deleted on block exit — whether the block returns normally, via early return, or via exception.

### Explicit close

For cases where you need to release the dir before the surrounding scope or block ends, call `.close`:

```caspian
$dir = %utils.tmp
# ... do work ...
$dir.close      # directory deleted now, even though we're still in scope
```

After `.close`, the dirjail handle is unusable; subsequent operations raise.

### Properties

- **Directory-jail abstraction.** The handle is a directory; it doesn't know or care where on the filesystem the directory actually lives. Code holding it isn't coupled to OS paths.
- **Multiple accesses produce independent dirjails.** `$work = %utils.tmp` and `$archive = %utils.tmp` give you two separate dirs.
- **Permission-based.** Temp-dir creation is a capability the engine grants, not an ambient ability. If the engine didn't grant it, `%utils.tmp` either errors or is simply absent from `%utils` (exact mechanism TBD).
- **Explicit chain propagation only.** A process that can create temp dirs does **not** automatically grant that capability to everything it calls. The capability has to be explicitly sent down the `%chain` — same posture as `%utils.forks` and similar engine-granted capabilities. This is the no-dangerous-defaults pattern.
- **Engine-level slot.** `%engine.tmp` is the user-only named access to the same capability. See [script-context.md § `%engine.tmp`](../../script-context.md#tmp) for the engine-side view.

### Concerns to keep in mind

- **Crash mid-block.** If the process hard-crashes while inside
  the block, the OS's `/tmp` cleanup sweeps eventually handle the
  abandoned directory — but it could persist for a while before
  that happens. Standard Unix posture; acceptable.
- **Forked subprocess outliving the block.** If a forked child
  process is still writing in the temp dir when the parent's
  block ends, the dir disappears under the child. Best treated as
  a "don't do that" — engineering around it (refcounting,
  deferred deletion) would complicate the simple
  block-scope model.
- **Untrusted code is a real attack vector.** Granting the
  tmp capability to untrusted code lets it touch real disk —
  fill it, stash data, or coordinate with other components via
  the filesystem. **Worse: untrusted code can intentionally
  abort** to bypass block-exit cleanup, leaving the temp dir
  visible on disk until the OS cleanup sweep catches it. That's
  an intentional information-leak vector if the temp dir held
  anything sensitive. The mitigation is straightforward: don't
  grant tmp to untrusted code in the first place. The
  explicit-only-down-the-chain rule already enforces this by
  default; the warning is here so the implications of overriding
  that default are clear.

### Implementation: disk-backed, not in-memory

The tmp is backed by a real OS temporary directory (`/tmp` or
equivalent), not by an in-memory mikobase. The motivating
use case for tmp is often "I need somewhere to put a huge
file while I work on it" — uploaded videos, generated archives,
multi-gigabyte intermediate data — and that's exactly where
in-memory storage falls down.

The in-memory option stays interesting for other "scratch that
vanishes with me" cases where the data is small (see
[Mikobase as filesystem § In-memory mode](../../../../ideas/apps/mikobase-as-filesystem.md#in-memory-mode)),
but `%utils.tmp` isn't one of them.

---

## `%utils.random`

Random-value helpers.

### `%utils.random.uuid`

Returns a UUID v4 string. This method uses Lua's
[libsodium](https://github.com/jedisct1/libsodium)
library. `libsodium` [uses your operating system's random number
generator](https://libsodium.gitbook.io/doc/generating_random_data).
For example, on Linux you get a
[cryptographically secure](https://man7.org/linux/man-pages/man7/random.7.html).
random value.
[This article](https://www.atsec.com/sp800-90a-and-sp800-90b-compliant-linux-random-number-generator/)
discusses Linux's compliance with US government cryptographic standards.

**Engine implementation note**: every UUID comes fresh from libsodium
per call — no caching, no PRNG state. See
[uuid-generation.md](../../uuid-generation.md) for the engine-level
implementation guidance (one-C-function-per-call, hex lookup table,
literal-dash writes, etc.) and the security rationale behind the
no-caching rule.

### `%utils.random.number`

Returns a random number in `[min, max]`, both ends inclusive, drawn
from the same cryptographically strong source as
[`%utils.random.uuid`](#utilsrandomuuid) (libsodium → OS CSPRNG).

```
%utils.random.number(1, 100)              # 1 through 100
%utils.random.number(1, 6)                # roll a six-sided die
%utils.random.number(1, 100, step: 0.1)   # one of 1.0, 1.1, 1.2, ..., 100.0
%utils.random.number(0, 10, step: 3)      # one of 0, 3, 6, 9
```

`min` and `max` are required. `step` defaults to `1`. The two bounds
can be passed in either order — if `min > max`, they're swapped before
use. `number(1, 100)` and `number(100, 1)` are equivalent.

The result is always `min + k * step` for some non-negative integer
`k` (after the swap, if any), picked uniformly via libsodium's
unbiased range function (no modulo bias).

If `max - min` isn't an exact multiple of `step`, the reachable
maximum is `min + floor((max - min) / step) * step` — the high end
is truncated to the last step-aligned value, not the literal `max`.
That's why `number(0, 10, step: 3)` never returns `10`.

Errors: `step <= 0`.

### `%utils.random.string`

Returns a random string of the given length, with each character
drawn uniformly from a pool. Uses the same cryptographically strong
source as [`%utils.random.uuid`](#utilsrandomuuid) (libsodium → OS
CSPRNG), via libsodium's unbiased range function (no modulo bias).

```
%utils.random.string(5)                        # 5 chars from the default :alphanum pool
%utils.random.string(16, from: :hex)           # 16 hex chars
%utils.random.string(5,  alphabet: 'abcde')    # 5 chars from a custom alphabet
```

`length` is required (character count, not bytes). The pool comes
from one of two mutually-exclusive keyword arguments:

- **`from:`** — a symbol naming a predefined alphabet (see table
  below). Defaults to `:alphanum` if neither keyword is given.
- **`alphabet:`** — a string containing the exact characters to draw
  from. Repeats are allowed (`'aaab'` weights `a` three times).

| Symbol       | Characters                                          |
|--------------|-----------------------------------------------------|
| `:alphanum`  | `a-z`, `A-Z`, `0-9` (62 chars; the default)         |
| `:hex`       | `0-9`, `a-f` (16 chars; lowercase)                  |
| `:base64`    | `a-z`, `A-Z`, `0-9`, `+`, `/` (64 chars)            |
| `:base64url` | `a-z`, `A-Z`, `0-9`, `-`, `_` (64 chars, URL-safe)  |
| `:digits`    | `0-9` (10 chars)                                    |
| `:letters`   | `a-z`, `A-Z` (52 chars)                             |
| `:lower`     | `a-z` (26 chars)                                    |
| `:upper`     | `A-Z` (26 chars)                                    |

**Length is character count, not bytes.** `string(16, from: :hex)`
returns a 16-character string, which carries 8 bytes of entropy
(each hex char is 4 bits). If you want N bytes of randomness
encoded as hex, ask for `N*2` characters.

Errors: `length <= 0`; unknown `from:` symbol; empty `alphabet:`
string; both `from:` and `alphabet:` passed in the same call.

---

## `%utils.now`

Current timestamp from the engine-controlled clock.

```caspian
$ts = %utils.now    # timestamp object
```

Engine-controlled rather than direct from the OS so test harnesses can inject a fixed clock for deterministic runs. See [script-context § `%engine.now`](../../script-context.md#now) for the engine-slot view.

---

## `%utils.argv`

Command-line arguments after the script name, as an array of strings.

```caspian
$args = %utils.argv
```

`$args` is just a variable name a script chooses; bind to whatever reads cleanly. See [script-context § `%engine.argv`](../../script-context.md#argv).

---

## `%utils.env`

Environment-variable accessor (hash-shaped). Read environment variables that were set when the script was launched.

```caspian
$home = %utils.env['HOME']
%utils.env.has_key?('SHELL')
```

Hash-style interface (`[]`, `.has_key?`, `.each`, `.keys`). Read-only — scripts can't mutate the environment of the running process through this surface.

---

## `%utils.file_system`

Filesystem access — dirjails, file objects, directory traversal. The global form of the user-only `%engine.root` dirjail.

Working surface (full spec TBD; canonical home will likely live at [built-in-classes/filesystem.md](../../built-in-classes/filesystem.md) or a dedicated file-system spec):

```caspian
$root = %utils.file_system          # root dirjail
$file = $root['some/path.txt']      # file object
```

Gated by `--allow-fs` at launch. Without the grant, `%utils.file_system` is `null`.

---

## `%utils.network`

Container for networking surfaces. Full spec at [network/](../../network/) and its sub-docs.

| Sub-surface | Purpose | Canonical home |
|---|---|---|
| `%utils.network.http_client` | HTTP client (often via `%net.http_client` / `%net.fetch` sugar) | [network/http/client/](../../network/http/client/) |
| `%utils.network.sockets` | Raw TCP/UDP/SSL socket constructors | [network/sockets.md](../../network/sockets.md) |
| `%utils.network.uds` | Unix-domain-socket server constructor; foundation of `$uds.share` and `$uds.mikobase` | [network/uds/](../../network/uds/) |

The `%net` global is a further-shortened alias for `%utils.network` — `%net.fetch(url)` is the most common form for one-shot HTTP requests.

---

## `%utils.encryption`

Container for cryptographic primitives. Two sub-surfaces:

### `%utils.encryption.signing`

Ed25519 signing and verification. Used by the [blockchain integration](../../downloads/blockchain/) for signed library endorsements, signed authority blocks, and signed records.

| Method | Purpose |
|---|---|
| `.generate_keypair()` | Fresh Ed25519 keypair |
| `.sign($private_key, $bytes)` | Produce a signature |
| `.verify($public_key, $signature, $bytes)` | Check a signature; returns boolean |
| `.keypair_from_seed($seed)` | Deterministic keypair from a seed |
| `.import_key(...)` / `.export_key(...)` | PEM / DER / raw-bytes interchange |

NOT for password storage — see [ideas/caspian/passwords/](../../../../ideas/caspian/passwords/) for the separate passwords spec.

### `%utils.encryption.sha`

SHA-family hashing primitives.

| Method | Purpose |
|---|---|
| `.sha256($data)` | SHA-256 digest as a hex string |
| `.sha512($data)` | SHA-512 digest as a hex string |
| `.hmac_sha256($key, $data)` | HMAC-SHA-256 |
| `.hmac_sha512($key, $data)` | HMAC-SHA-512 |

Slot is named `sha` rather than `hash` because it's SHA-family specifically. Other hash families (BLAKE2/3, etc.) would get their own slots when needed.

NOT for password storage — see [ideas/caspian/passwords/](../../../../ideas/caspian/passwords/).

---

## `%utils.forks`

Spawn forked child processes. Three forms: `%utils.forks.single()`, `%utils.forks.multiple(N)`, `%utils.detach()`. Each takes a `do ... end` block that runs in the child.

Full spec at [forking/](../../forking/).

```caspian
%utils.forks.multiple(20) do
    # this runs in each of 20 child processes
end
```

---

## `%utils.broadcast`

Broadcast an event to all registered listeners.

```caspian
%utils.broadcast 'event_name', arg1, arg2
```

Full spec at [events/](../../events/).

---

## `%utils.register`

Register a closure as an event handler.

```caspian
%utils.register $source, 'event_name' do($broadcaster, $name, $args...)
    # ...
end
```

Full spec at [events/](../../events/).

---

## `%utils.steps`

Count Caspian-level evaluation steps inside a block. Off by default — zero overhead unless a `%utils.steps` call is active. One step = one call to `eval` or `exec_stmt` in the interpreter. Deterministic; engine-independent.

```caspian
$count = %utils.steps do
    # ... work whose steps are counted ...
end
```

Full spec at [steps.md](steps.md).

---

## `%utils.timer`

Measure elapsed time around a block. Returns the duration in seconds.

```caspian
$seconds = %utils.timer do
    # ... work to measure ...
end
```

`%utils.timer` is `null` if the engine didn't grant `%utils`. Guard with `if %utils` if the caller can't assume the namespace.

---

## `%utils.timeout`

Limit a block's wall-clock duration. Raises if the block doesn't return within the budget.

```caspian
%utils.timeout(10) do
    # work that must finish within 10 seconds
end

%utils.timeout(3600, unwind: true) do
    # ...
end
```

The `unwind:` kwarg controls whether a timeout raises a normal exception (default) or unwinds without raising. Full semantics TBD.
