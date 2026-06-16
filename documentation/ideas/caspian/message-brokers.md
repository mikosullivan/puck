# Message brokers and where Caspian could fit

~~~vibecode
{"vibecode": {
	"doc": "message_brokers",
	"role": "research report and speculation. Stuart raised the idea of Caspian implementing message brokers for microservices. This document surveys the existing Linux message-broker ecosystem (the major brokers, the common patterns they share, the use cases they cover) and then speculates on where Caspian could realistically fit — as a client, as an embeddable broker, as a distributed extension of its in-process event system, or as a persistence-backed messaging layer via Mikobase.",
	"status": "speculative idea report — not a commitment to any of these paths",
	"raised_by": "Stuart",
	"audience": "Miko, Stuart, anyone thinking about Caspian's networking and concurrency story",
	"key_concepts": ["message_brokers_in_linux", "microservices_messaging_patterns",
		"caspian_as_client_vs_caspian_as_broker", "extending_the_in_process_event_system",
		"mikobase_as_message_store", "puck_protocol_as_messaging_primitive"]
}}
~~~

Stuart's proposal: Caspian should support message brokers for microservices. This report surveys the existing Linux message-broker ecosystem, identifies the patterns common across the major systems, and speculates on the angles from which Caspian could plausibly participate — what's already partly there, what would be additive, and what would be a fundamentally different scope of project.

---

## Part 1: the major brokers

Six systems dominate Linux production deployments. Each occupies a different point in the design space.

### RabbitMQ

The classic enterprise broker. Implements [AMQP 0.9.1](https://www.rabbitmq.com/specification.html), with optional support for AMQP 1.0, MQTT, and STOMP. Publishers send to **exchanges**; exchanges route to **queues** via **bindings** with **routing keys**. Routing keys support wildcards (`*` for one segment, `#` for multiple), and exchanges come in flavors (direct, topic, fanout, headers) that decide how keys are matched.

Strengths: rich routing, mature management UI, broad ecosystem, well-understood. Queues can be persistent or transient, acknowledged or auto-acked, mirrored across nodes for HA.

Typical use: traditional task queues, request/reply patterns, decoupling synchronous APIs from background processing.

### Apache Kafka

A **distributed commit log**, not a queue. Topics are split into **partitions**, each an append-only ordered log. Consumers track their own **offsets** — meaning the broker doesn't remember who has read what; the consumer does. Messages are retained for a configurable time/size regardless of consumption.

This inversion (log instead of queue) makes Kafka a great fit for event sourcing, stream processing, audit trails, and cross-system replication. Less so for simple "do a task" patterns where Kafka's consumer-group complexity is overkill.

Strengths: extreme throughput, durable replay, total ordering within a partition, ecosystem (Kafka Streams, Kafka Connect, Schema Registry, etc.). Costs: operational complexity, JVM-based runtime, requires ZooKeeper or KRaft for coordination.

### Redis Pub/Sub and Streams

Redis ships two messaging primitives. **Pub/Sub** is fire-and-forget — subscribers receive messages only while they're connected, no persistence, no replay. **Streams** (added in Redis 5) are a Kafka-style append-only log with consumer groups, persistence, and replay.

The case for Redis-as-broker: Redis is already running in most stacks (as a cache), so adding messaging avoids deploying another service. Low operational overhead. Weaknesses: in-memory primary storage limits durability stories at high volumes; clustering is less mature than RabbitMQ or Kafka for messaging workloads.

### NATS

A lightweight, cloud-native messaging system. **Core NATS** is at-most-once pub/sub: subjects with wildcard subscriptions, no persistence, very low latency. **JetStream** layers on persistence, streams, key-value, object storage — turning NATS into a full messaging+storage system without the operational weight of Kafka.

Strengths: tiny binary (under 20 MB), single-binary deploy, designed from the start for microservice meshes. Native support for request/reply, queue groups (load balancing), subject hierarchies.

Often the right choice for new microservice systems that want messaging without the Kafka tax.

### MQTT brokers (Mosquitto, EMQX, HiveMQ)

[MQTT](https://mqtt.org/) is a lightweight pub/sub protocol designed for constrained devices and unreliable networks. Topics form a hierarchy (`sensors/floor1/temp`), wildcard subscriptions cover subtrees (`sensors/+/temp`), and three QoS levels (`0`/`1`/`2`) trade durability for latency.

MQTT dominates IoT and telemetry. The brokers (Mosquitto is the canonical OSS option; EMQX and HiveMQ for enterprise scale) are typically smaller and simpler than RabbitMQ.

### ZeroMQ

Not a broker — a **library**. ZeroMQ provides socket-like primitives with pub/sub, request/reply, push/pull, and other patterns built in. There's no central broker; each program is its own message router.

Useful when you want messaging *patterns* without running a broker service. Distributed semantics are still up to the application (no built-in persistence, no routing service).

### Honorable mentions

- **Apache Pulsar** — newer Kafka-alternative; separates compute from storage (BookKeeper underneath); multi-tenant by design.
- **ActiveMQ / Artemis** — JMS-centric, mature, popular in Java shops.
- **AWS SQS / SNS, Google Pub/Sub, Azure Service Bus** — managed services that occupy the same conceptual space. Often the right answer for cloud-native shops that don't want to operate a broker.

---

## Part 2: the patterns

Across all of the above, the recurring patterns:

### Topic-based pub/sub

A publisher sends to a named **topic** (or **subject** or **exchange-key** depending on the system); zero or more subscribers register interest in that topic and receive a copy. Wildcard subscriptions are common: `orders.*` matches `orders.created`, `orders.shipped`, etc.

### Work queue (point-to-point with load balancing)

A queue with multiple consumers; each message is delivered to exactly one consumer. The broker load-balances. Used for background-job processing where N workers share a backlog.

### Request / Reply

RPC over messaging. **RPC** — Remote Procedure Call — is the pattern of invoking a function or method on a remote machine using the same shape as a local call: pass arguments, wait for a return value, treat the network round-trip as an implementation detail. gRPC, JSON-RPC, XML-RPC, Java RMI, and ordinary HTTP request/response APIs are all RPC by this definition; Caspian's own [Puck protocol](https://puck.uno/documentation/requirements/puck/) is too. The defining property is "remote call that reads like a local call."

When RPC runs over a message broker instead of directly over HTTP, the mechanism is: the requester publishes a message that includes a `reply-to` address; the responder reads the request, does its work, and publishes the response to that address; the requester is subscribed to that address and consumes the reply. The caller and callee never share a direct connection — the broker carries the round-trip.

**Correlation IDs.** With more than one request in flight, the requester needs to match responses to the requests that asked for them. Every request carries a unique correlation ID; the responder echoes it in the reply. The requester maintains a small map of `correlation_id → pending_callback` (or `→ promise`, or `→ thread`) and dispatches incoming replies through it.

**Reply-to address shapes.** Three common patterns:

- **Per-request ephemeral.** The broker mints a one-shot reply queue/topic for each request. RabbitMQ's "direct reply-to" works this way (`amq.rabbitmq.reply-to` pseudo-queue); the queue exists for the lifetime of the request. Cheapest model when requests are rare; per-request setup cost when requests are frequent.
- **Per-requester persistent.** Each requesting service has its own private reply queue, set up once at startup. All its outbound requests use that queue as their reply-to. Correlation IDs distinguish responses within the queue. Best when one client makes many requests.
- **Shared topic.** All requesters subscribe to a common reply topic and filter by correlation ID. Simplest setup; pays a filtering cost on every reply across every requester. Rare outside small systems.

**Timeouts.** A request that gets no reply within some window has to expire — either because the responder is down, or the message was lost, or the work is taking longer than the requester can wait. The timeout is a client-side concern; the broker just forwards messages.

**Load balancing across many responders.** If multiple consumers subscribe to the request topic via a queue group (NATS), competing consumers (RabbitMQ), or consumer group (Kafka), the broker delivers each request to exactly one of them. The reply mechanism doesn't change — whichever responder handled the request publishes back to the same reply-to address.

**Broker-specific support.**

- **NATS.** First-class. `nc.request(subject, data, timeout)` handles correlation IDs, reply queue, and timeout in one call. Idiomatic; the cleanest request/reply story of any major broker.
- **RabbitMQ.** Direct reply-to or per-client callback queues. Well-supported through client libraries that abstract the bookkeeping.
- **Kafka.** Awkward fit. Kafka is a log, not a queue; the consumer-group model assumes durable retention. Request/reply on Kafka usually means two topics (one for requests, one for responses keyed on correlation ID) and is more friction than the other brokers. People who want request/reply on Kafka often add a sidecar (e.g., Spring Cloud Stream's `ReplyingKafkaTemplate`).
- **MQTT.** No native support, but MQTT 5.0 adds a `Response Topic` and `Correlation Data` property to messages, formalizing the pattern.

**Why use it instead of HTTP?** Three reasons stand out:

- **Address-independence.** Requester doesn't need to know where the responder lives — just the topic name. The responder can move, restart, scale up to N instances; the requester is unaffected. With HTTP, requester needs a URL.
- **Buffering across responder downtime.** If the responder is briefly down or saturated, the broker holds the request until a responder is available. With HTTP the request just fails.
- **Trivial load balancing.** Adding more responders is "start another subscriber"; the broker fans requests across them automatically. With HTTP you need a load balancer in front.

The cost: latency (extra hop through the broker), failure modes that are harder to reason about than HTTP's, and complexity if the system is small enough that direct HTTP would have just worked.

**When it's the right pattern.** Service-to-service calls where the responder is dynamic (autoscaled, may have N instances, may go down briefly), where the requester shouldn't be tightly coupled to the responder's address, and where the broker is already part of the system for other reasons. When none of those apply, plain HTTP is usually simpler.

### Fan-out

One publisher, many independent subscribers — each subscriber sees every message. Pub/sub's degenerate case when there's no routing.

### Fan-in / aggregator

Many publishers, one consumer that combines results.

### Streams / event log

A categorically different model from queues. Where a queue is "broker holds messages until consumed, then deletes them," a log is "broker keeps every message forever (or until retention expires), and each consumer reads at its own pace from its own position." The shift looks like a small detail but reshapes what's possible.

**Core properties:**

- **Append-only.** Producers append; nothing mutates or deletes existing messages. The log is the authoritative history.
- **Total ordering within a partition.** Messages in a single partition are strictly ordered by append time and remembered in that order. Across partitions, order isn't guaranteed (this is the trade-off for partition-based scaling).
- **Offset-based consumption.** Each message has an offset (its position in the log). Consumers track their own current offset; the broker never marks anything "consumed." This means multiple consumers can read the same log independently — none of them affects the others' position.
- **Replay.** A consumer can rewind to any offset and re-read. This is the headline feature: bug in your downstream processor, ship a fix, replay the log through the fixed processor, catch up to current state with corrected behavior. Queues can't do this — the messages are gone.
- **Retention policies.** Messages stay until they fall off the back. Retention is configurable per topic: time-based (keep 7 days), size-based (keep 100 GB), or compacted (keep only the latest message per key — a snapshot view).

**Specific implementations.**

- **Apache Kafka.** The reference implementation. Topics are split into partitions for horizontal scaling; each partition is its own ordered log. Consumers join consumer groups; within a group each message is processed by exactly one consumer, providing queue-like semantics on top of the log. Offsets are themselves stored in a special internal topic (`__consumer_offsets`), so consumer position survives consumer restarts. Millions of messages/sec on commodity hardware. **Operational weight is real** — JVM runtime, KRaft or ZooKeeper for coordination, partition-balancing complexity.
- **NATS JetStream.** Newer (2020), part of the NATS server. Streams subscribe to subjects; messages on those subjects are persisted to disk. Consumers read at their own offset, push or pull mode. **Much simpler to operate** than Kafka — single binary, no separate coordination service — at the cost of a lower throughput ceiling.
- **Redis Streams.** Added in Redis 5 as a first-class data type. `XADD` appends, `XREAD` reads from a position, `XREADGROUP` provides consumer-group semantics. **Persistence depends on the Redis configuration** (RDB snapshots, AOF append-only file); not strong by default since Redis is memory-first. Good fit when Redis is already deployed; weak choice for high-volume durable workloads.
- **Apache Pulsar.** Topics with separated storage (Apache BookKeeper) and compute (brokers). Multi-tenant by design. Less mature ecosystem than Kafka; lower per-message overhead in some workloads.

**Patterns the log model enables.**

- **Event sourcing.** The log is the system's authoritative history; database state is a *projection* of the log. Append every state-change event to the log; rebuild current state by folding events. Want a different view? Build a second projection from the same log. The database becomes derived, replaceable, reproducible.
- **CQRS** (Command Query Responsibility Segregation). Write side appends commands or events to the log; read side maintains denormalized projections optimized for queries. The two sides scale independently and can have totally different storage models.
- **Audit trail.** Every action is appended; the log is immutable. Compliance use cases (financial systems, healthcare) often require this kind of forensic record by regulation.
- **Replay-based bug fixes.** When a downstream service had a bug for some window, you can fix the bug and replay just that window through the corrected processor. No "lost data," no manual reconstruction.
- **Real-time analytics.** Stream processors (Kafka Streams, Apache Flink, Apache Spark Streaming) consume from the log and emit aggregations, rollups, anomaly detection, joins between streams.
- **Cross-system replication.** The log becomes the canonical source; multiple downstream services subscribe and maintain their own consistent views. Common in microservice systems where multiple services need read access to the same domain events.

**Concepts that don't appear in queue systems.**

- **Offset / position** — every consumer's view of "where I am in the log."
- **Consumer lag** — how far behind the head of the log a consumer is. A key operational metric: a consumer whose lag keeps growing is falling behind production rate.
- **Watermark** — the highest offset a consumer has committed back to the broker as durably processed.
- **Compaction** — a special retention mode where only the latest message per key is kept. Turns the log into a current-state snapshot keyed by message key. Useful for materializing state (the log IS the state).
- **Partitioning** — how the log is split for parallelism. Partition key determines which partition a message lands in; messages with the same key always land in the same partition, preserving per-key ordering.

**Cost trade-offs vs queues.**

| Concern | Queue | Log |
|---|---|---|
| Storage | Low (deleted after consumed) | High (retain everything for window) |
| Replay | Not possible | Native |
| Independent multi-consumer | Hard (fan-out exchanges, etc.) | Easy (each at own offset) |
| "Process exactly once and forget" | Native | Application-side dedup needed |
| Operational complexity | Lower | Higher (especially Kafka) |
| Best fit | Transient task processing | Event sourcing, streams, audit |
| Worst fit | Audit trail (no history) | Simple "do this work" tasks (overkill) |

The choice between queue-shaped and log-shaped messaging is one of the larger architectural decisions in a microservice system. Reach for a log when history matters or when multiple downstream views of the same event stream are needed; reach for a queue when the work is transient and the broker as a system of record adds no value.

### Dead letter queue

Messages that fail repeatedly get routed to a parking queue for inspection. Standard reliability pattern.

### Delayed / scheduled delivery

A message is published with a "don't deliver until time T" instruction. Used for scheduled retries, delayed-effect workflows.

### Persistent vs ephemeral

A message either survives a broker restart (persistent) or doesn't (ephemeral). The choice is per-topic, sometimes per-message; brokers usually support both modes.

**Ephemeral.** Messages live in broker memory. Cheapest to send, lowest latency, no disk I/O. If the broker restarts or a subscriber is offline, messages in flight are lost. Right choice when:

- The data is a continuously-refreshed signal where stale information is useless (live sensor readings, market prices, presence indicators).
- The cost of losing a message is lower than the cost of keeping it.
- Throughput matters more than durability.

**Persistent.** Messages are written to disk before the broker **acknowledges** the producer — sends back a small confirmation message (an "ack," in shorthand) saying "I received it and stored it durably." Until the producer has this ack, it doesn't know whether the message landed. Persistence costs throughput (disk I/O is slower than memory), disk space (retention has to be managed), and added complexity in the broker's storage layer. Survives broker restart; can be re-delivered to consumers that were offline. Right choice when:

- The data can't be reconstructed if lost (orders, payments, user actions, anything that the system is the record-of-truth for).
- Compliance or audit requirements forbid loss.
- The broker is acting as a system of record, not just a transport.

**Acknowledgment timing within persistence.** Even within "persistent," there's a spectrum of how durable an ack actually is:

- **Synchronous fsync before ack** — broker writes to disk, calls `fsync`, acks the producer only after the OS confirms the write hit the device. Safest; slowest. Survives both broker crash and OS crash.
- **Asynchronous fsync** — broker acks after the write hits OS buffer cache; flush to disk happens lazily. Faster; can lose recent messages on hard crash (process kill, kernel panic, power loss) even though broker restart-with-clean-shutdown is safe.
- **Replication before ack** — broker writes locally then waits for N replica brokers to also write before acking. Most durable; pays both disk I/O and network round-trip cost. Kafka's `acks=all` setting is the canonical example.

Persistent doesn't mean "saved forever" — it means "survives the broker restart." Messages still age out per retention policy.

<a id="handling-client-crashes"></a>
#### Handling client crashes

A persistent broker can survive its own restart, but most production failures are actually client failures: a producer dies mid-publish, a consumer dies mid-processing. Persistence is most of the answer, but the rest depends on protocol semantics.

**Producer crashes between sending the message and receiving the ack.** The producer doesn't know whether the message landed. Two strategies:

- **At-most-once.** Producer doesn't retry. Some messages may be silently lost. Acceptable for fire-and-forget metrics, telemetry, ephemeral signals.
- **At-least-once with idempotent producer.** Producer retries on uncertainty. The broker dedups based on a producer-supplied unique ID (Kafka's `enable.idempotence=true`, AMQP publish-confirms with deduplication, etc.). Without the dedup, retry would mean duplicates land; with it, a retry of a successfully-delivered message is a no-op on the broker side.

**Consumer crashes after receiving a message but before processing it.** This is the common case and is handled by **explicit acknowledgment**:

- Consumer fetches a message; the broker marks it "in-flight" (assigned to this consumer, not deliverable to others).
- Consumer processes, then sends an ack.
- If the consumer crashes before acking — the broker times out the in-flight reservation (the **visibility timeout** / message lease) and re-delivers the message, either to the same consumer when it restarts or to a different consumer in the group.

This guarantees **at-least-once delivery** to the consumer. The consumer is responsible for either being idempotent (processing the same message twice yields the same result) or for using transactional semantics that tie the side-effect to the ack (process-and-ack as one atomic operation).

**Consumer crashes after processing but before acking.** Indistinguishable from "crashed mid-processing" from the broker's perspective. Message gets re-delivered. Consumer processes again. Same answer: idempotency or transactional process-and-ack.

**Visibility timeout.** A reservation that bounds "how long can this consumer hold a message before I assume it's dead?" Too short and a slow consumer gets duplicate deliveries; too long and a crashed consumer's messages take forever to retry. Tunable; some brokers let the consumer extend the lease while it's still working.

**Dead letter queues.** When a message has been re-delivered N times and still keeps failing, the broker stops retrying and forwards the message to a parking queue for human inspection. Prevents infinite retry loops on permanently-bad messages.

**Persistent subscriptions for absent clients.** For pub/sub (broadcast) shapes, a "durable subscription" means: while a subscriber is disconnected, the broker buffers messages addressed to it; when the subscriber reconnects, the queued messages are delivered. Requires a stable client identity (MQTT's Client ID, AMQP's persistent queue name, Kafka's consumer group + member ID) so the broker knows which subscription belongs to a reconnecting client.

**Stream / log consumers handle crashes differently.** Log-based brokers (Kafka, NATS JetStream, Redis Streams) don't track in-flight state per consumer; they track **committed offsets**. When a consumer crashes, it resumes from its last committed offset on restart and re-reads any messages that were processed but not yet committed. Re-processing is still possible, so idempotency still matters — but there's no broker-side "re-delivery" mechanism, just consumer-side re-reading.

**Producer-side message ordering across crashes.** If a producer crashes and restarts, in-flight messages it had sent before the crash might land out of order relative to new messages it sends after restart. Brokers that care about producer-side ordering (Kafka with `max.in.flight.requests.per.connection=1` plus idempotent producer, for example) require additional configuration to preserve order across producer restarts.

The summary: persistence on the broker side is necessary but not sufficient. The full crash-handling story requires coordinated discipline across both ends — durable storage, ack protocols, retry semantics, dedup or idempotency, dead-letter handling, stable client identity. Each broker offers a set of knobs; the right combination depends on what failure modes the application tolerates.

### Delivery guarantees

Three levels, with sharply different cost. The choice between them is fundamentally about **acknowledgments** — the short confirmation messages introduced in [Persistent vs ephemeral](#persistent-vs-ephemeral). Two kinds of acks matter in a broker workflow, on either end of the broker:

- **Producer-to-broker ack.** The broker tells the producer "I got your message" — usually after writing it to disk (for persistent topics) or to memory (for ephemeral). Until the producer has this ack, it doesn't know whether the message landed; if its connection drops mid-send, it has to decide whether to retry. Producer acks can be turned off entirely (fire-and-forget — fastest, least safe) or strengthened to wait for replication across multiple brokers (slowest, most durable).
- **Consumer-to-broker ack.** The consumer tells the broker "I have this message handled; you don't need to remember it for me anymore." Until the broker has this ack, the message is "in-flight" — assigned to that consumer but not yet considered done. If the consumer crashes without acking (the broker times out the assignment), the broker can re-deliver the message to a different consumer. See [Handling client crashes](#handling-client-crashes) for the full retry / lease story. Consumer acks are sometimes implicit (broker auto-acks on delivery — fast, but messages can be lost if the consumer crashes mid-processing) or explicit (consumer must call an `.ack()` method to confirm — safer, but the consumer has to remember to do it).

With those defined, the three delivery guarantees are about **which acks are required and how the system recovers when they fail to arrive:**

- **At-most-once** — no acks required at either end. Producer fires and forgets; broker delivers and forgets; consumer processes whatever it gets. Fastest. Messages can be lost on a broker crash, a network drop, or a consumer crash. Right for telemetry, transient signals, anything where missing one message in a stream is fine.
- **At-least-once** — producer acks required (so producer can retry if no ack arrives), consumer acks required (so broker can re-deliver if the consumer crashes mid-processing). Result: no messages are lost, but some messages may be delivered more than once. **The consumer is responsible for being idempotent** — processing the same message twice must yield the same result as processing it once, or the system has to detect and discard the duplicate. The default mode for most brokers.
- **Exactly-once** — at-least-once delivery plus **broker-side deduplication of producer retries** plus **transactional process-and-commit on the consumer side**, so a message that gets re-delivered after a partial processing failure either fully replaces the prior attempt or is rejected as a duplicate. Expensive (extra coordination, durable dedup state, transactional commits). Kafka offers it through its transactions API; Pulsar has it natively; others approximate it through application-layer idempotency. Often the "right" answer is at-least-once + application idempotency, which is cheaper and clearer than chasing true exactly-once.

### Backpressure / flow control

What happens when a publisher is faster than its consumers? Drop messages? Block the publisher? Buffer to disk? Each broker chooses a default and offers knobs.

---

## Part 3: typical microservice use cases

The places message brokers actually earn their keep in microservice systems:

- **Decoupling services.** Service A publishes "order_created"; services B, C, D each react independently. None of them needs to know the others exist. A can be deployed, redeployed, scaled, replaced without changing its consumers.
- **Async task processing.** Web request submits a job; a worker pool picks it up later. The request returns immediately.
- **Event sourcing.** Persist every state-change as an event; replay events to rebuild state. The broker IS the database (Kafka explicitly markets itself this way).
- **Cross-region replication.** A broker can stream events between data centers as the canonical replication mechanism.
- **IoT telemetry.** Many small devices publish telemetry; a small set of consumers aggregate. MQTT was designed for this.
- **Audit trail.** Every state change goes through a broker, providing a forensic record.
- **Rate-limited downstream calls.** Producer dumps work into a queue; consumer drains at a controlled rate, smoothing spikes that downstream services can't handle.

---

## Part 4: where Caspian could fit

Several distinct angles, in roughly increasing scope of commitment.

### Angle A: Caspian as a client of existing brokers

The most realistic V1.x move. Caspian programs participate in larger messaging systems by speaking the wire protocols of existing brokers. Each broker gets a Caspian package:

- `puck.uno/broker/rabbitmq` — AMQP client
- `puck.uno/broker/kafka` — Kafka protocol client
- `puck.uno/broker/nats` — NATS protocol client
- `puck.uno/broker/mqtt` — MQTT client
- `puck.uno/broker/redis` — Redis pub/sub + streams (likely under `puck.uno/redis/client` with messaging surfaces alongside KV)

A higher-level abstraction could provide a uniform interface where the underlying broker is configurable:

~~~caspian
$client = %puck['https://puck.uno/broker/client'].new(
    backend: 'rabbitmq',
    host:    'localhost'
)

$client.subscribe('orders.*') do($msg)
    %stdout.puts 'received: ' + $msg.body
end

$client.publish('orders.created', {order_id: 42})
~~~

**Strengths.** Realistic. Useful immediately. Doesn't require Caspian to invent anything new — just protocol implementations. Lets Caspian programs participate in established microservice meshes.

**Costs.** Each protocol is a real implementation lift (AMQP especially is complex). The "uniform abstraction" tax is real — each broker has subtly different semantics that don't fit a one-size interface.

### Angle B: an embeddable Caspian-native broker

Build a small, in-process or sidecar broker for Caspian programs that don't want the operational weight of Kafka/RabbitMQ/NATS.

The model would parallel SQLite: small, embeddable, no separate service required, fine for many use cases that don't need cluster-scale infrastructure. Examples of fit:

- A multi-process Caspian application on one host where forks need to coordinate.
- A development environment that wants real messaging without running an external broker.
- IoT-edge devices that need local pub/sub but can't ship a full broker.
- Small projects that would benefit from messaging patterns but won't grow into Kafka territory.

The implementation could lean on existing Caspian pieces: TCP/UDS for transport, Mikobase for persistence, the role system for tenant separation, the existing event-system primitives for in-process delivery.

**Strengths.** A real gap in the ecosystem. The choice between "deploy a broker (operational weight)" and "do everything synchronously (no flexibility)" leaves room for an embedded option. Aligns with Caspian's design philosophy (small, self-contained, embeddable).

**Costs.** "Build a broker" is a substantial project. The persistence story is hard (Mikobase isn't optimized for append-only-log throughput). Cluster modes, replication, HA are not free.

### Angle C: extending the in-process event system across processes

Caspian already has [an event system](https://puck.uno/documentation/requirements/caspian/events/) — `%self.object.broadcast`, `listen_to`, `on_broadcast`. Currently it's strictly in-process. **The same API could be extended to cross process and host boundaries.**

Specifically: a Caspian object's broadcasts could be made reachable to subscribers in other processes (other Caspian instances, maybe even other languages via a Puck-protocol surface). Local subscribers continue to work as today; remote subscribers participate through some transport (probably the broker from Angle B, or via existing brokers from Angle A).

~~~caspian
# Local subscription — unchanged
$logger.object.listen_to $server, 'request_received', 'log'

# Remote subscription — same API, the other side just happens to be in another process
$remote_server = %puck['https://orders.example.com/']
$logger.object.listen_to $remote_server, 'request_received', 'log'
~~~

This is the most Caspian-native of the options. The developer-facing API doesn't change; the engine handles whether the subscription is local, cross-process on the same host, or cross-network.

**Strengths.** Maximum integration. The event system is already there; making it network-reachable just expands its territory. Developers learn one set of primitives.

**Costs.** Big design questions. How does cross-host broadcast handle ordering, delivery guarantees, authentication, failures? How does discovery work — how does `$logger` find `$remote_server` to register on? Some of these are answered by Puck (which is itself a remote-object protocol), but the synthesis isn't trivial.

### Angle D: Mikobase-backed message store

Mikobase records are JSON objects with structured queries. Messages are JSON objects with structured filters. The fit is natural: a Mikobase database can serve as a message store, with queries replacing consumer subscriptions.

This wouldn't be a separate broker so much as a recognized pattern — "use Mikobase as your event log." Records have timestamps; queries can be temporal (WHERE created_at > $cursor). Consumer groups become "remember the cursor where you left off."

**Strengths.** Reuses Mikobase without adding new infrastructure. Persistence is automatic. Replay is just "query from earlier cursor."

**Costs.** Mikobase isn't optimized for append-only-log throughput; a high-volume messaging workload would stress patterns Mikobase wasn't designed for. Better suited for low-to-medium volume event sourcing than high-throughput streaming.

### Angle E: Puck protocol as a messaging primitive

[Puck](https://puck.uno/documentation/requirements/puck/) is a remote-object protocol — instantiate a remote class, call methods on it. With explicit support for event-style payloads, it could approximate a messaging system without being one:

- Server object exposes `subscribe(topic)` returning a stream of events.
- Client uses Puck to call `server.subscribe('orders.*')` and iterates the result.
- Server-side `publish(topic, data)` calls fan out to subscribers via Puck's remote-object mechanism.

This is "build a broker on top of Puck" rather than "Caspian has a broker." Light architectural commitment; lets Puck be the foundation for application-level messaging when the developer wants it.

**Strengths.** Doesn't add new protocols. Stays in the Puck design space. Lets applications choose how much messaging structure they want.

**Costs.** Puts the persistence and reliability story on the application, not the platform. Doesn't replace a real broker for serious workloads.

---

## Recommendations / open questions

If Caspian pursues messaging, the realistic path is probably:

1. **Angle A first** — protocol clients for the dominant brokers (NATS and Redis are probably the cheapest first wins; Kafka next for the throughput-streaming case; RabbitMQ for enterprise reach; MQTT for IoT). This makes Caspian a useful participant in existing infrastructure without committing to building a broker.
2. **Angle C as a longer-term ambition** — extending the in-process event system across processes feels like the most-Caspian answer. It's also the riskiest to design well. Worth specifying carefully before implementing.
3. **Angle B (embedded broker) is a possible adjunct** — if the cross-process event-system work needs a default transport that doesn't require deploying RabbitMQ or NATS, an embedded broker could fill that gap. But it's hard to motivate Angle B on its own — it's an answer to a problem that mostly exists if Angle C exists.
4. **Angles D and E are reuse patterns, not platform commitments** — worth documenting as ways to use Mikobase or Puck for messaging-shaped problems, but they don't justify a dedicated messaging-system project.

Open questions for Stuart:

- **Which microservices are we worried about?** Caspian-Caspian (where Angle C makes most sense) or Caspian talking to non-Caspian services (where Angle A is the only realistic answer)?
- **What's the scale?** Single-host coordination, multi-host cluster, or cross-data-center?
- **Durability needs?** Pub/sub fire-and-forget, at-least-once with replay, or full event-sourcing event-log semantics?
- **Existing infrastructure commitments?** A team that's already running Kafka has very different needs than one starting from scratch.

The answers shape which angles are worth pursuing first. The framing of "Caspian should implement message brokers" is broad enough to mean anywhere from "add a NATS client library" to "build a distributed Kafka alternative" — narrowing that down is the first design conversation.
