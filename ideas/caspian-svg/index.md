# Caspian-SVG

~~~vibecode
{"vibecode": {
	"doc": "ideas_caspian_svg",
	"role": "brainstorm on programming Caspian with an SVG app — a visual layer over Caspian, whether that's an authoring surface (draw boxes and arrows, get Caspian source), a live inspector (render running program state as an SVG canvas), a diagram library (Caspian stdlib that emits SVG), or some combination. Idea-stage; no commitments yet.",
	"status": "brainstorm — exploring what shape 'Caspian-SVG' could take"
}}
~~~

The prompt is one sentence: what if there were an SVG-first way of working with Caspian programs? The current answer is nothing — Caspian is text, its tools are text, and SVGs (like the [bootstrap diagrams](https://www.puck.uno/requirements/bootstrap/)) are hand-authored XML that isn't linked to any code.

But it's a fun direction. This page collects the flavors "Caspian-SVG" could take, presented as candidates rather than a settled shape.

## The library flavor

**A Caspian stdlib for building SVG diagrams.** The direct riff on the diagrams we've been hand-writing. Instead of authoring `<rect>` and `<line>` tags, you write:

~~~caspian
$diagram = %svg.diagram.new width: 500, height: 580

$diagram.add_step 'Open the DB', color: 'orange',
    subtitle: 'sqlite.open; foreign_keys pragma on.'

$diagram.add_step 'Install infrastructure', color: 'teal',
    subtitle: 'Creates tables, triggers, indexes, view; seeds the user row.'

# ...more steps...

$diagram.write 'init-process.svg'
~~~

The box-arrow grammar is stable enough (rounded rects, left-edge accent bars, arrow markers, legend) that it could be a well-defined subset. Diagram source becomes a Caspian file; adding a step is one line, not a viewBox recalculation and five y-coordinate shifts.

**Trade-off.** Locks the visual grammar. The current hand-authored SVGs have varied intentionally — dashed borders for "deferred," pill badges for "current work." A library would need to grow features for each variant, or accept that non-standard diagrams drop back to raw SVG.

## The authoring flavor

**A canvas app where you draw boxes and arrows, and Caspian source drops out.** The Scratch / Blockly / Node-RED direction. Boxes are statements or expressions; arrows are dependencies or control flow. Save produces `.casp` files.

Interesting because Caspian is already a block-shaped language — `class`, `function`, `if`, `while` blocks all have visual counterparts. `%foo.bar 'baz'` reads as a message to a box; `$x = ...` reads as a value flowing into a slot.

**Trade-off.** Visual programming environments usually stall at "expressive but tedious for real code." Great for the first 30 minutes, painful for the next 3 hours. The exit ramp (drop back to text without losing anything) is what determines whether it's fun-toy or actually-useful.

## The live-inspector flavor

**An SVG canvas that renders a running Caspian program's state.** MVM tables materialized as boxes; call stack as a strip; object graph as connected nodes; roles as a tree. As the program runs, boxes update. As you step through, arrows highlight.

Doesn't ask you to author anything visually — the SVG is a debugger surface, not a source of truth. Caspian source stays text; the SVG just shows what's happening at runtime.

**Trade-off.** Building a good debugger UI is a bigger lift than either of the above. It's also where SVG earns its keep — zoom, scroll, animation, cross-element links, printable output all come for free.

## The diagram-as-doc flavor

**Caspian source annotated with `svg:` blocks that render to embedded diagrams.** Like `mermaid` in markdown, but native to Caspian. A doc file with `~~~caspian-svg ... ~~~` fences renders as an SVG in place; source and image stay in sync because the source IS the image.

Overlaps with the library flavor — mostly a question of syntax and whether the diagrams stand alone or live inside prose.

## Cross-cutting design questions

Some questions apply across every flavor above; a coherent "Caspian-SVG" needs answers to at least these:

- **Grammar authority.** Who owns the visual grammar (box shape, arrow style, color palette)? A stdlib decision, a user-configurable theme, per-diagram overrides, or all three?
- **Reactivity.** Do diagrams re-render on Caspian value changes (spreadsheet-style), or are they output artifacts (print-statement-style)?
- **Bidirectionality.** Does the authoring flavor round-trip cleanly — edit the SVG, get equivalent Caspian back? Or is the SVG throwaway and Caspian is authoritative?
- **Rendering target.** SVG in a browser? SVG in a native window? SVG as file? Some combination?
- **Overlap with existing tools.** How much of this is "Caspian version of PlantUML / Mermaid / d2 / Excalidraw" vs a genuinely new axis?

## Where this connects

- The bootstrap diagrams ([overview](https://www.puck.uno/requirements/bootstrap/), [initialize-vm](https://www.puck.uno/requirements/bootstrap/initialize-vm/)) are the immediate motivator — they show the exact pattern the library flavor would automate.
- The MVM's structured runtime state (objects, frames, locals, relationships, uspace) is what the live-inspector flavor would visualize. That data is already there in MVM's schema; the question is only how to render it.
