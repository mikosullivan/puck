# Trust Policy

~~~json
{"vibecode": {
	"doc": "trust-policy",
	"role": "spec for the three-layer trust-policy model: host injects policy at boot, engine enforces it, Charlie consumes resources via %engine; covers CLI default behavior",
	"key_concepts": ["three_layer_trust_model", "host_injects_policy", "engine_enforces",
		"cli_default_open_policy", "charlie_blind_to_config"]
}}
~~~

<a id="overview"></a>
## 1 Overview

Charlie has no concept of where its trust configuration comes from. That is the host
program's responsibility. The engine enforces whatever policy the host provides; it does
not decide what that policy is.

The flow is always outside-in:

```
config source → host program → engine → %engine → Charlie script
```

---

<a id="the-three-layers"></a>
## 2 The Three Layers

**Charlie** — knows nothing about trust configuration. Accesses host-provided resources
via `%engine`. Cannot read, modify, or influence the trust policy.

**The engine** — knows the structure of the trust policy and enforces it. Accepts the
policy from the host at boot. Rejects objects that don't satisfy the policy.

**The host program** — decides what policy to inject. Reads config from wherever makes
sense for its context and passes it to the engine at startup. Two examples:

- The CLI reads from personal config and injects an open-by-default policy
- A web server injects a locked-down policy with a specific allow-list

---

<a id="cli-behavior"></a>
## 3 CLI Behavior

When a Charlie script is run from the command line, the CLI host applies this default:

1. Start with an open policy — any signed object from any domain is permitted
2. Read `~/.config/puck/trust.json` if it exists
3. Apply any restrictions or domain-specific settings found there

The personal config can only restrict the open policy — narrow permissions, add domains
to a deny list, tighten what specific domains are allowed to do. It cannot grant
permissions beyond the open default.

---

<a id="non-cli-behavior"></a>
## 4 Non-CLI Behavior

In any context other than the CLI, there is no concept of a default config location. The
host program is entirely responsible for providing the trust policy.

If the host provides no trust policy, the engine refuses to run. An absent policy in an
embedded context is most likely a configuration mistake, not an intentional choice. Silent
open-policy fallback would be a security hole.

---

<a id="trust-policy-structure"></a>
## 5 Trust Policy Structure

A trust policy has two parts: a base mode and an optional domain list.

<a id="base-mode"></a>
### 5.1 Base mode

| Mode | Behaviour |
|------|-----------|
| `open` | Any signed object from any domain is permitted at the default permission set |
| `allow_list` | Only domains explicitly listed are permitted |

<a id="domain-entries"></a>
### 5.2 Domain entries

Each domain entry specifies which permissions objects from that domain are granted:

```json
{
    "mode": "open",
    "domains": {
        "borg.com": {
            "fork": true,
            "network": true,
            "storage": false,
            "abort": false
        },
        "evil.com": {
            "deny": true
        }
    }
}
```

In `open` mode, domains not listed receive the default permission set. Listed domains
override the default — either granting less, granting more, or denying entirely.

In `allow_list` mode, domains not listed are denied automatically.

<a id="permissions"></a>
### 5.3 Permissions

| Permission | Description |
|------------|-------------|
| `fork` | May spawn child processes |
| `network` | May make network calls |
| `storage` | May read and write persistent data |
| `abort` | Abort exception propagates past the security boundary |
| `mining` | May perform crypto mining. See note below. |

<a id="crypto-mining"></a>
### 5.4 Crypto Mining

Any object that performs crypto mining must explicitly declare itself as such. The
declaration mechanism (a metadata field on the object) is not yet designed — setting TBD.

The `mining` permission is off by default for all domains. An engine will not execute
mining code unless the permission has been explicitly granted and the object has declared
its intent.

Failure to properly identify a crypto mining object is an ethical violation.

See [crypto-mining-payments.md](../apps/crypto-mining-payments.md) for the broader payment system
built on this mechanism.

---

<a id="capability-attenuation"></a>
## 6 Capability Attenuation

Permissions can be narrowed but never expanded. A script receiving an object from
`borg.com` can pass it to a subsystem with `fork` stripped out. It cannot grant `borg.com`
a permission the engine did not originally allow.

This applies at every level — engine to script, script to called function, function to
sub-function. The ceiling is always set by the host.

---

<a id="relationship-to-signing"></a>
## 7 Relationship to Signing

The trust policy only applies to signed objects. An unsigned object is rejected outright
regardless of policy. The policy controls what signed objects are permitted and at what
permission level — it assumes the signing problem is already solved.

See [signing.md](signing.md) for how object signatures work.
