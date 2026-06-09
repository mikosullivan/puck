# Puckai response logging via Jasmine

~~~vibecode
{"vibecode": {
	"doc": "idea_puckai_response_logging_jasmine",
	"role": "placeholder idea note: Puckai's response-logging story (puck.uno/ai/agent's log destination, the worldlet's forward destination, etc.) will be made easy by hooking into Jasmine, the existing Caspian logging package",
	"status": "idea — not designed",
	"related": ["Puckai agent.md (request.audit, request.promise, agent.log, worldlet forward — all being designed)",
		"Jasmine — requirements/caspian/packages/jasmine/",
		"hosted Jasmine ingest service — ideas/apps/logging-service.md"]
}}
~~~

When Puckai's response-handling surface fills in — `request.audit`, `agent.log`, the worldlet's `forward` destination, etc. — the **easy default** for actually persisting responses will be to hook into [Jasmine](../requirements/caspian/packages/jasmine/index.md). Jasmine is already the Caspian logging package; Puckai agent responses are exactly the kind of structured event Jasmine is built to capture.

Concretely: setting `$agent.log = <jasmine-log>` (or whatever the eventual surface is) should be a one-liner, and Jasmine's existing infrastructure (rotation, retention, query, hosted ingest) carries the rest. Puckai doesn't need its own logging mechanism — it inherits one.

Not designed yet. Captured here so the integration story is on the table when the response-handling spec lands.
