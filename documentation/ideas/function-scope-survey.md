# Idea: Function-scope survey

~~~vibecode
{"vibecode": {
	"doc": "function-scope-survey",
	"role": "cross-language survey of how functions call other functions defined in the same scope; catalog of design axes (visibility default, granularity, opt-in vs opt-out, mutual recursion mechanics, security posture) to give context for Caspian's function-scope decisions",
	"key_concepts": ["mutual_recursion", "forward_reference", "hermetic_function",
		"module_visibility", "lexical_scope", "capability_security", "late_binding"],
	"status": "survey",
	"context": "raised 2026-07-25 during the bare-function design at requirements/functions/bare; the current two-declaration-form compromise (named form captures sibling &-names, assignment form captures nothing) carries semantic weight beyond stylistic preference — this survey maps the landscape so alternatives can be evaluated against real precedent"
}}
~~~

## What this covers

How named callables reach other named callables in the same scope — the ergonomic sibling case that shows up everywhere, and the security-relevant case of a callable that can NOT reach its siblings by name. For each language: the mechanism, what "scope" means there, whether hermeticity has linguistic support, and any distinctive choice worth noting.

Caspian's current design lives at [functions/bare](https://puck.uno/documentation/requirements/functions/bare). This survey does not evaluate it — it just maps the neighborhood.

## Scheme

Internal `define`s inside a body have the semantics of `letrec*` (R6RS/R7RS): every internal definition is visible to every other, so mutual recursion between siblings works with no annotation.

```scheme
(define (even? n) (if (= n 0) #t (odd? (- n 1))))
(define (odd?  n) (if (= n 0) #f (even? (- n 1))))
```

For explicit local scoping, three binding forms differ deliberately: `let` (bindings cannot see each other), `let*` (each sees earlier ones), `letrec` / `letrec*` (all mutually visible). `letrec` is the direct answer to "I want these local functions to call each other."

R6RS `library` and R7RS `define-library` add an export list at the module boundary; inside the library everything is visible. No hermetic-callable primitive — lexical closure only.

## Common Lisp

CL is a Lisp-2: each symbol has a **function slot** distinct from its value slot. `defun` interns a function object into the symbol's function slot at package scope; calls in operator position look up the function slot, so `defun`'d siblings see each other automatically inside a package.

Locally, a deliberate split:

- `flet` — locally-bound functions; bodies do NOT see the other bindings in the same `flet`. Non-recursive by construction.
- `labels` — locally-bound; bodies DO see each other; supports mutual recursion.

```lisp
(labels ((even? (n) (if (zerop n) t   (odd?  (- n 1))))
         (odd?  (n) (if (zerop n) nil (even? (- n 1)))))
  (even? 10))
```

The `flet` / `labels` distinction is a direct precedent for "do siblings see each other?" as a per-binding-form decision rather than a language-wide default. Neither is a security mechanism — both close over the enclosing lexical scope.

## Clojure

`defn` at the top of a file interns a **Var** in the current namespace. Calling `(foo x)` resolves `foo` through the namespace at call time — late binding, so runtime order doesn't matter, but load-time references to a not-yet-defined symbol fail. `declare` forward-declares a Var so mutually recursive definitions can be written in any order:

```clojure
(declare odd?)
(defn even? [n] (if (zero? n) true  (odd?  (dec n))))
(defn odd?  [n] (if (zero? n) false (even? (dec n))))
```

`letfn` is the local-scope analogue of `letrec` / `labels`. Namespaces expose everything by default; `^:private` metadata (or `defn-`) restricts a Var to the defining namespace — a convention, not a security boundary (reflection reaches private Vars).

## OCaml

Top-level `let` is sequential and non-recursive. `let f = ...` establishes a binding that later definitions see, but `f`'s body cannot reference itself or any later sibling. Recursion and mutual recursion are opt-in via `let rec ... and ...`:

```ocaml
let rec even n = if n = 0 then true  else odd  (n - 1)
and     odd  n = if n = 0 then false else even (n - 1)
```

The `and` chain is the exclusive mechanism — there is no "everything in this module is mutually recursive" default. Sibling visibility is a per-declaration-group opt-in. The module system controls exports via `.mli` signatures.

## Haskell

The opposite default from OCaml: **every top-level binding in a module is mutually recursive** with every other, in any order. `where` and `let` clauses inside a function are also mutually recursive. No keyword required.

```haskell
even_ 0 = True
even_ n = odd_ (n - 1)
odd_  0 = False
odd_  n = even_ (n - 1)
```

Laziness makes many otherwise-looping forward references terminate. Module exports go on the `module Foo (bar, baz) where` line; omitting the list exports everything.

No hermetic-callable primitive. Purity substitutes at the type level: `Foo -> Bar` cannot do I/O; you'd need `Foo -> IO Bar`. "Give this callable no ambient authority" is expressed by refusing to give it `IO` in its type — a very different mechanism, same problem space.

## C

Names are visible from their declaration point forward within a translation unit. Forward declarations let callers appear before definitions; mutually recursive functions require at least one prototype. `static` limits linkage to the translation unit; non-`static` functions are exported to the linker. No module system, no hermetic form. Reachability is controlled coarsely and manually — the header-inclusion graph plus `static`.

## Rust

Items in a module are order-independent and mutually visible without forward declarations — the compiler makes two passes. Visibility is per-item and default-private-to-the-module: `pub`, `pub(crate)`, `pub(super)`, `pub(in path::to::mod)`. Private-by-default at fine granularity, with the escape hatch labeled.

No hermetic-callable form. Rust's answer to "restrict what this closure sees" is the type system (`Fn` / `FnMut` / `FnOnce` traits, `move` closures, borrow checker) — you constrain what a callable **can hold**, not what names it can see.

## Go

Package-level identifiers are visible to every file in the package, in any order, without forward declarations. There is no file-local scope for top-level names — the package IS the scope.

Cross-package visibility rides on identifier casing: uppercase-first = exported; lowercase-first = package-private. That's the entire mechanism — no `pub`, no export list, no directive. The distinctive axis: Go moves the visibility decision from a per-file / per-scope mechanism to a naming convention that lives in the identifier itself.

## Python

`def` at any scope binds a name in the enclosing namespace (module dict, class dict, or enclosing function's locals). Name resolution inside a function body is **late-bound** — the body looks up free names each time it runs, so forward references work provided the name is defined by the time the call fires:

```python
def even_(n): return True  if n == 0 else odd_(n - 1)
def odd_(n):  return False if n == 0 else even_(n - 1)
```

Both `def`s succeed at import; the mutual reference resolves at first call because module-level names live in `__dict__` and are looked up dynamically. Nothing is truly private; `_leading_underscore` is convention, `__name_mangling` is a class-scope trick.

Nearest primitive for a hermetic callable: `types.FunctionType(code, globals, name)` — construct a function object with a chosen `__globals__` dict. Manual and low-level; the escape hatch when you're building a sandbox.

## Ruby

Ruby's answer runs through method dispatch. A top-level `def foo` becomes a private instance method on `Object`, so any code in the default receiver context can call it — this is why `puts` "just works" at the top level. Inside a class or module, `def` adds an instance method there.

Sibling reachability is a runtime property of the receiver's method table, not a scope property. `public` / `private` / `protected` control who can send the message but do not gate the table lookup itself. `send` bypasses `private`; `binding.eval` reaches enclosing scope — the language does not enforce ambient-authority limits.

## JavaScript

Three definition forms with visibly different scoping:

- `function foo() {...}` — **hoisted** whole; siblings see each other in any order within the enclosing function/module.
- `var foo = function() {...}` — `var` binding hoisted (value `undefined` until the assignment); calling before assignment throws.
- `const foo = function() {...}` / `let foo = ...` — TDZ until the initializer runs.

```js
function even_(n) { return n === 0 ? true  : odd_(n - 1); }
function odd_ (n) { return n === 0 ? false : even_(n - 1); }
```

Modules control cross-file visibility; inside a module, all top-level bindings see every function in the module.

Closest hermetic form: `new Function('x', 'return x + 1')` — a callable whose scope is only the global scope, not the enclosing lexical scope. Realms (Stage 3) and SES (Hardened JavaScript) push this into a full capability-security model — a design point directly comparable to Caspian's hermetic-function goal.

## Erlang

Modules are the unit of scope. Functions in the same module can call each other by name, regardless of source order. The `-export([f/1, g/2])` directive lists what's callable from outside; unlisted functions are module-private.

Anonymous `fun`s close over their enclosing scope. No hermetic form; the "minimal authority" story runs through the actor model — you pass a `Pid`, and the receiver can only send it messages, not reach into its state.

## Perl

`sub foo { ... }` at file scope installs `foo` in the current package's symbol table. All subs in a package are mutually visible and reachable by bareword. Package boundaries (`package Foo::Bar;`) are the primary visibility mechanism.

For lexically-scoped subroutines, the `lexical_subs` feature (stable since 5.26) provides `my sub foo { ... }` — the name lives only in the enclosing lexical block, invisible to any other package or file. Direct precedent for "declare a callable whose reachability is scoped, not global-to-the-package." No hermetic-callable primitive; `Safe` compartments attempt a restricted-eval sandbox by masking opcodes.

## Forth

Definitions land in **the dictionary** as they are compiled. Each new word can call any word already in the dictionary. Order is strict and irrevocable — a word can never call one defined after it.

The idiom for mutual recursion is to `DEFER` the partner first, then plug in an implementation with `IS`:

```forth
DEFER ODD?
: EVEN? ( n -- ? ) DUP 0= IF DROP TRUE ELSE 1- ODD? THEN ;
: ODD?-IMPL ( n -- ? ) DUP 0= IF DROP FALSE ELSE 1- EVEN? THEN ;
' ODD?-IMPL IS ODD?
```

Self-reference during a definition uses `RECURSE`, because the word being defined isn't in the dictionary until the closing `;`. Redefining a word doesn't rewrite earlier callers; they keep pointing at the original. Forth demonstrates that sibling visibility can be strictly compile-time-monotonic and still be usable.

## E

E is a capability-security language: every reference is a capability, and there is no ambient authority — the only way to reach an object is to be handed a reference. Function-shaped things are objects; calling one is a message send. Sibling reach at the same lexical scope is supplied by ordinary closure — no separate mechanism.

The security posture that maps to Caspian's hermetic case: because E has no globals, a function's reachability set is exactly what its closure captured plus what its arguments hand in. To make a function hermetic, construct it in a scope that contains only the intended references — the language does not distinguish declaration forms by capture; it makes the scope you construct matter.

Newspeak takes this further: every name resolution is a message send on an implicit receiver, so even "globals" flow through a resolvable-and-swappable channel.

References: [Miller, *Robust Composition* (2006)](https://papers.agoric.com/assets/pdf/papers/robust-composition-towards-a-unified-approach-to-access-control-and-concurrency-control.pdf); [erights.org](http://erights.org/).

## Design axes

A handful of axes appear repeatedly across the fifteen sections.

### Default sibling visibility

- **All-mutually-visible by default:** Haskell (module), Rust (module), Go (package), Erlang (module), Common Lisp (package, via function slot), Ruby (class/module), JavaScript (module), Perl (package), Clojure (namespace, plus `declare` for load-order).
- **Sequential-visible, mutual opt-in:** OCaml (`let rec ... and`), Scheme's `letrec` vs `let`, Common Lisp's `labels` vs `flet`.
- **Strictly monotonic (no forward reference at all):** Forth.

The dominant modern default is "everything in the module sees everything else." The `letrec` / `labels` / `and` opt-in pattern is a Lisp/ML tradition; strict-monotonic is a Forth curiosity.

### Granularity of the visibility unit

- **Module / file / package:** Rust, Go, OCaml, Haskell, Erlang, Perl, Python, JavaScript module, Clojure namespace, Common Lisp package.
- **Class / receiver:** Ruby.
- **Explicit scope construct:** Scheme (`letrec`), Common Lisp (`labels`), Clojure (`letfn`), OCaml/Haskell (`let rec ... in`), Perl (`my sub`).
- **The identifier itself:** Go (uppercase = exported).

Caspian's problem is at the smallest granularity — the enclosing lexical scope of a `function &X` declaration group. The closest precedents are the `labels` / `letrec` / `letfn` family.

### Opt-in vs opt-out for sibling reach

- **Opt-out (default reach, silence to remove):** most modern languages; Rust's `pub`/private controls export, not intra-module reach.
- **Opt-in (default no reach, keyword to add):** OCaml `and`, Common Lisp `labels` vs `flet`, Scheme `letrec` vs `let`.

The opt-in tradition is older and narrower than the opt-out one, but it exists and is well understood.

### Static vs dynamic resolution

- **Static / lexical:** ML family, Scheme (`letrec`), Rust, Go, C, Haskell.
- **Late-bound through a namespace / dict:** Python (module dict), Ruby (method table), Clojure (Var), Erlang (module).
- **Late-bound with reassignment:** Clojure Var + `alter-var-root`, Python monkey-patching.

Late-binding pays for "you can redefine at the REPL" with "the reference at the call site is not the value at the definition site." Sibling-visibility mechanisms that snapshot a callable value sit closer to the static end.

### Hermetic / capability-safe callable

Rare as a direct primitive: E and Newspeak (no ambient authority in the language); JavaScript `new Function(...)` and Realms / SES (chosen global environment); Python `types.FunctionType(code, globals, name)` (manual construction); Perl `Safe` (opcode-restricted eval); Joe-E (Java subset with static-analysis-enforced no-ambient-authority).

Absent elsewhere, or approximated at the type system (Haskell `IO`) or the runtime (JVM/CLR sandboxes). Retrofitting capability discipline onto a language that started with ambient globals is hard; languages that start with the capability model get it cheaply.

### Mapping onto Caspian's problem

- **All-sibling-visible default (most modern langs):** collapse the two declaration forms; route hermeticity through a separate mechanism (an explicit "seal this callable" wrapper, a chain grant, or a construction primitive taking an env dict).
- **Opt-in mutual recursion (`labels` / `let rec ... and`):** keep both forms but require an explicit group keyword to enable sibling reach — no capture without asking.
- **Namespace with `declare` (Clojure):** move sibling reach onto a namespace surface separate from the lexical scope, decoupling "these names refer to each other" from "these names are in the same block."
- **Late-bound method dispatch (Ruby):** rework named callables as messages to a receiver; sibling reach becomes a property of the receiver's method table.
- **Capability-native (E / Newspeak):** every callable hermetic by construction; sibling reach through the ordinary reference-graph, no special sibling-set primitive.

Each has different consequences for the ergonomics-vs-security tension. This survey does not choose between them.
