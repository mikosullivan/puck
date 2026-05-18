# `%utils`

`%utils` is the engine-granted convenience-utility capability — a
bag of common, low-sensitivity helpers. Everything coming out of
`%utils` is owned by the `utils` role.

The full surface of `%utils` will fill in as utilities are
specified. This doc covers them one at a time.

---

<a id="utilsmemory"></a>
## 1 `%utils.memory`

Read-only introspection of the current process's memory usage,
plus an opt-in soft-limit mechanism for graceful handling of
pressure.

<a id="basic-introspection"></a>
### 1.1 Basic introspection

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
### 1.2 `%utils.memory.raise`

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
### 1.3 Implementation: Lua does the work

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
## 2 `%utils.tempdir`

Creates a temporary directory scoped to a block. The directory is
created on entry, exposed to the block as a DirJail, and **deleted
when the block exits** (whether normally, via early return, or via
exception).

<a id="shape"></a>
### 2.1 Shape

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
### 2.2 Properties

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
### 2.3 Concerns to keep in mind

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
### 2.4 Implementation: disk-backed, not in-memory

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
### 2.5 V1 status

**Open question — is this a v1 feature?** The capability is well
shaped and would be useful, but it requires the dirjail/directory
abstractions plus engine-capability plumbing. If those are not
otherwise on the v1 path, `%utils.tempdir` may slip to v2 or
later. To be decided alongside the rest of the v1 utility surface.
