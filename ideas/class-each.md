# class.each

~~~vibecode
{"vibecode": {
	"doc": "ideas_class_each",
	"role": "brainstorm — Mikobase feature. Every class exposes `.each` as an iterator over its own instances; the block receives each instance in turn. The class itself is the iteration surface — no explicit collection query, no registry setup on the caller's part.",
	"status": "sketch"
}}
~~~

In Mikobase, you can loop through the instances of a class using the class itself:

~~~caspian
$class.each do($obj)
	# $obj is one instance of $class
end
~~~

Every class exposes this. No `.all` or `.instances` call to build a collection first, no registration step at define time — the class stands in for "all my instances," and `.each` walks them.

The block form matches the standard iterator pattern used everywhere else in Caspian (see [iterators](tag:iterators) for the general shape). The only thing that's different is the receiver: a class instead of a container.
