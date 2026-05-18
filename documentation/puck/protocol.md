# Puck — Protocol Specification

~~~json
{"vibecode": {
	"doc": "puck-protocol",
	"role": "formal spec for the JSON expression of Puck — building up piece by piece, starting with class definitions; the HTML expression is described separately in puck-html.md",
	"status": "in_development_starting_with_class_definitions",
	"key_concepts": ["json_wire_format", "class_definition_json",
		"shared_shape_with_charlie_and_mikobase",
		"remote_methods_block", "method_params_and_returns",
		"dynamic_objects_are_pucks_on_the_wire",
		"stored_objects_live_on_servers_referenced_by_dynamic_objects",
		"method_dispatch_via_url", "instance_body_is_class_plus_bucket"],
	"audience": ["puck_protocol_designers", "puck_server_implementors",
		"puck_client_implementors_in_any_language"],
	"example_universe": "Star Trek",
	"example_language": "JSON"
}}
~~~

This doc defines the **Puck wire protocol expressed in JSON** — the
message structures and behaviors that a Puck server and client
agree on when speaking JSON over HTTP.

The conceptual overview is in [puck.md](puck.md); a Python client
sketch is in [python.md](python.md); this doc is the formal spec.

JSON is the primary wire format. Puck can also be expressed in HTML.
The HTML expression is described separately in
[puck-html.md](puck-html.md); JSON and HTML formats are convertible
losslessly.

**Status: in development.**

---

<a id="dynamic-and-stored-objects"></a>
## 1 Dynamic and stored objects

Two terms used throughout this doc:

- **Dynamic objects** — the pucks themselves. They live for the
  duration of a process and are what actually moves across the
  wire. Every request and response carries dynamic objects.
- **Stored objects** — long-lived data that lives on a server (a
  database row, a registry entry, a file in a content store).
  Stored objects don't themselves cross the wire; a dynamic object
  can carry a reference to one.

The Geo example in §2–3 below is a **dynamic object** whose entire
state is its fields (`lat`, `lon`) — nothing behind it on any
server. The Starship example in §4 is a dynamic object that holds
just a primary key (`registry`) and is a reference to a **stored
object** — the actual ship data on the Starfleet server.

---

<a id="class-definition"></a>
## 2 Class definition

A Puck class is defined in JSON, using the **same shape Charlie and
Mikobase use** (see [class-definition.md](../charlie/class-definition.md)
for the full Mikobase/Charlie spec). Here's `puck.uno/geo` with two
fields and three remote methods:

```json
{
    "name": "puck.uno/geo",
    "fields": {
        "lat": {"class": "number", "required": true},
        "lon": {"class": "number", "required": true}
    },
    "methods": {
        "weather": {
            "returns": {"class": "puck.uno/weather_report"}
        },
        "congressional_district": {
            "returns": {"class": "puck.uno/congressional_district"}
        },
        "map_image": {
            "params": {
                "zoom": {"class": "number", "integer_only": true, "default": 14}
            },
            "returns": {"class": "puck.uno/image"}
        }
    }
}
```

- **`fields`** — the class's data slots. Two required numbers
  (`lat`, `lon`) here. An instance is constructed by supplying
  values for the fields.
- **`methods`** — operations a client can invoke on an instance.
  Each method definition has:
  - **`params`** *(optional)* — named parameters, each in the same
    shape as a field definition (`class`, `required`, `default`,
    `min`, `max`, etc.). Omit when the method takes no args
    (`weather`, `congressional_district` above). **All Puck params are
    named**: on the wire they're always a JSON hash keyed by name.
    There are no positional placeholders.
  - **`returns`** — the type of the value the method produces, also
    in field-definition shape. The `class` can be a primitive
    (`string`, `number`, ...) or a UNS for a Puck class — in which
    case the call returns a reference to a remote object the client
    can call further methods on.

Every method in this block is callable by a Puck client over the
wire. The server side of the class implements them; the JSON
definition is what a client needs to know to dispatch a call
correctly.

---

<a id="invoking-a-method"></a>
## 3 Invoking a method

A method call is **typically a POST** to a URL that encodes the
class and the method, with a body that carries the instance's
`class` and `bucket` (the field-value hash):

- **URL** — `https://{class-uns}/{method}`. The method name lives
  in the URL, not the body.
- **HTTP verb** — POST in most cases. The protocol allows other
  verbs (GET, PUT, DELETE, ...); class designers can pick what fits
  each method's semantics. POST is the safe default and what the
  examples below use.
- **Body** — JSON with `class` (the UNS of the instance's class)
  and `bucket` (the field-value hash), plus `params` if the method
  takes any named arguments.

For example, calling `weather` on a Geo instance pointing at
Starfleet HQ in San Francisco:

```
POST https://puck.uno/geo/weather
```

with body:

```json
{
    "class": "puck.uno/geo",
    "bucket": {
        "lat": 37.7980,
        "lon": -122.4626
    }
}
```

And calling `map_image(zoom=14)` on the same instance:

```
POST https://puck.uno/geo/map_image
```

with body:

```json
{
    "class": "puck.uno/geo",
    "bucket": {
        "lat": 37.7980,
        "lon": -122.4626
    },
    "params": {
        "zoom": 14
    }
}
```

The `class` in the body looks redundant with the URL, but it's the
canonical declaration of what the bucket conforms to — useful for
validation, for forwarding the call to another handler without
re-parsing the URL, and for logs and replay.

<a id="response-shape"></a>
### 3.1 Response shape

The response body is the method's return value, encoded as JSON
with no envelope. The HTTP status code carries success/failure
(`200 OK` for normal returns, error codes for the
[error catalog](puck.md#error-catalog) — TBD here).

For a **primitive return**, the body is just the primitive. For
example, the response from a hypothetical `hq.name` (returning a
string) is:

```json
"Starfleet HQ"
```

For an **object return**, the body is a dynamic puck — `class`
plus `bucket`. The response from `congressional_district` on the
Geo instance from §3 returns a dynamic puck that references the
stored CongressionalDistrict for that location:

```json
{
    "class": "puck.uno/congressional_district",
    "bucket": {
        "code": "CA-11"
    }
}
```

The client can use that returned puck as the body of further
calls. To know what methods the returned object exposes, the client
should fetch the class definition from
`https://puck.uno/congressional_district` — the class's UNS doubles
as the URL where its JSON definition lives. To get the
representative, the client then takes the returned puck verbatim
and POSTs it to the `representative` method's URL:

```
POST https://puck.uno/congressional_district/representative
```

with the same body it just received as the response.

**The server is stateless with respect to instance identity.** It
keeps no handles, no sessions, no per-instance state between calls.
Each request carries the object it operates on. Subsequent calls on
the "same" instance from the client's perspective each re-send the
full instance — the server reconstructs whatever it needs each time.
Field values that a particular method doesn't actually use are
still sent; the protocol doesn't try to optimize that away.

**In practice the cost is small.** Most Puck objects are tiny — a
Geo is two numbers, a CongressionalDistrict reference is one UNS string, a
Color is one hex code. The wire payload is mostly HTTP/JSON
envelope; the object data itself rarely amounts to much.

---

<a id="stored-objects"></a>
## 4 Stored objects

The Geo example in §2–3 is a **dynamic object** that carries all
of its state in fields (`lat` and `lon`) — there's nothing behind
it on any server. Every call ships those numbers and that's it.

But many objects only make sense **server-side**: a row in a
database, a record in a registry, a long-lived account. These are
**stored objects** — they live on a server, and they're too big or
too sensitive or too database-bound to ship in full. For these, a
Puck class defines a dynamic object that carries just enough to
**reference** the stored one — typically a single primary-key
field — and lets the server resolve everything else.

Example: a Starfleet starship class keyed by registry number. The
dynamic puck has one field; the stored object (the actual ship
record, with name, captain, mission logs, crew list) lives in the
Starfleet database.

```json
{
    "name": "starfleet.com/starship",
    "fields": {
        "registry": {"class": "string", "required": true}
    },
    "methods": {
        "name":             {"returns": {"class": "string"}},
        "captain":          {"returns": {"class": "starfleet.com/officer"}},
        "current_location": {"returns": {"class": "puck.uno/geo"}}
    }
}
```

The dynamic class declares one field — `registry`, the primary
key — and three methods. The server holds the stored object. A
client asking for the ship's captain hits the captain method's URL
and sends just the dynamic puck (class + one-key bucket):

```
POST https://starfleet.com/starship/captain
```

with body:

```json
{
    "class": "starfleet.com/starship",
    "bucket": {
        "registry": "NCC-1701-D"
    }
}
```

The server resolves `NCC-1701-D` against its database, finds the
Enterprise-D, and returns the captain as a `starfleet.com/officer`
reference — itself probably another PK-only object the client can
make further calls on.

**Same wire shape, different sized bucket.** From the protocol's
perspective, the Geo and Starship examples are identical: a URL
that names class + method, and a body with `class`, `bucket`, and
optional `params`. The only difference is what the dynamic object
represents:

- **Dynamic-only** (Geo) — the dynamic object is the whole thing.
  Its fields are its full state. Nothing is stored anywhere; the
  client is the canonical holder. Good when state is small enough
  to ship per call.
- **Dynamic + stored** (Starship) — the dynamic object is a
  reference; the real value is a stored object on the server. The
  bucket carries identifiers only. Good when the underlying data
  is too big to ship per call, lives in a database the client
  can't replicate, or is owned by the server.

Most Puck classes pick one shape or the other. Mixed forms (some
fields carried, some server-resolved) are allowed; the protocol
doesn't care.

