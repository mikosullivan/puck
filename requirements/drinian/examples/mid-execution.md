# Mid-execution with nested frames

~~~vibecode
{"vibecode": {
	"doc": "requirements_drinian_examples_mid_execution",
	"role": "worked Drinian snapshot: function call inside if inside do-block inside method call inside top level, with the canonical references and objects tables that back Caspian's deterministic garbage collection",
	"status": "draft — V1.0-capable program shape; representation is the authoritative full form (main drinian doc uses inline-value shorthand for readability)"
}}
~~~

A program in mid-execution with a function call nested inside an if-block inside a do-block inside a method call. Demonstrates role alternation, `lexical_parent` divergence at the function call, outer-scope variable mutation from inside an inner scope, and the canonical `references` + `objects` representation that backs Caspian's deterministic garbage collection (see [drinian/references](https://puck.uno/requirements/drinian/references)).

Caspian source:

~~~caspian
function &greet($who)
	$msg = 'hello, ' + $who
	# CAPTURED HERE
	return $msg
end

$names = ['Aslan', 'Bree']
$count = 0

$names.each($name) do
	if $name == 'Aslan'
		$count = $count + 1
		$title = 'Lord '
		puts $title + &greet($name)
	end
end
~~~

Paused inside `greet` on the first iteration, after `$msg` has been computed but before `return` fires.

~~~json
{
	"srcs": {
		"a": {"file": "/home/miko/main.casp"}
	},
	"roles": {
		"user": {"bucket": {}},
		"engine": {"bucket": {}}
	},
	"sequence": 29,
	"references": {
		"1": "9",
		"2": "12",
		"3": "10",
		"4": "13",
		"5": "10",
		"6": "14",
		"7": "10",
		"8": "11"
	},
	"objects": {
		"1": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"15": {"class": "core:variable", "bucket": {}}
			}
		},
		"2": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"16": {"class": "core:variable", "bucket": {}}
			}
		},
		"3": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"17": {"class": "core:variable", "bucket": {}}
			}
		},
		"4": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"18": {"class": "core:variable", "bucket": {}}
			}
		},
		"5": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"19": {"class": "core:variable", "bucket": {}}
			}
		},
		"6": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"20": {"class": "core:variable", "bucket": {}}
			}
		},
		"7": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"21": {"class": "core:hash_element", "bucket": {"parent": "9", "key": 0}}
			}
		},
		"8": {
			"role": "user",
			"bucket": {},
			"stack": {
				"shadow": {},
				"22": {"class": "core:hash_element", "bucket": {"parent": "9", "key": 1}}
			}
		},
		"9": {
			"role": "user",
			"src": ["a", 6],
			"bucket": {"0": "7", "1": "8"},
			"stack": {
				"shadow": {},
				"23": {"class": "core:array"}
			}
		},
		"10": {
			"role": "user",
			"src": ["a", 6],
			"bucket": {"value": "Aslan"},
			"stack": {
				"shadow": {},
				"24": {"class": "core:string"}
			}
		},
		"11": {
			"role": "user",
			"src": ["a", 6],
			"bucket": {"value": "Bree"},
			"stack": {
				"shadow": {},
				"25": {"class": "core:string"}
			}
		},
		"12": {
			"role": "user",
			"src": ["a", 11],
			"bucket": {"value": 1},
			"stack": {
				"shadow": {},
				"26": {"class": "core:number"}
			}
		},
		"13": {
			"role": "user",
			"src": ["a", 12],
			"bucket": {"value": "Lord "},
			"stack": {
				"shadow": {},
				"27": {"class": "core:string"}
			}
		},
		"14": {
			"role": "user",
			"src": ["a", 2],
			"bucket": {"value": "hello, Aslan"},
			"stack": {
				"shadow": {},
				"28": {"class": "core:string"}
			}
		}
	},
	"call_stack": [
		{
			"action": "top_level",
			"role": "user",
			"lexical_parent": null,
			"src": ["a", 9],
			"locals": {"names": "1", "count": "2"}
		},
		{
			"action": "method_call",
			"role": "engine",
			"receiver_type": "array",
			"method": "each",
			"iterator": {"position": 0, "of": 2},
			"lexical_parent": null,
			"src": null,
			"locals": {}
		},
		{
			"action": "block",
			"role": "user",
			"lexical_parent": 0,
			"src": ["a", 10],
			"locals": {"name": "3"}
		},
		{
			"action": "if_block",
			"role": "user",
			"lexical_parent": 2,
			"src": ["a", 13],
			"locals": {"title": "4"}
		},
		{
			"action": "function_call",
			"role": "user",
			"function": "greet",
			"lexical_parent": 0,
			"src": ["a", 3],
			"locals": {"who": "5", "msg": "6"}
		}
	],
	"pending_exceptions": [],
	"gc_errors": []
}
~~~

<!-- SPEC CONFLICT: archive uses "stdlib" as the role for the array.each method_call frame; current spec (roles/index.md) has no stdlib role — V1 has user + engine + one role per engine-provided faucet. Rewritten as "engine" throughout this file; needs Miko decision on which role owns built-in method dispatch (engine? a separate stdlib-equivalent? something else) -->

<!-- SPEC CONFLICT: archive uses "puck.uno/variable", "puck.uno/hash_element", "puck.uno/array", "puck.uno/string", "puck.uno/number" as class identifiers; UNS is dropped per project memory. Rewritten as "core:variable", "core:hash_element", "core:array", "core:string", "core:number" — of these, only "core:variable" appears in current requirements/. The others follow the same pattern but are not yet documented. Needs Miko decision on the naming for the not-yet-documented ones -->

ID legend:

| ID | What it is | Where to look |
|---|---|---|
| `"1"` | variable `$names` (`core:variable`) | named in frame 0's `locals` as `"names"` |
| `"2"` | variable `$count` (`core:variable`) | named in frame 0's `locals` as `"count"` |
| `"3"` | variable `$name` (`core:variable`) | named in frame 2's `locals` as `"name"` |
| `"4"` | variable `$title` (`core:variable`) | named in frame 3's `locals` as `"title"` |
| `"5"` | variable `$who` (`core:variable`) | named in frame 4's `locals` as `"who"` |
| `"6"` | variable `$msg` (`core:variable`) | named in frame 4's `locals` as `"msg"` |
| `"7"` | array element for index 0 (`core:hash_element`) | parent = `"9"`, key = `0` |
| `"8"` | array element for index 1 (`core:hash_element`) | parent = `"9"`, key = `1` |
| `"9"` | the array `['Aslan', 'Bree']` (`core:array`) | top-level bucket maps index → hash_element ID |
| `"10"` | string `'Aslan'` (`core:string`) | value in top-level bucket |
| `"11"` | string `'Bree'` (`core:string`) | value in top-level bucket |
| `"12"` | number `1` (`core:number`) — current `$count` | value in top-level bucket |
| `"13"` | string `'Lord '` (`core:string`) | value in top-level bucket |
| `"14"` | string `'hello, Aslan'` (`core:string`) | born line 2 (the `+` operator's location) |

To resolve a variable: read its name from a frame's `locals` to get a reference ID → look up that ID in `references` to get a target object ID → look up the target in `objects` to see what it is. For example: `$msg` in frame 4's locals is `"6"`; `references["6"]` is `"14"`; `objects["14"]` is the string `"hello, Aslan"` born on line 2.

What to notice:

- **`$count` reads 1, not 0**, and lives in the top_level frame — not in the if-block's locals. The assignment on line 11 walked the lexical chain from inside the if, found `$count` in the top_level frame, and rebound its reference (`"2"`) to point at a freshly-allocated number object (`"12"`, value `1`). The old number (the integer `0` from line 7) lost its incoming pointer and was collected — that's why it doesn't appear in the snapshot. Compare to `$title`, which is a fresh name and lives as a new variable (`"4"`) in the if-block frame.
- **Aliasing is visible in `references`.** The string `"Aslan"` (object `"10"`) has THREE incoming pointers: `$name`'s variable (`"3"`), `$who`'s variable (`"5"`), and the array's element-0 reference (`"7"`). All three resolve to the same string object — the same `src: ["a", 6]` reflects birth at the array literal. Severing any one keeps the object alive through the others.
- **Hash elements are first-class reference objects.** The array's contents are reached through `core:hash_element` objects (`"7"` and `"8"`) whose buckets carry `parent` + `key`. The array object's bucket maps each key to the corresponding element ID, not directly to the target. That's what makes mutation uniform — assigning to `$names[0]` rebinds `references["7"]`; the same machinery as assigning to a hash key.
- **Role alternation:** user → engine → user → user → user. The engine frame is the cross-role hop into `array.each`.
- **`lexical_parent` diverges from the call stack at the `function_call` frame.** Frames 2 and 3 (block, if_block) have `lexical_parent` pointing to their immediate physical ancestor on the stack. Frame 4 (`greet`) has `lexical_parent: 0` — `greet` was defined at top level, not inside the if. From inside `greet`, `$name` and `$title` are NOT visible even though they're physically between `greet`'s frame and the top of the stack.
- **`src` values trace creation lines, not binding lines.** Object `"10"` (the string `"Aslan"`) carries `src: ["a", 6]` because it was born as a string literal on line 6, then passed through the array element ref (`"7"`), the `$name` variable (`"3"`, line 8 binding), and the `$who` variable (`"5"`, line 12 argument). Birth line follows the value because there's only one underlying object.
- **Object `"14"` (`$msg`'s value) carries `src: ["a", 2]`** because the `+` operator on line 2 produced the value. Operator location, not operand birth.
- **Uspace roots are the variable objects.** `core:variable` declares `uspace: true` (per [references § Uspace](https://puck.uno/requirements/drinian/references#uspace-a-class-level-property)), so objects `"1"`–`"6"` ground the program's reachability graph. `core:hash_element` declares `uspace: false`, so `"7"` and `"8"` aren't roots in their own right — they're reachable only because the array (`"9"`) is held by a variable root.
- **Every object record carries `role`** identifying the role that owns it. All 14 objects in this example are user-owned because user code created them. Cross-role allocations (e.g., an engine-role method returning a new object) would carry the allocating role.
- **`sequence` is `29`.** The global object-ID counter (see [references § Object IDs](https://puck.uno/requirements/drinian/references#object-ids)) exposed at the top level so snapshots can resume allocation from the right place. A bare integer starting at `0` at boot and incremented for each object AND each non-shadow platter allocated. Fourteen objects exist (with IDs `"1"`–`"14"`) plus fourteen non-shadow platters (IDs `"15"`–`"28"`); the next allocation will take ID `"29"`.
- **Roles' buckets are empty here.** Elided for focus; see [bootstrap](https://puck.uno/requirements/drinian/examples/bootstrap) for the standard registry with the engine role and stdin/stdout/stderr.
