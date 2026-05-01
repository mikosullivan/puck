# KScript + Ruby Integration Summary

## Overview

This document summarizes the design discussion for embedding **KScript (Lua-based)** into a **Ruby host environment**, focusing on:

- Bootstrapping the runtime
- Execution model
- Capability-based security
- Data passing
- Timeout handling
- Jail (filesystem sandbox) design

---

## 1. Architecture

```
Ruby (host / policy layer)
    ↓
Lua C library (embedded VM)
    ↓
KScript runtime (written in Lua)
```

- Ruby owns the process and enforces policy
- Lua executes the KScript engine
- KScript runs untrusted code

---

## 2. Engine API Design (Ruby)

### Desired Usage

```ruby
engine = KScript::Runtime.new
engine.stdout = :capture
engine.stderr = :capture
engine.timeout_seconds = 5

result = engine.run_string("puts 'hello'")
puts result
```

### Key Concepts

- `engine` = configured runtime
- `run_*` = execution entrypoint
- configuration is done before execution
- execution returns a structured result

---

## 3. Execution Model

### Request Shape (Conceptual)

```json
{
  "source": "...",
  "args": {},
  "capabilities": {},
  "limits": {
    "timeout_seconds": 5
  }
}
```

### Response Shape

```json
{
  "success": true,
  "value": null,
  "stdout": "...",
  "stderr": "",
  "elapsed_seconds": 0
}
```

---

## 4. Data vs Capabilities

Core rule:

```
Data is passed by value.
Authority is passed by capability.
Context is passed by chain.
```

### Data (safe)

```ruby
args: { "name" => "Riker" }
```

### Capabilities (controlled)

```ruby
engine.capability("clock") { Time.now }
```

---

## 5. Timeout Model

### Syntax (KScript)

```kscript
%timeout(5) do
    &spooky
end
```

### Rules

- Timeouts are **lexical and inherited**
- Nested timeouts cannot extend parent budget
- Untrusted calls get implicit default timeout

```
effective_timeout = min(requested, remaining_parent_time)
```

---

## 6. %chain (Scoped Context)

### Behavior

- Acts like a scoped hash
- Values flow **downward only**
- Modifications do not persist upward

```kscript
%chain["zap"] = "a"

function foo()
    %chain["zap"] = "b"
end

foo()

%chain["zap"]  # still "a"
```

### Security Rule

```
%chain is cleared when entering untrusted execution
```

---

## 7. Closures and Security

Functions capture values lexically:

```
function = code + captured capabilities
```

Example:

```kscript
function &riker()
    &hello "Riker"
end
```

Internally:

```
captures: { hello }
```

This avoids global access while preserving convenience.

---

## 8. Jail (Filesystem Sandbox)

### Ruby API

```ruby
engine["foo"] = KScript::Jail.new("/var/lib/myapp/foo", read: true)
engine["bar"] = KScript::Jail.new("/var/lib/myapp/bar", read: true, write: true)
```

### Ruby Class

```ruby
module KScript
  class Jail
    attr_reader :path, :read, :write

    def initialize(path, read: false, write: false)
      @path = path
      @read = read
      @write = write
    end
  end
end
```

### KScript Usage

```kscript
%foo.path("docs/readme.txt").read()
%bar.path("out/result.json").write($data)
```

### Key Security Rule

```
KScript sees virtual paths only.
Real filesystem paths are never exposed.
```

---

## 9. Capability Model Summary

- No global variables
- No ambient authority
- Everything is injected explicitly

```
engine["name"] = resource
```

becomes:

```
%name in KScript
```

---

## 10. Design Principles

- Explicit capability injection
- No hidden globals
- Untrusted code runs with minimal context
- Context (%chain) is controlled and scoped
- Timeouts are enforced by the runtime
- Filesystem access is sandboxed via jails

---

## Conclusion

The system forms a clean, composable model:

- Ruby = host and policy layer
- Lua = execution engine
- KScript = sandboxed language

Security is maintained through:
- capability isolation
- scoped context
- strict execution boundaries

This approach avoids traditional pitfalls of globals and implicit authority while still giving developers ergonomic tools.
