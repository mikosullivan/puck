# Unreal Blueprints

~~~vibecode
{"vibecode": {
	"doc": "ideas_caspian_gui_prior_art_unreal_blueprints",
	"role": "prior-art notes on Unreal Blueprints — Epic Games' visual scripting system built into Unreal Engine; node-graph editor where designers script game logic without writing C++.",
	"status": "brainstorm reference"
}}
~~~

![Screenshot of the Unreal Engine Blueprint editor, showing a graph of rectangular nodes with named input/output pins wired together — white execution wires running left-to-right through event and function nodes, colored data wires threading between typed pins.](./screenshot.png)

Unreal Blueprints is the visual scripting language embedded in Epic Games' Unreal Engine (shipped in Unreal Engine 4 in 2014 and carried forward into UE5). It's how designers, artists, and technical directors write gameplay logic without dropping down to C++. A Blueprint is a class — new actor, component, or UI widget — whose behavior is defined by graphs of connected nodes inside the editor.

The visual model is a node graph, not a block-stack. Each node is a rectangle with a title bar and two banks of pins: inputs on the left, outputs on the right. Nodes represent events (`BeginPlay`, `Tick`, input actions), function calls (any C++ or Blueprint-declared function), variable get/set, control flow (`Branch`, `Sequence`, `ForEachLoop`, `Gate`), and math. Wires are drawn between pins by dragging. The graph reads left-to-right in the direction execution flows.

The most distinctive UX choice is the **separation of execution and data flow into two visually distinct wire systems.** White triangular execution pins carry the "when does this run" signal — one execution wire enters a node, one or more leave, and following the white wires traces the program's control flow like an animated sequence diagram. Round data pins carry values, and their wires are **color-coded by type**: red for booleans, blue for integers, green for floats, pink for strings, yellow for vectors, teal for objects, and so on. A designer glancing at a graph sees the shape of the control flow in white and the shape of the data flow in a rainbow at the same time. Pin shape also encodes multiplicity — a filled circle is a single value, a grid icon is an array, a jigsaw icon is a map or set.

For Caspian-GUI, Blueprints is the reference point for professional-grade node-graph UX at scale — the largest live-fire test of "can you build a real product this way." Worth stealing: the execution/data wire split (control flow and data flow shouldn't look identical), color-and-shape type encoding on pins (redundant channels help colorblind users and speed reading either way), tight integration with an underlying compiled language (Blueprint nodes are declared in C++ with a `UFUNCTION(BlueprintCallable)` macro — the surface is extensible without editing the visual tool), and the "promote to variable" / "collapse to function" refactoring gestures that let a graph grow up without stalling. Worth being wary of: the way large Blueprint graphs devolve into an unreadable "spaghetti" once past a few dozen nodes — Unreal itself keeps adding features (reroute nodes, comment boxes, sub-graphs) to fight it.

## License

Part of Unreal Engine, which ships source-available under the [Unreal Engine End User License Agreement](https://www.unrealengine.com/en-US/eula). Free to download and use; games ship royalty-free until lifetime gross revenue exceeds US $1 million per product, after which a 5% royalty applies. Non-game commercial licensing (film, simulation, enterprise) is a separate paid license with different terms. Blueprints have no independent license — they're a feature of the engine.

## Source

- Screenshot: [File:Ue_bp.png](https://commons.wikimedia.org/wiki/File:Ue_bp.png) — Wikimedia Commons, uploaded 2025-01-06 by Kuldhi. License: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Downloaded here at the 960px thumbnail size.
- Official docs: [Blueprints Visual Scripting in Unreal Engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprints-visual-scripting-in-unreal-engine).
- Home page: [unrealengine.com](https://www.unrealengine.com/).
