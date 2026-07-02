# `%chain.argv`

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_global_utils_argv",
	"role": "spec for %chain.argv — global form of %engine.argv. Same array of command-line arguments, reachable from any role granted %"
}}
~~~

**Default-granted across role boundaries:** no.  

`%chain.argv` is the array of command-line arguments the program was invoked with — the same value as [`%engine.argv`](../../engine/argv), but reachable from any role granted the capability. User code typically reads `%engine.argv` directly; non-user code that needs the args reaches for `%chain.argv` after the user has granted it the capability.

The shape is identical: an array of strings, first element is the first user-supplied argument, may be empty.
