# Kiera

~~~json
{"vibecode": {
	"doc": "readme",
	"role": "entry-point overview of the Kiera ecoverse and its three core packages",
	"audience": ["humans_landing_on_github", "AIs_orienting_to_the_repo"],
	"key_concepts": ["Kiera_ecoverse", "Kiera_protocol", "Charlie", "Mikobase",
		"design_heavy_implementation_early", "canonical_specs_live_under_documentation"],
	"notes": ["umbrella_name_is_Kiera",
		"directory_named_mikobase_for_historical_reasons_see_CLAUDE_md",
		"deeper_specs_organized_under_documentation_directory"]
}}
~~~

Kiera is an **ecoverse** — a suite of interconnected software for querying
and executing remote objects. Active design and early implementation.

This repository is the working source: design docs, the engine in progress, tests, experimental code.

## The three packages

- **Kiera (the object protocol)** — UNS-addressed remote objects; one shape for working with objects across languages, processes, and machines.
- **Charlie** — a lightweight, embeddable language. Source is Charlie text; the runtime format is **CharlieJSON**, a JSON-shaped AST the engine executes directly.
- **Mikobase** — a live, portable object store. Class-based, NoSQL; queries are JSON.

## Reading the docs

Design specs live under [`documentation/`](documentation/).
