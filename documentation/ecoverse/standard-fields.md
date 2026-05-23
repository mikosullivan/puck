# Reserved Pass-Through Fields

<a id="overview"></a>
## Overview

~~~json
{"vibecode": {
	"section": "overview",
	"role": "introduces the four reserved pass-through fields in all Puckverse JSON objects",
	"key_concepts": ["vibecode", "comment", "misc", "corporate", "pass-through", "always_present"]
}}
~~~

The Puckverse reserves four keys in every JSON hash: `vibecode`, `comment`, `misc`, and
`corporate`. All four travel silently with any object — passed through transparently by
engines, firewalls, and network transport without being stripped, validated, or modified.
An object's schema does not need to declare them; they are always present by convention.

---

<a id="vibecode"></a>
## `vibecode`

`vibecode` carries AI-readable context alongside the object it describes.  Any AI
reading the object at any point in the system can find the context it needs.

---

<a id="structure"></a>
## Structure

`vibecode` is a free-form hash. There is no required schema. Useful fields include:

| Field | Description |
|---|---|
| `purpose` | Plain-language description of what this object is and what it does |
| `ai_notes` | Array of behavioral notes, constraints, and gotchas an AI should know |
| `related_objects` | Array of related object names or UNS classes |

Other fields may be added as needed. The structure is intentionally open.

---

<a id="example"></a>
## Example

```json
{
    "foo": "class",
    "bar": "invoice",

    "vibecode": {
        "purpose": "Represents a customer invoice.",
        "ai_notes": [
            "Do not treat paid invoices as editable.",
            "Line totals should be derived from line items.",
            "Use the object's methods instead of recalculating taxes externally."
        ],
        "related_objects": [
            "customer",
            "payment",
            "invoice_line"
        ]
    }
}
```

---

<a id="where-it-applies"></a>
## Where It Applies

`vibecode` can appear in any JSON hash in the Puckverse — any object, anywhere:

- Class definitions
- Individual methods and properties within a class
- Records
- Q0 queries
- Caspian functions
- Mikobase configurations
- Firewall rules

There is no object too small to carry `vibecode`.

---

<a id="remote-classes"></a>
## Remote Classes

`vibecode` is especially valuable on remote classes. When an AI is asked to instantiate
a class from `borg.com/person` and do something with it, it downloads the class definition
— which includes the method stubs, local Caspian, and all `vibecode`. The AI gets
everything it needs to use the class correctly in a single download, with no external
documentation required.

This means a developer who writes good `vibecode` on their class is writing instructions
for any AI that will ever use it — including AIs they will never meet. The ecosystem
creates a natural incentive: if you want AIs to use your remote class correctly, write
good `vibecode`.

---

<a id="in-caspian-documentation-and-vibecode"></a>
## In Caspian: `%documentation` and `%vibecode`

In addition to the `%documentation` feature, Caspian also has a `%vibecode`
method:


```
%vibecode <<EOF
{"purpose":"..."}
EOF


<a id="pass-through"></a>
## Pass-Through

All four reserved fields (`vibecode`, `comment`, `misc`, `corporate`) are always passed through. Engines, firewalls, and network transport do not strip or modify them.

---

<a id="misc"></a>
## `misc`

`misc` is a free-rider field for informal, ad hoc use. It has no defined schema and no
governance — any system or developer can put whatever they need there. Over time, `misc`
tends to accumulate a hodgepodge of conflicting conventions from different teams and
systems. That is expected and acceptable; it is what `misc` is for.

```json
{
    "foo": "bar",
    "misc": {
        "internal_tracking_id": "abc-123",
        "legacy_system_ref":    "old-format-id"
    }
}
```

---

<a id="corporate"></a>
## `corporate`

`corporate` fills the same pass-through role as `misc`, but is reserved for formally
defined standards. Content in `corporate` should follow agreed-upon schemas or
namespacing conventions so that different systems can rely on what they find there.

```json
{
    "foo": "bar",
    "corporate": {
        "acme.com/audit": {
            "created_by": "picard",
            "approved_by": "riker"
        }
    }
}
```

The distinction between `misc` and `corporate` is governance, not mechanics. Both travel
with the object in exactly the same way.
