# Jasmine

A logging format. Named after one of Miko's cats.

---

## Overview

Jasmine is a logging format derived from **JSONL** (JSON Lines) with
a few tweaks specific to the Kiera ecoverse.

### Terminology

- A **log** is a collection of entries. Typically a single file
  appended to over time, but conceptually any stream of entries.
- An **entry** is a single JSON object in a log — one line in the
  JSONL file.
- **`%chain.log`** is named "log" rather than "entry" because that's
  what developers will reach for intuitively, but strictly speaking
  it holds a single **entry** under construction — the one being
  built for the current operation. The actual log (the file it
  eventually gets written to) is a separate thing the framework
  manages.

**Primary use case: Robinson.** Jasmine was originally motivated by
[Robinson](../http-middleware/robinson.md), the filesystem-tree HTTP
server — capturing request/response data, errors, and other events
from filesystem-tree-served sites. (Note: Robinson and
[Dogberry](../../ideas/dogberry.md) are independent HTTP middleware
peers; Robinson is *not* a Dogberry handler, despite earlier docs
having framed it that way.) The design isn't Robinson-specific —
Jasmine is suitable for any logging scenario where its tweaks
(corruption tolerance, ecoverse-specific conventions) are useful.
Application logs, audit trails, event streams, and similar
log-shaped data fit naturally.

The JSONL baseline:

- Each log entry is a complete JSON value on its own line.
- File grows by appending one line at a time — streamable, no
  outer array or closing structure to maintain.
- Each line parses independently, so partial reads or corruption
  affect only their own line.
- Compatible with line-oriented Unix tools (`grep`, `awk`, `tail`,
  etc.) for ad-hoc inspection.

Jasmine adopts that baseline and adds format-specific tweaks for
ecoverse needs. The tweaks are detailed below.

---

## Differences from JSONL

### Malformed lines are silently ignored

If a line cannot be parsed as JSON, **Jasmine readers skip it
without error**. Strict JSONL implementations vary — some halt on a
bad line, some raise — but Jasmine standardizes on quiet
tolerance: bad lines are just skipped, and the next valid line is
processed normally.

The motivation is practical:

- **Truncation tolerance.** A log file cut off mid-line (process
  killed, disk full, etc.) leaves a partial line at the tail.
  Strict parsers would refuse to process the whole file or stop
  reading. Jasmine readers skip the partial line and continue.
- **Corruption tolerance.** Disk errors, accidental file edits, or
  concurrent writes from misbehaving producers can introduce
  malformed lines anywhere in the file. Jasmine extracts every
  valid line it can find, even if surrounding lines are damaged.
- **Concurrent-writer tolerance.** Multiple processes appending to
  the same log file can race; if one's write gets interleaved or
  truncated, that's one bad line, not a broken log.

The trade-off is **silent data loss**: corrupted lines just vanish.
For a logging format that's acceptable — logs are append-only and
we'd rather lose a few lines than the whole file. Producers that
need strict guarantees about every line getting through should
include their own integrity mechanisms (checksums in the JSON,
sequence numbers, etc.).

## Specification

### Required fields

Every Jasmine entry **must contain two fields**:

- **`uuid`** — a unique identifier for the entry.
- **`timestamp`** — when the entry was generated.

The minimal valid entry contains exactly these two fields:

```json
{
    "uuid": "[some uuid]",
    "timestamp": "[some timestamp]"
}
```

(Examples in this doc are pretty-printed across multiple lines for
readability. In practice every Jasmine entry occupies a single
line in the file — that's how JSONL works.)

Beyond these two fields, an entry can have any number of additional
fields specific to the application using Jasmine (event type, request
path, error message, structured data, etc.).

Format conventions:

- **`uuid`**: a fully random UUID (UUIDv4).
- **`timestamp`**: format spec'd separately (ISO 8601 with
  millisecond precision is the working assumption).

### Conventional fields

Beyond the required `uuid` and `timestamp`, Jasmine reserves certain
top-level field names for specific kinds of structured content.
These are **conventions** — not required, but if a producer uses
them, they should follow the documented shape so consumers can rely
on it.

#### `success` (outcome flag)

For operations that have a meaningful pass/fail outcome (a request
handled, a job run, a transaction completed), the entry carries a
top-level **`success`** field. The value is **truthy or falsey** —
strict `true`/`false` is the norm, but any JSON value works since
consumers read it as a boolean check.

Not all entries have a `success` field. Some kinds of logged events
don't really have a pass/fail outcome (a startup notice, a periodic
heartbeat, a structural marker). When there's no meaningful
success/failure to record, leave the field off.

**When present, `success` is conventionally the *first* field in
the entry.** It's the highest-signal piece of information for
scanning a log — putting it first means grep, jq, and human eyes
all see it before anything else.

**The idiom: start `false`, flip to `true` on success.** Set
`"success": false` when the entry is created, then update it to
`true` only if the operation completes successfully. The benefit is
crash-safety — if the operation aborts (crash, kill, uncaught
exception, anything that prevents the explicit flip), the entry
remains `false`, which is the correct outcome. No special handling
needed for failure cases; failure is the default.

```json
{
    "success": true,
    "uuid": "[some uuid]",
    "timestamp": "[some timestamp]"
}
```

#### `web` (request/response data)

When Jasmine is used to log HTTP traffic (Robinson's primary case),
each entry carries a top-level **`web`** field. The `web` field
contains exactly two sub-fields: **`request`** and **`response`**.

```json
{
    "success": true,
    "uuid": "[some uuid]",
    "timestamp": "[some timestamp]",
    "web": {
        "request": {
            "method": "GET",
            "path": "/some/path",
            "host": "example.com",
            "...": "..."
        },
        "response": {
            "status": 200,
            "duration_ms": 47,
            "bytes": 12480,
            "...": "..."
        }
    }
}
```

The two sub-fields are paired by structure — every `web` entry has
both. `request` holds details of what came in; `response` holds
details of what went out.

The detailed shape of `request` and `response` (which fields are
standard, which are optional, privacy considerations for things
like IP/user-agent, etc.) is its own spec — to be filled in as
Robinson's logging needs become more concrete.

## Loggers and entries

Two distinct concepts:

- A **Jasmine logger** is an object. The developer creates as many
  as they want, each configured with its own stores (dirjail, etc.).
  Use it explicitly: `$my_log.entry do ... end`.
- An **entry** is a single record written to a logger's stores. An
  entry exists for the duration of a scoped block — the
  `.entry do ... end` primitive — and gets flushed on block exit.

### Creating a logger

```
$log = %['kiera.uno/jasmine'].new(dir: $some_dirjail)

$log.entry do($entry)
    # %chain.log access works here if %chain.log is this logger;
    # otherwise just operate on $entry directly
    do_work()
end
```

A developer can create many loggers and use each explicitly.

### The engine-granted main logger: `%chain.log`

There is a special "main" logger that lives at **`%chain.log`** —
the ambient logging access point for the chain. **`%chain.log` is
always present**, and **only the engine can configure what it
points at.** User code cannot assign to `%chain.log`; the engine
decides what destinations (if any) it has, the same way it grants
`%forks`, `%tmp`, or `%utils`.

If the engine configured destinations, `%chain.log` is a real
logger writing to those destinations. If it didn't, `%chain.log`
is still a logger — just a **dev/null logger with zero stores**.
Writes succeed but go nowhere. The existing no-writers nanny
(see [Constructing a Jasmine log](#constructing-a-jasmine-log))
warns when entries are created on a zero-store logger; the
`no_writers_ok` flag silences the warning if discarding is
intentional.

The benefit: developer code can sprinkle `%chain.log[key] = value`
calls everywhere without `if %chain.log` guards. The logger is
always there; the question is just whether anyone's listening on
the other end.

(Possible future relaxation: allow user code to replace
`%chain.log` if real demand surfaces. Not in v1.)

### The ambient idiom

When `%chain.log` is granted, the ambient pattern is:

```
%chain.log.entry do
    %chain.log['user_id'] = $user.id
    %chain.log['cache_hit'] = true
    do_work()
end
```

Inside the block, writes via `%chain.log[key] = value` go to the
just-started entry. Code anywhere in the call stack can write —
that's the "ambient" part. When the block exits (normally or via
exception), the entry is flushed to the main logger's stores.

The block parameter (`$entry`, when written `do($entry)`) is the
entry object itself, available for code that wants explicit
access. Most code doesn't need it and omits the parameter.

### No null check needed

Because `%chain.log` is always a logger (real or dev/null), code
can write to it unconditionally:

```
%chain.log.entry do
    %chain.log['something'] = $value
end
```

If destinations are configured, the writes flow there. If not,
the writes are discarded (with a one-time nanny warning unless
`no_writers_ok` is set). Either way, no `if %chain.log` guards
clutter the code.

A nice side effect: `%chain.log[key] = value` calls double as
**documentation of intent**. Even when nothing is captured, the
code articulates what *would* be logged at each point — readable
notes that don't rot.

### Lifecycle (entries)

- **Created** by `.entry do(...) ... end` on a logger.
- **Mutated** throughout the block: writes via `%chain.log[...]`
  (for the engine-granted ambient) or directly via the entry object
  (for an explicit logger).
- **Flushed** to the logger's stores when the block exits — normal
  return, exception, or any other unwind.

A framework like Sinatra wraps each request in `%chain.log.entry do`
internally, so per-request logging Just Works for handler code; the
developer didn't have to write the wrapper themselves.

### Automatic exception recording

When an exception propagates out of a `.entry do` block, Jasmine
**records the exception into the entry before flushing**. The
record typically includes the exception type, message, source
location (line / file when available), and any other fields the
exception carries.

```json
{
    "uuid": "...",
    "timestamp": "...",
    "exception": {
        "type": "kiera.uno/error/something",
        "message": "...",
        "line": 142,
        "file": "..."
    },
    "calls": [...]
}
```

The exception is still **re-raised** after recording — Jasmine
doesn't swallow it. The recording is an observation, not a catch.
The exception continues unwinding the stack and is caught (or not)
by whoever was going to catch it anyway.

**On by default.** Jasmine is a debugging tool as much as a
request logger; capturing what went wrong is exactly the thing a
debugging tool should do. Most general-purpose logging libraries
(log4j, structlog, Sentry, etc.) do this by default for the same
reason. A developer who wants quiet logs can disable it; the
common case — "what failed and where?" — comes for free.

**Disabling.** A per-logger flag (working name `record_exceptions
= false`) turns it off. Per-entry override possible later if a
real use case surfaces.

**Redirects don't trigger this** because redirects (`response.redirect.permanent`
and friends, see Sinatra's response model) are caught by the
framework *inside* the entry scope — they never propagate out of
`.entry do`. From Jasmine's perspective, a redirect is a normal
exit. If a redirect ever does escape, **that's a framework bug**
and the auto-recording correctly surfaces it rather than hiding
it.

### Automatic warning capture

**`.entry do` implicitly heeds all warnings raised inside it.**
Any `%chain.warn` (or `.raise` on a warning object) anywhere
inside the entry — at any depth — is captured by the entry and
recorded in its `warnings` array. Warnings do not need to
"escape" the entry to be recorded, the way exceptions do; the
entry catches them actively.

The captured warning is recorded using the **same shape Xeme
uses** for its `warnings` array — a flat entry of
`{"id": ..., "details": {...}}` (plus class info when relevant).
Jasmine and Xeme are meant to look alike; the shared shape means
a tool that reads a Xeme's warnings can read a Jasmine entry's
warnings without translation, and vice versa.

```json
{
    "uuid": "...",
    "timestamp": "...",
    "warnings": [
        {"id": "duplicate_cookie_name",
         "details": {"name": "session", "scopes": [...]}}
    ],
    "calls": [...]
}
```

**On by default.** Same reasoning as exception recording: a
debugging tool that drops warnings is missing half its job. The
common case ("what's noisy in this request?") comes for free.

**Disabling.** Per-logger flag (working name
`record_warnings = false`) turns the capture off. With it off,
warnings propagate up the stack as normal; an outer `heed()`
might still collect them.

**Interaction with explicit `heed()`.** An inner `heed('class')`
block still works as written — it catches the warning before
Jasmine's implicit catch sees it. Jasmine's capture is the
catch-all at the entry boundary; explicit `heed`s inside are
finer-grained collectors that get first crack.

### Logger failure cascade

If Jasmine itself fails to record (downstream service down, disk
full, store rejected the entry, etc.), the original event is
**not silently swallowed**. Jasmine falls back to stderr with a
`[JASMINE FAILED]` marker followed by the original event in
plain form:

```
[JASMINE FAILED: <reason>] <original event as JSON>
```

The fallback is intentionally crude — stderr is the last resort
when everything else has failed, and a working log should be
restored as quickly as possible. But the event is preserved
somewhere a human can see it. Operators monitoring stderr will
notice the marker and know to look.

This prevents the classic "the bug that broke logging was the
bug we needed the logs to find" scenario. The cascade also
applies recursively: if writing to stderr itself fails (rare),
the failure is silently absorbed — at that point the host
environment is too broken for Jasmine to help.

### Nested call frames

**When an entry is active (we're inside a `.entry do` block), every
KScript function call gets its own fresh nested entry.** The called
function sees a new, empty entry — it cannot read or write the
caller's entry. When the function returns, if it wrote anything to
its entry, that entry is appended to the **parent's `calls`** array
as a nested frame. The result is a tree of log entries that mirrors
the call tree.

The "every KScript function call" rule is the simplest model to reason
about: either logging is on for this operation and every function
participates, or logging is off and nothing happens. No middle ground,
no per-function opt-in or out.

**Zero overhead when logging is off.** If no entry is active, no
per-call frames are allocated at all. Functions called outside an
entry block behave exactly as they always have; the nesting
machinery only kicks in when there's a log entry to extend.

The structure of an assembled entry:

```json
{
    "uuid": "...",
    "timestamp": "...",
    "web": { "request": "...", "response": "..." },
    "calls": [
        {
            "function": "process_request",
            "entry": {
                "cache_hit": true,
                "calls": [
                    {
                        "function": "authenticate",
                        "entry": {
                            "user_id": "abc123",
                            "calls": [ "..." ]
                        }
                    }
                ]
            }
        }
    ]
}
```

Each call frame contains:

- **`function`** — identifier for the function that generated the
  frame.
- **`entry`** — the Jasmine entry that function built up. May
  contain its own `calls` array of further nested frames.

The framework manages this transparently: when a function is about
to be called, the framework pushes a fresh empty entry; when it
returns, the framework appends the entry to the parent's `calls`
(if non-empty). User code just writes to `%chain.log` as normal.

### Why this design

This solves several things at once:

- **Untrusted code is structurally contained.** Each function only
  sees and writes its own entry. Can't exfiltrate from the caller's
  entry (it's a different frame, invisible). Can't inject into the
  caller's entry (only the framework knows where to append). Can't
  pollute the caller's log (its writes go into its own bucket; the
  framework decides whether to include it).
- **Free debugging / observability.** The call tree IS the log.
  Every function's contribution is structurally distinguishable
  from every other's. Reading a Jasmine entry gives you a complete
  account of which function did what.
- **Library authors can use `%chain.log` freely.** No risk of
  polluting their callers' audit trails. No coordination between
  unrelated libraries.
- **Composability.** Two libraries that both log don't conflict.
  Their entries nest under their own call frames.

### Empty entries are omitted

If a function doesn't write anything to its `%chain.log`, **no
frame is appended** to the parent's `calls` array on return. This
keeps the noise to a minimum — only functions that actually
recorded something contribute to the tree.

The flip side: there's no record that "function X was called but
recorded nothing." For most use cases this is the right tradeoff —
the noise of every trivial call ballooning the tree isn't worth it.

**Possible future feature:** if there's ever real demand for a
complete call record (every function call recorded whether it
wrote anything or not), the framework could expose that as an
opt-in mode (a configuration flag, a per-request setting, etc.).
Not in scope for v1; noted here so the option isn't forgotten.

### Source line numbers in frames

For code that originated from KScript source (rather than being
hand-written KScriptJSON), each call frame can include the source
line number where the call was made. This is enabled by
[KScriptJSON's source-position annotations](../kscriptjson.md#source-position-annotations)
— the KScript-to-KScriptJSON transpiler preserves line numbers on
emitted nodes, and the runtime exposes the current executing
position to consumers like Jasmine.

In Jasmine entries, this typically lives in the function identifier
or as a separate `line` / `file` field on the frame — exact shape
spec'd alongside the function-identifier format.

When the code didn't originate from KScript source (e.g.,
hand-written KScriptJSON, generated code with no known source
line), the field is absent. Tools just check for presence.

### Interaction with %chain's role-boundary wipe

The nested-frame design naturally handles cross-role calls: the
called role sees a fresh `%chain.log`, just as it sees a wiped
`%chain` in general. Any entries it writes go into its own frame.
When control returns, that frame is appended to the parent's
`calls` (if the called role wrote anything).

This replaces the earlier discussion of "role-boundary handling for
logging" as a future question — the nested-frames design *is* the
answer. Untrusted code gets its own sandboxed frame; the caller
sees what the callee recorded only after the call returns, as part
of the assembled tree.

The security properties are intact:

- Untrusted code can't read the caller's log (different frame).
- Untrusted code can't inject directly into the caller's log (its
  contribution is structurally tagged as its own frame).
- Trusted code can read what untrusted code recorded only at the
  end-of-call merge, in clearly attributed form. That's the audit
  trail working as intended.

---

## Stores

Jasmine separates **what to log** (entries, the format) from **where
they live** (the store). Stores are pluggable; one Jasmine producer
can be configured with multiple stores, and each entry fans out to
all of them.

A **store** is anything that holds Jasmine entries — handles
writing, and where applicable reading. The architecture is built
around an abstract **store class** with concrete subclasses for
each destination kind:

- **Directory store** — holds entries in files inside a directory.
  (Ships in v1.)
- **Memory store** — copies each entry to an in-process location
  (an array, a callback, a stream consumer, etc.). Useful for
  tests, in-process aggregation, and piping logs to other parts of
  the program. Not spec'd yet. (Future.)
- **Database store** — holds entries in a database table.
  (Future.)
- **Webhook store** — POSTs entries to an HTTP endpoint. Write-only;
  cannot be read back. (Future.)
- Others as needed.

Only the directory store ships in v1. The others remain pluggable
extension points; community or future work can fill them in.

### Constructing a Jasmine log

There is one class — **`kiera.uno/jasmine`** — for all Jasmine logs.
The constructor takes keyword arguments that configure which
store(s) the log uses. Each keyword names the kind of store:

```
$log = %kiera['kiera.uno/jasmine'].new(dir: '/path/to/directory')
```

The example above produces **a single log object with one store** —
a directory store pointed at the given path. Other store kinds use
different keyword names (`db:`, `webhook:`, etc.) once their
implementations land. For v1, **only `dir:` is supported**.

The shortcut form (one keyword arg, sensible defaults for
everything else) is what most users will use. The underlying setup
is more elaborate (file rotation, naming, etc. — details below);
defaults cover the common case.

**A log with no stores raises a warning when an entry is created on
it.** Constructing a Jasmine log with no store keyword arguments is
syntactically allowed (the object exists, you have a reference),
but the moment something tries to create an entry through it, a
warning fires — there's no destination for the entry to land in, so
the entry would be dropped silently. The warning surfaces the
common misconfiguration of forgetting to wire up a store. Silently
dropping entries would be worse than nagging.

**Suppressing the warning: `no_writers_ok`.** A log object exposes a
**`no_writers_ok`** property (also settable via constructor keyword)
that quiets the no-stores warning. When `no_writers_ok` is truthy,
creating an entry on an empty log is silent — entries are still
dropped, but the framework trusts the developer made that choice
deliberately:

```
$log = %kiera['kiera.uno/jasmine'].new(no_writers_ok: true)
# or
$log.no_writers_ok = true
```

This is an example of a **"Don't worry nanny" feature**: the
framework's default behavior is to warn about a likely mistake, but
the developer can flip a flag to indicate "I know, this is
intentional, hush." Part of Mikobase's no-nanny-code philosophy —
the nanny is on by default to catch real bugs, but it doesn't
override developer choice when the developer explicitly opts in.

### Directory store: file layout

The directory store organizes entries by **calendar date**. Each
day's entries go into a file named with the date:

```
2022-04-01.jasmine
2022-04-02.jasmine
2022-04-03.jasmine
```

When an entry is to be written, the directory store appends it to
the file for the current date. **If the file doesn't yet exist, it
is created automatically.** No manual setup required; the directory
just needs to be writable.

At midnight (local-date rollover), entries start going to the new
day's file automatically. No explicit rotation logic; the rollover
falls out of the naming scheme.

**Finer-grained naming** (per-hour, per-size, per-process, etc.) is
**not in v1**. The daily-rollover scheme is intentionally simple —
it covers the common case and produces readable, navigable
directories. If real demand emerges for more granular naming, we
can layer it on without breaking the daily default.

**Time zone is intentionally left unspecified** for the date in the
filename. The filename's date is for coarse grouping; precise time
information lives on each entry's `timestamp` field, which carries
a full timestamp including time zone. The filename's date would be
redundant information at best. If a real need emerges to pin
filename-date semantics (e.g., to enforce UTC across a fleet), we
can address it then.

### Reaping

The directory store supports a **reaping** pattern: a routine that
walks the file looking for unreaped entries, yields each to a
closure, then marks the entry as reaped. Reaping marks an entry by
**replacing its leading `{` with `#`**. The line becomes unparseable
JSON, but otherwise intact:

```
Before:  {"timestamp": "...", "uuid": "...", "web": {...}}
After:   #"timestamp": "...", "uuid": "...", "web": {...}}
```

On the next pass — and to any other Jasmine reader — the reaped
line is silently skipped via the malformed-line tolerance rule.
The line itself signals its reaped state; no separate flag, no
external tracking. The reaped line remains readable for forensic
inspection (you can still grep or eyeball it), it's just no longer
processed as an entry.

Idempotent: running reap twice doesn't double-process anything.
Single-byte change preserves the file's overall structure (no
length shifts, no offset corruption).

### Concurrency: the format's emergent gift

Because reaping only modifies single bytes in the middle of the
file (and only on lines that aren't being touched by writers),
**the reaper does not need an exclusive lock on the log file**.
Other processes can be appending entries at the same time without
coordinating with the reaper. Concretely:

- **Writers append to the end** of the file. They acquire an
  exclusive lock on **`write.lock`** (a sentinel file in the
  directory) briefly to prevent two writers from interleaving. The
  lock is held only long enough for the append (one line) — very
  fast, no traffic jam.
- **Reapers modify bytes in the middle** of the file. They don't
  contend for `write.lock`, because they're not appending. Their
  single-byte modifications are atomic at the OS level (POSIX
  `pwrite` at a specific offset). Reapers coordinate among
  themselves via **`reap.lock`** — see "Reaper coordination" below.
- **Readers (parsers, queries) don't lock at all.** They just
  stream through, skipping malformed lines (including reaped
  ones). Multiple readers run concurrently without coordination.

This is "lock-free reads, brief append locks, no read/write
contention" — a really nice concurrency property that falls out of
the format design rather than being engineered separately.

Notes on edge cases:

- **Multiple reapers**: coordinated via `reap.lock`. See "Reaper
  coordination" below.
- **File deletion**: handled by a separate routine — see "Purge"
  below. The reaper itself never deletes files.
- **Reaper crash mid-closure**: if a reaper yields an entry to its
  closure but crashes before marking the line, the next reaper run
  reprocesses that entry. This is **at-least-once delivery**
  semantics — preferable to at-most-once for most logging
  pipelines, but it means closures should be idempotent.
- **File rotation mid-reap**: the reaper operates on the file as
  it exists when it starts. Once a day rolls over and new entries
  go to a new file, the reaper either picks up the new file on its
  next run or runs a separate per-file reap pass.

### Reaper coordination

To prevent multiple reapers from processing the same entries, the
directory store uses a **sentinel lock file** named `reap.lock`
inside the log directory:

```
2022-04-01.jasmine
2022-04-02.jasmine
reap.lock
write.lock
```

Every reaper must acquire an **exclusive lock on `reap.lock`**
before reaping. The lock serializes reapers across processes (and
across machines, where the filesystem supports advisory locking).
The file's contents don't matter — it exists purely as a lock
target. The store creates it automatically if it doesn't exist.

**Default behavior: non-blocking.** If a reaper can't acquire the
lock (because another reaper is already running), it **doesn't
wait** — it just moves on with whatever else it was doing, skipping
reaping for this cycle. The reasoning:

- Reaper hangs are worse than missed reaps. A reaper waiting
  indefinitely on a lock isn't useful work; missing one reap cycle
  is.
- Reaping is typically idempotent and periodic. The next scheduled
  pass picks up where this one left off.
- Blocking could pile up multiple reapers all waiting on the same
  lock — a traffic jam that's worse than the original problem.

Why a separate file rather than locking the log file itself:

- Locking the log file would block **writers** too. Writers and
  reapers don't actually conflict (writers append; reapers
  modify mid-file bytes), so they shouldn't compete for the same
  lock.
- A separate lock file only coordinates **reapers among themselves**.
  Writers proceed without contention.

The non-blocking default can be overridden — a reaper can be
configured to block on the lock if a use case actually needs strict
serialization (e.g., the next reap cycle won't run for a long time).
Exact API for this TBD.

### Purge

The reaper marks entries as processed but **does not delete files**.
Over time the directory accumulates files whose entries are entirely
reaped — they parse to nothing, take up disk space, and clutter the
listing. A separate **purge** routine handles cleanup.

Purge is conceptually distinct from reaping:

- **Reaper**: walks one log file, yields each entry to a closure,
  marks each as processed (`{` → `#`). No file-level changes.
- **Purge**: walks the directory, identifies files whose entries
  are all marked (i.e., the file contains no parseable entries
  anymore), and deletes those files.

The two routines have different responsibilities and run on
different schedules. A typical setup might run reaping frequently
(every few minutes) and purge much less often (once a day, or once
a week). They don't need to coordinate with each other directly.

#### Locking

Purge acquires `write.lock` **per file**, not for the whole purge
run. For each candidate file:

1. Acquire exclusive lock on `write.lock`.
2. Scan the file — does any line parse as a Jasmine entry?
3. If no: delete the file. If yes: leave it alone.
4. Release the lock.
5. Move to the next candidate.

The reason for per-file granularity: if a purge cycle is working
through a large backlog (hundreds or thousands of stale files), we
don't want it to tie up writers for the entire sweep. Per-file
acquire/release keeps any individual writer's wait short — at most
the duration of one file scan, which is fast.

Why `write.lock` rather than a separate purge lock:

- Purge and writers genuinely conflict — a writer creating a fresh
  file for today's date can race against purge deleting a file that
  just became empty. Using the same lock prevents that race.
- Purge and reapers don't conflict — reapers only modify bytes
  inside files; if purge deletes a file the reaper was about to
  process, the next reaper run simply finds nothing to do. No
  corruption risk.
- One fewer lock file to think about.

By default purge **blocks** when acquiring `write.lock` for each
file (unlike the reaper's non-blocking default on `reap.lock`).
Purge runs rarely and needs to complete its work; missing a purge
cycle isn't useful. The wait is brief in practice because each lock
acquisition only spans a single file's scan + possible unlink.

#### What counts as "empty"

A file is eligible for purge when **no line in it can be parsed as
a Jasmine entry** — every line is either malformed, a reaped entry
(leading `#`), or some other non-JSON content. The check is the
same one any Jasmine reader does; if iterating the file yields zero
entries, the file is empty from Jasmine's point of view and can be
removed.

This definition handles the common edge cases naturally:

- A file with only reaped entries → purge-eligible.
- A file mid-rotation that just got a fresh entry → not eligible
  (has at least one parseable entry).
- A file someone hand-edited into a mess → eligible if no line
  parses, otherwise left alone.

**Configurable: should today's file be deletable?** Both purge
modes expose an option for whether the current-date file is
eligible when empty. The defaults differ:

- **Scheduled-purge mode default: `true`** — today's file can be
  deleted if empty. Worst-case churn is "delete the empty file,
  the next entry recreates it" once per scheduled run, which is
  negligible.
- **wrp mode default: `false`** — today's file is skipped. In
  write-reap-purge mode purge runs after every entry, so if
  today's file were deletable when empty, every reap that cleared
  it would be followed by a purge deleting it and the next entry
  recreating it — delete-and-recreate churn at the per-entry
  cadence. Skipping today's file avoids that.

Either default can be flipped by configuration if a user has a
reason to want the opposite behavior. The current-date file
becomes eligible regardless once the date rolls over.

---

## Open Questions

The Jasmine spec is intentionally kept light at this stage. The big
structural decisions are settled (JSONL baseline, malformed-line
tolerance, required uuid/timestamp, conventional `web` field,
ambient `%chain.log`, nested call frames, role-boundary security
via nesting). **Further format development is deferred** — the rest
will be refined through real use rather than upfront design. As
Robinson and other consumers actually exercise Jasmine, the format
will evolve in response to concrete needs that surface.

Specific items deferred:

- The detailed shape of `request` and `response` inside the `web`
  field — which fields, which are required, privacy considerations
  for IP / user-agent / headers / bodies.
- The exact format of the `function` identifier on call frames (a
  structured object was proposed in conversation; not yet
  filed pending the format-evolution approach).
- Per-entry timestamps inside nested frames — does each call frame
  carry its own `timestamp`, or only the root entry? Same question
  for `uuid`.
- Exception handling — what does a call frame look like when the
  function raised? Does the partial entry still get appended?
- Concurrent writers — atomicity guarantees for multiple processes
  appending to the same file (POSIX `O_APPEND` is atomic up to
  `PIPE_BUF`, but larger entries might interleave).
- Log rotation, retention, archival.
- Reading tooling — `jasmine` CLI, log viewers, dashboards.
- PII redaction conventions.
- Schema validation (JSON Schema or similar) for entries.
- The "full call record" opt-in mode (every call recorded whether
  or not it wrote anything).
- **Reaping into a mikobase.** A built-in reaper closure (or a
  related routine) that consumes Jasmine entries and writes them
  into a [[mikobase]] — the natural next step for log entries that
  want to be queryable as structured data. Noted as an eventual
  goal; v1 inclusion TBD.
- **Webhook store.** A built-in store that POSTs each entry to a
  remote HTTP endpoint — already listed under [Stores](#stores) as
  "Future," but flagged here so the v1-or-not decision can be made
  alongside the other deferred items.
- **Write-reap-purge (wrp) mode.** An opt-in mode where every
  entry write is immediately followed by a reap + purge cycle.
  Keeps the directory always-light (no backlog), and gives
  downstream consumers (especially the eventual mikobase reaper)
  near-zero-latency entry delivery. The value is mostly with a
  reaper consumer configured; without one, it degrades to
  purge-on-write. Opt-in, not default. By default skips today's
  file from the purge step to avoid delete-and-recreate churn —
  see [What counts as "empty"](#what-counts-as-empty).
- **Detached writes via fork.** When `fork(2)` is available, do
  the actual I/O in a detached child process so the parent never
  blocks on log I/O. The child does the work serially in one
  process: **append entry → run reap → run purge → exit.** One
  fork per write; the reap and purge are just function calls
  inside the child, not additional process spawns. Stays light in
  practice because (a) with wrp as steady state,
  reap touches almost nothing per cycle, (b) purge mostly
  skips — today's file is non-empty and older files were already
  cleaned by earlier writes, and (c) `fork` on Linux is
  copy-on-write so child startup is cheap. The trade-off is
  reduced crash visibility — if the child dies mid-write, the
  parent doesn't know — but for best-effort logging that's an
  acceptable cost. Opt-in. Synergizes strongly with wrp mode —
  together they make the operational
  picture "configure the log, write entries, never think about it
  again." A persistent background worker (one long-lived child
  pulling from a queue) stays available as a future optimization
  if per-write fork ever proves too expensive on a target
  platform.

Each will get addressed when there's a concrete need driving it.
