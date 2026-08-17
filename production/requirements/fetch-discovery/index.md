# Puck discovery
<!--index: 18-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_puck_discovery",
	"role": "spec for how %fetch resolves a URL to an object. %fetch holds an ordered array of fetcher objects; each fetch walks the array in order; the first fetcher to return an object wins; if none find it, the fetch fails. Fetcher classes covered on this page: Wire (fetch the URL directly over the network — typically the last-resort fallback), Octocat (GitHub-specific URL translator that rewrites human-facing github.com/blob/ URLs to raw.githubusercontent.com URLs and overrides the Content-Type from the URL's file extension), similar planned classes for GitLab / Bitbucket / Codeberg / etc., and Cache (any cache-format directory — the standard Cache ships with Caspian and holds the core library; user Caches are any additional cache-format directories the user adds). The URL is object identity; the array determines where the bytes come from.",
	"status": "draft — core model settled (ordered array, first-hit-wins, %fetch doesn't necessarily fetch from the URL); Wire, Octocat, and Cache described; other host-specific translators planned; fetcher registration surface, array-configuration API, and per-fetcher versioning behavior still to be filled in.",
	"audience": "developers who want to understand where %fetch actually gets an object from; anyone configuring the fetcher array; class authors writing new fetcher types"
}}
~~~

`%fetch` resolves a URL to an object by walking an **ordered array of fetcher objects**. Each fetcher is asked "can you produce the object at this URL?" and either returns the object or passes. The first fetcher to return an object wins; if every fetcher passes, the fetch fails.

**`%fetch` does not usually fetch the object from the URL itself.** The URL is the object's identity, but the bytes can come from many places: a local cache, a CDN mirror, a translated download URL, or in the most straightforward case a direct download from the URL. Wire (see below) is the fetcher that hits the URL directly, and in most workflows it's the last-resort fallback rather than the common path.

## Fetcher classes

### Wire

Fetches the URL directly over the network. Uses the URL as-is: whatever host, whatever path, whatever port — Wire makes the HTTP(S) request and hands the response back. Typically the **last entry in the fetcher array** — the fallback when no local cache, translator, or mirror has satisfied the fetch.

### Octocat

A GitHub-specific URL translator. Octocat recognizes URLs of the form:

~~~
https://github.com/<owner>/<repo>/blob/<ref>/<path>
~~~

— the URLs a developer sees in a browser when viewing a file on GitHub — and rewrites them to the corresponding **raw** URL:

~~~
https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>
~~~

Octocat delegates the actual download to Wire against the rewritten raw URL. It does not itself hit the network.

**Content-Type override.** `raw.githubusercontent.com` always returns `Content-Type: text/plain; charset=utf-8`, regardless of the file's actual type, and GitHub exposes no user-facing configuration to change that. To compensate, Octocat overrides the Content-Type based on the URL's file extension, using the mapping from [content-types](https://puck.uno/requirements/content-types): `.casp` → `text/x-caspian`, `.caspj` → `text/x-caspianj`, and so on. This is a per-fetcher override — a workaround for GitHub raw's known behavior, not a general rule about trusting extensions over headers.

### Other host-specific translators

Similar fetcher classes are planned for other popular git-hosting platforms — **GitLab**, **Bitbucket**, **Codeberg**, and others. Each recognizes its host's human-facing URL pattern and translates to the raw download URL, then delegates to Wire. Where a host returns generic Content-Types the way GitHub does, its translator applies the same extension-based override.

### Cache

Reads from a cache-format directory (see [cache-dir](https://puck.uno/requirements/cache-dir) for the on-disk format). Cache is a single class with **many possible instances** in the fetcher array — each instance pointed at a different directory:

- **Standard Cache** — ships with Caspian, pointed at the built-in cache directory that holds the core library. Every Caspian process has one; developers do not add it.
- **User Caches** — any additional cache-format directory the user adds to the fetcher array. Useful for holding third-party or user-authored objects that the user wants available without hitting the network.

All Cache instances behave identically; the distinction is which directory each one owns. The array can hold any number of them.

## CLI defaults

The Caspian CLI, on startup, initializes `%fetch.fetchers` with a default array that includes a Standard Cache for the shipped core library, per-user and system-wide Caches at XDG-standard locations, and Wire as the last-resort direct fetcher.

### Default cache locations

Cache directories follow the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) <!-- outbound-link-allowed -->, using the same environment variables the CLI already respects for `%fetch.locals` (see [local-loading § Environment variables](https://puck.uno/requirements/local-loading#xdg-environment-variable-overrides)):

- **User Cache** at **`$XDG_CACHE_HOME/caspian/`** — Linux default `~/.cache/caspian/`. `XDG_CACHE_HOME` is XDG's dedicated location for user-scoped cache content (files that can be regenerated by re-fetching).
- **System Caches** at **`<XDG_DATA_DIRS entry>/caspian/cache/`** — one per entry of `$XDG_DATA_DIRS`, Linux default expanding to `/usr/local/share/caspian/cache/` (admin-installed) and `/usr/share/caspian/cache/` (distribution-packaged).

The pattern mirrors library-directory placement exactly, with `cache/` appended for the cache path:

| Purpose | Library dirs (`%fetch.locals`) | Caches (in `%fetch.fetchers`) |
|---|---|---|
| User-scoped | `~/.local/share/caspian/` | `~/.cache/caspian/` |
| Admin-installed | `/usr/local/share/caspian/` | `/usr/local/share/caspian/cache/` |
| Distribution-packaged | `/usr/share/caspian/` | `/usr/share/caspian/cache/` |
| Env-var overrides | `XDG_DATA_HOME`, `XDG_DATA_DIRS` | `XDG_CACHE_HOME`, `XDG_DATA_DIRS` |

Setting the XDG env vars replaces the default location(s) wholesale per the XDG specification, matching the same behavior as `%fetch.locals`.

### Default array shape

A reasonable starting composition — order is a design question for later:

1. Standard Cache (built-in core library)
2. User Cache (`~/.cache/caspian/`)
3. System Caches (`/usr/local/share/caspian/cache/`, then `/usr/share/caspian/cache/`)
4. Maps and host-specific translators (Octocat, others as implemented)
5. Wire

Host-specific translators land ordered before Wire so a URL rewrite happens before the raw-URL fetch. System-wide Caches sit between the User Cache and the network so that admin-installed content is preferred over hitting the wire.

*(How each Cache gets populated — whether Wire writes fetched objects into a cache, on what policy, and how the user controls that — is spec'd separately.)*

## Fetcher array registration

*(TBD — the surface for adding fetchers to the array, ordering them, removing them, and inspecting the current array is not yet spec'd. Following the pattern of `%fetch.locals` (array) and `%fetch.maps` (hash), a plain-array `%fetch.fetchers` is a natural candidate, but the exact shape, the write-restriction model, and how fetcher instances get constructed all remain to be worked out.)*

## Testing

- **Fetcher array walked in order** — with two fetchers each capable of serving the URL, the earlier one supplies the object and the later one is not asked.
- **First-hit-wins** — a fetcher that returns an object short-circuits the walk; no later fetcher runs.
- **Miss on all fetchers raises** — a URL that every fetcher passes on causes `%fetch` to raise.
- **Wire fetches directly against the URL** — a Wire-only array with the URL `https://foo.bar/x.casp` issues an HTTPS request to `https://foo.bar/x.casp` and returns the response bytes.
- **Wire preserves the response Content-Type** — the Content-Type Wire returns matches the server's header.
- **Wire failure passes to the next fetcher** — a Wire network error or 4xx/5xx status causes Wire to pass; a subsequent fetcher gets a chance.
- **Octocat rewrites blob URLs to raw** — `https://github.com/<owner>/<repo>/blob/<ref>/<path>` triggers a rewrite to `https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>`.
- **Octocat delegates the download to Wire against the rewritten URL** — Octocat does not itself hit the network; the rewritten URL is the one Wire sees.
- **Octocat overrides Content-Type by extension** — a rewritten fetch of a `.casp` file returns Content-Type `text/x-caspian`, regardless of what `raw.githubusercontent.com` returned.
- **Octocat maps `.caspj` to `text/x-caspianj`** — extension override applies to CaspianJ trees as well.
- **Octocat ignores non-GitHub URLs** — a `https://gitlab.com/...` URL causes Octocat to pass.
- **Octocat ignores `https://github.com/...` URLs that aren't blob URLs** — a GitHub repo homepage URL causes Octocat to pass.
- **Standard Cache reads the shipped core library** — a fetch of a URL known to be in the built-in cache resolves through Standard Cache without hitting the network.
- **User Cache reads from `$XDG_CACHE_HOME/caspian/`** — with a matching cache-format directory at that path, a fetch resolves there.
- **System Caches read from `$XDG_DATA_DIRS/caspian/cache/`** — matching directories under system XDG locations resolve through their Cache instance.
- **Cache miss falls through to the next fetcher** — a URL not present in a Cache causes it to pass; the walk continues.
- **XDG env-var overrides replace defaults** — `XDG_CACHE_HOME=/opt/x` causes User Cache to point at `/opt/x/caspian/`; the default `~/.cache/caspian/` is not searched.
- **`XDG_DATA_DIRS` env var replaces the system-cache list** — `XDG_DATA_DIRS=/opt/y` reduces the system-cache list to `/opt/y/caspian/cache/`.
- **Default array shape places Wire last** — the CLI-initialized `%fetch.fetchers` has Wire as the final entry.
- **Standard Cache precedes user and system caches** — the shipped core library is preferred over user- or admin-installed caches for the URLs it covers.
- **Multiple Cache instances coexist** — several Cache entries pointing at different directories can coexist in the array; each is queried in order.
- **Host-specific translators sit before Wire** — Octocat and similar translators are ordered ahead of Wire so a rewrite happens before a raw fetch.

## Related

- [`%fetch`](https://puck.uno/requirements/fetch) — the Caspian-side gateway. This page describes the fetcher array that `%fetch` walks to resolve a URL.
- [cache-dir](https://puck.uno/requirements/cache-dir) — the on-disk format Cache fetchers read from.
- [content-types](https://puck.uno/requirements/content-types) — the Content-Type mapping Octocat and other host-specific translators use to override generic types returned by raw file servers.
- [non-caspian-mime-types](https://puck.uno/requirements/non-caspian-mime-types) — how the engine dispatches on Content-Type after a fetcher returns bytes.
- [local-loading](https://puck.uno/requirements/local-loading) — the `local:` scheme and URL-mapping mechanisms that complement the fetcher array for local-file resolution.
