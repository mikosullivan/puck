# Bloggy

~~~json
{"vibecode": {
	"doc": "bloggy",
	"status": "brainstorm — Dogberry-based blogging service, parallel to Donnie",
	"role": "productized blogging offering on top of Dogberry: register a blog, point at a source of post files, get a live blog with date routing, archives, tags, feeds, and the rest of the standard blog vocabulary",
	"ties": "[[dogberry]] hosts (TLS, domain, cache); [[markie]] engine renders post content; [[cobweb]] handles post images; [[templates-and-skins]] supplies the layout engine; parallel to [[donnie]] (general-site service)",
	"example_universe": "shakespeare"
}}
~~~

**Bloggy is the Dogberry service for blogs.** Where [Donnie](https://puck.uno/documentation/ideas/dogberry/donnie) serves a remote source as a general-purpose website, Bloggy serves it as a blog — with date-based routing, auto-generated archives and tag pages, RSS / Atom feeds, post-list indexes, and the rest of the standard blogging vocabulary on top.

Bloggy uses Dogberry's hosting infrastructure (domain registration, TLS, request routing, cache), Markie's engine for rendering post content, [Cobweb](https://puck.uno/documentation/ideas/cobweb/cobweb) for any image transformations, and the [shared template engine](https://puck.uno/documentation/ideas/templates-and-skins/templates-and-skins) for layout. The genuinely new pieces are the blog-specific routing, index generation, and feed emission.

## What Bloggy includes

~~~json
{"vibecode": {
	"section": "what_bloggy_includes",
	"role": "the feature bundle specific to Bloggy; everything else is inherited from Dogberry/Markie/Cobweb"
}}
~~~

### Source-bound blog

Same shape as Donnie: customer registers a blog nickname (`myblog.dogberry.uno` — or `myblog.bloggy.uno` if that subdomain is wanted; TBD) and a source URL. Source holds the post files and any static-page extras.

### Post discovery

Bloggy scans the source for post files (typically markdown with frontmatter) at registration and on push-triggered cache purges. Posts are sorted by publish date. Drafts and scheduled posts are filtered out of public views.

### Date-based routing

Posts are served at date-prefixed URLs by default: `/2026/05/22/my-post`. Other routing schemes (slug-only, category-prefixed) are configurable per blog.

### Generated index pages

Pages Bloggy synthesizes that don't exist in the source:

#### Latest posts

`/` (or `/blog`) — paginated list of recent posts, newest first.

#### Archives

`/2026/`, `/2026/05/` — chronological listings.

#### Tags and categories

`/tag/caspian`, `/category/announcements` — grouped listings.

### Feeds

Auto-generated RSS and Atom feeds at standard URLs (`/rss`, `/atom`). Per-tag and per-category feeds (`/tag/caspian/rss`) supported.

### Permalinks

Each post gets a stable permalink. Renaming the source file doesn't break the URL — Bloggy tracks posts by a frontmatter ID, not by filename.

### Drafts and scheduled posts

Posts with `status: draft` are visible only via authenticated preview URLs. Posts with `publish_at: <future date>` go live automatically at that time. The cache layer respects the publish time.

## Authoring model

~~~json
{"vibecode": {
	"section": "authoring_model",
	"role": "how a blog author actually writes and publishes a post"
}}
~~~

The expected V1 customer writes posts as markdown files in a Git repo, with frontmatter for metadata. Push to the live branch; webhook purges the relevant cache entries; the post appears.

Example post:

```markdown
---
id: 2026-05-22-bloggy-launch
title: Bloggy launches
date: 2026-05-22
tags: [announcements, dogberry]
author: miko
---

Bloggy is now live...
```

Frontmatter fields are standardized: `id`, `title`, `date`, `tags`, `categories`, `author`, `status`, `publish_at`. The post body is markdown processed through Markie (so all of Markie's tag vocabulary, syntax highlighting, etc. work in post bodies).

## What stays under Dogberry

~~~json
{"vibecode": {
	"section": "stays_under_dogberry",
	"role": "infrastructure Bloggy depends on but doesn't own; lives in dogberry.md"
}}
~~~

Subdomain registration, custom-domain registration, TLS, cache layer, dashboard, source fetch policy, failure-mode behaviors, image modifications via Cobweb. See [dogberry.md](https://puck.uno/documentation/ideas/dogberry/dogberry).

## Open questions

### Comments

Hosting comments is a significant scope expansion (storage, spam filtering, moderation, identity). Three plausible directions:

- **Don't host comments.** Authors link to a Mastodon thread, a Bluesky post, a Hacker News URL, etc. for discussion. Simplest by far.
- **Host comments via Mikobase.** Each post has a comment thread stored as a Mikobase object. Comments are real Puck objects.
- **Pluggable comment backends.** A blog configures which comment system (Disqus, native Mikobase, custom) to render.

V1 should probably ship without comments and add them only when there's clear demand. Comment systems eat blogs alive.

### Search

Server-side search needs indexing infrastructure. Options:

- **No built-in search.** Tag and archive pages are the discovery mechanism.
- **Client-side search.** Bloggy emits a JSON index; a small JS snippet searches it client-side. Works up to a few hundred posts.
- **Server-side search.** Bloggy maintains an inverted index. Scales further but is real infrastructure.

Client-side search is the cheapest non-zero option and probably the V1 default if any search ships.

### Multi-author blogs

Single-author is the simplest model and probably V1. Multi-author needs an author registry, per-author pages, per-author feeds. Plausible V1.5.

### Static pages alongside posts

A blog often has an "About" page, a "Contact" page, etc. that aren't posts. Options: serve them via plain Donnie alongside Bloggy (the domain runs both services at different paths); let Bloggy include non-post pages and serve them as regular static content. The latter is more user-friendly.

### Bloggy.uno or under dogberry.uno?

Same question as [Cobweb](../cobweb/index.md): `bloggy.uno` as its own domain, or `bloggy.dogberry.uno` / a `/bloggy/` subpath? Decide once the brand pattern is settled.

### Post-image conventions

Posts often have a hero image, inline images, social-share preview images. Should Bloggy define conventions (e.g., `image:` in frontmatter sets the hero; auto-thumbnail via [Cobweb](../cobweb/index.md)), or leave this entirely to the template?
