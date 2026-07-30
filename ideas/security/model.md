# Caspian security model

~~~vibecode
{"vibecode": {
	"doc": "ideas_security_model",
	"role": "Caspian's security model in as few rules as possible. A developer should be able to hold the whole thing in mind. This page states what each rule IS; consequences and worked examples belong elsewhere.",
	"status": "iterating — six rules around the roles-form-a-hierarchy model; boss-authority (structural mutation + ownership transfer) promoted to Rule 2; user's special-case grants dissolved into ancestral authority; dispatch corrected to defining-role",
	"context": "started after Caspian's security surface accumulated seven overlapping mechanisms in a few hours of piecewise design. This doc is the top-down pass."
}}
~~~

These are the core rules for Caspian's security model. All security features descend from these basic rules.

## Rules

### Rule 1: Roles and objects

Roles and objects work like Linux users and file ownership. Every frame runs as one role. Every object is owned by one role.

### Rule 2: Corporate structure

Roles are organized in a tree like a corporate hierarchy. Every role is the boss of its descendants and can manage any object owned by itself or by them — structural mutation (stack changes, freeze, destroy) and ownership transfer. `user` sits at the top. Employees cannot manage objects owned by ancestors.


### Rule 3: Method code runs in the role that defined it

A method runs under the role that DEFINED its code — the class's role for class methods, the attaching role for singleton methods. Not the caller's role, not the receiver's owner.

### Rule 4: Access is empowerment

If a frame holds a reference to an object, it can call any of the object's methods. There is no language-level fine-grained access control. Class authors can gate methods themselves via `%call.role` and `%call.trusted?`, but the language doesn't enforce anything behind the class author's back.

### Rule 5: I/O is engine-granted

I/O — filesystem, network, standard streams, subprocesses, anything crossing the boundary between the program and the outside world — reaches user code only through objects the engine hands in at startup. No object, no access. `%fs`, `%net`, `%stdout` are engine-scoped bindings; each role sees only what the engine placed there. Typically only `user` receives these primitives; other roles obtain narrowed access through broker objects user constructs.

### Rule 6: Referencing an object does not change its ownership

Ownership doesn't cascade through references. If a value is inside your container, you own the container, not the value.

