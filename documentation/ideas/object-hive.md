# Object hive

~~~vibecode
{"vibecode": {
	"doc": "object_hive",
	"role": "brainstorm — Caspian as a hive of living objects that interact with each other, rather than just a procedural language. Server-shaped by default; easy to listen on a socket and delegate received instructions to listeners. Single-threaded but feels asynchronous because objects react to triggers. Catalogs analogous systems for reference and proposes a blend (MOO + Erlang) as the closest match.",
	"status": "vague — clarifying the question; no design yet",
	"key_concepts": ["caspian_as_object_hive_not_just_procedural",
		"servers_are_easy_to_set_up",
		"objects_wait_for_triggers_and_delegate",
		"single_threaded_but_event_driven",
		"closest_existing_models_are_actor_systems_and_moos"]
}}
~~~

## The vision

Caspian should be more than a procedural language. The mental model should be **a Caspian program is a hive of objects that interact with each other** — similar to how a web page is an object (the document) made of smaller objects (elements) that react to events.

A few specific things this implies:

- **Servers should be easy to set up.** Listening on a socket, accepting connections, and dispatching incoming instructions to interested listeners should feel idiomatic — not boilerplate.
- **Programs are structured as live objects waiting for stimuli.** Sockets, events, scheduled triggers, messages from other objects. The objects sit there waiting until something happens; then they react.
- **Mirror the Mikobase mental model.** Mikobase is already an object store of live records that respond to queries and signals. Caspian-as-server should feel similar — a running process that holds a graph of objects and routes inputs to them.
- **Single-threaded, but feels asynchronous.** Caspian doesn't do threads. But objects should still feel like they're "alive in parallel" — each one ready to react when its trigger fires. The cooperative event-loop pattern (see [engine-events.md](caspian/engine-events.md)) is one way to achieve this without breaking the single-threaded model.

This is the seed of the idea. The shape is unclear — what's worth borrowing, what's specific to Caspian, what mental model carries the most weight — those are open.

---

## Systems that already do something like this

(Besides JavaScript, which is the obvious comparison.) Organized by which aspect of the vision they emphasize most.

### Actor model — "objects as living things waiting for messages"

The canonical answer. Each actor is a process with a mailbox; `receive` blocks until a message arrives; the whole program is a graph of actors sending each other messages.

- **Erlang / Elixir** — lightweight processes (millions possible), all cooperatively scheduled by the BEAM VM. No OS threads. `receive` blocks per-actor. The closest match for "things waiting to be triggered."
- **Pony** — actor model with type safety; more rigorous than Erlang.
- **Akka** (Scala/Java) — actor framework with supervision trees. Heavier.

### Smalltalk family — "everything is an object that responds to messages"

Alan Kay's "the computer is a society of cooperating objects" vision. The metaphor that started object-oriented programming.

- **Smalltalk-80** — the original.
- **Self** — Smalltalk descendant with prototypes.
- **Io** — small prototype language; async via coroutines; very clean object metaphor.
- **Pharo / Squeak** — modern Smalltalks. Squeak's Etoys-tile system shows how far the "objects with behaviors" model can stretch for end-users.

### MOO / MUD systems — the strongest "the program is a world of objects"

Multi-user object-oriented environments where every room, thing, and player is a live object with verbs (methods) that get triggered by inputs.

- **LambdaMOO** — running since 1990. Players send commands over a socket; the parser dispatches to verbs on objects. The program literally IS a hive. Written in MOO, a small language built exactly for this.
- **ColdMUCK / ColdC** — similar lineage.
- **Inform 7** — interactive fiction. The world is a hive of objects with rules that fire on actions. Less server-shaped but same mental model.

### Reactive / dataflow — "objects update when their inputs change"

- **Spreadsheets** — every cell is an object that reacts to its dependencies.
- **Observables in modern frontend frameworks** (React, Vue, Solid) — cells, signals, computed values; all reactive.
- **Rx / ReactiveX** — push-based streams composed via operators.

### Distributed object / capability systems

- **E language** (Mark Miller) — actors + promises + capabilities. Designed for distributed safety.
- **CORBA / DCOM / SOAP** — enterprise-heavy ancestors. Conceptually similar but operationally painful.

### GUI toolkits — "objects with handlers, glued by an event loop"

These are the most familiar "objects waiting to be triggered" pattern most developers know.

- **Cocoa / AppKit** (Objective-C / Swift) — every UI element is a responder in a chain; events bubble. NotificationCenter for global pub-sub.
- **Qt** — signals and slots: objects emit signals; other objects connect slots. Strikingly close to the [events spec](../requirements/caspian/events/) we already settled, plus a cooperative main loop.
- **Tk / Tcl** — `bind` widgets to commands. Tiny, explicit.

### Game-engine-style ECS / scene-graph

Every GameObject has `Update()` called per frame; components are attached behaviors; events propagate through the scene tree.

- **Unity / Unreal / Godot** — the dominant model. Not async exactly, but the "tree of living things with behaviors" framing is strong.

---

## The closest blend for Caspian's shape

Single-threaded, cooperative, server-oriented, server-as-object-hive — that combination points most strongly at **MOO + Erlang patterns**:

- **MOO** gives the "the program is a world" framing. A LambdaMOO server holds a graph of objects (rooms, items, players); inputs from sockets dispatch to verbs on objects. The program literally is the world; you don't write `def main():` because the program IS the running state. This matches the "Caspian-as-Mikobase-mirror" intuition very closely — a Mikobase IS a running collection of objects, and so is a MOO.
- **Erlang** gives the cleaner mechanics — message-passing primitives, mailboxes, `receive`. Cooperative scheduling that fits the "no threads" constraint. The actor model's "things waiting to be triggered" maps directly onto what the vision describes.
- **Qt's signals and slots** is interesting as a third reference, because the [events system](../requirements/caspian/events/) already settled in Caspian is essentially that pattern. The infrastructure exists; what's missing is the "things are alive and waiting" framing on top.

The combination would be: each Caspian object can broadcast events and listen for them (the existing event system handles this); a long-running server program drains a queue of work using the cooperative event-loop pattern (see [engine-events.md](caspian/engine-events.md)); and the server's "world" is the graph of live objects that receive and react to incoming inputs.

That's not a spec yet — it's a way of looking at where the existing pieces could fit together to produce the "hive" feeling Caspian is reaching for.

---

## Open question

Which of these analogous systems would help you clarify the vision further? Three angles to dig into:

1. **The actor / message-passing mechanics** — Erlang-style mailboxes, `receive`, cooperative scheduling. What primitives the runtime needs to make objects feel like they're "alive in parallel."
2. **The program-is-a-world framing** — MOO-style. What it means for a Caspian program to not have a `main()` but instead BE the running collection of objects. How that maps onto Mikobase's already-living model.
3. **The signals / event-binding pattern** — Qt-style. How the existing event system in Caspian gets dressed up with the "alive object" framing on top.

Pick one to push deeper on next, or steer to something else this brainstorm should surface.
