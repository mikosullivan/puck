# Cobweb

~~~json
{"vibecode": {
	"doc": "cobweb",
	"status": "brainstorm — code name confirmed 2026-05-22 (Midsummer fairy, parallel to Puck and Peaseblossom)",
	"role": "puck.uno image-modification service — submit an image plus a set of transformations, receive the transformed image bytes",
	"surface": "Puck protocol object AND standalone HTTP API (so any client, including Dogberry, can use it without a Puck dependency)",
	"ties": "Cobweb is to images what Markie is to HTML. Dogberry consumes Cobweb the same way Donnie consumes Markie — Cobweb does the transform, Dogberry handles the hosting context.",
	"example_universe": "shakespeare"
}}
~~~

**Cobweb is an image-modification service offered at `cobweb.uno` (or wherever; name TBD).** Submit an image — bytes uploaded with the request, or a URL Cobweb fetches — plus a description of the transformations you want, and Cobweb returns the modified image bytes. Rotate, resize, crop, convert format, adjust quality, strip metadata, apply filters, watermark.

Cobweb pairs naturally with [Dogberry's image-modifications feature](https://puck.uno/documentation/ideas/dogberry/dogberry#image-modifications): a request like `myshop.com/daisy.png?rotate=90` is Dogberry recognizing the query string, fetching the source, and calling Cobweb to do the rotate. But Cobweb is also standalone — any client can POST an image and get a transformed one back, no Puck or Dogberry needed.

## Operations

~~~json
{"vibecode": {
	"section": "operations",
	"role": "the transformation vocabulary Cobweb understands; query-parameter form shown for each"
}}
~~~

### Rotate

`?rotate=N` — rotate by N degrees clockwise. Common values: 90, 180, 270. Arbitrary values produce transparent-cornered output for formats that support alpha.

### Resize

`?width=N` or `?height=N` or `?width=N&height=N`. Specifying only one preserves aspect ratio. Specifying both squashes unless a `fit` mode is also given (`fit=contain`, `fit=cover`, `fit=stretch`).

### Crop

`?crop=W,H,X,Y` — crop to a `W×H` box anchored at `(X, Y)`. Coordinates are pixels from top-left; convenience aliases (`crop=center`, `crop=top`, etc.) cover common cases.

### Format conversion

`?format=webp` (or `png`, `jpeg`, `avif`, `gif`). The output is encoded in the requested format; the response `Content-Type` reflects the conversion.

### Quality

`?quality=N` — encoder quality, 1–100, for lossy formats (JPEG, WebP, AVIF). Ignored for PNG and GIF.

### Color filters

`?grayscale`, `?sepia`, `?invert`. The starter set of pixel-mapping filters. More can be added without breaking existing URLs.

### Strip metadata

`?strip` — remove EXIF, ICC profiles, and other non-pixel metadata. Useful before serving public images (privacy, file size).

### Composite

`?overlay=url&overlay-position=top-right` — composite another image (watermark, badge) onto the source. Position aliases plus pixel offsets.

### Chained transforms

Multiple operations apply in URL order: `?width=400&rotate=90&format=webp` resizes first, then rotates, then encodes as WebP. The order matters (rotating before resizing produces different output than the reverse).

## API surfaces

~~~json
{"vibecode": {
	"section": "api_surfaces",
	"role": "the ways to call Cobweb"
}}
~~~

### REST POST with image bytes

`POST https://cobweb.uno/transform?<params>` with the image in the request body. Returns the transformed bytes with the appropriate `Content-Type`. The canonical no-dependency API.

### REST GET from URL

`GET https://cobweb.uno/transform?source=https://...&<params>` — Cobweb fetches the source URL, transforms, returns. Used by Dogberry; useful for any client that already has the image at an HTTP-reachable location.

### Puck protocol object

`%['cobweb.uno'].transform(source: ..., width: 400, rotate: 90)` from Caspian. First-class Puck integration; lets Caspian code transform images without HTTP plumbing.

## Caching

~~~json
{"vibecode": {
	"section": "caching",
	"role": "Cobweb's own response cache, separate from any caller-side cache"
}}
~~~

### Content-addressed

The cache key is the hash of (source image bytes + transformation params). Identical input + identical params yields a cache hit even if the request URL differs. Lets Cobweb deduplicate aggressively across callers.

### TTL bounded by source

For GET-from-URL requests, the cache entry's TTL is bounded by the source's `Cache-Control`. For POST requests, the TTL is Cobweb-side configurable.

## Security

~~~json
{"vibecode": {
	"section": "security",
	"role": "the rules that keep Cobweb from being a free image-fetching proxy or a resource-exhaustion target"
}}
~~~

### URL allowlist (GET form)

The GET-from-URL endpoint refuses fetches to private IP ranges (RFC 1918, loopback, link-local) and customer-configurable allowed-domains lists. Prevents Cobweb from being used to probe internal networks.

### Input size limits

Maximum source size (in bytes and in pixel dimensions) prevents resource-exhaustion attacks. Configurable per account.

### Output size limits

Maximum output dimensions prevent `?width=999999` from allocating gigabytes. Hard cap regardless of account.

### Format whitelist

Cobweb only decodes well-known image formats. Random binary payloads are rejected before any decoder runs.

## Animated images

~~~json
{"vibecode": {
	"section": "animated",
	"role": "GIF / WebP / APNG handling; the design decision is whether to preserve animation or rasterize the first frame"
}}
~~~

Animated formats (GIF, animated WebP, APNG) need a design decision: preserve animation through transforms (more expensive), or rasterize the first frame to a still (cheaper, common-case). Likely both, with a `?animated=preserve` flag. Defaults TBD.

## Open questions

### Domain

`cobweb.uno`? A subpath under `puck.uno`? Both?

### Image processing engine

ImageMagick (the obvious default, but heavy), libvips (faster, less coverage), Sharp (Node-only), in-house. Influences which formats and operations are supported with what performance.

### SVG handling

SVG is vector, not raster. Some transforms (rotate, color filters) apply naturally; others (quality, format conversion to raster) require rasterization first. Worth thinking through what's well-defined for SVG inputs.

### Self-hostable

A customer with their own infrastructure might want to run Cobweb locally — for compliance, latency, or cost reasons. Open-source the implementation, or hosted-only?

### Relationship to Markie

Both Cobweb and Markie are "transformer-as-a-service" Puck objects. Worth asking whether they should share an abstract framework (a generic "transform-this-with-these-params" base) or stay independent. Probably independent for now — premature abstraction.
