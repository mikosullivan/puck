# Forking and Concurrency

~~~json
{"vibecode": {
	"doc": "plusplus-threads",
	"role": "Charlie++ design notes for forking and concurrency; threads are forks with a shared mikobase as the sole coordination mechanism, so Charlie itself has no threading primitives",
	"key_concepts": ["forking_model", "mikobase_as_coordination", "no_shared_memory",
		"forks_and_tmp", "single_threaded_charlie"],
	"status": "brainstorm"
}}
~~~

<a id="design-rationale"></a>
## 1 Design Rationale

Traditional threads share a memory space and leave access management to the developer —
locks, mutexes, semaphores. These primitives are easy to misuse and the bugs they produce
(race conditions, deadlocks) are among the hardest to diagnose.

This design inverts that. Forks are isolated by default. Shared state is not an accident
waiting to happen — it requires a deliberate decision to put something in the mikobase. The
discipline is enforced by the architecture, not by the developer remembering to do the
right thing.

Because a mikobase can be file-backed or served over a network, shared state can also be
persistent and distributed. A traditional thread pool cannot survive a process restart.
A mikobase can.

---

<a id="threading-model"></a>
## 2 Threading Model

Strictly speaking, the forking feature does not provide threads. Instead, it provides an
easy way for processes to talk to each other.

A "thread" is just a fork that has access to a shared mikobase. Each fork runs a
single-threaded Charlie interpreter independently. Forks do not share memory with each
other — all coordination happens through the mikobase.

This means Charlie itself has no threading primitives. The mikobase is the entire coordination
mechanism.

See [mikobase.md](../../mikobase/mikobase.md) for the mikobase design.

---

<a id="forks-and-tmp"></a>
## 3 `%forks` and `%tmp`

Forking is a standard Charlie feature, but it requires explicit engine permission. The
engine grants it by providing `%forks` and optionally `%tmp` — both are `null` if the
engine did not grant the corresponding permission.

```
if %forks
    %forks.run do
    end
end
```

`%tmp` returns a directory object for a temp path the engine has designated for this
process. It is `null` if not granted. Forked server processes use it to create Unix domain
socket files:

```
if %tmp
    $socket_path = %tmp.file("server.sock")
end
```

Both permissions are independent. An engine can grant `%tmp` without granting `%forks`,
or vice versa. A process that needs to set up a socket server needs both.

---

`%forks` is a system method (like `%call` and `%chain`) that returns the fork manager for
the current context.

<a id="spawning-forks"></a>
### 3.1 Spawning forks

`%forks.run` spawns a fork immediately, returns a process object, and does not block.
The returned process object is the same object stored in the `%forks` pool:

```
$process = %forks.run() do
end
```

The `do` block is the entire body of the forked process. When the block finishes, the
process exits. It does not continue executing any code after the block.

The optional name registers the fork so it can be retrieved later by name. The returned
object and the pooled object are identical:

```
$process = %forks.run(:foo) do
end

$process == %forks[:foo]   # true — same object
```

<a id="spawning-multiple-identical-forks"></a>
### 3.2 Spawning multiple identical forks

`times:` spawns N identical forks running the same block:

```
%forks.run(times: 4) do
end
```

This is equivalent to calling `%forks.run` in a loop four times.

<a id="passing-mikobases-into-a-fork"></a>
### 3.3 Passing mikobases into a fork

Forks are separate processes and cannot inherit the parent scope. Data must be passed in
explicitly. `mikobase:` and `mikobases:` are equivalent and merge — both accept a single mikobase or
an array of mikobases. Block parameters declare which mikobases are available inside the fork:

```
%forks.run(mikobase:$a) do($a)
end

%forks.run(mikobases:[$a, $b]) do($a, $b)
end
```

Forks do not belong to mikobases. A process simply holds references to mikobase objects and can
reference as many as needed.

<a id="forkspool"></a>
### 3.4 `%forks.pool`

`%forks.pool` is a structured concurrency boundary. It runs its block and waits for all
forks spawned within it to complete before returning. The caller blocks until the pool
is done:

```
%forks.pool do
    %forks.run(times: 4) do
    end
end
# all 4 forks are done here
```

`%forks.pool` is the standard way to coordinate a group of forks. It replaces manual
`%forks.wait` calls in the common case.

<a id="waiting-and-checking"></a>
### 3.5 Waiting and checking

```
%forks.wait    # block until all forks complete
%forks.done?   # non-blocking — returns true if all forks are done
%forks[:foo]   # access a named fork object
```

`%forks.wait` is still available for cases that need explicit control outside a pool.

<a id="detaching"></a>
### 3.6 Detaching

`%forks.detach` spawns a fork that runs independently. It is not tracked by `%forks.pool`
or `%forks.wait` and the caller does not wait for it.

```
%forks.detach() do
end
```

---

<a id="objectfork-forking-a-single-object"></a>
## 4 `object.fork` — Forking a Single Object

`object.fork` spawns N forks that all share a single object's `%bucket`. The object is
passed into each fork as a block parameter:

```
$color = %puck['puck.uno/color'].new(hex: '#ff0000')

$color.object.fork(20) do($c)
    $c.red = 128
end
```

`object.fork` blocks until all forks complete — pool semantics, no separate
`%forks.wait` needed.

Under the hood it is sugar for setting up a mikobase with `include_private = true`
scoped to just this object's `%bucket`, spawning N forks via `%forks.pool`, and passing
the object in as the block parameter. The caller sees none of that machinery.

---

<a id="sharing-bucket-through-a-mikobase"></a>
## 5 Sharing `%bucket` Through a Mikobase

Setting `include_private = true` on a mikobase causes `%bucket` to be backed by the mikobase for
any fork that connects to it. The fork's `@foo` reads and writes go directly to a live
object in the mikobase — child forks don't need to reference the mikobase explicitly at all.

```
$mikobase = %puck['puck.uno/mikobase/memory'].new
$mikobase.include_private = true

%forks.run(mikobase:$mikobase) do($mikobase)
    @foo = 'bar'    # reads and writes go directly to the mikobase
end
```

`%bucket` is synced to its own mikobase, not any mikobases that are explicitly passed through.

---

<a id="example-parallel-report-generation"></a>
## 6 Example: Parallel Report Generation

A company needs to generate monthly reports for 50 clients. Each report requires several
database queries. Running them serially takes minutes; in parallel, seconds.

```
%puck['puck.uno/mikobase/server'].run as $mikobase
    $mikobase['clients'] = &get_client_list
    $mikobase['reports'] = []

    %forks.pool do
        %forks.run(mikobase: $mikobase, times: 4) do($mikobase)
            $running = true

            while($running)
                $client_id = $mikobase['clients'].shift

                if($client_id)
                    $report = &generate_report($client_id)
                    $mikobase['reports'] << $report
                else
                    $running = false
                end
            end
        end
    end

    &email_reports($mikobase['reports'])
end
```

`puck.uno/mikobase/server` starts a managed mikobase server and yields it as `$mikobase`. Four
workers are spawned via `times: 4`. Each atomically grabs a client ID from the shared
queue (`.shift` triggers an exclusive lock), generates the report outside the lock, then
writes the result back. The pool waits for all four workers before returning. The server
shuts down cleanly when its block exits.

---

<a id="open-questions"></a>
## 7 Open Questions

- How are forks spawned at the process/OS level? (true OS fork, thread, coroutine?)
- How does a fork signal failure to the manager?
- Monitoring individual forks via `%forks[:foo]`. Design TBD.

---

<a id="future-fork-restrictions"></a>
## 8 Future: Fork Restrictions

There should be a way to indicate that a forked process may not itself fork. This will be
part of the security model — untrusted code running inside a fork should not be able to
spawn its own forks. Design TBD.
