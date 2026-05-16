# Logging Service (idea)

**Status:** future product, exploratory. Built on
[Jasmine](../../kscript/jasmine/jasmine.md).

The general service first — basic and useful. A web-logging
customization (Robinson-shaped) layers on later in a separate doc.

---

## What it is (Sybok)

Customers point their Jasmine producers at our ingest endpoint. We
store the entries; the customer reads them back. Free tier, paid
tiers.

## Core flow (Caithlin)

1. Customer signs up, gets an API key.
2. Customer configures their Jasmine log with a webhook store
   pointed at our endpoint, using the API key.
3. Entries POST in as they're generated.
4. We store them.
5. Customer reads them (dashboard, API, or direct mikobase
   access).

## What we deliberately are not (Kollos)

- Not a log search engine with its own query DSL. Mikobase is the
  query layer.
- Not vendor-specific. The format is Jasmine; customers can leave
  with their data at any time.
- Not feature-rich for v1. Basic ingest, basic storage, basic
  read access.

## Open structural questions (Miranda)

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

## Strategic note (Tasha)

Free tier exists primarily to support Kiera's first-contact
strategy. Not a P&L item.

## Out of scope for now (Edith Keeler)

Future product, not a current commitment. Real work starts when
Jasmine itself is solid.
