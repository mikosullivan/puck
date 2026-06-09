# Marina

~~~vibecode
{"vibecode": {
	"doc": "marina",
	"role": "set-aside design exploration of Puck, Q0, and class definitions; preserved for possible revisit and incorporation into the final design",
	"key_concepts": ["set_aside_exploration", "implicit_class_from_context",
		"early_puck_model", "q0_sketches"],
	"status": "set_aside"
}}
~~~

Marina is the codeword for a design exploration of Puck, Q0, and class definitions that was set aside. These ideas were developed collaboratively and may be revisited and incorporated into the final design later.

---

# Part 1: Puck

<a id="overview"></a>
## Overview

Puck is a remote object system designed to be simpler and more intuitive than systems like
REST. Classes in Puck are identified by UNS strings — a URL without the `https://`
protocol prefix — providing a globally unique namespace.

Examples:

- `puck.uno/query`
- `puck.uno/error`
- `puck.uno/exception`

Every popular language has a Puck interpreter, allowing developers in different languages
to work with the same remote objects in a consistent way.

Mikobase is designed to conform to Puck standards. The class definition format is shared
between the two systems. A class definition bucket written for Mikobase is valid in Puck.

---

<a id="implicit-class-from-context"></a>
## Implicit Class from Context

Every Puck object (hash/dict) has a `class` field, either explicit or implied by context.
When `class` is absent, the Puck interpreter determines the class from the surrounding
context — for example, the field name it appears under, the method it was returned from, or
the type declared in a class definition.

A formal mechanism for declaring and resolving implicit class rules has not yet been
defined. For now, implicit class rules are documented ad-hoc where they apply.

---

<a id="getting-a-class"></a>
## Getting a Class

`puck.get_class(uns, **params)` fetches a class definition from its UNS URL and returns a
local class object. The class definition includes fields and remote methods. Parameters may
be used to control which version of the definition is retrieved — for example, `cutoff`
pins the definition to a historical point in time.

The bracket shorthand `puck[uns]` is equivalent to `puck.get_class(uns)` with no params:

```python
clss = puck['puck.uno/color']              # shorthand
clss = puck.get_class('puck.uno/color')    # equivalent

clss = puck.get_class('puck.uno/color', cutoff='2026-09-21')  # with params
```

<a id="creating-an-object"></a>
## Creating an Object

`clss.new(**fields)` creates a new instance of the class with the given field values. The
resulting object behaves like any local object — fields are accessible as properties and
methods are callable normally.

```python
clss = puck['puck.uno/color']
color = clss.new(hex='#ff0000')
```

`puck.create(uns, **fields)` is a shorthand that fetches the latest class definition and
creates an instance in one step:

```python
color = puck.create('puck.uno/color', hex='#ff0000')
```

This is equivalent to `puck[uns].new(**fields)`.

---

<a id="method-calls"></a>
## Method Calls

When a method is called on a Puck object, the **entire object** is serialized and sent to
the method's URL. A response is received and returned to the caller.

The class definition specifies each method's required and optional parameters, and what to
expect in the response.

<a id="request-structure"></a>
## Request Structure

A Puck request is a JSON object with the following fields:

```json
{
    "class": "puck.uno/request",
    "method": "puck.uno/color/hex",

    "object": {
        "rgb": [122, 93, 81]
    },

    "params": {}
}
```

- `class` — identifies the request type. Usually redundant since the receiving URL implies
  it.
- `method` — the method being called. Usually redundant since the URL implies it.
- `object` — the full field values of the Puck object being sent. The class of the object
  is implicit in the request context and is not repeated inside `object`.
- `params` — method-specific arguments, separate from the object's own field values.

When `class` or `method` conflict with what the URL implies, the server may set policies.
Specific rules:

- If `method` differs from what the URL implies but is an alias for that method, the
  request is processed without error.
- If `method` refers to a method that does not exist, the server returns an error object.
- If `class` is not a request class, the server returns an error object. A subclass of
  `puck.uno/request` is acceptable, but the server must already know it is a subclass —
  the server is not required to query the UNS to verify the inheritance relationship.

The response structure is not yet defined.

---

<a id="value-objects-and-stored-objects"></a>
## Value Objects and Stored Objects

All Puck objects are the same type — they carry their field values with every method call.
There is no formal Stored Object class.

The terms **value object** and **stored object** are used informally as a shorthand:

- **Value object** — the object contains all its meaningful data directly in its fields.
- **Stored object** — the object's real data lives on the server; the object itself carries
  only enough to identify it (typically a `pk`). A Mikobase record is a stored object in
  this sense.

From Puck's perspective both are the same thing — a set of fields sent whole on every
method call. The distinction is a description of how a class is designed, not a type system
concept.

```python
# Value object — all data is in the object
color = puck.create('puck.uno/color', hex='#ff0000')

# Stored object — real data is on the server, object carries a pk
character = puck.create('foo.com/character', pk='92677339-df86-4f68-9397-999e40cf2c40')
```

---

<a id="puck-true"></a>
## `puck: true`

A class definition with `"puck": true` signals that remote method calls may be made using
objects of that class.

```json
{
    "name": "foo.com/bar",
    "puck": true
}
```

---

<a id="puckunoexception"></a>
## `puck.uno/exception`

The base class for all exceptions in Puck. `puck.uno/error` is a subclass of
`puck.uno/exception`. Further details of the exception hierarchy are not yet defined.

---

<a id="puckunoerror"></a>
## `puck.uno/error`

The base class for all errors. An error object is a first-class object with
`"class": "puck.uno/error"` (or a subclass).

`{"error": true}` is shorthand for `{"class": "puck.uno/error"}`. The `error` field may
be any truthy value.

```json
{"error": true}
{"class": "puck.uno/error"}
```

Error objects propagate upward through expression chains without further evaluation.

---

<a id="puckunoquery"></a>
## `puck.uno/query`

`puck.uno/query` is the base class for the Puck expression language. It defines a set of
general-purpose operators usable in any Puck context.

`mikobase.com/q0` inherits `puck.uno/query` and extends it with Mikobase-specific
operators for accessing record data.

<a id="expression-format"></a>
### Expression Format

An expression is either a **literal** (any JSON scalar or array) or an **operator object**
(a single-key JSON object whose key names the operation).

<a id="current-timestamp"></a>
### Current Timestamp

`{"now": true}` returns the current timestamp at the moment the query is executed, frozen
once at the start of execution.

<a id="arithmetic"></a>
### Arithmetic

| Operator | Description |
|---|---|
| `{"add": [a, b]}` | Addition |
| `{"subtract": [a, b]}` | Subtraction |
| `{"multiply": [a, b]}` | Multiplication |
| `{"divide": [a, b]}` | Division — returns `null` on division by zero |
| `{"mod": [a, b]}` | Modulo (remainder) |

<a id="string"></a>
### String

| Operator | Description |
|---|---|
| `{"concat": [...]}` | Concatenate two or more strings |
| `{"upper": expr}` | Uppercase |
| `{"lower": expr}` | Lowercase |
| `{"trim": expr}` | Strip leading and trailing whitespace |
| `{"length": expr}` | Character count |

<a id="array-aggregation"></a>
### Array Aggregation

| Operator | Description |
|---|---|
| `{"sum": expr}` | Sum of numeric elements |
| `{"avg": expr}` | Average of numeric elements |
| `{"min": expr}` | Minimum numeric element |
| `{"max": expr}` | Maximum numeric element |

Non-numeric elements are ignored. Empty or all-non-numeric arrays return `null`.

<a id="selection"></a>
### Selection

| Operator | Description |
|---|---|
| `{"coalesce": [...]}` | First non-null value |
| `{"first-truthy": [...]}` | First truthy value |

Returns `null` if no element meets the condition.

<a id="date-and-time"></a>
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

<a id="comparison"></a>
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

<a id="boolean"></a>
### Boolean

| Operator | Alias | Description |
|---|---|---|
| `{"and": [...]}` | `&&` | True if all are truthy |
| `{"or": [...]}` | `\|\|` | True if any is truthy |
| `{"not": expr}` | `!` | Logical negation |

<a id="conditional"></a>
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

<a id="null-handling"></a>
### Null Handling

- Any operator receiving a `null` input returns `null`, except `if` and `cond` where `null`
  is treated as falsy.
- Division by zero returns `null`.
- Type mismatches return `null`.

---

# Part 2: Functions, Methods, and Calls

This section documents a design for functions, methods, and method invocation developed
as part of Marina.

<a id="functions"></a>
## Functions

Functions are anonymous — they have no name of their own. They can live anywhere you can
store a value: in a class field definition, in a record's bucket, anywhere.

A function is a JSON object with a `params` block and either a `calculate` expression or a
`calls` chain:

```json
{
    "params": {
        "given": {"class": "string"},
        "family": {"class": "string"}
    },
    "calculate": {
        "concat": [{"param": "given"}, " ", {"param": "family"}]
    }
}
```

Parameters are referenced inside the body via `{"param": "name"}`.

`puck.uno/function` is the base type for functions.

<a id="methods"></a>
## Methods

`puck.uno/method` is a subclass of `puck.uno/function`. A method automatically receives
`"this"` bound to the object in its defining context.

In a class field definition, any function automatically has `"this"` bound to the instance
of that class. This means calculated fields and methods are the same underlying thing — a
`puck.uno/method` — distinguished only by whether the body uses `"this"` and whether the
definition declares additional explicit params for callers to supply.

```json
{
    "name": "puck.uno/color",
    "fields": {
        "hex": {"class": "string", "required": true},
        "hex_upper": {
            "calculate": {"method": "upper"}
        }
    }
}
```

Inside a method body, `{"param": "this"}` refers to the object itself. `{"param": ["this", "field"]}` navigates into a field on it.

<a id="puckunocall"></a>
## `puck.uno/call`

A method invocation is a first-class object of class `puck.uno/call`:

```json
{
    "class": "puck.uno/call",
    "receiver": "expression evaluating to an object",
    "method": "method name",
    "params": {"foo": "bar"}
}
```

`class` is usually implied by context and may be omitted. `receiver` may be omitted when
calling a method on `this` — the implicit receiver in the current context.

All params are named. There are no positional arguments.

<a id="calls-method-chains"></a>
### `calls` — Method Chains

`calls` is an array of `puck.uno/call` objects forming a pipeline. The receiver of each
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

<a id="path-expr"></a>
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

<a id="return-value"></a>
## `{"return": value}`

`{"return": value}` creates a propagating signal — a special exception type — that bubbles
up through the call stack until something catches it, such as a function call boundary.
This is the mechanism for early exit from a `calls` chain or nested expression.

```json
"rgb": {"return": [{"path": "red"}, {"path": "green"}, {"path": "blue"}]}
```

<a id="lazy-method-dispatch"></a>
## Lazy Method Dispatch

Method calls are evaluated lazily at runtime (duck typing). The interpreter does not
require a compile-time definition of what methods exist on what types. If the receiver has
the named method, it is called. If not, the result is a `puck.uno/error` that propagates
up through the expression chain.

<a id="example-puckunocolor"></a>
## Example: `puck.uno/color`

```json
{
    "name": "puck.uno/color",
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

        "red": {"path": ["decimal", {"start": 1, "end": 3}]},
        "green": {"path": ["decimal", {"start": 3, "end": 5}]},
        "blue": {"path": ["decimal", {"start": 5, "end": 7}]},

        "rgb": {"return": [{"path": "red"}, {"path": "green"}, {"path": "blue"}]}
    }
}
```

---

# Part 3: Q0 Expression Language

This is the expression language for `mikobase.com/q0`, which inherits `puck.uno/query`.

<a id="mikobasecomq0-operators"></a>
## `mikobase.com/q0` Operators

These operators are specific to the Mikobase record model and reference data from the
current record being evaluated.

<a id="bucket-fields"></a>
### Bucket Fields

`{"field": "key"}` returns the value of a top-level field in the record's `bucket`.

`{"field": ["key1", "key2"]}` navigates a nested path in the bucket.

```json
{"field": "birth_date"}
{"field": ["name", "family"]}
```

If the field or path does not exist, the result is `null`.

<a id="record-metadata"></a>
### Record Metadata

`{"record": "..."}` returns metadata about the current record.

| Value | Description |
|---|---|
| `{"record": "pk"}` | The record's primary key |
| `{"record": "updated_at"}` | The timestamp of the record's latest version |
| `{"record": "class"}` | The record's class name (UNS string) |

---

<a id="calculated-fields-in-class-definitions"></a>
## Calculated Fields in Class Definitions

A calculated field is declared in a class definition using `"calculate"` instead of
`"class"`. Calculated fields are read-only — they are never stored in `bucket`.

```json
{
    "name": "foo.com/character",
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

<a id="foreign-query-fields"></a>
## Foreign Query Fields

A foreign query field returns all active records of another class that reference this
record. It is declared using `"foreign"` and optionally `"field"`. The explicit class name
`"class": "mikobase.com/lookup"` may also be included.

<a id="explicit-field"></a>
### Explicit field

```json
"appearances": {"foreign": "borg.com/appearance", "field": "person"}
```

- `foreign` — the UNS class name to query
- `field` — the field in the foreign class whose value must match this record's pk

<a id="join-inference"></a>
### Join inference

If the foreign class has a `join` clause, `field` may be omitted. The engine inspects the
join fields and finds the one whose `allowed_class` matches the class being defined.

```json
"appearances": {"foreign": "borg.com/appearance"}
```

`field` is required if the foreign class has no `join` clause or if more than one join
field matches (ambiguous).

<a id="general-rules"></a>
### General rules

Foreign query fields are read-only, never stored, and lazily evaluated.

---

# Part 4: Q0 Advanced Features

<a id="placeholders"></a>
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

<a id="scoping-and-inheritance"></a>
### Scoping and Inheritance

Placeholders defined in an outer query are inherited by all nested `then` blocks. An inner
`then` block may define its own `placeholders` that shadow inherited ones with the same
name.

<a id="placeholder-validation"></a>
### Placeholder Validation

```python
engine.validate(query)               # shorthand
engine.validator.run_all(query)      # equivalent
engine.validator.placeholders(query) # placeholder checks only
```

<a id="rules"></a>
### Rules

- Placeholders are resolved each time they are encountered during execution, not eagerly.
- Circular references are an error only if the circular reference is actually reached.
- Referencing an undefined placeholder is an error only if it is actually reached.
- A placeholder never reached causes no error.
- Placeholders are local to the query and not reusable across separate queries.
- A placeholder may resolve to any JSON value.

---

<a id="return-clause-in-select"></a>
## `return` Clause in `select`

`return` is an optional dict evaluated for each record in the resultset. When present, the
resultset yields a new dict instead of the standard record dict.

```json
{
    "action": "select",
    "class": "foo.com/person",
    "return": {
        "full_name": {"concat": [{"field": ["name", "given"]}, " ", {"field": ["name", "family"]}]},
        "age": {"years": {"duration": [{"field": "birth_date"}, {"now": true}]}}
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
        "pk": {"record": "pk"},
        "name": {"concat": [{"field": ["name", "given"]}, " ", {"field": ["name", "family"]}]}
    }
}
```
