# Packaged Mikobases: Portable Object Worlds in the Ecoverse

## Overview

A **packaged mikobase** is a small, self-contained mikobase that can be exported, transported, imported, and executed anywhere within the ecoverse.

Packaged mikobases are more than data exports. They are **complete object environments**, containing structure, behavior, and state.

> A packaged mikobase is a reusable mini-world.

---

## Core Concept

Traditional systems separate:
- Code
- Data
- APIs
- Runtime

Packaged mikobases unify these into a single portable unit:

```
classes
methods
queries
indexes
hooks
permissions
seed objects
external connectors
scheduled jobs
```

This means a packaged mikobase is not just a dataset—it is a **functioning system**.

---

## Packaged Mikobases vs Traditional Concepts

| Concept              | Description |
|----------------------|-------------|
| Library              | Reusable code |
| API                  | Interface to a system |
| Database dump        | Static data snapshot |
| Container            | Runtime environment |
| **Packaged mikobase** | **Reusable object world (code + data + behavior)** |

A library says:
> "Here are functions you can call."

A packaged mikobase says:
> "Here is a functioning object ecosystem you can import."

---

## Example: Stock Tracker Mikobase

A developer could publish:

```
stock-tracker.mikobase
```

When imported, it installs:

### Classes
```
Stock
Ticker
Exchange
PricePoint
Portfolio
Watchlist
```

### Methods
```
Ticker.fetch_latest()
Portfolio.value()
Watchlist.refresh()
```

### Behavior

If the mikobase has access to a stock API, it can begin populating itself automatically.

---

## Execution Model

Packaged mikobases can be:

- Imported into a local mikobase
- Sent over the network
- Executed remotely via Kiera
- Used as test fixtures or reproducible environments

Example:

```
send packaged mikobase → remote system → execute logic → return result
```

This enables:
- portable computation
- reproducible bugs
- isolated execution environments

---

## Scaling Model

Mikobases scale seamlessly:

| Scale | Backend |
|------|--------|
| Tiny | In-memory SQLite |
| Medium | PostgreSQL |
| Large | Distributed storage (S3, etc.) |

Same abstraction, different storage engines.

---

## Capabilities and Permissions

Packaged mikobases should declare required capabilities:

```
requires:
  network:
    - api.example.com
  schedule:
    - every 5 minutes
  storage:
    - create objects: PricePoint
```

Installation becomes explicit:

> "This mikobase wants to fetch stock prices and write price history. Allow?"

This ensures:
- security
- transparency
- portability

---

## Use Cases

Packaged mikobases enable:

- Open-source object systems
- Installable data models with behavior
- Portable test environments
- Distributed computation units
- Offline/online sync mechanisms
- Reproducible bug reports

Examples:

```
stock tracker
recipe manager
home inventory
weather archive
blog engine
CRM
game state model
IoT sensor logger
research notebook
```

---

## Key Insight

> A packaged mikobase is not just data. It is a **living, portable system**.

Packaged mikobases turn Mikobase from a storage layer into a platform for:

- sharing systems
- composing object worlds
- executing behavior anywhere

---

## Conclusion

Packaged mikobases are the natural evolution of Mikobase and Kiera:

- Mikobase provides the world
- Kiera provides communication
- KScript provides execution

Packaged mikobases make these composable.

> Instead of sharing code, we share worlds.
