# GitHub fetcher

*A specialized fetcher in `%puck.sources` that recognizes GitHub URLs and handles the GitHub-specific shape (web URL → raw URL translation). Most publishers will host classes on GitHub; this fetcher makes that work without ceremony.*

~~~vibecode
{"vibecode": {
	"doc": "github_fetcher",
	"role": "spec sketch for a specialized fetcher that handles GitHub-hosted classes — recognizes github.com and raw.githubusercontent.com URLs, translates web URLs to raw URLs, fetches the bytes",
	"status": "sketch",
	"key_concepts": ["specialized_fetcher_for_github",
		"web_url_to_raw_url_translation",
		"participates_in_puck_sources_chain"],
	"related": ["requirements/downloads/ (fetcher framework)",
		"requirements/downloads/caching/ (where verified bytes land)",
		"requirements/downloads/blockchain/ (signature source)"]
}}
~~~

## What it does

The GitHub fetcher recognizes two URL shapes:

- **Web URL** (what humans share): `https://github.com/USER/REPO/blob/REF/PATH`
- **Raw URL** (where the bytes live): `https://raw.githubusercontent.com/USER/REPO/REF/PATH`

When the fetcher matches a `%puck[url]` lookup against either form:

1. If the URL is the web form, translate it to the raw form (drop the `/blob/` segment, swap the host).
2. Fetch the bytes from the raw URL via HTTPS.
3. Return the bytes to the engine for verification (per the [cache verification flow](../caching/#signature-verification)).

The signature check is the engine's concern, not the fetcher's. The fetcher just hands over bytes.

## Why a specialized fetcher

A generic HTTPS fetcher could already handle `raw.githubusercontent.com` URLs — the bytes are just served over HTTPS. The reason to specialize:

- **Web URL transparency.** Developers bookmark `github.com/...` URLs and share them in docs, READMEs, examples. A specialized fetcher makes those URLs loadable directly via `%puck`, without forcing publishers to communicate the raw URL form separately.
- **GitHub-specific affordances** later on (not in this initial sketch): authentication for private repos, GitHub API for "latest commit on this branch" resolution, rate-limit-aware retries, LFS handling.

## Open

Sketch-level for now. Things to settle as the design matures:

- Authentication for private repos (API tokens? OAuth? configured via what surface?).
- Whether the fetcher uses the GitHub API at all, or just hits raw.githubusercontent.com directly.
- Rate-limit handling — GitHub throttles unauthenticated requests; what does the fetcher do when it hits a 429?
- Handling of LFS-stored artifacts (the raw URL returns an LFS pointer, not the bytes).
- GitHub Pages URLs (`USER.github.io/REPO/...`) — separate URL space; out of scope for this fetcher, probably needs its own treatment or a more general "static site" fetcher.
- Whether the fetcher recognizes other Git-hosting services (GitLab, Codeberg, Gitea) under their own variants, or whether each gets its own specialized fetcher.

## See also

- [Downloads (parent)](https://puck.uno/documentation/requirements/downloads/) — the fetcher framework this plugs into.
- [Caching](https://puck.uno/documentation/requirements/downloads/caching/) — where bytes land after the fetcher returns them, and where signature verification happens.
- [Blockchain](https://puck.uno/documentation/requirements/downloads/blockchain/) — the signature source the engine uses to verify whatever this fetcher returns.
