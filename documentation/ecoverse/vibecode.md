# Reserved Pass-Through Fields

<a id="overview"></a>
## 1 Overview

vibecode: {
	"section": "overview",
	"role": "introduces the four reserved pass-through fields in all Kieraverse JSON objects",
	"key_concepts": ["vibecode", "comment", "misc", "enterprise", "pass-through", "always_present"]
}

The Kieraverse reserves four keys in every JSON hash: `vibecode`, `comment`, `misc`, and
`enterprise`. All four travel silently with any object — passed through transparently by
engines, firewalls, and network transport without being stripped, validated, or modified.
An object's schema does not need to declare them; they are always present by convention.

---

<a id="vibecode"></a>
## 2 `vibecode`

`vibecode` carries AI-readable context alongside the object it describes. It is passed
through transparently — not stripped, not validated, not modified by engines, firewalls,
or the wire. Any AI reading the object at any point in the system can find the context
it needs.

---

<a id="structure"></a>
## 3 Structure

`vibecode` is a free-form hash. There is no required schema. Useful fields include:

| Field | Description |
|---|---|
| `purpose` | Plain-language description of what this object is and what it does |
| `ai_notes` | Array of behavioral notes, constraints, and gotchas an AI should know |
| `related_objects` | Array of related object names or UNS classes |

Other fields may be added as needed. The structure is intentionally open.

---

<a id="example"></a>
## 4 Example

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
## 5 Where It Applies

`vibecode` can appear in any JSON hash in the Kieraverse — any object, anywhere:

- Class definitions
- Individual methods and properties within a class
- Records
- Q0 queries
- Charlie functions
- Mikobase configurations
- Firewall rules

There is no object too small to carry `vibecode`.

---

<a id="remote-classes"></a>
## 6 Remote Classes

`vibecode` is especially valuable on remote classes. When an AI is asked to instantiate
a class from `borg.com/person` and do something with it, it downloads the class definition
— which includes the method stubs, local Charlie, and all `vibecode`. The AI gets
everything it needs to use the class correctly in a single download, with no external
documentation required.

This means a developer who writes good `vibecode` on their class is writing instructions
for any AI that will ever use it — including AIs they will never meet. The ecosystem
creates a natural incentive: if you want AIs to use your remote class correctly, write
good `vibecode`.

---

<a id="in-charlie-document-and-vibecode"></a>
## 7 In Charlie: `%document` and `%vibecode`

`%document` is the general mechanism for saving documentation into the CharlieJSON
command array. It takes a MIME type and a heredoc or string:

```
%document 'text/plain' <<EOF
Some plain text note.
EOF

%document 'text/markdown' <<EOF
## Notes
Some *markdown* content.
EOF

%document 'text/vibecode' <<EOF
{"purpose":"instantiate a new officer record"}
EOF
```

<a id="shorthand-type-names"></a>
### 7.1 Shorthand type names

A few popular MIME types have shorthand aliases:

| Shorthand | Full MIME type |
|-----------|----------------|
| `text` | `text/plain` |
| `markdown` | `text/markdown` |
| `vibecode` | `text/vibecode` |

So these are equivalent:

```
%document 'vibecode' <<EOF
{"purpose":"..."}
EOF

%document 'text/vibecode' <<EOF
{"purpose":"..."}
EOF
```

<a id="vibecode-1"></a>
### 7.2 `%vibecode`

`%vibecode` is a further shorthand for `%document 'vibecode'`:

```
%vibecode <<EOF
{"purpose":"..."}
EOF
```

is identical to:

```
%document 'vibecode' <<EOF
{"purpose":"..."}
EOF
```

which is identical to:

```
%document 'text/vibecode' <<EOF
{"purpose":"..."}
EOF
```

All rules that apply to `%vibecode` — storage in the command array, the `side` field,
attachment semantics — apply equally to all `%document` statements regardless of type.

Syntax highlighters should support all three forms.

To indicate what a `%vibecode` block is documenting in an assignment context, use the
`side` field:

- `"side":"target"` — documents the variable being assigned (left-hand side)
- `"side":"value"` — documents the expression producing the value (right-hand side)
- omit `side` — for statements with no assignment (method calls, `puts`, etc.)

Two blocks can appear together when both sides warrant documentation:

```
%vibecode <<EOF
{"side":"target","purpose":"stores the active officer collection for use in the report loop"}
EOF
%vibecode <<EOF
{"side":"value","purpose":"selects all officers where active == true from the mikobase"}
EOF

$active = $mikobase.q0({action: :select, class: 'starfleet.com/officer',
then: {path: ['active', true]}})
```

For a simple statement with no assignment:

```
%vibecode <<EOF
{"purpose":"print the completed report to stdout"}
EOF

puts($report)
```

---

<a id="pass-through"></a>
## 8 Pass-Through

All four reserved fields (`vibecode`, `comment`, `misc`, `enterprise`) are always passed through. Engines, firewalls, and network
transport do not strip or modify them. The whole point is that any consumer reading the
object — at any point in its journey through the system — has access to whatever was
placed in these fields.

---

<a id="comment"></a>
## 9 `comment`

`comment` carries human-readable notes alongside the object. It is for things you want
to say to a human reader — a quick explanation of why something is done a certain way,
a caveat, a TODO. It is not AI documentation (`vibecode`) and not formal metadata
(`enterprise`).

```json
{
    "foo": "bar",
    "comment": "This field is intentionally left empty during the seed phase."
}
```

---

<a id="misc"></a>
## 10 `misc`

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

<a id="enterprise"></a>
## 11 `enterprise`

`enterprise` fills the same pass-through role as `misc`, but is reserved for formally
defined standards. Content in `enterprise` should follow agreed-upon schemas or
namespacing conventions so that different systems can rely on what they find there.

```json
{
    "foo": "bar",
    "enterprise": {
        "acme.com/audit": {
            "created_by": "picard",
            "approved_by": "riker"
        }
    }
}
```

The distinction between `misc` and `enterprise` is governance, not mechanics. Both travel
with the object in exactly the same way.
