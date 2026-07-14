# Test groups

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bryton_testing_tools_groups",
	"role": "spec for how test authors declare groups of tests using the Bryton testing tools — the runtime API that produces group xemes in the emitted result. Distinct from xeme/groups.md, which specs the JSON shape of a group xeme.",
	"status": "stub — content pending",
	"audience": "test authors organizing tests into groups within a Caspian test file"
}}
~~~

Test groups let a test author organize related tests together under a single named parent. Each group produces a [group xeme](../../xeme/groups) in the emitted result.

## `$bryton.group`

`.group` creates a nested group. The returned group has the **same test methods as `$bryton`** — `eq`, `assert`, `refute`, all the rest — so tests declared on it become children of the group rather than direct children of the file.

Two forms.

As a return value:

~~~caspian
$group = $bryton.group
$group.eq 1, 1
~~~

As a `do` block:

~~~caspian
$bryton.group do($group)
	$group.eq 1, 1
end
~~~

Groups nest to any depth:

~~~caspian
$bryton.group do($group)
	$group.eq 1, 1

	$group.group do($nested)
		$nested.eq 2, 2
	end
end
~~~
