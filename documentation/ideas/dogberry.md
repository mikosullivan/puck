# Dogberry

```
vibecode: {
    "status": "active_brainstorm",
    "started": "2026-05-17",
    "canonical_location": "ideas/ until firm enough to promote to documentation/kscript/http-middleware/",
    "what_is_known": "dogberry_is_http_middleware_peer_of_sinatra_and_robinson_but_a_different_kind_of_middleware_entirely_from_robinson",
    "what_is_not": ["not_robinson", "not_role_based_access_control"],
    "preexisting_file": "documentation/kscript/http-middleware/dogberry.md_is_stale_per_project_memory_pending_review_or_replacement_by_this_doc",
    "co_authoring": "claude_capturing_miko_brainstorm_in_realtime"
}
```

Brainstorm in progress. Sections will be added as the design takes
shape; for now this file is a workspace.

---

## Concept

```
vibecode: {
    "section": "concept",
    "category": "transforming_proxy",
    "shape": "public_facing_server_that_fetches_resources_from_other_web_servers_and_returns_them_to_the_client",
    "naming_convention_for_this_doc": {"shasta": "the_dogberry_instance", "lune": "the_remote_server"},
    "minimum_role": "router_that_forwards_requests_to_lune_and_returns_lune_responses_to_client",
    "value_add": "transformations_applied_to_the_fetched_resource_before_returning_to_client",
    "parameter_passing": "json_object_in_query_string_e_g_petunia_png_question_mark_rotate_90_brightness_122"
}
```

Dogberry ("shasta" in this doc) is a public-facing server that reads
from other web servers ("lune"). On request, shasta fetches a resource
from lune, optionally transforms it, and returns the result to the
client.

At its simplest, shasta is barely more than a router. What makes it
interesting is the **transformation layer**: parameters in the request
tell shasta what to do to the resource before returning it.

### Parameter shape

Parameters are passed as a JSON object in the query string:

```
https://shasta.example/petunia.png?{"rotate": 90, "brightness": 122}
```

shasta fetches `petunia.png` from lune, applies `rotate: 90` and
`brightness: 122` to the image, and returns the transformed image to
the client.

(Image transformation is one example. More categories of transformation
TBD as the brainstorm develops.)

### Generalization: fetch and execute KScript

The transformation idea extends beyond images. Shasta can also fetch
**KScript source** from lune, execute it, and return the result to the
client. The pitch to developers:

> *Host your own KScript on your own server. Point Dogberry at it.
> Dogberry runs it and serves the results.*

In other words, lune supplies the code (the developer's own infrastructure
keeps custody of the source), and shasta supplies the compute (the
KScript runtime that actually executes it). Client traffic hits shasta,
which fetches from lune on demand, runs the code, and responds.

This is the canonical use case for the engine's "run untrusted code with
a restricted surface" capability that the role model has been building
toward (see [roles.md](../kscript/roles.md) and the V0.0X CLI permission
model in [development/development.md](../development/development.md)).
Each fetched script runs with whatever capability set the shasta operator
grants it; the operator gets to decide what shasta exposes to lune's
code.

---


