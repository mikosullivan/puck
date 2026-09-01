~~~vibecode
{"vibecode": {
	"doc": "sprint-notes",
	"sprint": "caspm-method-refactor",
	"role": "Enumerates the atom-key vocabulary for the refactored CaspM. An atom is a single-key hash carrying a value directive; the key discriminates what kind of value the atom represents (literal, lookup, marker, closure). Atoms appear in step slots (as receivers) and in arg slots (as closure-like inputs to dispatch). This is the reference list — the shape decisions the sprint has made so far. Open questions are captured at the bottom.",
	"status": "in progress"
}}
~~~

# Atom keys

An **atom** is a single-key hash. The key is the discriminator; its value is the payload the atom carries.

**Every atom resolves to an object pk when invoked.** That's the common return type; individual atoms differ in HOW they resolve — creating a fresh object, looking up a name in scope, reusing the previous rv, pointing to a singleton.

Atoms appear in three positions:

- **As a value step** — the atom is the entire step; the step sets rv to the atom's pk.
- **As a receiver on a dispatch step** — the atom sits alongside `fn:NAME`; the pk it resolves to is the receiver of the dispatch.
- **As an arg** — the atom sits inside a dispatch step's `args:[...]` list. Arg atoms are closures: the dispatched method invokes each arg to get its pk at call time.

## `primitive`
Payload: a JSON scalar literal (string, number, boolean, or nil).

Creates a fresh scalar object in the CVM and returns its pk — read the atom key as "create-and-return-pk": one step, two effects. The Lua type of the payload discriminates the scalar's class: string → String, number → Number, boolean → Boolean, nil → Null.

Example: `{primitive: 1}`, `{primitive: "foo"}`, `{primitive: true}`, `{primitive: null}`.

Hash and array payloads (`{primitive:{a:1}}`, `{primitive:["a","b"]}`) are the subject of a separate sprint: [primitive-collections](../primitive-collections/). Not in scope here.

## `var`
Payload: a variable name (string).

Names a variable in the current scope chain. In a value slot the atom resolves via scope lookup — invoking produces the value bound to that name. In a target slot (e.g. the first arg of a setvar) the atom names the variable being written.

Example: `{var: "foo"}`.

## `rv`
Payload: always `true`.

Refers to the previous step's return value. On a dispatch step's receiver, marks "use the rv as receiver" (the chain-continuation case). In an arg slot, marks "the value in the current rv."

Example: `{rv: true}`.

## `frame`
Payload: always `true`.

Refers to the current frame — the frame that owns the step being dispatched. Used as the receiver of setvar (`{frame:true, fn:"="}`) and any other method whose receiver is the executing frame.

Example: `{frame: true}`.

## Requirement

- There must be exactly one of these atom-key per atom hash. Lacking one of these keys or having multiple of them raises an exception.

## Command-hash key order (custom)

By convention, a command hash's keys are emitted in this order:

1. The atom-key (`frame`, `var`, `rv`, `primitive`) — the receiver spec, first
2. `fn`
3. `syn`
4. `args` and/or `opts`
5. Trailing fields (e.g. `line`)

**This is a formatting custom, not a semantic requirement.** Lua tables are unordered hashes; the engine reads command fields by name and doesn't care about key order. The transpiler / normalizer output CaspM in this order so hand-authored fixtures, CaspM dumps, and pretty-printed outputs all follow the same visual layout — easier to compare and diff. Skipping the order (or reordering) doesn't change what the engine does.