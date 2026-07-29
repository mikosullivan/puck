# Plumbing

<span class="tag">plumbing</span>
<!--index: 4-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_plumbing",
	"role": "concept-family cover page. Plumbing is the collective term for the inbound and outbound edges of the Caspian runtime — faucets bring values in, sinks push values out. This page names the pair and links to each canonical doc; the mechanics of each live in their own subdirs.",
	"audience": "anyone reasoning about data crossing the runtime boundary in either direction"
}}
~~~

**Plumbing** covers the edges of the Caspian runtime — every value that enters or leaves the program does so through one. Two shapes:

- **[Faucets](https://puck.uno/requirements/plumbing/faucets/)** bring values IN. Every inbound value (stdin bytes, an env var, a network response, a `%fetch` object) comes through a faucet with its own role, and the value carries that role.
- **[Sinks](https://puck.uno/requirements/plumbing/sinks/)** push values OUT. Every outbound method (a stdout write, an HTTP request body, a filesystem write) is a method on a sink object, and holding the object is authority to call it.

The two mechanisms are duals but not symmetric: faucets tag inbound values with a source role (provenance), while sinks are role-neutral (capability lives in holding the object, not in role-checking each value). See the individual docs for the load-bearing rules on each side.

## Why the pair matters

- **Provenance and audit.** Every inbound value is tagged with its faucet's role, so questions like "did anything from the network reach the filesystem?" become answerable at the runtime level. Sinks don't role-check outbound values — the check happens by capability handoff, not by payload inspection.
- **Bounded roles and bounded capabilities.** The number of distinct faucet roles equals the number of engine-provided faucets; narrowing (nested dirjails, per-host net wrappers) doesn't mint new roles. Similarly, every sink traces back to an engine-provided object; user code can't invent new outbound paths.
- **Dual surfaces.** Several `%chain.X` methods are BOTH — `%chain.net` is a faucet (responses in) and a sink (requests out); `%fs` is both. Each side is governed by its own model; the object is one identity but plays both roles.

## Canonical docs

- [Faucets](https://puck.uno/requirements/plumbing/faucets/) — inbound edge; role-tagging of pulled values; narrowed-faucets rule.
- [Sinks](https://puck.uno/requirements/plumbing/sinks/) — outbound edge; sinks are just objects; holding-is-access; engine as the only outbound gateway.
