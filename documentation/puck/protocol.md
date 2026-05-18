# Puck — Protocol Specification

~~~json
{"vibecode": {
	"doc": "puck-protocol",
	"role": "formal spec for the JSON expression of Puck — building up piece by piece, starting with class definitions; the HTML expression is described separately in puck-html.md",
	"status": "in_development_starting_with_class_definitions",
	"key_concepts": ["json_wire_format", "class_definition_json",
		"shared_shape_with_charlie_and_mikobase",
		"remote_methods_block", "method_params_and_returns"],
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
