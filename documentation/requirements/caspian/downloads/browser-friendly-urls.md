# Browser-friendly URLs

*Classes should live at URLs that render as a web page when a human visits them in a browser — the same URL the developer would naturally bookmark or share. Specialized fetchers translate those URLs to whatever raw-bytes form the host actually serves.*

~~~json
{"vibecode": {
	"doc": "browser_friendly_urls",
	"role": "general design principle: classes live at human-facing browser URLs (what people share and bookmark), and specialized per-host fetchers handle the translation to raw-bytes URLs",
	"key_concepts": ["classes_addressable_by_human_facing_url",
		"per_host_specialized_fetcher_translates_to_raw_url",
		"developer_uses_the_url_they_would_share",
		"one_fetcher_per_host_pattern"],
	"related": ["requirements/caspian/downloads/github/ (first specialized fetcher)",
		"requirements/caspian/downloads/ (fetcher framework)"]
}}
~~~

## The principle

When a developer publishes a Caspian class, the URL they hand to a collaborator should be the **same URL they'd open in a browser to read it**. Not a separate "raw" URL, not an API endpoint, not a magic shortform — the actual web page where the class renders with syntax highlighting and an "Edit" button.

This matters because:

- **Developers already share these URLs.** They appear in READMEs, chat messages, issue comments, documentation, blog posts. A user clicks the link, sees the class, decides "I want this in my program," and types the same URL into `%puck[...]`. No translation step on the human side.
- **Browsers do the right thing.** Pasting the URL into a browser shows the page; pasting it into Caspian loads the class. Same URL, two ergonomic outcomes.
- **No new naming layer.** There's no separate URL form for code-fetching vs human-viewing. The host's own URL conventions are the only thing involved.

## The mechanism

Each host with a "browser view" of a file (the `/blob/` path on GitHub, the equivalent on other hosts) needs a **specialized fetcher** that knows how to translate that host's web URL to its raw-bytes URL. The translation is per-host because the URL shapes differ.

A specialized fetcher:

1. Pattern-matches the host (and possibly the path shape) on incoming `%puck[url]` lookups.
2. Translates the human URL to whichever URL actually serves the bytes for that host (the raw URL, a CDN endpoint, an API call, whatever).
3. Fetches the bytes.
4. Hands them to the engine (verification happens at the engine layer per the [cache spec](caching/#signature-verification)).

The first specialized fetcher is [GitHub](github/). Future fetchers in the same family would cover other major code-hosting services where the same pattern appears — GitLab, Codeberg, Bitbucket, Gitea, etc. Each would be its own small doc and its own translation rule.

## What this is not

- **Not a universal URL parser.** Each fetcher knows its host. There's no central registry of "all the ways every host serves files." Hosts not covered by a specialized fetcher fall through to the generic HTTPS fetcher (which works for any direct raw URL).
- **Not a substitute for the raw URL.** The raw URL still works directly — `raw.githubusercontent.com/USER/REPO/main/foo.casp` is loadable without involving the GitHub fetcher's translation. The specialized fetcher is the convenience layer, not a wrapper around the only path.
- **Not magic.** A fetcher exists only for hosts where the pattern is common enough to be worth specializing. Hosts with idiosyncratic URL schemes (paywalled CDNs, single-page-app frontends, etc.) won't get a specialized fetcher unless someone writes one.

## See also

- [GitHub fetcher](https://puck.uno/documentation/requirements/caspian/downloads/github/) — the first member of this family; translates `github.com/.../blob/.../` URLs to `raw.githubusercontent.com/...`.
- [Downloads (parent)](https://puck.uno/documentation/requirements/caspian/downloads/) — the broader fetcher framework these plug into.
- [Caching § Signature verification](https://puck.uno/documentation/requirements/caspian/downloads/caching/#signature-verification) — what the engine does with bytes once a fetcher returns them.
