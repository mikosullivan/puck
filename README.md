# Kiera

Kiera is an **ecoverse** — a suite of interconnected tools for storing, querying, and programming with objects across languages and systems. It is in active design and early implementation.

This repository is the working source for the whole ecoverse: design docs, the engine in progress, tests, and experimental code.

## Components

- **KScript** — a lightweight, embeddable language. Source is KScript text; the runtime format is **KScriptJSON**, a JSON-shaped AST the engine executes directly.
- **Mikobase** — a live, portable object store. Class-based, NoSQL, queries are JSON.
- **Q0** — the JSON-shaped predicate language used by Mikobase.
- **Roles** — KScript's security model: every object owned by exactly one role; cross-role calls are the security boundary; faucets are the only inbound channel.
- **Trivet** — a generic tree library used by Uma and other tree-shaped consumers.
- **Uma** — HTML library on top of Trivet. CSS selectors compile to **Astro** (a JSON-shaped AST).
- **Touchstone / Sinatra / Robinson** — HTTP middleware. Touchstone is the shared base; Sinatra is the routing-first API; Robinson is the page-based layer.
- **Bryton** — the test framework. Tests emit **Xeme** JSON; the runner walks a directory of test files and aggregates results.
- **Jasmine** — the logging framework.
- **Kiera (the object protocol)** — UNS-addressed remote objects; one shape for working with objects across languages, processes, and machines.

## Repo layout

| Path | Contents |
|---|---|
| `documentation/` | All design specs — language, data store, HTTP middleware, security model, the development plan, idea drafts |
| `code/` | Implementation (Lua-hosted KScript engine, Python Mikobase engine, etc.) |
| `tests/` | Tests for the engine and other components |
| `experiments/` | Small scratch files used for trying things out |
| `web/` | Web-side configuration (nginx, sites) |
| `vscode/` | VSCode extension scaffolding for KScript syntax |
| `LICENSE` | License |

The directory is named `mikobase` for historical reasons — the project started with the data store and grew outward. Today the umbrella name is **Kiera**.

## Reading the docs

The design specs live under [`documentation/`](documentation/). A rendered, browsable HTML version is published at:

**[https://mikosullivan.github.io/kiera-docs/](https://mikosullivan.github.io/kiera-docs/)**

That site is regenerated from `documentation/` and is the easiest way to read the spec end to end. The markdown sources here are canonical; the HTML site is a derivative for easier reading.

Recommended entry points:

- [documentation/overview.md](documentation/overview.md) — the project overview
- [documentation/development/development.md](documentation/development/development.md) — current V1 implementation plan
- [documentation/kscript/kscript.md](documentation/kscript/kscript.md) — KScript language reference
- [documentation/kscript/roles.md](documentation/kscript/roles.md) — the security model
- [documentation/mikobase/mikobase.md](documentation/mikobase/mikobase.md) — Mikobase
- [documentation/kscript/bryton/overview.md](documentation/kscript/bryton/overview.md) — Bryton (the test framework)

## Status

In active design and early implementation. The current development target is **V0.01** — codename `hello-world`. See the [development plan](documentation/development/development.md) for the walking-skeleton roadmap from V0.01 through V1.

## License

See [LICENSE](LICENSE).
