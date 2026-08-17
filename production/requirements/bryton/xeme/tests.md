# Xeme tests

~~~vibecode
{"vibecode": {
	"doc": "requirements_bryton_xeme_tests",
	"role": "spec for the test form of a Xeme — a xeme without a `nested` field. Sibling of groups.md. Covers the single test class (`test`) currently spec'd.",
	"status": "spec in progress — base test class settled; more classes may join as they emerge",
	"audience": "anyone producing or consuming Xeme tests"
}}
~~~

A xeme is a **test** if it does NOT have a `nested` field. It reports the result of a single verifiable operation.

## Classes

For now there is only one test class.

### Base class

<img src="./icons/tests/test.svg" width="32" height="32" alt="test icon" style="float: left; margin: 0 12px 4px 0;" />

The base test class is **`test`**.

<div style="clear: both;"></div>

~~~json
{
	"success": true,
	"class": "test"
}
~~~
