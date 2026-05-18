# Idea: When Is a UNS Required?

~~~json
{"vibecode": {
	"doc": "uns-required-when",
	"role": "open-question doc: when is a UNS required, optional, forbidden, or recommended across mikobase storage, in-memory Charlie classes, Robinson page files, server classes, and built-ins; to be pinned in a future conversation",
	"key_concepts": ["uns_requirement_rules", "anonymous_class_identity",
		"mikobase_storage_requires_uns", "robinson_page_no_uns"],
	"status": "brainstorm"
}}
~~~

Not yet specified. A topic to refine in a future conversation.

<a id="the-question"></a>
## 1 The Question

Different subsystems treat UNS names differently:

- **Mikobase storage** requires a class to have a UNS — that's how classes
  are identified and looked up (`%puck['foo.com/character']`).
- **Charlie in-memory** does not require a UNS for a class.
  `$foo = class ... end` produces a valid anonymous class with no
  identity beyond the variable that holds it.
- **Robinson page files** invoke to anonymous classes inheriting from
  `puck.uno/robinson/page`. No UNS on the page class itself — the file's
  location in the tree is its identity.
- **Other places UNS shows up**: server classes
  (`puck.uno/sinatra`, `puck.uno/robinson`), built-in classes
  (`puck.uno/exception/error`, `puck.uno/reference`), reference field types
  (`allowed_class: 'foo.com/planet'`), engine-resolved capabilities
  (`%puck['puck.uno/mikobase/sqlite']`), etc.

The framework currently has a working but uncodified intuition about which
of these need a UNS and which don't. Worth pinning explicitly:

- What's the rule for when a UNS is required?
- What's the rule for when a UNS is forbidden vs. optional vs. recommended?
- What does "identity" mean for an anonymous class — only the holding
  variable? Object identity at the runtime level? Both?
- How does UNS interact with class equality, comparison, serialization,
  and reflection?

<a id="when-to-revisit"></a>
## 2 When to Revisit

When the next conversation surfaces a concrete case where the answer
isn't obvious — or when the mikobase storage format, Charlie class
syntax, or related subsystems need to be more rigorously spec'd.
