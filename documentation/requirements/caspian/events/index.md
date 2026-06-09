# Events

~~~vibecode
{"vibecode": {
	"doc": "events",
	"role": "spec for Caspian's event-broadcasting system — any object can listen for events broadcast by any other object. The source explicitly broadcasts via %utils.broadcast; listeners register either by naming a method on themselves (.object.listen_to with method-name string) or by passing a closure (%utils.register with do block). The engine routes broadcast → handler calls. Zero cost when no listeners are registered; synchronous single-threaded execution; registrations clean up automatically via GC for the method-name form, and via source-GC or explicit unregister for the closure form.",
	"status": "spec — major decisions settled; some open points remain (unregister API, custom exception class names, runtime-state location details)",
	"audience": "Caspian programmers using events; engine implementers wiring the broadcast path",
	"key_concepts": ["explicit_source_broadcast_via_percent_utils_broadcast",
		"two_registration_forms_method_name_and_closure",
		"handler_signature_broadcaster_plus_event_name_plus_args",
		"zero_cost_when_no_listeners_registered",
		"registration_order_for_handler_invocation",
		"idempotent_registration_for_method_name_form",
		"exceptions_bubble_normally_remaining_handlers_dont_fire",
		"synchronous_nested_broadcast_no_special_cases",
		"gc_cleans_up_registrations_on_both_ends_for_method_name_form",
		"introspection_supported"]
}}
~~~

Any Caspian object can listen for events broadcast by any other object. The source explicitly **broadcasts** via `%utils.broadcast`; listeners **register** either by naming a method on themselves (`.object.listen_to`) or by passing a closure (`%utils.register`). The engine routes broadcast → handler calls.

Two things this design avoids by construction:

- **No mutation-fired events.** The engine's mutation paths stay zero-overhead. Events only fire when source code explicitly calls `%utils.broadcast`.
- **No listener-check tax on bystander objects.** A source with zero listeners pays one branch (a count check) per `broadcast` call, then returns. The system never walks "all listeners in the program."

---

<a id="broadcast"></a>
## Broadcast

A source broadcasts by calling `%utils.broadcast` from inside one of its own methods:

```
%utils.broadcast 'event_name', arg1, arg2, ...
```

(`broadcast` is the name of the dispatch primitive in the `%utils` namespace; some earlier drafts used `dispatch`.)

- The source is implicit — `%self` at the call site.
- The event name is a string. Any string is accepted; the engine doesn't validate that the source "declared" the event.
- Trailing args are the payload. Any number of args (zero or more), of any type. The handler is expected to match the shape; mismatches surface at the handler call.
- Returns: the integer **count of handlers that fired**.

Example — a socket broadcasting a new inbound connection:

```
%utils.broadcast 'new_connection', {'received': 'something'}
```

If no one is listening for `'new_connection'` on this source, the call does nothing and returns `0`.

---

<a id="listen"></a>
## Listen

Two registration forms. Both produce the same kind of registration (same registry, same dispatch order, same exception handling); they differ only in how the handler is identified.

### Method-name form

A listener registers by naming a method on itself:

```
$listener.object.listen_to $source, 'event_name', 'method_name'
```

- `$listener` — the object that will receive the handler call.
- `$source` — the object whose broadcasts trigger this handler.
- `'event_name'` — the event name as a string. Must match what the source broadcasts.
- `'method_name'` — the name of the method on `$listener` that the system will call when the event fires.

No validation at registration time. The source isn't checked to ever broadcast `'event_name'`; the listener's class isn't checked to have `'method_name'`. Registration is purely bookkeeping.

Example — `$foo` listens for `'new_connection'` on `$socket`, dispatching to its `log` method:

```
$foo.object.listen_to $socket, 'new_connection', 'log'
```

### Closure form

A closure can be registered directly, with no listener object involved:

```
%utils.register $source, 'event_name' do(...closure_params...)
    # handler body
end
```

- `$source` — the object whose broadcasts trigger this handler.
- `'event_name'` — the event name as a string.
- The `do ... end` block is the handler — a closure capturing its surrounding lexical scope.

Example — register a closure that logs new connections on `$socket`:

```
%utils.register $socket, 'new_connection' do($broadcaster, $event_name, $payload)
    puts 'new connection on ' + $broadcaster.id
    puts $payload.received
end
```

The closure runs in its **defining role** (per Caspian's closure-as-defining-role rule), so handler code runs with the same authority as the surrounding scope at registration time. This matches the method-name form's behavior (method runs in its class's role) — both forms place handler code in the role that wrote it, not the role that broadcast.

### When to use each

- **Method-name form** when the listener is a long-lived object with a well-defined response method. The method is inheritable, testable, named in the class definition. Lifetime tied to the listener (GC of the listener cleans up the registration).
- **Closure form** when the handler is a quick inline reaction with no obvious owning object. Captures local variables without needing a wrapping class. Lifetime tied to the source (GC of the source cleans up the registration); see [Garbage collection](#garbage-collection) for the asymmetry.

---

<a id="handler-signature"></a>
## Handler signature

When the broadcast fires, the system passes three categories of arguments to the handler:

```
handler($broadcaster, 'event_name', arg1, arg2, ...)
```

- **First arg:** the broadcaster object.
- **Second arg:** the event name string.
- **Remaining args:** whatever the broadcaster passed after the event name in `%utils.broadcast`.

Both registration forms use the same signature:

- **Method-name form** — the handler is `$listener.method_name(...)`, invoked as a regular method dispatch. Runs in the role of the class that defined the method.
- **Closure form** — the handler is the closure registered with `%utils.register`. Runs in the closure's defining role (per Caspian's closure-as-defining-role rule).

Cross-role broadcasts work automatically: the broadcaster broadcasts in its own role, the handler runs in its own role, only the payload args cross the role boundary.

Example handlers — method-name form and closure form, same signature:

```
class foo.com/foo
    method log($broadcaster, $event_name, $payload)
        # do something with the received payload
    end
end

%utils.register $socket, 'new_connection' do($broadcaster, $event_name, $payload)
    puts 'connection on ' + $broadcaster.id
end
```

A closure can declare fewer params than the handler signature provides (per Caspian's normal closure-arity semantics) if it only cares about some of them — e.g., `do($payload)` for closures that don't need the broadcaster or event name.

---

<a id="behavior"></a>
## Behavior

### Zero cost when no listeners

A source object carries a small counter — number of registrations currently pointing at it. `%utils.broadcast` checks the counter first; zero means return immediately. No registry walk, no global scan. The engine never asks "are there listeners anywhere in the program?" — it only asks "are there listeners on THIS source?"

For the overwhelming majority of objects (which are never listened to by anyone), the cost of supporting events is one branch per `broadcast` call. The mutation hot path is unaffected entirely.

### Registration order

When multiple listeners are registered for the same event on the same source, handlers fire in **the order they were registered**. First registered → first fired.

### Idempotent registration (method-name form)

Calling `listen_to` with the same `(listener, source, event_name, method_name)` tuple a second time is silently ignored. Registration is idempotent for the method-name form — no duplicates, no error, no warning.

Closures don't have comparable identity in the same way, so the idempotency rule doesn't apply to the closure form: each call to `%utils.register` creates a distinct registration even if the closure body is identical. Registering "the same" closure twice produces two registrations that both fire on broadcast.

### Multiple methods on the same source / event

Same listener + source + event_name with **different method names** creates separate registrations. Each registered method fires on broadcast:

```
$foo.object.listen_to $socket, 'new_connection', 'log'
$foo.object.listen_to $socket, 'new_connection', 'audit'
# Both $foo.log and $foo.audit fire when $socket broadcasts 'new_connection'.
```

The closure form has no method-name distinction; each `%utils.register` call is its own registration.

### Self-listening

An object can listen to itself with the method-name form. No special case:

```
$foo.object.listen_to $foo, 'event_name', 'method_name'
```

When `$foo` broadcasts `'event_name'`, its own `method_name` fires (as one of the handlers).

### Payload mutation

Payload args are passed by reference. A handler can mutate them, and subsequent handlers see the mutated values. This is intentional — handlers can deliberately communicate by chaining through the payload.

If a broadcaster doesn't want its payload mutated, it should freeze the hash or [jail](../network/http/client/index.md#http-jail) the object before dispatching.

### Exceptions bubble normally

If a handler raises an exception, it bubbles up through `%utils.broadcast` the same way any exception bubbles through a method call. Remaining handlers don't fire — they're never reached because the exception unwinds the stack. The dispatching code can catch the exception with normal `catch`.

### Synchronous nested broadcasts

If a running handler calls `%utils.broadcast` (on the same source, on a different source — doesn't matter), the nested broadcast runs to completion before the outer handler continues. Single-threaded straight-through call chain. No reentry suppression, no queueing, no special cases.

The natural consequence: a handler that broadcasts back to its source can cause unbounded recursion. That's user responsibility — the engine doesn't intervene.

### Garbage collection

- **When a source is collected**, all registrations on it (both method-name and closure forms) are cleaned up. No notification is sent — listeners just stop receiving events from a source that's gone.
- **Method-name form: registrations don't keep listeners alive.** A listener referenced only by registrations is eligible for collection; when it's collected, the registrations pointing at it are cleaned up. No notification.
- **Closure form: the closure is owned by the registration.** A closure registered via `%utils.register` is reachable through the registration table, so it stays alive as long as the source does. It doesn't have a separate "listener" identity to be collected independently. To remove a closure registration before the source goes away, an explicit unregister API is needed (see [open points](#open-points)).

All cleanups are silent. The invariant: registrations exist only while both ends are live, where "both ends" for the closure form collapses to just the source.

### Introspection

The system supports queries for debugging and inspection:

- "What is `$foo` listening to?" — list of `(source, event_name, method_name)` tuples for method-name registrations where `$foo` is the listener. (Closures aren't owned by a listener object, so they don't appear in this query.)
- "Who is listening to `$source`?" — list of all registrations on `$source`, including both method-name entries (with listener + method_name) and closure entries (probably with source-location info — the file:line where `%utils.register` was called).

The exact API surface for these queries is TBD; the capability is committed.

---

<a id="custom-exceptions"></a>
## Custom exceptions

Two custom exception classes carry event-system-specific failures (final class names TBD):

| Class (working name) | When raised |
|---|---|
| `puck.uno/error/trigger/missing_method` | A broadcast tries to call a method that doesn't exist on the listener. The registration succeeded earlier; the failure shows up at dispatch time. |
| `puck.uno/error/trigger/source_gone` | A broadcast attempts to fire on a source whose registrations should have been cleaned up but weren't. Shouldn't happen in normal operation (registrations clean up with source GC); the class exists for engine bad-state recovery. |

Both classes inherit from the standard Caspian exception base, can be caught with `catch`, and carry context about which source, event, listener, and method name was involved.

---

<a id="open-points"></a>
## Open points

- **Unregister API.** Currently no explicit method to stop listening before either end is collected. The method-name form handles cleanup via GC of the listener; **the closure form has no equivalent** (the closure has no listener identity, so it sticks around for the source's lifetime). An explicit unregister handle returned from `%utils.register` and `listen_to` is the obvious shape — TBD whether it's the only path or sits alongside GC-based cleanup.
- **Custom exception class names.** Working names use `puck.uno/error/trigger/*`; the eventual rename will happen alongside the broader URL-prefix decisions.
- **Runtime state location.** Registrations are runtime state (per-source counter, full registration entries with handler reference + event_name + form-specific identity, the `by_source` lookup index). They live somewhere in the engine's runtime hash; specifics deferred to the implementation pass.
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
			%utils.broadcast 'got-content', $content
		end
	end
end
~~~

### Script

~~~caspian
$srv = $server.new()

# Log content to stdout
%utils.register($srv, 'got-content') do($broadcaster, $event_name, $content)
	puts 'got: ' + $content
end

$srv.run 6667
~~~

### What's happening

1. `$srv.run(6667)` opens a TCP listener and enters its `wait` loop.
2. Content arrives over the network.
3. The `wait` closure fires with the content.
4. The closure calls `%utils.broadcast('got-content', $content)`. `$self` inside the closure is `$srv` (the closure was defined in `$srv.run`'s body), so the broadcast comes FROM the server.
5. The driver's registered closure handler fires and prints the content.
6. Handler returns. Broadcast returns. Wait returns to waiting.

### Notes

- **`@listener.wait do(...)` is a network-layer convenience, not part of the event system.** It's a method on the listener that takes a closure and blocks until content arrives. The actual event-system primitives (`%utils.broadcast` and `%utils.register`) are what the closure body uses to publish what it received.
- **The broadcaster is implicit.** `%utils.broadcast` uses `$self` to identify the source. `$self` inside `&run` is the server instance, so broadcasts come FROM the server. The driver's registration on `$srv` matches.
- **No per-connection object.** The simpler version doesn't model individual connections — the server just receives content and broadcasts it. A richer model with per-connection wrappers is below.

---

<a id="example-chat-server"></a>
## Example: chat server

A small chat room — server, per-client wrappers, and a driver — that demonstrates layered broadcasting (sockets broadcast, clients broadcast, server broadcasts), both registration forms, and the cleanup pattern when clients disconnect.

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
			%utils.broadcast('message', {text: $line})
		end
	end

	function &on_socket_closed($broadcaster, $event_name, $payload)
		# Bubble the closed event up so the server can clean up
		%utils.broadcast('closed', {reason: $payload.reason})
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
	%utils.broadcast('new_connection', {
		connection:  $new_conn,
		remote_addr: $remote
	})
	$new_conn
end
~~~

Inside the connection socket's read loop:

~~~caspian
function &on_kernel_data_arrival($bytes)
	%utils.broadcast('data_received', {bytes: $bytes})
end
~~~

### Script

~~~caspian
$server = $chat_server.new(port: 6667, client_class: $chat_client)
$server.start

# Optional — quick anonymous metrics listener using the closure form
$message_count = 0
%utils.register($server, 'message_relayed') do($broadcaster, $event_name, $payload)
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
4. `on_data` calls `%utils.broadcast 'message', {text: ...}` — `$self` is the chat_client, so the broadcast is FROM the client.
5. The server has registered for `'message'` on this client. Its `on_client_message` handler fires.
6. `on_client_message` iterates `@clients` and writes the line to every other client's socket. Each `write` calls `@socket.send_all` — synchronous I/O completes before the next iteration.
7. All writes done. Broadcast count returns. `on_data` returns. The socket's broadcast returns. The kernel-data-receive returns.

### Notes on the example

- **Layered broadcasting.** Three layers (socket → client → server → other clients' sockets). Each layer translates raw events into higher-level semantics. The chat_client converts byte-level `data_received` into message-level `message`.
- **`$self` IS the broadcaster.** When chat_client calls `%utils.broadcast 'message', {...}`, the engine uses `$self` (the chat_client instance) as the broadcaster. The server registered ON THAT specific client, so the dispatch finds the right handler.
- **Cleanup via `closed` events.** Both the client and server use `closed` events to know when to drop a connection from their lists. No explicit unregister needed — when the socket is collected, its registrations clean up; when the client is collected (after the server removes it from `@clients`), its registrations on the socket clean up; the chain unwinds naturally.
- **Synchronous cascade has a scale risk.** The chat_client's `on_data` broadcasts `'message'` synchronously. That triggers the server's `on_client_message`, which writes to each other client's socket. If any of those writes are slow (slow network client), the entire pipeline blocks. Fine for a small chat room; pathological at scale. The answer at scale would be forking or per-client work queues, neither of which is part of the event system itself.
- **Closure-form metrics in the driver.** The closure form is good for inline observers like a global counter — there's no obvious owning object and there's no value in making one just to hang a method on. Lifetime tied to the server: when the server goes away, the counter closure goes with it.
- **Loop-in-loop risk.** If the server's `on_client_message` happened to broadcast something the chat_client was listening for, and that broadcast triggered another `'message'` from the same client, you'd recurse. That's user responsibility; the engine doesn't intervene.

---

## See also

- [`%utils`](../global-methods/utils/) — the system-utility namespace `broadcast` and `register` live under.
- [`.object` meta-namespace](../built-in-classes/object.md) — where `listen_to` and the introspection methods live.
- [Roles](../roles.md) — handler-runs-in-its-own-role follows from normal method dispatch.
