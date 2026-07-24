# Artifact-centric programming

~~~vibecode
{"vibecode": {
	"doc": "idea_artifact_centric_programming",
	"role": "report on the 'artifact-centric programming' paradigm — a name for the design stance Caspian seems to embody, contrasted with the dominant type-centric OOP tradition. Surveys what the term means, which Caspian features fall out of it as natural consequences, where the paradigm sits relative to other systems (Smalltalk, Self, Lisp, filesystems), and where the framing has limits.",
	"status": "active brainstorming — the term is the author's analytical lens, not an established label of art",
	"audience": "Caspian designers and reviewers thinking about whether a proposed feature is on-paradigm",
	"related": ["../requirements/classes/instance.md (where this paradigm is referenced as the underlying stance behind the `instance` keyword)"]
}}
~~~

This report lays out what "artifact-centric programming" means — a label for the design stance Caspian appears to embody — and walks through why I think the language fits it. The term isn't a standard label of art; I'm using it as the cleanest name I've found for a pattern that runs through many of Caspian's choices but doesn't have a widely-recognized handle.

## What "artifact-centric" means

An **artifact-centric** language is one whose fundamental unit of organization is **the artifact** — a concrete thing that exists at a specific place — rather than **the type**, an abstract category that other things conform to.

In an artifact-centric system:

- An artifact is a real thing in a real location. It can be inspected, moved, replaced, copied, passed around.
- Identity comes from **where the artifact is stored**, not from any intrinsic "what kind of thing am I" property.
- Types still exist, but they're a kind of artifact too — one specific artifact among others — not a separate vocabulary the system is built on.
- Composition happens by **putting artifacts in places**, not by declaring categories and populating them.

In a type-centric system (the OOP mainstream), it works the other way:

- The architecture IS the type vocabulary. Types come first; you design with them, name them, organize them into hierarchies.
- An object's identity comes from its type membership — "an instance of `HashMap`," "a subclass of `Animal`."
- Types live in a separate space from values. The type-space is the gatekeeper of what objects can exist.
- Composition happens by **declaring categories and populating them**.

The two stances aren't strictly incompatible — most languages mix them in some proportion — but a language's tilt determines what feels natural to write and what feels like fighting the language.

## Where I got the term

A disclosure up front: "artifact-centric programming" isn't a term you'll find in the OOP literature. Closely related concepts have names — Smalltalk's "everything is an object," Self's "prototypes over classes," Lisp's "code is data" — but no single existing label captures the whole stance well enough for what Caspian seems to be doing.

I picked "artifact" as the head noun because it carries the right connotations:

- **Concrete.** An artifact is a real thing that exists at a real place. Not an abstraction, not an instance of something.
- **Inspectable.** You can look at an artifact, copy it, move it, replace it. It has a location and a content.
- **Made.** Artifacts are produced and placed. They don't pre-exist in some Platonic type-space.

Using a less-loaded word than "object" matters too. In OOP, "object" is heavily entangled with "instance of a class" — every object IS an instance of some class. Calling Caspian's primary unit an "artifact" sidesteps that baggage: an artifact is what it is regardless of what type-conformance story you tell about it.

## How Caspian fits

A cluster of Caspian's design choices look unrelated until you see them as expressions of the same underlying stance. Each is on-paradigm for artifact-centric, off-paradigm for type-centric.

### Identity is per-artifact, not via type

A class fetched from `puck.uno/color` and a class fetched from `myorg.com/color` aren't "the same type in two places." They're two separate artifacts. Each is whatever class it happens to be; neither resolves to a shared abstract `Color` type that the runtime knows about.

~~~caspian
$puck_color  = %puck['https://puck.uno/color']
$myorg_color = %puck['https://myorg.com/color']

# Two separate artifacts. Per-object identity; no global "Color" they both
# resolve to.
$puck_color == $myorg_color   # false

# An instance from one isn't "an instance of Color" abstractly — it's an
# instance of one specific class artifact.
$red = $puck_color.new(...)
$red.object.classes.includes?($myorg_color)   # false
~~~

The artifacts themselves don't know or care where they came from. The URLs above are how the *caller* found them; once fetched, each artifact is just an object in memory, identical in kind to one constructed inline or pulled from a Mikobase record. Identity is per-object, not derived from origin.

In a type-centric language, identity comes from type membership: `java.util.HashMap` is `HashMap`, and any two artifacts claiming that name are "the same type." Caspian has no such cross-artifact identity story. Each artifact is its own thing; equality is per-object unless a class explicitly overrides it.

### Classes don't carry their own names

A Caspian class definition is just `class ... end`. There's no concept of it having a specific name.

~~~caspian
# A whole class definition. Nothing in the body identifies the class itself.
$counter = class
	field :value, default: 0

	method increment()
		@value = @value + 1
	end

	method reset()
		@value = 0
	end
end

# The class is reachable through $counter. It has no "official" name.
# If it's later published at a URL, that URL becomes its name from the
# outside; until then, it's just whatever variable holds it.
$c = $counter.new()
$c.increment
$c.value   # 1
~~~

The class's name (if it has one) comes from the URL where the artifact is published, or from the variable holding it. Names are for locations, not abstractions.

A type-centric language would put the name on the class — `class HashMap { ... }`. The name is intrinsic. Moving the class to a different package keeps the name; the type-identity travels with the type.

Caspian's version is that artifacts don't inherently have names. You refer to an object by where it's stored... in a variable, a hash, a database record or a URL.

### Functions are values

A Caspian function isn't "a method of a class." It's a value you hold in a variable, pass to other functions, store in a record. It has the same status as any other artifact.

~~~caspian
# A function. Held at $greet.
$greet = function($name)
	'Hello, ' + $name
end

# Called via the & sigil applied to the variable name:
&greet 'World'   # 'Hello, World'

# Can be stored in a hash like any other value:
$registry = {greeter: $greet, parser: $some_parser}

# Passed to another function as an argument:
$names.each($greet)
~~~

This is barely surprising in 2026 — most modern languages have first-class functions to some degree. But in Caspian the framing is stronger: a function isn't "a special kind of value that mostly behaves like other values." It's literally an artifact in the same sense classes are. Stored at a place, named by the place, indistinguishable in fundamental kind from any other artifact.

### Ad-hoc instances need no type

The [`instance` keyword](../requirements/classes/instance) builds an object without declaring a class. The object exists as an artifact in its own right. No type vocabulary needs to admit it; nothing about the engine treats it specially.

~~~caspian
$config = instance
	field :host, default: 'localhost'
	field :port, default: 8080

	method dsn
		'tcp://' + @host + ':' + @port
	end
end

# $config is an object. There was no class declaration; the engine doesn't
# care. It's an artifact; that's the whole story.
$config.dsn   # tcp://localhost:8080
~~~

This is the most visible expression of the paradigm. In a type-centric language, "an object that isn't an instance of any declared type" is a contradiction in terms. In Caspian, it's the routine case — just one of the normal ways to put an object in place.

### Method dispatch walks classes the object carries

When you call `$foo.bar()`, Caspian walks the stack of classes `$foo` happens to carry, looking for a `bar` method. It does NOT consult a tree of types that `$foo` belongs to. The object's identity, for dispatch purposes, is what's *on* it, not what category it's been classified *into*.

~~~caspian
$ship = %['starfleet.com/ship'].new(name: 'Enterprise')

# Attach an additional class — adds auditing behavior to this one ship.
$ship.object.classes.add('logging.uno/audit')

# Now $ship carries two classes. Method calls walk both:
$ship.fire_torpedo   # resolved on starfleet.com/ship
$ship.audit_log      # resolved on logging.uno/audit

# The object's identity is what it carries, not what type it "is".
$ship.object.classes   # ['starfleet.com/ship', 'logging.uno/audit']
~~~

A type-centric language asks "what type is this?" then looks up the method in that type's vtable. Caspian asks "what classes does this artifact carry?" then walks them. The framing is artifact-first, type-second.

### Methods can be added to any specific object

`method $foo.name(params) ... end` adds a method directly to that one object. Not to its class. Not to a category of similar things. To this one artifact.

~~~caspian
$alice = %['starfleet.com/officer'].new(name: 'Alice')

# Attach a method to just this one officer.
method $alice.salute()
	'Captain ' + @name + ' reporting!'
end

$alice.salute   # 'Captain Alice reporting!'

# Other officers don't get the method — it's on the artifact, not the class.
$bob = %['starfleet.com/officer'].new(name: 'Bob')
$bob.salute   # raises method_missing
~~~

A type-centric language treats this as exotic (Ruby's singleton methods, Python's monkey-patching) — something you can do but that's against the grain. In Caspian it's just adding behavior to an artifact. Same shape as adding behavior to a class, because both are artifacts with shadow classes.

### `%puck` resolves URLs to artifacts, not types to instances

`%puck['https://example.com/thing']` fetches the artifact at that URL. The result is whatever the artifact happens to be — a class, a function, a Mikobase record, a config blob. The lookup mechanism doesn't ask "what type is this?" before returning; it just returns the artifact.

~~~caspian
# Fetching a class artifact:
$color = %puck['https://puck.uno/color']
$red   = $color.new(r: 255, g: 0, b: 0)

# Fetching a function artifact:
$validate = %puck['https://utils.org/email_validator']
&validate 'foo@bar.com'

# Fetching a data artifact (a Mikobase record, say):
$config = %puck['https://example.com/site_config']
$config.theme

# The lookup is the same regardless of what's there. The caller deals
# with what they get.
~~~

A type-centric module system would have you `import Thing from 'example.com'` and the result would be a typed Thing reference. Caspian's `%puck` is artifact-typed — you get whatever is there.

## What the paradigm encourages in practice

When a developer internalizes the artifact-centric stance, code organization shifts:

- **Compose artifacts to do the work**, rather than designing a type hierarchy and then populating it. The question stops being "what classes do I need?" and becomes "what artifacts do I need to put in place to make this work?"
- **Local craft over global architecture.** An ad-hoc instance is the right tool when an artifact is needed for a specific job — not because "every object needs a class." Classes still exist, but they exist when there's a reusable shape worth naming.
- **Cheap composition without scaffolding.** Combining behavior doesn't require designing a type hierarchy first. You attach pieces — classes, methods, fields — to the artifact that's going to use them. The artifact is the assembly point.

## Closest analogs in other systems

The paradigm isn't unprecedented — it inherits from several traditions, just without combining them this way before:

- **Smalltalk** — everything is an object, including classes. Caspian goes further: even the type system is artifacts. In Smalltalk, classes are objects but they're also clearly typed (`Class` is the type of classes). In Caspian, classes are just artifacts; there's no `Class` type sitting above them.
- **Self** — prototype-based OO with no required classes. Caspian shares the no-mandatory-class stance and adds the storage-as-identity twist. Self objects are anchored in memory, not in URLs; Caspian's anchoring story is more spatial.
- **Lisp** — code and data have the same form. Caspian's analog is "artifacts and types have the same form." Both undermine a separation that other languages treat as fundamental.
- **Filesystems generally** — files exist at paths, can be moved, can be inspected, are values. Caspian objects feel close to this. A class at a URL is to a file at a path as an instance is to a file's content; reading the file is reading the artifact.
- **Erlang/Elixir** (partial) — modules are addressable by name; processes are concrete actors with identities. Less aggressive about it than Caspian, but the artifact-as-real-thing flavor is there.

What's distinctive about Caspian's position is the combination: prototype-flexibility + spatial-storage-as-identity + the type system collapsed into the artifact system. None of the precedents have all three at once.

## Implications for evaluating new features

The paradigm gives reviewers a question to ask when a proposed Caspian feature lands on the table:

> Does this treat objects as artifacts, or as instances of types?

Features that lean artifact-centric tend to be **aligned**:

- More ways to use objects without committing to a type up front.
- More mechanisms for composing artifacts rather than declaring categories.
- More emphasis on storage as part of design (URLs, scopes, places).
- Per-artifact customization (singleton methods, shadow classes, instance-level behavior).

Features that pull type-centric tend to be **off-paradigm and worth questioning**:

- Mandatory type declarations.
- Intrinsic class names baked into class bodies.
- A type-space that lives separately from the value-space.
- "You can't do that with this object — it's the wrong type" enforcement that isn't backed by a real safety concern.

This isn't a hard rule. There are cases where a type-centric mechanism earns its place (compile-time checking of well-defined schemas, for instance). But the default presumption — when no specific case is being made — is artifact-centric.

## Where the framing has limits

A few places the paradigm doesn't carry as cleanly:

- **Type validation at boundaries.** When data flows in from outside (HTTP requests, file imports, untrusted input), you usually want to check it conforms to expectations. That's a fundamentally type-centric concern. Caspian handles it through field constraints and class checks, which are themselves artifacts — but the conceptual work is "does this match this schema," which is a type question.
- **Performance optimization.** Compilers love stable type information. Aggressively artifact-centric semantics make optimization harder. Caspian leans on inline caching and on-demand specialization to recover some of what static type info gives you, but there's a real cost.
- **Static analysis and tooling.** Type-centric languages have rich tooling because the types ARE the structure. Artifact-centric languages have to recover that structure dynamically; tooling can do it but takes more work.
- **Reasoning about "what kind of thing is this."** Sometimes you legitimately want to ask "is this a Color?" The artifact-centric answer is "look at what it carries" — but if "Color" is published at multiple URLs (vendored copies, forks, derived variants), there's no single answer. The paradigm makes you confront the ambiguity that type-centric systems paper over.

These aren't fatal — every paradigm has rough edges — but they're places where saying "we're artifact-centric" doesn't resolve the design question on its own.

## Status of the term

I want to be explicit that "artifact-centric programming" is a label I'm coining as I think about Caspian, not a term with established literature behind it. Whether it's the right name, or whether someone else has already named this stance better, are both open. The substance — Caspian's tilt toward artifacts-as-fundamental and away from types-as-fundamental — is what matters; the label can change if a better one surfaces.
