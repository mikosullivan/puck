# Design

~~~vibecode
{"vibecode": {
	"doc": "obrien_design",
	"role": "the actual design for the Caspian job-queue manager we may implement — distinct from study.md, which surveys the broader space and how other languages handle this. This file is where committed-to-implementation design decisions land; study.md is the exploration.",
	"codename": "O'Brien",
	"status": "active design — being shaped collaboratively, not yet a committed spec",
	"sibling_docs": ["study.md (survey + exploration of how other languages do this)"],
	"settled_decisions": ["one_and_done_jobs",
		"one_and_done_workers",
		"mikobase_as_the_queue_store",
		"manager_is_single_writer_to_mikobase",
		"worker_reports_back_via_stdout_as_json",
		"stderr_is_for_everything_else",
		"xeme_is_the_job_result_format",
		"two_verification_modes_implicit_default_and_positive_assertion",
		"no_periodic_sweeper_needed_just_one_time_startup_sweep"]
}}
~~~

A potential design for a job-queue manager. This project is code named **O'Brien**.

O'Brien manages a queue of jobs in a single Caspian process. The manager forks one worker per job (subject to a concurrency cap), waits for each worker to exit, records the outcome, and moves on. The guarantee: every job ends in a terminal state — either completed or marked as cannot-be-completed. No job is ever stuck in flight; no job is ever silently lost.

The design pulls heavily on three Caspian primitives:

- **[`%utils.forks.multiple(N)`](https://puck.uno/documentation/requirements/caspian/forking/)** for the worker pool with built-in concurrency cap.
- **[Mikobase](https://puck.uno/documentation/requirements/mikobase/)** for durable job records.
- **[Xeme](https://puck.uno/documentation/requirements/caspian/packages/bryton/xeme/)** as the result-recording format.

The sibling [study.md](study.md) surveys how other languages do this and discusses the broader design space. This file is the path we may actually build.

---

## Core decisions

The following are settled for V1. Together they collapse a lot of the complexity that other job-queue systems carry.

### Jobs are one-and-done

Each job is attempted **exactly once**. No retries, no backoff, no max-attempts cap. The worker either succeeds or fails; the outcome is recorded; the job is finished.

Callers that need retry semantics build them on top — by re-enqueuing on failure, by writing a job class whose body itself retries, etc. O'Brien doesn't decide retry policy; the caller does.

The job lifecycle is correspondingly small:

```
pending → claimed → done
                  → failed
                  → cannot_be_completed (in practice, same as failed)
```

Four states, three transitions. Once a job leaves `claimed`, it's terminal.

### Workers are one-and-done

Each worker is a fresh OS fork that runs **exactly one job and exits**. No worker reuse, no long-lived worker process polling for the next job, no worker dispatch loop.

This is the opposite of Sidekiq / Celery / RQ, which pool long-lived workers. The trade-off is a higher per-job fork cost (OS fork is fast but not free) in exchange for:

- **Fork = job, 1:1.** Easier to reason about. `ps` shows you exactly what's running. Killing a fork kills exactly one job. No "which job is this stuck worker on?" question.
- **No worker pool to manage.** No graceful drain, no rolling restart, no worker-died-mid-loop edge cases. Each worker's lifecycle is exactly one job's lifecycle.
- **State leakage between jobs is impossible.** Each fork starts fresh from the manager's state at spawn time. No "the worker's memory got polluted by the previous job" bug class.
- **Per-job role isolation is natural.** Each fork can run in whatever restricted role suits its job; different jobs can have different role profiles without worker-pool gymnastics.

For jobs short enough that fork overhead dominates the work, O'Brien isn't the right tool (in-process work is). For jobs in the millisecond-to-minute range, the fork cost is noise.

### The manager is the single writer to Mikobase

Only the manager process writes to job records. Workers report back to the parent via STDOUT (see [Worker-to-parent IPC](#worker-to-parent-ipc-stdout) below); the manager translates that into Mikobase writes. Three things this buys:

- **No write contention.** Exactly one process ever touches each row.
- **Worker doesn't need Mikobase capability.** The worker can be sandboxed to "just what it needs to do its actual job" — Mikobase write access stays inside the manager's role.
- **Manager owns the truth.** Mikobase reflects what the manager has confirmed receiving. A worker that wrote a value and then died before the parent acknowledged it doesn't leave Mikobase in a half-committed state.

### Job outcomes are Xemes

Every job result is recorded as a [Xeme](https://puck.uno/documentation/requirements/caspian/packages/bryton/xeme/). Xeme is the existing Caspian-standard JSON tree format for structured outcomes (test results, log entries, anything that needs a verdict plus structured reasons).

Concretely, a job record stores a Xeme that carries:

- **`success`** — `true` (done) or `false` (failed). O'Brien doesn't use `null` (no-verdict) in V1 — every job ends with a definitive verdict, since worker death, missing output, etc. all resolve to `success: false` with a structured `errors[]` entry.
- **`errors[]`** — structured failure reasons when `success: false`. Each entry has its own `class` identifying the kind. O'Brien **reuses the existing [Xeme runtime error classes](https://puck.uno/documentation/requirements/caspian/packages/bryton/xeme/#class-field)** rather than inventing new ones — so worker crashes use `bryton/runtime/crashed`, timeouts use `bryton/runtime/timedout`, unparseable STDOUT uses `bryton/runtime/unparseable`, etc. The benefit: the existing Xeme icon set covers them all by name lookup.
- **`meta.uuid`**, **`meta.timestamp`**, **`meta.run_time`** — record-keeping fields.
- **`io.stdout`**, **`io.stderr`** — captured worker output, useful for failure forensics.
- **`class`** — identifies the kind of job (`myorg.com/job/email_send`, etc.).

Bonus benefits of using Xeme:

- **No new result schema to invent.** Xeme already exists, already covers what's needed, already has tooling that consumes it.
- **Streaming / progress support.** A worker can emit a Xeme that starts as `success: null` with `nested: []` and append children as it works. Final resolution to `true` or `false` at job completion. Lets us add progress reporting later without changing the result shape.
- **Structured failure taxonomy.** Dashboards and reporting can filter by failure class. "Show me all timeouts" or "show me all `worker_died` failures across the last 24 hours" becomes a Mikobase query against the Xeme structure.
- **Parent-child workflow door is open.** Xeme's `nested[]` and resolution rule (parent ≤ children) means a parent job's verdict can naturally aggregate from sub-job verdicts. Not in V1, but the format doesn't preclude it.

### Two verification modes for worker success

The worker can signal success in two ways. The default is **implicit**; the opt-in is **positive-assertion**.

**Implicit mode (default).** A clean exit (status 0) means success. The worker doesn't have to write anything special. Anything else (non-zero exit, abnormal exit, signal) means failure (or null, on abnormal exit).

Right for jobs where the work itself is its own verification — the email got sent, the file got moved, the database write committed. The act of completing IS the signal.

**Positive-assertion mode (opt-in).** A clean exit isn't enough; the worker must explicitly report `success: true` (write a Xeme verdict back to the parent). A clean exit with no report is treated as a failure.

Catches the "worker silently no-op'd" failure mode that implicit mode can't see: a bug where the worker caught an exception, swallowed it, ran to its end without doing the work, and exited 0. Useful when the work itself isn't externally observable, or when defensive verification is wanted.

The failure side is symmetric in both modes:

- A worker can always explicitly report `success: false` with structured `errors[]` if it knows it failed. This is the most informative path.
- A worker that exits non-zero without reporting gets a default failure Xeme: `{class: "bryton/runtime/crashed", exit_code: N}`.

The modes only diverge when the worker **exits 0 with no verdict reported**:

- Implicit: counted as success.
- Positive-assertion: counted as failure with `{class: "bryton/runtime/missing"}`.

Granularity of the mode setting (per-job, per-job-class, per-queue, global) is not yet decided — see [Open questions](#open-questions).

### Fork lifecycle IS the lease

In other job systems, "worker crashed and abandoned its claim" is a real problem that requires lease leases, heartbeats, sweepers, etc. In O'Brien it's not, because the OS-level fork lifecycle gives the manager direct observation of worker liveness.

- Manager forks a worker; the engine tracks it.
- Manager calls `$mgr.wait` on the worker; this blocks until the worker exits and surfaces the exit status.
- If the worker died abnormally, the exit status says so immediately. Manager writes the failure Xeme to Mikobase. No timer-based detection needed; the kernel told the manager.

The only sweeper-equivalent that remains is a **one-time startup sweep** to handle the case where the manager itself crashed and restarted: any rows still marked `claimed` from a previous run necessarily have no live worker (the manager process is fresh), so the manager marks them all failed and starts clean. One query and one update at boot; no ongoing loop.

---

## Architecture

The core loop, in shape:

1. **Manager queries Mikobase for pending jobs.** Up to N at a time, where N is the configured concurrency cap (and how many forks the manager has room for).
2. **Manager spawns one worker fork per job**, via `%utils.forks.multiple(N)` or `%utils.forks.single()` (sketched below — exact API TBD). Each job's record gets marked `claimed`.
3. **Each worker runs its job.** On completion (or failure it caught), the worker writes its Xeme verdict as the final JSON hash on STDOUT and exits. Whatever else the worker wrote to STDOUT during execution (debug messages, progress, etc.) is preserved as forensic context.
4. **Manager reaps the worker via `$mgr.wait`** and captures its STDOUT. Four outcome paths:
   - Clean exit + parseable trailing JSON hash → manager writes that Xeme to Mikobase, with any pre-verdict STDOUT content stuffed into `io.stdout` on the Xeme.
   - Clean exit + empty STDOUT → implicit mode counts as success; positive-assertion mode counts as failure (`{class: "bryton/runtime/missing"}`).
   - Clean exit + STDOUT doesn't end with parseable JSON hash → manager writes `{success: false, errors: [{class: "bryton/runtime/unparseable"}]}` with the raw STDOUT captured into `io.stdout`.
   - Abnormal exit → manager constructs a Xeme with `{success: false, errors: [{class: "bryton/runtime/crashed", exit_code: N, signal: S}]}` (signal-killed and exit-non-zero both resolve to the same `bryton/runtime/crashed` class with the exit/signal carried as fields) and writes it.
5. **Manager updates the job's Mikobase record.** Status leaves `claimed`; goes to `done` or `failed`.
6. **Loop continues.** Manager queries for the next pending job and spawns a replacement worker (as long as it's under the concurrency cap).

On **startup**, before entering the main loop:

- Manager sweeps Mikobase for any rows marked `claimed` from a previous run. Each such row has no live worker (the manager just started); manager marks them all failed with `{class: "bryton/runtime/crashed"}` and continues.

On **shutdown** (SIGTERM, etc.):

- Manager stops accepting new jobs from the queue.
- Waits for all in-flight workers to drain (each finishes its current job and exits).
- Manager exits cleanly with no `claimed` rows remaining.

(Graceful-shutdown details are subject to refinement.)

### Worker-to-parent IPC: STDOUT

The worker reports its Xeme verdict to the parent by **writing a JSON hash at the end of STDOUT** and exiting. The manager captures the worker's full STDOUT and parses the trailing JSON hash as the Xeme.

The contract is "STDOUT must end with a valid JSON hash," not "STDOUT must contain only JSON." Workers are free to write whatever they want to STDOUT during execution — progress messages, debug output, sub-process output — as long as the very last thing they write is a JSON hash that the manager can parse as the verdict. Anything earlier on STDOUT is captured and stuffed into the verdict Xeme's `io.stdout` field for forensics. STDERR is also free for the worker to use; the Xeme's `io.stderr` field captures whatever lands there.

Concretely:

- The worker function calls `puts {success: ..., ...}` (or any other path that emits a JSON hash as the final STDOUT bytes) and exits. By the [to_primitives conversion chain](../../../requirements/caspian/to-primitives.md), `puts` on a hash produces the hash's JSON form, so a plain `puts {...}` at the end of the function is enough.
- The manager reads STDOUT after `$mgr.wait` returns. Parses the trailing JSON hash. If parsing succeeds, that's the worker's Xeme; any STDOUT content before the hash becomes `io.stdout` on the Xeme. If no parseable JSON hash is at the end, the manager writes a default failure Xeme: `{success: false, errors: [{class: "bryton/runtime/unparseable"}]}` with the raw STDOUT captured into `io.stdout`.
- Empty STDOUT + exit 0 means "no verdict reported." Under implicit mode that's success; under positive-assertion mode that's failure (see [Two verification modes](#two-verification-modes-for-worker-success)).

This is a deliberate O'Brien-specific choice — not necessarily the right answer for every fork-based parent-child IPC in Caspian. Other contexts (where streaming or richer message structure matters) might still prefer the shared-hash IPC primitive. For O'Brien, STDOUT-tail-JSON wins on simplicity:

- **Universal.** Every OS process has STDOUT. No special IPC primitive setup; no shared-hash allocation; no protocol negotiation.
- **Testable.** The worker function can be invoked directly outside O'Brien (in a test, in a script, at a REPL) and its STDOUT inspected. No mock of a shared-hash channel needed.
- **Language-neutral.** A worker doesn't have to be a Caspian function. Anything that can write JSON to STDOUT and exit — a shell script, a Python program, a compiled binary — can be an O'Brien worker. That opens the door to wrapping arbitrary external tools as O'Brien jobs without Caspian-side glue.
- **Workers can log freely.** Because STDOUT is "anything, as long as it ends with the verdict," a worker can debug-print throughout its run without breaking the protocol. The pre-verdict content is preserved in `io.stdout` automatically.
- **No streaming needed at V1.** O'Brien's one-and-done jobs don't need mid-execution progress reporting; the worker runs to completion and reports its verdict at the end. If progress reporting becomes a feature later, it can ride a separate channel without changing the verdict mechanism.

---

## Deliberate non-features

Things O'Brien explicitly does NOT do in V1:

- **No retries.** Each job is attempted exactly once. Caller does retry policy.
- **No worker reuse.** Each worker is a fresh fork that handles one job.
- **No exactly-once delivery.** With one-and-done execution, "exactly-once" is structurally guaranteed for the success path. The failure path may leave work partially done; idempotency of the job body is the caller's concern.
- **No distributed workers across hosts.** O'Brien runs on a single host. Workers are local forks. Multi-host job processing would require Puck or a real broker (see [study.md § Where it gets harder](study.md#where-it-gets-harder)).
- **No periodic background sweeper.** Fork-exit detection is OS-level; no need for periodic liveness scans.
- **No automatic dead-letter queue.** Failed jobs stay in Mikobase as `failed` records; querying for them is the dashboard concern.

---

## What's NOT yet decided

<a id="open-questions"></a>

These are the design questions still in flight:

- **Granularity of the verification-mode setting.** Per-job (caller picks at enqueue time), per-job-class (the class declares its mode), per-queue (all jobs in a queue use the same mode), or global (one O'Brien setting). Per-job-class feels natural but unclear yet which actually plays best in real use.
- **Exact API surface.** Method names, signatures, what's on the manager class vs free-standing — all TBD.
- **Concurrency cap configuration.** Static at manager start, dynamic via config update, per-queue, etc.
- **Result-record retention.** Failed records stay forever? Pruned after N days? Caller manages?
- **Scheduled / delayed jobs.** Possible but not in the first cut.
- **Graceful shutdown details.** Drain timeout, force-kill threshold, etc.
- **Observability.** What metrics, what hooks for external monitoring, dashboard vs raw Mikobase queries.

---

## See also

- [study.md](study.md) — the broader survey of how other languages do this and the design alternatives considered.
- [Caspian forking](https://puck.uno/documentation/requirements/caspian/forking/) — the fork primitives O'Brien builds on.
- [Caspian events](https://puck.uno/documentation/requirements/caspian/events/) — the in-process broadcast/listen system, useful for external observability hooks.
- [Mikobase](https://puck.uno/documentation/requirements/mikobase/) — the structured object store backing the queue.
- [Xeme](https://puck.uno/documentation/requirements/caspian/packages/bryton/xeme/) — the result-recording format O'Brien uses for job outcomes.
