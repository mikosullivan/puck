# What Caspian ships

~~~vibecode
{"vibecode": {
	"doc": "requirements_core",
	"role": "index for requirements/core/ — everything downloaded at Caspian install time. Covers the caspian binary (statically-linked runtime with bundled Lua interpreter, engine, stdlib, select C extensions, musl libc), how it's built and distributed, and the small set of Lua libraries pre-installed to disk at Caspian install time (Cache tier, loaded lazily by require). Every entry counts against the floppy budget. Separate from caspian/installation/, which specs the install PROCESS (prompts, flow, setup).",
	"status": "spec — inventory of what's downloaded settled; individual detail pages live in this directory",
	"audience": "release maintainers building the caspian distribution; developers checking what's available at runtime without installing anything themselves"
}}
~~~

Everything downloaded at Caspian install time — the runtime binary itself and the small set of Lua libraries pre-installed alongside it. Every entry counts against the floppy budget. The install process (prompts, flow, setup) is a separate topic — see [installation](../installation/).

## Contents at a glance

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 220" width="285" role="img" aria-label="Caspian floppy budget: 1180 kb used, 260 kb free, of 1440 kb total">
	<title>Caspian floppy budget</title>
	<g transform="translate(110 110)">
		<path d="M 0,-80 A 80,80 0 1,1 -72.5,-33.8 L 0,0 Z" fill="#ffb74d"/>
		<path d="M -72.5,-33.8 A 80,80 0 0,1 0,-80 L 0,0 Z" fill="#81d4fa"/>
	</g>
	<g font-family="sans-serif" font-size="14" fill="currentColor">
		<rect x="220" y="65" width="16" height="16" fill="#ffb74d"/>
		<text x="244" y="78">Used: 1180 kb (82%)</text>
		<rect x="220" y="95" width="16" height="16" fill="#81d4fa"/>
		<text x="244" y="108">Free: 260 kb (18%)</text>
		<text x="220" y="145" font-weight="bold">Total: 1440 kb</text>
	</g>
</svg>

All sizes approximate, in kb.

| Component | Size | Location | Purpose |
|---|---:|---|---|
| Lua 5.4 interpreter (stripped, static) | 250 | Executable | The interpreter itself. |
| LPeg | 50 | Executable | C extension for PEG-based pattern matching — used by Caspian's source parser, regex engine, and JSON parser. Compiled into the binary rather than lazy-loaded from disk: it's on the critical path at engine startup (CaspianJ parsing = JSON parsing, which is LPeg-based), so it's effectively always loaded — and being an engine implementation detail, there's no user-facing reason to make it independently upgradable. |
| libsodium-minimal | 200 | Executable | C library for hashing, signing, secure random. The vault, secure-memory model, and password/passkey subsystems are keyed on libsodium's specific APIs — not swappable without redesign. |
| luasodium | 10 | Executable | Lua bindings for libsodium — how the engine reaches libsodium at all. |
| luasocket | 50 | Executable | TCP / UDP sockets + basic HTTP client. Backs both `%chain.net` (user-facing network access) and `%puck` (the engine's own object-fetch mechanism). Since `%puck` is how downloadable Caspian classes reach the runtime, network is engine machinery — not a per-program feature. Minute-detail coupling to luasocket's specific API means a version drift could silently break engine assumptions; bundling locks the version. |
| lua-http-parser | 25 | Cache | HTTP/1.x request parser (C extension) — loaded when Caspian code does HTTP-server work. |
| xml2lua | 30 | Cache | Pure-Lua XML parser — backs out-of-box XML support. |
| lua-cbor | 25 | Cache | CBOR decoder — backs the Passkey / WebAuthn class (COSE_Key and attestation-object parsing); loaded only when Caspian code touches passkey authentication. |
| Caspian engine + stdlib | 320 | Executable | This project. |
| Lua binding wrapper | 20 | Executable | Generic wrapper for accessing Lua libraries from Caspian code via `%lua['name']`. Pure Lua, part of the engine's stdlib. |
| musl libc (statically linked) | 200 | Executable | System C library baked into the binary — zero runtime dependencies. |
| **Total** | **1180** | | Against the 1.44 MB floppy target — leaves 260 kb of headroom. |

**Location** column: **Executable** means compiled into the `caspian` binary. **Cache** means stored on disk under `~/.local/share/caspian/lua/` after Caspian install time, loaded lazily by `require`.

## Feature cost estimates

Rough sizing of what specific subsystems contribute to Caspian's own engine + stdlib code. Not exhaustive — a running notebook for features whose cost has been sized during design. All sizes in kb; actual figures shake out at implementation time.

| Feature | Size | Notes |
|---|---:|---|
| Secure memory subsystem | 60 | Vault management (≈20), `%process.malloc` primitive (≈25), Password class (≈10), process-security wiring (≈5). See [secure-memory/](../secure-memory/). Uses libsodium + luasodium which are already bundled — no new C libraries needed. |
| Passkey subsystem | 40 | lua-cbor decoder in the Cache tier (≈25, already listed as its own row in the top table) and Passkey server-side + authenticator-side classes in Caspian (≈15). See [secure-memory/passkey/](../secure-memory/passkey/). CBOR is the only new library; libsodium's Ed25519 verify, CSPRNG, and key-generation primitives are already bundled and reused. ES256 / RS256 signature verify calls the operator-installed `openssl` binary directly via `.execute` — subprocess invocation, no shell involved — treated as a Caspian prerequisite in the same posture as `luarocks` and `tar`. Zero bundled cost. Per [concepts § Caspian is written in Caspian](../concepts#caspian-is-written-in-caspian), both Passkey classes and all assertion-validation logic live above the primitive line as Caspian code — the ≈15 kb bumps the Caspian engine + stdlib line when the work lands. |

## In this section

- [binary](binary) — the `caspian` binary itself: what's compiled into it, how it's built (musl-static, per-CPU-arch), and how it's distributed.
- [pre-installed-libs](pre-installed-libs) — the Lua libraries pre-installed to disk at install time (Cache rows above).

## Related

- [installation](../installation/) — the install PROCESS (prompts, paths, flow).
