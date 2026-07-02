# `%chain.tmp`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_tmp",
	"role": "spec for %chain.tmp — fresh temp dirjail per access; auto-deleted when the handle leaves scope (or on explicit .close, or on block exit). Disk-backed, not in-memory."
}}
~~~

**Default-granted across role boundaries:** no.  

Each access to `%chain.tmp` returns a fresh dirjail backed by a new temp directory on disk. Code holding the dirjail can read and write inside it but can't escape — same dirjail abstraction used everywhere else in `%chain.root`.

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
