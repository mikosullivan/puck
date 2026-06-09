# Location-Based Reminder App (idea)

~~~vibecode
{"vibecode": {
	"doc": "location-reminder-app",
	"role": "consumer app concept that exercises puck.uno/geo with geofencing and brand-name business matching for location-tied errands; sketched to surface what geo features it would require",
	"key_concepts": ["location_reminders", "geofencing", "brand_name_business_match",
		"puck_uno_geo_exercise"],
	"status": "brainstorm"
}}
~~~

**Status:** future idea, noted in passing. A small consumer app
concept that would exercise `puck.uno/geo` in ways the driver app
doesn't.

---

<a id="the-idea"></a>
## The Idea

A personal location-monitoring app: the user maintains a list of
"errands tied to places" (e.g., "buy milk at Kroger," "drop off
returns at FedEx," "pick up prescription at CVS"), and the app
reminds them when they're near a relevant location.

Day-to-day: the user is driving past a Kroger. The app pops a
gentle reminder: "You wanted to buy milk here." User pulls in, gets
the milk, marks the errand done.

---

<a id="what-it-would-use-from-puckunogeo"></a>
## What it would use from `puck.uno/geo`

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
## Why it's a useful validation

- Different access pattern than the driver app — long-running
  background-ish location monitoring with sparse "did anything
  interesting happen?" queries, rather than continuous routing.
- Tests the named-business-match filter, which the driver app
  doesn't really need.
- Cross-class users (drivers, non-drivers) makes the geo service's
  appeal broader than just rideshare.

---

<a id="out-of-scope-for-now"></a>
## Out of scope for now

This is a future idea, not a current commitment. Filed so it isn't
lost. Real spec when the time comes.
