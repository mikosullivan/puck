# Pause and resume

~~~vibecode
{"vibecode": {
	"doc": "requirements_cvm_pause_resume",
	"role": "sketch for Caspian's pause / resume primitive. %engine.pause writes a pause frame at the top of the stack and closes the CVM database. The database file IS the paused state — no serialization pass, no snapshot format. Resume: any writer edits the process's frame stack (objects rows with primitive='f') to remove the pause frame and optionally populate a payload hash. Engine reopens, execution continues, %engine.pause returns the payload. Structurally this is delimited continuations with argument, persisted in a database. Composes with Big Processes and cross-host revive.",
	"audience": "Caspian programmers writing pause-resume patterns; engine implementers building pause frame handling; external processes (HTTP handlers, agents, schedulers, humans) triggering resumes",
	"key_concepts": ["pause_frame_on_stack", "close_is_commit",
		"sql_edit_resumes", "revival_with_payload", "engine_minimalism",
		"cross_host_resume", "delimited_continuations_persisted"],
	"status": "design settled — pause/resume mechanics, revival-with-payload, use cases; a few open questions remain on transaction interaction and payload shape"
}}
~~~

Caspian's pause primitive freezes a running program in place, closes the runtime, and lets any external process resume it later — potentially minutes, days, or months later, potentially on a different host, potentially with data attached that describes what happened while the process was paused.

The mechanism is a single stack frame. When code calls `%engine.pause`, the engine writes a "pause" frame at the top of the call stack in CVM, then closes the database file. The process is gone. The state persists.

Resume is symmetric: any writer that can edit the CVM file — an HTTP handler, an agent, a scheduled callback, a human tapping "approve" — removes the pause frame and optionally attaches a payload hash. When an engine reopens the database, execution picks up where it left off, and `%engine.pause` returns whatever payload the resumer wrote.

## The pause primitive

~~~caspian
$result = %engine.pause
&do_something_with($result)
~~~

Reads: "pause execution here; when resumed, `$result` holds whatever the resumer sent back."

## What pause does mechanically

1. The engine writes a pause frame to `objects` — a single `primitive = 'f'` row marked as the pause frame, chained under the current top-of-stack frame (`parent_frame = <current top frame pk>`).
2. The write happens inside a SQL transaction.
3. The engine closes the SQLite connection. Closing commits the transaction atomically — WAL mode ensures either the pause frame lands cleanly or the whole transaction rolls back, never a half-paused state.
4. The engine process exits. The database file remains on disk with the paused state fully persisted.

Nothing else. There's no separate "paused" flag, no state-machine state, no scheduler waiting for a resume signal. The database IS the paused state.

## Resume by SQL edit

To resume a paused process, some other code opens the CVM file and edits the process's frame stack in `objects`:

1. Remove the pause frame row (or mark it as revived — the exact shape is an implementation detail of the pause frame schema).
2. Optionally populate a payload hash — key-value pairs describing what happened during the pause.

The next time an engine opens the database, the pause frame is gone. The engine's main loop reads the top frame, sees a normal frame, and continues execution as if the pause never happened. `%engine.pause`'s return value is the payload the resumer wrote.

Whoever resumes doesn't need to be an engine. It's just a database write. HTTP handler, cron, message queue consumer, human clicking "approve" through a web UI, another paused-then-woken agent — all use the same protocol: open, edit, close.

## Revival with payload

`%engine.pause` returns whatever hash the resumer attached:

~~~caspian
$revived = %engine.pause
$revived['name']    # 'Alice'
$revived['action']  # 'approved'
~~~

The paused code doesn't need to know how the resume was triggered. It reads the keys it expects. Whoever unpauses fills in what they know.

Common shapes:

- **HTTP request arrived** — `$revived['params']`, `$revived['body']`.
- **Agent yielded to LLM** — `$revived['response']`.
- **Human approved** — `$revived['decision']`, `$revived['note']`.
- **Scheduled cron fired** — `$revived['reason']`, `$revived['timestamp']`.

The payload can be null or an empty hash when the resumer has nothing to say — pause was just "wait for permission to continue."

## Properties

- **Atomic pause.** The pause frame lands as part of a SQL transaction; closing the DB commits. WAL mode guarantees no half-paused state.
- **Durability for free.** The database file IS the paused state. No serialization pass, no snapshot format, no marshaling. Same design as Big Processes ([features § Big Processes](https://www.puck.uno/ideas/drinian-with-sqlite/features#big-processes)).
- **Cross-host resume.** Pause on host A, copy the file, resume on host B. The CVM file is portable across any host that can open SQLite.
- **Duration unbounded.** A file paused today can revive next year. Filesystem-lifetime, not process-lifetime.
- **Engine minimalism.** The engine doesn't grow special "waiting for X" primitives. Its main loop reads and executes frames. Pause is one frame that causes the loop to exit; revival is the same frame being gone.
- **Cause travels in the payload.** Whoever resumed tells the resumed code what happened. No polling, no persistent connections, no handoff protocol needed.
- **Compositional.** Any writer that can open SQLite and edit a row can resume any paused process. No API to negotiate.

## Use cases

- **HTTP request handling.** A web handler starts a script; the script processes a form; then calls `%engine.pause` to wait for the user to click "confirm." When they do, an HTTP handler writes the payload and closes the file. The script resumes with the confirmation.
- **Agent coordination.** A supervisor agent pauses when it delegates a subtask. The subordinate agent completes the work, writes the result to the supervisor's CVM file, resumes it. Multi-step agent flows without polling.
- **Human-in-the-loop.** An automated workflow pauses at a decision point requiring human judgment. Whoever monitors reads the paused state, decides, writes the decision to the file, workflow continues.
- **Scheduled callbacks.** A script pauses with an expected resume time. A cron job checks periodically for files with matching expected-resume-times and revives them at the right moment.
- **Long-running external operations.** A script kicks off a hours-long external job. It pauses. When the job's done, its completion callback writes the result to the paused script and resumes it.
- **Retry loops without holding resources.** Instead of a `while true` loop with `sleep()`, a script pauses. The scheduler resumes it at the right interval. No connection held during the wait.

## Design connection

Structurally, `%engine.pause` is a **delimited continuation with argument** persisted in a database:

- **Erlang selective receive** — a process waits for messages matching a pattern; resumes when one arrives.
- **Racket control operators** — `call/cc` and delimited variants freeze the stack at a specific point.
- **Coroutines with arguments** — Python generators receiving `send()` values.
- **Async / await** — suspended coroutines that resume when a Future completes.

All of those hold state in memory during the pause. Caspian's pause writes the state to disk and releases the process. Revival happens on a completely fresh process, potentially days later, potentially on a different host. The stack IS the continuation, and the SQLite file IS the pause.

## Open questions

- **Pause frame contents.** Just a marker, or does it carry pause metadata (why paused, expected-resume-condition, timeout hint)? Structured metadata makes debugging easier and enables scheduler-side matching.
- **Transaction interaction.** If `%engine.pause` fires mid-transaction — does the pause auto-commit (releasing the DB cleanly) and resume start a new transaction? Or does the transaction stay in-flight across the pause? Auto-commit is simpler and matches the "close IS commit" property, but the transaction primitive quietly ends when you least expect it. Cross-references [transactions](https://www.puck.uno/ideas/transactions/).
- **Payload type strictness.** The payload is a hash; do we type-check it against what the paused code expects, or is it Caspian-dynamic (paused code reads keys, misses are null)?
- **Multiple pause frames.** A paused-and-revived script calling `%engine.pause` again — presumably works, the stack grows and shrinks normally, but worth confirming.
- **Debugging paused processes.** A paused process is a queryable SQLite file — inspection with `sqlite3` works. But a structured debugger UI (which frame paused, which code path, what state was live) needs schema conventions in the pause frame.
- **Race between pause commit and external write.** If the engine writes the pause frame + closes concurrently with an external process trying to write a revival — what's the ordering guarantee? WAL handles row-level ordering but the pause + close + revive protocol needs an explicit race-safe sequence.
