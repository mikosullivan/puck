# `%utils`

~~~json
{"vibecode": {
	"doc": "utils",
	"role": "spec for %utils, the engine-granted convenience-utility capability; bag of common low-sensitivity helpers owned by the utils role",
	"key_concepts": ["utils_capability", "utils_role",
		"low_sensitivity_helpers"]
}}
~~~

`%utils` is the engine-granted convenience-utility capability — a
bag of common, low-sensitivity helpers. Everything coming out of
`%utils` is owned by the `utils` role.

The full surface of `%utils` will fill in as utilities are
specified. This doc covers them one at a time.

---

<a id="utilsmemory"></a>
## `%utils.memory`

Read-only introspection of the current process's memory usage.

```
%utils.memory.used   # bytes currently used by this process
```

<a id="memory-management-ideas-tbd"></a>
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

<a id="utilstempdir"></a>
## `%utils.tempdir`

Creates a temporary directory scoped to a block. The directory is
created on entry, exposed to the block as a
[directory jail](../built-in-classes/filesystem.md#the-directory-jail),
and **deleted when the block exits** (whether normally, via early
return, or via exception).

```
%utils.tempdir do($jail)
    $jail.write 'scratch.txt', 'some bytes'
    # ... use $jail like any directory ...
end
# $jail is gone; the temp dir has been deleted
```

The block receives a directory jail object — composable with anything that
takes a directory (e.g., `$server.static $jail`, a Jasmine
directory store writing here transiently, etc.).

<a id="properties"></a>
### Properties

- **Block-scoped lifetime.** Created on block entry, deleted on
  block exit. No cleanup boilerplate, no leak from a forgotten
  unlink.
- **Directory-jail abstraction.** The block sees a directory; it doesn't
  know or care where on the filesystem the directory actually
  lives. Code inside the block isn't coupled to OS paths.
- **Permission-based.** Temp-dir creation is a capability the
  engine grants, not an ambient ability. If the engine didn't
  grant it, `%utils.tempdir` either errors or is simply absent
  from `%utils` (exact mechanism TBD).
- **Explicit chain propagation only.** A process that can create
  temp dirs does **not** automatically grant that capability to
  everything it calls. The capability has to be explicitly sent
  down the `%chain` — same posture as `%forks` and similar
  engine-granted capabilities. This is the no-dangerous-defaults
  pattern.

<a id="concerns-to-keep-in-mind"></a>
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
  tempdir capability to untrusted code lets it touch real disk —
  fill it, stash data, or coordinate with other components via
  the filesystem. **Worse: untrusted code can intentionally
  abort** to bypass block-exit cleanup, leaving the temp dir
  visible on disk until the OS cleanup sweep catches it. That's
  an intentional information-leak vector if the temp dir held
  anything sensitive. The mitigation is straightforward: don't
  grant tempdir to untrusted code in the first place. The
  explicit-only-down-the-chain rule already enforces this by
  default; the warning is here so the implications of overriding
  that default are clear.

<a id="implementation-disk-backed-not-in-memory"></a>
### Implementation: disk-backed, not in-memory

The tempdir is backed by a real OS temporary directory (`/tmp` or
equivalent), not by an in-memory mikobase. The motivating
use case for tempdir is often "I need somewhere to put a huge
file while I work on it" — uploaded videos, generated archives,
multi-gigabyte intermediate data — and that's exactly where
in-memory storage falls down.

The in-memory option stays interesting for other "scratch that
vanishes with me" cases where the data is small (see
[Mikobase as filesystem § In-memory mode](../../ideas/apps/mikobase-as-filesystem.md#in-memory-mode)),
but `%utils.tempdir` isn't one of them.

---

<a id="utilsrandom"></a>
## `%utils.random`

Random-value helpers.

<a id="utilsrandomuuid"></a>
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
[uuid-generation.md](../uuid-generation.md) for the engine-level
implementation guidance (one-C-function-per-call, hex lookup table,
literal-dash writes, etc.) and the security rationale behind the
no-caching rule.

<a id="utilsrandomnumber"></a>
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

<a id="utilsrandomstring"></a>
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

