# Rideshare Driver App (worked example)

~~~vibecode
{"vibecode": {
	"doc": "rideshare-driver-app",
	"role": "worked-example spec for a driver-side PWA built on puck.uno/geo; doubles as the end-to-end validation case for whether geo covers a real rideshare driver use case",
	"key_concepts": ["driver_pwa", "puck_uno_geo_validation", "address_resolution",
		"turn_by_turn_navigation", "fare_zone_logic"],
	"status": "brainstorm"
}}
~~~

**Status:** spec for a real app Miko may build — a driver-side
Progressive Web App for a new rideshare service. Doubles as a worked
example of how `puck.uno/geo` is intended to be used.

This doc covers the driver-side app only. The companion rider-side
app is a separate concern (different UI, mostly the same geo usage).

---

<a id="goals"></a>
## Goals

- Build the **driver app first**, since Miko is the most reliable
  user (he's actually a rideshare driver). Eat our own dog food.
- Use **puck.uno/geo** for everything map-related. Validate that
  the service covers the real driver use case end-to-end.
- Ship as a **Progressive Web App (PWA)** rather than native iOS/
  Android. Lower deployment friction (no app stores), single
  codebase, installable on driver phones, but with the known PWA
  limitations (background behavior, push notifications, etc.) that
  need to be designed around.

---

<a id="what-puckunogeo-provides"></a>
## What puck.uno/geo Provides

Everything map-related routes through `puck.uno/geo`:

- **Address resolution** for pickup and drop-off addresses
  (`$geo.address`).
- **Postal-code / city / state** for fare-zone logic
  (`$geo.postal_code`, `$geo.city`).
- **Distance and ETA** between driver and pickup, and between pickup
  and drop-off (`$geo.distance_to`, `$geo.eta_to`).
- **Turn-by-turn navigation** to pickup, then to drop-off
  (`$geo.route_to`, returning a route object with steps).
- **Nearby businesses** for during-shift micro-needs (bathroom,
  coffee, gas, parking) (`$geo.businesses`, `$geo.restrooms`,
  `$geo.coffee`, etc., with `drive_thru:` and `open_now:` defaults).
- **Map embeds** on most screens (`$map.iframe_html`).

The geo service is the **only third-party-style dependency** for
maps. No Google Maps, no Mapbox, no separate provider keys.

---

<a id="what-puckunogeo-does-not-provide"></a>
## What puck.uno/geo Does NOT Provide

Everything ride-business-specific lives in the rideshare's **own
backend** (which is a separate system from puck.uno/geo):

- Driver authentication and profile management.
- Driver online/offline state tracking.
- Ride matching (assigning a rider's request to a nearby available
  driver).
- Rider information delivery (name, rating, special instructions).
- Ride lifecycle state machine (requested → accepted → en route →
  arrived → in trip → completed).
- Real-time driver location reporting (for ETA-to-rider, surge
  modeling, fraud detection).
- Payment processing and fare calculation.
- Earnings tracking and payouts.
- Surge pricing logic, driver heat maps, demand prediction.
- Rating and review system.

The rideshare backend is its own beast; this doc concerns itself
only with the driver-PWA side and its use of puck.uno/geo.

---

<a id="tech-stack"></a>
## Tech Stack

- **Frontend**: PWA. HTML/CSS/JS in a service-worker-enabled web
  app. Mobile-first, designed for phones in a vehicle dash mount.
- **Framework**: TBD (could be vanilla, could be a small framework
  like Lit or Svelte). PWA capabilities are what matter; the
  framework choice is secondary.
- **Maps and geo**: `puck.uno/geo` services via remote calls (Caspian
  client-side or, in non-Caspian browsers, the JSON-over-HTTP form).
- **Real-time driver↔backend**: WebSocket connection to the
  rideshare backend for ride requests and lifecycle events.
- **Offline storage**: IndexedDB for the current ride state and a
  queue of pending operations (e.g., "ride ended, fare to upload").
- **Push notifications**: Web Push API for incoming-ride alerts when
  the app is backgrounded. (See PWA Limitations below — iOS support
  is the gating issue.)

---

<a id="major-screens"></a>
## Major Screens

<a id="status-main-idle"></a>
### Status / Main (idle)

The driver's home screen when not on a ride.

- **Top half**: a map embed centered on the driver's current
  location, dropped directly into the page DOM via **`$map.html`**.
  Not in an iframe — the map element is a child of the home-screen
  DOM, so the PWA's JS can interact with it directly (query it,
  attach listeners, update state). The PWA gets driver location via
  `navigator.geolocation.watchPosition()` and feeds updates to the
  map element through its JS API (specific shape TBD). The map
  smoothly re-centers on each update.
  - Auto-follow the driver pin by default; "recenter" button if the
    user pans away.
  - North-up orientation (no rotation with heading — simpler and
    more readable).
  - Driver shown as a blue dot or directional chevron (chevron if
    `heading` is provided).
  - Default zoom ~level 15 (neighborhood scale).
  - Fallback when no location yet: "locating…" placeholder or last
    known position from IndexedDB.
  - The driver can see surrounding streets, traffic, nearby pickup
    zones (overlay TBD — needs rideshare backend data).
- **Bottom half**: status panel.
  - Online/Offline toggle (controls whether the driver is taking
    requests).
  - Today's earnings so far (from rideshare backend).
  - Today's ride count.
  - Buttons for quick driver-life utilities:
    - **Restrooms nearby** → `$geo.restrooms` → list with distance
      and walking time.
    - **Coffee / Food nearby** → `$geo.coffee`,
      `$geo.food(drive_thru: true)` → drive-thru-friendly list.
    - **Gas / EV charging** → `$geo.gas` / `$geo.ev_charging`.
  - Settings / Profile button.

The map embed updates as the driver moves. The driver can pan/zoom
inside the iframe if they want to look around.

<a id="incoming-ride-request"></a>
### Incoming Ride Request

A modal that appears (with push notification if backgrounded) when
the rideshare backend matches this driver with a pickup.

- **Pickup address** (from rideshare backend; resolved through
  `$geo.address` if only coords were sent).
- **Distance to pickup** (linear via `$geo.distance_to`, then
  driving ETA via `$geo.eta_to`).
- **Estimated fare** (rideshare backend computes this).
- **Rider rating** (rideshare backend).
- **Special instructions** if any (rideshare backend).
- **Big visible countdown** until the request expires.
- **Accept / Decline** buttons.

If the driver accepts, the rideshare backend confirms and transitions
the ride to "en route." The app moves to the "To Pickup" screen.

<a id="to-pickup-en-route-to-rider"></a>
### To Pickup (en route to rider)

Active navigation screen — the driver is driving to the pickup
location.

- **Top half**: `$map.iframe_html` with the route drawn from current
  location to pickup. The route comes from
  `$geo.route_to(pickup_coords)`; the iframe URL is parameterized to
  show the route geometry. Reuses the static-map-with-route logic
  (`$route.map.iframe_html` or similar).
- **Below the map**: turn-by-turn directions, current step
  highlighted, distance to next maneuver visible. Pulled from
  `$route.steps`.
- **Rider info card**: rider name, photo, rating, instructions.
- **Contact rider button**: opens the rideshare backend's anonymous
  phone/text bridge.
- **ETA to pickup**: prominently displayed. Shared with the rider via
  the rideshare backend.
- **Cancel ride** button (with confirmation; this is a friction-y
  action for a reason).

ETA recalculates periodically (every minute, or on significant
location change). Each recalc is a `$geo.eta_to(pickup_coords)`
call from the driver's current location.

<a id="arrived-at-pickup"></a>
### Arrived at Pickup

Driver pulls up; app detects arrival (proximity to pickup coords).

- "I'm here" button (manual confirm; app's auto-detection is a hint,
  not a trigger).
- Map continues to show but smaller, with rider pin highlighted.
- Wait timer starts (in case the rider is late — backend may
  compute a wait fee).
- **Start Trip** button — driver presses when the rider is in the
  car.

<a id="in-trip-en-route-to-drop-off"></a>
### In Trip (en route to drop-off)

Same shape as "To Pickup" but routed to the drop-off coords.

- Map + route + turn-by-turn — `$route.map.iframe_html` from current
  location to drop-off.
- **Drop-off address** — `$geo.address` on the drop-off coords.
- **End Trip** button.
- **Trip duration** running timer.

<a id="end-trip"></a>
### End Trip

Driver pulls up at drop-off; presses End Trip.

- Fare summary (from rideshare backend).
- Rate the rider (1–5 stars).
- Notes (optional).
- Returns to Status / Main screen.

<a id="earnings"></a>
### Earnings

A separate screen showing recent rides, totals, payout status. Pure
rideshare-backend data; no puck.uno/geo involvement.

<a id="settings-profile"></a>
### Settings / Profile

Vehicle info, documents, driver preferences. Rideshare-backend data.

---

<a id="puckunogeo-usage-summary"></a>
## puck.uno/geo Usage Summary

Cross-referenced from the screens above:

| Screen | puck.uno/geo methods used |
|--------|---------------------------|
| Status / Main | `$map.html` (current location, with live tracking via postMessage), `$geo.restrooms`, `$geo.coffee`, `$geo.food(drive_thru:)`, `$geo.gas` |
| Incoming Request | `$geo.address` (resolve pickup), `$geo.distance_to`, `$geo.eta_to` |
| To Pickup | `$map.html` with `$map.navigation = true`; destination set programmatically (mechanism TBD) |
| Arrived at Pickup | `$geo.distance_to` (for proximity detection) |
| In Trip | `$map.html` with `$map.navigation = true`; destination set to drop-off coords |
| End Trip | none (rideshare backend handles fare/payment) |
| Earnings | none |
| Settings | none |

This is the **complete geo surface** the driver app uses. Any geo
method not on this list isn't needed for v1; any geo method on this
list needs to actually work well for v1 to ship.

---

<a id="validation-does-puckunogeo-have-whats-needed"></a>
## Validation: Does puck.uno/geo Have What's Needed?

Cross-checking the table above against the geo spec:

| Method | Status in geo spec |
|--------|-------------------|
| `$geo.address` | ✅ Spec'd |
| `$geo.distance_to` | ✅ Spec'd (linear distance) |
| `$geo.eta_to` | ✅ Spec'd in navigation brainstorm |
| `$geo.route_to` | ✅ Spec'd in navigation brainstorm |
| `$geo.restrooms` / `.coffee` / `.food` / `.gas` | ✅ Spec'd in `$geo.businesses` shortcuts |
| `$map.html` | ✅ Spec'd — DOM embed; the rendered map handles dynamic behavior internally |
| `$map.navigation = true` | ✅ Spec'd — toggles navigation features in the rendered map |
| `$map.voice = true` | ✅ Spec'd — toggles voice prompts during navigation |

<a id="gap-surfaced"></a>
### Gap surfaced

- **Programmatic destination control**. Setting `$map.navigation = true`
  gives the rendered map a destination-entry UI for users. But the
  driver app needs to set the destination *programmatically* (the
  pickup or drop-off coords from the rideshare backend, not typed by
  the driver). A `$map.destination` property (working name) needs to
  exist for this. Flagged in the geo spec as "may be added later";
  the driver app makes it a clear requirement, not optional.

The earlier "live-tracking map embed" and "route-as-map" gaps are
now resolved by the simpler navigation paradigm — the rendered map
handles all dynamic behavior internally; Caspian just toggles
features.

---

<a id="pwa-limitations-to-design-around"></a>
## PWA Limitations to Design Around

PWAs are not native apps; some things that "just work" on iOS/Android
require workarounds in a PWA. The driver app is particularly sensitive
to a few of these:

<a id="background-location"></a>
### Background location

Native apps can track location in the background. PWAs cannot
(deliberately — browser privacy protection). For a driver app this
means:

- **App must stay in the foreground** while accepting rides and
  during the ride itself. Mitigation: dashboard-mount-friendly UI;
  bright always-on display; wake lock to prevent screen sleep.
- **Location reporting to backend** uses the Geolocation API only
  when the app is foregrounded. Periodic reports during a ride —
  every 10–30 seconds depending on need.
- **When the app is backgrounded**, the rideshare backend loses
  driver location updates. New ride matching pauses; existing rides
  continue using last known position.

<a id="push-notifications"></a>
### Push notifications

Web Push API works on Android (Chrome, Firefox, Edge) and recently on
iOS (Safari 16.4+, requires PWA installed to home screen). For a
driver:

- **Incoming ride request notifications** are the critical use case.
  Must work reliably. iOS support depends on the driver installing
  the PWA to their home screen first.
- Mitigation: **explicit install prompt** during driver onboarding,
  with clear "you must install this to receive ride requests"
  messaging.

<a id="wake-lock"></a>
### Wake lock

Screen Wake Lock API keeps the screen from sleeping. Supported on
Android Chrome and recent iOS Safari. Critical for the driver — a
dimmed/locked screen mid-ride is a usability disaster.

<a id="offline-behavior"></a>
### Offline behavior

Spotty cell coverage is real (rural roads, parking garages, etc.).
The app needs:

- **Cached map tiles** for the immediate area, refreshed when
  connectivity returns. Service worker caches recent tile fetches.
- **Cached current route** so turn-by-turn continues even if the
  network drops mid-ride.
- **Queued state changes** ("ride ended" if pressed while offline)
  uploaded when connectivity returns.

<a id="battery"></a>
### Battery

Drivers run their phones 8–12+ hours a day. The app needs to be
battery-conscious:

- Avoid continuous high-frequency location polling when not needed.
- Throttle map redraws when stationary.
- Avoid keeping the map iframe loaded with full interactivity when
  the driver is on the status screen idling.

---

<a id="whats-out-of-scope-for-v1"></a>
## What's Out of Scope for v1

To keep the v1 scope honest:

- **Driver rating viewing / disputing.** Just the score is shown;
  no rich UI for managing it.
- **Document upload (license, insurance).** Done out-of-band before
  driver onboarding; not in the app.
- **Tip jar / direct gratuity.** Whatever the rideshare backend
  supports.
- **Multi-stop ride support.** v1 is single-pickup single-drop-off.
- **Surge zone heat maps.** Cool but not v1.
- **Ride sharing (UberPool-style).** v1 is single-passenger rides.
- **Driver community features (chat, leaderboards).** v1 is solo
  use.

---

<a id="open-questions"></a>
## Open Questions

- **Authentication mechanism.** PWAs don't have great native
  patterns for this. Probably an OAuth flow on first launch +
  device-key for subsequent sessions. Details TBD with the rideshare
  backend team (which is, at the moment, also Miko).
- **Real-time channel.** WebSocket vs Server-Sent Events. WebSocket
  is more flexible (bidirectional) but heavier; SSE is simpler if we
  only push down. Probably WebSocket for the ride-related flow.
- **Geo result caching client-side.** The puck.uno server already
  caches; should the PWA also maintain its own client-side cache of
  recent geo results to absorb repeat queries during a ride? Probably
  yes, in IndexedDB, with short TTLs.
- **Map provider for the iframe.** The geo spec leaves provider
  choice to puck.uno; for the driver app, we don't override it. But
  we may want to negotiate a higher cache TTL on the puck.uno side
  for areas a particular driver frequents (heuristic: same coords
  visited >N times in a week → bump TTL).
- **Voice navigation.** Drivers don't look at the screen continuously
  — voice prompts for turn-by-turn would be a huge win. Web Speech
  API can do this; whether it stays reliable in a PWA across iOS and
  Android is the question.

---

<a id="why-this-validates-the-geo-service"></a>
## Why This Validates the Geo Service

If this app ships and works well, that's strong evidence the
puck.uno/geo service is sufficient for real driver use. The doc
above pins down exactly which geo methods the app needs; gaps surface
as missing methods or weak performance. The validation feedback loop
goes:

1. Build the driver app per this spec.
2. Use it. Note where geo falls short.
3. Refine geo. Repeat.

Eating our own dog food is the point.
