# Downloads

*The different ways libraries get pulled into a Caspian process.*

~~~vibecode
{"vibecode": {
	"doc": "downloads_hub",
	"role": "hub for the downloads area — the spec for how libraries are pulled into a running Caspian process. %puck is the library faucet; the subdirs here document the sources it pulls from.",
	"audience": ["Caspian programmers and operators reasoning about where their libraries come from",
		"implementers of any of the download mechanisms"],
	"key_concepts": ["puck_is_a_library_faucet",
		"search_path_is_ordered_array_of_fetchers",
		"all_fetchers_share_a_standard_api_polymorphic_implementation",
		"downloads_describes_the_sources_puck_pulls_from",
		"versioning_decides_which_version_downloads_decides_where_from"]
}}
~~~

`%puck` is a **library faucet** — it brings library data into the running process. The downloads area documents the **different sources** the faucet can pull from, plus the on-disk and network-side mechanisms each source involves.

This is distinct from [versioning](../versioning/): versioning decides **which version** of a library a lookup picks; downloads decides **where the bytes for that version come from**. Both apply to every `%puck[uns]` call; versioning constraints filter first, downloads provides the bytes.

## The search path

`%puck` holds an **ordered array of fetchers**, each capable of retrieving a library by URL. When a lookup happens, `%puck` walks the array and asks each in turn until one returns the library — or the list runs out and the lookup fails.

This is search-path semantics, the same shape as `PATH` for executables or the provider chain in any layered lookup system. Each entry in the array is one fetcher: a cache, a mirror like blockchain.puck.uno, a direct-publisher fetch, a private mirror configured by the operator, anything that satisfies the fetcher contract.

### The fetcher API

All fetchers implement the **same standard API** — at minimum, "given a URL (and any active version constraints), return the bytes or null." Polymorphism happens behind that API: one fetcher checks a local cache, another does a direct download from the publisher, another talks to a blockchain.puck.uno-style service, another walks a private mirror, anything that fits the contract. `%puck` doesn't care how a fetcher actually does it; it just calls the API and uses what comes back.

The standard API is what makes fetchers composable. Any operator (or library) can implement a new fetcher — for a private mirror, an in-memory test cache, an embedded set of pre-baked libraries, a different signature-verification scheme — and slot it into the search path without `%puck` needing to know anything special about it. The three documented mechanisms below are the well-known implementations; they're not the complete set.

### The install-bundled cache is always first

When Caspian is installed, the bundled standard libraries are written to a [cache](caching/) — the same on-disk layout user-facing caches use. That install-bundled cache is **always the first fetcher in `%puck`'s search path by default**, and downstream fetchers (network mirrors, direct fetch, private caches) extend the path after it rather than displacing it.

Two reasons this matters:

- **Bootstrapping.** The engine has its core libraries available before any network access is possible — even a fresh, never-online install has a working `%puck[uns]` for everything that ships in the box.
- **Predictability.** The bundled libraries are versioned at install time; subsequent fetchers can't shadow them with different builds of the same URL unless the operator explicitly reorders the path. The first-position guarantee is what makes the install reproducible across deployments.

### Typical search path is several cache layers, then network

In a realistic deployment, the search path is **a layered list** — typically several cache-style fetchers in front, then any network-touching fetchers. A common shape:

1. **Install-bundled cache** (always first) — the libraries shipped with the Caspian install.
2. **User-owned cache** — per-user storage, e.g. `~/.config/caspian/...` (path TBD).
3. **System-wide cache** — host-level shared storage, wherever the platform puts system caches (path TBD).
4. **Engine-supplied shared cache** — when the engine offers one for multi-process sharing.
5. **Network fetchers** — service ([blockchain.puck.uno](service/) or a private mirror) and/or direct URL fetch to the publisher.

Any of these layers can be present or absent depending on how the engine is configured; the order is policy, not protocol. Operators can also install fetcher implementations not listed here — anything that satisfies the [fetcher API](#fetcher-api) slots in.

The three [well-known implementations](#sources-documented-here) below are **types**, not the literal entries you'd expect in a deployed path. A real path holds *instances* of those types (one user cache + one system cache + one mirror + ... ), often with several cache instances stacked before anything reaches the network.

### Each fetcher has its own role; data inherits it

**Every fetcher has a role**, and **objects retrieved through a fetcher are owned by that fetcher's role**. Two fetchers in the same search path — say, the install-bundled cache and a network mirror — produce objects with different role ownerships, even when they happen to retrieve the same URL. Faucets inside a fetcher share the fetcher's role.

This is the role model's natural extension into the download path. See [roles.md](../roles.md) for the broader ownership rules; see [ideas/puck-object.md](../../../ideas/puck-object.md) for the fetcher-level discussion of why per-fetcher roles matter. Practical consequence: an operator who wants stronger separation between, say, "trusted bundled code" and "anything else" gets that for free as long as those sources are different fetchers in the path — no extra wiring needed beyond installing the fetchers under distinct roles.

**Order is configuration.** The default order is set at the engine layer (and may be locked down per the [engine envelope rules](service/index.md#opt-in)); user code can narrow within whatever the engine allows. Typical orderings put the cache first (fastest), then a chosen network source (mirror or direct), but the order is policy, not protocol.

**Failure is collective.** Only when *every* entry in the array fails to produce a match does the lookup raise [`puck.uno/error/out_of_range`](versioning/timestamp.md#out-of-range-alarm). Individual entries returning null are not errors; they're "this entry can't help, try the next one."

(One open semantic question to settle when this gets fully spec'd: **first-hit vs. consult-all-then-pick-latest**. The simple search-path model is "first one that satisfies the constraint wins"; the existing [resolution rules in versioning/timestamp.md](../versioning/timestamp.md#resolution-rules) say *"finding the latest requires consulting all fetchers, not short-circuiting on first hit."* For exact pins these are equivalent; for range queries they're not. Pinning the rule is its own design question; out of scope here.)

## Sources documented here

Three well-known fetcher implementations — concrete types that satisfy the [fetcher API](#fetcher-api) and slot into `%puck`'s search path:

| Subdir | Source | Role |
|---|---|---|
| [caching/](caching/) | Local on-disk cache | Fastest path — once a library has been pulled in once, it lives in the cache and subsequent lookups don't go to the network. Also the foundation for cache-only / network-isolated security postures. |
| [service/](service/) | blockchain.puck.uno (the public Puck library service) | A common-mirror + chain-verified-signatures download endpoint. Opt-in. Includes the [blockchain](service/blockchain/) implementation that backs the signature checks. |
| Direct URL fetch | The publisher's own HTTPS endpoint, derived from the URL | The simplest mechanism: translate the URL to a URL (e.g. `borg.com/parser` → `https://borg.com/parser`) and fetch the bytes from there. No intermediary mirror, no chain check beyond what the program itself runs. The publisher's TLS certificate is the only credential involved. **The engine has no default for this** (consistent with the engine's bare-defaults-locked posture); **the Caspian CLI defaults to permitting direct download** so casual `caspian script.casp` invocations work the way developers expect. Spec lives inline here for now; promote to a subdir if the mechanism grows. |

Other sources (private mirrors, future mechanisms) are configuration of the engine's fetcher / faucet chain rather than self-contained mechanisms with their own specs.

## User-facing surfaces

Two `%puck`-level surfaces control library loading. They're **orthogonal**:

- **`%puck.sources`** — the ordered array of [fetchers](#the-search-path) in the search path. Direct assignment replaces it; `.clear do ... end` empties it for a block (testing pattern: ensure no fetches happen inside the block). See [service/index.md § %puck.sources](service/index.md#puck-sources--the-fetcher-array).
- **`%puck.blockchain`** — the signature-verification policy. `true` for the default Puck chain; a URL for a specific chain; `null` or `false` for no verification (the default). Verification is universal: every cache read checks against the configured chain. See [service/index.md § %puck.blockchain](service/index.md#puck-blockchain).

These answer different questions: `sources` controls *where libraries come from*; `blockchain` controls *whose signatures are trusted for verifying them*. Either can be set independently.

## Reading order

A reader new to the area generally wants:

1. **[caching/](caching/)** first — the cache is what every other source eventually populates, and its layout determines what "having a library locally" looks like on disk.
2. **[service/](service/)** second — blockchain.puck.uno is the canonical public download mechanism and the simplest non-local network source to reason about.
3. **Direct URL fetch** third — the raw "just go to the URL" path, useful to understand for cases where the program needs (or is configured to) bypass the mirror.

The other concerns — engine source policy, allowed-source allowlists, eval gates — live in [service/](service/) since they're about controlling what the faucet draws from, not about the faucet itself.
