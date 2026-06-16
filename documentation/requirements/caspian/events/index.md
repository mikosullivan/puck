# Events

~~~vibecode
{"vibecode": {
	"doc": "events",
	"role": "spec for Caspian's event-broadcasting system — any object can broadcast events; any object (or any anonymous closure) can register a handler for someone else's events. The source broadcasts via %self.object.broadcast. Handlers register via three forms: a method on a listener, a closure on a listener, or a closure directly on the broadcaster. All registrations live in a single engine-level event table; GC cleans up rows when participants go out of scope.",
	"status": "spec — major decisions settled; some open points remain (unregister API, custom exception class names, class-level opt-in)",
	"audience": "Caspian programmers using events; engine implementers wiring the broadcast path",
	"key_concepts": ["explicit_source_broadcast_via_percent_self_object_broadcast",
		"three_registration_forms_method_name_closure_on_listener_closure_on_broadcaster",
		"single_engine_level_event_table",
		"weak_references_to_participants_strong_references_to_anonymous_closures",
		"row_lifetime_bounded_by_participants_alive",
		"handler_signature_includes_source_event_name_and_payload_args",
		"registration_order_for_handler_invocation",
		"idempotent_registration_for_method_name_form",
		"exceptions_bubble_normally_remaining_handlers_dont_fire",
		"synchronous_nested_broadcast_no_special_cases",
		"gc_cleans_up_rows_for_either_end_going_out_of_scope",
		"introspection_supported"]
}}
~~~

Any Caspian object can listen for events broadcast by any other object. The source explicitly **broadcasts** via `%self.object.broadcast`; handlers register through one of three forms — a method on a listener, a closure tied to a listener, or a closure tied directly to the broadcaster. The engine routes broadcast → handler calls.

Two things this design avoids by construction:

- **No mutation-fired events.** The engine's mutation paths stay zero-overhead. Events only fire when source code explicitly calls `%self.object.broadcast`.
- **No bookkeeping on bystander objects.** Objects that nobody ever listens to and that never broadcast pay nothing for the event system. A broadcaster with no listeners pays one hash lookup per `broadcast` call that returns empty. The system never walks "all listeners in the program."

---

<a id="broadcast"></a>
## Broadcast

A source broadcasts by calling `%self.object.broadcast` from inside one of its own methods:

```
%self.object.broadcast 'event_name', arg1, arg2, ...
```

- The source is `%self` — the object the call dispatches on.
- The event name is a string. Any string is accepted; the engine doesn't validate that the source "declared" the event.
- Trailing args are the payload. Any number of args (zero or more), of any type. The handler is expected to match the shape; mismatches surface at the handler call.
- Returns: the integer **count of handlers that fired**.

Example — a socket broadcasting a new inbound connection:

```
%self.object.broadcast 'new_connection', {'received': 'something'}
```

If no one is listening for `'new_connection'` on this source, the call does nothing and returns `0`.

---

<a id="listen"></a>
## Three ways to register a handler

A handler can be registered in three forms. All three put a row in [the event table](#the-event-table) and dispatch on broadcast the same way; they differ in **what holds the handler** and **whose lifetime governs the registration**.

### Method-name form (on a listener)

A listener registers by naming one of its own methods:

```
$listener.object.listen_to $source, 'event_name', 'method_name'
```

- `$listener` — the object that will receive the handler call.
- `$source` — the object whose broadcasts trigger this handler.
- `'event_name'` — the event name as a string. Must match what the source broadcasts.
- `'method_name'` — the name of the method on `$listener` that the system will call when the event fires.

No validation at registration time. The source isn't checked to ever broadcast `'event_name'`; the listener's class isn't checked to have `'method_name'`. Registration is purely bookkeeping.

Example — `$logger` listens for `'new_connection'` on `$socket`, dispatching to its `write_to_log` method:

```
$logger.object.listen_to $socket, 'new_connection', 'write_to_log'
```

### Closure form (on a listener)

A listener can pass a closure directly to `listen_to` instead of a method-name string:

```
$listener.object.listen_to($source, 'event_name') do(...closure_params...)
    # handler body
end
```

The closure captures its lexical scope at the registration site. Use this when the handler doesn't justify a named method on the listener's class (an inline reaction, a quick observer, etc.).

Example — register a closure on `$logger` that logs new connections on `$socket`:

```
$logger.object.listen_to($socket, 'new_connection') do($event_name, $payload)
    puts 'new connection: ' + $payload.received
end
```

### Closure form (on the broadcaster)

A closure can be registered directly on the broadcaster, with no listener identity:

```
$source.object.on_broadcast('event_name') do(...closure_params...)
    # handler body
end
```

- `$source` — the broadcaster whose events trigger this closure.
- `'event_name'` — the event name as a string.
- The `do ... end` block is the handler closure.

The closure is anchored to the broadcaster; when the broadcaster is collected the registration goes with it. Each `on_broadcast` call **adds** a new closure to the broadcaster's set for that event — never overrides a previous registration.

Example — wire up a quick logger directly on the server:

```
$server.object.on_broadcast('got_request') do($event_name, $request)
    %stdout.puts 'request: ' + $request.summary
end
```

This form is useful when the developer holds a reference to the broadcaster, wants to attach a reaction, and has no separate listener object to bind it to. In spirit it's the same as a listener registering — just without the ceremony of inventing a listener.

### When to use each

- **Method-name form** when the listener has a well-defined response method. The method is inheritable, testable, named in the class definition.
- **Closure on a listener** when the handler should be captured inline but the developer wants the registration scoped to a particular listener's lifetime (cleanup when either end goes).
- **Closure on the broadcaster** when there's no separate listener — the developer just wants a closure to react when this broadcaster fires this event. Cleanup is broadcaster-tied.

All three forms register the same way underneath ([see the event table](#the-event-table)) and fire in registration order.

---

<a id="handler-signature"></a>
## Handler signature

When the broadcast fires, the system invokes the handler with this signature:

- **Method-name form** — the method is called as `$listener.method_name($source, $event_name, $args...)`. The source is the first arg because the method is a regular method on the listener's class and doesn't have lexical capture of the source.
- **Closure form (either kind)** — the closure is called with `($event_name, $args...)`. The source isn't passed as a parameter because, in both closure forms, the closure body captures whatever it needs (either lexically, or — for `on_broadcast` — via the broadcaster's role context if needed).

In all three cases, the trailing `$args...` are exactly what the broadcaster passed to `%self.object.broadcast` after the event name.

Example — same signature shapes for the two registration styles:

```
class
    method &write_to_log($server, $event_name, $request)
        # method-name form: source is the first parameter
    end
end
```

```
$logger.object.listen_to($server, 'got_request') do($event_name, $request)
    # closure-on-listener: source is captured lexically as $server
end
```

```
$server.object.on_broadcast('got_request') do($event_name, $request)
    # closure-on-broadcaster: source is reachable via $server too
end
```

Cross-role broadcasts work automatically: the broadcaster broadcasts in its own role, the handler runs in its own role (the method's class role or the closure's defining role), only the payload args cross the role boundary.

---

<a id="the-event-table"></a>
## The event table

All registrations live in a single engine-level data structure called **the event table**. There is one event table per Caspian process; every register/unregister/broadcast goes through it.

Each row carries:

- **`source`** — the broadcaster.
- **`listener`** — the registered listener (or absent for the `on_broadcast` form).
- **`event_name`** — the event name string.
- **`handler`** — either a method name (for the method-name form) or an actual closure object (for the two closure forms).

The table holds **weak references to participants and strong references to anonymous closures.** Specifically:

- The references to `source` and `listener` are weak: they don't extend the participants' lifetimes. The participants live wherever they normally live (variables, attributes, scopes, the engine's runtime); the table just records that they're connected.
- For rows whose handler is an anonymous closure (closure form on a listener, or closure form on the broadcaster), the closure itself is stored in the row. The closure's home IS the row; its lifetime is the row's lifetime.

**Broadcast lookup.** On `%self.object.broadcast 'event_name', args...`, the engine queries the event table for rows where `source == %self AND event_name == 'event_name'`, then invokes each row's handler in registration order. The hash-indexed lookup returns empty in O(1) for sources with no listeners, so the "zero listeners" fast path falls out of the data structure without needing a separate counter.

**Row removal.** A row is removed when either of its participants is collected (a source going out of scope removes all its rows; a listener going out of scope removes all rows where it's the listener; for the `on_broadcast` form there's no listener, so only the source's lifetime applies). The engine implements this through whatever GC mechanism is appropriate to the host runtime — weak-reference notifications, finalizers, or sweeps — but the observable contract is just "row alive iff participants alive."

Routine cleanup is silent: a participant going out of scope is the normal way to stop listening, and the engine doesn't warn about it.

---

<a id="behavior"></a>
## Behavior

<a id="registration-order"></a>
### Registration order

When multiple handlers are registered for the same event on the same source, they fire in **the order they were registered**. First registered → first fired.

<a id="idempotent-registration-method-name-form"></a>
### Idempotent registration (method-name form)

Calling `listen_to` with the same `(listener, source, event_name, method_name)` tuple a second time is silently ignored. Registration is idempotent for the method-name form — no duplicates, no error, no warning.

Closures don't have comparable identity in the same way, so the idempotency rule doesn't apply to closure forms: each `listen_to` (closure variant) or `on_broadcast` call creates a distinct row, even if the closure body is identical. Registering "the same" closure twice produces two rows that both fire on broadcast.

<a id="multiple-methods-on-the-same-source-event"></a>
### Multiple handlers on the same source / event

Same source + event_name with multiple registrations creates multiple rows. Each fires on broadcast:

```
$foo.object.listen_to $socket, 'new_connection', 'log'
$foo.object.listen_to $socket, 'new_connection', 'audit'
# Both $foo.log and $foo.audit fire when $socket broadcasts 'new_connection'.

$socket.object.on_broadcast('new_connection') do($event_name, $payload)
    %stdout.puts 'metric: connection received'
end
# This closure also fires, in registration order with the others.
```

<a id="self-listening"></a>
### Self-listening

An object can listen to itself. No special case — the broadcaster and listener happen to be the same object:

```
$foo.object.listen_to $foo, 'my_event', 'my_handler'
```

The same applies to `on_broadcast` — registering a closure on the broadcaster for one of its own events is just the normal use case.

<a id="payload-mutation"></a>
### Payload mutation

Handlers see live references to the payload args, not copies. A handler that mutates a payload object visibly affects subsequent handlers and the broadcaster's view of that object after broadcast returns. This is normal Caspian object-reference behavior; the event system doesn't copy or freeze payloads.

<a id="exceptions-bubble-normally"></a>
### Exceptions bubble normally

If a handler raises an exception, it bubbles up through `%self.object.broadcast` the same way any exception bubbles through a method call. Remaining handlers don't fire — they're never reached because the exception unwinds the stack. The dispatching code can catch the exception with normal `catch`.

<a id="synchronous-nested-broadcasts"></a>
### Synchronous nested broadcasts

If a running handler calls `%self.object.broadcast` (on the same source, on a different source — doesn't matter), the nested broadcast runs to completion before the outer handler continues. Single-threaded straight-through call chain. No reentry suppression, no queueing, no special cases.

The natural consequence: a handler that broadcasts back to its source can cause unbounded recursion. That's user responsibility — the engine doesn't intervene.

<a id="garbage-collection"></a>
### Garbage collection

The contract is simple: **a row in the event table is alive only while its participants are alive.**

- **Method-name form:** row removed when either `$listener` or `$source` is collected.
- **Closure on a listener:** row removed when either `$listener` or `$source` is collected; the anonymous closure stored in the row dies with the row.
- **Closure on the broadcaster (`on_broadcast`):** row removed when `$source` is collected; the anonymous closure stored in the row dies with the row.

No notification is sent to surviving participants — they just stop being involved in broadcasts that no longer exist. All cleanups are silent, considered normal lifecycle behavior. The rows aren't extending anyone's lifetime; the participants live wherever the program's normal references live them, and routine GC handles the rest.

<a id="introspection"></a>
### Introspection

The system supports queries for debugging and inspection:

- "What is `$foo` listening to?" — list of rows where `$foo` is the listener (method-name form or closure-on-listener).
- "Who is listening to `$source`?" — list of all rows where `$source` is the source, including method-name entries, closure-on-listener entries, and `on_broadcast` entries.

Closure entries don't have a method-name handle, so they probably surface with source-location info (the file:line where they were registered) as their identifier. Exact API surface is TBD.

---

<a id="custom-exceptions"></a>
## Custom exceptions

Two custom exception classes carry event-system-specific failures (final class names TBD):

| Class (working name) | When raised |
|---|---|
| `puck.uno/error/trigger/missing_method` | A broadcast tries to call a method that doesn't exist on the listener. The registration succeeded earlier; the failure shows up at dispatch time. |
| `puck.uno/error/trigger/source_gone` | A broadcast attempts to fire on a source whose rows should have been cleaned up but weren't. Shouldn't happen in normal operation; the class exists for engine bad-state recovery. |

Both classes inherit from the standard Caspian exception base, can be caught with `catch`, and carry context about which source, event, listener, and handler was involved.

---

<a id="open-points"></a>
## Open points

- **Unregister API.** Currently no explicit method to stop listening before either end is collected. The participant-GC story covers most cases, but long-lived broadcasters that accumulate closure registrations (via `on_broadcast` or the closure-on-listener form) have no in-program way to shed them. An unregister handle returned from `listen_to` / `on_broadcast` is the obvious shape — TBD whether it's the only path or sits alongside GC-based cleanup.
- **Custom exception class names.** Working names use `puck.uno/error/trigger/*`; the eventual rename will happen alongside the broader URL-prefix decisions.
- **Introspection API surface.** The capability is committed; the method names and return shapes are TBD. Closure entries need a meaningful identifier for the "who is listening?" query — source-location (file:line) is the obvious candidate.
- **Class-level "I can be listened to" declaration.** Whether objects implicitly support events or have to opt in at the class level isn't yet settled. Implicit-on with engine-internal carve-outs is the simpler default; explicit class-level opt-in is more disciplined.

---

<a id="example-content-broadcaster"></a>
## Example: simple content broadcaster

A minimal server that opens a TCP listener, broadcasts whatever content arrives, and lets external code register handlers for the broadcast.

### The server class

~~~caspian
$server = class
	method &run($port)
		@listener = %net.tcp_listen('0.0.0.0', $port)

		@listener.wait do($content)
			%self.object.broadcast 'got-content', $content
		end
	end
end
~~~

### Script

~~~caspian
$srv = $server.new()

# Log content to stdout
$srv.object.on_broadcast('got-content') do($event_name, $content)
	%stdout.puts 'got: ' + $content
end

$srv.run 6667
~~~

### What's happening

1. `$srv.run(6667)` opens a TCP listener and enters its `wait` loop.
2. Content arrives over the network.
3. The `wait` closure fires with the content.
4. The closure calls `%self.object.broadcast('got-content', $content)`. `%self` inside the closure is `$srv` (the closure was defined in `$srv.run`'s body), so the broadcast comes FROM the server.
5. The driver's registered closure handler fires and prints the content.
6. Handler returns. Broadcast returns. Wait returns to waiting.

### Notes

- **`@listener.wait do(...)` is a network-layer convenience, not part of the event system.** It's a method on the listener that takes a closure and blocks until content arrives. The actual event-system primitive (`%self.object.broadcast`) is what the closure body uses to publish what it received.
- **The broadcaster is `%self` — explicit in the call.** `%self.object.broadcast` dispatches on `%self`, so the broadcaster is whatever `%self` resolves to at the call site. `%self` inside `&run` is the server instance, so broadcasts come FROM the server. The driver's `on_broadcast` registration on `$srv` matches.
- **No per-connection object.** The simpler version doesn't model individual connections — the server just receives content and broadcasts it. A richer model with per-connection wrappers is below.

---

<a id="example-chat-server"></a>
## Example: chat server

A small chat room — server, per-client wrappers, and a driver — that demonstrates layered broadcasting (sockets broadcast, clients broadcast, server broadcasts), all three registration forms, and the cleanup pattern when clients disconnect.

### The chat server

Listens for incoming connections; wraps each one in a chat_client; broadcasts each received message to all other clients; removes clients on disconnect.

~~~caspian
$chat_server = class
	field :port,         class: :number, integer_only: true, required: true
	field :client_class, class: :class,                       required: true

	function &new(port:, client_class:)
		@port = $port
		@client_class = $client_class
		@clients = []
	end

	function &start()
		@listener = %net.tcp_listen('0.0.0.0', @port)
		# Listen for new connections on our socket
		%self.object.listen_to(@listener, 'new_connection', 'on_new_connection')
	end

	function &on_new_connection($broadcaster, $event_name, $payload)
		# Wrap the raw socket in a chat_client
		$client = @client_class.new(
			socket: $payload.connection,
			nick:   'guest-' + $payload.connection.id.first(8)
		)
		@clients << $client

		# When this client sends a message, broadcast it to the room
		%self.object.listen_to($client, 'message', 'on_client_message')

		# When this client disconnects, clean up
		%self.object.listen_to($client, 'closed', 'on_client_closed')

		# Greet the new client
		$client.write('welcome, ' + $client.nick + "\n")
	end

	function &on_client_message($from_client, $event_name, $payload)
		# Rebroadcast to every other connected client
		$line = $from_client.nick + ': ' + $payload.text + "\n"
		@clients.each do($c)
			if $c != $from_client
				$c.write($line)
			end
		end
	end

	function &on_client_closed($client, $event_name, $payload)
		@clients.remove($client)
	end
end
~~~

### The chat client

Represents one connected user. Listens on its own socket for incoming data and translates byte-level events into message-level events.

~~~caspian
$chat_client = class
	field :nick, class: :string, required: true

	function &new(socket:, nick:)
		@socket = $socket
		@nick = $nick
		# Listen on our own socket for incoming data
		%self.object.listen_to(@socket, 'data_received', 'on_data')
		%self.object.listen_to(@socket, 'closed',        'on_socket_closed')
	end

	function &on_data($broadcaster, $event_name, $payload)
		# Each line received is a message
		$line = $payload.bytes.trim
		if $line != ''
			# Broadcast 'message' so the room sees it
			%self.object.broadcast('message', {text: $line})
		end
	end

	function &on_socket_closed($broadcaster, $event_name, $payload)
		# Bubble the closed event up so the server can clean up
		%self.object.broadcast('closed', {reason: $payload.reason})
	end

	function &write($text)
		@socket.send_all($text)
	end
end
~~~

### The socket broadcast call sites

The socket layer itself initiates the cascade. Inside the `tcp_listener.accept` function (illustrative — the real function body lives in the network layer):

~~~caspian
function &accept(opts: null)
	$new_conn = .wait_for_kernel_accept
	$remote   = $new_conn.remote_addr
	%self.object.broadcast('new_connection', {
		connection:  $new_conn,
		remote_addr: $remote
	})
	$new_conn
end
~~~

Inside the connection socket's read loop:

~~~caspian
function &on_kernel_data_arrival($bytes)
	%self.object.broadcast('data_received', {bytes: $bytes})
end
~~~

### Script

~~~caspian
$server = $chat_server.new(port: 6667, client_class: $chat_client)
$server.start

# Optional — quick anonymous metrics directly on the server using on_broadcast
$message_count = 0
$server.object.on_broadcast('message_relayed') do($event_name, $payload)
	$message_count = $message_count + 1
end

# Run forever; the server is event-driven through the socket layer
forever
	$server.accept_one    # blocks; broadcasts cascade through it
end
~~~

### Event cascade for one received message

1. Kernel delivers a byte buffer to `$client.@socket`.
2. The socket broadcasts `'data_received'` with `{bytes: ...}`.
3. The chat_client's `on_data` handler runs (in chat_client's role).
4. `on_data` calls `%self.object.broadcast 'message', {text: ...}` — `%self` is the chat_client, so the broadcast is FROM the client.
5. The server has registered for `'message'` on this client. Its `on_client_message` handler fires.
6. `on_client_message` iterates `@clients` and writes the line to every other client's socket. Each `write` calls `@socket.send_all` — synchronous I/O completes before the next iteration.
7. All writes done. Broadcast count returns. `on_data` returns. The socket's broadcast returns. The kernel-data-receive returns.

### Notes on the example

- **Layered broadcasting.** Three layers (socket → client → server → other clients' sockets). Each layer translates raw events into higher-level semantics. The chat_client converts byte-level `data_received` into message-level `message`.
- **`%self` IS the broadcaster.** When chat_client calls `%self.object.broadcast 'message', {...}`, the engine uses `%self` (the chat_client instance) as the broadcaster. The server registered ON THAT specific client, so the dispatch finds the right handler.
- **Cleanup via `closed` events.** Both the client and server use `closed` events to know when to drop a connection from their lists. No explicit unregister needed — when the socket is collected, its rows in the event table clean up; when the client is collected (after the server removes it from `@clients`), its rows clean up too; the chain unwinds naturally.
- **Synchronous cascade has a scale risk.** The chat_client's `on_data` broadcasts `'message'` synchronously. That triggers the server's `on_client_message`, which writes to each other client's socket. If any of those writes are slow (slow network client), the entire pipeline blocks. Fine for a small chat room; pathological at scale. The answer at scale would be forking or per-client work queues, neither of which is part of the event system itself.
- **`on_broadcast` for inline metrics.** The closure form on the broadcaster is good for inline observers like a global counter — no listener needed, no method to invent on a class. Lifetime tied to the server: when the server goes away, the counter closure goes with it.
- **Loop-in-loop risk.** If the server's `on_client_message` happened to broadcast something the chat_client was listening for, and that broadcast triggered another `'message'` from the same client, you'd recurse. That's user responsibility; the engine doesn't intervene.

---

## See also

- [`.object` meta-namespace](../built-in-classes/object.md) — where `broadcast`, `listen_to`, `on_broadcast`, and the introspection methods live.
- [Roles](../roles.md) — handler-runs-in-its-own-role follows from normal method dispatch.
