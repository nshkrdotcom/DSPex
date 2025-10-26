# Why "SnakeBridge" (Not "PyBridge")

**Decision Date**: 2025-10-25
**Status**: ✅ Approved and Implemented

---

## The Decision

The library will be called **SnakeBridge** (not PyBridge).

## Rationale

### 1. **Brand Cohesion**

SnakeBridge creates a **unified ecosystem** with Snakepit:

```
┌──────────────────────────────────────────────────────┐
│           The Snakepit Ecosystem                     │
│                                                      │
│  ┌─────────────┐              ┌─────────────────┐  │
│  │  Snakepit   │──────────────│  SnakeBridge    │  │
│  │  (Runtime)  │    powers    │  (Integration)  │  │
│  └─────────────┘              └─────────────────┘  │
│       │                               │             │
│       │                               │             │
│   Python Workers            Elixir Developers       │
│   (The "Pit")              (The "Bridge")           │
└──────────────────────────────────────────────────────┘
```

**Metaphor**:
- **Snakepit** = The foundation where Python processes live (the "pit")
- **SnakeBridge** = The bridge FROM Elixir TO the snakepit

### 2. **Memorable and Unique**

- ✅ **Distinctive**: No other library uses "SnakeBridge"
- ✅ **Searchable**: Google-friendly, unique brand
- ✅ **Playful**: The "snake" theme is fun and approachable
- ❌ **PyBridge**: Generic—dozens of "PyX" bridges exist

### 3. **Clear Relationship**

**SnakeBridge** immediately communicates:
- "This is part of the Snakepit ecosystem"
- "This bridges Elixir to Python via Snakepit"
- "Depends on Snakepit as substrate"

**PyBridge** is ambiguous:
- Just another Python bridge?
- Independent tool?
- Related to Snakepit?

### 4. **Marketing Story**

**SnakeBridge narrative**:
> "Snakepit orchestrates Python workers in isolated processes—the 'pit' where your snakes live. SnakeBridge is how you safely cross from Elixir into that pit, calling Python code as if it were native."

**PyBridge narrative**:
> "It's a Python bridge for Elixir... like the other ones... but better?"

### 5. **Hex Package Clarity**

```elixir
# Clear dependency relationship
def deps do
  [
    {:snakepit, "~> 0.6"},      # The substrate
    {:snakebridge, "~> 0.1"}    # The integration framework
  ]
end
```

Users immediately understand the relationship.

### 6. **Future Extensibility**

The "bridge" metaphor still works if we expand beyond Python:

```elixir
# Future: Other language bridges?
{:snakebridge, "~> 0.1"}           # Python integration
{:nodebridge, "~> 0.1"}            # Node.js integration
{:rubybridge, "~> 0.1"}            # Ruby integration

# OR they all live under SnakeBridge as backends:
SnakeBridge.Python
SnakeBridge.NodeJS
SnakeBridge.Ruby
```

The "Bridge" concept is language-agnostic.

---

## Comparison

| Aspect | PyBridge | SnakeBridge | Winner |
|--------|----------|-------------|--------|
| **Brand cohesion** | ❌ Disconnected | ✅ Unified ecosystem | SnakeBridge |
| **Memorability** | ⚠️ Generic | ✅ Unique | SnakeBridge |
| **Searchability** | ❌ Many results | ✅ Unique | SnakeBridge |
| **Relationship clarity** | ⚠️ Ambiguous | ✅ Obvious | SnakeBridge |
| **Marketing** | ⚠️ Bland | ✅ Story-driven | SnakeBridge |
| **Ecosystem vision** | ⚠️ Siloed | ✅ Cohesive | SnakeBridge |

**Result**: SnakeBridge wins on every dimension.

---

## Implementation

### Package Name
- **Hex**: `snakebridge`
- **Module**: `SnakeBridge`

### Documentation
- **Display name**: SnakeBridge
- **Tagline**: "Bridge Elixir to the Python ecosystem via Snakepit"

### File Structure
```
snakebridge/
├── mix.exs                     # defproject :snakebridge
├── lib/
│   ├── snakebridge.ex          # Main module
│   └── snakebridge/
│       ├── config.ex           # SnakeBridge.Config
│       ├── generator.ex        # SnakeBridge.Generator
│       ├── runtime.ex          # SnakeBridge.Runtime
│       └── discovery.ex        # SnakeBridge.Discovery
└── README.md                   # SnakeBridge: Python Integration Framework
```

### Usage Examples

```elixir
# Configuration
use SnakeBridge.Integration,
  integration_id: :dspy,
  config: DSPyConfig

# Mix tasks
mix snakebridge.discover dspy
mix snakebridge.validate
mix snakebridge.diff dspy

# IEx helpers
import SnakeBridge.IEx
snakebridge_info(:dspy)
```

---

## Community Messaging

### Announcement

> **Introducing SnakeBridge** 🐍🌉
>
> The next evolution in the Snakepit ecosystem: configuration-driven Python integration for Elixir.
>
> With SnakeBridge, integrating any Python library takes minutes, not days. Write a config, generate type-safe Elixir modules, and bridge to the Python ecosystem—all with zero manual wrapper code.
>
> Built on Snakepit. Powered by metaprogramming. Designed for developers.

### Social Media

- "SnakeBridge: Your fast track to the Python ML ecosystem from Elixir 🐍🌉"
- "Snakepit orchestrates. SnakeBridge integrates. Together, they unlock Python for Elixir."
- "Configuration > Code. That's the SnakeBridge way."

---

## FAQ

### Q: Why not just call it "Snakepit.Bridge"?

**A**: We want SnakeBridge to be a **standalone library** with independent releases. Making it a sub-namespace of Snakepit would imply it's part of core, which conflicts with our architectural decision to keep them separate.

### Q: What if we expand to other languages?

**A**: The "Bridge" concept works for any runtime:
- SnakeBridge (Python)
- NodeBridge (Node.js)
- RubyBridge (Ruby)

OR, SnakeBridge becomes the umbrella with backends:
- `SnakeBridge.Python`
- `SnakeBridge.NodeJS`
- `SnakeBridge.Ruby`

Either way, the name scales.

### Q: Does "SnakeBridge" sound too playful for enterprise?

**A**: No. Companies like:
- MongoDB (database)
- RabbitMQ (message queue)
- Elasticsearch (search engine)

All use friendly names. "SnakeBridge" is memorable without being unprofessional.

---

## Conclusion

**SnakeBridge** is the right name because it:

1. ✅ Creates a cohesive ecosystem with Snakepit
2. ✅ Is unique and memorable
3. ✅ Clearly communicates the relationship
4. ✅ Tells a better marketing story
5. ✅ Scales to future expansion

**Decision**: All documentation uses "SnakeBridge" (not "PyBridge").

---

**Approved By**: Architecture team
**Implemented**: 2025-10-25
**Status**: ✅ Complete
