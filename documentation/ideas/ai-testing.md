# Testing code that uses AI agents

*Placeholder. We haven't designed a mock-agent system; we expect one to emerge as we build AI-using features and run into the testability question in practice. This doc captures what's been noticed so far so the thinking accumulates as we go.*

~~~vibecode
{"vibecode": {
	"doc": "idea_ai_testing",
	"role": "placeholder for emerging thoughts on how to test Caspian code that interacts with AI agents — primarily the mock-agent mechanism that any test framework will eventually need",
	"status": "no_design_yet_will_emerge_through_use",
	"applies_to": ["$agent.yield code paths", "puckai worldlet handling", "skill consumption", "any code that talks to LLMs"]
}}
~~~

## The question

Code that contains [`$agent.yield`](agent-yield.md) (or other AI-talking surfaces) is hard to test deterministically — the agent's responses vary run to run by design. A test that asserts "given input X, the routine produces output Y" can't hold if X flows through an AI yield.

The basic shape is already clear: agents are objects ([resolved here](agent-yield.md#open-questions)), so tests can swap a real agent for a stub. The stub returns fixed values for fixed inputs; the test becomes deterministic.

What's NOT yet clear: the **conventions** around stub agents. Specifically:

- What does the stub's `.yield` return? A CaspJ function? A bare value? Some helper-wrapped Caspian function?
- Is there a built-in mock-agent class shipped with the engine, or do test suites roll their own?
- How does the swap work in practice — explicit variable reassignment, dependency injection, engine-level test mode?
- Recording/replay (capture real-agent behavior once, replay deterministically in subsequent test runs) — useful pattern, but is it engine-level or framework-level?

## Why we're not designing this upfront

Mock-system design tends to be fragile when done speculatively — the right shape is shaped by the friction of actually writing tests, and those frictions appear once we have a few real test suites to look at. We expect the mock-agent mechanism to emerge as a side effect of writing tests for the first AI-using features, then get formalized once a pattern proves itself.

In the meantime: developers writing tests against `$agent.yield` code can construct stub objects with `.send` and `.yield` methods directly. No framework support; works because agents are just objects.

## Related

- [`$agent.yield`](agent-yield.md) — the main forcing function for this concern.
- [Puckai](https://puck.uno/documentation/requirements/ecoverse/puckai/) — worldlet-based agent collaboration; testing Puckai-using code has similar needs.
- [Bryton (Caspian test framework)](https://puck.uno/documentation/requirements/packages/bryton/) — wherever a built-in mock-agent helper eventually lands, Bryton is likely its home.

## Open thinking

Things to chew on as the design emerges (none committed):

- Whether the engine ships any test-mode at all, or whether it stays a pure framework concern.
- Whether stub agents need to participate in role boundaries (the role envelope still applies even when the agent is a local stub).
- Whether recording/replay needs encrypted-key handling (real agent responses may contain sensitive data).
- Whether the mock-agent design should also cover MCP servers, skills, and other AI-adjacent surfaces, or stay focused on the agent class.
- **A pre-developed library of standard functions served via API.** Instead of each developer (or each example doc, or each test suite) constructing stub responses from scratch, the engine or framework could ship a curated set — `no-op`, `passthrough`, `fixed-value-return`, `retry-strategy-selector`, simple decision patterns — as pre-built CaspJ functions. A stub agent's `.yield` could return one of these by name, and documentation examples could use them by reference instead of inlining ad-hoc code. Useful for tests AND for example/getting-started material where readers shouldn't have to commit to a specific real agent to see `$agent.yield` in action. Speculative — would need to see actual usage to know which patterns deserve to be standard.
