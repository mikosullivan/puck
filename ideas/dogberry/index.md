# Dogberry

~~~vibecode
{"vibecode": {
	"doc": "dogberry",
	"status": "brainstorm — first concrete proposal for Dogberry's role; supersedes the prior 'undefined' placeholder",
	"role": "domain-aware hosting service: users register a domain, point Dogberry at a remote source of HTML/Markie-DSL, Dogberry handles incoming requests by fetching, processing, and serving the result",
	"ties": "Markie does the DSL→HTML transform; Dogberry handles domain registration, TLS, request routing, and the cache layer that puts a Markie-authored site in front of real traffic",
	"example_universe": "shakespeare"
}}
~~~

**Dogberry is a hosted front door for sites you author elsewhere.** You build a static site of HTML (optionally written in [Markie](https://puck.uno/ideas/markie/)'s DSL) and host the source wherever you like — GitHub Pages, S3, your own server, a static-file mirror. You register a site nickname with Dogberry and your site goes live at `<nickname>.dogberry.uno`. Custom domains (your own `myshop.com`) are a separate, optional registration step layered on top.

Dogberry is the deployment story for Markie. Markie alone is a transformer you call from your own pipeline; Dogberry makes "I authored this in the DSL and want it live at `foo.dogberry.uno`" a single registration step.

A primary use case is **formatting sites hosted on GitHub** — keep your source in a public or private GitHub repo, point Dogberry at it, and your domain serves the Markie-expanded output. Git is the authoring + version-control layer; GitHub is the source-of-truth host; Dogberry is the front door that turns the repo into a live, properly-domained website. The same flow works for GitLab, Codeberg, Bitbucket, and any other Git host that exposes raw file URLs.

## GitHub as a source

~~~vibecode
{"vibecode": {
	"section": "github_source",
	"role": "the specific shape of pointing Dogberry at a GitHub-hosted repo; the most common expected source today"
}}
~~~

### Public repos

Register the domain with a source like `https://raw.githubusercontent.com/<user>/<repo>/<branch>/` (or a GitHub Pages URL). Dogberry fetches from there on each uncached request. No credentials needed.

### Private repos

The customer registers a GitHub personal access token (or app installation) scoped to the repo. Dogberry uses it on the source fetch; the token never reaches the visitor. Stored encrypted.

### Push-triggered cache purge

A GitHub Actions workflow (or repo webhook) POSTs to Dogberry's purge endpoint after a successful push to the live branch. Fresh content appears within seconds of `git push` — no TTL wait. Sample workflow shipped in the docs.

### Branch as environment

Point one domain at `main`, another at `staging`. Authoring shape stays standard Git; Dogberry handles the routing. Lets a customer preview a branch on `staging.myshop.com` before merging.

## How the request flow works

~~~vibecode
{"vibecode": {
	"section": "request_flow",
	"role": "the path a single inbound HTTP request takes through Dogberry"
}}
~~~

A request to `https://myshop.com/products/widgets` arrives at Dogberry. Dogberry looks up `myshop.com` in its domain registry, finds the configured source location (e.g. `https://mikosullivan.github.io/myshop/`), fetches `/products/widgets` (or `.html`, or `/index.html` per resolution rules), pipes the response through Markie, and returns the expanded HTML to the visitor.

Cached responses skip the fetch and the Markie step entirely — the second visitor in a TTL window gets the bytes straight from Dogberry's edge.

## Subdomain registration

~~~vibecode
{"vibecode": {
	"section": "subdomain_registration",
	"role": "the primary path by which a customer brings a site online — register a nickname, get a dogberry.uno subdomain, point at a source"
}}
~~~

The default registration flow:

1. Visit `dogberry.uno`.
2. Log in with shared puck.uno credentials.
3. Add a site with a nickname (e.g. `foo`).
4. Configure the site's source location and any other metadata.
5. The site goes live at `foo.dogberry.uno`.

No DNS configuration, no certificate management, no domain purchase. The nickname is the only thing the customer picks; Dogberry handles everything else.

### Source binding

Step 4 above. The customer registers a source URL — where Dogberry fetches content from on each uncached request. The source can be a static-file host, a Git-hosted directory, an S3 bucket, or any plain HTTP endpoint that returns the document on GET.

### Wildcard TLS

Dogberry holds a wildcard certificate covering `*.dogberry.uno`, so every nickname gets HTTPS for free with no per-site issuance. Custom domains use per-domain Let's Encrypt certs — see [Custom-domain registration](#custom-domain-registration) below.

### Site metadata

Beyond the source URL, a site's settings hold display name, default cache TTL, Markie configuration (which vocabulary version, custom DSL extensions), and access rules. Set once during registration; editable via the dashboard.

## Custom-domain registration

~~~vibecode
{"vibecode": {
	"section": "custom_domain_registration",
	"role": "the advanced/branded path — bring your own domain instead of using the dogberry.uno subdomain"
}}
~~~

A registered site can additionally be served on a customer-owned domain (`myshop.com`). This is a separate step layered on top of [Subdomain registration](#subdomain-registration) above — it doesn't replace the subdomain.

### DNS pointing

The customer points their domain at Dogberry's IPs (A record) or at a Dogberry hostname (CNAME). The customer keeps registrar ownership; Dogberry just answers for the domain.

### Domain ownership verification

Before issuing certs or serving traffic, Dogberry verifies the customer controls the domain via the standard DNS-TXT or HTTP-file challenge. Prevents domain-takeover via someone else's misconfigured DNS.

### Multiple sources per domain

Optional: subpath routing — `myshop.com/blog/*` resolves from one source, `myshop.com/*` from another. Lets a customer compose a site from multiple authoring pipelines. The same applies to subdomain sites.

## TLS

~~~vibecode
{"vibecode": {
	"section": "tls",
	"role": "how Dogberry serves HTTPS — wildcard for subdomain sites, per-domain for custom domains"
}}
~~~

### Wildcard cert for subdomain sites

A single wildcard certificate covers `*.dogberry.uno`, so every nickname-registered site gets HTTPS for free with no per-site issuance.

### Automatic certificate issuance for custom domains

For customer-owned domains, Dogberry issues Let's Encrypt certs per domain. The ACME challenge is satisfied automatically once the customer's DNS points at us. Renewal is automatic; the customer never touches a cert.

### Custom certificate upload

For customers who need EV certs or a specific CA, an optional upload path. Default is automatic Let's Encrypt.

## Caching

~~~vibecode
{"vibecode": {
	"section": "caching",
	"role": "the layer between Dogberry's source fetch and the visitor; the difference between a site that survives the source going down and one that doesn't"
}}
~~~

### Per-path TTL cache

Each fetched + expanded response is cached by path. TTL is set per domain (default ~5 minutes) and honored unless the source's `Cache-Control` says otherwise. Lets a site survive bursts of traffic without hammering the source.

### Stale-while-revalidate

If a cached response is past TTL but the source fetch is in progress, serve the stale copy and refresh asynchronously. Smooths over slow source hosts.

### Stale-on-error

If the source is down or returning errors, keep serving the last good cached response instead of returning a 500 to visitors. Configurable maximum staleness (default: indefinite for read traffic; visible warning in the dashboard).

### Webhook-driven purge

The customer's source host (or CI) can POST to a Dogberry webhook to invalidate one path or the whole domain. Lets fresh content appear instantly without waiting for TTL expiry.

## Source fetch policy

~~~vibecode
{"vibecode": {
	"section": "source_fetch",
	"role": "how Dogberry talks to the customer's source host"
}}
~~~

### Pull on demand

Default. Dogberry fetches paths from the source as visitors request them. Simplest model; no setup beyond the source URL.

### Scheduled pre-fetch

Optional: a sitemap or path list lets Dogberry warm its cache on a schedule, so first-visitor latency is never the source-fetch time.

### Authenticated source

For private sources, the customer registers credentials (basic auth, bearer token, GitHub PAT for private repos). Stored encrypted; only the fetch path uses them.

## Image modifications

~~~vibecode
{"vibecode": {
	"section": "image_modifications",
	"role": "query-string-driven image transformations on a customer's served images; Dogberry intercepts recognized params, delegates the transform to the puck.uno image service, caches by full URL"
}}
~~~

A request to `https://myserver.com/daisy.png?rotate=90` should return a daisy rotated 90 degrees. Dogberry sees the query string on an image URL, fetches the source image from the bound source, hands it to [Cobweb](https://puck.uno/ideas/cobweb/cobweb) (the puck.uno image-modification service) along with the requested transformation, caches the result by full URL (path + query), and serves the transformed bytes.

Cobweb is to images what Markie is to HTML: a per-call transformer offered as a Puck service. Dogberry consumes it the same way Donnie consumes Markie — Cobweb does the work, Dogberry handles the hosting, caching, and serving in the customer's domain context.

### Recognized parameters

The exact vocabulary lives in Cobweb's spec. Common ones a customer will reach for: `rotate`, `width`, `height`, `crop`, `format` (for conversion), `quality`, `grayscale`. Dogberry recognizes whatever Cobweb does — the recognition list isn't duplicated.

### Cache key includes the query string

`daisy.png`, `daisy.png?rotate=90`, and `daisy.png?rotate=180` are three independent cache entries. Same TTL and stale-on-error rules as plain Dogberry caching apply per entry.

### Opt-in or opt-out

Image-mod query interception means the customer can't freely use query strings on image URLs for other purposes (analytics, cache-busting, etc.). Two reasonable defaults: opt-out per domain (image-mod handling on by default; turn off if you use query strings yourself) or opt-in per domain. Decision TBD.

### Only on image extensions

Query-string interpretation applies only to paths with recognized image extensions (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.avif`, `.svg`). HTML pages and other resources pass query strings through untouched, regardless of the opt-in/out setting.

## Identity and accounts

~~~vibecode
{"vibecode": {
	"section": "identity",
	"role": "the account layer that owns domain registrations, source bindings, and billing"
}}
~~~

### Shared puck.uno account

One identity covers puck.uno login, dogberry.uno site nicknames, Markie service usage, custom DSL extensions, custom-domain registrations, and any future puck.uno-hosted service. Designing this as one system from the start prevents a painful merge later.

Domain ownership verification for custom domains lives in [Custom-domain registration](#custom-domain-registration) above.

## Failure modes

~~~vibecode
{"vibecode": {
	"section": "failure_modes",
	"role": "the situations where something is broken and how Dogberry behaves"
}}
~~~

### Source returns 500

Serve the stale cached copy if available; otherwise return a Dogberry-branded error page with status reporting. Customer dashboard surfaces the upstream error.

### Source returns 404

Cache the 404 briefly (short TTL — minutes, not hours) so a typo doesn't hammer the source, but expire fast so fixes appear quickly.

### Source is unreachable

Same as 500 — serve stale, surface the issue. Distinguish "DNS failed" from "TCP timeout" from "TLS handshake failed" in the dashboard.

### Markie expansion fails

The source returned content but Markie rejected it (syntax error, unknown component, sanitizer block). Return a 502 with the Markie error visible to the customer (not the visitor); cache the failure briefly so retries don't loop on a broken commit.

### Customer's DNS misconfigured

Dogberry serves nothing for a domain whose DNS doesn't yet point at us. The dashboard shows the configuration status.

### Cert renewal failed

Dogberry retries; surfaces the failure in the dashboard well before the cert expires. Email alert thresholds configurable.

## API surfaces

~~~vibecode
{"vibecode": {
	"section": "api_surfaces",
	"role": "the ways customers manage their Dogberry-hosted domains"
}}
~~~

### Web dashboard

The interactive surface: register domains, set source bindings, see cache statistics, inspect failure logs. The default front door for non-developer users.

### REST API

Same operations available programmatically. Lets a deployment pipeline register or update bindings as part of CI.

### Puck protocol object

`%('dogberry.uno').register_domain(domain: ..., source: ...)` from Caspian. First-class Puck integration; lets a Caspian program manage its own hosting.

### Webhook receivers

The cache-purge webhook lives here. Future surfaces: deployment-completed hooks, source-rotation triggers.

## Relationship to Markie

~~~vibecode
{"vibecode": {
	"section": "markie_relationship",
	"role": "the split of responsibilities between Dogberry and Markie"
}}
~~~

Markie is the transformer. Dogberry is the host. A site can use Markie without Dogberry (call Markie from your own pipeline, deploy the HTML wherever) and Dogberry without Markie (point Dogberry at plain HTML, skip the expansion step — Dogberry just proxies and caches).

The combined story — author in Markie's DSL, register your domain with Dogberry, done — is the V1 customer experience. Other combinations are valid but second-class.

## Open questions

### Is Dogberry the right name for a hosting service?

Dogberry was previously slotted as "future HTTP middleware (peer of Sammy/Robinson)." Hosting + domain registration is a specific shape; if the name has been informally promised to a middleware role, this proposal might want a different name. Decide before publishing.

### Free tier vs paid-only

Dogberry costs money to run (TLS certs are free, but bandwidth and compute are not). A free tier (one domain, low bandwidth) lowers adoption friction; paid-only keeps operations simple. Influences identity and billing design.

### Domain-level Markie config

Where does a customer configure Markie options (vocabulary version, sanitizer allowlist, custom DSL extensions) for their Dogberry domain? Per-domain registry? Per-source `.markie-config` file fetched alongside the document? Both?

### Multi-tenant cache isolation

One bad actor's site shouldn't be able to fill Dogberry's cache and evict another tenant's hot paths. Standard CDN problem; standard solutions (per-tenant cache quotas) apply but need to be designed in early.

### Geographic distribution

Single-origin Dogberry works for V1 but a global CDN is the eventual shape. When does that shift happen? Influences whether the cache layer is local-disk (V1) or distributed from the start.
