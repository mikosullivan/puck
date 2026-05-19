# `%utils`

~~~json
{"vibecode": {
	"doc": "utils",
	"role": "spec for %utils, the engine-granted convenience-utility capability; bag of common low-sensitivity helpers (memory introspection and soft limits, etc.) owned by the utils role",
	"key_concepts": ["utils_capability", "utils_role", "memory_introspection",
		"soft_limit_opt_in", "low_sensitivity_helpers"]
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

Read-only introspection of the current process's memory usage,
plus an opt-in soft-limit mechanism for graceful handling of
pressure.

<a id="basic-introspection"></a>
### Basic introspection

```
%utils.memory.used        # bytes currently used by this process
%utils.memory.limit       # configured hard limit (null if uncapped)
%utils.memory.available   # limit minus used (null if uncapped)
```

Three read-only values. Useful when a handler is about to do
something memory-intensive and wants to check whether there's
headroom first:

```
if %utils.memory.available > 50_000_000
    # plenty of room — proceed with in-memory processing
else
    # near the limit — reject, defer, or spill to FSO instead
end
```

<a id="utilsmemoryraise"></a>
### `%utils.memory.raise`

A settable soft threshold:

```
%utils.memory.raise = 100_000_000
```

When set, the engine raises a memory-limit exception
(`puck.uno/error/memory_limit` or similar) when memory usage
crosses the threshold. Standard exception flow unwinds the chain,
freeing memory along the way; handlers can catch it and turn it
into a 503 or whatever response makes sense.

**Why an engine-level threshold instead of user-side checks:**

- **Continuous, mid-allocation enforcement.** Fires the moment
  the threshold is crossed, including inside framework or
  library code the user didn't write and can't instrument.
- **Pre-allocation rejection.** A single big allocation that
  would cross the threshold can be rejected before it succeeds;
  the memory was never actually used.
- **No developer discipline required.** User-side checks fire
  only at points the developer remembers to insert them.

A small reserved memory pool sits aside for the exception
machinery itself, so raising the exception still works when the
heap is genuinely tight.

Setting `%utils.memory.raise = null` disables the threshold.

<a id="implementation-lua-does-the-work"></a>
### Implementation: Lua does the work

Charlie engines run on Lua, which already tracks memory
continuously for its own garbage collector. The `used` / `limit` /
`available` values come straight from Lua's accounting; the
`raise` threshold and hard limit are enforced via `lua_setallocf`,
which lets the engine interpose on every allocation. There's no
separate memory-tracking subsystem to design or maintain — we
expose what Lua already knows.

The framework deliberately does **not** get heavy into memory
management beyond this. Lua's GC handles routine cleanup; the
engine adds the threshold/limit hooks; that's the whole surface.

---

<a id="utilstempdir"></a>
## `%utils.tempdir`

Creates a temporary directory scoped to a block. The directory is
created on entry, exposed to the block as a DirJail, and **deleted
when the block exits** (whether normally, via early return, or via
exception).

<a id="shape"></a>
### Shape

```
%utils.tempdir do($jail)
    $jail.write 'scratch.txt', 'some bytes'
    # ... use $jail like any directory ...
end
# $jail is gone; the temp dir has been deleted
```

The block receives a DirJail object — composable with anything that
takes a directory (e.g., `$server.static $jail`, a Jasmine
directory store writing here transiently, etc.).

<a id="properties"></a>
### Properties

- **Block-scoped lifetime.** Created on block entry, deleted on
  block exit. No cleanup boilerplate, no leak from a forgotten
  unlink.
- **DirJail abstraction.** The block sees a directory; it doesn't
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
[Mikobase as filesystem § In-memory mode](../ideas/apps/mikobase-as-filesystem.md#in-memory-mode)),
but `%utils.tempdir` isn't one of them.

<a id="v1-status"></a>
### V1 status

**Open question — is this a v1 feature?** The capability is well
shaped and would be useful, but it requires the dirjail/directory
abstractions plus engine-capability plumbing. If those are not
otherwise on the v1 path, `%utils.tempdir` may slip to v2 or
later. To be decided alongside the rest of the v1 utility surface.

---

<a id="utilsrandom"></a>
## `%utils.random`

Random-value helpers.

<a id="utilsrandomuuid"></a>
### `%utils.random.uuid`

Returns a fresh UUID v4 string. By contract, **the result is
cryptographically strong** — the 122 random bits inside the UUID
come from the operating system's cryptographically secure random
source, not from a regular PRNG.

```charlie
$id = %utils.random.uuid
# "550e8400-e29b-41d4-a716-446655440000"
```

<a id="why-crypto-strong-by-default"></a>
#### Why crypto-strong by default

"Cryptographically strong" means the output is **unpredictable**:
given any number of previous UUIDs from this generator, an attacker
cannot guess the next one, and cannot reconstruct the generator's
internal state. Regular PRNGs (such as Lua's `math.random`) are
fully predictable once you know the seed and recoverable from a
modest number of observed outputs. Crypto-strong generators are
not.

For most uses of `%utils.random.uuid` — internal record IDs in a
Mikobase, keys in a worldlet, etc. — predictability doesn't matter;
uniqueness is the only required property (see
[mikobase.md § Record identity](../mikobase/mikobase.md#record-identity)).
But UUIDs leak into URLs, session identifiers, and tokens often
enough that the safer default is unpredictability for free.

The cost is essentially zero. A crypto-strong UUID is a 16-byte
read from the OS — sub-microsecond, indistinguishable in
practice from a regular `math.random` call at human scale.

<a id="implementation"></a>
#### Implementation

The contract is platform-agnostic: 16 bytes from a
cryptographically strong source, with the version and variant
marker bits set, hex-formatted as `8-4-4-4-12`. Crypto strength is
**guaranteed by the operating system's CSPRNG**, not by anything
the engine does on top.

The reference engine sources those bytes through **libsodium**'s
`randombytes_buf`. The dataflow on a single call:

```
Charlie:       %utils.random.uuid
Lua engine:    → Lua binding for libsodium
libsodium:     → randombytes_buf(buf, 16)
OS kernel:     → getrandom() on Linux ≥ 3.17
                 getentropy() on macOS/BSD
                 BCryptGenRandom() on Windows
                 (libsodium picks the right call per platform)
                 ← 16 crypto-quality bytes
libsodium:     ← bytes
Lua engine:    set version + variant bits, hex-format as 8-4-4-4-12
Charlie:       ← "550e8400-e29b-41d4-a716-446655440000"
```

The kernel is doing the actual cryptographic work; libsodium is a
thin platform-abstraction pass-through; the engine is a
formatter. Project page for libsodium:
<https://libsodium.org/>.

**Why libsodium specifically:**

- **Security-by-default.** libsodium is designed to be hard to
  misuse. OpenSSL has more features but more sharp edges; for a
  language whose pitch includes safety, the smaller, more
  opinionated library is the better neighbour.
- **One dependency for all of Charlie's crypto needs.** The Puck
  blockchain uses Ed25519 signing
  (see [blockchain.md](blockchain.md)); libsodium provides that
  too. Adding libsodium here means the blockchain implementation
  comes from the same place rather than a second crypto
  dependency.
- **Small surface, well-audited.** Much smaller codebase than
  OpenSSL; security-focused maintenance; permissive ISC licence.

What the engine **must not do** under any circumstances: fall
back to a non-crypto PRNG (`math.random`, Lua's default
generator). If libsodium is unavailable at runtime,
`%utils.random.uuid` raises rather than silently degrading.
A weak UUID labeled "crypto-strong" is worse than no UUID at
all — it breaks the contract that downstream code is relying on.

<a id="rating-the-strength"></a>
#### Rating the strength

Because the actual bytes come from the OS kernel's CSPRNG (via
libsodium), the strength a developer can claim for
`%utils.random.uuid` is exactly the strength of the OS's
crypto-random source. Concretely:

- **Statistical quality.** Every supported OS CSPRNG passes the
  rigorous test batteries (NIST SP 800-22, TestU01 BigCrush,
  PractRand) trivially. A developer can claim "passes BigCrush"
  with high confidence without running it themselves.
- **Cryptographic construction.** Linux's `getrandom`, macOS's
  `getentropy`, and Windows' `BCryptGenRandom` are all built on
  cryptographically-vetted primitives (Linux uses a ChaCha20-based
  construction; the others are similar in spirit). The
  construction-level standard they target is **NIST SP 800-90A**
  (the spec for approved CSPRNG constructions).
- **Formal certification.** OS CSPRNGs are often **FIPS
  140-2 / FIPS 140-3 validated** in their certified configurations
  (e.g., RHEL with the FIPS-validated kernel module, Windows in
  FIPS mode). However, **libsodium itself is not FIPS-validated**,
  and Charlie does not carry a FIPS certification of its own. The
  practical effect: a developer can honestly say "the randomness
  is sourced from a FIPS-validated kernel CSPRNG" on appropriate
  platforms, but not "Charlie is FIPS-certified."
- **For regulated industries.** If a compliance regime requires
  end-to-end FIPS validation (some government, healthcare, and
  financial contexts do), `%utils.random.uuid` is **not the right
  tool** — the application needs to call a FIPS-validated crypto
  module directly. For everything else, this is the strongest
  practical option short of that.

In short: the bytes are as strong as the operating system can
give you, which on every platform Charlie supports is
state-of-the-art cryptographic randomness. The library chain
between Charlie and the kernel adds no measurable weakness.

<a id="not-for-reproducible-runs"></a>
#### Not for reproducible runs

If you need a reproducible UUID for a test fixture or a deterministic
simulation, do **not** reach for `%utils.random.uuid` — by design
its output cannot be reproduced. A separate seeded-PRNG API (to be
spec'd) is the right tool for that, and it should be an
explicit opt-in, not a flag on `%utils.random.uuid`.

<a id="v1-status-random"></a>
#### V1 status

In scope for V1. The implementation surface is small (read bytes,
set marker bits, hex-format) and the dependency surface is
nonexistent on the Linux platform the reference engine targets.
