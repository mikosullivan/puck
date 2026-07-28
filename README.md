# Caspian

~~~vibecode
{"vibecode": {
	"doc": "readme",
	"role": "entry-point overview of the Caspian language repo",
	"audience": ["humans_landing_on_github", "AIs_orienting_to_the_repo"],
	"key_concepts": ["Caspian_language", "design_heavy_implementation_early",
		"canonical_specs_live_under_documentation", "four_guiding_principles",
		"lightweight_under_1mb", "extracted_from_puck_ecoverse"],
	"notes": ["repo_was_originally_the_Puck_ecoverse_umbrella",
		"Puck_protocol_and_Mikobase_object_store_extracted_pending_own_repos",
		"pre-caspian-only_git_tag_marks_the_extraction_boundary"]
}}
~~~

Caspian is a **lightweight, embeddable programming language**. Active design and early implementation.

This [repository on GitHub](https://github.com/mikosullivan/puck) is the working source: design docs, the engine in progress, tests, experimental code.

You can submit issues to GitHub with these links: [GitHub issue](https://github.com/mikosullivan/puck/issues/new?title=%5Bdocs%5D%20README.md&body=Page%3A%20%60README.md%60%0A%0A%28Describe%20the%20issue%20here.%29)

## Origin

Caspian was originally designed as one of three packages in the **Puck ecoverse** (Puck the remote-object protocol, Caspian the language, Mikobase the object store). The other two packages have been staged for their own repos; the `pre-caspian-only` git tag marks the extraction point. From that tag forward, this repository is Caspian-only.

## Lightweight

Caspian is kept under **1 MB** — engine, standard library, and docs all together. That would fit on an old 3.5" floppy disk with room to spare.

The Caspian engine is written in [**Lua**](https://www.lua.org/), itself a famously lightweight and transportable language.

## The Caspian community

Caspian is guided by four core principles:

- **Caspian is easy.**
- **The Caspian community is friendly.**
- **Software shouldn't tell you how to live your life.**
- **Everything doesn't have to be complicated.**

## Reading the docs

Start with the **[project overview](https://puck.uno/documentation/overview)** for an end-to-end tour.
