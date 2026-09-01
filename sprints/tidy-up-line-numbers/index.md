~~~vibecode
{"vibecode": {
	"doc": "sprint-index",
	"sprint": "tidy-up-line-numbers",
	"role": "Sprint for cleaning up how source-line numbers sit in the CaspM. Under the current shape, `line` is a meta field scattered across atoms (e.g. `{primitive:1, line:1}`, `{var:'foo', line:3}`) — one atom carries its own line, and the outer command it lives in has no line of its own. The design goal is to promote `line` to be a property of the COMMAND (the step) rather than the atom: every dispatch step has one `line` field naming the source location where the command appears, and atoms drop their per-atom `line` fields entirely.",
	"status": "not yet started"
}}
~~~

# tidy-up-line-numbers

Sprint for making `line` a property of the command, not the atom.

## Current shape

Under today's CaspM, `line` (formerly `l` in the compact form) sits inside individual atoms:

```
{primitive: 1, line: 1}
{var: "foo", line: 3}
```

Each atom carries a `line` recording where in the source THAT atom came from. Commands that contain multiple atoms end up with line info scattered across them. The command itself has no line of its own — you have to look at its atoms to know where it sits.

## Target shape

`line` promoted to a command-level property:

```
{
    "frame": true,
    "fn": "=",
    "syn": true,
    "line": 1,
    "params": [
        {"var": "foo"},
        {"primitive": 1}
    ]
}
```

The command (dispatch step) has one `line` field. Atoms lose their `line` fields entirely.

## Rationale

- **One command, one line.** A `$foo = 1` at line 5 is a single command at a single source location; scattering line info across atoms says the wrong thing.
- **Error messages and debugger have a single place to look.** "Command X failed at line Y" reads directly off the step's `line`, not synthesized from the atoms inside.
- **Atoms get smaller.** Under the refactored atom vocabulary (`primitive` / `var` / `rv` / `frame`), the goal is atoms with exactly one atom-key. Adding a `line` field pushes them to two keys and blurs the "single-key hash" invariant.

## Design questions to answer here

- **What about atoms whose payload IS a scalar with meaningful position info?** A `{primitive: "some long string"}` that spans multiple lines — do we care about start-line vs end-line, or is one line enough for the command?
- **Multi-line commands.** A `$foo = begin ... end` with a body spread over ten lines — does the outer command's `line` point at `$foo =` (the start) or the whole span (start + end)? Current convention is that trailing sole-line metas record the `end` position for multi-line constructs; do we keep that distinction under command-level line?
- **Do closures inside params carry their own line?** The value param of `$foo = $bar.baz` might be a closure step-list. Each step in that closure is its own command with its own line; the outer step gets its own line too. That's the natural extension of "line per command."
- **Preserving line info through the normalizer.** The transpiler emits line metas from the source; the normalizer promotes them to command-level. What's the algorithm — take the FIRST line meta seen inside a command, or something else?

## Not urgent

This sprint sits alongside [caspm-method-refactor](../caspm-method-refactor/). Line placement doesn't block that sprint's core work (settling the four atoms + step shape + params-as-closures rule), and dealing with it separately keeps each sprint focused.
