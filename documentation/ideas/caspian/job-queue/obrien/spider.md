# Example: a web spider

~~~vibecode
{"vibecode": {
	"doc": "obrien_spider_example",
	"role": "worked example demonstrating O'Brien through a simple web spider — each URL to crawl is a job, the worker fetches and parses the page, reports back extracted data plus newly-discovered URLs to enqueue. Shows the core O'Brien patterns concretely: per-job fork isolation, manager-as-single-writer, Xeme as the result format, the two verification modes, and how a worker requests further enqueues without touching Mikobase directly.",
	"status": "illustrative example — API specifics are sketched, not committed",
	"parent_doc": "index.md (the O'Brien design)",
	"sibling_docs": ["../study.md (broader survey of job-queue patterns)"]
}}
~~~

A worked example showing how O'Brien could be used to index web pages. The spider starts from seed URLs, fetches each page, extracts links and indexed data, and enqueues newly-discovered URLs for further crawling. Each fetch is one job. Each worker is one fork.

This example is **illustrative** — exact method signatures are sketched, not committed. The point is to make O'Brien's mechanics concrete through a real use case.

---

## What the spider does

For each URL in its queue:

1. **Fetch** the page over HTTP.
2. **Parse** the HTML to extract the title, the visible text, and the outbound links.
3. **Index** the page (write a `spider/indexed_page` record to Mikobase).
4. **Enqueue** any newly-discovered URLs as follow-up jobs.
5. **Report** back to the O'Brien manager: success with extracted data, or failure with structured error.

When the queue drains, the spider is done. Failed pages are recorded as `failed` Mikobase rows with structured `errors[]` explaining why.

---

## The job function

A job is just a function the worker calls. No class needed when the job is one operation that takes some args and outputs a Xeme to STDOUT — and most spider-style jobs are that shape.

~~~caspian
%vibecode
	role: 'one crawl job — fetch a URL, parse it, return what was found plus URLs to enqueue next';
	notes: 'returned Xeme uses producer-namespaced `enqueue` field to ask the manager to enqueue follow-up jobs';
end

$execute = function($url)
	$response = %net.fetch($url)

	if $response.ok?
		$doc = %['https://puck.uno/html/parser/links']($response.body)
		$followups = $doc.links

		puts {
			success: true,

			meta: {
				name:     $url,
				run_time: $response.run_time
			},

			title:   $doc.title,
			enqueue: $followups
		}
	else
		puts {
			success: false,
			meta:    {name: $url},
			errors: [
				{
					class:  'spider/error/http_status',
					status: $response.status
				}
			]
		}
	end
end
~~~

Notes:

- **The job is a plain function.** No class, no fields, no `&execute` ceremony. The function takes the job's args directly. For one-method jobs (almost all jobs), this is dramatically simpler than declaring a class just to hold one method.
- **Output, don't return.** The function writes its Xeme to STDOUT via `puts`, then the worker process exits. The manager captures the worker's STDOUT and parses the **trailing JSON hash** as the Xeme. No `return` value crosses the process boundary — there's no in-process return path between manager and worker, so the function doesn't try to fake one.
- **STDOUT must END with a valid JSON hash; everything else on STDOUT is free-form.** The worker can write whatever it wants to STDOUT during execution — progress messages, debug output, sub-process output, anything — as long as the very last thing is a JSON hash that the manager can parse as the verdict Xeme. The pre-verdict STDOUT content is captured and stuffed into the Xeme's `io.stdout` field for forensics. STDERR is also free for the worker to use; the Xeme's `io.stderr` field captures whatever lands there.
- **Writing `success: true` is the positive-assertion path.** The worker says explicitly "I succeeded" by writing a Xeme to STDOUT with `success: true`. Writing `success: false` with structured `errors[]` is the explicit-failure path.
- **The worker does NOT write anything to Mikobase.** STDOUT is its only output channel; the manager translates that into the Mikobase write.
- **`enqueue` is a producer-namespaced field on the Xeme** (allowed by the Xeme spec for non-reserved fields). The manager looks for `enqueue[]` in the worker's Xeme and enqueues those URLs as follow-up jobs. This keeps the worker side simple (just write a Xeme) and the manager invariant intact (only the manager writes to Mikobase).
- **Some details are sketched.** `%['https://puck.uno/html/parser/links']`, `$doc.links`, `$doc.title`, and `$response.ok?` are placeholders for whatever the real APIs are; the point of the example is the O'Brien flow.
- **No depth limit or seen-set deduplication shown.** A real spider needs both. They're caller-level concerns; O'Brien itself doesn't decide how the spider terminates.

---

## Starting the spider

Seed the queue and start the manager:

~~~caspian
%vibecode
	role: 'driver script: seed URLs, start the manager with concurrency cap';
end

# Instantiate the O'Brien manager, telling it which function to run per job
$obrien = %puck['https://puck.uno/obrien'].new(
	job: $execute
)

# Enqueue seed URLs
['https://example.com/', 'https://example.org/'].each do($url)
	$obrien.enqueue($url)
end

# Start the worker pool; blocks until the queue drains
$obrien.run(concurrency: 10)
~~~

`concurrency: 10` means at most 10 worker forks run at once. New workers spawn as old ones complete and free up slots. The total number of jobs processed is bounded only by the size of the crawled space (and whatever termination the caller adds — depth limit, max-pages cap, or seen-set deduplication).

---

## What happens at runtime

Walking through one URL's lifecycle:

1. **Enqueue.** Driver (or a follow-up emitted by a previous run) calls `$obrien.enqueue($url)`. Manager writes a row to Mikobase: the job's function reference, the args (`$url`), `status: pending`.

2. **Claim.** Manager's main loop picks up the pending row, marks it `claimed`, and forks a worker. The fork is tracked by the engine; the manager holds the fork handle.

3. **Run.** Inside the fork, the worker invokes the registered function with the row's args. The fork has whatever role-restricted capabilities the spider was granted — typically network access (for `%net.fetch`) but no Mikobase write capability.

4. **Report.** The function writes its Xeme to STDOUT via `puts`, then the worker process exits. The manager captures the worker's STDOUT.

5. **Reap.** Worker exits cleanly (`exit 0`). Manager calls `$mgr.wait`, gets the exit status, and parses the **trailing JSON hash** of the captured STDOUT to recover the Xeme. Anything earlier on STDOUT (debug output, progress logs, sub-process output) gets stuffed into the Xeme's `io.stdout` field for forensics.

6. **Record.** Manager writes the Xeme to the job's Mikobase row. Status moves from `claimed` to `done` (or `failed` if the Xeme says so).

7. **Follow up.** Manager inspects the Xeme for the producer-namespaced `enqueue[]` field. For each URL in it, the manager writes a new `pending` row to Mikobase. Those rows get claimed by future iterations of the same loop.

8. **Next.** Manager dispatches the next pending job, spawns a replacement worker. As long as there are pending jobs and free concurrency slots, the loop keeps going.

When the queue empties (no pending rows, no claimed rows), `$obrien.run` returns.

---

## Failure modes

The spider exercises several of O'Brien's failure paths concretely:

- **HTTP error (404, 500, etc.).** Worker catches the bad status and writes `{success: false, errors: [{class: 'spider/error/http_status', status: 404}]}` to STDOUT. Manager parses and writes that Xeme; status becomes `failed`.

- **Network timeout.** `%net.fetch` raises a timeout exception. The worker doesn't catch it. The worker process exits non-zero with no STDOUT output (or with partial output). Manager constructs a default failure Xeme: `{success: false, errors: [{class: 'bryton/runtime/crashed', exit_code: N}]}` and writes it. Note: the worker COULD catch the timeout itself and write a more informative Xeme to STDOUT (`spider/error/timeout` with the URL and elapsed time). The implicit fallback is the safety net.

- **HTML parser crash.** Parser throws on malformed input. Worker dies non-zero. Same fallback as above.

- **Worker STDOUT doesn't end with a valid JSON hash.** Worker exited 0 (or non-zero), but the manager can't find a parseable JSON hash at the end of STDOUT — perhaps the worker never wrote its verdict, or whatever it wrote at the end isn't valid JSON, or a stray write came after the verdict. Manager writes `{success: false, errors: [{class: 'bryton/runtime/unparseable'}]}` with the raw STDOUT captured into `io.stdout` for forensics.

- **Worker killed by OOM.** Spider grabbed a huge page; kernel killed the fork with SIGKILL. Manager sees abnormal exit (signal-terminated, no exit code). Constructs `{success: false, errors: [{class: 'bryton/runtime/crashed', signal: 9}]}` and writes it. The job is permanently failed; consistent with one-and-done semantics.

- **Manager crashes mid-crawl.** Power cut, OOM-killer on the manager, etc. On restart, the manager's startup sweep marks every previously-`claimed` row as failed with `{class: 'bryton/runtime/crashed'}`. The spider then continues with whatever was still `pending` (and nothing was lost since claimed rows were sweep-failed).

In every case, every job ends in a terminal Mikobase row. Nothing is ever stuck in flight.

---

## Inspecting results

Because O'Brien writes every job's Xeme to Mikobase, querying results is just a Mikobase query:

~~~caspian
# All successfully crawled pages
$done = %mikobase.query({
	job:    $execute,
	status: 'done'
})

# All HTTP failures
$http_errs = %mikobase.query({
	job:            $execute,
	status:         'failed',
	'errors.class': 'spider/error/http_status'
})

# All pages that timed out
$timeouts = %mikobase.query({
	job:            $execute,
	status:         'failed',
	'errors.class': 'spider/error/timeout'
})
~~~

The structured Xeme failure taxonomy means classifying failures is just a query filter. No log parsing, no string-matching.

---

## What this example shows about O'Brien

The spider exercises every load-bearing design choice:

- **One-and-done jobs.** Each URL is fetched exactly once. If a fetch fails (timeout, 500, parser crash), it stays failed. No retry. If the user wants retries, they re-enqueue from the dashboard or write a follow-up sweeper that re-enqueues `failed` rows whose errors are transient.
- **One-and-done workers.** Each fetch runs in its own fork. A page that crashes the parser kills only its own worker; the next URL gets a fresh fork. No "the worker pool got into a bad state" possibility.
- **Manager owns Mikobase.** The worker has no write capability. Even if the worker is compromised by a malicious page (a hypothetical bug in the HTML parser), it can't corrupt the Mikobase queue.
- **Xeme as the result format.** Success/failure/null with structured reasons, captured `meta`, captured `data` (the spider's domain payload), producer-namespaced `enqueue[]` for follow-up requests. Everything the spider needs to communicate fits the Xeme shape.
- **Positive-assertion verification.** The spider returns explicit Xemes; a worker that crashes silently before returning gets caught (silent exit-0 with no Xeme = failure under positive-assertion mode). For a spider that actually does work per page, this is the right mode.
- **Per-worker role isolation.** The spider worker runs in a role with network access but no filesystem or database access. The blast radius of a worker bug is bounded.
- **Concurrency via `%utils.forks.multiple`.** Configurable cap (10 in the example); spider doesn't fork-bomb the host or hammer one server. The cap could be lower (1, for a serial crawler) or higher (50, for a beefy host indexing many sites).

A real spider would add features (robots.txt support, per-host rate-limiting, URL canonicalization, content-type sniffing, etc.) but those are spider-level concerns built ON TOP of O'Brien, not features O'Brien provides. O'Brien just runs jobs.
