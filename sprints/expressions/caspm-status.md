~~~vibecode
{"doc": "sprint-status-note", "sprint": "expressions",
	"role": "What the current production transpiler + normalizer already produce in the shape the sprint's design assumes, and what still needs updating. Reference for implementers before starting the walker. Findings gathered by running the transpiler + normalizer against sample sources; see [caspianj](https://puck.uno/requirements/caspianj) for the current CaspJ / CaspM spec."}
~~~

# CaspM support status

The sprint's design assumes every command reduces to a tree of `method_call` invocations — every apparent binary operator is sugar over dot method dispatch. This doc catalogs what the current production transpiler + normalizer already produce in that shape and what still needs updating before the walker can consume everything uniformly.

## Already works — no changes needed

| Source | CaspM shape | Notes |
|---|---|---|
| `$foo.bar(1, 2)` | `[{"in":"fc"}, {"rc": $foo, "fn": "bar", "a": [{"v":1}, {"v":2}]}]` | Dot method call — already `fc`. |
| `1 + 2` (in expression position) | `[{"in":"fc"}, {"rc": {"v":1}, "fn": "+", "a": [{"v":2}]}]` | Arithmetic normalizes to `fc`. Method on left operand. |
| `5 < 10` | `[{"in":"fc"}, {"rc": {"v":5}, "fn": "<", "a": [{"v":10}]}]` | Comparison — same as arithmetic. |
| `&foo(x)` | `[{"in":"fc"}, {"rc": {"var":"foo"}, "fn": "call", "a": [{"var":"x"}]}]` | Amp-call — normalizes to `fc` with `fn: "call"`. |

The general story: whatever collapses to a dot-binop in CaspJ gets normalized to an `fc` atom in CaspM. The receiver-and-method-name shape the sprint's `method_call` primitive expects is exactly what these atoms carry.

## Doesn't work yet — normalizer updates needed

| Source | Current CaspM | Should be |
|---|---|---|
| `$a \\|\\| $b` | `{"op": "\|\|", "left": $a, "right": $b}` — unresolved op atom | `[{"in":"fc"}, {"rc": $a.obj, "fn": "or", "a": [<closure→$b>]}]` |
| `$a && $b` | `{"op": "&&", "left": $a, "right": $b}` — unresolved op atom | `[{"in":"fc"}, {"rc": $a.obj, "fn": "and", "a": [<closure→$b>]}]` |
| `if $foo then A else B end` | `{"if": {"conditions": [...], "else": ...}}` — special tree atom | `[{"in":"fc"}, {"rc": engine, "fn": "if", "a": [<closure→$foo>, <closure→A>, <closure→B>]}]` |
| `$foo ? 1 : 0` | parse failure | `[{"in":"fc"}, {"rc": engine, "fn": "if", "a": [<closure→$foo>, <closure→1>, <closure→0>]}]` — same primitive as keyword `if` |

The normalizer already collapses arithmetic and comparison binops to `fc`. Extending the same collapse to `||`, `&&`, and the `if` keyword form is the remaining work. Two rewrite shapes depending on the construct's category:

- **Binary operators** (`||`, `&&`) — turn the op atom into an `fc` with `rc: <left>.obj`, `fn: "<name>"`, `a: [<closure for the right operand>]`. Left is the eager receiver; right is a lazy closure.
- **Standalone commands** (`if` keyword, and eventually `while` / `until` / `for` / etc.) — turn the special tree atom into an `fc` with `rc: engine`, `fn: "<name>"`, `a: [<closures for all args>]`. All args are lazy closures; the engine primitive drives evaluation order.

The closure-wrapping of args is the new mechanism. Currently the normalizer doesn't produce closure atoms for lazy positions; it just leaves the right operand as an unresolved atom in `right`. The wrapping needs to happen at norm time so the walker sees closures uniformly.

## Doesn't parse yet — transpiler updates needed

| Source | Status |
|---|---|
| `$foo ? 1 : 0` | Parse failure — transpiler doesn't recognize `? :` syntax at all. |

The ternary needs both:

- **Transpiler support** — recognize `? :` as a source-level construct and produce a CaspJ atom for it (probably a three-slot atom carrying the condition, then-branch, and else-branch as sub-expressions).
- **Normalizer support** — collapse that atom to an `fc` on `engine.if` (same primitive as the keyword `if` form), wrapping all three sub-expressions as closures.

## What the walker needs from CaspM

The sprint's [evaluation-model](./evaluation-model) walker consumes only `fc` atoms plus a small set of leaf atoms (`v` for literals, `var` for variable references, `assign` shape for `$x = ...`, closure atoms for lazy args). Everything the walker dispatches goes through `method_call`. Every source-level construct not yet in `fc` shape is a normalizer gap that would force the walker to special-case.

The order-of-work implication: the normalizer updates land before (or alongside) the walker so the walker never needs to know about `{op: "||"}`, `{if: {...}}`, or any other non-`fc` shape. One dispatch primitive, one atom shape.

## How to reproduce the findings

The commands used to gather this table:

    lua5.4 -e "
    local home = os.getenv('HOME')
    package.path = home .. '/.luarocks/share/lua/5.4/?.lua;'
    	.. home .. '/.luarocks/share/lua/5.4/?/init.lua;'
    	.. 'production/src/engine/?.lua;'
    	.. package.path
    package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

    local t  = require('transpiler')
    local n  = require('normalize')
    local dk = require('dkjson')

    for _, src in ipairs({...}) do
    	print('src:   ' .. src)
    	local ok, r = pcall(t.transpile, src)
    	if ok then print('caspm: ' .. dk.encode(n.normalize(r)))
    	else       print('parse-fail: ' .. tostring(r))
    	end
    	print()
    end
    "

Substitute the source strings of interest; the output is the normalizer's CaspM for each.

## Related

- [caspianj](https://puck.uno/requirements/caspianj) — spec for the current CaspJ / CaspM formats.
- [evaluation-model](./evaluation-model) — walker's assumptions about what CaspM looks like at dispatch time.
- [primitives/method-call](./primitives/method-call) — the dispatch primitive whose atom-shape assumptions this doc catalogs.
