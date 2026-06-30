# Bootstrap
<!--index: 1 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bootstrap_root",
	"role": "index for the bootstrap/ directory — how a Caspian engine comes into existence, gets configured by a host, and starts running a program. Stub: each subdoc owns a layer of the bootstrap story; this page points readers at the right one.",
	"audience": "anyone writing a host that loads Caspian, or anyone reasoning about what's true the moment user code starts running"
}}
~~~

Three docs cover bootstrap, each at a different level of abstraction.

## [initialization](https://puck.uno/documentation/requirements/caspian/bootstrap/initialization)

The conceptual lifecycle — what's happening from host process startup through to the first user-program statement, in language-agnostic terms.

## [engine-creation](https://puck.uno/documentation/requirements/caspian/bootstrap/engine-creation)

The Lua-mechanical view — what the engine actually IS at the code level, how a host loads the module, and how the host installs properties on it.

## [startup-scenarios](https://puck.uno/documentation/requirements/caspian/bootstrap/startup-scenarios)

Worked end-to-end examples — full code for real hosts (CLI runner, Python embedding, JavaScript embedding) loading the engine, configuring it, running a program, and reading the result.
