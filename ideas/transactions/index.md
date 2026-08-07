# Transactions

~~~vibecode
{"vibecode": {
	"doc": "ideas_transactions",
	"role": "sketch for Caspian's transaction feature. Block-form yields a transaction object; the block returns the transaction as its value. Rollback is data-typed — `.debug` slot captures developer info, `.committed?` predicate reports outcome. Optional `catch: true` keyword makes the block a fault-protection boundary: uncaught exceptions inside cause rollback and are captured on the transaction for inspection; execution continues past the block instead of unwinding.",
	"audience": "Caspian programmers wrapping state changes; engine implementers building the transaction primitive",
	"key_concepts": ["block_form", "transaction_as_result", "debug_slot",
		"rollback_halts_block", "catch_true_keyword", "fault_protection_boundary",
		"retry_pattern", "mikobase_overlap"],
	"status": "sketch 2026-08-07"
}}
~~~

Caspian's transaction feature is a block-form that returns a transaction object. State on that object tells the caller what happened — did it commit, was it rolled back, what did the developer note about it, was there an uncaught exception. Nothing about the outcome is exception-based; the transaction result is data the caller inspects and dispatches on.

## Basic form

The block-form yields the transaction, binds it to a name inside the block, and evaluates to that transaction after:

~~~caspian
$tr = transaction as $transaction
	&do_stuff
	&do_more_stuff
end

$tr.committed?    # true
~~~

Reads: "start a transaction bound to `$transaction`; run the block; the block's result is the transaction object." If the block completes without calling `.rollback`, the transaction commits. `$tr.committed?` returns true.

## Rollback

Inside the block, calling `.rollback` marks the transaction to roll back. The block halts execution at the `.rollback` call — subsequent statements in the block do not run. When control returns to the caller, the DB state is rolled back and `.committed?` returns false.

~~~caspian
$tr = transaction as $transaction
	if not $valid
		$transaction.debug = 'validation failed'
		$transaction.rollback
	end

	&this_never_runs_if_rollback_was_called
end

$tr.committed?    # false
$tr.debug         # 'validation failed'
~~~

`.debug` is an orthogonal slot for developer-facing context. It can hold any value — a string, a hash of structured info, whatever helps the caller understand what happened. Setting it is optional and unrelated to rollback — a committed transaction can carry debug info too.

## The transaction object

The object returned by the block exposes:

- **`.committed?`** — true if the transaction committed, false if it rolled back.
- **`.debug`** — whatever the developer set inside the block; null if never set.
- **`.exception`** — when `catch: true` is in effect, holds the uncaught exception that was captured; null otherwise. See [fault protection](#fault-protection).

Additional accessors may grow as the design settles.

## Fault protection

The `catch: true` keyword argument turns the transaction into a fault-protection boundary. Any uncaught exception that would otherwise escape the block is caught, the transaction is rolled back, the exception is captured on the transaction, and execution continues after the block.

~~~caspian
$tr = transaction(catch: true) as $transaction
	&risky_operation
end

if $tr.committed?
	# clean success
elsif $tr.exception.null?
	# explicit rollback — inspect $tr.debug
else
	# uncaught exception was captured — inspect $tr.exception
end
~~~

The keyword form documents the block's behavior at the top, before any body code runs. A reader knows "this block handles its own exceptions" as soon as they see the header, not after they've dug through the block looking for a `try / catch`.

Without `catch: true`, uncaught exceptions propagate normally — the transaction rolls back on its way up the stack, but the caller doesn't get a transaction object to inspect.

**Inner `try / catch` composes naturally.** If code inside the block catches an exception before it escapes, the transaction never sees it — the transaction only captures exceptions that actually left the block uncaught.

## The retry pattern

Fault protection composes with an ordinary loop to give a retry primitive:

~~~caspian
$attempt = 0

loop
	$tr = transaction(catch: true) as $t
		&risky_operation
	end

	if $tr.committed?
		break
	end

	$attempt = $attempt + 1

	if $attempt >= 3
		raise 'gave up after 3 tries: %$tr.exception'
	end
end
~~~

No separate retry framework — the primitives compose. Circuit breakers, speculative execution, and other resilience patterns extend from the same shape.

## What "all" catches

The `catch: true` behavior catches ordinary exceptions raised by user code. Fatal-level exceptions — engine panics, out-of-memory, forced shutdown — propagate through the boundary regardless, because the engine may not be in a state to cleanly capture them and pretending to recover would mask a real problem.

The exact set of "user exceptions vs. fatal-level" awaits the exceptions system spec.

## Overlap with Mikobase

Transactions with fault protection start to look like the primitives Mikobase would need for durable session semantics — atomic writes, rollback on failure, data-typed outcomes to inspect. If Drinian and Mikobase share the storage substrate (per [[project_caspian_mikobase_shared_class_definitions]]), transactions here may become transactions there.

For now: track this as a Drinian-runtime feature. Note the overlap; consolidate when the Mikobase spec gets serious.

## Open questions

- **Rollback halting.** The `.rollback` call halts block execution — subsequent statements don't run. This is the sketch's working assumption; formal test cases will pin it down.
- **Field name for the captured exception.** Currently `.exception`. Alternatives: `.uncaught`, `.error`, `.raised`. Not chosen.
- **Fatal exception boundary.** Which exception classes propagate through `catch: true` vs. get captured. Depends on the exceptions system spec.
- **Interaction of explicit `.rollback` with a later raise.** If code calls `.rollback` and the halting semantic is right, this can't happen — the rollback halts the block. If halting isn't the semantic, first-past-the-post is probably the rule.
- **Nested transactions.** Whether a transaction inside a transaction is a savepoint, a no-op, an error, or something else. Not addressed here.
- **Multiple `.debug` calls.** Last-write-wins is the natural default (like any slot assignment). If aggregation is wanted, a helper method like `.debug_append` could be added.
