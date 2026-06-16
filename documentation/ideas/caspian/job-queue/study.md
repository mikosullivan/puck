# Job-queue manager design

~~~vibecode
{"vibecode": {
	"doc": "job_queue_manager",
	"role": "design exploration for a Caspian job-queue manager — a process that maintains a queue of jobs and forks a child per job (capped concurrency), waits for each child to complete, harvests results, and guarantees that every job ends in either a completed state or a cannot-be-completed state. Surveys how this is done in other languages (Sidekiq, Celery, Resque, RQ, BullMQ, etc.) and proposes a Caspian-native implementation leveraging the existing fork primitives and Mikobase for persistence.",
	"status": "speculative idea report — not a commitment to build",
	"proposed_by": "Miko",
	"audience": "Caspian designers and implementers thinking about concurrency, queueing, and durable job processing",
	"key_concepts": ["job_queue_manager", "fork_per_job_worker_model",
		"capped_concurrency", "result_harvesting",
		"every_job_completed_or_marked_uncompletable",
		"mikobase_backed_durability",
		"caspian_fits_naturally_with_existing_fork_primitives"]
}}
~~~

A design exploration for a Caspian job-queue manager. Survey of how the pattern is implemented in other languages, then a sketch of how it would land in Caspian.

---

## The proposed design

A single Caspian process — call it the **manager** — holds a queue of jobs and dispatches them to child workers. The shape:

- The manager keeps a queue of pending jobs (in memory, on disk, or in Mikobase).
- For each job, the manager **forks a child process** to run it. Not all jobs at once — a configurable concurrency cap.
- The manager waits for each child to exit, harvests the result, updates the job's status, and dispatches the next pending job.
- Every job ends in one of two terminal states: **completed** (the child finished, the result is captured) or **cannot-be-completed** (after retries, or because the work is impossible). No "in-flight forever" state. The guarantee is uniform regardless of how a child died.

This is a classic worker-pool / job-queue pattern. The interesting parts in Caspian are (1) leaning on the fork-per-job model that Caspian's primitives already favor, and (2) figuring out what makes the "completed or marked uncompletable" guarantee robust in the face of crashes.

---

## How it's done in other languages

Job-queue managers are a well-trodden problem; almost every modern language has at least one canonical library. The differences are in the queue store, the worker model, and the operational story.

### Python: Celery, RQ, Dramatiq, Huey

- **[Celery](https://docs.celeryq.dev/)** dominates. Workers run as separate processes; the queue lives in a broker (RabbitMQ or Redis). Concurrency is `--concurrency=N` on worker startup, typically using either prefork (one OS process per task) or gevent/eventlet (greenlets). Rich features: scheduled tasks, retries with backoff, chains and groups (DAG-shaped workflows), dead-letter queues.
- **[RQ](https://python-rq.org/)** is the simpler alternative — Redis-only, process-per-job, intentionally smaller surface than Celery. "Job is a Python callable; queue is a list in Redis; worker dequeues and runs."
- **[Dramatiq](https://dramatiq.io/)** and **[Huey](https://huey.readthedocs.io/)** occupy similar space; each makes slightly different trade-offs around middleware, persistence, and scheduling.

The pattern across all of them: workers are separate OS processes, jobs are serialized to a broker, retries are handled at the framework level, monitoring is dashboard-based.

### Ruby: Sidekiq, Resque

- **[Sidekiq](https://sidekiq.org/)** is the canonical Ruby answer. Multi-threaded workers within a single process; Redis-backed queue. The threaded model lets Sidekiq pack many concurrent jobs per worker process — good for I/O-bound work, less good for CPU-bound (Ruby's GIL).
- **[Resque](https://github.com/resque/resque)** is the older single-process-per-job alternative. Same Redis backing; one OS process per running job. Sidekiq grew out of Resque to address the per-process memory cost.

### Node.js: BullMQ, Bee-Queue, Agenda

- **[BullMQ](https://docs.bullmq.io/)** is the current standard. Redis-backed; workers are async event-loop callbacks rather than processes. Job lifecycle states (waiting, active, completed, failed, delayed), retry strategies, repeatable jobs, parent/child workflows.
- **[Bee-Queue](https://github.com/bee-queue/bee-queue)** is the lighter alternative.
- **[Agenda](https://github.com/agenda/agenda)** uses MongoDB for persistence instead of Redis.

### Elixir: Oban, Exq

- **[Oban](https://hexdocs.pm/oban/)** is interesting because it's **Postgres-backed**, not Redis. Jobs are rows in a table; the worker uses `SELECT FOR UPDATE SKIP LOCKED` to claim them. The case for Postgres-backed queues: the application probably has Postgres already, so the queue inherits the same transactional / backup / monitoring story as the rest of the data.
- **[Exq](https://github.com/akira/exq)** is the Redis-backed Sidekiq-compatible alternative.

### Erlang/OTP: built into the platform

OTP's `gen_server` + supervision trees are basically a built-in job-queue framework: every process is supervised, restart policies are declarative, and the "let it crash" philosophy means individual job failures are handled by the supervisor restarting the worker. No separate library needed for the basics.

### Go: asynq, machinery, gocraft/work

- **[asynq](https://github.com/hibiken/asynq)** is the modern leader — Redis-backed, designed around Go's goroutine concurrency model. Scheduled tasks, retries, dead-letter queues, web UI.
- **[machinery](https://github.com/RichardKnop/machinery)** and **[gocraft/work](https://github.com/gocraft/work)** are alternatives; less standardization than the Python or Ruby ecosystems.

### Java: Quartz, Spring Batch, JMS-based

Quartz handles scheduling-focused workloads; Spring Batch tackles large-scale ETL; for general task queues most Java shops use JMS-based brokers (ActiveMQ, RabbitMQ via AMQP). More fragmentation than other ecosystems.

### Managed services

AWS SQS + Lambda, Google Cloud Tasks, Azure Service Bus — each provides queue + worker infrastructure as a service. Often the right answer for cloud-native shops that don't want to operate the queue themselves.

---

## Common patterns across the libraries

A few patterns are essentially universal:

- **Job records.** A job is a serialized payload (args, the function/method to invoke, metadata like job ID, created_at, attempt count). Stored in the queue backend.
- **Lifecycle states.** Pending → claimed (a worker has reserved it) → in_progress → success / failure. Failed jobs may go back to pending (retry) or to dead-letter (permanent).
- **Worker concurrency model.** Either process-per-job (RQ, Resque, Caspian's natural fit) or thread/coroutine-per-job (Sidekiq, BullMQ). Process-per-job costs more in setup but provides full isolation; thread/coroutine-per-job is cheaper but harder to fail-isolate.
- **Visibility timeout / claim lease.** When a worker claims a job, it gets a time window to complete. If the worker crashes (no heartbeat, no completion), the lease expires and another worker can claim the job. This is the mechanism for ensuring "every job is eventually completed."
- **Retry with backoff.** Failed jobs are retried, typically with exponentially increasing delays between attempts. After N retries, the job is marked permanently failed and moved to a dead-letter queue.
- **Idempotency expectation.** Since jobs can be re-tried and re-delivered, jobs are expected to be idempotent (running the same job twice should be safe). Frameworks don't enforce this; they assume it.
- **Scheduled / delayed jobs.** "Run this job in 5 minutes" or "run this every day at 03:00."
- **Priority queues.** Some libraries support multiple queues with different priorities; high-priority queues drain before low-priority.
- **Operational dashboard.** Sidekiq's web UI, BullMQ's board, Celery Flower — visibility into pending jobs, running jobs, failures, throughput.

The **storage choice** is often the biggest architectural decision: Redis-backed (Sidekiq, RQ, BullMQ, asynq) is fast and operationally cheap if Redis is already there; Postgres-backed (Oban) is durable and inherits the application's transactional story; in-memory (some lightweight options) loses everything on restart but is simplest.

---

## How Caspian could implement this

Caspian's design — single-threaded with explicit forks, Mikobase available as a structured store, existing fork primitives that already support N-capped pools — makes a fork-per-job manager a natural fit. Most of the pieces already exist; the work is in the orchestration layer on top.

### What's already there

- **[`%utils.forks.multiple(N)`](https://puck.uno/documentation/requirements/caspian/forking/)** spawns N tracked child processes, each running the same block independently. The "capped concurrency" the proposed design wants is exactly this primitive.
- **[`%utils.forks.single()`](https://puck.uno/documentation/requirements/caspian/forking/)** spawns one tracked child. Fine for one-at-a-time job processing or for ad-hoc fork management.
- **`$mgr.wait`** on a fork manager blocks the parent until the child exits and lets the parent observe the exit status. The "harvest" step of the proposed design.
- **Auto-close at script end** means if the manager process dies, all tracked children get cleaned up (SIGTERM then SIGKILL). No zombies, no orphans.
- **Mikobase** can store job records as queryable, durable, structured data — pending status, payload, attempts, last_error, etc.
- **The event system (`broadcast` / `listen_to` / `on_broadcast`)** can wire up "job done" notifications from worker forks back to the manager, if needed.

### Proposed architecture

The job-queue manager is itself a Caspian object (a class instance, or a top-level script) that:

1. **Maintains a queue.** Jobs sit as Mikobase records of a `puck.uno/job` (or similar) class. The bucket carries the payload; the stack carries the job class. Status field tracks lifecycle (pending / claimed / running / done / failed). Created-at and updated-at timestamps for monitoring.
2. **Spawns a pool of workers.** A `%utils.forks.multiple(N) do($fork)` block starts N worker forks. Each worker loops: claim a pending job from Mikobase, run it, write the result back, repeat. The N cap enforces the concurrency limit naturally — only N jobs run at any moment.
3. **Claim with leases.** A worker claims a job atomically (Mikobase transaction-like): "find one pending job, mark it claimed by my fork ID with a deadline." If the worker dies, the lease expires; a separate sweep finds expired claims and reverts them to pending.
4. **Harvest results.** When a worker finishes a job successfully, it updates the Mikobase record (status = done, result = ...). On failure, it records the error and either schedules a retry or marks the job permanently failed if max-attempts is exceeded.
5. **Lease-sweeper.** A separate small loop (in the manager, or as its own fork) periodically queries Mikobase for jobs whose lease has expired and reverts them to pending. This is what catches worker-fork crashes.
6. **Permanent failure tracking.** Jobs that have exhausted retries get status = `cannot_be_completed` with the captured error info. They stay in Mikobase as a record but are not re-tried.

Sketch:

~~~caspian
class
	function &start(concurrency: 4)
		# Spawn N worker forks; each runs its own dispatch loop
		@workers = %utils.forks.multiple($concurrency) do($fork)
			%self.&worker_loop($fork.index)
		end

		# Spawn a lease-sweeper to recover crashed jobs
		@sweeper = %utils.forks.single() do
			%self.&sweep_loop
		end
	end

	function &worker_loop($worker_id)
		while true
			$job = %self.&claim_one_job($worker_id)

			if $job.is_null
				%utils.sleep 0.5    # nothing pending; back off briefly
			else
				%self.&run_job $job
			end
		end
	end

	function &run_job($job)
		try
			$result = $job.execute
			$job.mark_done(result: $result)
		catch $err
			if $job.attempts >= @max_attempts
				$job.mark_cannot_be_completed(error: $err)
			else
				$job.mark_for_retry(error: $err)
			end
		end
	end

	function &sweep_loop()
		while true
			$expired = %mikobase.query({class: 'puck.uno/job',
				status: 'claimed', lease_expires_before: %utils.now})
			$expired.each do($job)
				$job.revert_to_pending
			end
			%utils.sleep 5
		end
	end
end
~~~

Sketch only — the exact API of `$job.mark_done`, `%mikobase.query`, etc. needs the corresponding specs to firm up. But the shape is straightforward, and every primitive used already exists or is on the design map.

### Guaranteeing "completed or cannot-be-completed"

Miko's specific requirement — every job ends in one of two terminal states — falls out of three pieces working together:

1. **Worker tries to complete.** On success, write `status = done`. On caught error, either retry or `cannot_be_completed`. As long as the worker runs to completion of either branch, the guarantee holds for "expected" failures.
2. **Lease sweeper catches unexpected failures.** A worker crash (segfault, SIGKILL, host reboot) leaves a job in `claimed` status with an expired lease. The sweeper sees the expired lease and reverts the job to `pending`, where another worker picks it up. If the same job repeatedly crashes workers, the retry counter eventually pushes it to `cannot_be_completed`.
3. **Mikobase persistence guarantees state survives.** Even if the entire manager process dies and restarts, jobs in flight are still in Mikobase. The new manager's lease-sweeper finds the expired claims and recovers them. Pending jobs are pending; done jobs are done; cannot-be-completed jobs are not retried.

The retry counter is what bounds "indefinite retry." The lease sweeper is what catches "worker died without updating the record." Together they cover every failure path. No job state can persist forever as "running" — either the worker finishes and updates the record, or the lease expires and recovery kicks in.

### Where Caspian fits naturally

- **Fork-per-job is the right granularity.** Caspian has no native threading; forks ARE the parallelism story. A job-queue manager that one-process-per-job is the grain-aligned design.
- **Engine-tracked fork cleanup.** The engine already handles "if the parent dies, kill the tracked children" without the developer having to wire up signal handling. That's exactly what a job manager wants: if the manager process dies, all the in-flight worker forks get cleaned up; their lease expires shortly after; another manager instance recovers the jobs.
- **Role isolation per worker.** Each worker fork can run jobs in a restricted role — limited filesystem access, no network if not needed, etc. Caspian's role system means worker forks can be sandboxed without the manager having to invent the mechanism.
- **Mikobase as queue store.** Mikobase queries are JSON; job records are introspectable in a debugger; the data is durable across manager restarts; backup / monitoring inherit from Mikobase's story. No separate Redis or Postgres deployment if Mikobase is already in the stack.
- **Engine event system for in-process notifications.** When a worker finishes, it can broadcast a `'job_done'` event the manager listens for — useful for "shut down gracefully after current jobs finish" or "wake up the lease-sweeper now."

### Where it gets harder

- **Single-host limit.** Forks live on one machine. A distributed job-queue across multiple hosts requires either Puck (workers as remote objects), a real broker (workers consume from external Redis/RabbitMQ), or both. The single-host version is fully Caspian-native; the multi-host version isn't.
- **Mikobase throughput for queue churn.** Mikobase is a structured object store, not a purpose-built queue. High-frequency claim/release cycles might stress Mikobase patterns it isn't optimized for. Probably fine for moderate workloads (hundreds of jobs per second); a real broker becomes more appealing at higher scale.
- **Fork startup cost.** OS `fork()` is fast on Linux but not free. For very short-running jobs (microseconds each), the fork cost dominates the work. A worker that processes many jobs sequentially within a single fork — the loop in the sketch above — amortizes the cost, which is why most production job systems work that way rather than forking per job.
- **Stale leases sized correctly.** Lease durations are a tuning knob: too short and a slow-but-healthy job gets stolen mid-execution by the sweeper; too long and a crashed worker's jobs take forever to recover. Some libraries let the worker extend its lease while still working. Worth designing in from the start.

---

## Open design questions

If Caspian builds this, the design questions worth settling early:

- **Mikobase vs in-memory vs file.** Three storage options, three durability profiles. Mikobase is the obvious answer when persistence matters; in-memory is fine for ephemeral workloads (lost on restart is OK); file-based is a middle ground if Mikobase feels heavy. Probably worth supporting at least two of these via a swappable backend.
- **Job class shape.** Is a job a Caspian object whose class implements `&execute`? A Puck-style remote callable? A pure data record plus a registered function reference? The Caspian-native answer is probably "job is an object with an `&execute` method," but the serialization story (how does the job survive a manager restart?) needs thought.
- **Result storage.** Where do completed-job results go? Back into the same Mikobase record? A separate `results` table? Discarded after consumption? Probably configurable per-queue.
- **Retry policy.** Exponential backoff? Linear? Fixed delay? Per-job override of the queue default? The common case is exponential backoff with a max-attempts cap and a dead-letter destination.
- **Priority queues.** Single FIFO, or N priority levels? If priorities, are they preemptive (high-pri jumps ahead of low-pri claims) or cooperative (workers prefer high-pri when free)?
- **Scheduled / delayed jobs.** "Run this in 5 minutes" needs a different storage shape (jobs that aren't claimable yet). Mikobase can hold them; the worker query needs a `where claimable_at <= now` filter.
- **Graceful shutdown.** "Stop accepting new jobs, finish current ones, then exit" needs a signal-handling story. The manager probably listens for SIGTERM and stops feeding workers; workers complete their in-flight job and exit; the manager waits for the pool to drain.
- **Heartbeat / progress reporting.** Should long-running jobs be able to update their progress (so the manager / dashboard can show "75% done")? Useful for monitoring; adds API surface.
- **Multi-queue isolation.** A single manager processing N independent queues? Or one manager per queue? Different operational profiles.
- **Observability.** Built-in metrics (jobs/sec, error rate, queue depth) or just "query Mikobase for whatever you want to see"? A dashboard is a substantial follow-on project.

The simplest first cut would be: in-memory queue, fork-per-job with a fixed concurrency, no retries (job either succeeds or is marked failed once), no scheduling. That gets the core pattern working in a few hundred lines and proves the design. Persistence, retries, scheduling, priorities all add on incrementally.

---

## See also

- [Caspian forking](https://puck.uno/documentation/requirements/caspian/forking/) — the fork primitives the manager builds on.
- [Caspian events](https://puck.uno/documentation/requirements/caspian/events/) — the in-process broadcast/listen system useful for manager↔worker notifications.
- [Mikobase](https://puck.uno/documentation/requirements/mikobase/) — the structured object store proposed as the queue backend.
- [Message brokers report](message-brokers.md) — adjacent space; brokers do queueing too, but at a different scope (cross-process, distributed) than the in-process fork-pool design proposed here.
