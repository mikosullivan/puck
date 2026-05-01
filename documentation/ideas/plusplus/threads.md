# Threads

## Design Rationale

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

## Threading Model

Strictly speaking, KScript++ does not support threads. Instead, it provides an easy way
for processes to talk to each other.

A "thread" is just a fork that has access to a shared mikobase. Each fork runs a
single-threaded KScript interpreter independently. Forks do not share memory with each
other — all coordination happens through the mikobase.

This means KScript itself has no threading primitives. The mikobase is the entire coordination
mechanism.

See [mikobase.md](../mikobase.md) for the mikobase design.

---

## `%forks`

`%forks` is a system method (like `%call` and `%chain`) that returns the fork manager for
the current context.

### Spawning forks

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

### Spawning multiple identical forks

`times:` spawns N identical forks running the same block:

```
%forks.run(times: 4) do
end
```

This is equivalent to calling `%forks.run` in a loop four times.

### Passing mikobases into a fork

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

### `%forks.pool`

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

### Waiting and checking

```
%forks.wait    # block until all forks complete
%forks.done?   # non-blocking — returns true if all forks are done
%forks[:foo]   # access a named fork object
```

`%forks.wait` is still available for cases that need explicit control outside a pool.

### Detaching

`%forks.detach` spawns a fork that runs independently. It is not tracked by `%forks.pool`
or `%forks.wait` and the caller does not wait for it.

```
%forks.detach() do
end
```

---

## Sharing `%bucket` Through a Mikobase

Setting `include_private = true` on a mikobase causes `%bucket` to be backed by the mikobase for
any fork that connects to it. The fork's `@foo` reads and writes go directly to a live
object in the mikobase — child forks don't need to reference the mikobase explicitly at all.

```
$mikobase = %kiera['kiera.uno/mikobase/memory'].new
$mikobase.include_private = true

%forks.run(mikobase:$mikobase) do($mikobase)
    @foo = 'bar'    # reads and writes go directly to the mikobase
end
```

`%bucket` is synced to its own mikobase, not any mikobases that are explicitly passed through.

---

## Example: Parallel Report Generation

A company needs to generate monthly reports for 50 clients. Each report requires several
database queries. Running them serially takes minutes; in parallel, seconds.

```
%kiera['kiera.uno/mikobase/server'].run as $mikobase
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

`kiera.uno/mikobase/server` starts a managed mikobase server and yields it as `$mikobase`. Four
workers are spawned via `times: 4`. Each atomically grabs a client ID from the shared
queue (`.shift` triggers an exclusive lock), generates the report outside the lock, then
writes the result back. The pool waits for all four workers before returning. The server
shuts down cleanly when its block exits.

---

## Open Questions

- How are forks spawned at the process/OS level? (true OS fork, thread, coroutine?)
- How does a fork signal failure to the manager?
- Monitoring individual forks via `%forks[:foo]`. Design TBD.

---

## Future: Fork Restrictions

There should be a way to indicate that a forked process may not itself fork. This will be
part of the security model — untrusted code running inside a fork should not be able to
spawn its own forks. Design TBD.
