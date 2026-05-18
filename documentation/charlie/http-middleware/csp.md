# Content Security Policy

```
vibecode: {
    "section": "overview",
    "scope": "ecoverse_wide",
    "policy": "any_service_giving_out_html_must_also_provide_csp_header_info_for_remote_references",
    "consumer_choice": "use_csp_info_or_not_their_call"
}
```

**Ecoverse-wide policy.** Whenever a Puck service gives out HTML that
references remote objects — JavaScript libraries, stylesheets, fonts,
images, iframes, anything fetched at render time — the service **must
also provide the information needed to construct a
`Content-Security-Policy` HTTP header** that allows those references.

The consumer can choose to use the CSP information or not — they
might already have their own CSP they're managing, they might not be
using CSP at all, they might want a stricter policy than ours. But
the information has to be there for those who want it.

<a id="why"></a>
## 1 Why

CSP is a browser-level defense-in-depth mechanism that lets a site
declare which origins/sources are allowed for various asset types.
When a site embeds third-party content, getting CSP right requires
knowing exactly which origins the third-party fetches from.

If puck.uno emits HTML that pulls in a JavaScript library from
`https://cdn.puck.uno/`, an iframe from `https://maps.puck.uno/`,
and a font from `https://fonts.gstatic.com/`, the embedding site
needs to know about all of those to write a CSP that doesn't
unintentionally break the embed. We hand them that information so
they can. They might assemble:

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' https://cdn.puck.uno;
  frame-src https://maps.puck.uno;
  font-src https://fonts.gstatic.com;
```

Without our CSP information, that policy is hand-assembled by trial
and error, which usually means it's either too permissive (defeating
the point of CSP) or too strict (and the embed silently breaks).

<a id="what-the-service-provides"></a>
## 2 What the service provides

Details to be spec'd later, but the shape: alongside any HTML
snippet, response, or embed code that involves remote references,
the service makes available a **CSP info bundle**. This includes:

- The full set of origins the HTML pulls from
- The asset types those origins serve (script, style, font, image,
  frame, etc.)
- Any inline-content allowances needed (`'unsafe-inline'`,
  `'unsafe-eval'`, nonce-based exceptions, etc. — preferably none)
- Any header that the service itself would set if it were serving
  the page directly

Exact format (HTTP header in a response, JSON sidecar, comment in
the HTML, structured response field) TBD.

<a id="posture"></a>
## 3 Posture

We never include remote references in our HTML without making the
CSP information available alongside. This is a hard rule: if a
service is going to ship HTML, the CSP info is part of the package.

This also pushes our own services toward being CSP-friendly. We
avoid `'unsafe-inline'` and `'unsafe-eval'` in what we emit so the
CSP info we provide can stay clean. If a service can't operate
without those, that's a service-design problem we fix on our side,
not a burden we push onto consumers.

<a id="scope"></a>
## 4 Scope

This policy applies to every Puck service that emits HTML, not
just geolocation. As of the writing of this doc the first concrete
case is `puck.uno/geo`'s map embedding, but the same rule applies
to anything else in the ecoverse that hands out HTML with remote
references.
