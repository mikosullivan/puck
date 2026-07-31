# Role interaction

~~~vibecode
{"vibecode": {
	"doc": "ideas_role_interaction",
	"role": "spitball page for how roles interact with each other beyond the base mechanisms already in the security model. Companion to requirements/security/model/ (the five settled rules) and ideas/run-as.md (voluntary narrowing).",
	"status": "stub — populated iteratively",
	"context": "the five-rule model plus %role.run_as and the broker/jail patterns cover a lot, but there's still surface area for role-to-role interaction that hasn't been mapped. This page collects the shapes worth exploring."
}}
~~~

## What's already in place

The five [security model rules](https://puck.uno/requirements/security/model/) already give us:

- **Structural authority** (Rule 2) — parents can manage descendants' objects; includes ownership transfer.
- **Method dispatch** (Rule 3) — code runs in the role that defined it, so cross-role calls happen naturally through Rule 4 access.
- **I/O delegation** (Rule 5) — user constructs brokers and passes them to descendants; that's the mechanism for handing controlled slices of ambient authority down the tree.

Plus companion mechanisms:

- **Brokers** — narrowing wrappers user builds around `%net`/`%fs`/etc.; recipients call broker methods, methods run as broker's owner.
- **Jails** — narrowing wrappers for interface (which methods are exposed) with caller-role dispatch.
- **`%role.run_as`** — voluntary narrowing to a descendant's authority for a block.
- **Introspection** — `%call.role`, `%call.trusted?`, `%role.user?` for who-is-calling-me decisions.

## Areas worth spitballing

- **Sibling interaction.** Two roles at the same level under a common ancestor. Neither can structurally mutate the other's objects (Rule 2 blocks). How do they cooperate? Do they always go through the common ancestor, or is there a direct pattern?
- **Explicit grants beyond ownership.** A parent can transfer ownership down. Can a parent grant a specific capability (say "you can freeze this one object" or "you can call these three methods") without transferring ownership? Or is ownership transfer the only mechanism, and finer-grained needs get built via wrapper objects?
- **Role introspection from inside.** Can code ask "who's my parent?" or "how deep in the tree am I?" or "list my siblings"? Should it be able to? What does that expose?
- **Role events.** When a role is created, destroyed, or has an object transferred to/from it, are those observable? By whom?
- **Cross-tree interaction.** If two independent trees coexist (separate `user` roots, or a sandboxed process alongside the main one), what — if anything — can they share? Is cross-tree interaction a language concern or purely an application concern?
- **Role delegation without ownership transfer.** A parent wants to say "run this callback later, using your authority not mine." Is that different from `%role.run_as`, or the same thing viewed from the callback's perspective?
- **Handoff between siblings.** Sibling A wants to hand an object to sibling B. Under Rule 2, A can't give_to a sibling directly (must go through common ancestor). Is that the whole story, or is there a natural intermediate primitive?
- **Role naming and identity comparison.** `%role.user?` exists as a specific check. Should there be more (`%role.ancestor_of?(other)`, `%role.same_tree_as?(other)`, `%role.depth`)? What's the minimum useful set?
- **Time-bounded authority.** A parent temporarily elevates a descendant (via ownership transfer) but wants it to auto-revert. Is that block-scoped `%role.run_as` inverted, or a separate mechanism?

These aren't ordered by priority. To be worked one at a time.

## Potential designs

### Assigning URLs to a role

A parent creates a named role and binds a URL pattern to it. From then on, anything downloaded from a URL matching the pattern becomes a child of that role, rather than getting its own fresh implicit role.

```caspian
# Running as user:
$stuart = %role.children.new
$stuart.assign_source 'https://[www.]github.com/stuartbain/*'

# later — either in the same frame or a descendant's:
$lib = %fetch('https://www.github.com/stuartbain/some-library.casp')
# $lib is a child of $stuart, not a fresh minted role
```

The source binding is a routing rule: URLs decide where downloaded code lands in the tree. Everything from Stuart's GitHub becomes part of Stuart's branch. Different source patterns can be assigned to different roles; downloads route to whichever role's pattern matches.

**Implicit vs explicit roles.** With this design there are now two categories:

- **Implicit roles** — minted automatically by `%fetch` when no binding matches. GC'd when nothing owns them. Same behavior as today.
- **Explicit roles** — created intentionally via `%role.children.new` (or similar). Persist until manually destroyed. They exist as anchor points; the whole point is that they hold source bindings and act as trust buckets, so auto-GCing them when empty would defeat the pattern.

`%role.destroy` (or similar) manually removes an explicit role. Its children and their objects presumably transfer up to the parent, or the destroy raises if the role isn't empty — TBD.

Shape questions:

- **Pattern form** — exact URL, prefix, glob, regex, or Caspian-specific bracket-optional syntax? The `[www.]` optional-match in the example needs a defined grammar.
- **Conflicting bindings.** If a parent has assigned a source pattern to one of its children, other children of the same parent cannot assign a pattern that overlaps — an attempt to do so raises. First-bound wins; siblings can't compete for the same source. Details on how overlap is detected (identical patterns only? any URL matched by both?) are TBD until the design lands.
- **Composition with brokers** — this addresses "what role does the downloaded code run under"; brokers still address "what ambient I/O the code has access to." Orthogonal concerns, both needed.
- **Revocation** — can the binding be removed later? `%role.remove_source` seems obvious; behavior on already-downloaded objects (do they stay in the role or migrate?) is the interesting question.
- **Explicit role's position in the tree** — the `%role.children.new` shape makes it always a child of the current role; simple. If you need a role elsewhere, run the creation from where you want it parented.
- **Persistence across process runs** — if bindings are set up at startup and matter for security decisions, is there a way to declare them once and have them applied consistently? Or is that a config concern, not a language one?

The design captures a real trust pattern: "I trust everything from this source as coming from the same origin." Different from the general external-account discussion because it's source-based (fits Caspian's existing fetch model) rather than requiring authentication with an external identity provider.

#### URL pattern language

The pattern language is deliberately tiny. Two features, each with strict position rules:

1. **Optional literal group.** `[foo.]` matches zero or one occurrences of the literal string `foo.`. The brackets are not regex — the content is a plain string, matched exactly. Restrictions:
   - Only ONE `[...]` group per pattern.
   - Must appear at the beginning — right after the scheme's `://`.
   - Content must end with `.` and have at least one character before it.
2. **Trailing wildcard.** A pattern may end with `*`, but only if the `*` is immediately preceded by `/`. The wildcard matches any URL suffix.

Allowed:

```
https://[www.]github.com/stuartbain/*
```

Matches `https://github.com/stuartbain/foo.casp`, `https://www.github.com/stuartbain/anything/deeply/nested`, and so on.

Prohibited (all rejected at pattern-registration time):

```
https://[www.]github.com/stuartbain*     # * not preceded by /
https://github[foo.].com/stuartbain/*    # [foo.] not at the beginning
https://example.com/[stuff.]bar/*        # [stuff.] not at the beginning
https://[www]github.com/*                # bracket content doesn't end with .
https://[.]github.com/*                  # bracket content has nothing before .
```

That's the entire pattern language. No mid-string wildcards, no mid-string optional groups, no character classes, no regex, no glob, no negation. The two features cover the common cases; anything else is handled by assigning multiple patterns (see below) or by a custom broker in Caspian code.

**Why the `/*`-must-follow-slash rule.** Anchoring the wildcard at a path segment boundary prevents partial-segment matches like `github.com*` accidentally matching `github.com.attacker.net`. This is the security-relevant part of the wildcard restriction, not just "wildcard at end."

**Why `[...]` only at the beginning, must end with `.`, must have characters before.** All three constraints tie the feature to its intended use — an optional subdomain prefix like `www.`, `api.`, `beta.`. Mid-string groups would let patterns match hosts you didn't intend. Bracket content without a trailing `.` would raise unclear boundary questions. Bracket content with no characters before the `.` would be degenerate.

**Multiple patterns per role.** A single role can have multiple source patterns assigned. When a project's code lives on more than one site — GitHub, GitLab, a company mirror — assign each URL pattern separately:

```caspian
$stuart = %role.children.new
$stuart.assign_source 'https://[www.]github.com/stuartbain/*'
$stuart.assign_source 'https://[www.]gitlab.com/stuartbain/*'
$stuart.assign_source 'https://code.example.internal/sb/*'
```

All three bindings route to `$stuart`. The pattern language stays minimal; getting fancy is done by adding more patterns, not by making a single pattern more expressive.

**Cost.** URL normalization already has to exist for basic `%fetch` operation (matching `https://Example.com/` and `https://example.com/` as the same resource). The pattern matcher on top is a small delta — split the pattern into scheme + optional-group + rest, split the URL the same way, compare. Implementation fits in a few dozen lines. Complex pattern languages would eat significant floppy budget and open the door to subtle matching bugs; this doesn't.

Small implementation questions to pin down:

- Empty brackets `[]` — raise at registration (redundant with the "must have characters before the `.`" rule, but worth naming).
- URL normalization applied to both pattern and target before matching (lowercase scheme/host, resolve percent-encoding, strip default ports).

### Delegating

A block-form primitive that temporarily grants ANOTHER role the ability to do everything the current role can do. Different from `%role.run_as` — the target role stays as itself; it just gets a temporary extended permission set.

```caspian
%role.delegate_to($foo.obj.role) do
    # $foo.obj.role has all of the current role's permissions
    # (ambient I/O, ancestral authority over the current role's subtree, source bindings, etc.)
    # $foo.obj.role doesn't run AS the current role — it can just do the same things.
end
# $foo.obj.role's permissions revert to what they were before the block.
```

Contrast with `%role.run_as`:

| | `run_as` | `delegate_to` |
|---|---|---|
| What changes | current frame's role | another role's permission set |
| Where the effect happens | inside the block, in this frame | wherever that role runs code during the block |
| Cleanup | frame's role restores at block exit | target role's permissions restore at block exit |

**Only the current role can delegate its own permissions.** `%role.delegate_to(...)` inherently means "the current running role delegates to X." You can't call it to force-elevate someone else's permissions — `%role` is definitionally the current role, and you can only give away what you have.

**Extra wiring under the hood.** `run_as` is frame-local: swap this frame's role for the block, swap back. `delegate_to` is non-local: the engine has to track a per-role "temporary elevated permission set" that's active for the block's lifetime and cleared at exit (including on raise). That's a real but bounded addition — the engine already tracks role state elsewhere, so adding a per-role "temporary grants stack" is engineering, not model change.

Shape questions:

- **Scope of "all of the current role's permissions."** Ambient I/O (`%fs`, `%net`, brokers)? Structural authority over the current role's subtree (ancestor-like power over the current role's descendants)? Source bindings? All? Some subset? The purest reading is "everything the current role can do" — including transitively reaching into its descendant subtree — but that's powerful and worth confirming.
- **Concurrent frames running as the target role.** If another frame elsewhere in the call stack is also running as `$foo.obj.role` while the block is active, it ALSO gets the elevated permissions — elevation is per-role, not per-frame. Feature (that's what makes it useful for callback patterns) but worth naming.
- **Transitive delegation.** During the block, `$foo.obj.role` has the elevated permission set. Can `$foo.obj.role` now call `.delegate_to` and hand those elevated permissions further? Probably yes — it's just "current role delegates what it currently has" — but nested cleanup gets fiddly; each block has to remember what it specifically added.
- **Direction restriction.** Should there be a restriction like "target must be a descendant" (matching Rule 2's asymmetry) or is delegating to a sibling or unrelated role also fine? Probably worth restricting to descendants for consistency with the rest of the model, though the mechanism itself doesn't require it.
- **Overlap with brokers.** Brokers hand out one specific narrow capability; delegate_to hands out everything. They're different tools for different granularities; delegate_to isn't obviously simpler enough to replace either.

The primitive fits use cases where a role wants to say "please act on my behalf, briefly, with my full authority" — deferred callbacks, coroutine-style handoffs, "run this cleanup as me" scenarios. Different shape from `run_as` (which is "I'll act narrower") and different shape from brokers (which are "here's a specific narrow capability object"); the three cover different points in the same design space.

### Transferring ownership

**No-go.** Explored during this design pass; couldn't find a shape that earns its keep.

**What we considered.** A primitive like `$obj.obj.give_to($foo.obj.role)` that transfers direct ownership of an object from the current owner to a specified descendant. Intent was to handle two use cases: (1) scoping an object's lifetime to a specific descendant role, so the object dies when that role does; (2) permanent handoff for customization, so the recipient can freely restructure the object without borrowing authority repeatedly.

**Why it didn't work.**

- **Shallow transfer.** Ownership doesn't cascade through references — you own the container, not its contents. Transferring a class object hands over the class, not the methods' referents, not its instances, not anything the class points at. Transferring a hash hands over the hash, not the values inside. For anything object-graph-shaped — which is most cases where you'd instinctively want to transfer — the result is a partial move that will surprise the developer.
- **Existing primitives cover the real cases.** Delegation handles "I need foo to be able to do owner-things"; reference-passing plus Rule 4 handles "I need foo to be able to use this." The remaining gap — "I need foo to be the persistent owner specifically" — turned out to be narrow and mostly hypothetical.
- **The lifetime-scoping case is undermined by the shallow-transfer issue.** Transferring a container into a child's lifetime doesn't move the container's contents; they stay wherever they were created.
- **The permanent-customization case has coupling problems.** Transferring a class lets the recipient mutate the class object, but existing instances stay in their original owners' trees, and their behavior now depends on a class the recipient can restructure — exactly the kind of coupling the security model is designed to prevent.

**What to use instead.**

- **Primary strategy: have the intended role create the object in the first place.** Ownership is set at creation; if you want an object to be foo-owned, arrange for foo to create it. This handles lifetime scoping (the object dies with the creating role), permanent customization (the creator has full owner-authority from the start with no borrowing), and isolation (no cross-role ownership implications to reason about). Almost every case that seemed to need transfer is actually a case of "the wrong role created the object" — the fix is upstream, at creation, not downstream via a transfer primitive.
- For "let foo do owner-things briefly on an object it didn't create" → delegation (`%role.delegate_to`).
- For "let foo use an object without owning it" → just pass the reference. Rule 4 makes methods callable.

**When to revisit.** A specific use case that genuinely needs a persistent ownership change (not delegation, not reference-passing), IS object-graph-shallow enough that partial transfer is fine, AND doesn't fit the "just have the target create it" workaround. If such a case surfaces, add the primitive against that concrete need.

**Downstream cleanup.** Both spots that assumed the primitive have been updated:

- [security model Rule 2](https://puck.uno/requirements/security/model/) — "and ownership transfer" removed from the parent-authority list.
- [tires example, Pattern B](https://puck.uno/ideas/security/model/tires) — rewritten to use delegation (`%role.delegate_to`) instead of `.give_to`.
