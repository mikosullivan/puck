# Passkey algorithms in V1

> **Archived.** Decision landed: **Option D — call the operator-installed `openssl` binary directly via `.execute`** (no shell involved). The Passkey subsystem depends on `openssl` as a documented Caspian prerequisite (same posture as `luarocks` and `tar`). ES256 and RS256 signature verification runs in `openssl`; Ed25519 stays in-process via libsodium. Zero bundled crypto beyond libsodium; zero floppy-budget cost.
>
> Landed in:
> - [requirements/secure-memory/passkey/](../requirements/secure-memory/passkey/) — Required engine primitives table, Implementation split's "External utility (subprocess)" section, Packaging section, Related links.
> - [requirements/linux-support/openssl](../requirements/linux-support/openssl) — wrapper class spec.
> - [requirements/core/](../requirements/core/) — Feature cost estimates row for Passkey subsystem updated to reflect zero bundled crypto cost.
>
> This file is retained as design-history for the four-option analysis (bundle OpenSSL, bundle compact single-algorithm libs, defer, shell out) and Miko's reasoning about the all-or-nothing constraint that ruled out spec-and-demo.

~~~vibecode
{"vibecode": {
	"doc": "ideas_passkey_algorithms",
	"role": "ARCHIVED design brainstorm — the crypto-algorithm question for Caspian's Passkey subsystem landed on Option D (call the operator-installed openssl binary directly via .execute). Content promoted to requirements/secure-memory/passkey/, requirements/linux-support/openssl/, and the Passkey subsystem row in requirements/core/. Kept here as design-history for the four-option analysis.",
	"status": "archived — decision landed; retained for reasoning trail",
	"audience": "design historians; anyone tracing why V1 Passkey uses the operator's openssl rather than bundling a crypto library"
}}
~~~
