# Location-Based Reminder App (idea)

**Status:** future idea, noted in passing. A small consumer app
concept that would exercise `kiera.uno/geo` in ways the driver app
doesn't.

---

<a id="the-idea"></a>
## 1 The Idea

A personal location-monitoring app: the user maintains a list of
"errands tied to places" (e.g., "buy milk at Kroger," "drop off
returns at FedEx," "pick up prescription at CVS"), and the app
reminds them when they're near a relevant location.

Day-to-day: the user is driving past a Kroger. The app pops a
gentle reminder: "You wanted to buy milk here." User pulls in, gets
the milk, marks the errand done.

---

<a id="what-it-would-use-from-kieraunogeo"></a>
## 2 What it would use from `kiera.uno/geo`

- **Continuous location monitoring** in the app (using the browser's
  Geolocation API).
- **`$geo.businesses`** with filtering — find named businesses near
  the current coords matching specific brands or types ("any Kroger
  within 500 meters?").
- **Geofencing / proximity** — fire a reminder when the user enters
  a radius around a matching place. The geo service may need a
  helper for this (e.g., `$geo.near?($place, within: 500)`) or it
  could be computed client-side from raw `$geo.businesses` results
  + the user's current position.

The named-business-match filter is worth specifically calling out —
the current `$geo.businesses` spec returns nearby businesses by
category. A reminder app needs to match by **brand name** ("Kroger,"
"CVS") which is more specific. Probably backed by OSM's `brand=`
tag or `name=` matching. Worth adding when this app is fleshed out.

---

<a id="why-its-a-useful-validation"></a>
## 3 Why it's a useful validation

- Different access pattern than the driver app — long-running
  background-ish location monitoring with sparse "did anything
  interesting happen?" queries, rather than continuous routing.
- Tests the named-business-match filter, which the driver app
  doesn't really need.
- Cross-class users (drivers, non-drivers) makes the geo service's
  appeal broader than just rideshare.

---

<a id="out-of-scope-for-now"></a>
## 4 Out of scope for now

This is a future idea, not a current commitment. Filed so it isn't
lost. Real spec when the time comes.
