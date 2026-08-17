# YAML

~~~vibecode
{"vibecode": {
	"doc": "requirements_v1_downloads_yaml",
	"role": "spec for the YAML class at `caspian.uno/yaml.casp` — Ships: no, Day 1: yes. Wraps a Lua YAML library (installed on demand via `caspian --install-lua`); not bundled in core.",
	"status": "stub — needs class-surface design and scope decision on which YAML features are in / out",
	"audience": "developers reading/writing YAML files (Kubernetes manifests, Rails/GitHub Actions config, dev tooling); anyone writing the YAML class spec"
}}
~~~

Stub. First-party download at `caspian.uno/yaml.casp` — YAML encode/decode. Underlying implementation is a wrapped Lua YAML library installed on demand via `caspian --install-lua`, not bundled in core.

## What YAML is

TBD. Human-readable data serialization language; superset of JSON in shape. In practice the full spec is a trap (anchors, aliases, custom tags, multi-document streams, four-way boolean spelling), so this class's scope decision is which subset it supports.

## Scope call to make

TBD. Two schools of thought:
- **Full spec.** Anchors, aliases, custom tags — accept whatever a Lua YAML library implements.
- **YAML 1.2 core / "sane subset".** Reject the historical quirks that Lua libs still ship; force the extras through an explicit opt-in flag.

## Method surface

TBD. `.parse` / `.emit` shape; options for whichever features live behind flags.

## Testing

TBD.
