# Mikobase Service (idea)

~~~json
{"vibecode": {
	"doc": "mikobase-service",
	"role": "future-product concept for a public hosted mikobase service with a generous free tier as a Puck adoption lever; analogous to Heroku Postgres or PlanetScale but for mikobase",
	"key_concepts": ["hosted_mikobase_service", "free_tier_adoption_lever",
		"frictionless_first_contact", "shared_infra_with_logging_service"],
	"status": "brainstorm"
}}
~~~

**Status:** future product, intent stated. A public hosted
mikobase service with a free tier. Filed as exploration alongside
the [logging service](logging-service.md) — they share the same
strategic role and probably the same infrastructure.

---

<a id="the-idea"></a>
## 1 The Idea

Customers get a hosted [[mikobase]] instance they can read from
and write to via the standard mikobase API. We handle hosting,
backups, scaling, dashboards. They handle their data.

Like Heroku Postgres or PlanetScale, but for mikobase. The free
tier is generous enough to be useful; paid tiers cover real
production workloads.

---

<a id="why-a-free-tier"></a>
## 2 Why a Free Tier

Same logic as the [logging service](logging-service.md#strategic-role-an-adoption-lever-for-puck):
**a free tier is an adoption lever for the Puck ecoverse.**

Mikobase by itself is just a database. To get someone to use it,
they need a frictionless way to *try* it. A free hosted instance
removes the "set up a server first" barrier. Someone curious about
Puck can have a working mikobase in five minutes, write some
data, and see what the API feels like — without committing
anything.

That's the Macintosh-shipping-with-MacWrite move applied to a
database: don't make the user host infrastructure before they can
explore the platform.

The free tier doesn't need to be profitable; it's marketing spend
for the rest of the ecoverse.

---

<a id="shape-sketched-not-committed"></a>
## 3 Shape (sketched, not committed)

<a id="free-tier"></a>
### 3.1 Free tier

- One mikobase instance per account.
- Small storage cap (e.g., 100 MB; TBD).
- Read/write API access.
- Browser dashboard for inspecting data.
- Public URL (with auth) so the customer's apps can connect.

<a id="paid-tiers"></a>
### 3.2 Paid tiers

- Larger storage caps.
- More instances per account.
- Better SLA, backups, support.
- Eventually: replication, read replicas, multi-region.

<a id="enterprise"></a>
### 3.3 Enterprise

- Dedicated infra, custom limits, compliance audits, optional
  self-hosted appliance.

---

<a id="synergies"></a>
## 4 Synergies

<a id="with-the-logging-service"></a>
### 4.1 With the logging service

The [logging service](logging-service.md) already runs per-customer
mikobases as its storage backend. **Same infrastructure, two
products.** A customer of the logging service could plausibly get
direct mikobase access to their log data as part of their plan —
or sign up for both products with a single account.

<a id="with-puck-adoption"></a>
### 4.2 With Puck adoption

Every Puck tutorial, demo, and example needs a place to put
data. A free mikobase service is the obvious answer:
"`%puck['logs.puck.uno/mikobase'].new(account: '...')` — done."
No setup, no infra, just a working data store.

<a id="with-other-future-products"></a>
### 4.3 With other future products

Any future Puck service that needs a customer-facing database
backend (CMS-style products, structured-data services, etc.) can
ride on the same infrastructure.

---

<a id="open-questions"></a>
## 5 Open Questions

- **Endpoint shape.** What's the API URL pattern? Per-customer
  subdomain? Path-based?
- **Auth model.** API keys? OAuth? Connection-string-style?
- **Multi-instance per account.** Free tier = one; what's the
  cap for paid?
- **Storage measurement.** Bytes on disk? Object count? Both?
- **Pricing structure.** Per-instance, per-GB, per-operation, or
  some blend.
- **Data portability.** Customer should be able to export their
  full mikobase at any time (consistent with the
  [logging service's](logging-service.md#leaving-data-portability)
  no-lock-in posture).

---

<a id="out-of-scope-for-now"></a>
## 6 Out of Scope for Now

Future product. Not a current commitment. Real planning when
mikobase itself is solid and there's a clear sense of who would
use this. Until then, this doc just captures the intent so the
shape isn't lost.
