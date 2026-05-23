# Site

~~~json
{"vibecode": {
	"doc": "site",
	"role": "canonical home for requirements, decisions, and design notes about the puck.uno site itself (as distinct from the Puck ecoverse it documents)",
	"status": "early — populated as requirements get articulated",
	"current_implementation": "Orlando (Lua HTTP server reading local files)",
	"future_implementation": "Gitter (Caspian class fetching from GitHub) — V1 per ideas/github/puck-site/gitter.md"
}}
~~~

Requirements and design notes for the **puck.uno** site itself.

The site is the public face of the Puck ecoverse: it serves the documentation, and over time will host whatever public-facing tooling lives at `puck.uno`. This directory is where decisions about *the site as a product* live — distinct from the documentation it contains (under `documentation/`) and distinct from the ecosystem specs the documentation describes (Caspian, Mikobase, Puck, etc.).

Today the site is served by Orlando (Lua HTTP server, local files). The V1 implementation is [Gitter](../ideas/github/puck-site/gitter.md), a Caspian class that fetches from `mikosullivan/puck` and renders through the same conventions.

## Subsections

### Frameworks

Web-framework choices and considerations for the site live in [frameworks/](frameworks/frameworks.md).
