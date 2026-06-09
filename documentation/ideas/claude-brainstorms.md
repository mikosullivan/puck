# Ten Brainstorms (Claude)

~~~vibecode
{"vibecode": {
	"doc": "claude-brainstorms",
	"role": "ten short, undiscussed-with-the-project new-direction seeds from Claude: time-travel debugger, Xeme viewer, and other 30-second-read ideas not yet specified",
	"key_concepts": ["seed_ideas_not_specs", "time_travel_debugger", "xeme_tree_renderer",
		"speculative_directions"],
	"status": "brainstorm"
}}
~~~

Ten new-to-the-project ideas I came up with while you were at
7-Eleven. None of these have been explicitly discussed; some
overlap conceptually with existing work but propose new
directions.

These are seeds, not specs. Most are worth at most a 30-second
read each.

---

<a id="1-time-travel-debugger-for-caspian"></a>
## 1. Time-travel debugger for Caspian

Mikobase already supports time-travel reads (querying state as
of any past timestamp). A debugger could exploit this:
**step backwards through state changes**, not just forwards.
Pair with Caspian's deterministic GC (collection happens at known
moments) and the auto-recorded Jasmine call frames, and you have
the ingredients for a real "rewind execution to before the bug"
experience.

Would require recording function-call entries in something
mikobase-shaped during a debug run. Heavy but feasible.

---

<a id="2-visual-xeme-tree-renderer"></a>
## 2. Visual Xeme tree renderer

The icons we just spent time organizing are a contract waiting
for a client. A browser-based (or desktop) viewer that:

- Reads Xeme JSON (file, URL, stdin).
- Renders the tree using the canonical icon set.
- Supports filtering (show only failures), trimming, expanding
  branches.
- Live-updates from streaming Xeme output during a Bryton run.

Becomes the canonical "see your test results" tool. Implements
the icon-fallback rule once, in one place.

---

<a id="3-test-analytics-service"></a>
## 3. Test analytics service

A hosted service that consumes Xeme trees over time and surfaces:

- **Flaky-test detection** — same test, different verdicts across
  runs.
- **Reliability trends** — pass rate over time per test, per
  directory, per project.
- **Regression flags** — tests that started failing after a given
  commit/deployment.
- **Owner attribution** — Xeme metadata (`meta.uuid`, file
  ownership) → who should look at it.

Natural paid-tier upgrade on top of the planned logging/Jasmine
service.

---

<a id="4-jasmine-notifications-service"></a>
## 4. Jasmine → notifications service

A hosted service that consumes Jasmine entries and routes
attention-worthy events to email / SMS / Slack / Pushover / etc.

- Rules engine: severity > X, class matches pattern, occurs > N
  times in 5 minutes → send.
- Deduplication: don't alert on the same recurring error 100
  times.
- Per-class subscriptions: ops cares about one set of classes;
  product cares about another.

Builds on top of the hosted logging service rather than
competing with it.

---

<a id="5-trycaspian-browser-playground"></a>
## 5. TryCaspian — browser playground

A web page where someone can type Caspian and see it run. Mimics
TryRuby, Replit, the various "play with this language" pages.

- Sandboxed Caspian runtime in WebAssembly or compiled-to-JS.
- Persistent saved snippets for sharing.
- Pre-loaded mikobase examples, blockchain examples,
  Sammy/Bryton skeletons.
- A real first-contact surface: someone reads a Puck article,
  clicks a "try it" link, and 30 seconds later is running Caspian
  in their browser.

Aligns with the first-contact strategy memory.

---

<a id="6-puck-cli-tool"></a>
## 6. Puck CLI tool

A unified command-line tool — `puck` — for everyday Puck
operations. Like `kubectl` for Kubernetes or `gh` for GitHub.

```
puck object get foo.com/widget/42
puck mikobase create scratch
puck mikobase sync source=... target=...
puck class show puck.uno/jasmine
puck blockchain verify
puck test run            # wraps bryton
```

Single entry point for what's currently a constellation of
specific scripts. Discoverable via `puck --help`.

---

<a id="7-universal-logger-sidecar"></a>
## 7. Universal logger sidecar

A small daemon — `puck-log` — that reads Jasmine entries on
stdin (or a Unix socket) and routes them to whatever's configured
(local files, the hosted logging service, syslog, Slack, etc.).

Apps just write Jasmine to their local sidecar — they don't need
to know where logs ultimately go. The sidecar's routing config is
the one knob the operator turns.

Inspired by Fluentd / Vector but Jasmine-native. Small enough to
ship as part of the core toolset.

---

<a id="8-federated-mikobases"></a>
## 8. Federated mikobases

Multiple mikobases can be queried as a single virtual store. The
federation layer:

- Takes a Q0 query.
- Routes sub-queries to each underlying mikobase based on schema.
- Merges results respecting cross-mikobase references.

Use case: an "all my data" view spanning a local mikobase, a
remote shared mikobase, and a third-party mikobase the user has
access to. None merge physically; the view is a join.

Hard to do well (cross-mikobase joins are nontrivial) but
philosophically aligned with Puck's "objects everywhere"
posture.

---

<a id="9-time-bounded-objects"></a>
## 9. Time-bounded objects

A class capability: objects with an explicit lifetime. The
mikobase auto-collects them after their TTL expires.

```
$token = %['puck.uno/auth/token'].new(
    expires_at: %now + 3600,
    user: $user
)
$mikobase.save($token)
# 1 hour later: $token is gone, automatically
```

Common need (auth tokens, session caches, throttling windows,
temporary shares). Mikobase already has the time-travel
infrastructure to implement this cleanly — TTL is "this object
is collectible after timestamp X."

---

<a id="10-lazy-mikobase-records"></a>
## 10. Lazy mikobase records

A record whose value is computed on demand by a function, not
stored. The mikobase keeps the recipe (the function + its
dependencies) and re-evaluates when the record is read.

```
$mikobase.save({
    'class': 'lazy_record',
    'key': 'total_users',
    'compute': function() %query.count('users') end
})
# Reading 'total_users' runs the compute function each time
```

Useful for derived data that doesn't fit a static record (counts,
aggregates, computed views) without inventing a separate
materialized-view system. The lazy record IS the view.

Caching strategies, dependency tracking, and invalidation are the
hard parts.

---

<a id="status"></a>
## Status

All ten are speculative. Some overlap with already-flagged
future work; others are new threads. None are commitments.
Filed for the record while you got snacks.
