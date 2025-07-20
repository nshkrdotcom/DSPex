  Proposed Architecture for Dual Implementation Support

  1. Strategy Pattern with Runtime Routing

  The key is to maintain the same public API while internally routing to the appropriate
  implementation:

  defmodule DSPex.Modules.ChainOfThought do
    @moduledoc """
    Chain of Thought reasoning module.
    Routes to native implementation when available, falls back to Python DSPy.
    """

    def create(signature, opts \\ []) do
      case implementation_for(:chain_of_thought) do
        :native ->
          DSPex.Native.ChainOfThought.create(signature, opts)
        :python ->
          create_via_python(signature, opts)
      end
    end

    defp implementation_for(module_type) do
      if DSPex.Native.Registry.has?(module_type) do
        :native
      else
        :python
      end
    end
  end

  2. Implementation Registry

  Create a registry that tracks which modules have native implementations:

  defmodule DSPex.Implementation.Registry do
    @native_modules %{
      signature: true,           # Already native
      template: true,           # Already native
      validator: true,          # Already native
      predict: false,           # Python for now
      chain_of_thought: false,  # Python for now
      react: false,            # Python for now
      # ... etc
    }

    def available_implementations(module_type) do
      case @native_modules[module_type] do
        true -> [:native, :python]
        false -> [:python]
        nil -> []
      end
    end

    def preferred_implementation(module_type, opts \\ []) do
      force = opts[:implementation]

      cond do
        force == :native && has_native?(module_type) -> :native
        force == :python -> :python
        has_native?(module_type) && native_preferred?() -> :native
        true -> :python
      end
    end
  end

  3. Unified Module Protocol

  Define a protocol that both native and Python implementations must satisfy:

  defprotocol DSPex.Module do
    @doc "Create a new instance of the module"
    def create(impl, signature, opts)

    @doc "Execute the module with inputs"
    def execute(impl, module_id, inputs, opts)

    @doc "Get module metadata"
    def info(impl)
  end

  4. Adapter Pattern for Consistent Interface

  Each implementation gets an adapter:

  defmodule DSPex.Adapters.Native do
    defstruct [:module_type]

    defimpl DSPex.Module do
      def create(%{module_type: type}, signature, opts) do
        native_module = Module.concat([DSPex.Native, type])
        native_module.create(signature, opts)
      end

      def execute(%{module_type: type}, module_id, inputs, opts) do
        native_module = Module.concat([DSPex.Native, type])
        native_module.execute(module_id, inputs, opts)
      end
    end
  end

  defmodule DSPex.Adapters.Python do
    defstruct [:module_type]

    defimpl DSPex.Module do
      def create(%{module_type: :chain_of_thought}, signature, opts) do
        # Snakepit call to create DSPy module
      end
    end
  end

  5. Router Enhancement

  Enhance the existing Router to handle implementation selection:

  defmodule DSPex.Router do
    def route(operation, args, opts \\ []) do
      implementation = select_implementation(operation, opts)

      telemetry_metadata = %{
        operation: operation,
        implementation: implementation,
        native_available: native_available?(operation)
      }

      :telemetry.execute(
        [:dspex, :router, :route],
        %{},
        telemetry_metadata
      )

      case implementation do
        :native -> route_to_native(operation, args, opts)
        :python -> route_to_python(operation, args, opts)
      end
    end
  end

  6. Configuration for Implementation Preferences

  Allow users to configure their preferences:

  # config/config.exs
  config :dspex,
    implementation_preference: :auto,  # :auto, :native_first, :python_first
    allow_fallback: true,
    module_overrides: %{
      # Force specific modules to use certain implementations
      chain_of_thought: :python,
      predict: :native
    }

  7. Gradual Migration Path

  As you implement native versions:

  1. Start with Python wrapper (what we just created)
  2. Implement native version alongside Python
  3. Add feature flags for testing
  4. Gradually enable native based on performance/stability
  5. Keep Python as fallback for edge cases

  8. Performance Metrics Collection

  Track performance to make intelligent routing decisions:

  defmodule DSPex.Metrics.Collector do
    def track_execution(module_type, implementation, duration, success?) do
      # Store metrics for adaptive routing
      # Could influence future routing decisions
    end
  end

  9. Transparent API Example

  The end user experience remains the same regardless of implementation:

  # User code - doesn't change whether native or Python
  {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
  {:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{question: "..."})

  # Can force implementation if needed
  {:ok, cot} = DSPex.Modules.ChainOfThought.create(
    "question -> answer",
    implementation: :native  # or :python
  )

  10. Benefits of This Approach

  1. Zero API changes as you migrate to native
  2. Gradual rollout with feature flags
  3. Performance comparison between implementations
  4. Fallback safety if native has issues
  5. User control when needed
  6. Clean separation of concerns

  This architecture allows DSPex to evolve from Python-backed to native implementation module by
  module, while maintaining a stable API for users.
