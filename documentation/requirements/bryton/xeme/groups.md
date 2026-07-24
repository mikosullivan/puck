# Xeme groups

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_xeme_groups",
	"role": "spec for the group form of a Xeme — a xeme that has a `nested` field and holds any number of child xemes. Covers what makes a xeme a group, the recursive nesting model, and the rule that a group's success is derived from its children (a parent cannot be more successful than any child).",
	"status": "spec in progress — group form and success-derivation rule settled; the empty-`nested` cases beyond the explicit-false abend case are intentionally left undefined",
	"audience": "anyone producing or consuming Xeme groups"
}}
~~~

A xeme is a **group** if it has the `nested` field:

~~~json
{
	"success": null,
	"nested": []
}
~~~

## Nesting

A group has any number of nested xemes. Those child xemes can themselves be groups or [tests](./) — the format is recursive, so a tree of groups can nest arbitrarily deep.

A xeme nested three deep — a top-level group containing a group, which contains a group, which contains a test:

~~~json
{
	"success": true,
	"nested": [
		{
			"success": true,
			"nested": [
				{
					"success": true,
					"nested": [
						{
							"success": true
						}
					]
				}
			]
		}
	]
}
~~~

## Success is derived from children

A group's `success` is calculated from the successes of its child xemes. The rule is that **a parent cannot be more successful than any child**.

Concretely, for a group with at least one child:

- Any child is `false` → the group is `false`.
- Any child is `null` (and no child is `false`) → the group is `null`.
- Every child is `true` → the group is `true`.

## Empty `nested`

The rules above don't apply to a group with no children — there's nothing to derive from. The producer sets `success` explicitly.

The primary case for this is an **explicit failure**: a group that was supposed to have children but didn't produce any. For example, if an executable file holds a group of tests but the file abends before enumerating them, the group itself reports as an explicit `false`.

~~~json
{
	"success": false,
	"nested": []
}
~~~

Other combinations of empty `nested` with a non-`false` `success` are unusual and their behavior isn't specified here. A rule will be added if a real use case surfaces.

## Classes

The classes below are the ones Bryton ships and understands out of the box. **This is not an exhaustive list** — the community may develop more group classes as needs arise. New classes follow the same URL-style slash convention (`group/foo`, `group/foo/bar`) and drop their own icons under `icons/tests/group/`.

### Base class

<img src="./icons/tests/group.svg" width="32" height="32" alt="group icon" style="float: left; margin: 0 12px 4px 0;" />

The base group class is **`group`**.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group",
	"nested": []
}
~~~

### Directory group

<img src="./icons/tests/group/dir.svg" width="32" height="32" alt="group/dir icon" style="float: left; margin: 0 12px 4px 0;" />

A **`group/dir`** groups tests by directory.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group/dir",
	"nested": []
}
~~~

### File group

<img src="./icons/tests/group/file.svg" width="32" height="32" alt="group/file icon" style="float: left; margin: 0 12px 4px 0;" />

A **`group/file`** groups tests by file.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group/file",
	"nested": []
}
~~~

Language extensions can appear as further subclasses of `group/file` — for example, `group/file/py` for Python test files or `group/file/casp` for Caspian ones.

### Remote group

<img src="./icons/tests/group/remote.svg" width="32" height="32" alt="group/remote icon" style="float: left; margin: 0 12px 4px 0;" />

A **`group/remote`** holds tests that were retrieved over the network.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group/remote",
	"nested": []
}
~~~

### Subprocess group

<img src="./icons/tests/group/subprocess.svg" width="32" height="32" alt="group/subprocess icon" style="float: left; margin: 0 12px 4px 0;" />

A **`group/subprocess`** holds tests that were run in a fork of the main process.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group/subprocess",
	"nested": []
}
~~~

### Timer group

<img src="./icons/tests/group/timer.svg" width="32" height="32" alt="group/timer icon" style="float: left; margin: 0 12px 4px 0;" />

A **`group/timer`** times a group of tests.

<div style="clear: both;"></div>

~~~json
{
	"success": null,
	"class": "group/timer",
	"nested": []
}
~~~
