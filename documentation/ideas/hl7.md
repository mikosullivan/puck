# HL7 null flavors

~~~vibecode
{"vibecode": {
	"doc": "hl7_null_flavors",
	"role": "research report on how HL7 (specifically HL7 v3, CDA, and FHIR) uses null flavors — the origin, the standard flavor codes, whether multiple flavors can apply to one value, and whether a value can be associated with a flavor. Written to inform Caspian's null-flavor design.",
	"status": "research report",
	"audience": "language designers working on Caspian's null-flavor spec"
}}
~~~

This report answers four specific questions about HL7's null-flavor mechanism so the Caspian null-flavor design can decide where to follow, extend, or diverge.

## What HL7 null flavors are

### Origin and layering

The concept originated in **HL7 Version 3 (v3)** as part of the Abstract Data Types specification, first balloted in the early 2000s (v3 Data Types Release 1 was normative in 2005; Release 2 was published in 2010). HL7 v3 built the entire messaging framework on a Reference Information Model (RIM) whose root abstract data type, `ANY`, carries a single attribute called `nullFlavor` typed as `CS` (Coded Simple, a single non-hierarchical code drawn from a fixed value set).

Because `ANY` is the root of the type lattice, **every** HL7 v3 data type — booleans, integers, strings, timestamps, coded values, physical quantities, complex acts — inherits the `nullFlavor` attribute. HL7 designers describe this as making v3 a system of "partial data types": any attribute may return a proper value OR a null flavor, and consumers must handle both.

Three downstream specifications inherit the mechanism:

- **HL7 v3 messaging** (the original bearer). `nullFlavor` appears as an XML attribute on any element whose type descends from `ANY`.
- **CDA and Consolidated CDA (C-CDA)**. The Clinical Document Architecture uses the same code system on the same attribute, with additional template-level guidance about when `nullFlavor` is allowed.
- **FHIR** (Fast Healthcare Interoperability Resources). FHIR **renames and re-scopes** the concept as the **`dataAbsentReason` extension**, a first-class extension that any element can carry. FHIR's code set is a redesign of v3's — overlapping in intent but not code-for-code identical (see the "Standard flavor codes" section below).

The canonical HL7 v3 code system lives at `http://terminology.hl7.org/CodeSystem/v3-NullFlavor`. FHIR's replacement lives at `http://terminology.hl7.org/CodeSystem/data-absent-reason`. HL7 publishes bidirectional concept maps between the two for use when converting CDA documents to FHIR resources.

### Wire-format example: v3 / CDA

In HL7 v3 messaging and CDA, the flavor is an XML attribute. On a simple typed element:

~~~xml
<!-- Value known -->
<value xsi:type="PQ" value="98.6" unit="[degF]"/>

<!-- Value not known -->
<value xsi:type="PQ" nullFlavor="UNK"/>

<!-- Coded value falls outside required code system -->
<code nullFlavor="OTH">
	<originalText>frostbitten toe, second phalanx</originalText>
</code>
~~~

The attribute lives on the same element that would carry a proper value, and its presence signals that the reader must not expect a normal value in the usual slots.

### Wire-format example: FHIR

In FHIR the same idea takes the form of an extension. On a primitive element, FHIR JSON uses a sibling `_field` object:

~~~json
{
	"resourceType": "Observation",
	"status": "final",
	"_valueQuantity": {
		"extension": [{
			"url": "http://hl7.org/fhir/StructureDefinition/data-absent-reason",
			"valueCode": "asked-declined"
		}]
	}
}
~~~

On a complex element, the extension appears inline:

~~~json
{
	"valueQuantity": {
		"unit": "mg/dL",
		"extension": [{
			"url": "http://hl7.org/fhir/StructureDefinition/data-absent-reason",
			"valueCode": "unknown"
		}]
	}
}
~~~

And some resources — `Observation`, `Questionnaire.item.answer` — promote the concept to a first-class field named `dataAbsentReason` bound to the FHIR value set, so no extension URL is needed at all.

### What kinds of nullness HL7 recognizes

HL7's design carves the space of "missing" into three broad regions:

- **True absence** — no proper value exists for this element, either because none is applicable (`NA`) or because none is known (`UNK`, `ASKU`, `NASK`, `NAV`, `NAVU`).
- **Withheld or unencodable value** — a proper value exists but cannot be transmitted as-typed, either for privacy (`MSK`), because the value falls outside the constrained code system (`OTH`), because it wasn't yet coded (`UNC`), or because it must be derived (`DER`).
- **Boundary and error conditions** — negative and positive infinity (`NINF`, `PINF`), invalid content (`INV`), trace amounts (`TRC`), sufficient-quantity placeholders (`QS`).

The root of the hierarchy is `NI` ("no information") — the default when nothing more specific applies. All other flavors are Is-A descendants of `NI`, so any receiver that understands only `NI` still gets a correct (if less informative) reading.

## Standard flavor codes

### HL7 v3 NullFlavor hierarchy

The v3 code system organizes flavors as a strict Is-A tree rooted at `NI`. A receiver may safely climb toward the root and treat a specific code as its ancestor when it doesn't understand the specific one. The hierarchy from the HL7 Terminology publication (THO v6.5.0 and later):

~~~
NI  no information (root)
├─ INV  invalid
│	├─ DER  derived
│	├─ OTH  other (value outside the permitted domain)
│	│	├─ NINF  negative infinity
│	│	└─ PINF  positive infinity
│	└─ UNC  un-encoded
├─ MSK  masked (withheld for privacy or security)
├─ NA   not applicable
└─ UNK  unknown (proper value exists but is not known)
	├─ ASKU  asked but unknown
	│	└─ NAV  temporarily unavailable
	├─ NASK  not asked
	├─ NAVU  not available
	├─ QS    sufficient quantity
	└─ TRC   trace
~~~

Plain-language descriptions:

- `NI` — **No information.** The default. "Something is missing but I have nothing more to say about why."
- `INV` — **Invalid.** Content is present but does not conform to the constrained value domain.
- `DER` — **Derived.** The value is not stored; it must be computed from other information in the message.
- `OTH` — **Other.** A value exists but is not a member of the permitted code set. Typically paired with an `originalText` giving the free-text term.
- `NINF` / `PINF` — **Negative / positive infinity.** Numeric boundary values that cannot be encoded as a finite number.
- `UNC` — **Un-encoded.** A value exists but has not yet been mapped to the required code system.
- `MSK` — **Masked.** A proper value exists and is known, but is withheld for security, privacy, or policy reasons.
- `NA` — **Not applicable.** No proper value can exist. Canonical example: "last menstrual period" on a male patient.
- `UNK` — **Unknown.** A proper value applies but is not known by the sender.
- `ASKU` — **Asked but unknown.** The sender asked the source and the source did not know.
- `NAV` — **Temporarily unavailable.** Asked, not known now, expected later.
- `NASK` — **Not asked.** The sender didn't ask; the workflow didn't call for gathering this value.
- `NAVU` — **Not available.** Information is not accessible from the sender's current position, without commitment to when (or whether) it might become available.
- `QS` — **Sufficient quantity.** In pharmacy dosing, the "make up the bulk" placeholder (Latin: *quantum satis*).
- `TRC` — **Trace.** Greater than zero, too small to quantify.
- `NP` — **Not present.** Retired; formerly used to mean the value is not present in the message. Deprecated because it duplicates the meaning of simply omitting the element.

### FHIR data-absent-reason codes

FHIR redesigned the code set for `dataAbsentReason`. The result is smaller, uses lowercase hyphenated tokens (matching FHIR's naming style), and drops some v3 codes (`NI`, `INV`, `DER`, `UNC`, `NAVU`, `QS`, `TRC`, `NP`) while adding new ones for concerns that v3 did not model (`unsupported`, `as-text`, `not-performed`, `not-permitted`).

~~~
unknown              value expected but not known
├─ asked-unknown     source was asked, does not know
├─ temp-unknown      may become known via workflow
├─ not-asked         workflow did not gather this
└─ asked-declined    source was asked and declined
masked               withheld for security or privacy
not-applicable       no proper value can exist here
unsupported          source system could not represent this element
as-text              value is captured only in narrative, not structured
error                system or workflow error prevented capture
├─ not-a-number      IEEE NaN result
├─ negative-infinity value too low to represent
└─ positive-infinity value too high to represent
not-performed        the procedure that would supply the value was not done
not-permitted        the value is not permitted here (profile constraint)
~~~

Notable design differences from v3:

- **No `NI` root.** FHIR treats "no reason given" as simply omitting the extension; the code system doesn't need a placeholder for that case.
- **`asked-declined` is new.** v3 has no distinct code for "source refused to answer." Implementations typically packed this under `ASKU`.
- **`unsupported`, `as-text`, `not-performed`, `not-permitted` are new.** These name real-world reasons systems failed to supply data — receiver-side capability gaps, narrative-only capture, uncompleted procedures, and profile-driven suppression — that v3 had no clean home for.
- **The `error` subtree replaces v3's `INV` / `OTH` region for numeric errors.** `not-a-number`, `negative-infinity`, and `positive-infinity` sit under `error` in FHIR but under `INV.OTH` (or as a sibling of `OTH`) in v3.

### Bidirectional concept maps

HL7 publishes `ConceptMap-FC-DataAbsentReasonNullFlavor` (FHIR to C-CDA) and `ConceptMap-CF-NullFlavorDataAbsentReason` (C-CDA to FHIR) in the C-CDA-on-FHIR Implementation Guide. The maps are near-1:1 for the common codes:

- `unknown` ↔ `UNK`
- `asked-unknown` ↔ `ASKU`
- `temp-unknown` ↔ `NAV`
- `not-asked` ↔ `NASK`
- `masked` ↔ `MSK`
- `not-applicable` ↔ `NA`

And degrade gracefully for the rest — FHIR-only codes (`asked-declined`, `unsupported`, `as-text`, `not-performed`, `not-permitted`) map to `NI` when going to C-CDA (losing specificity); v3-only codes (`DER`, `INV`, `UNC`, `TRC`, `QS`, `NAVU`) map to `unknown` when going to FHIR.

### Side-by-side comparison

The two vocabularies overlap in intent but not exactly in scope. A rough alignment:

~~~
concept                   v3 code    FHIR code
─────────────────────────────────────────────────────
no reason given           NI         (omit extension)
not applicable            NA         not-applicable
unknown                   UNK        unknown
asked, source didn't know ASKU       asked-unknown
temporarily unavailable   NAV        temp-unknown
not asked                 NASK       not-asked
declined to answer        (ASKU)     asked-declined
masked / withheld         MSK        masked
outside code system       OTH        (usually text field)
negative infinity         NINF       negative-infinity
positive infinity         PINF       positive-infinity
invalid                   INV        (no direct code)
derived / computed        DER        (no direct code)
un-encoded                UNC        (no direct code)
trace                     TRC        (no direct code)
sufficient quantity       QS         (no direct code)
not available (period)    NAVU       (no direct code)
system can't represent    (no code)  unsupported
narrative only            (no code)  as-text
procedure not done        (no code)  not-performed
constraint disallows      (no code)  not-permitted
NaN                       (via OTH)  not-a-number
~~~

Parentheses mark cases where the vocabulary doesn't have a direct equivalent — the mapping either falls back on the root (`NI` / `unknown`) or requires a different modeling pattern (a companion text field, a separate status field, etc.).

## Multiple flavors per value?

**Short answer: no.** In every HL7 layer, a null flavor is a single code, not a set.

### HL7 v3 and C-CDA

The `nullFlavor` XML attribute is typed `CS` — the abstract "Coded Simple" data type, which by definition carries exactly one code from a single fixed code system, with no translations, qualifiers, or coexisting alternate codings. It is not a `CD` (Coded with Details) and not a `LIST<CS>`. There is no XML-schema-level way to write two null flavors on one element.

The Is-A hierarchy is the standard's answer to "what if two apply?" — pick the most specific ancestor that both share. Concretely:

- If a value is both "unknown" AND the sender was asked, use `ASKU` (which specializes `UNK`).
- If a value is both "unknown" AND expected later, use `NAV` (which specializes `ASKU`, which specializes `UNK`).
- If a value is both "not applicable" AND "masked" — this genuinely can't be expressed. The sender must pick one. Guidance in circulation prefers `MSK` here because it protects information disclosure (using `NA` would signal the value is truly absent, which if incorrect would be a false negative).

There is no combinator rule (no additive tags, no comma-separated lists, no bitmask). The hierarchy IS the combination mechanism — climbing toward the root loses precision but is always semantically safe. Two orthogonal flavors that can't fold into one ancestor are a design gap the spec doesn't resolve.

### FHIR

The `dataAbsentReason` extension carries a **`CodeableConcept`** — which structurally *could* hold multiple `coding` alternatives — but the FHIR guidance treats it as a single reason, and the value set binding is Extensible on a single code. In practice, implementations use one code. FHIR does not endorse using multiple `coding` entries as "the field has flavor A AND flavor B" — that would violate the CodeableConcept contract (multiple `coding` are meant to be alternative encodings of the same concept, not conjunctions of concepts).

Nothing in the FHIR spec forbids putting two coded values into the CodeableConcept, but doing so as a conjunction of independent flavors is a bespoke local convention with no standardized reader semantics.

### Where the "multiple reasons" question actually arises

The scenarios where callers would want to say "this value is both A and B" have been debated on HL7 mailing lists over the years. Representative cases:

- **Not applicable AND masked.** A field ("last menstrual period") that could be `NA` for a male patient — but in a system that also has trans patients on file and treats sex-at-birth as protected, the sender might want to signal both "structurally absent" and "we're not going to elaborate." HL7 forces a pick. Common guidance is that `MSK` is safer because `NA` positively asserts structural absence, which may be false.
- **Asked but declined, temporarily unavailable.** In v3 both fold into `ASKU`; the sender loses the distinction between "declined" and "not-known-right-now." FHIR added `asked-declined` specifically to close this gap — but even in FHIR, a value that is both temporarily unavailable AND was declined at the point in time it was asked has to pick one code.
- **Invalid AND unknown.** A sender receives garbage from an upstream source; is the value `INV` (the content is invalid) or `UNK` (we can't derive a proper value from what we got)? Both are true. HL7 forces one.

None of these have first-class resolution in HL7. The design pattern the spec endorses is: pick the most operationally relevant code and use narrative or annotation fields to convey secondary reasons out-of-band.

### Practical implication for Caspian

Caspian's design decision here is unencumbered by HL7 precedent: HL7 provides a hierarchy, not a set. If Caspian wants multiple orthogonal flavors on one value, that is a genuine extension beyond HL7 rather than a re-adoption of an HL7 pattern.

## Value alongside a null flavor?

**Short answer: it depends on the layer.** FHIR forbids it categorically for primitives. HL7 v3 and CDA forbid it in principle for simple elements but permit specific patterns for complex elements. The rules are subtle and are one of the most-argued areas of the spec.

### FHIR: strict either/or on primitives

FHIR R4 defines a constraint on the extension itself (constraint `ext-1`):

~~~
Must have either extensions or value[x], not both
~~~

For a **primitive** element (an FHIR string, integer, code, boolean, dateTime, etc.), that constraint means what it says: the element either carries a value or carries a `dataAbsentReason` extension. Not both.

The mechanism FHIR uses is that primitive elements are represented as two parallel JSON properties: `foo` for the value and `_foo` for its extensions. So a primitive `Observation.valueQuantity.value = 12.3` in a form where the number is known, versus:

~~~json
{
	"_valueQuantity": {
		"extension": [{
			"url": "http://hl7.org/fhir/StructureDefinition/data-absent-reason",
			"valueCode": "unknown"
		}]
	}
}
~~~

when it is not. The constraint `ext-1` prevents both being present.

For a **complex** element (a BackboneElement, a Quantity, a CodeableConcept, a nested resource), the picture changes. A complex element can itself carry a `dataAbsentReason` while individual child elements carry values. In FHIR's `Observation` resource, for example:

- `Observation.valueQuantity` may be omitted with a top-level `Observation.dataAbsentReason` explaining why the whole observation has no value.
- Or `Observation.valueQuantity.value` may be omitted with a `dataAbsentReason` on that specific field, while `Observation.valueQuantity.unit` carries a real value.

So FHIR's rule generalizes to: at each element level, the value slot and the data-absent-reason are mutually exclusive, but child elements are treated independently.

### HL7 v3 and CDA: mostly either/or, with named exceptions

The rule in v3's Abstract Data Types is that `nullFlavor` applies when the element has no proper value. If the element has a value, `nullFlavor` should not appear.

CDA's C-CDA General Guidance restates this and then documents the **exception patterns** that are actually used in practice:

- **`nullFlavor="OTH"` with `originalText`.** This is the canonical partial-information case: the coded value cannot be given because the concept is outside the required code system, but the free-text term IS given. The element looks like:

	~~~xml
	<code nullFlavor="OTH">
		<originalText>knuckle scraping</originalText>
	</code>
	~~~

	Here the `nullFlavor` says "no value from the constrained code system," and the `originalText` child carries the human-readable term. This is universally accepted.

- **`nullFlavor` on a parent, values on children.** A parent complex element (a `<time>`, an `<addr>`, a `<name>`) may carry `nullFlavor` while some children carry values. Rules for whether children's values are respected in that state depend on the template.

- **Partial dates.** `TS` (timestamp) in v3 lets a sender give as much precision as they know (`19790615` — year, month, day, nothing more). The convention here is precision truncation, NOT a `nullFlavor` on the "unknown time-of-day" portion. Some templates layer `nullFlavor="UNK"` on a `<time>` with `<low>` given and `<high>` absent, which effectively communicates "we know when it started, not when it ended."

- **Coded with translations.** A `CD` element may carry `nullFlavor="OTH"` on the outer wrapper while carrying `<translation>` codes from non-required systems. This is a documented mixed-mode pattern for "we can't code it in the required system, here are codes from other systems."

The IHE HL7 V3 Data Types Implementation Notes flag this as a real ambiguity: XML Schema validation alone cannot enforce "no `nullFlavor` when a value is present," because a schema will accept `<code code="foo" nullFlavor="OTH"/>` as structurally valid even though semantically incoherent. Enforcement lives in Schematron or template-level validators, and different implementations disagree on which mixes are acceptable.

### Concrete field-level rules

A working summary of the rules receivers actually apply:

- If `nullFlavor` is present on a primitive-typed element and the primitive's value is also present, the value **should be ignored** and the element treated as null with the given flavor. Some validators reject the message entirely.
- If `nullFlavor` is present on a complex-typed element and a child element carries a value, the child value **is respected** at the child's level, but the parent as a whole is still considered exceptional. This is the `OTH` + `originalText` pattern generalized.
- If `nullFlavor="OTH"` is present with `originalText`, the free-text is the authoritative representation.
- If `nullFlavor` is present with an unrelated attribute like `representation`, the extra attribute is nonsense and should be ignored (but nothing prevents it structurally).

Concretely, the four canonical shapes a CDA `<value>` element can take:

~~~xml
<!-- 1. Value present, no flavor -->
<value xsi:type="CD" code="386661006" codeSystem="2.16.840.1.113883.6.96"
	displayName="Fever"/>

<!-- 2. No value, plain flavor -->
<value xsi:type="CD" nullFlavor="UNK"/>

<!-- 3. Structured flavor with companion text (the OTH + originalText case) -->
<value xsi:type="CD" nullFlavor="OTH">
	<originalText>persistent low-grade chills, not febrile</originalText>
</value>

<!-- 4. Coded value with translations, none in the required system -->
<value xsi:type="CD" nullFlavor="OTH">
	<originalText>frostbitten toe</originalText>
	<translation code="T33.831A" codeSystem="2.16.840.1.113883.6.90"/>
</value>
~~~

Shape 1 is the ordinary "value known" case. Shape 2 is the ordinary "value absent" case. Shapes 3 and 4 are the mixed-mode patterns — the outer element is flagged as exceptional, but child elements carry usable information. Note that in shape 4, the `<translation>` is NOT a "value" in the required code system — it is an alternate coding in a different system, and the required-system slot remains genuinely null.

### FHIR "estimated" is NOT a null flavor

An important distinction: neither HL7 v3 nor FHIR uses null-flavor mechanisms to say "this value IS 42, and its flavor is estimated." That kind of value-plus-qualifier is modeled elsewhere:

- HL7 v3 uses **update-mode** and **uncertainty** attributes on specific data types (e.g., `PPD<PQ>` — a physical quantity with a probability distribution).
- FHIR uses domain-specific fields on the resource (e.g., `Observation.method`, `Observation.status = "preliminary"`).

Null flavors in HL7 are specifically for the *absence* of a value, not for annotating a present value's provenance or confidence. If Caspian wants both — a flavor tag on a null AND a flavor tag on a present value — the second is a distinct feature that HL7 does not provide via this mechanism.

### The partial-date exception (or the closest thing to one)

The one case that looks like "value + flavor coexisting" but really is not: HL7 v3's `TS` (timestamp) type. A sender may transmit `19790615` — year, month, day, no time-of-day. This is not modeled as "value = date + flavor = time-unknown"; it is modeled as **precision truncation**, where the receiver reads the value at the precision the sender supplied. No `nullFlavor` is involved.

FHIR follows the same convention with its `dateTime` and `instant` primitives — a partial date is a legitimate value at a coarser precision, not a value-plus-null-flavor.

This matters for Caspian's design because "the sender knows Y but not X" scenarios are structurally common, and HL7 does NOT reach for null flavors to model them. The pattern HL7 uses is: **make the value type itself precision-aware**. If Caspian wants to model partial knowledge inside a value (a date with unknown day, a number with uncertainty), HL7's precedent is to solve that in the type, not in the null-flavor mechanism.

## Other notes

### Extensibility

- **HL7 v3 / CDA.** The NullFlavor code system is **fixed**. Implementations are not free to add local flavors — the value set is not extensible. If a new reason for absence emerges, it goes through HL7 balloting.
- **FHIR.** The `dataAbsentReason` binding is **Extensible**, meaning implementers MAY use codes outside the value set if no listed code fits. In practice, additions are rare — the value set is comprehensive enough that virtually all real-world reasons already have a code. The Extensible binding is more about future-proofing than active extension.

### Where the codes actually appear in the wire format

- HL7 v3 messages: the `nullFlavor` XML attribute on any element whose type descends from `ANY`.
- CDA / C-CDA documents: same as v3 — the `nullFlavor` attribute.
- FHIR JSON: the `data-absent-reason` extension inside `extension` (for complex elements) or inside `_field` (for primitives).
- FHIR XML: the `data-absent-reason` extension as a nested `<extension url="..." />` element.
- FHIR CodeableConcept fields specifically (like `Observation.dataAbsentReason`): a first-class field on the resource, bound to the value set. Not an extension, a real field. Some FHIR resources promote `dataAbsentReason` to a top-level field because absence is a first-class concern for that resource.

### Common misuse patterns

- **Using `NI` when a more specific code is available.** `NI` is the fall-through. Senders that always use `NI` because it's easiest lose the information the hierarchy was designed to preserve.
- **Using `NA` for "we didn't ask."** `NA` means the value cannot exist for structural reasons (male patient, menstrual period). Confusing this with `NASK` produces false negatives — a receiver may prune a patient from a cohort because a field is marked truly-absent when the sender only meant "didn't ask."
- **Coexisting `nullFlavor` and value on primitives.** Structurally valid in v3 schemas, semantically undefined, and different validators disagree on what to do.
- **Using `dataAbsentReason` on a CodeableConcept that has a `text` child.** Some implementations pack the "we don't have a code but here's the term" pattern into `dataAbsentReason = "unknown"` plus `text = "..."`; others rely on the CodeableConcept's own `text` field with no code. FHIR guidance prefers the second pattern.
- **Bundling multiple reasons.** Neither v3 nor FHIR supports this cleanly. Implementations that try to do it invent local conventions with no interoperable meaning.

### Criticism and known limitations

- **Three-valued Boolean logic.** Because `nullFlavor` applies to every type including `BL` (boolean), HL7 v3 booleans are effectively three-valued: true, false, and null-with-flavor. Software written against v3 must treat every boolean as potentially nullable. Critics — including the openEHR community and CEN — have argued this makes v3 unsafe for downstream logic that assumes classical two-valued booleans.
- **Ubiquity forces null-awareness everywhere.** In HL7 v3, every field of every message may carry a null flavor. Consumer code cannot assume any field is definitely present, even fields marked mandatory. This is a documented complexity cost.
- **The hierarchy models "how unknown" but not "why the sender chose the code."** Two senders describing the same underlying situation may legitimately pick different codes (`ASKU` vs `NAV` vs `NASK`), and receivers have limited ability to normalize.
- **FHIR's redesign didn't fully retire v3.** The two vocabularies coexist in the ecosystem — CDA documents still use v3 codes, FHIR resources use the FHIR codes, and any system that bridges the two needs a concept map. The mapping is lossy in both directions.
- **No standardized reason-for-mask.** `MSK` is the same code whether the reason is legal (Part 2 substance-use records), organizational (VIP handling), or patient-directed (opt-out). Systems that need to reason about the *reason for masking* have to add out-of-band metadata.
- **`OTH` with `originalText` is a "structured escape hatch" that swallows a lot.** Any concept the sender can't code lands here, so `OTH` values accumulate free text that becomes hard to normalize downstream.

### Design takeaways for Caspian

Reading HL7's design as prior art rather than as a target to copy, the informative points are:

- **A hierarchy makes lossy degradation safe.** A receiver that only understands `NI` still gets a correct reading of every more-specific code. This is worth preserving.
- **Single-code-per-value is a real constraint HL7 chose deliberately.** Nothing about HL7 supports "multiple flavors at once." If Caspian goes there, it is a genuine extension.
- **Value + flavor is not what HL7 means by null flavor.** HL7 null flavors are strictly for absence. A "42 but estimated" pattern would be a distinct Caspian feature, not a null-flavor use.
- **`OTH` + `originalText` is the one place HL7 does allow content alongside a flavor** — and it's specifically for complex types where the flavor names "why we can't code this" and the child element carries the free-text representation. This is a mild precedent for Caspian allowing an absent-value-with-companion-information pattern, though HL7 uses it exclusively for the "outside code system" case.
- **Extensibility is a live question.** Fixed (v3) vs Extensible (FHIR) is a real design axis, and the answer depends on whether Caspian wants central curation of the meaning of null-flavor codes or wants library authors to introduce their own.

## Sources

Primary HL7 specifications:

- HL7 v3 NullFlavor CodeSystem (HL7 Terminology THO v6.5.0): <https://terminology.hl7.org/6.5.0/CodeSystem-v3-NullFlavor.html>
- HL7 v3 NullFlavor CodeSystem (latest, THO v7.0.1): <https://terminology.hl7.org/7.0.1/CodeSystem-v3-NullFlavor.html>
- HL7 v3 Data Types Abstract Specification (mirror): <https://vico.org/HL7_RIM/infrastructure/datatypes_r2/datatypes_r2.html>
- HL7 V3 Datatypes Implementation Notes (IHE Wiki): <https://wiki.ihe.net/index.php/HL7_V3_Datatypes_Implementation_Notes>

CDA and C-CDA:

- C-CDA General Guidance (build): <https://build.fhir.org/ig/HL7/CDA-ccda/generalguidance.html>
- CDANullFlavor ValueSet (CDA core structure definitions): <https://build.fhir.org/ig/HL7/CDA-core-sd/ValueSet-CDANullFlavor.html>
- HL7 CDA Core Principles (ART-DECOR docs): <https://docs.art-decor.org/introduction/cda/>

FHIR:

- FHIR R4 Extension: Data Absent Reason: <https://www.hl7.org/fhir/R4/extension-data-absent-reason.html>
- FHIR R4 CodeSystem: data-absent-reason: <https://hl7.org/fhir/R4/codesystem-data-absent-reason.html>
- FHIR ValueSet: data-absent-reason (current build): <https://build.fhir.org/valueset-data-absent-reason.html>
- FHIR Extensions IG (v5.0.0) — Data Absent Reason: <https://www.hl7.org/fhir/extensions/StructureDefinition-data-absent-reason.html>

Cross-standard mappings:

- ConceptMap: FHIR Data Absent Reason → C-CDA NullFlavor: <https://www.hl7.org/fhir/us/ccda/ConceptMap-FC-DataAbsentReasonNullFlavor.html>
- ConceptMap: C-CDA NullFlavor → FHIR Data Absent Reason: <https://build.fhir.org/ig/HL7/ccda-on-fhir/ConceptMap-CF-NullFlavorDataAbsentReason.html>

DICOM's adoption of HL7 null flavors:

- DICOM PS3.20 section 5.3.2 Null Flavor: <https://dicom.nema.org/MEDICAL/Dicom/current/output/chtml/part20/sect_5.3.2.html>

Secondary sources and commentary:

- HL7 Watch, "Flavors of Null" (Grahame Grieve, 2008), summarizing the codes and quoting openEHR-side criticism: <http://hl7-watch.blogspot.com/2008/10/flavors-of-null.html>
- CDA Best Practices (Trifolia Workbench): <https://trifolia.lantanagroup.com/Help/CDABestPractices.html>
- "Adding HL7 version 3 data types to PostgreSQL" (Suzuki et al., 2010) — describes v3 as a system of partial data types: <https://arxiv.org/pdf/1003.3370>
