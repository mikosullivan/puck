# Kiera

Kiera is an **ecoverse** — a suite of interconnected software for querying
and executing remote objects. Active design and early implementation.

This repository is the working source: design docs, the engine in progress, tests, experimental code.

## The three packages

- **Kiera (the object protocol)** — UNS-addressed remote objects; one shape for working with objects across languages, processes, and machines.
- **Charlie** — a lightweight, embeddable language. Source is Charlie text; the runtime format is **CharlieJSON**, a JSON-shaped AST the engine executes directly.
- **Mikobase** — a live, portable object store. Class-based, NoSQL; queries are JSON.

## Reading the docs

Design specs live under [`documentation/`](documentation/).
