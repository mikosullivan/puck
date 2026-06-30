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
