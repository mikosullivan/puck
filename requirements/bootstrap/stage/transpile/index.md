# Transpile — Caspian → CaspM

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage_transpile",
	"role": "canonical spec for the first sub-step of Stage — parsing the Caspian source string and producing the CaspM tree the engine will dispatch on. Two internal passes (transpiler.transpile → normalize.normalize) treated as one conceptual step at the spec level.",
	"status": "V1 spec — brief; both internal passes already implemented and tested."
}}
~~~

The first sub-step of [Stage](https://www.puck.uno/requirements/bootstrap/stage/). Takes the Caspian source string and produces the dispatch-ready CaspM tree.

Internally two passes:

1. `transpiler.transpile(source)` — parses Caspian, produces a CaspianJ tree. Source-fidelity: comments, cosmetic flags, bareword commands all preserved.
2. `normalize.normalize(caspj)` — collapses CaspJ into CaspM (drops comments and vibecode, resolves call shapes to the `fc` internal primitive, applies short keys). See [caspianj](https://www.puck.uno/requirements/caspianj) for the vocabulary and design principle.

The engine treats these as one step; the split into two modules is implementation detail. Callers of Stage get CaspM back either way.

Raises on parse errors (from transpile) or normalization errors (from normalize), which aborts Stage before anything is written to the CVM.
