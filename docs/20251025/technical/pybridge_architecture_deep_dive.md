# PyBridge Architecture Deep Dive & Packaging Strategy

**Date**: 2025-10-25  
**Audience**: Snakepit & DSPex maintainers, prospective PyBridge contributors  
**Related Docs**:  
- `docs/20251025/PYBRIDGE_INNOVATION.md` (innovation blueprint)  
- `docs/20251025/DSPY_PYBRIDGE_CONFIG_EXAMPLE.exs` (comprehensive DSPy config)  
- `docs/20251025/README.md` (executive overview)

---

## 1. Purpose

This document extends the PyBridge innovation proposal with implementation-grade details. It covers:

1. Runtime and compile-time module layout
2. gRPC protocol extensions, serialization layers, and caching strategy
3. Concurrency and lifecycle concerns when multiple integrations coexist
4. Packaging trade-offs (standalone library vs. Snakepit core)
5. Recommended plan for aligning Snakepit and DSPex around the new abstraction

---

## 2. High-Level Responsibilities

| Layer | Responsibility | Delivered By |
|-------|----------------|--------------|
| Configuration | Declarative API description, overrides | `PyBridge.Config` schema (Elixir) |
| Introspection | Python schema discovery, doc capture | `PyBridge.Agent` (Python) |
| Code Generation | Compile-time module emission | `PyBridge.Generator` (Elixir macro) |
| Runtime Execution | Session management, telemetry, retries | `PyBridge.Runtime` (Elixir) + Snakepit |
| Transport | gRPC bridge, streaming, tool registry | Snakepit 0.6.x (with extensions) |

PyBridge sits above Snakepit: it does not replace pool management, but supplies the missing “describe → generate → execute” loop.

---

## 3. Module Layout

```text
pybridge/
 ├── lib/
 │   ├── pybridge/application.ex          # boots caches, ensures Snakepit presence
 │   ├── pybridge/config.ex               # Ecto schema & validator
 │   ├── pybridge/config/loader.ex        # Reads manifests (<%= %> supported)
 │   ├── pybridge/config/formatter.ex     # Generates .exs configs from introspection
 │   ├── pybridge/generator.ex            # __using__/__before_compile__ macros
 │   ├── pybridge/runtime.ex              # create_instance/4, call_method/4, streaming
 │   ├── pybridge/runtime/telemetry.ex    # instrumentation emitters
 │   ├── pybridge/runtime/cache.ex        # ETS/DETS descriptor cache
 │   ├── pybridge/session.ex              # session checkout/release, pooling hints
 │   ├── pybridge/introspection.ex        # Elixir side RPC client
 │   ├── pybridge/introspection/parser.ex # Turns Python metadata into config structs
 │   └── pybridge/type_converter.ex       # JSON/msgpack/Nx tensor adapters
 └── priv/python/pybridge_agent.py        # Worker-side introspection & exec helpers
```

Generated modules (`MyApp.SomeModule`) live alongside application code, either compiled in during `mix compile` or dynamically emitted in dev/test via `PyBridge.Generator.generate_and_load/2`.

---

## 4. gRPC Protocol Extensions

Snakepit 0.6.3 already exposes `ExecuteTool` and related RPCs. PyBridge requires two additions:

1. **DescribeLibrary RPC**
   ```proto
   message DescribeLibraryRequest {
     string library_id = 1;
     string module_path = 2;
     repeated string submodules = 3;
     uint32 depth = 4;
     bytes config_hash = 5;    // to reuse cached descriptors
   }

   message DescribeLibraryResponse {
     string version = 1;
     map<string, ClassDescriptor> classes = 2;
     map<string, FunctionDescriptor> functions = 3;
     bytes descriptor_hash = 4;
     repeated string warnings = 5;
   }
   ```
   This call is executed once per manifest load (with cache fallback).

2. **ExecuteToolStreaming** (currently unimplemented; needed for `streaming: true`)
   - Implement server-side stream that forwards worker responses chunk-by-chunk.
   - Reuse `ExecuteToolRequest` with `stream = true`.
   - Require worker adapters to yield `yield`ed messages with `chunk_id`, `payload`, `is_final`.

Snakepit changes:
* `Snakepit.GRPC.BridgeServer` implements `describe_library` and `execute_streaming_tool`.
* Worker adapter (`dspex_adapters.dspy_grpc`) dispatches to `pybridge_agent.describe_library`.
* `Snakepit.GRPC.ClientImpl` adds `describe_library/3` and extends streaming support.

---

## 5. Serialization & Type Conversion

PyBridge supports pluggable encodings per integration:

| Encoder | Use Case | Notes |
|---------|----------|-------|
| JSON (default) | Structured data, maps/lists | Works with today’s Snakepit Any wrapper |
| Msgpack | Large payloads, numeric heavy data | Requires new optional dependency |
| Nx tensor | Direct BEAM tensor transport | Wrap Nx binary terms, bypass JSON |

Configuration snippet:
```elixir
serialization: %{
  args: :json,
  result: :json,
  tensor_passthrough: true
}
```

Runtime flow:
1. `PyBridge.Runtime.call_method/4` fetches encoder module from config.
2. Arguments -> `PyBridge.TypeConverter.to_python/2`
3. Response -> decode, optional Nx shape inference
4. Dialyzer specs generated based on converter metadata

---

## 6. Caching Strategy

### Descriptor Cache

* **Hot cache**: ETS table keyed by `{integration_id, descriptor_hash}`
* **Persistent cache**: DETS or JSON file for warm boots (`priv/pybridge/schemas/*.json`)
* `config_hash` in `DescribeLibraryRequest` allows Python agent to short-circuit if config matches disk cache

### Execution Cache

* Optional per-method caching (`cacheable: true`)
* Implemented via `:ets.update_counter` with TTL, keyed by `(integration, method, args_hash)`
* Useful for pure functions like `Signature.parse`

### Invalidations

* Config change -> compile-time invalidation (mix recompiles)
* Python version change -> introspection hash mismatch -> re-fetch descriptors
* Manual invalidation API: `PyBridge.Cache.invalidate!(:dspy)`

---

## 7. Concurrency & Lifecycle

* Each generated module delegates session management to `PyBridge.Session`: supports pools, per-call ephemeral sessions, and explicit reuse.
* `PyBridge.Session.Manager` tracks session reference counts to release when unused.
* Telemetry events for `checkout`, `return`, `timeout`.

**Bulk Introspection**: performed sequentially during app boot to avoid stampede. Mix task parallelizes by module, but runtime load should be single-threaded to minimize Python worker churn.

**Hot Reload (dev mode)**:
1. File watcher detects updates under `config/pybridge/*.exs`.
2. Loader re-validates config, flushes generated module(s) via `:code.purge` + `Code.compile_quoted`.
3. Session cache optionally reset when classes change constructor signatures.

---

## 8. Packaging Options

### Option A — Embed in Snakepit Core

**Pros**
* Single dependency for users
* Tight coupling to gRPC bridge (less coordination)
* Officially part of Snakepit “story”

**Cons**
* Snakepit becomes heavy-weight (requires Ecto, macros, config tooling)
* Slows down core releases (PyBridge iterations gated on Snakepit version)
* Harder for non-Python integrations to avoid unused code

### Option B — Standalone `:pybridge` Hex Package (Preferred)

**Pros**
* Independent release cadence, semantic versioning
* Optional dependency on Snakepit (`{:snakepit, ">= 0.6.3"}`) keeps PyBridge focused
* Clear layering: Snakepit = runtime substrate, PyBridge = integration facade
* Facilitates community contributions without touching Snakepit internals

**Cons**
* Requires coordination on protocol changes (gRPC extensions)
* Users must add two deps (PyBridge + Snakepit)

### Option C — Hybrid (`snakepit_pybridge` umbrella app)

**Pros**
* Keeps PyBridge close to Snakepit repo while isolating dependencies
* Shared CI pipeline

**Cons**
* Still couples release schedules
* Adds repository complexity

**Recommendation**: Pursue **Option B**. Publish `pybridge` as a dedicated Hex package, depending on Snakepit for runtime orchestration. Snakepit should expose a stable extension surface: the new gRPC RPCs, introspection hook registration, and optional helpers in `Snakepit.Integration`. DSPex (and other consumers) depend on PyBridge; Snakepit remains lean.

---

## 9. Integration Plan (Technical)

1. **Snakepit Enhancements**
   - Implement `describe_library` RPC server/client support.
   - Finish `execute_streaming_tool/2`.
   - Provide `Snakepit.Integration` behaviour with callbacks for tool registration and introspection.

2. **Python Worker Agent**
   - Ship `pybridge_agent.py` alongside existing adapters.
   - Expose `describe_library` using `inspect` + `typing`.
   - Provide caching (`.pybridge_cache/<module>.json`) to avoid recomputation.

3. **PyBridge Library (New Project)**
   - Scaffold mix project with modules described in §3.
   - Implement config schema + validator (Ecto).
   - Add generator macro that emits modules during compile.
   - Build runtime executor bridging to Snakepit.
   - Include telemetry instrumentation (duration, success, payload size).

4. **DSPex Migration**
   - Replace manual modules with `use PyBridge.Generator, config: DSPyConfig`.
   - Migrate tests to run against generated SDK.
   - Validate streaming behaviours for Chain of Thought, ReAct, etc.

5. **Tooling**
   - `mix pybridge.discover <module>` (introspection and config generation).
   - `mix pybridge.diff <module>` (compare cached descriptor vs. new introspection).
   - `mix pybridge.clean` (purge caches & generated modules).

---

## 10. Telemetry & Observability

Emit consistent events (opt-in via manifest):

```elixir
:telemetry.execute(
  [:pybridge, :call, :stop],
  %{duration: native_time, payload_bytes: byte_size},
  %{
    integration: :dspy,
    module: "dspy.Predict",
    method: "__call__",
    streaming: false,
    session_id: session_id,
    cache_hit: false
  }
)
```

Standard metrics:
* Duration (histogram)
* Success/error counts
* Streaming chunk throughput
* Cache hit/miss ratio
* Session reuse rate

These feed into Prometheus/Grafana dashboards for production observability.

---

## 11. Security Considerations

* **Config Validation**: enforce allowlist for Python module paths, optional digital signatures for manifests in regulated environments.
* **Worker Sandbox**: reuse Snakepit process isolation; optionally require virtualenv per integration.
* **Secrets Management**: support `{:system, "ENV"}` pattern in config for API keys; PyBridge runtime resolves via `System.get_env/1` at runtime.
* **Audit Trail**: log descriptors with hash to detect tampering; optionally store in append-only log.

---

## 12. Future Work (Beyond MVP)

* Protox/Buf integration for generated gRPC clients beyond Snakepit (export to other services).
* Nx tensor streaming using `tensor_passthrough: true`.
* WASM mode (Pyodide) for serverless usage.
* VSCode plugin to author configs with autocomplete from cached descriptors.
* OpenAPI exporter for auto-generated REST facades.

---

## 13. Summary & Recommendation

* **PyBridge should ship as an independent Hex package** that depends on Snakepit and extends it via the proposed RPCs.
* Snakepit remains the execution substrate; PyBridge supplies declarative integration, code generation, and runtime ergonomics.
* DSPex becomes a thin consumer: configuration + optional custom transforms. This unlocks rapid onboarding of future Python ML libraries without repeated wrapper work.
* Immediate next steps: land Snakepit protocol updates, scaffold PyBridge library, and port DSPex onto the new abstraction as first proof point.

By executing this plan, Snakepit evolves from “Python pooler” to “Python integration fabric,” while PyBridge provides the ergonomic layer Elixir developers need to tap into the Python ecosystem with confidence.

---

**Prepared by**: Codex (GPT-5)  
**Reviewed by**: _Pending_  
**Version**: 0.1 (Draft)

