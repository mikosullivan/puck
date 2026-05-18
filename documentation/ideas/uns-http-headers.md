# UNS HTTP Headers (idea)

**Status:** speculative, outside current development plans. Filed
to capture the idea in case it ties into Puck later.

---

<a id="the-idea"></a>
## 1 The Idea

A single HTTP header named **`uns`** carries one JSON hash. Anyone
can add fields to that hash using UNS identifiers to namespace
their keys. The official-headers vs X-headers split disappears —
everything custom lives inside `uns`, namespaced by UNS.

```
uns: {"puck.uno/log/token": "tok_8f3a2b:<api-key>", "example.org/feature": "on"}
```

<a id="why-its-interesting"></a>
## 2 Why it's interesting

- **Namespacing.** UNS identifiers eliminate header-name
  collisions cleanly. RFC 6648 deprecated `X-` prefixes without
  putting anything in their place; UNS fills that gap.
- **One header to parse.** Aligns with Puck's "minimize HTTP
  headers" preference. One parse step yields the whole bag.
- **Structured values.** Arrays, nested objects, booleans, nulls
  — all natural inside JSON. Standard headers tend to invent
  ad-hoc microsyntaxes for structure.
- **Consistency with Puck's JSON-everywhere posture** (Charlie,
  mikobase records, JSON URL params, etc.).

<a id="coexistence-and-long-term-vision"></a>
## 3 Coexistence and long-term vision

`uns` is just another HTTP header — it coexists with everything
else. Standard headers (`Content-Type`, `Authorization`, etc.)
keep working unchanged.

**Long-term ambition:** standard headers could be described in
*both* forms during a transition, then eventually the standard
header surface fades and `uns` becomes the only header. Not a
plan, just the direction the idea points.

<a id="open-questions"></a>
## 4 Open questions

- **Size limits.** Header size caps (typically 8–64 KB per
  server) constrain how much fits in one JSON blob.
- **Tooling visibility.** Standard tools (curl, proxies, caches)
  read named headers. Values inside `uns` are opaque to them —
  affects debugging, `Vary` semantics, and CDN/proxy
  inspection.
- **Encoding.** JSON inside a header value has its own escaping
  rules; needs spec.
- **Adoption path.** Only useful if both ends speak it. Puck
  services can do this with each other freely; broader adoption
  needs a story.

<a id="path-to-standardization"></a>
## 5 Path to standardization

The body that standardizes HTTP is the **IETF** (Internet
Engineering Task Force), specifically the **httpbis** working
group. The rough path:

1. **Write an Internet Draft.** A formal document describing the
   `uns` header — syntax, semantics, encoding, examples, security
   considerations, IANA registration details. Drafts are
   submitted via the IETF's datatracker tool. Format is plain
   text or XML (xml2rfc).
2. **Build reference implementations.** The IETF values "running
   code." At least one working implementation, ideally two
   independent ones, demonstrates the idea is real. A Puck
   service handling `uns` headers natively would be one.
3. **Engage with httpbis.** Post the draft to the working group's
   mailing list. Present at an IETF meeting (three per year,
   in-person + remote). Expect critique — interoperability,
   security, intermediaries, existing-deployment effects, etc.
4. **Iterate.** Address feedback, publish new draft revisions.
   Drafts expire after 6 months unless renewed.
5. **Working group adoption.** If the WG agrees the idea has
   merit, they adopt the draft as a working-group document. This
   is the first major milestone.
6. **Working group last call → IESG review → RFC publication.**
   The remaining process is review-heavy and slow but mostly
   procedural once adoption happens.

**Realistic time and effort.** Years, not months. Even
well-received proposals typically take 2–4 years from initial
draft to RFC. Requires sustained engagement — showing up to
meetings, responding to mailing-list traffic, building rough
consensus.

**Alternative lighter paths:**

- **Informational RFC.** Publish via the Independent Submission
  stream — describes the idea without claiming standards-track
  status. Faster, less consensus required, but carries less
  weight.
- **De facto standard.** Skip IETF entirely. Ship `uns` in Puck
  services, document it openly, build broad adoption first. If
  enough of the ecosystem uses it, standardization becomes
  retroactive paperwork rather than a gate.
- **W3C / WHATWG.** Relevant if browser support becomes part of
  the story.

**For Puck specifically, the de facto path is probably the right
opener.** Make `uns` work within the Puck ecoverse, prove the
value, accumulate adopters. Approach IETF only once there's a
real ecosystem behind it — empty proposals get politely ignored;
proposals with demonstrated traction get serious consideration.

<a id="status"></a>
## 6 Status

Captured for the record. Not on any roadmap.
