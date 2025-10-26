# Snakepit Config-Driven Python Integration Blueprint

## 1. Overview

Snakepit v0.6.x introduced a streamlined gRPC bridge focused on session and program orchestration. The next step is to turn Snakepit into a reusable integration fabric that can expose an entire Python library to Elixir with zero bespoke glue code. This document defines a configuration-driven architecture that pairs Elixir metaprogramming with Python-side introspection to produce fully functional clients at runtime. DSPex becomes the first consumer by instantiating the blueprint for DSPy, but the design generalizes to any Python ML toolkit.

## 2. Vision

* Allow any Python package to appear in Elixir as if it were a native library.
* Require only declarative configuration (no handwritten wrappers).
* Support both synchronous command execution and future streaming/telemetry flows.
* Cache introspected schemas so follow-up boots are instant.
* Emit ergonomic Elixir modules generated via macros, retaining typespecs and docs derived from Python metadata.
* Keep the runtime entirely within Snakepit so downstream Elixir apps `use Snakepit.Integration, config: ...` and immediately gain access to Python capabilities.

## 3. Guiding Principles

1. **Configuration First:** Everything the bridge needs is described in a config artifact; codegen is deterministic from that source.
2. **Runtime Introspection:** Python workers expose descriptors for functions, classes, and tool metadata. Introspection runs once per boot per integration unless cached.
3. **Metaprogrammed SDKs:** Elixir macros expand descriptors into modules with strongly typed functions, documentation, and guardrails.
4. **Session-Centric:** Snakepit’s SessionStore remains the source of truth for program state and metadata; variables are gone.
5. **Sidecar Friendly:** The Python integration kit is light enough to run inside the existing Snakepit worker lifecycle.
6. **Observability:** Every generated operation emits structured telemetry for tracing and debugging.

## 4. Core Concept — Snakepit Integration Fabric (SIF)

We refer to the new component as the **Snakepit Integration Fabric (SIF)**. SIF lives inside Snakepit and provides:

* A configuration loader for integration manifests.
* A handshake protocol workers implement to expose metadata and execution entrypoints.
* A schema cache persisted in ETS/disk for fast reloads.
* A metaprogramming layer that emits SDK modules on demand.
* Runtime helpers for executing operations and translating responses.

## 5. Architecture

### 5.1 Components

1. **Integration Manifest Loader (Elixir):** Reads config (YAML/JSON) at boot, validates against a schema, and registers integrations with Snakepit.
2. **Worker Introspection Agent (Python):** Python adapter script handles `describe_library` and returns structured metadata (available modules, methods, arguments, docstrings, streaming flags, etc.).
3. **Schema Cache (Elixir):** Stores introspection results keyed by integration ID + version hash. Supports ETS for hot cache and optional persistence to disk (e.g., `priv/integration_cache`).
4. **Module Generator (Elixir Macro):** `Snakepit.Integration` macro expands cached descriptors into modules under a configurable namespace (e.g., `DSPex.DSPy`). Generates typespecs, docs, and function wrappers calling `Snakepit.execute_in_session`.
5. **Execution Router (Elixir Runtime):** Generic dispatcher translating Elixir args onto gRPC `ExecuteToolRequest`. Applies encoding/decoding policies defined in config.
6. **Telemetry + Metrics:** Emits events like `[:snakepit, :integration, :call]` and attaches config metadata (integration name, entrypoint, latency).

### 5.2 Flow

```
Config Manifest -> Loader -> (Cache hit?) -> Module Generator -> SDK Modules
                                  |
                             (Cache miss)
                                  v
                    Snakepit Worker <-> Python Introspection Agent
                       (describe_library RPC over gRPC)
```

## 6. Integration Manifest

Manifests declare integrations in a declarative format. Example (YAML-like, convertible to JSON/EEx):

```yaml
integrations:
  dspy:
    python_package: "dspy"
    version_constraint: ">= 2.5.0"
    entrypoints:
      - name: "Predict"
        kind: "class"
        locator: "dspy.Predict"
        methods:
          - "__init__"
          - "__call__"
        execution:
          tool: "call_dspy"
          session_mode: "per_call"        # or "stateful"
    adapters:
      execute_tool: "dspy_grpc.execute_tool"
      register_program: "dspy_grpc.register_program"
    serialization:
      args: "json"
      result: "json"
    telemetry:
      enabled: true
      tags:
        domain: "ml"
        family: "dspy"
    codegen:
      namespace: "DSPex"
      module_prefix: "DSPy"
      behaviours:
        - "Snakepit.Integration.Behaviours.Program"
    caching:
      enabled: true
      ttl_seconds: 86400
```

Key sections:

* `integrations` — Multiple definitions allowed.
* `entrypoints` — Classes/functions to expose. Methods list can be explicit or introspection-driven.
* `execution` — Maps to the gRPC tool(s) used; can specify session policy.
* `adapters` — Optional override names for Python handlers.
* `serialization` — How to encode args/return values (`json`, `msgpack`, `raw`).
* `codegen` — Determines namespace and optional behaviours.
* `caching` — TTL for introspection results.

## 7. Runtime Lifecycle

1. **Boot:** Loader reads manifests, validates them, and registers integration descriptors.
2. **Introspection:** For each integration without a fresh cache, Snakepit calls the worker’s `describe_library` RPC. The Python side returns descriptors (`classes`, `functions`, arguments, docstrings, streaming support, etc.).
3. **Codegen:** Generator macro receives descriptors and emits modules during compilation (or at runtime via `Code.compile_quoted/1` for dynamic reload). Each function wraps a call to `Snakepit.execute_in_session/4` with consistent argument preparation and response decoding.
4. **Execution:** At runtime, Elixir consumers call generated modules; dispatcher routes to Snakepit’s gRPC client, attaches session metadata, and returns decoded results.
5. **Observability:** Telemetry spans capture execution metrics, tying back to integration config for dashboards.

## 8. Elixir Metaprogramming Strategy

Provide a reusable macro, e.g.:

```elixir
defmodule Snakepit.Integration do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @integration_id opts[:integration_id]
      descriptors = Snakepit.Integration.Registry.fetch!(@integration_id)

      for %{elixir_module: module_name, functions: funcs} <- descriptors.modules do
        defmodule module_name do
          @moduledoc descriptors.docs[module_name]

          for fn_desc <- funcs do
            @spec unquote(fn_desc.name)(unquote_splicing(fn_desc.typespec_args)) ::
                    unquote(fn_desc.return_spec)
            def unquote(fn_desc.name)(session_id \\ Snakepit.Session.new(), args \\ %{}, opts \\ []) do
              Snakepit.Integration.Executor.call(
                @integration_id,
                unquote(fn_desc.remote_name),
                session_id,
                args,
                opts
              )
            end
          end
        end
      end
    end
  end
end
```

Descriptors come from cache and include docstrings, argument metadata, streaming flags, and expected result schemas. DSL provides the ability to map Python names to idiomatic Elixir ones (`predict/3` instead of `__call__`).

## 9. Python Introspection Agent

Python workers must implement two extensions in addition to normal tool handlers:

1. `describe_library(config)` — Returns metadata:
   ```json
   {
     "package": "dspy",
     "version": "2.5.1",
     "modules": [
       {
         "name": "Predict",
         "kind": "class",
         "elixir_name": "Predictor",
         "methods": [
           {
             "name": "__call__",
             "elixir_name": "predict",
             "doc": "Run inference.",
             "args": [
               {"name": "question", "type": "str", "required": true}
             ],
             "returns": {"type": "dict"},
             "supports_streaming": false
           }
         ]
       }
     ]
   }
   ```
2. `execute_tool` — Already exists; must respect the descriptors (names, argument converters, session policy). Optionally, provide validation endpoints when misconfigurations arise.

Introspection data can be produced with Python reflection (`inspect`, `typing.get_type_hints`) and stabilized via dataclasses to ensure consistent schema.

## 10. MVP Scope

* **Configuration Parser & Schema:** Accepts JSON/YAML manifest, validates required keys.
* **Integration Registry:** Stores manifests and cached descriptors (ETS + optional disk).
* **Introspection RPC:** Define `describe_library` request/response proto, implement server + client inside Snakepit’s gRPC layer.
* **Basic Codegen Macro:** Generates modules for functions/methods with synchronous execution (no streaming yet).
* **Execution Router:** Single function that packages args and calls Snakepit’s gRPC client, honoring serialization policy.
* **DSPy Manifest:** Encode DSPy core classes (`Predict`, `ChainOfThought`, etc.) with manual method lists (introspection optional in MVP).
* **Telemetry Hooks:** Emit events with integration name, entrypoint, latency, session, success flag.
* **Docs & Examples:** Provide quickstart showing how an Elixir app declares an integration and invokes generated modules.

Out of scope for MVP: streaming, automatic schema diffing, advanced error recovery, interactive code reload.

## 11. DSPy Instantiation

DSPex becomes a thin wrapper:

```elixir
defmodule DSPex do
  use Snakepit.Integration,
    integration_id: :dspy,
    manifest: "config/dspy_integration.yml"
end
```

The manifest lists DSPy entrypoints. On boot:

1. Snakepit loads `:dspy` manifest.
2. Cache miss triggers `describe_library` on Python worker (`dspex_adapters.dspy_grpc.DSPyGRPCHandler`).
3. Generated modules appear under `DSPex.DSPy.*` (e.g., `DSPex.DSPy.Predict`). Each function wraps `Snakepit.execute_in_session(session_id, "call_dspy", args)`.
4. DSPex also uses the descriptors to expose metadata (list of modules, signatures) for UI/CLI clients.

Because DSPEx does no manual wiring, upgrading DSPy simply refreshes the manifest and introspection cache.

## 12. Future Extensions

* **Streaming RPCs:** Extend `execute_streaming_tool` to support method descriptors marked `supports_streaming: true`.
* **Schema Diffing:** Detect changed Python interfaces and emit warnings before regeneration.
* **Implicit Config:** Ship curated manifests for popular libraries; allow overrides.
* **OpenAPI Export:** Derive REST/gRPC descriptions from the same descriptors, enabling multi-client generation.
* **Interactive Console:** Provide `iex` helpers for exploring available modules/functions dynamically.
* **Multi-language Support:** Extend to Node.js/Ruby by swapping the introspection agent.

## 13. Open Questions

* Where should cached descriptors persist across deployments? Options include ETS snapshot, `persistent_term`, or disk files.
* How should authentication/authorization map onto integration usage? (Possibly via per-entrypoint policy in manifest.)
* Do we need version pinning enforcement (fail boot if Python package version mismatches manifest expectation)?
* What format best balances readability and rigidity for manifests? YAML is convenient, but JSON may be safer for runtime embedding.
* Can we pre-generate modules at compile time for Umbrella apps to avoid runtime code compilation in production?

## 14. Next Steps

1. Define protobuf messages for `describe_library` and update Snakepit’s gRPC service.
2. Build a minimal manifest parser and registry.
3. Implement Python introspection kit for DSPy (leveraging existing `dspy_grpc.py` handler).
4. Create the `Snakepit.Integration` macro with descriptor-driven module generation.
5. Wire DSPex to consume the new integration and replace legacy bridge code.
6. Add integration tests demonstrating manifest-driven exposure of simple Python functions.

This blueprint positions Snakepit as the reusable integration substrate and turns DSPex into a thin manifest + macro invocation. Once the MVP lands, adding new Python libraries becomes a matter of authoring manifests and optionally customizing introspection helpers.
