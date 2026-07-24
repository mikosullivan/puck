# Logging Service (idea)

~~~vibecode
{"vibecode": {
	"doc": "logging-service",
	"role": "future-product concept for a hosted Jasmine log ingest/storage/read service with a free tier as a Puck adoption lever; deliberately not a search-engine-with-DSL (mikobase is the query layer)",
	"key_concepts": ["jasmine_ingest_service", "free_tier_adoption_lever",
		"mikobase_query_layer", "vendor_neutral_format"],
	"status": "brainstorm"
}}
~~~

**Status:** future product, exploratory. Built on
[Jasmine](../../requirements/packages/jasmine/index.md).

The general service first — basic and useful. A web-logging
customization (Robinson-shaped) layers on later in a separate doc.

---

## What it is

Customers point their Jasmine producers at our ingest endpoint. We
store the entries; the customer reads them back. Free tier, paid
tiers.

## Core flow

1. Customer signs up, gets an API key.
2. Customer configures their Jasmine log with a webhook store
   pointed at our endpoint, using the API key.
3. Entries POST in as they're generated.
4. We store them.
5. Customer reads them (dashboard, API, or direct mikobase
   access).

## What we deliberately are not

- Not a log search engine with its own query DSL. Mikobase is the
  query layer.
- Not vendor-specific. The format is Jasmine; customers can leave
  with their data at any time.
- Not feature-rich for v1. Basic ingest, basic storage, basic
  read access.

## Open structural questions

- **Ingest endpoint shape.** POST URL, auth mechanism, single
  entry vs batch, rate limiting.
- **Storage backend.** Probably per-customer mikobase, but the
  service can start simpler if mikobase isn't ready when this
  ships.
- **Read access.** Dashboard + API + direct mikobase — which of
  those ship in v1.
- **Tier shape.** Free tier limits (retention window, volume),
  paid tier shape, pricing.

Each gets specified when we focus on it.

## Strategic note

Free tier exists primarily to support Puck's first-contact
strategy. Not a P&L item.

## Out of scope for now

Future product, not a current commitment. Real work starts when
Jasmine itself is solid.
