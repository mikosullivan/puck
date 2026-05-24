# Null

~~~json
{"vibecode": {
	"doc": "nulls",
	"role": "spec for Caspian's null model: bare-word null returns a fresh puck.uno/null instance per call; nulls carry an assignable flavor field; null/true/false are not user-overridable",
	"key_concepts": ["null_instance_per_call", "null_flavor", "no_singleton",
		"reserved_bare_words", "puck_uno_null_class"]
}}
~~~

`null` is a bare word method that returns an instance of the `puck.uno/null`
class.

<a id="too-long-didnt-read"></a>
## Too Long, Didn't Read

`null` returns a new instance of `puck.uno/null`. You do not get the same null
object every time. Every null object has a `flavor` field to which you can
assign anything.

Claude got pretty wordy in this document but it's a nice read if you're into
the finer points of null.

<a id="construction"></a>
## Construction

~~~json
{"vibecode": {
	"section": "construction",
	"creation_method": "null",
	"per_call": "fresh_instance",
	"override": "not_allowed"
}}
~~~

Each invocation of the bare word `null` allocates a fresh instance of
`puck.uno/null`. There is no singleton; `$x = null; $y = null` produces two
distinct instances.

This is the simplest implementation: every null is a real object with its own
storage. Optimizations (interning unflavored nulls, copy-on-write for flavor
assignment, etc.) are possible later but are not required by the spec.

`null` cannot be overridden by user code. The same applies to `true` and `false`.
A program that tries to redefine these names raises a runtime error.

---

<a id="equality"></a>
## Equality

~~~json
{"vibecode": {
	"section": "equality",
	"value_equality": "all_nulls_equal_regardless_of_flavor",
	"identity_equality": "distinct_instances_distinct_under_triple_equals",
	"flavor_comparison": "explicit_via_flavor_field"
}}
~~~

Equality on null is value-based: any null equals any other null under `==`, even if
their flavors differ. To compare flavors, read the `flavor` field directly.

```
$a = null
$a.flavor = :unknown

$b = null
$b.flavor = :timeout

$a == $b                     # true — both are null
$a.flavor == $b.flavor       # false — different flavors
```

Identity comparison (`===`) compares instances and so distinguishes any two distinct
nulls regardless of flavor.

To check whether a value is null at all (any flavor):

```
if $x == null
    # $x is some null
end
```

To check for a specific flavor:

```
if $x == null and $x.flavor == :timeout
    # $x is a null with flavor :timeout
end
```

---

<a id="identity-guarantees"></a>
## Identity Guarantees

~~~json
{"vibecode": {
	"section": "identity_guarantees",
	"role": "states the engine-level guarantee that null/true/false instances always answer equality and predicate checks consistent with what they were created as; the mechanism is the read-only .object.bool property",
	"key_concepts": ["once_null_always_null", "user_code_cannot_redefine_identity",
		"layering_other_classes_and_fields_remains_open",
		"mechanism_is_dot_object_dot_bool_read_only"]
}}
~~~

The engine guarantees that any value created by `null`, `true`, or `false`
**always answers equality and identity checks consistent with what it was
created as**, regardless of what user code does to it afterward.

The mechanism is a read-only property on the universal object helper: every
value has `.object.bool` set at creation, and user code cannot change it. The
derived predicates (`truthy?`, `null?`, `defined?`) read from `bool` and are
likewise engine-enforced. See [object.md](object.md) for the full set of four
methods.

User code may:

- Add other classes to the value's class array
- Assign fields (such as `flavor` on a null, or arbitrary fields)
- Define methods the value will respond to

User code may **not**:

- Change `.object.bool` (it is read-only)
- Make `$x == null` return false for an instance created by `null`
- Cause `$x.object.null?` to return false for such an instance
- Talk a null into not being null in any other way

The same applies symmetrically to `true` and `false`. The mechanism is
`.object.bool`; the contract is the four predicate methods.

---

<a id="null-flavors"></a>
## Null Flavors

Null flavors let a program distinguish *why* a value is null, not just that it is
null. The rest of this section explains the problem they solve, how the canonical
healthcare standard (HL7) handles it, and Puck's deliberately simple
implementation.

<a id="background-the-challenge"></a>
### Background: The Challenge

~~~json
{"vibecode": {
	"section": "background_the_challenge",
	"role": "explains why a single NULL is insufficient — distinguishing reasons for missing data is often the most important information at the point of consumption"
}}
~~~

In most languages and databases, "missing" is one thing. A field is `null`, a row
returns `NULL`, a function returns `nil`. That's the end of the story.

But in practice, "missing" is several things at once. Consider a patient record
where the blood pressure field is empty:

- The reading was never taken
- The reading was attempted but the device failed
- The patient refused to consent
- The value exists but is masked for privacy
- The value was redacted by a downstream system

Every one of these warrants a different downstream action. A reading that wasn't
taken should probably be taken. A patient who refused should be respected. A
not-applicable field should be skipped. A masked field signals that something
exists you can't see.

A single shared `NULL` collapses all of these into "absent," forcing every
consumer of the data to guess what the absence meant. The information that
matters most — *why* the value is missing — is the very thing that gets lost.

This is not a healthcare-only problem. It shows up everywhere data flows through
multiple systems:

- A function returning null because of a timeout vs. because of a legitimate empty
  result
- A query for a record returning null because no record matched vs. because the
  caller wasn't permitted to see it
- A configuration value being absent because the user hasn't set it vs. having
  been explicitly cleared
- An AI agent's response being null because it declined to answer vs. because it
  hasn't responded yet vs. because it errored

Wherever distinguishing absence reasons matters, a single `NULL` forces awkward
sentinel values, side-channel error codes, or out-of-band state tracking.

<a id="background-how-hl7-handles-it"></a>
### Background: How HL7 Handles It

~~~json
{"vibecode": {
	"section": "background_hl7",
	"role": "documents the canonical example of null flavors in HL7 v3 and FHIR healthcare standards",
	"key_concepts": ["formal_vocabulary", "hierarchy_of_reasons", "interop_across_systems"]
}}
~~~

HL7 (Health Level 7), the standards body for healthcare interoperability, has
developed the most-formalized treatment of this problem. Both HL7 v3 and FHIR
define a vocabulary of **null flavors** — codes that explain why a value is
absent. A receiving system can distinguish reasons without ambient knowledge.
The canonical reference is the
[HL7 v3 NullFlavor code system](https://terminology.hl7.org/en/CodeSystem-v3-NullFlavor.html).

The HL7 null-flavor vocabulary:

| Code | Meaning |
|------|---------|
| `NI` | No information (the root — nothing is known about whether a value should exist) |
| `UNK` | Unknown (a value should exist but is not known) |
| `ASKU` | Asked but unknown (we asked, the patient/source doesn't know) |
| `NASK` | Not asked (we didn't ask) |
| `NAV` | Temporarily unavailable (information is expected but not available right now) |
| `NA` | Not applicable (no proper value can apply for this case) |
| `MSK` | Masked (a value exists but has been withheld) |
| `INV` | Invalid (a value cannot be valid) |
| `OTH` | Other (a value exists but isn't in the receiver's vocabulary) |
| `TRC` | Trace (present in trace amounts) |
| `QS` | Quantity insufficient (a result couldn't be produced; not enough sample) |
| `NP` | Not present |

The vocabulary is arranged in a hierarchy. `NI` (no information) is the root;
`UNK`, `NA`, and `MSK` are children; `ASKU` and `NASK` are children of `UNK`. A
consumer can ask "is this missing for any reason that's a kind of UNK?" and get a
useful answer.

This works because every system speaking HL7 understands the same flavors. A lab
that reports `ASKU` for a missing allergy field is communicating "we asked the
patient, they didn't know" to every receiving system, and every receiving system
acts on that information appropriately.

The price of the precision is the maintenance: the HL7 vocabulary is large,
formally specified, and changes through a standards process. Adding a new flavor
requires committee approval. The vocabulary is the right design for healthcare
because the cost of getting absence wrong is high; for less safety-critical
domains, the formality is overkill.

Other systems take similar approaches at different scales:

- **SAS** has 27 distinct missing-value codes (`.A`–`.Z` plus `._`) for
  statistical analysis — researchers distinguish "missing because skipped" from
  "missing because invalid response" from "missing because not applicable."
- **R** distinguishes `NA` (statistical missing), `NaN` (not a number), and
  `NULL` (absence of object) — three nothings with different propagation rules.
- **SQL** stayed with one NULL plus three-valued logic; Codd proposed multiple
  null markers in 1979, mainstream SQL never adopted them, and SQL applications
  have been working around it ever since.

The pattern across all of these: when "missing" matters, distinguishing reasons
pays off.

<a id="pucks-approach"></a>
### Puck's Approach

~~~json
{"vibecode": {
	"section": "puck_approach",
	"role": "summarizes the deliberately-simple Puck implementation: a single flavor field that accepts anything, with a small optional canonical vocabulary",
	"key_concepts": ["one_flavor_field", "free_form_value", "canonical_set_optional"]
}}
~~~

Puck takes the simplest possible approach to the same problem.

Each null instance has a single `flavor` field that can be assigned anything —
a symbol, a string, a hash, an arbitrary object. Whatever the application
needs to express *why* this value is null.

```
$x = null
$x.flavor = :unknown                              # standard symbol flavor
$x.flavor = "insufficient funds"                  # string flavor
$x.flavor = {code: :timeout, retry_after: 30}    # structured object flavor
$x.flavor = 'puck.uno/null/flavor/masked'        # canonical UNS flavor
```

There is no formal vocabulary baked into the language. There is no hierarchy. There
is no committee. Puck ships a small canonical set of flavors under
`puck.uno/null/flavor/` for ecosystem interop, but applications are free to use any
flavor values they want.

The trade-off vs. HL7's approach is deliberate: Puck's design is lighter and more
flexible at the cost of giving up automatic cross-application semantic
consistency. Two libraries might both use the symbol `:unknown` to mean different
things, and there's no central authority that says they shouldn't. For most
applications this is fine; if interop matters in a specific domain (healthcare,
finance, etc.), that domain's conventions can be defined and adopted as community
standards on top of the Puck primitive.

<a id="the-flavor-field"></a>
### The `flavor` Field

~~~json
{"vibecode": {
	"section": "flavor_field",
	"field": "flavor",
	"type": "any",
	"default": "null"
}}
~~~

Every null instance has a `flavor` field. It defaults to `null` (an unflavored
null) and accepts any value via assignment. Reading the flavor of a default null
returns `null`:

```
$y = null
$y.flavor          # null
```

The flavor field is mutable. Assigning a new flavor replaces the previous one.

<a id="standard-flavors"></a>
### Standard Flavors

~~~json
{"vibecode": {
	"section": "standard_flavors",
	"namespace": "puck.uno/null/flavor",
	"intent": "shared_vocabulary_for_common_cases_application_specific_flavors_remain_free",
	"organization": "patterned_after_http_status_codes_with_numeric_codes_alongside_names",
	"classes": ["2xx_intentional", "3xx_redirection", "4xx_caller_reason", "5xx_provider_reason", "6xx_domain_extensions"]
}}
~~~

Canonical flavors live under the `puck.uno/null/flavor/` namespace.
They are intended for ecosystem interop — application-specific flavors
remain free-form and are not constrained to this list.

The vocabulary is **organized after HTTP status codes**. Each flavor
has both a name and a numeric code; the code follows HTTP conventions
where the concept aligns and uses novel numbers where it doesn't.
Classes by hundred:

- **2xx** — Intentional. The null is the affirmative answer.
- **3xx** — Redirection. The value lives elsewhere; the null points
  the caller somewhere else.
- **4xx** — Caller-side reason. The caller asked in a way that
  prevents an answer.
- **5xx** — Provider-side reason. The provider couldn't supply the
  answer despite a valid request.
- **6xx** — Domain extensions. Things that don't have HTTP analogs
  but are widely useful (object lifecycle, HL7-style data states,
  etc.).

| Code | UNS | Meaning |
|------|-----|---------|
| 200 | `puck.uno/null/flavor/explicit` | This null is the intended answer — null is correct here |
| 301 | `puck.uno/null/flavor/moved` | Value lives at a different UNS (target in `flavor.target`) |
| 304 | `puck.uno/null/flavor/not_modified` | No newer value than caller's last-seen |
| 400 | `puck.uno/null/flavor/bad_request` | Caller asked for something malformed |
| 401 | `puck.uno/null/flavor/unauthorized` | Auth required and not provided |
| 403 | `puck.uno/null/flavor/forbidden` | Auth provided but insufficient |
| 404 | `puck.uno/null/flavor/not_found` | No value at this address |
| 408 | `puck.uno/null/flavor/timeout` | Operation exceeded its time bound |
| 409 | `puck.uno/null/flavor/conflict` | Concurrent state prevents the answer |
| 410 | `puck.uno/null/flavor/gone` | Used to exist; was permanently removed |
| 423 | `puck.uno/null/flavor/locked` | Resource is locked by another holder |
| 429 | `puck.uno/null/flavor/rate_limited` | Too many requests in window |
| 500 | `puck.uno/null/flavor/internal_error` | Provider failed unexpectedly |
| 501 | `puck.uno/null/flavor/not_implemented` | Operation not supported by this provider |
| 502 | `puck.uno/null/flavor/bad_gateway` | Upstream provider returned an error |
| 503 | `puck.uno/null/flavor/unavailable` | Provider temporarily can't answer |
| 504 | `puck.uno/null/flavor/gateway_timeout` | Upstream provider didn't respond in time |
| 507 | `puck.uno/null/flavor/insufficient_storage` | No room to fulfill |
| 508 | `puck.uno/null/flavor/loop_detected` | Resolution cycled |
| 600 | `puck.uno/null/flavor/destroyed` | Object's `destroy` was called (lifecycle) |
| 601 | `puck.uno/null/flavor/not_applicable` | No proper value can apply (HL7 carryover) |
| 602 | `puck.uno/null/flavor/unknown` | Value exists but is not known (HL7 carryover) |
| 603 | `puck.uno/null/flavor/masked` | Value exists but is withheld (HL7 carryover) |
| 604 | `puck.uno/null/flavor/not_set` | Field was never assigned |
| 605 | `puck.uno/null/flavor/pending` | Not yet computed (lazy / async / in-flight) |
| 606 | `puck.uno/null/flavor/cancelled` | Operation was explicitly cancelled |
| 607 | `puck.uno/null/flavor/declined` | Handler chose not to process (pass-to-next pattern) |
| 608 | `puck.uno/null/flavor/disconnected` | Connection lost |

Each canonical flavor exposes its code via `flavor.code` and its class
prefix via `flavor.class`:

```
$x.flavor                # puck.uno/null/flavor/not_found
$x.flavor.code           # 404
$x.flavor.class          # '4xx'
```

A useful side effect of the HTTP-style organization: converting a
null return into an HTTP response in web frameworks (Dogberry,
Robinson, etc.) becomes mechanical — the `4xx`/`5xx` code can be
used directly as the HTTP status when the flavor maps cleanly.

The canonical set stays small relative to what's possible. Adding a
new flavor to the canonical list is a deliberate ecosystem decision;
new ones should be widely useful before being added. Application
code that needs more specific reasons uses its own flavor values
(symbols, strings, structured objects) without going through the
canonical namespace.

<a id="when-to-use-a-flavor"></a>
### When to Use a Flavor

A flavor is only useful if **callers will actually branch on it**.
The rule: *return a flavored null only when someone is expected to
need the distinction.*

A plain unflavored null says "no value here, deal with it however
you want." Adding a flavor says "no value here, AND here's why, in
case that matters to you." If no caller's logic differs based on
the *why*, the flavor is noise — it adds surface area without
informing anyone.

Don't preemptively flavor every null in the codebase. Use plain
nulls by default. Add a flavor when:

- The caller has multiple legitimate reactions depending on the
  reason (404 vs 410 vs 503, for example, each suggests different
  follow-up behavior).
- The flavor is part of a contract that crosses systems (HTTP-style
  error reporting in web APIs, HL7-style data states in healthcare,
  etc.).
- Diagnostic context will be needed at a higher layer (logging,
  monitoring, debugging across role boundaries).

Many cases don't qualify. `%puck` returning a plain null when its
chain slot is empty is an example: there's nothing for callers to
distinguish ("no puck here" is the whole story; no further branch
is implied).

<a id="flavor-propagation"></a>
### Flavor Propagation

~~~json
{"vibecode": {
	"section": "flavor_propagation",
	"rule": "operations_that_consume_null_discard_its_flavor",
	"rationale": "flavor_describes_why_this_value_is_null_does_not_extend_to_replacement_value"
}}
~~~

Operations that consume a null and produce a non-null value **discard the flavor**.
The flavor describes why a particular null was null; once that null has been
replaced by a real value, the explanation is no longer relevant to the new value.

```
$x = null
$x.flavor = :timeout

$y = $x or "default"
# $y is "default" (a fresh string from the literal source).
# The flavor :timeout does not transfer to $y.
```

If a developer needs to preserve the flavor across an `or`-style fallback, they
must do so explicitly:

```
$x = null
$x.flavor = :timeout

if $x == null
    $reason = $x.flavor
    $y = "default"
    # $reason holds :timeout for the developer to use as needed
end
```

<a id="use-cases"></a>
### Use Cases

~~~json
{"vibecode": {
	"section": "use_cases",
	"role": "shows where null flavors are most useful in the Puck ecoverse"
}}
~~~

Null flavors carry information that single-NULL systems lose. Common applications:

- **Mikobase reads.** A field returning null can carry `flavor: :not_set` vs
  `:explicitly_cleared` vs `:redacted`.
- **Q0 query results.** A query for a non-existent record returns null with
  `flavor: :not_found` vs `:filtered_out` vs `:no_permission`.
- **Function returns.** Functions return flavored null instead of throwing
  exceptions for non-fatal failures: `null` with `flavor: :timeout` or
  `:rate_limited`. Callers branch on flavor without try/catch noise.
- **AI conversation records.** An agent's response field being null with
  `flavor: :declined_to_answer` vs `:not_yet_responded` vs `:errored` carries
  distinctions downstream agents and humans care about.
- **`%chain.misc` lookups.** Distinguish "this chain value was never set" from
  "explicitly cleared" from "cleared at security boundary."

<a id="serialization"></a>
### Serialization

~~~json
{"vibecode": {
	"section": "serialization",
	"rule": "unflavored_null_serializes_as_native_null_flavored_null_serializes_as_typed_hash_via_custom_classes",
	"key_concepts": ["round_trip_preserves_flavor",
		"unflavored_uses_native_null", "flavored_uses_custom_classes_uuid_marker",
		"keeps_bucket_namespace_open"]
}}
~~~

Flavor survives serialization. A flavored null written to a Mikobase record,
a worldlet, or any other persistent form retains its flavor and reconstitutes
as a flavored null on read.

The serialization rule:

- **Unflavored null** (where `flavor == null`) serializes as the native null of
  the target format (`null` in JSON, `NULL` in SQL, etc.). Cheap, indistinguishable
  from a "plain" null.
- **Flavored null** serializes as a **typed hash inside the bucket**, with class
  identification carried out-of-band in `custom_classes`. Mikobase uses this
  pattern for any nested typed object so that the bucket's key namespace stays
  fully open to user data — no reserved key like `"class"` is needed inside the
  bucket itself.

Example (Mikobase record):

```
bucket:
    {
        "agent_response": null,
        "user_status":   {"[uuid-1]": true, "flavor": "declined_to_answer"},
        "device_reading": {"[uuid-2]": true, "flavor": "puck.uno/null/timeout"}
    }

custom_classes:
    {
        "[uuid-1]": "puck.uno/null",
        "[uuid-2]": "puck.uno/null"
    }
```

A typed object in the bucket is recognized by a UUID key (set to `true`) that
maps to a class UNS in the record's `custom_classes` table. The remaining keys
in the hash are the object's fields — for nulls, just `flavor`. On read, the
engine sees the UUID marker, looks up the UNS in `custom_classes`, and
reconstructs an instance of that class with the captured fields. Anything
expecting a null still sees a null (per the equality rules above).

This pattern is how all nested typed objects round-trip through Mikobase, not just
flavored nulls. The same approach allows arbitrary class instances to be embedded
in buckets without claiming reserved key names.

The flavor value itself must be representable in the target format. Symbol and
string flavors round-trip cleanly. Hash flavors round-trip if the hash is itself
serializable. Flavors holding live objects (functions, capabilities, etc.) cannot
survive serialization — the engine raises if asked to serialize one.

<a id="relation-to-the-role-model"></a>
### Relation to the role model

~~~json
{"vibecode": {
	"section": "relation_to_role_model",
	"role_and_flavor": "independent"
}}
~~~

A flavored null is a `puck.uno/null` instance with a populated field. It
participates in the role model like any other value (see
[roles.md](../roles.md)): the null has an owning role (from the role of
the code that created it) and a flavor. The two are independent — flavor
does not affect the owning role, and vice versa.

The owning role does not survive serialization (storage breaks the role
chain by design). Flavor does, per the rule above. The distinction is
intentional: the owning role describes *where this value came from in the
current program*, which loses meaning across a serialization boundary;
flavor describes *what the value is*, which carries through.
