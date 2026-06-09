# blockchain.puck.uno

*The public library-download service operated by Puck.uno. Opt-in.*

~~~vibecode
{"vibecode": {
	"doc": "libs_puck_uno_service",
	"role": "spec for blockchain.puck.uno — the public-API service that provides a common download mirror for Caspian libraries and verifies signatures against the Puck blockchain before serving. Opt-in: programs can use blockchain.puck.uno or fetch libraries directly from their original hosts.",
	"audience": ["Caspian programmers deciding whether to route library fetches through blockchain.puck.uno",
		"implementers of the blockchain.puck.uno service",
		"library publishers whose artifacts are mirrored / verified by the service"],
	"key_concepts": ["opt_in_not_mandatory",
		"common_download_mirror_for_resilience",
		"signature_verification_against_blockchain_before_serving",
		"not_a_package_manager"]
}}
~~~

`blockchain.puck.uno` is the **public library-download service** operated by Puck.uno. It does two things:

- **A common place to download libraries**, without relying on each library's original host to be available. If `borg.com` is down or has moved or has rate-limited a fetcher, the same bytes are still available from blockchain.puck.uno.
- **Signature verification against the [blockchain](blockchain/) before serving.** Every artifact served by blockchain.puck.uno has its hash and signer cross-checked against the chain. If the hash doesn't match a signed entry — or if the signature doesn't verify against the signer's authority block — the artifact is not served.

---

<a id="opt-in"></a>
## Opt-in

**blockchain.puck.uno is opt-in.** It plays two roles in a Caspian process, and the user-facing surfaces for opting into them are **orthogonal**:

- **As a fetcher** — blockchain.puck.uno is one of many [fetchers](../#sources-documented-here) that can sit in `%puck`'s search path. Add it (or remove it) via `%puck.sources` like any other fetcher. Whether it's in the path determines whether the mirror is consulted on cache misses.
- **As a blockchain trust anchor** — the Puck blockchain that blockchain.puck.uno publishes against is what `%puck.blockchain` typically points at. Setting `%puck.blockchain` configures *signature verification*, separately from which fetchers are in the path.

These two axes used to be conflated in an earlier draft (a `%puck.source = :puck` shortcut that claimed to do both). They're now split because they answer different questions:

- *"Where do my libraries come from?"* — `%puck.sources` (the fetcher array).
- *"Whose signatures do I trust for verifying them?"* — `%puck.blockchain` (the verification policy).

<a id="puck-blockchain"></a>
### `%puck.blockchain` — the verification policy

`%puck.blockchain` configures **which blockchain service is used to verify the signature of every library** the process loads. It does *not* configure where libraries are fetched from. Libraries can come from anywhere in the search path; they have to match the signature recorded on the configured blockchain. Cached entries that fail verification are bypassed (and, if the cache is writable, deleted with a warning, then re-fetched).

Values:

```
%puck.blockchain = true                          # use the default Puck blockchain (blockchain.puck.uno's)
%puck.blockchain = 'https://foo.bar/whatever'    # use a specific blockchain URL
%puck.blockchain = null                          # not set (the default); no chain verification
%puck.blockchain = false                         # same as null — no chain verification
```

`null` and `false` are equivalent — both mean "no blockchain verification policy is active." `true` is shorthand for "use the default Puck chain." A string is a specific URL. (Polymorphic value, matching Caspian's broader "flat at top, polymorphic values" config pattern.)

**Signature capture happens at cache-write time.** When a library is first downloaded into the cache, the engine queries the configured blockchain for its signature and stores it in [`meta.json`](../caching/index.md#meta-json). Subsequent cache reads verify that stored signature locally against the chain's baked-in public key — no network needed for cache hits.

**Verification scope is universal.** Once `%puck.blockchain` is set, *every* library load gets checked, including cached entries from prior runs. A cached entry without a stored signature (because it was cached before blockchain verification was enabled) is treated like any other unverifiable cache entry: warn, delete if writable, re-fetch.

### `%puck.sources` — the fetcher array

`%puck.sources` is the ordered array of [fetchers](https://puck.uno/documentation/requirements/caspian/downloads/#sources-documented-here) the engine has made available to user code. **By default it's locked** — user code reads it but can't assign, append, clear, narrow, reorder, or otherwise modify it. The engine's array is the array.

In **CLI mode** the array is unlocked, and the user can do anything they want to it — replace it, narrow it, add fetchers the engine didn't supply. Anything goes.

```
%puck.sources    # always readable: shows what fetchers are available

# in CLI mode only:
%puck.sources = ['blockchain.puck.uno', <local-cache>, <direct-fetcher>]    # replace
```

### Engine-supplied fetchers

The engine passes user code a list of fetchers via `%puck.sources`. **By default it doesn't pass any** — a Caspian process with no engine-supplied fetchers can barely do more than bootstrap (run its own code, but not `%puck`-load anything external).

In the common case, one of the engine-supplied fetchers is an **HTTP client** that fetches a resource at a URL and runs signature verification if `%puck.blockchain` is set. Other fetchers (mirrors, local caches, specialized per-host fetchers like the [GitHub fetcher](https://puck.uno/documentation/requirements/caspian/downloads/github/)) may also be in the list.

The engine controls what's in the array; user code uses it as-is (except in CLI mode, see above).

**Open: cache-location config.** A fetcher that downloads bytes still needs to know where (or whether) to cache the result. The mechanism for telling a fetcher its cache location isn't pinned down yet — could be a property the engine sets on the fetcher when supplying it, could be a per-fetcher kwarg the user code passes when invoking, could be a process-level setting fetchers consult. To be settled when V1.0 implementation lands.

### Why opt-in matters in practice

The developer first-try path is one line of user code — `%puck.blockchain = true` to opt into chain-verified loading, optionally combined with `%puck.sources = [...]` to compose the fetcher path. The engine-config layer is what hardened deployments use to lock the policy in — operators pin a stricter envelope (e.g. air-gapped boxes forbid network sources entirely), and no amount of user code can punch out of it.

This also keeps blockchain.puck.uno from being a single point of failure: anyone who finds its availability or policy unworkable can route around it via `%puck.sources` (when the engine allows), and any program that requires offline operation can ship its libraries baked into a local cache without ever talking to it.

---

<a id="why-both"></a>
## Why both things

The two services bundle naturally because they share infrastructure — to verify a signature against the chain, the service has to fetch the chain entry that signed the artifact; to serve the artifact, the service has to have the bytes. Doing both lets the verification happen at fetch time without requiring every consumer to maintain its own chain reader.

**A consumer that wants integrity without using the mirror** still benefits from the chain directly: the chain is public, the signing scheme is documented, any consumer can verify a directly-fetched artifact's hash against the chain on its own. blockchain.puck.uno is the convenience layer that does that verification for callers who'd rather not.

**A consumer that wants the mirror without integrity** is also free to do that — though there's no actual cost saving in skipping the verification, since blockchain.puck.uno does it regardless. The integrity check is non-optional from the service's perspective; an artifact whose hash doesn't match the chain is simply not served.

---

<a id="relationship-to-blockchain"></a>
## Relationship to the blockchain

blockchain.puck.uno **uses** the [Puck blockchain](blockchain/) — it doesn't replace it, and it doesn't add new trust on top of it. The chain is the source of truth for who signed what; blockchain.puck.uno just enforces that source-of-truth at serving time.

| Concern | Where it lives |
|---|---|
| Authoritative signature records | [Blockchain](blockchain/) (`blockchain.puck.uno`) |
| Artifact bytes (mirror) | blockchain.puck.uno (this service) |
| Hash-vs-chain check at fetch time | blockchain.puck.uno (this service) |

A consumer that bypasses blockchain.puck.uno and fetches an artifact directly can still walk the chain on its own to verify provenance — the chain is public and the verification scheme is documented in the [blockchain spec](blockchain/index.md#signing-scheme).

---

<a id="not-a-package-manager"></a>
## What blockchain.puck.uno is not

- **Not a package manager.** No manifests, no lockfiles, no dependency-resolution algorithm, no `install` / `uninstall` / `update` commands. Library selection lives in [versioning](../../versioning/) (the era/per-UNS/per-call surfaces); blockchain.puck.uno just serves bytes once a version is chosen.
- **Not a search index.** It serves what's been registered; it doesn't browse, recommend, or rank.
- **Not a registry-of-record.** The chain is the registry. blockchain.puck.uno is downstream of the chain, not the other way around.
- **Not mandatory.** [See above](#opt-in).

---

<a id="see-also"></a>
## See also

- [Blockchain implementation](https://puck.uno/documentation/requirements/caspian/downloads/blockchain/blockchain-implementation/) — the chain itself; canonical record of who signed what, plus the reference engine that serves it.
- [Caspian versioning](https://puck.uno/documentation/requirements/caspian/versioning/) — how a program selects which version of a library to look up. blockchain.puck.uno enters the picture only after the version is selected.
- [Downloads (parent)](https://puck.uno/documentation/requirements/caspian/downloads/) — the broader fetch/cache layer beneath `%puck`.
