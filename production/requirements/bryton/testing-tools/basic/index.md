# Basic test tools

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_testing_tools_basic",
	"role": "spec for Bryton's basic test-authoring tools — the everyday primitives a test file uses to declare tests, make assertions, and produce a xeme. Sibling of runner/ and xeme/. Being spec'd from scratch.",
	"status": "stub — content pending",
	"audience": "test authors writing Bryton-runnable tests in Caspian"
}}
~~~

The **basic test tools** are the everyday primitives a test file reaches for — declaring individual tests, making assertions, and building the xeme the [runner](../../runner/) will read.

## Test name

Every test method on `$bryton` follows the same parameter convention:

- The **first param is optional and is the name of the test** — a human-readable label. When present, it becomes the [`name`](../../xeme/#name) field on the test's xeme.
- **Remaining params are defined by each type of test.** Different test methods take different arguments (a value to check, an expected value, a block of code, etc.), spec'd per method.

Because the first param is optional, a caller can pass a name or omit it; the rest of the arguments carry the test's actual content either way.

## Timeouts

`$bryton.timeout` sets time limits for the tests that follow. Same shape as the hash form of the [`timeout`](../../runner/bryton-json/#timeout) field in `bryton.json`:

~~~caspian
$bryton.timeout limit: 10, warning: 1
~~~

- **`limit`** — hard limit in seconds. If reached, the run is marked as [timed out](../../xeme/results/failure#timed-out).
- **`warning`** — soft limit in seconds. If reached, a warning is added to the xeme.

**At least one of `limit` or `warning` must be given.** Both are optional individually — pass just `limit`, just `warning`, or both — but calling `.timeout` with neither is meaningless.

## Assertions

### `$bryton.assert`

Passes when the given value is truthy. Fails when it's falsy.

~~~caspian
$bryton.assert $foo
$bryton.assert 'Foo test', $foo
~~~

- With no name, the test carries only the assertion.
- With a name, the string becomes the test's [`name`](../../xeme/#name).

### `$bryton.refute`

The mirror of `.assert`. Passes when the value is falsy. Fails when it's truthy.

~~~caspian
$bryton.refute $bar
$bryton.refute 'Bar test', $bar
~~~

## Null checks

### `$bryton.defined`

Passes when the value is not null.

~~~caspian
$bryton.defined $foo
$bryton.defined 'Foo defined', $foo
~~~

### `$bryton.null`

Passes when the value is null.

~~~caspian
$bryton.null $foo
$bryton.null 'Foo null', $foo
~~~

## Comparisons

Two-value tests. Each takes an optional name (per the [signature convention](#test-name)) followed by the two values to compare.

**Argument order: actual first, then expected.** This follows Python's convention (`unittest.assertEqual(actual, expected)`, `assert actual == expected` in pytest). Some other-language frameworks reverse this (Ruby's Test::Unit, JUnit historically); Bryton picks the Python order.

### `$bryton.eq`

Passes when the two values are equal.

~~~caspian
$bryton.eq $actual, $expected
$bryton.eq 'Test name', $actual, $expected
~~~

### `$bryton.ne`

Passes when the two values are not equal.

~~~caspian
$bryton.ne $actual, $unwanted
$bryton.ne 'Test name', $actual, $unwanted
~~~

### `$bryton.gt`

Passes when the first value is greater than the second.

~~~caspian
$bryton.gt $actual, $threshold
$bryton.gt 'Test name', $actual, $threshold
~~~

### `$bryton.gte`

Passes when the first value is greater than or equal to the second.

~~~caspian
$bryton.gte $actual, $floor
$bryton.gte 'Test name', $actual, $floor
~~~

### `$bryton.lt`

Passes when the first value is less than the second.

~~~caspian
$bryton.lt $actual, $ceiling
$bryton.lt 'Test name', $actual, $ceiling
~~~

### `$bryton.lte`

Passes when the first value is less than or equal to the second.

~~~caspian
$bryton.lte $actual, $ceiling
$bryton.lte 'Test name', $actual, $ceiling
~~~

### `$bryton.approximate`

Passes when the actual value is within `$tolerance` of the expected value.

~~~caspian
$bryton.approximate $actual, $expected, $tolerance
$bryton.approximate 'Test name', $actual, $expected, $tolerance
~~~

## Collections

### `$bryton.empty`

Passes when the collection has zero elements.

~~~caspian
$bryton.empty $collection
$bryton.empty 'Test name', $collection
~~~

### `$bryton.any`

Passes when the collection has at least one element.

~~~caspian
$bryton.any $collection
$bryton.any 'Test name', $collection
~~~

### `$bryton.includes`

Passes when `$collection` contains `$item`.

~~~caspian
$bryton.includes $collection, $item
$bryton.includes 'Test name', $collection, $item
~~~

## Patterns

### `$bryton.matches`

Passes when the string matches the regex.

~~~caspian
$bryton.matches $string, $regex
$bryton.matches 'Test name', $string, $regex
~~~

## Type checks

### `$bryton.isa`

Passes when the object is an instance of the given class.

~~~caspian
$bryton.isa $object, $class
$bryton.isa 'Test name', $object, $class
~~~

## Exceptions

### `$bryton.raises`

Passes when the block raises an exception whose class matches one of the given exception classes.

~~~caspian
$bryton.raises($exception_class_1, $exception_class_2, ...) do
	# code that should raise
end
~~~

Returns the xeme.

To also get the xeme via a `do` block, pass a second trailing block:

~~~caspian
$bryton.raises($exception_class_1, $exception_class_2, ...) do
	# code that should raise
end

do($xeme)
	# use $xeme
end
~~~

## Getting the xeme from a test

The test **returns** the [xeme](../../xeme/class). It also **yields** the xeme to an optional `do` block.

As a return value:

~~~caspian
$xeme = $bryton.assert($foo)
~~~

As a `do` block:

~~~caspian
$bryton.assert($foo) do($xeme)
	# use $xeme here
end
~~~

Tests that do **not** yield a block have that noted in their own documentation.
