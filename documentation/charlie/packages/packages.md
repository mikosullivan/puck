# Charlie packages

~~~json
{"vibecode": {
	"doc": "packages",
	"role": "umbrella landing page for the Charlie standard packages — Bryton, Jasmine, Touchstone, Trivet. Each has its own spec under packages/<name>/; this page just collects them."
}}
~~~

The packages bundled with Charlie. Each is a separate spec.

- **[Bryton](bryton/)** — language-agnostic test runner that walks a
  directory of test files and aggregates results in Xeme JSON.
- **[Jasmine](jasmine/)** — structured logging spec, with a file
  format and a directory store.
- **[Touchstone](touchstone/)** — the base HTTP middleware class.
  Sammy is the built-in route-style framework on top.
- **[Trivet](trivet/)** — generic tree library (node / child_set /
  document classes), used wherever the framework deals with trees.
