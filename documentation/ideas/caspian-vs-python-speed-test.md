# Caspian vs Python speed test

~~~vibecode
{"vibecode": {
	"doc": "idea_caspian_vs_python_speed_test",
	"role": "design sketch for a fair, defensible speed comparison between Caspian and Python 3.13. Covers what decision the number is meant to inform, methodology pitfalls when one side is a mature runtime and the other is a walking-skeleton transpiler-to-Lua, the benchmark shortlist with per-workload rationale, harness design, what NOT to measure, expectations about losing, and how results should be published without turning into stale marketing.",
	"status": "no_measurements_yet_methodology_only",
	"audience": "language-implementation decisions (JIT-or-not, dispatch-table shape, timing surfaces); anyone eventually publishing numbers under Caspian's name"
}}
~~~

Caspian is a from-scratch dynamic language. Right now it's a Lua-hosted transpiler with the engine being written next to it. Sooner or later somebody — probably Miko, on a slow afternoon — is going to want to know how it compares to Python on speed. This doc is what to do BEFORE running the first benchmark, so the number that comes out is defensible instead of embarrassing for the wrong reason.

## What the number is for

Speed numbers only matter if they change a decision. Before writing any harness, name the decisions:

- **Should Caspian invest in a JIT after V1?** A **just-in-time compiler** (JIT) watches which code paths run hot at runtime and generates specialized machine code for them on the fly, trading startup cost for steady-state speed on repeatedly-executed loops. It's the standard next step for a dynamic language that outgrows a pure interpreter — PyPy has one, LuaJIT has one, CPython 3.13 has an experimental one. A 50× gap on numeric loops against CPython is one answer to whether Caspian needs to travel that road; a 3× gap is a different answer. The number tells you whether the AOT-transpile-to-Lua strategy has enough headroom, or whether the top of the curve is already in sight.
- **Is the current dispatch-table shape carrying its weight?** Object-dispatch benchmarks show whether the platter-stack walk is the tax it looks like on paper, or whether interpreter overhead swamps it either way.
- **Is Caspian a plausible replacement for Python in the ecoverse's dev tooling?** Orlando is Lua today. Bryton is Caspian by design. Assorted repo-maintenance scripts are Python by inertia. If Caspian is within 2× of Python for the shapes those scripts actually run, "just use Caspian" becomes a reasonable default; if it's 20× off, Python stays.
- **Does the "not slow enough to matter" claim hold?** Every language project makes this claim. The number either supports it for specific workload classes or it doesn't. Better to know which.
- **Competitive positioning.** External-facing, this matters least — nobody picks a research-prototype language over Python because of a microbenchmark — but it's still a bar the language has to clear to be taken seriously by anyone who bothers to look.

If none of these decisions are actually on the table, don't run the benchmark. Curiosity is a fine reason to measure things privately; it's a bad reason to publish.

## Fair comparison is hard because "Python" is four runtimes

There is no single "Python" to compare to. There is:

- **CPython 3.13**, the reference interpreter, now with the free-threaded (no-GIL) build option and an experimental JIT. The default apt-installed `python3`.
- **CPython 3.13 with the JIT enabled**, a different runtime for benchmark purposes than the same version without.
- **PyPy**, the tracing-JIT implementation, routinely 4–10× faster than CPython on numeric loops.
- **Cython / mypyc / Nuitka**, the compile-Python-ahead-of-time tools that turn Python into C. Different beast, but people cite these numbers when it suits them.

Caspian has exactly one runtime right now: a Lua-hosted transpiler emitting CaspianJ that a Lua-hosted engine executes. That's a single point on a curve the other side has occupied for thirty years.

**The honest framing:** compare Caspian to **CPython 3.13 without the experimental JIT**. That's what `python3` invokes on a fresh Ubuntu install, which is what most Python code runs under most of the time. Report separately against PyPy when it's illustrative (numeric loops especially) so readers can see the full envelope, but headline against stock CPython.

**Do NOT** headline against PyPy. Comparing a first-pass transpiler-to-Lua against a mature tracing JIT is the language-implementation equivalent of racing a bicycle against a Cessna. The number is meaningless and looks like you're stacking the deck against your own language.

**Do NOT** headline against Cython-compiled Python. That's a different runtime again, and the comparison invites the reply "then compile Caspian ahead of time too" — which the current implementation doesn't do.

Say which Python, which build flags, which version, on every published number. The absence of that information IS a signal that the number is unserious.

## Benchmark shortlist

The workloads worth measuring, each chosen because it isolates a different property of the runtime. Every benchmark exists in Caspian AND in the target Python runtime; no port that requires a numpy-shaped primitive Caspian doesn't have.

### Numeric loops (fib, primes, mandelbrot)

Measures raw interpreter overhead per opcode. Recursive `fib(30)`, sieve of Eratosthenes up to N, a fixed-viewport Mandelbrot iteration count. Zero I/O, no heap growth to speak of, one hot loop.

What it reveals: how much each language pays to execute one arithmetic op. This is where Caspian will lose worst against CPython initially and worst-still against PyPy. That's fine — this benchmark's job is to quantify the gap, not to win.

### String and regex work

Word counting, `.split` / `.join` shuffles, regex-heavy log parsing. Python is unusually good here because much of its string work is in C and its regex engine is a mature C implementation.

What it reveals: whether Caspian's string layer (Lua strings underneath, plus whatever wrapping the engine adds) leaks overhead, or gets close to the C floor.

### Hash-heavy work

Dictionary counters, group-by aggregations, key-lookup-in-a-loop patterns. Python's `dict` is one of the most-optimized data structures in any dynamic language.

What it reveals: how well the engine's hash implementation performs against a target that has had thirty years of profile-guided tuning.

### Object dispatch

Polymorphic method calls in a hot loop — a mixed array of shapes with a `.area` method on each, summed. Something where the receiver's class differs call-to-call, so the dispatch cache (if any) can't degenerate to a single case.

What it reveals: whether the platter-stack walk from [concepts § Classes are the only method-carrier](https://puck.uno/documentation/requirements/concepts#classes-are-the-only-method-carrier) is expensive at runtime, and whether the current no-cache-in-V1 decision (from `documentation/requirements/classes/`) needs revisiting. This benchmark specifically motivates or de-motivates method-lookup caching.

### I/O-heavy (file read, JSON parse)

Read a 100 MB file, count lines. Parse a 10 MB JSON blob into structures and walk it. Represents workloads where the runtime often doesn't dominate — the syscall and libc `read` win, or the JSON parser wins.

What it reveals: for a large class of real programs (CLI tools, ETL scripts, log processors), the "language speed" question is mostly irrelevant. Numbers close to Python's on these workloads let Caspian truthfully claim "for the work most tools do, it doesn't matter which language you picked."

### Startup time

Time from `caspian foo.casp` to first line of output, versus `python3 foo.py` to first line of output. Includes transpile time on the Caspian side. Measured cold (no OS page cache) and warm.

What it reveals: often the single most user-visible number for CLI tools. Python's ≈40 ms cold start is a well-known papercut; if Caspian's is 200 ms every invocation, `caspian` won't feel like a tool people reach for from a shell prompt. If it's under 100 ms, the CLI-tool positioning is viable.

### The shortlist as a table

| Benchmark class      | Property isolated                    | Where Caspian probably lands (V0.1) |
| ---                  | ---                                  | ---                                 |
| Numeric loops        | Interpreter overhead per opcode      | Worst gap — expect 10×–50×          |
| String / regex       | String primitives, regex engine      | Depends on regex library choice     |
| Hash-heavy           | Hash-table implementation quality    | Middle of the pack; Lua tables carry Caspian here |
| Object dispatch      | Method-lookup cost, platter walk     | Motivates or kills dispatch caching |
| I/O-heavy            | Language irrelevance for real work   | Should be close to Python           |
| Startup              | Cold-start UX for CLI tools          | Watch this one — transpile cost adds up |

## What NOT to benchmark

- **numpy-shaped workloads.** Caspian has no first-party equivalent to numpy. Comparing a Caspian for-loop over 10 million floats against `numpy.sum` is comparing Caspian against C. Skip until Caspian has a first-party numeric-array primitive worth benchmarking.
- **Ecosystem-dependent tasks.** "Web framework hello world" is a benchmark against Flask/FastAPI, not against Python. Caspian doesn't have a mature web framework. Wait.
- **Microbenchmarks in isolation, without accompanying real-program benchmarks.** A pure `fib(30)` number tells you the interpreter overhead but nothing about whether that overhead matters for anything anyone runs. Always pair a microbenchmark with at least one realistic-program benchmark that exercises similar primitives, so readers see both floors.
- **Anything before Caspian V1.** Publishing numbers against a walking-skeleton implementation risks setting an anchor the language then has to justify or beat. Keep pre-V1 measurements internal; publish nothing until the language has stabilized past V1 and the engine's second-pass optimization has landed. The "not for publication" tier can still measure — it just doesn't leave the repo.
- **AI-tool subjective speed.** "How fast does Caspian feel while I write it in Cursor" is not a language benchmark, however tempting.

## Harness design

The harness is where credibility is won or lost. It has to survive the "why should I trust this?" reading.

### Timing surface

Wall-clock is what users experience; CPU time is what removes noise from other processes. Report both.

For sub-millisecond measurements, `%now` may not give adequate resolution — the [`%now` spec](https://puck.uno/documentation/requirements/chain/methods/now) doesn't yet pin down clock precision, and the engine-controlled indirection means "high-resolution monotonic timer" needs to be an explicit surface, not an assumption. If the resolution turns out to be milliseconds-only, benchmarks that take under ≈10 ms per iteration need to loop internally to a measurable duration, or a separate `%engine.monotonic_ns` (or equivalent) needs specifying before the harness can be written. This is a real dependency on a spec that doesn't exist yet; note it as a blocker rather than papering over it.

### Warmup and iteration count

- Discard the first N iterations (warmup). N is usually 5–10 for interpreters; for JITs, 100+.
- Run at least 1000 iterations after warmup, or until the fastest observed run stabilizes.
- Report **percentiles (p50, p95, p99)**, not means. Means get destroyed by GC pauses and OS scheduling noise. Percentiles are honest about the distribution.
- Report the fastest observed run separately — it's the closest thing to "the language, without noise."

### Environmental control

- Same hardware, same OS, same kernel version, same power profile (no laptop battery-saver kicking in mid-run).
- CPU governor pinned to performance mode.
- No other user processes running.
- Network disabled for benchmarks that don't need it.
- Cold-cache and warm-cache runs reported separately for I/O benchmarks.

Skipping any of these lets a reviewer dismiss the whole run.

### Result artifact

Every run produces a JSON blob. Shape:

~~~json
{
	"benchmark": "fib30",
	"language": "caspian",
	"runtime_version": "0.1.3-dev+abc123",
	"target": "cpython-3.13.1",
	"target_build_flags": ["--enable-optimizations", "--no-jit"],
	"machine": {
		"cpu": "AMD Ryzen 9 7950X",
		"cpu_governor": "performance",
		"ram_gb": 64,
		"os": "Ubuntu 24.04",
		"kernel": "6.8.0-136-generic"
	},
	"iterations": 1000,
	"warmup_discarded": 10,
	"timing_unit": "ns",
	"wall_p50": 4823119,
	"wall_p95": 5102003,
	"wall_p99": 5388711,
	"wall_min": 4718203,
	"cpu_p50": 4801022,
	"utc_run_at": "2026-07-23T18:22:04Z"
}
~~~

Versioned by the tuple `(Caspian version, target version, machine fingerprint)`. A blob without all three keys is a blob you can't reproduce and shouldn't publish.

### Harness language

Three options for what the harness itself is written in:

- **Caspian.** Dogfooding. Also the honest choice — a harness written in Caspian exercises the same runtime it's measuring, which surfaces the "our measurement code adds N ms of overhead" problem where it can be inspected.
- **Bryton.** Caspian's test framework. Same benefits as Caspian, plus reuses existing runner infrastructure. Once Bryton exists.
- **A neutral shell layer (bash, or a small Lua script).** Times both sides externally, no in-language measurement bias, but adds process-start overhead to every measurement and can't easily do per-iteration timing.

Recommendation: **shell-layer harness for startup and end-to-end runs; Caspian in-process harness for per-iteration microbenchmarks**, once Caspian has a monotonic-nanosecond timer surface. Report which was used per benchmark.

## What "loses" means

Caspian is going to lose to CPython in most microbenchmarks initially. Say it out loud in the results page. The interesting number isn't whether Caspian loses — it's:

- **By how much.** A 2× slowdown on numeric loops is impressive for a first pass. A 100× slowdown is a signal that the transpiler is producing pathologically-slow Lua, and the fix is to look at the emit strategy, not to fret about JIT plans.
- **On which workloads.** Losing on numeric loops is expected; losing on hash operations would be surprising and worth investigating (Lua tables are excellent). Losing on I/O-heavy work would be embarrassing and would indicate a real bug.
- **Whether the gap closes per release.** The trend line matters more than the point measurement. A V0.1 baseline that's 30× off, closing to 15× at V0.2 and 8× at V0.3, is a language on a trajectory. Same 30× still there at V1.0 is a language that has a problem.

Concrete thresholds worth naming in advance, so the discussion doesn't become "well, that's not so bad":

- **Under 2× of CPython on I/O-heavy real-program benchmarks** — the "not slow enough to matter" claim holds for that class of work.
- **Under 5× on hash and object-dispatch benchmarks** — the language is competitive for the kinds of programs Caspian is meant to be good at.
- **Under 20× on numeric loops** — no JIT is needed yet; the language is behaving like a reasonable AOT-compiled dynamic language.
- **Over 20× on numeric loops** — start planning a numeric-loop optimization pass or a JIT experiment.
- **Startup under 100 ms cold** — CLI-tool positioning is viable.

None of those are pass/fail gates. They're the numbers to argue against when the actual measurements come in.

## Publishing

Results are load-bearing PR material once published — they become the anchor for every future "is Caspian fast enough?" conversation. That means the publishing surface has to be built to age, not to launch.

- **Home for results:** a `documentation/benchmarks/` page (does not exist yet; not being created by this doc — the point is that when the first real benchmark run happens, that's where its output lives). Machine-readable JSON alongside human-readable prose. Not Miko's blog — a blog post is a snapshot in time and gets stale invisibly; a docs page is expected to reflect current state.
- **Versioning:** every published number is tagged with (Caspian version, target Python version, harness version, run date). Old numbers stay visible under their version tag so trend-over-time claims are checkable.
- **Freshness policy:** numbers older than one Caspian minor version get a visible "stale" banner. The dashboard renders results with the banner automatically based on the current Caspian version, so the staleness doesn't require anyone to remember to update it.
- **Never publish a single number without its methodology paragraph.** "Caspian is 3× slower than Python on X" without the harness details is exactly the shape of marketing garbage the project should be embarrassed to produce.
- **Never publish geometric means across benchmark categories.** "Caspian is on average N× slower than Python" collapses information that readers need. Publish the per-benchmark numbers; let readers do their own arithmetic if they want a single figure.
- **Publish nothing before V1.** Repeat: nothing. Pre-V1 measurements are for the implementers. Once published, numbers acquire gravity that a walking-skeleton implementation can't support.

## Follow-on questions

Deliberately unresolved. Each is its own design decision:

- **What monotonic-nanosecond timer surface does Caspian expose?** `%now` is a wall-clock reading with unspecified resolution. Benchmarking wants a separate high-resolution monotonic timer, probably as `%engine.monotonic_ns` or similar. Needs its own spec pass before the harness can be written in Caspian.
- **Does the harness itself need a role model?** A benchmark reading its own timings and writing its own result artifact runs as `user`, so it can touch `%engine` freely. If the benchmark also wants to run other people's code (e.g., a benchmark suite fetched from a URL), the code-under-test lands with a downloaded role and can't reach the timer. Interface between the two needs designing before third-party benchmark contributions can happen.
- **Is Bryton the right home for the benchmark runner, or is it a separate tool?** Bryton is for correctness tests; benchmark runs have different needs (warmup semantics, percentile aggregation, environmental checks). Might be a sibling tool that shares Bryton's discovery mechanism but not its runner.
- **Cross-machine result comparison.** Miko's laptop is not a benchmark server. If numbers get published from multiple contributors' machines, they need a normalization strategy — either a fixed reference machine, or a portable scaling factor derived from a calibration benchmark. This is a whole design problem in its own right.
- **Where do sibling comparisons live?** Caspian vs Lua (the host language), Caspian vs Ruby, Caspian vs the various JS runtimes. If the answer is "same harness, more targets," fine — but the multi-target UX in the results page needs planning early so it doesn't become a per-language grid of prose.
