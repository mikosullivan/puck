# `%chain.timeout`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_timeout",
	"role": "spec for %chain.timeout — cap a block's wall-clock duration; raises if the block doesn't return in time"
}}
~~~

**Default-granted across role boundaries:** yes.  

`%chain.timeout(seconds) do ... end` runs the block under a wall-clock budget. If the block returns within `seconds`, the call returns whatever the block returned. If the budget elapses first, a timeout exception is raised in the block's frame.

~~~caspian
%chain.timeout(10) do
    # work that must finish within 10 seconds
end
~~~

## `unwind:` keyword

By default, a timeout raises a normal exception that can be caught with the usual exception handling. The `unwind:` kwarg controls a quieter mode:

~~~caspian
%chain.timeout(3600, unwind: true) do
    # ...
end
~~~

With `unwind: true`, the block unwinds without an exception bubbling out — useful for "best-effort within N seconds" cases where you want partial work to take whatever it took and move on. Full semantics for the unwind variant are still settling.

## Granularity

The check happens at safe points inside the interpreter, not mid-instruction. Pure-CPU loops that never reach a safe point will overrun the budget; in practice that's rare since virtually any Caspian operation reaches a safe point quickly.
