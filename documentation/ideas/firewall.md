# Firewall Rules

## Overview

```
vibecode: {
	"section": "overview"
}
```

Firewall rules are built into every engine, the same way Q0 is. They are not a separate
engine type — any engine can be configured as a firewall by giving it rules. An engine with
only rules and no other behavior (no DBMS connection, no HTTP forwarding) is a valid and
useful configuration, but it is a configuration, not a distinct type.

Because rules are part of the base engine spec, every engine author must implement rule
processing, just as every engine author must implement Q0.

This means defense in depth is natural: rules can be applied at any point in the chain
without inserting a dedicated layer.

Rules apply to entire records. There is no field-level filtering.

---

## Two Types of Rules

**Static rules** — described in this document. A JSON structure that expresses conditions
using Q0.

**Dynamic rules** — developer-written code for situations the static rules cannot express.
Not yet designed.

---

## Static Rule Structure

A rule has three required fields:

| Field       | Required | Description |
|-------------|----------|-------------|
| `on`        | yes      | Which operations this rule applies to |
| `direction` | yes      | Whether the rule applies to incoming queries, outgoing results, or both |
| `allow`     | yes      | A Q0 filter defining which records are permitted |

```json
{
    "rules": [
        {
            "on":        "select",
            "direction": "outgoing",
            "allow":     {"class": "borg.com/person"}
        }
    ]
}
```

### `on`

Specifies which operations the rule covers. Accepts a single value or an array.

Valid values:
- `"select"`, `"create"`, `"update"`, `"delete"` — specific operations
- `"read"` — shorthand for `"select"`
- `"write"` — shorthand for `["create", "update", "delete"]`

### `direction`

Required. No default — omitting it is a validation error.

| Value        | Meaning |
|--------------|---------|
| `"incoming"` | Applies to queries and writes coming in to the engine |
| `"outgoing"` | Applies to results going out from the engine |
| `"both"`     | Applies in both directions |

### `allow`

A Q0 filter defining which records are permitted. Uses the same syntax as a Q0 select
query but without the `action` field — the operation is already declared in `on`.

The `allow` filter may include callbacks. Every engine a callback hits must recognize it
or the query fails with an error.

---

## Default Behavior

- If no rules cover an operation, everything passes — the engine is transparent for that
  operation, subject to class-level restrictions (see below).
- Once at least one rule exists for an operation and direction, a record must pass every
  applicable rule or it is blocked.
- Multiple rules for the same operation use AND semantics: a record is permitted only if
  it satisfies all matching rules.
- To allow multiple alternatives within a single rule, use Q0's native syntax —
  `{"class": ["foo.com/a", "foo.com/b"]}` — rather than separate rules.

---

## Class-Level Pass-Through Restriction

A class definition can declare:

```json
{
    "name": "borg.com/foo",
    "pass_through": false
}
```

When `pass_through` is `false`, records of that class are blocked by default — even when
no rules are configured. To allow them through, an explicit rule must cover them.

The default value of `pass_through` is `true`. Classes that omit it are passable under
normal rule evaluation.

This is how meta records are restricted: they are defined with `pass_through: false`. No
engine needs special meta-record logic — the class definition carries the policy.

**Class definition reachability**: engines and clients are always expected to be able to
reach class definitions. Failure to retrieve a class definition when evaluating a record
is an error, not a policy decision.

---

## Rule Validation

Rules are validated before the engine processes anything — at startup, or whenever the
rule set is loaded. A rule set that fails validation raises an error and halts the engine.

The validator checks:

- `direction` is present and one of `"incoming"`, `"outgoing"`, `"both"`
- `on` is present and contains only valid operation values
- `allow` is present and is a valid Q0 structure
- No unrecognized keys appear in the rule (catches typos)

---

## Example: Read-Only Access to a Class

```json
{
    "rules": [
        {
            "on":        "select",
            "direction": "outgoing",
            "allow":     {"class": "borg.com/person"}
        }
    ]
}
```

Only `borg.com/person` records are returned. No writes are restricted by this rule.

## Example: Read and Write Access, Write Gated by Callback

```json
{
    "rules": [
        {
            "on":        "select",
            "direction": "outgoing",
            "allow":     {"class": "borg.com/person"}
        },
        {
            "on":        ["create", "update", "delete"],
            "direction": "incoming",
            "allow":     {"class": "borg.com/person", "callback": "borg.com/callbacks/is-owner"}
        }
    ]
}
```
