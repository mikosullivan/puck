# `%chain.frames` and `%chain.parent`

Deferred sketch. Two chain-inspection accessors that were considered for V1 and dropped:

- **`%chain.frames`** — the full call-stack sequence as an array of frames, current-first.
- **`%chain.parent`** — the frame that called this one. Shortcut for `%chain.frames[-2]`.

Under the sketch, both were **not** granted by default — chain-frame visibility is information that doesn't cross a role boundary unless the calling frame explicitly hands it across, so non-user code calling them without an explicit grant would get nothing back. Chain depth would come from `%chain.frames.length`. The intended use cases were diagnostics, debugging, and any code that needs to behave differently based on who called it — though gating behavior on call-stack inspection is usually a sign the role system should be used instead.

**Why deferred.** The current-frame's role is available as [`%role`](https://puck.uno/requirements/roles/#role), which is the only piece of chain-frame identity most code actually needs. Full frame-walking is a heavier surface with more subtle role-boundary implications; keeping it off the V1 surface avoids committing prematurely.

**If the community wants them.** Introducing either accessor post-V1 is a plain extension of `%chain` — no rework of the existing `%chain` surface required. The default-deny posture, per-frame grant model, and role-boundary reset already spec'd on `%chain` all cover them for free. The main design decision to nail down is what a "frame" object looks like from the outside: what methods it exposes, how it names its role, whether it carries argument or local-variable inspection.
