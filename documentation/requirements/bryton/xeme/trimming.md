# Trimming

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_xeme_trimming",
	"role": "spec for the trimming operation on Xeme trees — the reduction that removes successful leaves so consumers can focus on the parts of the tree that surface failures or nulls. Owns the trimming rules, what it preserves, and the specific scenarios worth naming.",
	"status": "spec in progress — brought over from the old requirements; rules and scenarios settled; the `trimmed` field lives under Fields on the main page",
	"audience": "producers that trim before emitting; consumers that display trimmed trees; tool authors implementing the reduction"
}}
~~~

A test run that mostly passes produces a tree full of successful leaves that might just be noise. **Trimming** is a defined operation that removes successful leaves, leaving behind only the parts of the tree that surface failures (or `null` non-verdicts).

## Example

Before trimming:

~~~json
{
	"success": false,
	"nested": [
		{"success": true},
		{
			"success": false,
			"nested": [
				{"success": true},
				{"success": false}
			]
		}
	]
}
~~~

After trimming:

~~~json
{
	"success": false,
	"trimmed": true,
	"nested": [
		{
			"success": false,
			"nested": [
				{"success": false}
			]
		}
	]
}
~~~

The successful leaves are gone. The failed leaf survives, along with its ancestors.

## Rules

Applied bottom-up to a resolved xeme tree:

- **Test with `success: true`** — remove.
- **Test with `success: false`** — keep.
- **Test with `success: null`** — keep (no-verdict results are informational and worth surfacing).
- **Group** — recursively trim its children first, then:
  - If all children were trimmed away **and** the group's `success` is `true` — remove the group entirely.
  - Otherwise — keep the group. If the trimmed `nested` is empty, drop the `nested` field.

## Specific scenarios

- **Everything passed.** The whole tree trims to a single xeme `{"success": true}`. Still valid, still meaningful — "the suite ran and everything passed."
- **Group with explicit `success: false` and all-true children.** The children trim away; the group stays as `{"success": false}` with no `nested`. Still meaningful — the producer wanted to mark it failed.

## What trimming preserves

Trimming is a **reduction**, not a transformation. It doesn't change any `success` values, doesn't rewrite fields, doesn't add anything. The trimmed tree is a strict subset of the original. A producer that emits a full tree and a consumer that trims it agree on every value that's still there.

## The `trimmed` field

If a xeme has been trimmed, the **top-level xeme** carries `"trimmed": true` so consumers can tell the tree they're looking at is a reduction, not the original. Only the root xeme sets it; inner xemes don't repeat it. The only useful value is `true` — a xeme that hasn't been trimmed doesn't need the field at all.
