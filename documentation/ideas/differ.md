# Differ

~~~json
{"vibecode": {
	"doc": "differ",
	"status": "brainstorm — not part of any version target",
	"purpose": "Online diff viewer that runs both sides through the viewer's Caspian formatter before diffing, so only semantic changes surface",
	"modes": ["paste two scripts", "walk a file's GitHub history"]
}}
~~~

Brainstorm for a Caspian-aware diff service.

## Why

Caspian's formatter is explicitly personal, not project policy ([formatting.md](../ecoverse/formatting/formatting.md#philosophy)). That makes ad-hoc collaboration work — but two contributors editing the same file can easily produce a diff that's 80% style noise. Differ normalizes both sides to the *viewer's* `style.json` before diffing, so the result reflects what actually changed.

It's the "run the formatter before complaining about formatting" social contract, implemented as a viewing surface instead of an editing one.

## Paste mode

Two text areas, one diff pane. User pastes two scripts, hits compare, gets a unified or side-by-side diff with both sides reformatted to their personal style first.

## GitHub mode

Point Differ at a `github.com/user/repo/blob/.../file.casp` URL and it walks the file's commit history, normalizes each version, and lets you step through clean version-to-version diffs — useful for "what actually changed in this file over the last week" without GitHub's own style-noisy blob diffs.

## Style source

Differ uses the viewer's personal style to normalize both sides before diffing. Two paths in, one policy:

- **Logged-in puck.uno user**: their puck.uno style preferences travel with their session — no upload, no per-tool configuration.
- **Anonymous user**: starts with the puck.uno canonical default, adjustable inline on the page.

### Policy: anonymous default equals canonical default

The style applied to an anonymous user must be **the exact same file** as the puck.uno canonical default — the same file a logged-in user sees when they haven't customized anything yet. The canonical default is the floor; user preferences are deltas on top.

Rationale: a logged-in user with an unconfigured profile should see identical results to an anonymous user. No surprise difference based on "did you make an account but skip the style step." First-contact and second-contact converge on the same baseline.

This makes the model boringly predictable: there is one default, used everywhere, and everything else is a delta from it.

## How it works (and why to trust it)

Differ never parses Caspian text directly. Both sides go through the canonical Caspian→CJS transpiler, then a code generator renders each side back to Caspian using the viewer's style. The diff runs on those rendered outputs.

This is the same architecture as the engine itself — the interpreter consumes CJS, never Caspian source. Extended outward, every tool that reads Caspian goes through the one parser. Formatters, linters, refactors, and Differ are all CJS-in / Caspian-out generators on top.

The trust requirement collapses to a single sharper property: **the transpiler is lossless**. Lossless here means CJS preserves everything semantically meaningful — code, comments, `%vibecode` heredocs. If the transpiler round-trips correctly (verifiable against a corpus), Differ can't silently hide a real change. A "show raw text diff" toggle is still worth offering as a sanity-check escape hatch — belt-and-suspenders, not the primary safety mechanism.

This pushes a dependency back onto CJS: comments and `%vibecode` blocks must be first-class CJS nodes. If they aren't yet, that's the spec change that has to land before any formatter or Differ work begins.

## Open questions

- Which transpiler version runs server-side? Pinned, latest stable, or viewer-selectable? (The code generator/style version matters much less — it just renders.)
- Show both sides reformatted side-by-side, or treat reformatting as a hidden normalization step and only render the diff?
- For GitHub mode: full history walker, or "between these two refs" only?
- Does it need 3-way (merge) diffing, or two-way only for V1?
- What about non-Caspian content in the file — heredoc payloads, JSON inside `%vibecode`? Skip, sub-format, or pass through unchanged?
- Does it need to handle private repos (GitHub auth), or public-only for V1?

## Out of scope (for now)

- Editing in-browser. Differ is read-only viewing of two states.
- Inline review comments. GitHub already does that; Differ is a viewing lens, not a review tool.
- Non-Caspian languages. Could extend later, but the value prop is specifically Caspian's personal-formatter model.
