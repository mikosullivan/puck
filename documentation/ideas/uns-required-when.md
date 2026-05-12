# Idea: When Is a UNS Required?

Not yet specified. A topic to refine in a future conversation.

## The Question

Different subsystems treat UNS names differently:

- **Mikobase storage** requires a class to have a UNS — that's how classes
  are identified and looked up (`%kiera['foo.com/character']`).
- **KScript in-memory** does not require a UNS for a class.
  `$foo = class ... end` produces a valid anonymous class with no
  identity beyond the variable that holds it.
- **Robinson page files** invoke to anonymous classes inheriting from
  `kiera.uno/dogberry/page`. No UNS on the page class itself — the file's
  location in the tree is its identity.
- **Other places UNS shows up**: handler classes
  (`kiera.uno/dogberry/piscopo`), built-in classes
  (`kiera.uno/error`, `kiera.uno/reference`), reference field types
  (`allowed_class: 'foo.com/planet'`), engine-resolved capabilities
  (`%kiera['kiera.uno/mikobase/sqlite']`), etc.

The framework currently has a working but uncodified intuition about which
of these need a UNS and which don't. Worth pinning explicitly:

- What's the rule for when a UNS is required?
- What's the rule for when a UNS is forbidden vs. optional vs. recommended?
- What does "identity" mean for an anonymous class — only the holding
  variable? Object identity at the runtime level? Both?
- How does UNS interact with class equality, comparison, serialization,
  and reflection?

## When to Revisit

When the next conversation surfaces a concrete case where the answer
isn't obvious — or when the mikobase storage format, KScript class
syntax, or related subsystems need to be more rigorously spec'd.
