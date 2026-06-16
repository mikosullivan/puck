# Bootstraps

~~~vibecode
{"vibecode": {
	"doc": "bootstraps",
	"role": "conceptual framing for the 'bootstrap object' design pattern in Caspian — a one-off object built ad-hoc for a single specific situation, without the ceremony of declaring a class. The pattern is realized in code via the `bootstrap` keyword but exists conceptually independent of any specific syntax.",
	"status": "active brainstorming — concept settled, additional patterns and use cases still being explored",
	"audience": "Caspian programmers and designers",
	"builds_on": "https://puck.uno/documentation/requirements/caspian/classes/bootstrap-build"
}}
~~~

A **bootstrap object** is a design pattern: a one-off object built from nothing for a single specific situation. The developer doesn't want the ceremony of declaring a class — naming it, picking a place to put it, signaling that it's a shape others might reuse. They just want a thing that does what's needed here, right now.

The pattern is realized in code via the [`bootstrap` keyword](https://puck.uno/documentation/requirements/caspian/classes/bootstrap-build). But the concept stands on its own — a bootstrap object is whatever results from "start with a bare object, add methods and inheritance to its shadow, use it, move on."

Bootstraps are a natural consequence of Caspian's broader [artifact-centric programming](#artifact-centric-programming) paradigm — laid out in the next section. In a language where objects are artifacts (concrete things in specific places) rather than instances of types, an object can exist without a type to admit it. Bootstraps are the syntactic convenience that makes "make an artifact directly, without first declaring a type" cheap and idiomatic.

---

<a id="artifact-centric-programming"></a>
## Artifact-centric programming

~~~vibecode
{"vibecode": {
	"section": "artifact_centric_programming",
	"role": "names the design philosophy that runs through Caspian's object model — objects are artifacts (concrete things that exist in specific places), not instances of types. Contrasts with traditional class-centric OOP and explains why several Caspian features point in the same direction: classes don't have intrinsic names, storage IS identity, functions are first-class values, and bootstrap objects can exist without a type at all.",
	"key_concepts": ["objects_are_artifacts_not_type_instances",
		"storage_is_identity",
		"classes_are_one_kind_of_artifact_not_the_foundational_one",
		"bootstraps_are_the_natural_consequence",
		"place_based_reasoning"]
}}
~~~

Caspian's object model is **artifact-centric**, not type-centric. This is a meaningful departure from the OOP tradition that Java, C#, Python, and similar languages share, and it's worth naming explicitly because several Caspian features that look unrelated are actually expressions of the same underlying choice.

**Traditional class-centric OOP.** The architecture IS the type vocabulary. Types come first; you design with them, name them, organize them into hierarchies. Objects exist as instances of types — a type is the gatekeeper of "what can exist." To create an object, you usually have to declare a type first; the type carries an intrinsic name (`java.util.HashMap`, `collections.OrderedDict`); the type-space lives separately from the value-space.

**Caspian's artifact-centric stance.** Types aren't the architecture; **storage is**. Every object is an artifact — a specific thing that exists at a specific place, that can be inspected, moved, replaced, passed around. A class is one kind of artifact (the `puck.uno/class` kind); a function is another kind; an instance built ad-hoc via [`bootstrap`](https://puck.uno/documentation/requirements/caspian/classes/bootstrap-build) is yet another. They differ in role, not in fundamental kind. There's no separate "type space" the artifacts conform to — the artifacts themselves are the whole system.

This explains why a cluster of Caspian features that look independent are actually expressions of the same choice:

- **Objects live where you store them.** The storage IS the identity. A class published at `puck.uno/color` and a class published at `myorg.com/color` aren't "the same type in two places"; they're two artifacts that happen to be similar.
- **Classes don't have intrinsic names.** A class's identity comes from the URL it's published at, or from the variable holding it — never from an internal `name` field. Names belong to artifacts, not to abstractions.
- **Functions are values.** A function isn't "a method of a class"; it's a value you hold in a variable, pass to other functions, or store in a record. Same status as any other artifact.
- **Bootstrap objects need no type.** A developer can build an object directly via `bootstrap ... end` without declaring a class. The object exists as an artifact in its own right; no type vocabulary needs to admit it.
- **Method dispatch walks the stack of classes the object happens to carry**, not a tree of types the object belongs to. The object's identity is what's on it, not what category it's been classified into.

**What the paradigm encourages.** Once a developer internalizes the artifact-centric stance, code organization shifts:

- **Compose artifacts to do the work**, rather than designing a type hierarchy and then populating it. The question stops being "what classes do I need?" and becomes "what artifacts do I need to put in place to make this work?"
- **Local craft over global architecture.** A bootstrap object is the right tool when an artifact is needed for a specific job — not because "every object needs a class." Classes still exist, but they exist when there's a reusable shape worth naming.
- **Place-based reasoning.** Where something is stored MEANS something. The URL signals scope (`puck.uno/X` is puck-ecosystem-level; `myorg.com/X` is org-specific; `$cls` is script-local). Storage becomes a first-class part of design.

**Closest analogs in other systems:**

- **Smalltalk** — everything is an object, including classes. Caspian goes further: even the type system is artifacts.
- **Self** — prototype-based OO with no required classes. Caspian shares the no-mandatory-class stance and adds storage-as-identity.
- **Lisp** — code and data have the same form. Caspian's analog is artifacts and types having the same form.
- **Filesystems generally** — files exist at paths, can be moved, can be inspected, are values. Caspian objects feel close to this.

This is a paradigm, not just a feature set. When evaluating whether a proposed Caspian feature is on-paradigm, the question to ask is: **"does this treat objects as artifacts, or as instances of types?"** Features that lean toward artifact-centric (more ways to use objects without committing to a type, more ways to compose artifacts, more emphasis on storage as identity) are aligned. Features that pull toward type-centric (mandatory type declarations, intrinsic class names, type-space separate from value-space) are off-paradigm and should be questioned.

---

## What a bootstrap object is

- **Conceptual, not technical.** "Bootstrap object" is a design-pattern label, not an engine concept. Nothing in Caspian's runtime cares whether an object was built this way; the resulting object is structurally identical to one built through any other path.
- **Starts bare, gets built up.** Conceptually, the developer instantiates "object" itself — an empty thing with no methods and no inherited classes — and then adds custom behavior to its shadow. The `bootstrap` keyword does this in one block, but the same outcome could be reached by creating a bare object and calling `.object.classes.add` and `.object.method(...)` step by step.
- **Singleton-spirited.** Like a singleton, it's one of its kind. Unlike a singleton, there's no global registry, no convention for finding it later — it lives wherever the variable holding it lives, and when that variable goes out of scope, the object goes with it.

---

## When to reach for one

The canonical case: a developer is writing a custom script for one specific situation and doesn't want the baggage of class declaration. Examples of that shape:

- **A configuration object** assembled for this run of this script. Specific values, specific methods, no need to publish it as a type.
- **A bespoke handler / actor / agent** that exists only inside one function or one script. Defines its behavior inline; nobody outside the script ever sees it.
- **A test fixture** that needs tailored behavior for one assertion. Local to the test, dies with the test.
- **A module-global "the X"** — the logger, the registry, the connection pool — when there really is only one of it and inventing a class to make one feels like overhead.

What unites these: **the object is one-of-a-kind by intent**, not a candidate-for-reuse waiting to be extracted later.

---

## When NOT to reach for one

The pattern's right when the object IS genuinely one-of-a-kind; wrong when it's secretly a class waiting to be extracted.

- **Don't bootstrap shapes used in many places.** If the same body would appear in N call sites, that's a class. Reach for `class`, give it a name, instantiate it.
- **Object factories aren't the best fit.** A factory function that produces tailored instances on demand is closer to "varied recipes from a shared base" than "one-of-a-kind objects." The bootstrap pattern can be used inside a factory, but it's not what the pattern is for. Whether factory implementations want their own syntactic treatment is an open question.

The boundary to draw: **classes are for shapes worth sharing; bootstraps are for behavior worth doing once.**

---

## Examples

Each example lives in its own file. They share the same shape: a real-world-ish situation, the bootstrap code, and a brief "why a bootstrap" rationale (versus a plain function or a declared class).

- **[Script-specific configuration](script-specific-configuration.md)** — a deploy script's config object, with values and a couple of derivation methods. Bare `bootstrap ... end` form.
- **[Custom one-shot parser](custom-one-shot-parser.md)** — a parser for a script-local markup format, using the `bootstrap(:parse, $source)` form that constructs-and-runs in one expression.
- **[Small content builder](small-content-builder.md)** — an HTML report builder with chainable `heading` / `paragraph` methods and a `render` at the end.
- **[Server-management actor](server-management-actor.md)** — a maintenance script's protagonist that manages one specific server through its lifecycle.

---

## Why Caspian fits this naturally

The deeper reason bootstraps are idiomatic in Caspian is that the language is [artifact-centric, not type-centric](#artifact-centric-programming). Objects exist as artifacts in their own right — concrete things in specific places — rather than as instances of types declared up front. A bootstrap object is just one more way to put an artifact in place, alongside class definitions, function values, Mikobase records, and worldlet entries. The pattern isn't an awkward workaround; it's the language working as designed.

Concretely, several features make the bootstrap pattern cheap and idiomatic at the syntactic level:

- **Everything is a class.** The shadow class inside an object is real and addressable; adding methods and inherited classes to it isn't a special case.
- **Classes can be modified at runtime.** Adding methods to a shadow class doesn't require a separate ceremony or workaround.
- **Singleton methods are first-class.** Caspian already provides `$foo.object.method(name) do(params) … end` for adding methods to any specific object. The `bootstrap ... end` block is just doing this in bulk at construction time instead of one method at a time later.

Other languages fight the pattern because they fight the underlying paradigm. Java requires every object to be an instance of a declared type — the artifact-first stance isn't expressible cleanly. Python supports building objects ad-hoc (`object()` then `__class__.method = ...`) but with awkward dunder mechanics that signal "you're going off the rails." In Caspian, ad-hoc object construction is on the rails — no special engine support is needed, just a syntactic convenience for doing it ergonomically.

---

## Open

This file is brainstorming territory — the things below are unsettled.

- **Factory implementations.** Whether bootstraps are the right substrate for object factories — and if so, how args get passed into the build — is undecided. The factory case is parked for now.
- **Additional patterns built on bootstraps.** This document will collect further ways the pattern gets used as they surface.
