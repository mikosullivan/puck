# Idea: methods callable without a leading dot

~~~vibecode
{"vibecode": {
	"doc": "no_dot_methods",
	"role": "brainstorm — some Caspian methods (mathematical Unicode symbols like ⊂, ⊆, ∪, ∩, △) can be called without a leading dot between the receiver and the method name — `$a⊂($b)` rather than `$a.⊂($b)`. This idea catalogs the surfaces that want this form, the reasons the dot is redundant for them, and the open question of how the syntax spec formally marks methods as no-dot-required.",
	"status": "brainstorm — settled that at least the set-theory Unicode symbols work this way; syntax-level formalism (how the parser knows, how the spec marks them) is TBD",
	"references": ["https://puck.uno/documentation/ideas/array-methods#set-operations"]
}}
~~~

Most method calls in Caspian use the dot-prefix form: `$widget.render`, `$arr.map`, `$foo.$method`. The dot is the method-call separator; it makes the receiver-method boundary visible even when the method name is short or unusual.

**Some methods drop the dot.** When the method name is a Unicode mathematical symbol like `⊂`, `⊆`, `∪`, `∩`, `△` AND the method takes at least one argument, the receiver-method boundary is already visually clear (the right-hand operand does the work the dot would do), and the mathematical reading of the expression matches natural notation better without the dot:

~~~caspian
$a ⊂ $b             # subset-of, no dot — reads as the math symbol
$a.subset_of?($b)   # English form, with dot — reads as a method
~~~

Both call the same method under the hood. The dot-free form is only available on the symbol name; the English alias still needs a dot.

Parens around the argument are optional (that's Caspian's general rule — parens are always allowed on any method call, but never required). For the Unicode-symbol forms specifically, they read cleaner without parens; `$a ⊂ $b` is the recommended style.

### The space requirement

**No-dot symbol methods must be separated from the receiver by a space.** Without the dot AND without space, the receiver and the symbol run together visually:

~~~caspian
$a ⊂ $b            # good — space around the symbol
$a⊂$b              # not allowed — receiver runs into the symbol
$a.⊂($b)           # also legal — dot form is always available
~~~

The space is what the dot used to do: mark the boundary between receiver and method. Every no-dot call site needs it.

### The parameter requirement

Zero-argument symbol methods keep the dot. Without a right-hand operand, there's nothing to signal that the symbol is being applied — the code would read as "receiver, then a floating symbol":

~~~caspian
$arr.∅?         # empty-set predicate — dot required
$arr ∅?         # would read as "$arr, followed by a floating symbol" — no
~~~

`.∅?` takes no argument, so dropping the dot leaves it visually adrift. The dot stays.

The rule is really about **whether there's an operand after the symbol to make "this is a call" obvious.** Argument-taking symbol methods have a right-hand operand; zero-arg symbol methods don't; only the first category drops the dot.

## Where this shows up

- **Set operations on arrays** — `∪`, `∩`, `△`, `⊂`, `⊆` all work no-dot. See [array-methods § Set operations](https://puck.uno/documentation/ideas/array-methods#set-operations).
- **Anywhere else Unicode symbols might get used as method names** — TBD. If math-y string methods, comparison operators, or other domain-symbol methods land, they'd want the same treatment.

## Why the dot is redundant for symbol methods

- The symbol itself makes it obvious what's happening. `$a⊂($b)` reads as the mathematical subset-of statement; adding `.` doesn't clarify anything.
- Mathematicians write `A ⊂ B`, never `A . ⊂ B`. Requiring the dot in code would give up the very readability that motivated adopting the symbol in the first place.
- The symbol characters don't collide with variable names or word-shaped identifiers, so there's no parser ambiguity in dropping the separator. `$a⊂($b)` cannot mean anything except "call `⊂` on `$a` with argument `$b`."

## How methods are marked no-dot

**Explicit declaration in the class body.** A method that can be called without the dot has to be marked as such at definition time. There is no automatic rule based on the method name, character class, arity, or anything else — a class author who wants no-dot invocation for a method opts in explicitly. Method names that look symbolic default to dot-required, same as every other method.

Shape TBD; something like:

~~~caspian
class # array
	method &⊂ ($other) as :no_dot
		# ...
	end
end
~~~

The `as :no_dot` marker (or whatever the syntax settles on) is what tells the parser to accept `$a⊂($b)` in addition to `$a.⊂($b)`. Both call sites remain valid — no-dot is an ADDITIONAL surface, not a replacement.

**Why explicit?** No automatic rule would get all the cases right. `⊂` and `⊆` deserve no-dot; `.map!` (ASCII with a symbol suffix) does not; `.∅?` (Unicode with an ASCII suffix, zero-arg) does not. A class author who's designing a method surface knows which reading is intended for a given method; the language shouldn't guess. This also means the no-dot form scales cleanly to user code — anyone can mark their own methods as no-dot when it makes sense for their domain.

## Open questions

- **The parameter requirement.** Zero-arg symbol methods can't drop the dot even if the class author would want to — without a right-hand operand or parens, there's nothing to signal that the symbol is being applied. Is `no_dot` a marker the parser rejects at definition time for zero-arg methods, or is it silently ignored, or does the language just trust the class author to only apply it where it makes sense?
- **Can user-defined classes participate?** If a user defines a class with a `⊂` method and marks it `no_dot`, does the parser accept `$a⊂($b)` in user code the same way it does for built-ins? Recommend yes — same mechanism everywhere; no reason to gate it to built-ins.
- **What about typing?** The dot-free form is only useful if you can type the symbol. Requiring users to opt in to Unicode input is fine — the English alias always exists, and the class author can always define an ASCII-named twin.
- **What about ambiguity with juxtaposition?** In some parsers, `$a $b` could mean "call `$a` on `$b`" or "two adjacent expressions." Caspian doesn't currently have juxtaposition as a call form, so `$a⊂($b)` is unambiguous — but if juxtaposition ever gets considered, the interaction matters.

## Not yet in scope

- **General binary operators** (`+`, `-`, `*`, `/`, `<`, `>`, `==`) are already no-dot in every language; they're not the interesting case here. This idea is specifically about Unicode-symbol *method* names that would otherwise need the dot.
- **Assignment aware methods** ([ideas/assignment-aware-methods](https://puck.uno/documentation/ideas/assignment-aware-methods)) — separate concept about `.field = value` triggering a method. Not related.

## Related

- [array-methods § Set operations](https://puck.uno/documentation/ideas/array-methods#set-operations) — the first concrete surface exercising this, and the reason this idea exists.
