# Idea: Annotation pattern as uniform API

~~~json
{"vibecode": {
	"doc": "annotation-pattern",
	"role": "speculative note: formalize the %name(label) <<HEREDOC pattern (already used by %documentation) as a uniform mechanism for attaching labeled, format-tagged data blobs to scripts and classes; alternative to inventing a __DATA__ sub-language",
	"key_concepts": ["no_meta_language", "heredoc_as_payload",
		"uniform_introspection", "metadata_vs_runtime_payload"],
	"status": "brainstorm",
	"context": "raised 2026-05-27 after building Caspian's __END__ marker; Miko's redirect: don't invent a sub-language for embedded data, lean on the existing %documentation pattern"
}}
~~~

Caspian already has a pattern for attaching labeled blobs to a class:

```caspian
class
    %documentation('markdown') <<EOF
    = User
    Represents a user record.
    EOF
end
```

That single line is doing three things at once:

1. **Calling a system method** (`%documentation`) that registers the blob
2. **Tagging the blob with a format hint** (`'markdown'`) — the body is opaque to the runtime
3. **Carrying the body as a heredoc** — first-class string

If the pattern itself is treated as the API surface, embedded-data needs no new syntax. `%data`, `%schema`, `%example`, `%fixture` all become instances of the same shape:

```caspian
class
    %documentation('markdown') <<EOF
    = User
    EOF

    %schema('json') <<EOF
    {"type": "User", "fields": ["name", "age"]}
    EOF

    %example('user_create') <<EOF
    $u = User.new(name: 'Alice', age: 30)
    EOF
end
```

A uniform introspection API (`class.annotations`, indexed by name + label) gives tools (Sammy, Orlando, doc generators, schema validators) one mechanism to walk all blobs a class carries.

Compared to a `__DATA__` sub-language (Perl style):

- No new parse mode. A `.casp` file is Caspian top to bottom.
- No special access syntax — `%data['name']` is just a system method.
- The body is a normal heredoc; no second grammar to learn.
- Adding a new annotation kind is convention work, not language work.

## Open questions to revisit

### Metadata vs runtime payload

`%documentation` is metadata — read by tools, not by the program. `%data` would be runtime payload — read by the program itself. Same shape, different consumers. Worth distinguishing in the API, or is one namespace fine with consumer-side filtering?

### Scope

`%documentation` inside `class ... end` attaches to the class. Where does `%data` live in a top-level script with no class? Attached to the script object? Or does each annotation type declare its own target?

### Disambiguation with regular method calls

`%data(...)` looks identical to "call the system method `%data` with these args." If `%data` is also a regular system method for, say, reading runtime input, the heredoc form needs to disambiguate — either by the trailing heredoc making it a declaration, or by `%data` being the family name with the runtime branching on shape.

### `%annotation` as a single primitive?

One general-purpose `%annotation(name, label, format)` primitive with `%documentation`, `%data`, etc. as thin conventions over it? Or each annotation kind as its own system method with shared shape but no shared implementation?
