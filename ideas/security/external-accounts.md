# Tying Caspian roles to external accounts

~~~vibecode
{"vibecode": {
	"doc": "ideas_security_external_accounts",
	"role": "design-exploration essay on whether — and how — Caspian's internal role system should tie into external identity (Unix uids, GitHub accounts, OAuth, LDAP, SSO). Enumerates interpretations, use cases, integration paths against the five-rule model, prior art, tensions, concrete design sketches, and a recommendation. Companion to the settled model at requirements/security/model/ and the critique at ideas/roles-critique.",
	"status": "exploration — no direction promoted to spec; the recommendation is a working position, not a decision",
	"context": "Stuart, reading the model for the first time, assumed roles meant things like Unix accounts or GitHub identities. They don't. But the confusion pointed at real programs Caspian will eventually want to serve — multi-user services, per-developer permissions, auditable action trails — and Miko wanted the design space written down before it accretes ad-hoc."
}}
~~~

Caspian roles are internal identities. They exist inside one program run, form a tree rooted at `user`, and vanish when the branch that created them becomes unreachable. Nothing about a role is durable, nothing about it names anything outside the process, and the engine grants I/O to `user` without asking who `user` is.

Stuart hit this model cold and assumed roles were tied to Unix accounts, GitHub identities, or an OAuth login. They're not. But the assumption is a reasonable one — every enterprise permission story in the last thirty years starts with an external identity — and if that mental model is where developers arrive by default, the language owes an answer for whether the door is open, closed, or somewhere in between.

This page walks the design space. It is exploratory. Nothing here is a spec.

## The confusion is a feature request

A developer coming from Unix, Rails, Django, Spring, Node.js, or any other server ecosystem has years of muscle memory that says: **identity means a real person or a real account**. Postgres roles are DB accounts. Kubernetes service accounts are cluster identities. GitHub Actions runs jobs under an identifiable actor. Every framework's `current_user` is the authenticated human. The word "role" in ninety percent of a working developer's career refers to enterprise RBAC — a real user's real group membership.

Against that background, "role" as "opaque internal tree node minted by `%fetch`" reads as odd. It looks like the language deliberately declined to use the obvious primitive.

The use cases behind that expectation are the interesting part:

- **"I want to know who did what."** Audit trails, per-user quotas, incident forensics. The developer wants a role identifier that survives out to logs and databases as a durable name.
- **"I want different users to see different things."** Multi-tenant services, per-account data isolation, admin-vs-regular access. The developer wants roles that map to authenticated principals from an external system.
- **"I want to trust code from person X differently than code from person Y."** Signed packages, verified publishers, "run this only if it came from a Puck-endorsed author." The developer wants role identity tied to the author of the code.
- **"I want to run downloaded code with the calling user's authority, not with some anonymous fetch-role authority."** SaaS-shaped services where the human on the other end is the actual principal.

None of these are fringe. They are the reason enterprise auth exists. The current model doesn't say "no" to any of them, but it also doesn't say "yes" — the primitives for stitching an external identity into a role are simply absent.

## What "tie to external account" could mean

There are at least five distinct interpretations. They are not variants of the same thing. Getting them straight is prerequisite to any useful discussion.

### Role identity IS the external account

The role's name literally is the external identifier — `github:alice`, `unix:1000`, `oauth:acme.example.com/user_42`. Two program runs that authenticate the same GitHub user get roles with the same name; two runs by different users get different roles. Role identity is durable across process boundaries.

This is what Stuart imagined. It is also the most invasive interpretation — it makes roles a global namespace, subject to spoofing concerns, dependency on external systems, and the confusion of two roles-with-the-same-name-but-different-meanings.

### Role has an external-account attribute

Roles stay internal identities. Some roles — typically ones created in response to an authenticated request — carry an optional external claim as metadata: a role representing an authenticated session might have `.external_identity = 'github:alice'` attached. Most roles never carry one (class roles from imports, internal orchestration roles, general worker roles have no external counterpart). Structural rules — parent/child relationships, what mutations are allowed — still run against the internal identity, whether or not a claim is present. External systems (audit logs, permission checks in application code) read the attribute on the roles that have it.

This is the least invasive interpretation. The role machinery is unchanged; roles that want to record external provenance can, and most don't. Almost every use case above can be satisfied by application code reading the attribute at the appropriate boundary.

### External accounts map to permission grants

The engine gates I/O by external identity, not by role. Roles are still ephemeral internal identities, but the ambient authority available to `user` (or to any role) is a function of the OS user running the process, or the OAuth token presented at launch, or the Kerberos ticket in the environment. Different accounts → different capability sets handed to `user` at startup.

This is closest to how Unix works. The role structure inside the program is orthogonal to the account identity; the account identity is where the *grants* come from.

### External accounts drive role instantiation

The program does not have one `user` role. It has one role per authenticated principal. A web request from Alice runs under `R_alice`; a request from Bob under `R_bob`. Both are internal roles minted at request time; both carry the external identity of the account they were minted for; both sit under some `user` (or under separate `users`) in the tree.

This is the interpretation that fits a multi-user server. It is not one of the others in disguise — it changes the shape of the role tree per-request, and requires the language to have some notion of "principal boundary" that the current model doesn't.

### Code-source identity, not caller identity

The role that runs downloaded code is tied to the *publisher* of the code — the signed author of the package, not the fetching site. `%fetch('github.com/alice/lib')` creates a role that is `github:alice` because Alice signed the library. Trust decisions look at the publisher, not the local frame.

This is a separate axis from the above. External identity here means "who wrote this code," not "who is running the program." Confused-deputy dynamics look completely different.

These five overlap in some cases and are orthogonal in others. Any coherent design decides which of them (possibly more than one) it wants to serve, and rejects the rest explicitly.

## Real-world use cases

Making the interpretations concrete against the programs Caspian will plausibly run.

**Multi-user web service.** A Caspian-based HTTP server. Each request arrives with a session token that resolves to a real user. The server wants: per-user data isolation (Alice can't read Bob's rows), per-user audit trail (log lines identify the human), per-user quota enforcement (rate limits per account). Today the developer builds this in application code — the framework threads a `current_user` string through everything. Roles could carry the claim automatically.

**Shared build server.** A Caspian program acting as a CI runner or code-execution sandbox. It runs code submitted by different developers under different levels of trust. The Ops team wants: "code from developers on the vetted list runs with these grants; code from anyone else runs with a much smaller set." Publisher identity, not caller identity.

**Multi-developer platform.** A running Caspian service that engineers on the team can extend by pushing plugins. Each plugin is authored by a specific person; the platform wants to know whose plugin caused what. Audit and blame both want a durable identifier.

**Enterprise SSO integration.** A corporate deployment where the OS user is authenticated against Active Directory. The Caspian process wants to consult the AD claim ("is this user in the `finance` group?") when deciding whether to expose certain surfaces. This is the classic Windows `PrincipalPermission` shape.

**Package trust.** A Caspian program that pulls in libraries from unknown authors. It wants: "only run methods from libraries signed by a publisher on my allow-list." Signed publisher identity carried into the role.

**Data access on a per-account basis.** Downstream — a Puck object store or Mikobase deployment. The Caspian program presents an external identity; the storage layer decides what rows the identity may see. Whether or not Caspian participates, the identity has to be produced *somewhere*; today the developer does it by hand.

Every one of these is a real program shape. Not all of them need language-level support — the multi-user web service, for example, can be done end-to-end in application code. But the pattern where identity travels *through* the language rather than *around* it recurs.

## How it composes with the five rules

Walking each interpretation against the settled [five-rule model](https://puck.uno/requirements/security/model/) exposes which rules bend and which break.

### Rule 1: roles and objects

Rule 1 says every frame runs as one role, and every object is owned by one role. That rule survives any of the five interpretations — none of them change the one-role-per-frame or one-owner-per-object property. What changes is *how a role comes into existence*.

Under "role identity IS the external account," creation happens at authentication time, and the role's identity is decided externally. Under "attribute on role," creation is unchanged; the attribute is set at creation time or later. Under "external drives instantiation," each authenticated principal produces a fresh role — the process's role tree can have multiple `user`-like roots, one per authenticated session. That is a meaningful change to Rule 2.

### Rule 2: corporate structure

Rule 2 says roles form a tree rooted at `user`. This is the rule that strains hardest.

If a request from Alice and a request from Bob both need a `user`-level role — because both are the *actual* user for their request — then Rule 2's single-root story falls apart. Either the tree grows multiple roots (one per authenticated session), or `user` becomes a bootstrap notion distinct from "the human on the other end," and per-request roles live somewhere below it.

The multi-root variant is a real change: `%engine` grants at startup no longer go to a well-defined `user`; the grant model has to know which root gets what. The bootstrap variant preserves the tree but makes `user` less meaningful — the actual human is one level down, and the parent-authority story has to account for that.

Under "external attribute on role" (the least invasive interpretation), Rule 2 is untouched. Roles are still minted from other roles; the attribute is decoration.

### Rule 3: dispatch on defining role

Rule 3 says a method runs under the role that defined the code. That rule is the most robust — it doesn't care about external identity at all. Even under the multi-user server, `$db.next_tire` still runs in the DB class's defining role; the fact that the calling request has an authenticated user is Rule 3's problem only if Rule 3 itself is what changes.

The interesting question is code-source identity: if the role a method runs under is tied to the code's *publisher* rather than to a fresh mint at fetch time, then Rule 3 gains new content. It's still "method runs under the defining role," but "defining role" now has an external name. Downstream code deciding "should I let this method touch my secrets?" can ask a durable question.

### Rule 4: access is empowerment

Rule 4 says holding a reference is enough to call the reference's methods. External identity does not change this. The reference itself carries the authority; the identity of who holds it is a Rule 3 question (dispatch) rather than a Rule 4 question (access).

Where external identity *could* interact with Rule 4 is in class-author-written gates — a method that decides at runtime "I only run for Alice" would consult the current role's external identity. That is application-level policy on top of the language rule, not a change to the rule itself.

### Rule 5: I/O is engine-granted

Rule 5 is where external identity has the most interesting story. Today the engine hands I/O to `user` and asks nothing about who `user` is. Under any interpretation where external identity *does* affect I/O grants — the Unix-uid interpretation, the OAuth-token interpretation, the AD-group interpretation — Rule 5 gains a new axis: the grant set is a function of the presenting identity.

This does not have to be baked into the language. It can live entirely in the host process: the host program authenticates the request, decides which grants to hand to the engine, calls `engine.run`. Caspian itself never sees the identity; it just receives the grants. That matches how the current trust-policy design already works ([host injects policy, engine enforces](https://puck.uno/ideas/security/trust-policy)).

The moment external identity crosses into the language — the moment Caspian code can say "who am I?" and get an answer that means anything to the outside world — Rule 5 has to grow a story about where that answer came from and how it survives inside the process.

## Prior art

The industry has been through most of these interpretations already. What each did, and why.

**Unix (uids and gids).** Integers stored in `/etc/passwd`, mapped to accounts by the OS. Every process runs as a uid; every file has an owner. `setuid` and `setgid` let a program acquire another identity, and every exploit textbook has a chapter on `setuid`. The model is deeply embedded and every system programmer knows it — but it composes poorly with capabilities. A process's uid does not decompose into "may open /etc/shadow but not /etc/passwd"; it is a single identifier and grants are Boolean per-resource. Fine-grained control had to be bolted on later (capabilities(7), SELinux, AppArmor), and each addition broke someone's mental model.

**Kerberos.** Identity is a ticket signed by a trusted authority. Tickets expire; tickets can be revoked; tickets can be delegated with restrictions. The mechanism is genuinely distributed and genuinely secure, but the developer burden is high — every service has to speak the Kerberos ceremony, and misconfiguration is the norm. Enterprises that get it working depend on it deeply; smaller teams walk away.

**OAuth 2.0.** Tokens with scopes, obtained from an authorization server, presented at each request. The web absorbed OAuth because it worked for the browser case; using it for machine-to-machine identity has proven considerably rougher. Scopes are stringly-typed and provider-specific. Refresh flow is a security minefield. The lesson: token-based delegation is workable at a well-defined boundary and painful everywhere else.

**SPIFFE / SPIRE.** Cryptographically-verifiable service identities designed for cloud-native workloads. Each workload gets a SPIFFE ID (a URI); the identity is provable by X.509 or JWT. The design is *good* — it maps closely to what a modern Caspian-shaped system would want for machine identity — but adoption requires substantial infrastructure. Not something Caspian can lean on for a V1 story.

**macOS XPC and Windows SIDs.** OS-level identity propagates into processes automatically. An XPC service knows the audit token of its caller; a Windows service can query the SID of the client on the other end of a named pipe. Both work well *inside* their respective OSes; both are opaque to portable code. Caspian would gain little by hard-wiring to either.

**Capability-based OS research (KeyKOS, EROS, CapROS).** These systems deliberately separated identity from authority: capabilities were the access mechanism, and identities existed for logging and administrative purposes only. The lesson is important: the languages and systems that survived (see [roles-prior-art](https://puck.uno/ideas/roles-prior-art)) moved authority to references, not to identities. Tying Caspian roles to external accounts risks re-attaching authority to identity, which is exactly the direction the research consensus argues against.

**Erlang node identities.** Nodes in an Erlang cluster have names; processes have PIDs. Neither is tied to a user account. Communication happens by message, and the sender's node/PID is available to the receiver, but nothing about that identity is a claim of who is *behind* the process. The Erlang answer to authentication is "put it in the application" — which is honest and has held up.

**Keybase's identity proofs.** Cryptographic ties between accounts on different services — this GitHub account, this Twitter handle, and this domain are all the same person, provably. The interesting move is treating identity as a *set* of external accounts rather than a single one, with cryptographic linkages between them. Not directly relevant to intra-process role tracking, but it is the model to steal from if Caspian ever wants to say "this role represents the same person as this GitHub account and this domain."

The common thread: **every system that succeeded kept identity and authority separate**. Identities existed for audit, for display, for admin decisions; authority came from capabilities, tokens, or references. Systems that fused the two (Unix uids, Java's SecurityManager) either accumulated bolt-ons or retired.

## Tensions and pitfalls

Six problems any tying scheme runs into.

**Roles are ephemeral; accounts are durable.** A Caspian role vanishes when its tree branch becomes unreachable — that is the whole point of Rule 2's tree model. A GitHub account outlives every program run. Naming a role after an account creates two-way confusion: the same account might be represented by different role objects across program runs (and across concurrent requests in the same run), and querying "is this role Alice?" gives an answer whose meaning depends on when you ask.

Any scheme has to be clear whether external identity is the *object* or an *attribute* of the object. Making it the object breaks the ephemeral-role story. Making it an attribute preserves the story but requires application code to do the "is this Alice?" lookup by reading the attribute rather than comparing role identity.

**External systems are unreliable.** A Caspian program that depends on GitHub API availability to decide who has what authority is a Caspian program that stops working when GitHub is down. The language cannot make external identity load-bearing at method-dispatch time without inheriting the reliability of every identity provider it touches.

The clean answer is: external identity is resolved *at boundaries*, cached inside the process for the duration of the run, and never re-consulted per operation. Making that discipline the default rather than an opt-in is a language-design choice.

**Authentication is the actual problem.** "Tie roles to external accounts" is easy to say and impossible to do without deciding *how the external identity is verified*. Trusting a JWT means trusting the signing key; trusting an SSH principal means trusting the SSH daemon; trusting a `getuid()` value means trusting the process boundary. Caspian cannot invent authentication; it can consume it. The host program has to hand identity to the engine the same way it hands trust policy — as a claim the engine takes on faith, backed by whatever ceremony the host performed to earn that faith.

**Multiple identity axes.** A single Caspian process can plausibly carry: the OS uid of the process itself; the OAuth identity of the current web request; the GitHub identity of the code the fetching site loaded; the corporate SSO identity of the developer who pushed the deployment. These are different, and they mean different things, and application code sometimes needs one and sometimes needs another.

A design that assumes "the external identity" is one thing gets this wrong. Every real system is multi-axis. Either the language surface names the axis every time it is used (`.oauth_identity`, `.publisher_identity`, `.process_uid`), or it picks one and forces the developer to work around it for the others.

**Privacy consequences of a durable claim.** The moment roles carry real names, they leak. A stack trace from a running process starts revealing who was on the phone. Log lines that used to say `R_47` now say `alice@example.com`. GDPR territory. This is not a reason to reject the design; it is a reason to make the identity claim opt-in per-role and per-context rather than defaulting on.

**Backwards compatibility with the tight five-rule story.** The current model is compact enough to teach in an afternoon. Any tying scheme that adds a new rule (Rule 6: roles may carry external identity) or modifies an existing one (Rule 2: multiple roots when principals differ) makes the model larger. The size cost is real. A design that satisfies the use cases *without* adding a rule is preferable to one that adds a rule, even if the added-rule version is more principled.

## Design proposals

Three directions worth exploration. None are recommendations — the recommendation is at the bottom.

### Direction A: opaque attribute, host-set, application-read

Roles remain what they are. A new optional field on a role — call it `.claim` — stores a hash of external identity claims. The host program sets the claim when it mints (or receives) a role that corresponds to an authenticated principal. Application code reads the claim when it needs to.

~~~caspian
if $user.role.claim['github'] == 'alice'
	# admin path
end
~~~

The engine assigns no semantics to the claim. It does not use it for dispatch, does not check it at I/O time, does not include it in the tree structure. The claim is metadata for the application layer, in the same way `%amber` is metadata for cross-cutting context.

**Pros.** No change to Rules 1-5. Composes with existing role mechanics. Application code that ignores the claim keeps working. Multiple identity axes are natural — the claim is a hash, keyed by axis name.

**Cons.** Everything is application-level policy. The language does not help enforce anything about the claim; a class author who forgets to check gets no warning. This is a floor, not a ceiling.

### Direction B: authenticated-principal roots

The role tree gains multiple roots. `user` remains one of them — the process's own identity — but each authenticated session (a web request, a background job, an interactive user) can be given its own root. Each root has its own I/O grant set, determined by the host program at authentication time.

~~~caspian
# Host program, before engine.run:
$root_alice = engine.mint_root(claim: {oauth: 'alice@example.com'}, grants: {net: $net_alice, fs: null})
$root_bob   = engine.mint_root(claim: {oauth: 'bob@example.com'},   grants: {net: $net_bob,   fs: null})

engine.dispatch(root: $root_alice) do
	&handle_request $req_alice
end
~~~

Inside the Caspian process, `$root_alice` and `$root_bob` are peer roots; nothing in the tree bridges them. The I/O one gets is not the I/O the other gets. Each root's tree grows and shrinks per Rule 2 as normal.

**Pros.** Multi-user services fall out of the design cleanly. Rule 5 already talks about the engine handing I/O to `user`; generalizing to "the engine hands I/O to each root" is a small change. Session isolation is real, not policy.

**Cons.** Bigger change. Rule 2's single-root property was load-bearing for the mental model; giving that up costs teachability. It also invites the question of *who is parent* between roots (probably: nobody, they are peers), which the current model doesn't have to answer.

### Direction C: publisher identity for downloaded code

Only the fifth interpretation, applied narrowly. `%fetch` continues to mint fresh roles, but the role gains an optional `.publisher` attribute pulled from the fetched package's signature (if present) or from the fetch source (if not). Publisher identity is a claim about the *code*, not about the caller.

Trust policies can then be expressed against the publisher: "grant `%net` to roles whose publisher is on this allow-list." The developer building a plugin platform gets a straightforward way to say "only trust code from these signed authors."

**Pros.** Solves a real problem (untrusted code from unverified authors) without touching the caller-identity story. Composable with A: publisher is one axis of the claim hash. Composable with B: publisher lives on any role, root or not.

**Cons.** Requires a signing story, which Caspian doesn't have yet. Meaningful only if the fetch source supports signatures. Falls back to "source URL as identity," which is weak — anyone who can compromise the source can impersonate the publisher.

### What definitely should not be adopted

Making role identity *itself* the external account — the most naive interpretation — is a bad direction. It breaks the ephemeral-role story, makes role identity dependent on external system availability, and re-attaches authority to identity in the exact way the industry moved away from. Every problem it solves is solvable with an attribute instead. Do not do this.

Making external identity load-bearing for dispatch (Rule 3 consults `.claim` to decide what to run) is also bad. Same reasons: identity becomes authority, network becomes prerequisite, all of Java SecurityManager's problems reappear in a smaller frame.

Making Caspian speak any specific external protocol natively (bake OAuth in, bake LDAP in, bake Kerberos in) is bad. The language should not carry that surface. Consume identity as a claim the host provides; leave the protocol to the host.

## Recommendation

Do Direction A. Consider Direction B once multi-user services become a live target. Defer Direction C until Puck's signing story exists.

Concretely, for the next design pass:

**Add an opaque claim attribute to roles.** A hash, keyed by axis name (`'unix'`, `'github'`, `'oauth:acme.example.com'`, whatever), values are strings. Set by the host program when it constructs a role (or by `user` code when it mints subroles under a controlled interface). Read by application code that cares. The engine assigns no semantics — no dispatch check, no grant check, no tree-structure implication.

This satisfies the audit-trail use case, the multi-user-service use case (as long as multi-user is done at the application layer, which every existing web framework already does), and the multi-axis reality without adding a rule. It is the smallest surface change that makes the confusion Stuart had translate to a real answer: "roles are internal, but you can hang an external claim on them, and you decide what it means."

**Do not add a mechanism for the engine to enforce anything about the claim.** As soon as the engine cares whether `role.claim['oauth'] == 'alice'` is true, the engine has to define how it was verified, what happens when the identity provider is down, and what the semantics are of two roles with the same claim. All of those are host-program problems. Keep them there.

**Do not name the field `identity`.** That word implies verification the language cannot promise. `claim` — a thing that is *asserted* and might be true — is honest.

**Do not build a claim-lookup convenience like `%call.role.github` or `%call.role.oauth`.** Every convenience of that shape hard-codes an axis into the language. Force the developer to write `%call.role.claim['github']`; the small ugliness prevents entrenching axes the language shouldn't know about.

**Wait on multi-root roles.** Direction B is the right answer for a multi-user server, but a multi-user server is a specific program shape and V1 does not have to serve it. When it does, revisit — the change to Rule 2 is real but tractable, and the design gains from having concrete web-framework code to design against.

**Wait on publisher identity.** Direction C depends on signing infrastructure that does not exist yet. When Puck's signing story materializes, publisher identity becomes cheap to add — it's the same claim attribute, populated by the fetch layer instead of the host.

The failure mode to avoid is a slow accretion of external-identity surfaces bolted onto the current model piecemeal — one convenience method here, one Rule 5 exception there. Every step feels small; the sum is a model no one can teach. Doing the minimum (a claim attribute, and nothing else) leaves the door open for every direction the design might eventually go, without pre-committing to any of them.

Miko's instinct here should be conservative. The current five-rule model is small enough to be a *feature*, and external identity is exactly the kind of concern that grows without bound if you let it inside the language. Keep it outside. Let the host inject a claim; let application code read it; do not build any engine-enforced meaning on top of it. If a real program later demands more, the demand will arrive with concrete constraints, and the design can respond then.
