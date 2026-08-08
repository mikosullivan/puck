# `%forks`

~~~vibecode
{"vibecode": {
	"doc": "requirements_global_methods_forks",
	"role": "spec for %forks — Caspian's process-forking surface. Stub — content lands here as it's worked out.",
	"status": "stub — only fork-lifetime semantics settled so far",
	"audience": "developers reasoning about process-level parallelism in Caspian; engine implementers building the fork surface"
}}
~~~

Stub. Content lands here as it's worked out.

## Fork lifetime

Forking returns a **fork object**. That object's scope is the child process's lifetime — when the object goes out of scope (script exit, block exit, explicit `.destroy`, any other reason the reference drops), the child process is terminated whether it has completed or not.

This is deliberate. Caspian doesn't accumulate unreaped children; there's no situation where a script hangs at exit because it's waiting on a forgotten child. If a caller wants a child to run to completion, the caller waits on the fork object explicitly (e.g., `$fork.wait` — provisional name) before allowing it to fall out of scope.

Instance of the [bounded-lifetime objects](https://puck.uno/requirements/concepts#bounded-lifetime-objects) pattern: the fork object owns the child process the same way a transaction handle owns a transaction or a broker owns its wrapped authority. Uniform machinery — `.destroy`, `.destroyed?`, class-declared "Fork terminated" error on calls to a dead fork.

**Design implication.** There is no "fire and forget" child process; a child's lifetime is always visible in code as the presence of a fork object in scope. Fan-out / gather patterns work naturally with this rule. Persistent background services that should outlive their creator are a different problem — they need a persistent service, not a fork.

## Post-fork PRNG reseeding

**Every child process must reseed its SQLite PRNG immediately after forking.** SQLite's `sqlite3_randomness()` API — which backs `random()`, `randomblob()`, and the `uuid()` extension — uses a ChaCha20 stream cipher seeded from `/dev/urandom` at library load. `fork()` copies the parent's PRNG state verbatim; without reseeding, parent and child generate the same random values. That means colliding UUIDs, duplicate session tokens, and other correctness bugs that only surface at scale — subtle, hard to debug, security-relevant.

The engine forces the reseed by calling `sqlite3_randomness(0, NULL)` in the child immediately after `fork()` returns, for every open SQLite connection the child inherits. That resets the internal PRNG state; the next randomness call reads a fresh seed from `/dev/urandom`.

Unconditional. No opt-out. The fork surface must ensure the child reseeds before it can call any RNG-using code — before any UUID generation, before any random token allocation, before any code path that could observe a random value.
