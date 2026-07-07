# Exceptions
<!--index: 11-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_exceptions",
	"role": "hub for Caspian's exception system. An exception is an object that can stop execution the moment it's raised. Caspian uses exceptions in many situations where other languages wouldn't — the intent is to keep the language slim by reusing one general control-flow mechanism rather than accumulating parallel machinery for each case. There is no technical concept of an 'error' exception; every exception is just an exception, and whether a specific class represents an error is a matter of that class's intent, not a runtime property. Whether a given exception can be caught (and by whom) is settled per exception. Same for whether it unwinds the stack (running ensure blocks and releasing resources) or exits without unwinding (dropping frames without cleanup) — the mechanism (class-level property, engine-level rules, or something else) is TBD, but callers can't choose at the raise or catch site. Both properties are spec'd per exception in the catalog rather than as a general taxonomy. Any exception that reaches the top of %chain without being caught is an uncaught exception. Only one exception can be in flight at a time.",
	"status": "draft — foundational rules spec'd; specifics of raise, catch, and the exception classes to be filled in as we work through them",
	"audience": "developers writing Caspian; engine implementers"
}}
~~~

An **exception is an object that can stop execution at the moment it's raised.**

**Caspian uses exceptions in many situations where they wouldn't normally appear in other languages.** The intent is to keep the language slim by reusing one general control-flow mechanism rather than accumulating parallel machinery for each case.

**There is no technical concept of an "error" exception.** Every exception is just an exception; the runtime treats them all the same way. Whether a specific exception class represents an error is a matter of that class's intent, documented on the class itself — not a runtime property, not a base class, not a flag on the object.

Whether an exception can be caught — and by whom — is a property of that specific exception. Rather than enumerate categories up front, catchability is spec'd on each entry in the [Exception catalog](#exception-catalog) below.

## Uncaught exceptions

An exception that **reaches the top of `%chain` without being caught** is an **uncaught exception**. The top of `%chain` is the outermost frame of the running program; nothing catches beyond that point.

## Unwinding

Every exception either **unwinds the stack** or **exits without unwinding**:

- **Unwinding.** As frames are popped, `ensure`-style cleanup blocks run, resources close, and any other automatic release fires. The stack is walked cleanly.
- **Exits without unwinding.** Frames are dropped without running cleanup. Resources like open database handles, network connections, or file descriptors stay open — the runtime bails, and nothing between the raise site and the top of `%chain` gets a chance to release what it holds.

Which behavior a given exception has is spec'd per entry in the catalog. Whether that's carried as a property of the exception's class, controlled by engine-level rules for specific exceptions, or arrived at some other way is TBD. What's settled: callers don't choose at the raise or catch site — the exception itself determines whether unwinding runs.

## One exception at a time

**Only one exception can be raised at a time.** There is no in-flight exception stack — the runtime tracks a single exception during unwind, not multiple.

## Raising exceptions

The `raise` bare-word command raises an exception. What it does depends on what you pass:

- **`raise` (no argument)** — raises a fresh `PlainException` with `.details` returning `null`.
- **`raise $exception`** where the argument IS an exception object — raises that exception directly.
- **`raise <anything else>`** — raises a fresh `PlainException` with the given value stored in `.details`. The value can be any type — a string, a hash, an array, a full object. `raise "bad thing happened"` is just the string case of this rule.
- **`$exception.raise`** — raise via the exception object's own `.raise` method. Equivalent to `raise $exception`.

Examples of each form:

~~~caspian
raise                                     # PlainException, .details is null
raise "bad thing happened"                # PlainException, .details is the string
raise {code: 500, path: '/foo'}           # PlainException, .details is the hash
raise $some_object                        # PlainException, .details is the object

$exception = SomeClass.new()
raise $exception                          # raises $exception directly
$exception.raise                          # equivalent
~~~

The wrap-into-details rule means callers don't have to construct a plain exception explicitly when all they want is to attach some data — they can hand any value directly to `raise` and get a plain exception carrying it.

For pre-built exceptions of a specific class, construct the object, configure it as needed, then raise:

~~~caspian
$exception = SomeClass.new()
$exception.details({code: 500, path: '/foo'})
raise $exception
~~~

The raise site records the same call frame regardless of which form was used.

## Catching exceptions

Catching is done with the bare-word command `catch` and an `end`. The general shape:

~~~caspian
$exception = catch(<filter>)
	# body — code that might raise
end
~~~

The body runs; if a matching exception fires during the body, the catch construct completes with the caught exception object as its value. If the body runs to completion without raising a matching exception, the construct returns **`null`**. The `$exception = ...` form captures whichever value into a variable.

The nothing-raised case makes the caller's check-and-handle pattern straightforward:

~~~caspian
$exception = catch()
	do_thing()
end

if $exception.object.null?
	# nothing was caught
else
	# handle $exception
end
~~~

### Filter forms

The parenthesized filter determines which exceptions match:

- **`catch()` (or bare `catch`)** — empty filter; matches every catchable exception. Bare `catch` and `catch()` are equivalent — any command, function, or method in Caspian can be called with or without parens.
- **`catch($class)`** — matches the given class or **any subclass** of it. Matching is subclass-inclusive.
- **`catch($class_1, $class_2, ...)`** — matches any of the listed classes (still subclass-inclusive per entry). The arg list is an OR.
- **URL-string filters.** A class can be named by its canonical URL identifier: `catch('https://foo.bar/gup/')`. The protocol can be omitted: `catch('foo.bar/gup/')`. String and class-object filters can be mixed within the same argument list.

### Uncatchable classes in a filter are silently ignored

Naming an uncatchable exception class in a `catch` filter has no effect. The exception never reaches any `catch` in the first place — it just propagates past every filter unchanged — so listing it produces no error, no warning, no match. It's silently a no-op.

~~~caspian
$exception = catch(AbortException)
	risky_operation()
end
# If risky_operation() calls abort, this catch does NOT see it.
# The AbortException in the filter is ignored; the abort flows past unchanged
# (either straight to program-end if user raised it, or through the ungraceful
# unwind to the UntrustedAbortException substitution if a non-user role raised it).
~~~

The empty-filter `catch()` and `catch` forms behave the same way — they catch every **catchable** exception, but uncatchable ones (like `AbortException` in flight) still propagate past.

~~~caspian
$exception = catch(PlainException, 'foo.bar/gup/')
	risky_operation()
end
~~~

### No syntactic dispatch by class

There is no `catch (A) ... catch (B) ...` chain, no `case ... when` shape inside the catch body. To handle different exception classes differently, inspect the caught object after the catch:

~~~caspian
$exception = catch()
	risky_operation()
end

if $exception.object.isa?(SomeSpecificClass)
	# specific handling
elsif $exception.object.isa?(AnotherClass)
	# other handling
end
~~~

The [`.object.isa?`](https://puck.uno/documentation/requirements/caspian/built-in-classes/object/methods/#isaclass) method is the standard way to branch on class; it's subclass-inclusive too, so the branches read the same way `catch` filters do.

## Exception catalog

The exceptions Caspian defines are cataloged flat below — no inheritance hierarchy for now. Groupings and a base-class organization will emerge later once the shape of the catalog is visible; for now each entry is spec'd on its own terms.

### PlainException

The general-purpose exception. Class name: **`PlainException`**. (The eventual canonical identifier will look something like `https://puck.uno/exception/`; using the short form here for now.)

Raised with `raise` followed by a message string:

~~~caspian
raise "bad thing happened"
~~~

The message is whatever string the caller passes.

**`.details`** — a method on the exception object that attaches arbitrary data to it. Any value — a hash, an array, a scalar, a full object — can be attached. The details travel with the exception through the unwind and are available to any handler that catches it.

**Catchability.** `PlainException` can be caught anywhere in the chain, by any role. No frame, no role, no chain depth restricts who can install a matching `catch`. Subclasses of `PlainException` inherit the same open catchability.

**Unwinding.** `PlainException` unwinds. As it propagates up the stack, ensure-style cleanup blocks run and resources are released cleanly.

### ReturnException

Raised by `return $value` and `%call.return $value`. Class name: **`ReturnException`** (for now; classes in Caspian don't carry names as language-level attributes — the eventual canonical identifier will be a URL, and that assignment is TBD).

The exception carries the returned value.

**`return` vs. `%call.return`.** The two forms target different frames:

- **`return`** returns from the enclosing **function** or **method** only. Inside a closure, `return` skips the closure body and returns from the enclosing function or method — not from the closure itself. (Closures don't count as return targets for the bare `return` keyword.)
- **`%call.return`** returns from whichever frame is currently the `%call` — function, method, or closure. It's the general-purpose form; use it when you want to exit the immediate call frame regardless of what shape it is.

The engine installs an implicit `catch` at the appropriate frame boundary — the enclosing function/method for `return`, or the immediate `%call` frame for `%call.return`. When the catch fires, the engine unpacks the value and hands it back to the caller as that frame's return value.

If a return exception is raised outside any matching frame — or otherwise gets past all the engine's boundary catches — it behaves like any other uncaught exception and propagates to the top of `%chain`.

**Catchability.** TBD.

**Unwinding.** TBD.

### ExitException

Raised by `exit`. Class name: **`ExitException`** (for now; eventual canonical identifier TBD).

**Catchability.** Uncatchable. No `catch` — neither in user code nor at any engine boundary — matches an `ExitException`. It always propagates to the top of `%chain`, at which point the program terminates.

**Unwinding.** Unwinds. As the exception propagates up, ensure-style cleanup blocks run and resources are released cleanly. The program shuts down, but it does so in the orderly way.

### AbortException

Raised by `abort`. Class name: **`AbortException`** (for now; eventual canonical identifier TBD).

`abort` behaves differently depending on which role calls it:

- **When user calls `abort`.** No unwinding. The script ends immediately — no ensure blocks, no cleanup, no propagation dance. The program is over.
- **When any other role calls `abort`.** Ungraceful unwinding — frames are dropped without running cleanup — until the runtime reaches a frame owned by `user`. At that boundary, the `AbortException` is discarded and **replaced by an `UntrustedAbortException`** in the user frame.

**Catchability.** Uncatchable directly. No user code and no engine boundary intercepts an `AbortException` in flight. User code encounters abort only through the `UntrustedAbortException` substitution described above (when a non-user role initiated the abort).

**Unwinding.** Determined by the role that raised it. User-raised: no unwinding at all — the program simply ends. Non-user-raised: ungraceful unwinding up to the user-role boundary, then the substitution.

### UntrustedAbortException

Substituted for an `AbortException` at the user-role boundary when a non-user role called `abort`. Class name: **`UntrustedAbortException`** (for now; eventual canonical identifier TBD).

**Catchability.** User-catchable. User code can install a matching `catch(...)` and handle it — though it usually shouldn't. When a non-user role has resorted to `abort`, something has gone badly enough that the caller wanted the program stopped; catching and ignoring is almost always a bug. Handle it only if there's a specific reason (forensics, structured logging, cleanup that must happen no matter what).

**Unwinding.** Unwinds. Once the `UntrustedAbortException` is in flight in the user frame, the chain unwinds gracefully — ensure blocks run and resources release as usual. The ungraceful non-user unwinding that preceded the substitution is done; from the substitution point onward, propagation is clean.

### SecurityException

Class name: **`SecurityException`** (for now; eventual canonical identifier TBD).

**Catchability.** User-only. Only user code can install a matching `catch(...)`. No other role — and no engine boundary — intercepts a `SecurityException` in flight; it propagates through non-user frames untouched and either reaches a user-installed catch or continues to the top of `%chain`.

**Unwinding.** Unwinds gracefully. Ensure blocks run and resources release as the exception propagates.

### Controller returns (loop, block, conditional)

Each of the three controllers — the loop controller (`$loop.return $value`), the bare-block controller (`$block.return $value`), and the if/unless conditional controller (`$conditional.return $value`) — raises a return exception targeted at the frame that owns the corresponding construct.

Working class names: **`LoopReturnException`**, **`BlockReturnException`**, **`ConditionalReturnException`** (canonical URLs TBD; whether these are separate classes, subclasses of a shared base, or a single class distinguished by a target field is also TBD).

Each raise carries the value the caller passed. The engine has an implicit `catch` at the corresponding construct's boundary — the loop for `LoopReturnException`, the bare block for `BlockReturnException`, the if/unless chain for `ConditionalReturnException`. When the catch fires, the engine unpacks the value and hands it back as the construct's return value.

If a controller-return exception escapes past the construct that would catch it — for example, the loop already ended and the controller was captured by a late-called function — it propagates like any other uncaught exception until something catches it or it reaches the top of `%chain`. (This is the same "raise after the loop ended" case already spec'd under [loops § Control methods raise after the loop ends](https://puck.uno/documentation/requirements/caspian/syntax/loops#control-methods-raise-after-the-loop-ends); the phrasing there — "raises" — is realized as one of these controller-return exceptions escaping past its would-be catch.)

**Catchability.** Engine-caught at the corresponding construct's boundary. Whether user code can install a matching catch in addition — TBD.

**Unwinding.** Unwinds gracefully. Ensure blocks between the raise site and the construct boundary run; resources release cleanly.
