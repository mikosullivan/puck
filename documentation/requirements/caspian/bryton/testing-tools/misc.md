# Misc test tools

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_bryton_testing_tools_misc",
	"role": "spec for miscellaneous test-tool methods that don't fit under the basic-tests or groups categories. Sibling of basic/index.md and groups.md.",
	"status": "stub — content pending",
	"audience": "test authors reaching for less-common tools"
}}
~~~

Miscellaneous test-tool methods that don't fit under the [basic tests](basic/) or [groups](groups) categories.

## `$bryton.succeed`

Adds an unconditional success xeme.

~~~caspian
$xeme = $bryton.succeed
$xeme = $bryton.succeed 'Test name'
~~~

## `$bryton.fail`

Adds an unconditional failure xeme.

~~~caspian
$xeme = $bryton.fail
$xeme = $bryton.fail 'Test name'
~~~

## `$bryton.test`

Adds an unpopulated test xeme — no success/failure decision made, no result set. The caller fills in the xeme's fields directly.

~~~caspian
$xeme = $bryton.test
$xeme = $bryton.test 'Test name'
~~~
