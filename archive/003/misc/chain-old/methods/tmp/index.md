# `%chain.tmp`

**STALE — pending relocation.** `%chain` no longer carries methods. This file describes what used to live on `%chain.X` and awaits relocation to its correct home (typically a top-level global, a downloadable core object, or a permission-indicator stub). See [chain/index](https://puck.uno/requirements/chain/) for the current `%chain` scope.

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_utils_tmp",
	"role": "spec for %chain.tmp — fresh temp dirjail per access; auto-deleted when the handle leaves scope (or on explicit .close, or on block exit). Disk-backed, not in-memory."
}}
~~~

**Default-granted across role boundaries:** no.  

Each access to `%chain.tmp` returns a fresh dirjail backed by a new temp directory on disk. Code holding the dirjail can read and write inside it but can't escape — same dirjail abstraction used everywhere else in `%fs`.

Three lifetime patterns; pick the one whose scope matches the work.

## Direct access

~~~caspian
$dir = %chain.tmp
$dir.write 'scratch.txt', 'some bytes'
~~~

The dirjail is auto-deleted when `$dir` goes out of the surrounding scope. No cleanup boilerplate.

## Block form

For lifetime tied to a specific block rather than the surrounding scope:

~~~caspian
%chain.tmp do($dir)
	$dir.write 'scratch.txt', 'some bytes'
end
# $dir is gone; the temp dir has been deleted
~~~

Created on block entry, deleted on block exit — whether the block returns normally, via early return, or via exception.

## Explicit close

For cases that need to release before the surrounding scope or block ends:

~~~caspian
$dir = %chain.tmp
# ... do work ...
$dir.close      # directory deleted now
~~~

After `.close`, the dirjail handle is unusable; subsequent operations raise.

## Properties

- **Each access produces an independent dirjail.** `$work = %chain.tmp` and `$archive = %chain.tmp` give two separate dirs.
- **Capability-gated.** Without the engine grant, `%chain.tmp` is absent or `null`. Explicit chain propagation only — a process with tmp does not automatically grant it to everything it calls.
- **Disk-backed.** Real OS temp directory, not in-memory. The motivating use case is "I need somewhere to put a huge file while I work on it"; in-memory storage falls down there.

## Concerns

- **Crash mid-block.** If the process hard-crashes inside the block, the OS's `/tmp` cleanup eventually sweeps the abandoned dir — but it may persist for a while first. Standard Unix posture.
- **Forked child outliving the block.** If a forked child is still writing in the temp dir when the parent's block ends, the dir disappears under the child. Best treated as a don't-do-that.
- **Untrusted code is an attack vector.** Granting tmp to untrusted code lets it touch real disk and intentionally abort to bypass block-exit cleanup, leaving data on disk. Mitigation: don't grant tmp to untrusted code. The explicit-only-down-the-chain rule already enforces this by default.

## `%engine` counterpart

`%engine.tmp` is the user-only access to the same capability.

## Testing

- **Direct access returns a dirjail** — `$dir = %chain.tmp` binds `$dir` to a dirjail handle.
- **Write and read inside the jail** — `$dir.write 'scratch.txt', 'some bytes'` followed by `$dir.read 'scratch.txt'` returns `'some bytes'`.
- **Fresh dirjail per access** — `$a = %chain.tmp; $b = %chain.tmp` yields two dirjails backed by distinct directories on disk (their paths differ).
- **Independence between calls** — a file written into `$a` is not visible via `$b`.
- **Path returned by handle** — the handle exposes an absolute path (via a `path` property or equivalent) that resolves under the OS temp directory.
- **Directory exists during scope** — while `$dir` is live, a host-side check (`stat` on the path) shows the directory exists.
- **Auto-delete on scope exit** — after the enclosing function returns and `$dir` goes out of scope, a host-side check on the path shows the directory no longer exists.
- **Block form creates on entry** — `%chain.tmp do($dir); # observe path; end` — the path exists during the block body.
- **Block form deletes on normal exit** — after a normal block exit, the path no longer exists.
- **Block form deletes on early return** — a `return` from inside the block still triggers cleanup; the path no longer exists after.
- **Block form deletes on raise** — a `raise` from inside the block still triggers cleanup; the path no longer exists after.
- **Explicit `.close` deletes immediately** — after `$dir.close`, a host-side check shows the directory gone.
- **Operations after `.close` raise** — `$dir.write 'x', 'y'` following `$dir.close` raises.
- **Cannot escape the dirjail** — `$dir.write '../escape.txt', 'x'` raises or is contained inside the jail (no file created outside the jail root).
- **Cannot read outside the dirjail** — `$dir.read '../../etc/passwd'` raises or resolves to a path inside the jail (not the real file).
- **Disk-backed not in-memory** — the returned path exists on the real filesystem (e.g., under `/tmp` or the platform equivalent), verifiable from outside the engine.
- **Default-denied across role boundaries** — a non-user role invoked without an explicit `%chain.tmp` grant sees it as absent / `null`.
- **Explicit grant reaches non-user role** — after the user grants `%chain.tmp` to a non-user role, that role can allocate its own dirjails.
- **Grant does not transit further without opt-in** — a non-user role holding `%chain.tmp` cannot pass it to a further-nested role without an explicit sub-grant.
- **Revoke ends access** — after `%chain.tmp` is revoked, the next access raises capability-not-granted.
- **Contents owned by the tmp faucet's role** — data written and re-read is owned by the tmp-faucet role attribution (verify via role introspection on the dirjail or its files).
- **Two roles' tmp dirs are isolated** — role A's `%chain.tmp` dir is not readable via role B's dirjail, even at the host-filesystem level (the dirjail restricts access).
- **`%engine.tmp` and `%chain.tmp` share the same capability** — verify the underlying implementation is one code path; a granted `%chain.tmp` does not conflict with the user's `%engine.tmp` access.
- **Nested block forms don't collide** — two nested `%chain.tmp do($x); ... %chain.tmp do($y); ... end; end` blocks get two distinct dirjails; both clean up in the right order.
- **Large-file write works** — writing a multi-megabyte file into a `%chain.tmp` dir succeeds (disk-backed, not memory-bound).
