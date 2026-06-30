# `%engine.argv`
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_engine_argv",
	"role": "spec for %engine.argv — the array of command-line arguments the host passed to the engine when the program was invoked",
	"shape": "array of strings"
}}
~~~

`%engine.argv` is the array of command-line arguments the program was invoked with, as supplied by the host. The first element is the first user-supplied argument — the launcher binary's own name is not included.

When the host is a CLI runner, `%engine.argv` reflects the shell tokens that came after the program file path. When the host is an embedded runtime (Python, JavaScript, a test harness), the host decides what to place here — typically the analogous list of program arguments if there's one, or an empty array.

Every element is a string. The array may be empty.
