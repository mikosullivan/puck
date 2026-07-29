# Publishing to the Puck blockchain
<!--index: 2-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_puck_discovery_blockchain_publishing",
	"role": "spec for how authors publish objects to the Puck blockchain — the submission API, what the service does on receipt, and the low-friction publishing philosophy that distinguishes this from PyPI/RubyGems/npm-style ecosystem hubs which require a metadata manifest upfront. The author's only input is a URL; the service reads all metadata (license, contact info, etc.) from the file itself or from the hosting platform's API — no author-supplied form fields.",
	"status": "stub — publishing concept settled at a high level (author submits file, service records signed endorsement, service caches bytes for durability, no manifest ceremony required); submission endpoint, authentication surface, per-field requirements, and edge behaviors all still to be worked out.",
	"audience": "authors publishing Puck objects; anyone comparing Puck's publishing model to language-ecosystem package hubs; service implementers realizing the submission side of the API"
}}
~~~

Publishing an object to the Puck blockchain is deliberately **low-friction**. An author submits the file; the service records a signed endorsement of it, caches the bytes for durability, and makes it available through the [Ledger fetcher](./#the-ledger-fetcher) from that point on. There is no upfront manifest to author, no metadata scaffolding to fill in, no separate registration step — the submission itself is what publishes the object.

## The low-friction principle

Language-ecosystem package hubs — PyPI, RubyGems, npm, Cargo, Maven Central — all require an author to build up a manifest of metadata (name, version, author, license, dependencies, keywords, homepage, ...) before a package can be published. The manifest lives alongside the package and often duplicates information that the code itself could carry.

The Puck blockchain does not require any of that. The submission carries only what the endorsement inherently needs — the URL, the license, and the artifact bytes — and everything else is derived on the service side (hash) or supplied later through additional endorsements. Publishing is closer to "here's my file at this URL" than "here's my package with all its metadata."

*(Rationale, comparison table, and specific field requirements to be filled in.)*

## The basic flow

Publishing works in four steps:

1. **The author submits a URL** to `blockchain.puck.uno` — typically through a web form on the site itself. The URL is the **entire input**; no license field, no author info, no description — just the URL pointing at the resource the author wants to publish. All metadata is read by the service from the file itself or from the hosting platform (see [Where metadata lives in the file](#where-metadata-lives-in-the-file) below).
2. **The service downloads** the resource from the submitted URL.
3. **The service records an endorsement** on the blockchain, tying the URL to the artifact's hash (and any other endorsement fields that apply).
4. **The service caches the bytes** in its own store, so the resource stays available through the [Ledger fetcher](./) even if the origin URL later goes down.

That's the whole surface. No manifest, no separate package build, no registration ceremony. The author's file at its own URL is what gets published; the service handles everything downstream.

*(Authentication of the submitter — how the service verifies that the person submitting a URL is the party entitled to publish under it — is still to be worked out. The surface needs to distinguish "endorsement by the URL's controlling party" from "endorsement by an arbitrary third party" without adding manifest-shaped ceremony that would undercut the low-friction principle.)*

## Where metadata comes from

**Metadata is not supplied by the author at submission time.** The author registers a URL, and the service must be able to discover the file's metadata from that URL alone. The submission form has no license field, no author-info field, no description field for the author to fill in; the URL is the entire input.

This keeps publishing genuinely low-friction and gives the metadata a single source of truth wherever the file lives. The service needs some minimum metadata about the file — the license, at least — to record an endorsement, and it obtains that from one of the sources below.

Two sources for the metadata are settled so far. They are **peer options**, not primary + fallback — either one on its own is sufficient, and which one an author leans on depends on where the file is hosted. For files served from a platform with a metadata API (GitHub and similar), authors are typically **encouraged to omit `%meta` from the file** and let the platform supply the metadata, since duplicating it in the file adds redundant information the author has to maintain. For files served from a plain webserver, or for authors who want the metadata to travel with the file regardless of host, an embedded `%meta` is the right choice.

**When both sources are present, `%meta` wins — but having both is considered bad form.** If a file both carries a `%meta` block and is hosted on a platform with a metadata API, the file's `%meta` is authoritative — a `license` value in `%meta` overrides the platform's `spdx_id`, an `author` field in `%meta` overrides the platform's owner info, and so on. The rationale for `%meta` winning: the author's explicit declaration in the file is a stronger intent signal than anything the platform auto-detects or infers.

That said, publishing a file that has both a `%meta` and platform-API metadata is **discouraged as bad form**. Two sources of the same information invite drift, obscure the author's intent about which is authoritative, and put a burden on future readers to check both places. Platform-hosted authors should omit `%meta`; authors who need `%meta` in the file should accept that the platform's metadata will be ignored.

The two sources:

### 1. `%meta` command in the file

Caspian source files declare their metadata with the **`%meta`** command, which takes a JSON hash of fields via a heredoc:

~~~caspian
%meta <<EOF
{
    "license": "MIT",
    "author": {
        "name": "Mike O'Sullivan",
        "email": "miko@example.com"
    }
}
end
~~~

**Rules.**

- **At most one `%meta` per file.** A second `%meta` in the same file raises.
- **When present, `%meta` must include `license`.** A `%meta` block that omits `license` — or carries an unrecognized license value — is treated as invalid. If the file is served from a platform whose metadata API provides a license, the service can still publish the file by falling back to the platform value; otherwise, publication is refused.
- **A license must exist somewhere.** `blockchain.puck.uno` **will not serve any file without a license**, regardless of source. If neither `%meta` nor the platform API provides a valid SPDX license, publication is refused. There is no default license and no implicit fallback.
- **Content is a JSON hash.** Field names follow the [npm `package.json` conventions](#schema) where they apply.

#### Schema

The metadata schema **follows npm's `package.json` conventions** as closely as they apply. Reusing npm's naming means the schema stays familiar to most developers, avoids inventing new field names for well-solved cases, and keeps the door open for tooling reuse. Puck-specific fields will only be introduced when npm has no equivalent.

Commonly-included fields:

| Field | Type | Description |
|---|---|---|
| `license` | string | A single SPDX identifier — `MIT`, `Apache-2.0`, `GPL-3.0-or-later`, `BSD-3-Clause`, and so on. **Mandatory in the `%meta` block whenever the block is present.** When `%meta` is omitted entirely (typical for platform-hosted files), the license comes from the platform API instead — see rules above. SPDX expressions and multi-license combinations are not supported at V1; if a genuine need for them surfaces later, the field can be extended. |
| `author` | string or object | The primary author. Object form: `{"name": "...", "email": "...", "url": "..."}` — all three fields optional beyond `name`. String shorthand: `"Name <email> (url)"`. |
| `contributors` | array | Additional contributors beyond the primary author. Each entry has the same shape as `author` (string or object). |
| `homepage` | string | URL of the project homepage. |
| `description` | string | Short human-readable description. |

License values reference the [SPDX License List](https://spdx.org/licenses/) <!-- outbound-link-allowed -->, the industry-standard catalog of open-source (and non-open-source) licenses that every major package manager, security scanner, and license-detection tool already uses.

*(Full field schema TBD — additional fields will be added as concrete situations arrive. npm-package-shaped fields that don't apply here — `main`, `scripts`, `dependencies`, `engines`, and similar — are not part of the Puck schema.)*

### 2. Hosting-platform API

For files hosted on platforms with a public metadata API — GitHub, GitLab, and similar — the service pulls metadata from the platform's own repo-level fields: license, owner, description, topics. Each supported platform gets its own reader class on `blockchain.puck.uno` that maps the platform's fields onto the endorsement schema.

**This is the preferred source for platform-hosted files** — not a fallback. Authors who host on GitHub / GitLab / Codeberg / etc. are encouraged to omit `%meta` from the file entirely and let the platform-level metadata (which they already maintain in the repo's settings anyway) do the job. Duplicating metadata in both the file and the platform settings introduces two places that can drift.

*(More sources may be added as they surface — project-level manifests separate from the file, out-of-band chain records posted by third parties, and platform-specific well-known files are all candidates. The one thing that will not be added is author-supplied fields at submission time; publishing intentionally has no metadata form.)*

## The submission surface

*(TBD — the exact web-form / API shape, response format, error semantics, and any per-endorsement-type fields that need to be supplied at submission time.)*

## Testing

- **Submission with URL only succeeds** — a submission carrying only a URL (no license field, no author info) triggers the service to fetch the file, hash it, and record an endorsement.
- **Submitted URL is fetched by the service** — the service downloads bytes from the origin URL as part of processing the submission.
- **Endorsement `artifact_hash` matches fetched bytes** — the SHA-256 in the recorded endorsement matches the hash of the bytes the service fetched.
- **Endorsement `url` matches submitted URL** — the `url` field on the endorsement is the URL the author submitted.
- **Service caches fetched bytes** — after submission, Ledger's `/v1/download` for the URL returns the cached bytes even after the origin URL goes down.
- **`%meta` in file provides license** — a `.casp` file with `%meta` containing `license: MIT` publishes with SPDX `MIT` in the recorded endorsement.
- **Second `%meta` in file raises** — a file with two `%meta` blocks raises on parse; publication does not proceed.
- **`%meta` without `license` is invalid** — a file where `%meta` is present but omits `license` is treated as an invalid metadata source.
- **`%meta` with unrecognized license value is invalid** — a value that isn't a known SPDX identifier is rejected.
- **Platform API supplies license when `%meta` is absent** — a GitHub-hosted file with no `%meta` publishes using the repo's `spdx_id` as the license.
- **`%meta` wins when both sources present** — a file with `%meta` on GitHub uses the `%meta` license; the platform's `spdx_id` is ignored.
- **`%meta` `author` wins over platform owner** — an `author` field in `%meta` supersedes the platform's owner info.
- **No license anywhere refuses publication** — a submission with no `%meta` and no platform-supplied license is refused.
- **Author-supplied metadata form fields are not accepted** — the submission surface has no license, author, description form fields to fill in.
- **`%meta` follows npm `package.json` field naming** — `license`, `author`, `contributors`, `homepage`, `description` map to their npm shapes.
- **`author` string shorthand parses** — `"Name <email> (url)"` populates the endorsement's name/email/url fields.
- **`author` object form parses** — `{"name": "...", "email": "...", "url": "..."}` populates the endorsement.
- **`contributors` is an array of author-shaped entries** — each entry parses under the same rules as `author`.
- **npm-specific fields not in Puck's schema are ignored** — `main`, `scripts`, `dependencies`, `engines` in `%meta` do not affect the endorsement.
- **SPDX expressions are not supported at V1** — a `license` value like `"MIT OR Apache-2.0"` is refused at V1.
- **Bad-form warning when both sources present** — publishing a file that has both a `%meta` and platform metadata surfaces a warning about drift risk (does not refuse).
- **Published file is retrievable through Ledger** — after publication, `%import(url)` with the URL through the Ledger fetcher returns the file's bytes.

## Related

- [fetch-discovery/blockchain](./) — the parent page describing the blockchain, the Ledger fetcher, the trust-anchor role, and the endorsement structure that publishing produces.
- [content-types](https://puck.uno/requirements/content-types) — the Content-Type an author's file is served with, both from the origin and from the blockchain's cache.
