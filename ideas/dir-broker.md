# Dir broker

~~~vibecode
{"vibecode": {
	"doc": "ideas_dir_broker",
	"role": "spec for the dir-broker — the mechanism user uses to give other roles access to directories in the filesystem. Only user can work directly with the filesystem; every other role reaches the filesystem through a dir-broker handed to it by user. The dir-side of the brokers pattern (settled terminology for owner-authority narrowing objects). Constructor is $dir.broker(...); the earlier .dirjail(...) name is being retired — the object mediates access from OUTSIDE (callee code runs as itself, broker executes as user), so 'broker' is the correct semantic, not 'jail'. Existing spec on %fs still uses 'dirjail'; sweep pending.",
	"status": "early — read-only spec drafted; read-write, write-only TBD; broker/dirjail sweep across other docs pending"
}}
~~~

Brokers are how user gives access to directory objects. Only user can work directly with the filesystem. This spec explains how to use brokers to give access to directories in the filesystem to other roles.

## OS permissions are the ceiling

Brokers narrow, never escalate. A broker's permissions sit on top of the underlying OS file permissions and can never exceed them. `$dir.broker(write:true)` on a directory the user process only has OS-level read on gets you a handle whose writes still fail — the OS refuses before Caspian's grant matters. Caspian brokers are a per-callee narrowing layer, not a way to gain access the user itself doesn't have.

## Read-only

The read-only form:

~~~caspian
# as user
$dir    = %fs['/tmp/foo']
$broker = $dir.broker(read:true)

&some_utility $broker
~~~

Inside `&some_utility`, the callee holds `$broker`. The callee can:

- **Read file contents** — `$broker['config.json'].read`.
- **Enumerate** — `$broker.each`, `$broker.glob('*.log')`.
- **Traverse into subdirectories** — `$broker['sub']` returns a nested broker rooted at `/tmp/foo/sub/`, itself read-only. Nested brokers inherit the parent's permission set.
- **Query metadata** — file size, mtime, existence predicates. Read-adjacent, included in `read:true`.

The callee cannot:

- **Write, create, delete, rename** — every mutating method raises.
- **See outside the broker root** — `$broker['..']` raises. Absolute paths do not resolve; the callee sees the broker root as its own top.
- **Follow symlinks that point outside the broker root** — symlinks resolving outside `/tmp/foo/` behave as if the target doesn't exist.

`$broker.broker(read:true)` from inside `&some_utility` produces a further-nested read-only broker (subset-only downstream). Calling `$broker.broker(write:true)` from inside raises — a callee cannot elevate beyond what it holds.

Introspection uses the same predicates user has on a plain dir handle — because a broker IS a dir handle, just one running as user with a narrowed permission set:

~~~caspian
$broker.read?     # true
$broker.write?    # false
~~~

Each predicate composes the OS-level bit with the broker's own permission set: `.read?` is true when the OS allows reads AND the broker was granted `read:true` at construction. No separate `.can?(...)` or `.permissions` accessor — the surface is the surface user already knows.

Block form:

~~~caspian
$dir.broker(read:true) do ($broker)
	&some_utility $broker
end
# $broker is destroyed at end of block
~~~

The broker created by the block form is **destroyed** when the block exits — normally, via `raise`, or from any other exit path. Destruction is structural, not just out-of-scope: any later call on `$broker` raises, including calls made through references captured elsewhere (a closure that grabbed it, a hash that stored it, another object that received it as a constructor argument). The object itself is dead; every handle to it is dead.
