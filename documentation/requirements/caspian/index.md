# Caspian
<!--index: 2 -->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_root",
	"role": "root of the Caspian language section of the authoritative requirements tree. Names what lives under requirements/caspian/ and links into the canonical doc for each concept. Does not redefine concepts; cross-references the docs that own them.",
	"status": "rebuilding — concepts migrate from requirements-old/caspian/ one at a time, with revision as needed",
	"audience": "anyone looking up authoritative Caspian behavior; start here, follow the links into the canonical doc for the concept you want"
}}
~~~

Caspian is the programming language of the Puck ecoverse. This directory holds the authoritative spec for the language.

## What lives here

The Caspian spec is being rebuilt under the single-source-of-truth discipline described in [the requirements root](https://puck.uno/documentation/requirements/). Concepts migrate from `requirements-old/caspian/` to this tree as they're revised. Until a concept lives here, this section is silent about it.

### bootstrap/

How a Caspian engine comes into existence and starts running a program. Covers the host-engine boundary, the property-based host API, the role of `engine.run()`, and worked startup scenarios for several host environments.

### initial-state/

The state of the engine and program at the moment user code begins running — what's provisioned, what's in the chain, what's reachable.

### engine/

The `%engine` system method — the user-only gateway to host-provisioned resources. Covers `%engine.require`, host-injected slots, and the `user`-role access check.

### roles/

The role system — the identity that owns currently-executing code. Owns the role catalog, cross-role method access rules, role-reference semantics, and how capabilities flow per role.

### global-methods/

The complete catalog of `%X`-prefixed globals — standalone system namespaces and chain-mediated capability shortcuts. The catalog lives in `index.md`; specs that don't already have a home elsewhere (currently `%call`) live as their own files in this directory. Per-capability specs for the chain-mediated globals link back into `chain/methods/`.

### chain/

The `%chain` ambient call-frame chain. Every global capability method lives on `%chain`; grant/revoke are block-scoped methods on those capabilities; ambient hash values flow down the chain with role-boundary resets.

### concepts.md

Cross-cutting concepts that don't belong to any one subtree — no-nanny code, edge-case handling, long descriptive names, and other design principles the whole spec references.

### syntax/

Caspian's surface syntax — what a programmer actually types. Sub-pages for comments and whitespace, sigils, variables and assignment, operators, truthy and falsy, if / unless, loops, bare blocks, classes, system-method sigils, and pipes.

### functions/

Function-shaped callables — bare functions, closures, and methods. Also covers parameter defaults, the call surface, and the caller-object mechanism used by DSLs and configured calls.

### classes/

Class-level features beyond what fits on a single class page — definition-time DSL, inheritance, method resolution, and singleton / amend patterns.

### built-in-classes/

The classes Caspian ships out of the box — the JSON-primitive family (string, number, boolean, null, hash, array) and the meta / structure surface (object, class, method, function, closure, caller). Root of the primitive spec sub-tree.

### plumbing/

Faucets and sinks — Caspian's abstractions for values-coming-in and values-going-out that carry role identity across the boundary.

### downloads/

The catalog of first-party classes Caspian fetches on demand at V1 launch (CSV, YAML, TOML, INI, BSON, Markdown, zip, gzip).

### installation/

How the `caspian` binary and its supporting files land on a developer's machine — install script, prompts, XDG paths, self-test, OS checks.

### core/

What Caspian ships — the binary itself, pre-installed Lua libraries, and the floppy-budget accounting for both.

### secure-memory/, exceptions/, filesystem/, puck-discovery/, linux-support/, bryton/, lua/, test-cases/

Deeper areas — the vault and Password class, the exception hierarchy, dirs / grants / dirjails, `%puck` object-download resolution, Linux-specific shellout wrappers (openssl, tar), the Bryton test runner, the Lua-binding surface, and the test-case fixtures.
