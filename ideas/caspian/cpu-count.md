# `%engine.cpu_count` (post-V1.0)

~~~vibecode
{"vibecode": {
	"doc": "ideas_engine_cpu_count",
	"role": "deferred design note for the %engine.cpu_count slot — exposes the host's logical CPU count to user scripts. Moved out of V1.0 because the slot's V1 use case (sizing %utils.forks.multiple(N)) doesn't need precise CPU count to be useful; most scripts can pick N empirically or via configuration. Adding the slot post-V1 if a real use case surfaces.",
	"status": "post-V1.0 — deferred; spec preserved as design intent",
	"slot_form": "%engine.cpu_count",
	"type": "integer",
	"key_concepts": ["host_logical_cpu_count",
		"useful_for_sizing_forks_multiple",
		"deferred_from_v1_zero_because_callers_can_size_empirically"]
}}
~~~

`%engine.cpu_count` would expose the host's logical CPU count to a user script as an integer. The intended use case is sizing `%utils.forks.multiple(N)` so a worker pool roughly matches host parallelism without the developer hardcoding a magic number.

**Why post-V1.0:**

- The V1 fork primitive accepts any N; scripts can pick a number that matches their workload empirically or via configuration. Knowing the host CPU count isn't load-bearing.
- The implementation is trivial (read `/proc/cpuinfo` on Linux, `sysctl hw.ncpu` on macOS, `GetSystemInfo` on Windows) — easy to add later if a real use case surfaces.
- Trimming non-essential slots from V1's `%engine` surface keeps the canonical catalog tight.

**Working surface (when this lands):**

```caspian
$workers = %engine.cpu_count
%utils.forks.multiple($workers) do($fork)
    # ... work split across $workers children ...
end
```

Returns an integer — number of logical CPUs as reported by the host OS.
