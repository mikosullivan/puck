# Puck — Protocol Specification

~~~json
{"vibecode": {
	"doc": "puck-protocol",
	"role": "formal spec for the JSON expression of Puck — building up piece by piece, starting with class definitions; the HTML expression is described separately in puck-html.md",
	"status": "in_development_starting_with_class_definitions",
	"key_concepts": ["json_wire_format", "class_definition_json",
		"shared_shape_with_charlie_and_mikobase",
		"remote_methods_block", "method_params_and_returns",
		"self_contained_vs_pk_reference_instances"],
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

<a id="class-definition"></a>
## 1 Class definition

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
        "census_district": {
            "returns": {"class": "puck.uno/census_district"}
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
    (`weather`, `census_district` above). **All Puck params are
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
## 2 Invoking a method

To invoke a remote method, **the client sends the entire instance
to the server**, along with the method name and the params hash.
The request body is a JSON object with three top-level keys:

- **`instance`** — the full object being called on, including its
  `class` UNS and all field values.
- **`method`** — name of the method to invoke.
- **`params`** *(optional)* — hash of named arguments. Omit when
  the method takes none.

For example, calling `weather` on a Geo instance pointing at
Starfleet HQ in San Francisco:

```json
{
    "instance": {
        "class": "puck.uno/geo",
        "lat": 37.7980,
        "lon": -122.4626
    },
    "method": "weather"
}
```

And calling `map_image(zoom=14)` on the same instance:

```json
{
    "instance": {
        "class": "puck.uno/geo",
        "lat": 37.7980,
        "lon": -122.4626
    },
    "method": "map_image",
    "params": {
        "zoom": 14
    }
}
```

**The server is stateless with respect to instance identity.** It
keeps no handles, no sessions, no per-instance state between calls.
Each request carries the object it operates on. Subsequent calls on
the "same" instance from the client's perspective each re-send the
full instance — the server reconstructs whatever it needs each time.
Field values that a particular method doesn't actually use are
still sent; the protocol doesn't try to optimize that away.

**In practice the cost is small.** Most Puck objects are tiny — a
Geo is two numbers, a CensusDistrict reference is one UNS string, a
Color is one hex code. The wire payload is mostly HTTP/JSON
envelope; the object data itself rarely amounts to much.

---

<a id="reference-style-instances"></a>
## 3 Reference-style instances

The Geo example in §1–2 carries all of its state in fields (`lat`
and `lon`) — every call sends those numbers across the wire. That's
fine when the object's full state is small and the client can
plausibly know it.

But many objects only make sense **server-side**. A row in a
database, a record in a registry, a long-lived account — these live
somewhere; the client has no way to hold their full state and
shouldn't need to. For these, a Puck class can carry just enough
information to identify the object — typically a single primary-key
field — and let the server resolve everything else.

Example: a Starfleet starship class keyed by registry number:

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

The class declares one field — `registry`, the primary key. The
server holds the actual data (name, captain, location, crew, mission
logs, everything). A client asking about a ship sends just the
registry:

```json
{
    "instance": {
        "class": "starfleet.com/starship",
        "registry": "NCC-1701-D"
    },
    "method": "captain"
}
```

The server resolves `NCC-1701-D` against its database, finds the
Enterprise-D, and returns the captain as a `starfleet.com/officer`
reference — itself probably another PK-only object the client can
make further calls on.

**Same wire shape, different sized payload.** From the protocol's
perspective, the Geo and Starship examples are identical: instance
hash + method + optional params. The only difference is how much of
the instance actually fits in the hash. Class designers choose
between the two patterns:

- **Self-contained instance** (Geo) — the object's full state is
  the fields. Server holds no per-instance state; client and server
  agree on the data each call. Good when the state is small enough
  to ship per-call and the client is the canonical owner.
- **Reference by primary key** (Starship) — the object's fields
  are just identifiers; the server holds the data. Good when the
  state is too big to ship per-call, when the data lives in a
  database the client can't replicate, or when the server is the
  canonical owner of the value.

Most Puck classes pick one shape or the other. Mixed forms (some
fields carried, some server-resolved) are allowed; the protocol
doesn't care.

