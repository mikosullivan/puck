# Robinson per-directory `robinson.kscript` handlers

```
vibecode: {
    "status": "paused_2026-05-17_returning_to_issues_walkthrough",
    "started": "2026-05-17",
    "subsystem": "robinson",
    "canonical_location": "ideas/ until firm enough to promote to documentation/kscript/http-middleware/robinson.md",
    "relation_to_other_robinson_features": {
        "embed_target_cascade": "structural_sibling_but_for_kscript_logic_not_html; embed_target_set_aside_for_this_discussion",
        "reserved_prefix_robinson_dot_star": "naturally_blocks_these_from_public_http; reuses_existing_rule"
    },
    "co_authoring": "claude_capturing_miko_brainstorm_in_realtime",
    "resume_here": "the_design_is_pretty_well_developed_through_composition_and_framework_organization; outstanding_decisions_are_yield_vs_next_callable_and_where_handler_placeholder_match_values_come_from"
}
```

Brainstorm paused. Resume points when picking this back up:

- Lock down `yield` vs `$next.call()` (currently leaning to `$next`, not committed)
- Spell out how a placeholder-matched handler reads its matched segment value
- Whether `pass_through` is dir-handler-only or available on any class

---

## Concept

```
vibecode: {
    "section": "concept",
    "what": "per_directory_handler_files_named_robinson_kscript",
    "trigger": "every_request_traversing_a_directory_runs_any_robinson_kscript_in_that_directory",
    "traversal_order": "root_to_leaf",
    "non_public": "automatic_via_existing_robinson_dot_star_reserved_prefix_rule"
}
```

A directory in a Robinson tree may contain a file named
`robinson.kscript`. When a request is processed, each `robinson.kscript`
along the path from the site root to the resolved page file gets a chance
to see the request.

### Traversal

For a request to `/blog/posts/my-post`, the chain along the path is:

1. `/robinson.kscript` (site root) — first.
2. `/blog/robinson.kscript` — next, if present.
3. `/blog/posts/robinson.kscript` — next, if present.
4. The resolved page file — the leaf.

Root sees the request before any descendant. Each `robinson.kscript`
runs in directory order from outer to inner.

Files at intermediate directories without a `robinson.kscript` are
simply skipped — no requirement that every directory have one.

### Non-public by construction

`robinson.kscript` matches the [reserved `robinson.*` prefix rule](../kscript/http-middleware/robinson.md#reserved-filename-prefix-robinson)
that already blocks request-boundary access. These files exist on
disk to be loaded by Robinson, never to be served as URLs.

---

## File shape

```
vibecode: {
    "section": "file_shape",
    "form": "anonymous_class_same_form_as_page_files",
    "base_class_uns": "tbd_likely_kiera_uno_robinson_dir_handler_or_similar",
    "syntax_dependency": "uses_the_bare_anonymous_class_form_per_audit_issue_26; same_syntax_gap_as_page_files; one_fix_covers_both"
}
```

A `robinson.kscript` file follows the same shape as a page file: the
file's last expression is an **anonymous class** that inherits from a
Robinson-supplied base class. The base class for directory handlers is
distinct from `kiera.uno/robinson/page` (working name TBD —
e.g., `kiera.uno/robinson/dir_handler`).

```
class
    inherits 'kiera.uno/robinson/dir_handler'

    function process_request($transaction) do
        # runs as the request travels root -> leaf
    end

    function process_response($transaction) do
        # runs as the response travels leaf -> root
    end

    # more methods TBD
end
```

The syntax depends on the same bare/anonymous `class` form that page
files use, currently flagged in audit issue #26 (kscript.md only
defines `class 'UNS' ... end`). One spec fix covers both.

---

## The two-trip pattern

```
vibecode: {
    "section": "two_trip_pattern",
    "methods_so_far": ["process_request", "process_response"],
    "more_methods": "tbd",
    "request_trip_order": "root_to_leaf_outer_first",
    "response_trip_order": "leaf_to_root_inner_first",
    "shape": "onion_each_dir_handler_wraps_its_descendants",
    "argument_to_process_response": "request_not_response; response_accessible_via_transaction_or_response_reference_same_as_page_files"
}
```

Each `robinson.kscript` exposes two phase methods (more to come):

| Method | Phase | Order along path |
|---|---|---|
| `process_request($transaction)` | Inbound — before the page file runs | Root → leaf (outer first) |
| `process_response($transaction)` | Outbound — after the page file produces a response | Leaf → root (inner first) |

This is the **onion pattern**: every dir handler effectively wraps
its descendants. An outer handler sees the request first and the
response last; an inner handler sees the request last and the response
first.

Both methods take `$request` (not `$response`). The response is
accessible the same way page files access it — via the transaction
or a `response` reference. This keeps the calling convention uniform
across page files and dir handlers.

---

## Framework organization

```
vibecode: {
    "section": "framework_organization",
    "design_goal": "avoid_the_ruby_dogberry_pain_of_optional_yields_interacting_with_optional_pass_through_methods_across_a_chain",
    "diagnosis": "ruby_yield_is_opaque_to_the_caller; framework_cannot_detect_short_circuit_or_thread_state_cleanly_through_yield",
    "two_axes": ["surface_syntax_what_developer_writes",
                 "framework_code_how_dispatcher_orchestrates"],
    "lean": "explicit_next_callable_parameter_over_yield_keyword; lean_only_not_locked_as_of_2026-05-17"
}
```

### Surface syntax: `$next` callable vs `yield`

The Ruby version was painful because `yield` is opaque — the framework
can't tell from outside whether the method yielded, threading state
through `yield` is awkward, and "pass_through is optional" requires
runtime detection that ripples through the dispatcher.

KScript can sidestep all of that by being **explicit**: the framework
passes the inner-chain callable as a parameter, and the handler invokes
it directly.

```
function &pass_through($transaction, $next) do
    # setup
    $next.call()       # explicit invocation; no magic
ensure
    # teardown
end
```

Trade-off:

| Concern | `yield $transaction` | `$next.call()` |
|---|---|---|
| Familiar to Ruby folks | High | Medium (Express/Koa shape) |
| Framework can detect short-circuit | Painful | Trivial (wrap `$next`, track if called) |
| Pass args to inner / capture return | Awkward | Normal |
| Wrap inner with retry / timing / etc. | Painful | Trivial |
| Spec complexity | Need to define `yield` semantics in class methods | Just a callable parameter |

**Current lean: explicit `$next` over `yield`.** Costs a slightly less
elegant surface for tiny handlers; in exchange, loses the entire class
of problems that made the Ruby version awful. **Not locked** — the
original example earlier in this doc uses `yield $transaction`; both
shapes are still on the table.

### Framework code: recursive single-handler step

One function, three method-presence checks, one recursive call:

```
function run_chain($handlers, $page_runner, $transaction) do
    if $handlers.empty? then
        $page_runner($transaction)
        return
    end

    $handler = $handlers.first
    $rest    = $handlers.rest
    $next    = closure() do
        run_chain($rest, $page_runner, $transaction)
    end

    if $handler.has_method?('process_request') then
        $handler.process_request($transaction)
    end

    if $handler.has_method?('pass_through') then
        $handler.pass_through($transaction, $next)
    else
        $next.call()
    end

    if $handler.has_method?('process_response') then
        $handler.process_response($transaction)
    end
end
```

The Ruby ugliness came from trying to coordinate the optionality of
`pass_through` with the optionality of yield-within-`pass_through`
across multiple handlers. Here the dispatcher handles "no
`pass_through` → call inner directly" trivially, and "`pass_through`
doesn't call `$next`" is a developer choice the framework doesn't have
to detect — the chain just stops where it stops.

---

## Composition across handlers

```
vibecode: {
    "section": "composition_across_handlers",
    "shape": "nested_per_handler_each_handler_wraps_everything_below_it",
    "resolved": "2026-05-17"
}
```

When there are multiple `robinson.kscript` handlers along a path, each
one's three methods nest the next one's full sequence inside its own
`pass_through` yield. For a request to `/blog/posts/my-post` with
handlers at `/`, `/blog`, and `/blog/posts` (each implementing all
three methods):

```
root.process_request($transaction)
root.pass_through($transaction):
    # root's setup
    yield ->
        blog.process_request($transaction)
        blog.pass_through($transaction):
            # blog's setup
            yield ->
                posts.process_request($transaction)
                posts.pass_through($transaction):
                    # posts's setup
                    yield ->
                        page.process($transaction)   # the leaf
                    # posts's teardown
                posts.process_response($transaction)
            # blog's teardown
        blog.process_response($transaction)
    # root's teardown
root.process_response($transaction)
```

The shape:

- **`process_request` sees the request before any descendant.** Outer
  handlers can prepare context the inner handlers (and the page) will
  read.
- **`process_response` sees the response after every descendant.** It's
  the last chance to transform output before handing it up to the next
  outer handler.
- **`pass_through` teardown runs after every descendant's full work**
  (including their teardowns and `process_response` calls). Resource
  cleanup with natural `ensure` semantics — if the inner chain raises
  during the yield, the teardown still runs.
- **`%chain` set by an outer handler is visible to every descendant**
  (same role, no chain wipe).
- **Missing handlers are simply skipped.** A directory without a
  `robinson.kscript` contributes no methods to the chain.

---

## `pass_through` — the wrapping primitive

```
vibecode: {
    "section": "pass_through",
    "shape": "context_manager_wraps_inner_chain_with_yield_in_the_middle",
    "method_signature": "pass_through($transaction)",
    "yield_semantics": "transfers_control_to_the_inner_chain_then_resumes_after",
    "ergonomic_advantage_over_process_request_plus_process_response":
        "resource_lifecycle_reads_top_to_bottom_in_one_place; state_stays_in_local_variables; ensure_semantics_apply_naturally_so_teardown_runs_even_if_inner_chain_raises",
    "syntax_note":
        "the_class_methods_do_end_block_shown_in_the_example_is_illustrative; final_class_method_definition_syntax_tbd_see_audit_15"
}
```

A class method that **surrounds** the inner chain. Setup runs before
the yield, the inner handlers and page file run during the yield,
teardown runs after.

```
class
    class_methods                                     # illustrative syntax — see audit #15
        function &pass_through($transaction)
            # setup — e.g., open a DB handle, store it on %chain
            yield $transaction
            # teardown — close the DB handle
        end
    end
end
```

The Shakespeare-site example: open a database handle, store it on
`%chain`, yield to let the inner chain (descendant dir handlers +
page file) run with the handle available, close the handle on the
way back.

This is the same shape as:

- Ruby's `File.open { |f| ... }` block form
- Python's `with` statement context manager
- Lisp's `unwind-protect`
- Express middleware's `(req, res, next) => { setup; next(); teardown; }`

### Why this is more powerful than process_request + process_response

| Concern | Two-method version | `pass_through` |
|---|---|---|
| Resource lifecycle | Setup in one method, teardown in another | Setup, yield, teardown — top-to-bottom in one place |
| Sharing state across the trip | Instance field or `%chain` plumbing | Local variables (closure) |
| `ensure` semantics | Need explicit error handling in `process_response` | Teardown after `yield` runs naturally via `ensure` |
| Reads like the lifecycle | No | Yes |

### Open questions

- ~~**Coexistence with `process_request` / `process_response`.**~~
  **Resolved 2026-05-17.** All three methods coexist as independent
  methods — a handler may implement any subset. When all three are
  present on a single handler, the per-handler call order is:
  `process_request($transaction)` → `pass_through($transaction)`
  (whose `yield` invokes the inner chain) → `process_response($transaction)`.
  All three take `$transaction`.
- **Short-circuit by not yielding.** If `pass_through` returns
  without yielding, does that short-circuit the inner chain entirely
  (skip everything below and just unwind back up)?
- **Yield return value.** Does `yield` produce a value the
  `pass_through` body can capture and inspect?
- **`%chain` interaction.** The example stores the DB handle on
  `%chain`. Since the inner chain runs in the same role (no role
  boundary), the `%chain` set in `pass_through` is visible to
  descendants. Confirm: same-role calls don't trigger the chain
  wipe, so this works.
- **Per-class scope.** Is `pass_through` available only on dir
  handlers, or on any class? (`class_methods` block suggests "any
  class.")

---

## Open questions (tracked as the brainstorm continues)

- **What does each `robinson.kscript` return / do?** Inspect-only,
  modify the request/transaction, short-circuit with a response,
  register cleanup, all of the above?
- **Response trip.** Does the chain reverse for the response —
  leaf → root, onion-style — so descendants can wrap parent output?
  Or is the response unwrapped without further handler involvement?
- **Per-directory state passing.** Can an outer `robinson.kscript`
  set context that descendants (and the page) can read?
- **Relationship to global Touchstone Handler chain.** Per-directory
  handlers fire inside the `pages/` directory handler's `process`,
  or are they peers in the chain alongside the global Handler list?
- **Per-directory class shape.** Is `robinson.kscript` a class
  inheriting from a `kiera.uno/robinson/dir_handler` base (parallel to
  page files inheriting from `kiera.uno/robinson/page`), or a
  function, or something else?
- **Multiple trees.** If a site has `pages/` and `admin/` and both
  contain `robinson.kscript` at corresponding levels, do both fire
  for a request that resolves into one of them, or only the tree
  the request belongs to?

---
