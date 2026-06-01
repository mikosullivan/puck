# Universal Namespace

~~~json
{"vibecode": {
	"doc": "uns",
	"role": "spec for the Universal Namespace (UNS), Puck's globally unambiguous naming scheme: a URL minus the protocol used to identify objects, classes, capabilities, and services across the ecoverse",
	"key_concepts": ["universal_namespace", "uns_is_not_url", "global_identity",
		"collision_avoidance", "puck_uno_namespace"]
}}
~~~

A simple naming scheme for identifying things in a globally
unambiguous way.

<a id="too-long-didnt-read"></a>
## Too Long, Didn't Read

A UNS is just a URL without the protocol. It's a way to identify
an object without the noise of protocols:

So this:

```
https://puck.uno/jasmine
https://example.org/widgets/blue
https://miko.dev/projects/mikobase
```

becomes a little less noisy:

```
puck.uno/jasmine
example.org/widgets/blue
miko.dev/projects/mikobase
```

A UNS isn't a URL. They just look alike. If you need a protocol then
that's a URL. Use a URL instead. 

That's probably all you'll ever need to know about UNS.
Read on for more.

---

<a id="introduction"></a>
## Introduction

Software systems hit namespace collisions all the time — two
libraries that both want to define a `User` class, two services
that both want a `status` field, two protocols that both want a
header named `auth`. The standard fix is to **prefix names with
something the namer already owns**, typically a domain name.

Java's package naming does this with reverse domains
(`com.example.foo.Bar`). XML namespaces use full URLs
(`xmlns:dc="http://purl.org/dc/elements/1.1/"`). RDF, JSON-LD,
and many others lean on the same idea: if your name starts with a
domain you control, you can't accidentally collide with anyone
else's name.

UNS does the same thing. A UNS identifier is **a URL without the
protocol**:

```
puck.uno/jasmine
example.org/widgets/blue
miko.dev/projects/mikobase
```

The owner of the domain owns the namespace below it; they can mint
identifiers underneath it freely. Anyone reading the identifier can
tell who owns it by looking at the domain.

Why no protocol prefix: for naming purposes, the protocol is just
noise. That's the main motivation for UNS. The naming idea isn't
new — domain-prefixed identifiers have been around for decades.
UNS just cuts down the noise.

<a id="pancake-simple"></a>
## Pancake simple

The whole concept is barely an invention — it's a thin
formalization of what people already do with domain-prefixed
names. The value is in **everyone agreeing on the same shape** so
identifiers parse and compare consistently across tools and
systems.

<a id="specification"></a>
## Specification

<a id="valid-characters"></a>
### Valid characters

UNS is meant to travel across filesystems, URLs, shell commands,
and any other context where strings get passed around. The basic
rule is **no weird characters** — stick to the basics. The full
list of allowed characters:

- Letters `a-z` and `A-Z`
- Digits `0-9`
- Underscore `_`
- Hyphen `-`
- Dot `.`
- Forward slash `/`
- Question mark `?`

Nothing else. No spaces, no other punctuation, no non-ASCII. Rule
of thumb: if you'd need to percent-encode it in a URL, escape it
in a shell, or worry about it in a filename, it doesn't belong in
a UNS.

The `?` is allowed because developers may want to use it for
namespace organization. UNS doesn't prescribe how — it's a
character developers can use however suits their namespace. When
a UNS is converted to a URL, the portion after `?` is preserved
as the URL's query string.

<a id="bare-domains-are-valid"></a>
### Bare domains are valid

A UNS doesn't need a path. `puck.uno`, `example.org`, and
`miko.dev` are all valid UNSes on their own. The path is optional;
it just adds specificity below the domain.

<a id="disallowed-patterns"></a>
### Disallowed patterns

Even within the allowed character set, certain patterns aren't
valid:

- `..` (parent-directory traversal) — anywhere in the UNS.
- Empty path segments (`//`).
- Trailing or leading dots in a path segment.
- IP addresses as the domain part — `192.168.1.1/foo` is not a
  valid UNS. The domain must be a DNS name.
- Bare domain names without a dot — `localhost/foo` is not a
  valid UNS. The domain must contain at least one dot.

<a id="validation-algorithm"></a>
### Validation algorithm

To validate a candidate UNS:

1. **Prepend a protocol** (e.g., `http://`) to make it a parseable
   URL.
2. **Parse the URL** using standard URL machinery, resolving the
   path as relative to `/`. This collapses any `..`, removes
   redundant slashes, and normalizes other path-traversal funny
   business.
3. **Extract the path and query** from the normalized URL.
4. **Concatenate** path + query into a single string.
5. **Validate** that string against the allowed character set.
6. **Reject** if any disallowed pattern remains.

The URL-parser step is the heart of the algorithm — it lets us
lean on battle-tested URL normalization to defuse traversal
attacks before we look at the result.

**Validation is structural, not resolved.** A valid UNS doesn't
have to point at a domain that actually resolves in DNS. The
validator checks shape and character set; it does not perform a
DNS lookup. Developers can use UNSes built around domains they
own privately, test domains, future domains, or anything else
that looks structurally correct.

<a id="case-sensitivity"></a>
### Case sensitivity

**UNS is case-sensitive.** `puck.uno/Foo` and `puck.uno/foo`
are distinct identifiers. Tools comparing UNSes do a byte-for-byte
match; no case folding.

The "[prefer lowercase](#prefer-lowercase)" norm exists for human
readability and to discourage gratuitous case variants, but it
doesn't change the technical rule — if you write a UNS with
uppercase letters, that's the UNS, and only an exact match
identifies the same thing.

<a id="why-so-strict"></a>
### Why so strict

UNS is used as the structure of the **caching directory** (and
similar filesystem-backed contexts). A UNS that survives
validation can be turned directly into a path on disk without
escaping or sanitization. The strictness is what makes that safe.

<a id="norms"></a>
## Norms

<a id="keep-unses-short"></a>
### Keep UNSes short

UNSes are meant to be **human-readable**. Always prefer the
shorter form when one is available. The norms below are mostly
specific applications of this general principle.

<a id="prefer-lowercase"></a>
### Prefer lowercase

Uppercase letters are allowed but lowercase is preferred.
`puck.uno/jasmine` reads better than `Puck.uno/Jasmine`, and
mixing cases invites the "is `Foo` the same UNS as `foo`?"
confusion.

<a id="skip-www"></a>
### Skip `www.`

Prefer `puck.uno` over `www.puck.uno`. The `www.` prefix is
noise from a different era. UNS is about cutting noise, so leave
it off.

<a id="skip-trailing-slashes"></a>
### Skip trailing slashes

`puck.uno/foo/` and `puck.uno/foo` are technically different
UNSes (UNS is byte-for-byte case-sensitive), but the trailing
slash is usually just noise. Omit it unless you have a specific
reason to keep it.

<a id="use-in-puck"></a>
## Use in Puck

<a id="parser-is-a-core-caspian-requirement"></a>
### Parser is a core Caspian requirement

A UNS parser/validator is a **core requirement** of any Caspian
implementation. Every host needs to be able to take a string and
answer "is this a valid UNS?" and "what's the canonical form?"
without depending on external libraries. The parser is not a
convenience — Puck leans on UNS heavily enough (caching, class
lookup, identifier handling) that lacking one would break the
runtime.

<a id="uns-doubles-as-url"></a>
### UNS doubles as URL

Puck often treats a UNS as **synonymous with a URL**. Many
objects in the ecoverse live at the address their UNS points to —
the UNS `puck.uno/jasmine` is also the address from which the
corresponding object can be fetched.

When a UNS is used as a URL this way, **the protocol is always
HTTPS.** No need to write it out; Puck doesn't speak plain HTTP
for these.

This is a Puck convention layered on top of UNS. UNS itself is
just a naming scheme; the "many UNSes also resolve as live HTTPS
URLs" convention belongs to Puck, not to UNS in general.

**Trailing-slash friction.** The "no trailing slash" norm runs
into a quirk when a UNS becomes a URL. A UNS like `puck.uno/foo`
becomes `https://puck.uno/foo`, but if the resource on the
server is actually a directory, a typical HTTP server (Apache,
nginx) will redirect to `https://puck.uno/foo/` — costing an
extra round trip. Noted here so the friction is acknowledged;
not considered a significant problem at present.

<a id="first-contact-angle"></a>
## First-contact angle

UNS is one of the lowest-friction ways someone might encounter
Puck. It's small, self-contained, and useful on its own — you
can adopt UNS for namespacing without using anything else from
the ecoverse. Someone who likes the idea can start using UNS in
their own systems immediately, and discover the rest of Puck
later if they're interested. Aligns with the broader first-contact
strategy.
