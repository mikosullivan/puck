# Simulink

~~~vibecode
{"vibecode": {
	"doc": "ideas_caspian_gui_prior_art_simulink",
	"role": "prior-art notes on Simulink — MathWorks' block-diagram environment for modeling and simulating dynamic systems; the standard tool for control systems, signal processing, and model-based design.",
	"status": "brainstorm reference"
}}
~~~

![Screenshot of a Simulink block-diagram model of a car powertrain: User Inputs block feeds Brake and Throttle signals into an Engine block, a shift_logic block, and a transmission block that drives a Vehicle block; scope blocks display engine RPM and vehicle mph](./screenshot.png)

Simulink is a graphical block-diagram environment for modeling, simulating, and analyzing multi-domain dynamic systems — continuous, discrete, and hybrid. Built by MathWorks as the visual companion to MATLAB, it launched in 1990 (as "SimuLAB") and has been a fixture of control-systems, signal-processing, communications, and mechatronics work for the three-and-a-half decades since. It is the standard tool in aerospace, automotive, and industrial-controls engineering; the phrase "model-based design," as used in those industries, effectively means Simulink.

Programs are assembled by dragging blocks from a library browser onto a canvas and wiring them together with signal lines. The base library is enormous: integrators, derivatives, transfer functions, state-space blocks, summing junctions, gains, saturations, delays, look-up tables; sources (constants, step, sine, ramp, from-file, from-workspace); sinks (scope, display, to-file, to-workspace); logic and bit operations; matrix ops; discrete-time counterparts to every continuous block. On top of that base, MathWorks and third parties ship domain-specific block sets — Simscape (physical modeling: mechanical, electrical, hydraulic, thermal), Stateflow (state machines and flow charts embedded as blocks), Aerospace Blockset, Powertrain Blockset, Communications Toolbox, DSP System Toolbox, and dozens more. Signals carry typed values (scalar, vector, matrix, bus, frame) along the lines; the simulation engine turns the assembled diagram into a system of equations and solves it forward in time with a solver you pick (fixed-step, variable-step, stiff, non-stiff).

Hierarchy is done with subsystem blocks: any group of blocks can be collapsed into a single block with named input and output ports, and that subsystem can itself be reused or turned into a "referenced model" that lives in its own file. Model-referencing gives you separate compilation and namespacing at the diagram level, which is how real Simulink projects — an aircraft flight-control law, an engine-management system — scale to tens of thousands of blocks across many files. Simulink Coder generates C or C++ from a model for deployment to embedded targets (ECUs, DSPs, FPGAs via HDL Coder), which is the actual business proposition: the diagram is not just a picture, it's the source that ships to the hardware. The whole thing is tightly bound to MATLAB — variables in the MATLAB workspace parameterize blocks, MATLAB scripts drive batch simulations, and MATLAB Function blocks let you drop imperative code into a diagram when the block library doesn't have what you need.

For the Caspian-GUI direction, four things are worth studying. **Domain-specific block libraries as a scale story** — Simulink didn't try to be a universal visual language; it committed to dynamic systems, and then let vertical block sets (Simscape, Aerospace, Powertrain) grow on top. A visual environment that picks a domain and dominates it can go much deeper than one that stays general. **Code generation to a real deployment target** — the diagram compiles to C that runs on the actual ECU. That closes the loop between "picture on a screen" and "artifact that ships," which is the loop most educational block languages leave open. **Hierarchical decomposition via subsystem and model-reference blocks** — the same primitive (a block with typed input and output ports) covers both "collapse this group for readability" and "this is a separately-versioned module referenced from many parents." One mechanism, two use cases. And **tight integration with a text host** — Simulink is inseparable from MATLAB; blocks read their parameters from MATLAB variables, MATLAB Function blocks embed textual code inside the diagram, and scripts drive the simulation. A visual layer that assumes a companion text language, and lets each side do what it's better at, is a very different design point from Scratch or Blockly, which try to keep the user inside the visual world.

## License

Proprietary commercial software from [MathWorks](https://www.mathworks.com/), sold alongside MATLAB. Paid license required for commercial use; MathWorks offers reduced-price [student](https://www.mathworks.com/store) and [home](https://www.mathworks.com/store) editions. Free trial available. No source access; the block library and solver internals are closed.

## Source

- Image: [MATLAB_Simulink_Car_Throttle_and_Braking.png](https://upload.wikimedia.org/wikipedia/commons/a/a2/MATLAB_Simulink_Car_Throttle_and_Braking.png)
- Description page: [File:MATLAB Simulink Car Throttle and Braking.png on Wikimedia Commons](https://commons.wikimedia.org/wiki/File:MATLAB_Simulink_Car_Throttle_and_Braking.png)
- License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0). Simulink itself is proprietary MathWorks software; the screenshot content (the model diagram) is the uploader's own work and the block-diagram interface is used editorially. The MathWorks, MATLAB, and Simulink names and marks are trademarks of MathWorks and are excluded from CC BY-SA.
- Attribution: Uploaded 2022-08-17 by Wikimedia user MrAlanKoh as own work; original screenshot captured from Simulink (MathWorks).
