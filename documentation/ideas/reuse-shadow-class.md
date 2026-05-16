# Reuse Shadow Class

Speculative metaprogramming idea. Filed for exploration, not as a
proposed feature.

See [kscript-runtime.md § Object Model](../kscript/kscript-runtime.md#object-model)
for the established shadow-class concept this idea builds on.

---

## The idea

The shadow class is normally a per-object hidden thing — you
`object.define` methods on it to customize one specific instance,
and that's the end of it. Once the object is garbage-collected,
the shadow goes with it.

But the shadow is still a real class. So what if you could
instantiate from it directly? Once you've tricked out a single
object with custom methods, treat that object as a prototype
and `.new()` more objects from its shadow:

```
$foo = some_class.new()

$foo.object.define do
    function &bar
        # ... custom method only on $foo, in foo's shadow class ...
    end
end

# $foo is now a one-off — only $foo has &bar.

# But the shadow class is reachable. Instantiate from it:
$foo_2 = $foo.object.shadow.new()

# $foo_2's class stack: [its own fresh shadow,
#                         $foo's shadow (the one we customized),
#                         some_class]
# So $foo_2 also has &bar.
```

The original singleton becomes a *template* — a fully-built,
fully-configured instance whose customizations are visible to any
new object spawned from its shadow.

## Why it's interesting

- **Prototype-style inheritance for free.** Same mechanism that
  supports per-instance methods now supports "make more like this
  one." No separate prototype-cloning machinery.
- **Factory-by-example.** Instead of writing a factory function
  that builds and configures an object, configure one instance
  and `.new()` from its shadow. The shape of the prototype IS the
  factory.
- **Ad-hoc subclassing.** Want a quick variation of a class
  without declaring a new class formally? Make an instance,
  customize it, treat that as the new "class."
- **Same concept, more useful.** Shadow class doesn't gain new
  semantics — it's still a class with methods. We just stop
  treating it as one-off-only.

## Open questions

- **Bucket state.** Does `$foo.object.shadow.new()` start with a
  fresh empty bucket, or copy $foo's bucket as initial state?
  Both are defensible; the latter is closer to "factory by
  example" but blurs the line between class and instance.
- **Chained shadows.** If `$foo_2 = $foo.object.shadow.new()`,
  and then I customize $foo_2's own shadow, what happens to a
  `$foo_3 = $foo_2.object.shadow.new()`? The class stack starts
  to nest: `$foo_3` would have its own shadow, then $foo_2's
  customizations, then $foo's. That's potentially powerful, but
  also a way to build inscrutable class hierarchies.
- **Mutation propagation.** If $foo's shadow gets a new method
  added *after* $foo_2 is instantiated, does $foo_2 see it?
  Probably yes (class methods are shared across instances), but
  the "shadow customized on a per-instance basis" framing makes
  this surprising.
- **Naming and discoverability.** What does `$foo_2.object.classes`
  return? If $foo's shadow shows up in the stack, it needs a
  name — but shadows historically don't have names because
  they're implicit per-object.

## Related: cloning the entire class stack

A sister idea, also already baked into the existing object model:
clone the full class stack of one object onto another.

```
$bar = %['some/base'].new()
$bar.object.classes = $foo.object.classes
```

This is enabled by the role model: the owning role can mutate
`object.classes` directly. Foreign roles cannot. So an object's
configuration profile — base class plus any additional classes
added to its stack — can be replicated onto another object
without writing a factory.

Use case: a **decorated database client** built up at runtime
with several layers stacked on (retry, cache, metrics). When you
need another client with the same decoration profile pointed at
a different host, copy the class stack onto a fresh instance.

```
$db1 = %['my/db'].new(host: 'db1.example.com')
$db1.object.classes.push(%['my/decorators/retry'])
$db1.object.classes.push(%['my/decorators/cache'])
$db1.object.classes.push(%['my/decorators/metrics'])

# Clone the decoration onto a second client
$db2 = %['my/db'].new(host: 'db2.example.com')
$db2.object.classes = $db1.object.classes
```

No factory function. No DSL. No "decorator pattern" framework.
The class stack IS the decoration; copying it IS the cloning.

## Status

Filed as exploration. No commitment to spec, implement, or even
keep the idea in mind during v1 design. Both features
(shadow-class instantiation, class-stack cloning) are already
enabled by the existing object model — the role system provides
the access control, and the standard `.new()` / array mutation
operations do the work. The metaprogramming patterns shown here
emerge for free.

Worth revisiting if a real use case surfaces that these would
handle elegantly and that the explicit-class path handles
awkwardly.
