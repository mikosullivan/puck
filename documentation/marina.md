# Marina

Marina is the codeword for a design exploration of Kiera, Q0, and class definitions that was set aside. These ideas were developed collaboratively and may be revisited and incorporated into the final design later.

---

# Part 1: Kiera

## Overview

Kiera is a remote object system designed to be simpler and more intuitive than systems like
REST. Classes in Kiera are identified by UNS strings — a URL without the `https://`
protocol prefix — providing a globally unique namespace.

Examples:

- `kiera.uno/query`
- `kiera.uno/error`
- `kiera.uno/exception`

Every popular language has a Kiera interpreter, allowing developers in different languages
to work with the same remote objects in a consistent way.

Mikobase is designed to conform to Kiera standards. The class definition format is shared
between the two systems. A class definition bucket written for Mikobase is valid in Kiera.

---

## Implicit Class from Context

Every Kiera object (hash/dict) has a `class` field, either explicit or implied by context.
When `class` is absent, the Kiera interpreter determines the class from the surrounding
context — for example, the field name it appears under, the method it was returned from, or
the type declared in a class definition.

A formal mechanism for declaring and resolving implicit class rules has not yet been
defined. For now, implicit class rules are documented ad-hoc where they apply.

---

## Getting a Class

`kiera.get_class(uns, **params)` fetches a class definition from its UNS URL and returns a
local class object. The class definition includes fields and remote methods. Parameters may
be used to control which version of the definition is retrieved — for example, `cutoff`
pins the definition to a historical point in time.

The bracket shorthand `kiera[uns]` is equivalent to `kiera.get_class(uns)` with no params:

```python
clss = kiera['kiera.uno/color']              # shorthand
clss = kiera.get_class('kiera.uno/color')    # equivalent

clss = kiera.get_class('kiera.uno/color', cutoff='2026-09-21')  # with params
```

## Creating an Object

`clss.new(**fields)` creates a new instance of the class with the given field values. The
resulting object behaves like any local object — fields are accessible as properties and
methods are callable normally.

```python
clss = kiera['kiera.uno/color']
color = clss.new(hex='#ff0000')
```

`kiera.create(uns, **fields)` is a shorthand that fetches the latest class definition and
creates an instance in one step:

```python
color = kiera.create('kiera.uno/color', hex='#ff0000')
```

This is equivalent to `kiera[uns].new(**fields)`.

---

## Method Calls

When a method is called on a Kiera object, the **entire object** is serialized and sent to
the method's URL. A response is received and returned to the caller.

The class definition specifies each method's required and optional parameters, and what to
expect in the response.

## Request Structure

A Kiera request is a JSON object with the following fields:

```json
{
    "class":  "kiera.uno/request",
    "method": "kiera.uno/color/hex",

    "object": {
        "rgb": [122, 93, 81]
    },

    "params": {}
}
```

- `class` — identifies the request type. Usually redundant since the receiving URL implies
  it.
- `method` — the method being called. Usually redundant since the URL implies it.
- `object` — the full field values of the Kiera object being sent. The class of the object
  is implicit in the request context and is not repeated inside `object`.
- `params` — method-specific arguments, separate from the object's own field values.

When `class` or `method` conflict with what the URL implies, the server may set policies.
Specific rules:

- If `method` differs from what the URL implies but is an alias for that method, the
  request is processed without error.
- If `method` refers to a method that does not exist, the server returns an error object.
- If `class` is not a request class, the server returns an error object. A subclass of
  `kiera.uno/request` is acceptable, but the server must already know it is a subclass —
  the server is not required to query the UNS to verify the inheritance relationship.

The response structure is not yet defined.

---

## Value Objects and Stored Objects

All Kiera objects are the same type — they carry their field values with every method call.
There is no formal Stored Object class.

The terms **value object** and **stored object** are used informally as a shorthand:

- **Value object** — the object contains all its meaningful data directly in its fields.
- **Stored object** — the object's real data lives on the server; the object itself carries
  only enough to identify it (typically a `pk`). A Mikobase record is a stored object in
  this sense.

From Kiera's perspective both are the same thing — a set of fields sent whole on every
method call. The distinction is a description of how a class is designed, not a type system
concept.

```python
# Value object — all data is in the object
color = kiera.create('kiera.uno/color', hex='#ff0000')

# Stored object — real data is on the server, object carries a pk
character = kiera.create('foo.com/character', pk='92677339-df86-4f68-9397-999e40cf2c40')
```

---

## `kiera: true`

A class definition with `"kiera": true` signals that remote method calls may be made using
objects of that class.

```json
{
    "name": "foo.com/bar",
    "kiera": true
}
```

---

## `kiera.uno/exception`

The base class for all exceptions in Kiera. `kiera.uno/error` is a subclass of
`kiera.uno/exception`. Further details of the exception hierarchy are not yet defined.

---

## `kiera.uno/error`

The base class for all errors. An error object is a first-class object with
`"class": "kiera.uno/error"` (or a subclass).

`{"error": true}` is shorthand for `{"class": "kiera.uno/error"}`. The `error` field may
be any truthy value.

```json
{"error": true}
{"class": "kiera.uno/error"}
```

Error objects propagate upward through expression chains without further evaluation.

---

## `kiera.uno/query`

`kiera.uno/query` is the base class for the Kiera expression language. It defines a set of
general-purpose operators usable in any Kiera context.

`mikobase.com/q0` inherits `kiera.uno/query` and extends it with Mikobase-specific
operators for accessing record data.

### Expression Format

An expression is either a **literal** (any JSON scalar or array) or an **operator object**
(a single-key JSON object whose key names the operation).

### Current Timestamp

`{"now": true}` returns the current timestamp at the moment the query is executed, frozen
once at the start of execution.

### Arithmetic

| Operator | Description |
|---|---|
| `{"add": [a, b]}` | Addition |
| `{"subtract": [a, b]}` | Subtraction |
| `{"multiply": [a, b]}` | Multiplication |
| `{"divide": [a, b]}` | Division — returns `null` on division by zero |
| `{"mod": [a, b]}` | Modulo (remainder) |

### String

| Operator | Description |
|---|---|
| `{"concat": [...]}` | Concatenate two or more strings |
| `{"upper": expr}` | Uppercase |
| `{"lower": expr}` | Lowercase |
| `{"trim": expr}` | Strip leading and trailing whitespace |
| `{"length": expr}` | Character count |

### Array Aggregation

| Operator | Description |
|---|---|
| `{"sum": expr}` | Sum of numeric elements |
| `{"avg": expr}` | Average of numeric elements |
| `{"min": expr}` | Minimum numeric element |
| `{"max": expr}` | Maximum numeric element |

Non-numeric elements are ignored. Empty or all-non-numeric arrays return `null`.

### Selection

| Operator | Description |
|---|---|
| `{"coalesce": [...]}` | First non-null value |
| `{"first-truthy": [...]}` | First truthy value |

Returns `null` if no element meets the condition.

### Date and Time

Timestamps are ISO 8601 strings with millisecond precision.

`{"duration": [a, b]}` — elapsed time from `a` to `b` as an internal duration value.

Duration extraction (return integers):

| Operator | Description |
|---|---|
| `{"years": expr}` | Whole years |
| `{"months": expr}` | Whole months |
| `{"days": expr}` | Whole days |
| `{"hours": expr}` | Whole hours |
| `{"minutes": expr}` | Whole minutes |
| `{"seconds": expr}` | Whole seconds (truncated) |

Timestamp component extraction (return integers):

| Operator | Description |
|---|---|
| `{"year": expr}` | Calendar year |
| `{"month": expr}` | Month (1–12) |
| `{"day": expr}` | Day of month (1–31) |
| `{"hour": expr}` | Hour (0–23) |
| `{"minute": expr}` | Minute (0–59) |
| `{"second": expr}` | Second (0–59) |

### Comparison

Take a two-element array. Return a boolean. Work for numbers, strings (lexicographic), and
timestamps (chronological). Comparing values of different types returns `null`.

| Operator | Alias | Description |
|---|---|---|
| `{"eq": [a, b]}` | `==` | Equal |
| `{"neq": [a, b]}` | `!=` | Not equal |
| `{"gt": [a, b]}` | `>` | Greater than |
| `{"lt": [a, b]}` | `<` | Less than |
| `{"gte": [a, b]}` | `>=` | Greater than or equal |
| `{"lte": [a, b]}` | `<=` | Less than or equal |

### Boolean

| Operator | Alias | Description |
|---|---|---|
| `{"and": [...]}` | `&&` | True if all are truthy |
| `{"or": [...]}` | `\|\|` | True if any is truthy |
| `{"not": expr}` | `!` | Logical negation |

### Conditional

`cond` — array of `[condition, value]` pairs evaluated in order. Optional trailing default.

```json
{
    "cond": [
        [{"gte": [{"field": "score"}, 90]}, "pass"],
        [{"gte": [{"field": "score"}, 60]}, "borderline"],
        "fail"
    ]
}
```

`if` — shorthand for a single-pair `cond`:

```json
{"if": [condition, then_expr, else_expr]}
```

`else_expr` is optional; defaults to `null`.

### Null Handling

- Any operator receiving a `null` input returns `null`, except `if` and `cond` where `null`
  is treated as falsy.
- Division by zero returns `null`.
- Type mismatches return `null`.

---

# Part 2: Functions, Methods, and Calls

This section documents a design for functions, methods, and method invocation developed
as part of Marina.

## Functions

Functions are anonymous — they have no name of their own. They can live anywhere you can
store a value: in a class field definition, in a record's bucket, anywhere.

A function is a JSON object with a `params` block and either a `calculate` expression or a
`calls` chain:

```json
{
    "params": {
        "given":  {"class": "string"},
        "family": {"class": "string"}
    },
    "calculate": {
        "concat": [{"param": "given"}, " ", {"param": "family"}]
    }
}
```

Parameters are referenced inside the body via `{"param": "name"}`.

`kiera.uno/function` is the base type for functions.

## Methods

`kiera.uno/method` is a subclass of `kiera.uno/function`. A method automatically receives
`"this"` bound to the object in its defining context.

In a class field definition, any function automatically has `"this"` bound to the instance
of that class. This means calculated fields and methods are the same underlying thing — a
`kiera.uno/method` — distinguished only by whether the body uses `"this"` and whether the
definition declares additional explicit params for callers to supply.

```json
{
    "name": "kiera.uno/color",
    "fields": {
        "hex": {"class": "string", "required": true},
        "hex_upper": {
            "calculate": {"method": "upper"}
        }
    }
}
```

Inside a method body, `{"param": "this"}` refers to the object itself. `{"param": ["this", "field"]}` navigates into a field on it.

## `kiera.uno/call`

A method invocation is a first-class object of class `kiera.uno/call`:

```json
{
    "class": "kiera.uno/call",
    "receiver": "expression evaluating to an object",
    "method":   "method name",
    "params":   {"foo": "bar"}
}
```

`class` is usually implied by context and may be omitted. `receiver` may be omitted when
calling a method on `this` — the implicit receiver in the current context.

All params are named. There are no positional arguments.

### `calls` — Method Chains

`calls` is an array of `kiera.uno/call` objects forming a pipeline. The receiver of each
step is implicitly the result of the previous step. Only the first step requires an explicit
`receiver`.

```json
{
    "calls": [
        {"method": "hex"},
        {"method": "slice", "params": {"start": 1, "end": 3}},
        {"method": "hex2dec"}
    ]
}
```

This is equivalent to nested calls where each call's receiver is the previous result.

## `{"path": expr}`

`{"path": "field"}` accesses a field on `this`. `{"path": ["field"]}` is equivalent.

If the field resolves to a method, the next element in the path array is a params hash:

```json
{"path": ["decimal", {"start": 1, "end": 3}]}
```

These two forms are equivalent:

```json
{"path": ["decimal", {"start": 1, "end": 3}]}
{"method": "decimal", "params": {"start": 1, "end": 3}}
```

## `{"return": value}`

`{"return": value}` creates a propagating signal — a special exception type — that bubbles
up through the call stack until something catches it, such as a function call boundary.
This is the mechanism for early exit from a `calls` chain or nested expression.

```json
"rgb": {"return": [{"path": "red"}, {"path": "green"}, {"path": "blue"}]}
```

## Lazy Method Dispatch

Method calls are evaluated lazily at runtime (duck typing). The interpreter does not
require a compile-time definition of what methods exist on what types. If the receiver has
the named method, it is called. If not, the result is a `kiera.uno/error` that propagates
up through the expression chain.

## Example: `kiera.uno/color`

```json
{
    "name": "kiera.uno/color",
    "fields": {
        "hex": {"class": "string", "required": true},

        "decimal": {
            "params": {"start": {"class": "number"}, "end": {"class": "number"}},
            "calls": [
                {"method": "hex"},
                {"method": "slice", "params": {"start": {"param": "start"}, "end": {"param": "end"}}},
                {"method": "hex2dec"}
            ]
        },

        "red":   {"path": ["decimal", {"start": 1, "end": 3}]},
        "green": {"path": ["decimal", {"start": 3, "end": 5}]},
        "blue":  {"path": ["decimal", {"start": 5, "end": 7}]},

        "rgb": {"return": [{"path": "red"}, {"path": "green"}, {"path": "blue"}]}
    }
}
```

---

# Part 3: Q0 Expression Language

This is the expression language for `mikobase.com/q0`, which inherits `kiera.uno/query`.

## `mikobase.com/q0` Operators

These operators are specific to the Mikobase record model and reference data from the
current record being evaluated.

### Bucket Fields

`{"field": "key"}` returns the value of a top-level field in the record's `bucket`.

`{"field": ["key1", "key2"]}` navigates a nested path in the bucket.

```json
{"field": "birth_date"}
{"field": ["name", "family"]}
```

If the field or path does not exist, the result is `null`.

### Record Metadata

`{"record": "..."}` returns metadata about the current record.

| Value | Description |
|---|---|
| `{"record": "pk"}` | The record's primary key |
| `{"record": "updated_at"}` | The timestamp of the record's latest version |
| `{"record": "class"}` | The record's class name (UNS string) |

---

## Calculated Fields in Class Definitions

A calculated field is declared in a class definition using `"calculate"` instead of
`"class"`. Calculated fields are read-only — they are never stored in `bucket`.

```json
{
    "name": "foo.com/character",
    "record_class": true,
    "fields": {
        "birth_date": {"class": "string"},
        "age": {
            "calculate": {
                "years": {
                    "duration": [{"field": "birth_date"}, {"now": true}]
                }
            }
        },
        "full_name": {
            "calculate": {
                "concat": [
                    {"field": ["name", "given"]},
                    " ",
                    {"field": ["name", "family"]}
                ]
            }
        }
    }
}
```

The following two forms are identical:

```json
{
    "age": {
        "calculate": {
            "years": {"duration": [{"field": "birth_date"}, {"now": true}]}
        }
    }
}
```

```json
{
    "age": {
        "class": "mikobase.com/calculated",
        "calculate": {
            "years": {"duration": [{"field": "birth_date"}, {"now": true}]}
        }
    }
}
```

`"class": "mikobase.com/calculated"` is optional. When present, it must not conflict with
the `"calculate"` key.

Calculated fields appear in the record dict alongside regular bucket fields, in definition
order. They are computed fresh on each read and are never stored in `bucket`.

A subclass may define additional calculated fields. A subclass may not override a
calculated field defined by a parent class.

---

## Foreign Query Fields

A foreign query field returns all active records of another class that reference this
record. It is declared using `"foreign"` and optionally `"field"`. The explicit class name
`"class": "mikobase.com/lookup"` may also be included.

### Explicit field

```json
"appearances": {"foreign": "borg.com/appearance", "field": "person"}
```

- `foreign` — the UNS class name to query
- `field` — the field in the foreign class whose value must match this record's pk

### Join inference

If the foreign class has a `join` clause, `field` may be omitted. The engine inspects the
join fields and finds the one whose `allowed_class` matches the class being defined.

```json
"appearances": {"foreign": "borg.com/appearance"}
```

`field` is required if the foreign class has no `join` clause or if more than one join
field matches (ambiguous).

### General rules

Foreign query fields are read-only, never stored, and lazily evaluated.

---

# Part 4: Q0 Advanced Features

## Placeholders

Placeholders allow query templates to be reused with minimal changes. They are defined at
the top level of a query (or inside a `then` block) and referenced anywhere in the query
using `{"placeholder": "name"}`.

```json
{
    "action": "select",
    "placeholders": {
        "name": "Picard"
    },
    "path": ["name", "family", {"placeholder": "name"}]
}
```

Placeholders can themselves reference other placeholders:

```json
{
    "action": "select",
    "placeholders": {
        "name": "Picard",
        "family_match": {
            "value": {"placeholder": "name"},
            "case-sensitive": false,
            "collapse": true
        }
    },
    "path": ["name", "family", {"placeholder": "family_match"}]
}
```

### Scoping and Inheritance

Placeholders defined in an outer query are inherited by all nested `then` blocks. An inner
`then` block may define its own `placeholders` that shadow inherited ones with the same
name.

### Placeholder Validation

```python
engine.validate(query)               # shorthand
engine.validator.run_all(query)      # equivalent
engine.validator.placeholders(query) # placeholder checks only
```

### Rules

- Placeholders are resolved each time they are encountered during execution, not eagerly.
- Circular references are an error only if the circular reference is actually reached.
- Referencing an undefined placeholder is an error only if it is actually reached.
- A placeholder never reached causes no error.
- Placeholders are local to the query and not reusable across separate queries.
- A placeholder may resolve to any JSON value.

---

## `return` Clause in `select`

`return` is an optional dict evaluated for each record in the resultset. When present, the
resultset yields a new dict instead of the standard record dict.

```json
{
    "action": "select",
    "class": "foo.com/person",
    "return": {
        "full_name": {"concat": [{"field": ["name", "given"]}, " ", {"field": ["name", "family"]}]},
        "age":       {"years": {"duration": [{"field": "birth_date"}, {"now": true}]}}
    }
}
```

`return` always produces a dict. Standard record fields are not included unless explicitly
added via `{"record": "pk"}` etc.

`return` is applied after filtering and sorting. `order_by` sorts by bucket fields before
`return` transforms the output.

```json
{
    "action": "select",
    "class": "foo.com/person",
    "return": {
        "pk":   {"record": "pk"},
        "name": {"concat": [{"field": ["name", "given"]}, " ", {"field": ["name", "family"]}]}
    }
}
```
