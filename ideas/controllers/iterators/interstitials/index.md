# Interstitials

~~~vibecode
{"vibecode": {
	"doc": "ideas_iterators_interstitials",
	"role": "spitball space for loop interstitials. Interstitials are the loop-lifecycle hooks (before / between / after / noloop) that fire around iterations. Deferred earlier and now back in scope alongside the iterator-controller model; this file works out the target surface shape (the ~name sugar over attach(NAME)) and how primitive loops route the attached blocks to the iterator. The Lua base-class machinery that actually dispatches the interstitials lives in ideas/controllers/iterators/repeatable.",
	"status": "spitballing 2026-08-06 — target shape captured; mechanism handed off to the Repeatable page"
}}
~~~

## The target shape

Interstitial blocks written as siblings after the main loop; each opens with a `~name` prefix and closes with its own `end`. Each attaches to the immediately preceding loop.

~~~caspian
while(&something)
	# do something
end

# something that happens before the first loop *if there is one*
~before
	# do something
end

# something that happens between two loops
# never happens on one or zero loops
~between
	# do something
end

# something that happens after the last loop *if there were any loops*
~after
	# do something
end

# something that happens *if there were no loops*
~noloop
	# do something
end
~~~

## Named do blocks

Caspian currently supports passing multiple `do` blocks to a single call by writing them as consecutive trailing forms. The first block follows the call's parentheses; each subsequent block follows the previous block's `end`. Inside the method, `%call.blocks[0]` is the first block, `%call.blocks[1]` the second, and so on — they're addressed by index.

~~~caspian
$foo.read() do($row)
	# first closure
end

do()
	# second closure that can be called
end
~~~

### Proposed shape change

Named attached blocks after a call — each opens with `attach(NAME)` and closes with its own `end`. Instead of addressing blocks by index (`%call.blocks[0]`, `[1]`, ...), the receiving method addresses them by name.

~~~caspian
$library.read(&something)
	# do something
end

attach('shakespeare')
end

attach('narnia')
end
~~~

Arguments after the name are the closure's params — bound to the values the receiving method passes when it invokes the block:

~~~caspian
attach('shakespeare', $play, $character)
end
~~~

Sugar: `~name` is shorthand for `attach(:name)`. The following are equivalent:

~~~caspian
while ($record = $query.read)
end

~before
end
~~~

## Named blocks as used with iterators

This section posits the shape change proposed above — named attached blocks via `attach(NAME)`. Everything below assumes that mechanism is in place.

### Routing to the iterator

Primitive loops (`while`, `until`, `.each`, `.times`, etc.) recognize a fixed set of interstitial names: `:before`, `:between`, `:after`, `:noloop`. During setup, each primitive loop inspects its own `%call.blocks` for those names; for each one found, it hands the block to its iterator via a registration mechanism (probably a method like `$loop.on(:before, block)`). The iterator fires the registered block at the appropriate lifecycle moment.

Trace with the target-shape example:

- The parser records `~before` (i.e., `attach(:before)`) as an attached block on the outer `while` call.
- `while` runs and creates its iterator (`$loop`).
- During setup, `while` checks its own `%call.blocks[:before]` and finds the block.
- `while` registers it with the iterator: `$loop.on(:before, %call.blocks[:before])`.
- Before the first iteration, `$loop` fires the registered `:before` block.

The exact API for step 3 (how `while` hands the block to the iterator) is an implementation detail — could be `.on(:name, block)`, typed slots like `.before_block = ...`, or an internal hooks hash. The design at this level works regardless.

For nested / user-method cases, the interstitial only fires for the iterator whose primitive loop was directly attached. If the user wants an interstitial to reach a deeper iterator (like the one inside a `.records` method that internally wraps a while), the receiving method has to explicitly forward — matching the "controller must be explicitly passed down the call stack" principle in the iterators doc.

### Working example

A concrete end-to-end trace with `~before`, `~between`, and `~after` attached to an `.each` loop over an array. The Caspian source:

~~~caspian
$fruits = ['apple', 'banana', 'cherry']

$fruits.each() do($fruit)
	$stdout.print $fruit
end

~before
	$stdout.print 'starting'
end

~between
	$stdout.print '---'
end

~after
	$stdout.print 'done'
end
~~~

Expected output:

~~~
starting
apple
---
banana
---
cherry
done
~~~

What happens on the Lua side:

- The parser records four blocks on the `.each` call: `blocks[0]` is the primary `do($fruit) ... end` block; `attached[:before]`, `attached[:between]`, and `attached[:after]` are the three sibling `~name` blocks.
- `.each` runs and constructs an `ArrayRepeatable` over `$fruits` (see [the base Repeatable class § Example: iterating an array](https://www.puck.uno/ideas/controllers/iterators/repeatable#example-iterating-an-array)).
- `.each` hands `%call` to the shared `looper` on `ArrayRepeatable` — no per-primitive registration code needed, the looper reads `call.attached` directly.
- Iteration 1: `get_next` returns `'apple'`. `first_loop_done` is false, so the looper fires `attached[:before]` (`'starting'`), then flips the flag, then yields to `blocks[0]` (`'apple'`).
- Iteration 2: `get_next` returns `'banana'`. `first_loop_done` is true, so the looper fires `attached[:between]` (`'---'`), then yields (`'banana'`).
- Iteration 3: `get_next` returns `'cherry'`. Same path as iteration 2 — fires `attached[:between]` (`'---'`), then yields (`'cherry'`).
- `get_next` returns `nil`, breaking out of the while loop.
- `first_loop_done` is true, so the looper fires `attached[:after]` (`'done'`). `attached[:noloop]` is not fired (the array was non-empty).

If `$fruits` had been an empty array, `get_next` would have returned `nil` on the very first call, no yields would have happened, `first_loop_done` would still be false at the end, and the looper would fire `attached[:noloop]` instead of `:before` / `:between` / `:after`.

## Related

- [the base Repeatable class](https://www.puck.uno/ideas/controllers/iterators/repeatable) — the Lua base class every primitive loop shape inherits from, the shared looper machinery that dispatches interstitials, and the `LoopBreak` / `LoopNext` exception classes.

