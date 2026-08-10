# Flowchart symbols

~~~vibecode
{"vibecode": {
	"doc": "ideas_caspian_gui_prior_art_flowchart_symbols",
	"role": "reference for the standard flowchart-symbol grammar — rhombus for decision, oval for start/end, parallelogram for I/O, cylinder for data storage, etc. Predates the visual-programming environments; codified in ISO 5807:1985 (formerly ANSI Y15.3-1979). Included here so caspian-gui design conversations can reach for the standard shapes when they fit.",
	"status": "brainstorm reference"
}}
~~~

Before Scratch, before Node-RED, before any of the visual programming environments in this prior-art tree, there was the flowchart — a vocabulary of geometric shapes standardized by ISO 5807:1985 (which superseded ANSI Y15.3-1979). Most software people have run into these shapes in a textbook or on a whiteboard. Fewer have the whole set on hand as a reference.

![Nine standard flowchart shapes: terminator (oval), process (rectangle), decision (rhombus), input/output (parallelogram), data storage (cylinder), predefined process (rectangle with double vertical lines), on-page connector (circle), off-page connector (home-plate pentagon), flow direction (arrow).](./symbols.svg)

## The vocabulary

- **Terminator (oval / rounded rectangle)** — Start or End of the flow. Every flowchart has one Start and at least one End.
- **Process (rectangle)** — A step of work: assignment, computation, or any action that doesn't fit a more specialized shape. The workhorse of the vocabulary.
- **Decision (rhombus / diamond)** — A branch point. One arrow in, two or more arrows out, each labeled with the condition that takes it. Almost always used for yes/no; sometimes for multi-way switches.
- **Input / Output (parallelogram)** — Data entering or leaving the system. Read a file, print to console, receive a network message.
- **Data storage (cylinder)** — A database or persistent store. Distinct from I/O because the flowchart cares about what data lives *there*, not just that data moves.
- **Predefined process (rectangle with double vertical lines)** — Call to a subroutine or externally-defined process. Signals "the details are elsewhere; treat this as one step."
- **On-page connector (circle)** — Jump within the same page. Labeled with a letter or number that matches its landing point.
- **Off-page connector (home-plate pentagon)** — Jump to another page. Same labeling convention.
- **Flow direction (arrow)** — The line between shapes, with a head showing direction. Down / right for the default reading order; up / left when the flow returns.

## Extended shapes (not drawn above)

The standard also defines many less-used shapes: manual input (trapezoid pointing up), manual operation (trapezoid pointing down), display (curved-side rectangle), document (rectangle with wavy bottom edge), merge (downward triangle), extract (upward triangle), delay (D-shape), preparation (elongated hexagon), and a handful more. The nine above cover the vast majority of practical use.

## Why this matters for Caspian-GUI

Any visual-programming environment that draws boxes and arrows is either reusing this vocabulary, refusing it, or unaware of it. Reusing means an experienced flowchart reader can pick up the tool faster. Refusing means the tool has its own visual grammar (Scratch's colored puzzle-piece blocks, Node-RED's rounded rectangles with connector dots) that has to be learned from scratch. The Caspian-GUI conversation can pick either direction, but should pick deliberately.

The bootstrap-diagram SVGs we hand-authored ([boot-process](https://www.puck.uno/requirements/bootstrap/), [init-process](https://www.puck.uno/requirements/bootstrap/initialize-vm/)) use only two shapes so far: the process rectangle and the flow arrow. When decisions arrive (fresh vs existing DB, first-time vs revival) we'll want the rhombus.
