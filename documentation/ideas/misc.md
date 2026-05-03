# Ideas

## Firewall Design

### What Is Settled

- Rules apply to entire records. Field-level filtering is a separate mechanism (see below).
- Rules use AND semantics: a record must pass every applicable rule or it is blocked.
- Every rule has three components: allow/prohibit, a Q0 condition, and a set of actions
  (select, create, update, delete).
- Direction (incoming/outgoing/both) is a required field on each rule — no default.
- Unreachable class definition is an error, not a policy decision.
- If an `allow` list is present in the final rule set, any record not covered by it is blocked.
- `prohibit` and `allow` are independent checks: `prohibit` is checked first; if the record
  is not prohibited and an `allow` list exists, the record must appear there.

### What Is Not Settled

#### Rule Structure

Three options were considered. The override key differs between them.

**Option 1: Array of rules with IDs**

Each rule is a self-contained object. Override by matching `id`. No `id` means no override
is possible from a later layer.

```json
[
    {
        "id": "block-meta",
        "prohibit": "kiera.uno/private",
        "on": "all"
    },
    {
        "id": "allow-person",
        "allow": "borg.com/person",
        "on": "select",
        "condition": {}
    }
]
```

**Option 2: Dict keyed by class, under `allow`/`prohibit`**

Override key is the class name within each bucket. Moving a class from `prohibit` to `allow`
requires two operations (delete from one, add to the other).

```json
{
    "prohibit": {
        "kiera.uno/private": {"on": "all"}
    },
    "allow": {
        "borg.com/person": {"on": "select", "condition": {}}
    }
}
```

**Option 3: Dict keyed by rule name**

Rule name is the override key. `allow`/`prohibit` and class live inside the rule. Easy to
flip a rule from prohibit to allow in one operation.

```json
{
    "block-meta": {
        "prohibit": "kiera.uno/private",
        "on": "all"
    },
    "allow-person": {
        "allow": "borg.com/person",
        "on": "select",
        "condition": {}
    }
}
```

Option 3 is the most flexible. Option 2 has the cleanest visual grouping by class.

#### Layered / Inherited Rules

Rules should be organized in layers so that a later layer can override an earlier one.
Every engine has a default layer; engine configuration adds one or more layers on top.
Layers are deep-merged into a final rule set. An entry with `{"delete": true}` removes
a rule from a previous layer.

How layers are expressed in configuration is not yet decided.

#### Default Restriction of Meta Records

Two approaches were considered:

1. **`pass_through: false` on the class definition.** Meta record classes declare themselves
   as restricted. Any engine evaluating a record checks the class definition. If
   `pass_through` is false, the record is blocked unless an explicit rule allows it. Clean
   because the policy travels with the class, not the engine config.

2. **Built-in default layer.** Every engine ships with a default layer that prohibits meta
   record classes. No special field needed on the class definition. Override with
   `delete: true` in a later layer.

Both approaches require that class definitions are always reachable.

---

## Field-Level Filters

Separate from record-level firewall rules. A filter strips fields from records that pass
the firewall, rather than blocking the record entirely.

Proposed structure:

```json
{
    "filters": {
        "borg.com/person": {
            "allow_fields": ["name", "birthdate"],
            "direction": "both"
        }
    }
}
```

Settled:
- Filters are per-class, keyed by class name.
- `allow_fields` is an allowlist — fields not listed are stripped.
- If a filter is configured for a class and an incoming write contains a field not in
  `allow_fields`, it is an error (not silently dropped). This prevents developers from
  wondering why their writes never land.
- `pk` and `class` are always preserved regardless of `allow_fields`.

Not yet settled:
- Whether a `deny_fields` counterpart to `allow_fields` should exist.
- Behavior when a record has multiple classes and more than one filter applies
  (union vs. intersection of allowed fields).
- Whether filters participate in the same layer/inheritance mechanism as rules.

---

## Rule IDs and Override / Inheritance

Every firewall rule can optionally declare an `id`. When engines inherit a default rule set,
a rule in the specific configuration can override a default rule by declaring the same `id`.

Not well thought out yet. May be resolved by whichever layering mechanism is chosen above.

---

## AI Agent Collaboration

See [agent-collaboration.md](agent-collaboration.md).
