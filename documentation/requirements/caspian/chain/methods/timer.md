# `%chain.timer`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_timer",
	"role": "spec for %chain.timer — measure elapsed wall-clock time around a block; returns duration in seconds"
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.timer` measures elapsed wall-clock time around a block and returns the duration in seconds.

~~~caspian
$seconds = %chain.timer do
    # ... work to measure ...
end
~~~

The block runs normally; the return value of `%chain.timer` is the duration, not the block's return value. If you need both, capture the block's return inside and read it outside.

Wall-clock time, not CPU time — captures whatever happened during the block, including sleep, I/O wait, and forked-child time the parent waited on. For CPU-only measurements, a separate API would be needed; that's not what `%chain.timer` does.

## Companion: [`%chain.steps`](steps)

For engine-independent benchmarking — "how many steps did this take" rather than "how many seconds" — use [`%chain.steps`](steps). The two are typically used together when characterizing a piece of code.
