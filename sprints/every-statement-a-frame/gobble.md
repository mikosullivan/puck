~~~vibecode
{"doc": "sprint-note", "sprint": "every-statement-a-frame",
	"role": "Design pattern: the AST at rest is what's left to execute. Executed nodes are deleted; the tree shrinks as the program runs. 'Current' is derived from tree structure, not stored on any node. Linear programs, conditionals, sequences all fall out cleanly; loops need a template mechanism to complement the pattern."}
~~~

# The gobble pattern

The pattern:

> **The AST at rest is what's left to execute.**

Nothing tracks "we're on statement 5 of 12." Statements 1-4 are gone. Statement 5 is the next leaf in the tree. Whatever's above it in the tree is scaffolding for what comes after.

## Linear case

A straight sequence:

~~~caspian
puts "foo"
puts "bar"
puts "ok"
~~~

Load-time tree: a block with three statement children, in order.

Execute the first statement. Delete it. The tree now has two children. Execute the first (was second). Delete it. One child. Execute, delete. Block has no children — delete the block. Program done.

At any moment, look at the tree and you see exactly what's left. "Current" is whatever's at the top of the tree waiting to be run — no flag needed.

## Nested case: if/else

~~~caspian
if foo
    puts 'foo'
else
    puts 'bar'
end
~~~

Load-time tree: an `if` node with three children — the condition (`foo`), the then-branch (`puts 'foo'`), and the else-branch (`puts 'bar'`).

Execution goes:

1. Walker picks the leftmost live leaf inside the `if`: the condition. Executes it. It produces true or false.
2. The condition leaf is deleted; its result lands somewhere the `if` can read it (a slot on the `if` node, or a small marker attached to it).
3. The `if` handler runs next. It reads the result and drops the unselected branch — if the condition was true, the else-branch subtree is deleted; if false, the then-branch is deleted.
4. The `if` is now a node with a single remaining child — the branch that was taken. From the outside, it looks like any other container with one thing inside it.
5. Walker traverses into that one child, executes it, deletes it.
6. The `if` now has no children. Delete the `if`. Control returns to whatever contained the `if`.

After each step, the tree at rest is a valid representation of "what's left." A crash-and-resume just picks the tree back up.

Note the recursive property: at step 4, an `if` with one remaining branch is *structurally indistinguishable* from any other container with one child. The walker doesn't need "am I inside an if?" logic — it just walks.

## What the pattern gives you

- **No `current_frame` flag.** Traversal order plus tree shape tells you what's next.
- **No stmt_idx counter.** The absence of executed nodes IS the position.
- **Resume-safety is automatic.** The at-rest tree is the complete state.
- **Uniform walker.** "Find the next leaf, dispatch by kind, delete when done" — no per-kind traversal rules; kinds only decide what happens when their leaves are reached.

## Where it doesn't naturally cover

Loops. A `while` body has to execute more than once, but the pattern deletes it after one iteration. Some template-and-instance mechanism has to sit alongside gobble — the loop keeps an immutable template subtree; each iteration clones a fresh instance for consumption. That's not fatal, just extra machinery that straight-line and conditional code doesn't need.
