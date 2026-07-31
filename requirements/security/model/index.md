# Caspian security model

~~~vibecode
{"vibecode": {
	"doc": "ideas_security_model",
	"role": "Caspian's security model in as few rules as possible. A developer should be able to hold the whole thing in mind. This page states what each rule IS; consequences and worked examples belong elsewhere.",
	"status": "iterating — six rules around the roles-form-a-hierarchy model; parent-authority (structural mutation + ownership transfer) promoted to Rule 2; user's special-case grants dissolved into ancestral authority; dispatch corrected to defining-role",
	"context": "started after Caspian's security surface accumulated seven overlapping mechanisms in a few hours of piecewise design. This doc is the top-down pass."
}}
~~~

These are the core rules for Caspian's security model. All security features descend from these basic rules.

## Rules

### Rule 1: Roles and objects

Roles and objects work like Linux users and file ownership. Every frame runs as one role. Every object is owned by one role.

### Rule 2: Corporate structure

Roles are organized in a tree like a corporate hierarchy. `user` sits at the top; all other roles descend from it. A role can manage any object owned by itself or by any of its descendants — structural mutation (stack changes, freeze, destroy). Descendants cannot manage objects owned by ancestors.


### Rule 3: Method code runs in the role that defined it

A method runs under the role that DEFINED its code — the class's role for class methods, the attaching role for singleton methods. Not the caller's role, not the receiver's owner.

### Rule 4: Access is empowerment

If a frame holds a reference to an object, it can call any of the object's methods. There is no language-level fine-grained access control. Class authors can gate methods themselves but the language doesn't enforce anything automatically.

### Rule 5: I/O is engine-granted

The engine hands I/O objects — filesystem, network, standard streams, subprocesses — to `user` at startup. Nothing about I/O is ambient. For any other role to touch I/O, `user` must pass a permission to the subrole.

