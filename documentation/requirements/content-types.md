# HTTP Content-Types
<!--index: 13-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_content_types",
	"role": "spec for the HTTP Content-Type headers that Caspian source files and CaspianJ tree files must be served with. Establishes the two canonical media types (text/x-caspian and text/x-caspianj), the rationale (engines and tooling need an authoritative signal that doesn't depend on extension or content-sniffing), and the list of web-server configuration guides the documentation set should carry.",
	"status": "spec — the two Content-Type strings are canonical; the guide list is a scope decision (V1 required set plus candidates for later).",
	"audience": "server operators publishing Caspian objects over HTTP; documentation authors writing per-server configuration guides; engine implementers who dispatch fetch responses by Content-Type"
}}
~~~

Caspian source files and CaspianJ tree files, when served over HTTP, must be delivered with specific `Content-Type` header values. This lets clients — engines, tools, browsers — recognize the content authoritatively without extension pattern-matching or content-sniffing.

## Content-Type mappings

| File type | Extension | Content-Type |
|---|---|---|
| Caspian source | `.casp` | `text/x-caspian` |
| CaspianJ tree | `.caspj` | `text/x-caspianj` |

Both media types use the `x-` prefix that RFC 6648 designates for unregistered / experimental types. If either is later registered with IANA the prefix will be dropped; until then, the `x-` form is canonical.

## Rationale

Serving Caspian source and CaspianJ trees with distinct Content-Types lets any client tell them apart without inferring from extensions or sniffing bytes:

- **Engines fetch by URL.** `%puck['https://foo.bar/whatever']` may not include a recognizable extension in the URL. The Content-Type header is the authoritative signal for which parser (if any) to apply.
- **Tooling.** Editor plugins, linters, and package managers all pick handling based on Content-Type when the extension is missing, ambiguous, or wrong for the actual payload.
- **Direct browser fetches.** Reviewing a published object in a browser (for debugging, verification, or documentation) gets the right downstream handling from browser extensions and pipeline tools.

## Server configuration guides

Configuring a web server to serve `.casp` and `.caspj` files with the correct Content-Type varies by server. The documentation set should include configuration guides for every major server a Caspian developer or Puck object publisher is likely to reach for.

Each guide should carry the minimum configuration snippet, a note on whether the change requires a server restart, and a verification step (e.g., `curl -I` showing the expected header on a test request).

### Required guides (V1)

- **nginx** — the most common general-purpose web server.
- **Apache httpd** — long-standing, still widely deployed.
- **lighttpd** — lightweight alternative common on smaller deployments.

### Additional guides worth considering

- **Caddy** — modern server with automatic HTTPS; growing adoption.
- **Microsoft IIS** — Windows-hosted enterprise deployments.
- **OpenLiteSpeed** — high-performance alternative on the Linux side.
- **Traefik** — reverse proxy / edge router common in containerized deployments.
- **Cloudflare Workers / Pages** — edge hosting.
- **AWS S3 + CloudFront** — static hosting at scale.
- **GitHub Pages** — free static hosting; Caspian samples and demos are likely to land there.
- **Netlify** — static-site deployment platform.
- **Vercel** — static-site deployment platform.
- **Node.js / Express** — programmatic serving; the guide would show how to set the Content-Type in application code (this covers most application-server stacks by example).

Which of the additional guides ship with V1 vs. later revisions is a scope decision, not a spec decision — the Content-Type strings themselves are stable regardless.

## Testing

- **`.casp` served as `text/x-caspian` parses as Caspian source** — a fetch of a `.casp` URL with the canonical Content-Type is handed to the Caspian source parser.
- **`.caspj` served as `text/x-caspianj` parses as a CaspianJ tree** — a fetch of a `.caspj` URL with the canonical Content-Type is handed to the CaspianJ tree loader.
- **Content-Type wins over URL extension** — a URL ending in `.casp` served with `text/x-caspianj` is treated as a CaspianJ tree; a URL ending in `.caspj` served with `text/x-caspian` is treated as source.
- **Content-Type case is normalized** — a server sending `TEXT/X-CASPIAN` is accepted the same as `text/x-caspian`.
- **Unknown Content-Type falls through to non-Caspian handling** — a response with a Content-Type not on Caspian's own list is routed through the parser registry (see [non-caspian-mime-types](https://puck.uno/documentation/requirements/non-caspian-mime-types)).
- **Missing Content-Type raises** — a fetch that returns no Content-Type header at all raises; the engine does not sniff bytes.
- **Charset parameter on `text/x-caspian` is tolerated** — `text/x-caspian; charset=utf-8` parses identically to `text/x-caspian` alone.
- **Non-UTF-8 charset is transcoded** — a `text/x-caspian; charset=utf-16` response is decoded to UTF-8 before parsing (per [concepts § Strings are UTF-8](https://puck.uno/documentation/requirements/concepts#strings-are-utf-8)).
- **Trailing whitespace in Content-Type header is ignored** — `text/x-caspian ` (trailing space) is accepted.
- **Unrelated media types don't collide** — a `.casp` URL served accidentally as `text/plain` is treated as plain text and reaches the text parser, not the Caspian source parser.
