# Stage 1 Prompt 3: Adapter Pattern Implementation (Updated for 3-Layer Testing)

## OBJECTIVE

Implement a robust adapter pattern that provides a clean abstraction layer for DSPy operations, enabling seamless switching between Python port implementation, testing adapters, and future native Elixir implementations. This adapter system must integrate with our 3-layer testing architecture and provide consistent interfaces while hiding the complexity of underlying execution mechanisms.

## INTEGRATION WITH 3-LAYER TESTING ARCHITECTURE

### OVERVIEW OF EXISTING TEST SYSTEM

Our current 3-layer testing architecture provides:

- **Layer 1 (mock_adapter)**: Fast unit tests (~70ms) using pure Elixir mock
- **Layer 2 (bridge_mock)**: Protocol testing without full Python DSPy 
- **Layer 3 (full_integration)**: Complete Python bridge integration tests

**Test Mode System Integration Points:**
- Environment variable: `TEST_MODE=mock_adapter|bridge_mock|full_integration`
- Mix aliases: `mix test.fast`, `mix test.protocol`, `mix test.integration`
- Conditional supervisor respects test modes
- ExUnit test tagging with `@moduletag :layer_1|:layer_2|:layer_3`

### ADAPTER MAPPING TO TEST LAYERS

```
┌─────────────────────────────────────────────────────────────┐
│                Adapter-Driven Test Architecture            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1 (Fast)    │  Layer 2 (Protocol)  │  Layer 3 (Full)│
│  ┌──────────────┐  │  ┌─────────────────┐  │  ┌─────────────┐│
│  │ Mock         │  │  │ BridgeMock      │  │  │ PythonPort  ││
│  │ Adapter      │  │  │ Adapter         │  │  │ Adapter     ││
│  │ - Pure Elixir│  │  │ - Wire protocol │  │  │ - Full DSPy ││
│  │ - 70ms tests │  │  │ - No Python     │  │  │ - E2E tests ││
│  │ - Deterministic│ │  │ - Mock server   │  │  │ - Real ML   ││
│  └──────────────┘  │  └─────────────────┘  │  └─────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## COMPLETE IMPLEMENTATION CONTEXT

### ADAPTER PATTERN ARCHITECTURE OVERVIEW

From DSPY_ADAPTER_LAYER_ARCHITECTURE.md with testing integration:

```
┌─────────────────────────────────────────────────────────────┐
│                    Adapter Layer Architecture              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Adapter         │  │ Test Mode       │  │ Registry     ││
│  │ Behavior        │  │ Integration     │  │ System       ││
│  │ - create_program│  │ - Layer mapping │  │ - Auto select││
│  │ - execute       │  │ - ENV detection │  │ - Validation ││
│  │ - list_programs │  │ - Mix aliases   │  │ - Config     ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Mock Adapter    │  │ BridgeMock      │  │ PythonPort   ││
│  │ (Layer 1)       │  │ Adapter         │  │ Adapter      ││
│  │ - Deterministic │  │ (Layer 2)       │  │ (Layer 3)    ││
│  │ - GenServer     │  │ - Protocol test │  │ - Real Bridge││
│  │ - Call logging  │  │ - Wire format   │  │ - DSPy calls ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Core Design Principles:**
- Clean interface abstraction hiding implementation details
- **Integration with existing 3-layer test architecture**
- **Automatic adapter selection based on TEST_MODE**
- Consistent error handling across all adapters
- Type conversion and validation at adapter boundaries
- Configuration-driven adapter selection for production
- Extensible architecture for future implementations

### ENHANCED ADAPTER BEHAVIOR DEFINITION

```elixir
defmodule DSPex.Adapters.Adapter do
  @moduledoc """
  Behavior for DSPy adapters with 3-layer testing support.
  """
  
  @type program_config :: %{
    id: String.t(),
    signature: module(),
    modules: list(map()),
    settings: map()
  }
  
  @type execution_options :: %{
    timeout: pos_integer(),
    max_retries: non_neg_integer(),
    context: map()
  }
  
  @type program_info :: %{
    id: String.t(),
    signature: map(),
    status: atom(),
    created_at: DateTime.t(),
    stats: map()
  }
  
  # Core operations (required for all adapters)
  @callback create_program(program_config()) :: {:ok, String.t()} | {:error, term()}
  @callback execute_program(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_programs() :: {:ok, list(String.t())} | {:error, term()}
  @callback delete_program(String.t()) :: :ok | {:error, term()}
  
  # Extended operations (optional with default implementations)
  @callback execute_program(String.t(), map(), execution_options()) :: {:ok, map()} | {:error, term()}
  @callback get_program_info(String.t()) :: {:ok, program_info()} | {:error, term()}
  @callback validate_signature(module()) :: :ok | {:error, term()}
  
  # Health and monitoring (adapter-specific implementations)
  @callback health_check() :: :ok | {:error, term()}
  @callback get_stats() :: {:ok, map()} | {:error, term()}
  @callback cleanup() :: :ok | {:error, term()}
  
  # Test layer compatibility
  @callback supports_test_layer?(atom()) :: boolean()
  @callback get_test_capabilities() :: map()
  
  @optional_callbacks [
    execute_program: 3,
    get_program_info: 1,
    validate_signature: 1,
    health_check: 0,
    get_stats: 0,
    cleanup: 0,
    supports_test_layer?: 1,
    get_test_capabilities: 0
  ]
end
```

### TEST-MODE INTEGRATED REGISTRY SYSTEM

**Registry with Test Mode Integration:**
```elixir
defmodule DSPex.Adapters.Registry do
  @moduledoc """
  Registry for managing available adapters with 3-layer test integration.
  """
  
  @default_adapter DSPex.Adapters.PythonPort
  
  @adapters %{
    python_port: DSPex.Adapters.PythonPort,
    bridge_mock: DSPex.Adapters.BridgeMock,  # New for Layer 2
    mock: DSPex.Adapters.Mock,
    native: DSPex.Adapters.Native  # Future implementation
  }
  
  @test_layer_adapters %{
    mock_adapter: :mock,
    bridge_mock: :bridge_mock,
    full_integration: :python_port
  }
  
  def get_adapter(adapter_name \\ nil) do
    # Priority: explicit -> test mode -> config -> default
    resolved_adapter = 
      adapter_name || 
      get_test_mode_adapter() || 
      Application.get_env(:dspex, :adapter) ||
      @default_adapter
    
    case resolved_adapter do
      atom when is_atom(atom) and is_map_key(@adapters, atom) -> 
        Map.get(@adapters, atom)
      module when is_atom(module) -> 
        module
      string when is_binary(string) -> 
        String.to_existing_atom(string) |> get_adapter()
      _ -> 
        @default_adapter
    end
  end
  
  defp get_test_mode_adapter do
    if Mix.env() == :test do
      case DSPex.Testing.TestMode.current_test_mode() do
        test_mode when is_map_key(@test_layer_adapters, test_mode) ->
          Map.get(@test_layer_adapters, test_mode)
        _ -> 
          nil
      end
    end
  end
  
  def get_adapter_for_test_layer(layer) do
    case layer do
      :layer_1 -> Map.get(@adapters, :mock)
      :layer_2 -> Map.get(@adapters, :bridge_mock)
      :layer_3 -> Map.get(@adapters, :python_port)
      _ -> @default_adapter
    end
  end
  
  def list_adapters do
    Map.keys(@adapters)
  end
  
  def list_test_layer_adapters do
    @test_layer_adapters
  end
  
  def validate_adapter(adapter) do
    case Code.ensure_loaded(adapter) do
      {:module, _} ->
        if function_exported?(adapter, :create_program, 1) and
           function_exported?(adapter, :execute_program, 2) and
           function_exported?(adapter, :list_programs, 0) do
          {:ok, adapter}
        else
          {:error, "Adapter does not implement required callbacks: #{adapter}"}
        end
      {:error, reason} ->
        {:error, "Failed to load adapter #{adapter}: #{reason}"}
    end
  end
  
  def validate_test_layer_compatibility(adapter, test_layer) do
    if function_exported?(adapter, :supports_test_layer?, 1) do
      case adapter.supports_test_layer?(test_layer) do
        true -> {:ok, adapter}
        false -> {:error, "Adapter #{adapter} does not support test layer #{test_layer}"}
      end
    else
      # Assume compatibility if not implemented
      {:ok, adapter}
    end
  end
end
```

### BRIDGE MOCK ADAPTER (NEW FOR LAYER 2)

**New Adapter for Protocol Testing:**
```elixir
defmodule DSPex.Adapters.BridgeMock do
  @moduledoc """
  Bridge mock adapter for Layer 2 protocol testing.
  
  This adapter validates the wire protocol and message format without
  requiring full Python DSPy. It uses our existing BridgeMockServer
  to simulate the Python bridge communication layer.
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  alias DSPex.Testing.BridgeMockServer
  alias DSPex.PythonBridge.Protocol
  
  @impl true
  def create_program(config) do
    # Convert signature to wire protocol format
    signature_def = convert_signature_to_wire_format(config.signature)
    
    # Send through mock bridge to validate protocol
    case send_mock_command(:create_program, %{
      id: config.id,
      signature: signature_def,
      modules: config.modules || []
    }) do
      {:ok, response} -> {:ok, config.id}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    case send_mock_command(:execute_program, %{
      program_id: program_id,
      inputs: inputs
    }) do
      {:ok, response} -> 
        # Generate deterministic mock outputs based on protocol response
        {:ok, generate_protocol_compatible_outputs(inputs)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def list_programs do
    case send_mock_command(:list_programs, %{}) do
      {:ok, response} -> {:ok, []}  # Mock empty list for protocol testing
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def delete_program(program_id) do
    case send_mock_command(:delete_program, %{program_id: program_id}) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def health_check do
    case BridgeMockServer.ping() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def get_stats do
    {:ok, %{
      adapter_type: :bridge_mock,
      layer: :layer_2,
      protocol_validated: true,
      mock_server_running: BridgeMockServer.running?()
    }}
  end
  
  @impl true
  def cleanup do
    # No cleanup needed for mock
    :ok
  end
  
  @impl true
  def supports_test_layer?(layer) do
    layer == :layer_2
  end
  
  @impl true
  def get_test_capabilities do
    %{
      protocol_validation: true,
      wire_format_testing: true,
      python_execution: false,
      deterministic_outputs: true,
      performance: :fast
    }
  end
  
  defp send_mock_command(command, args) do
    # Use existing bridge mock server infrastructure
    case BridgeMockServer.handle_command(command, args) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp convert_signature_to_wire_format(signature_module) do
    signature = signature_module.__signature__()
    
    %{
      inputs: convert_fields_to_wire_format(signature.inputs),
      outputs: convert_fields_to_wire_format(signature.outputs)
    }
  end
  
  defp convert_fields_to_wire_format(fields) do
    Enum.map(fields, fn {name, type, _constraints} ->
      %{
        name: to_string(name),
        type: convert_type_to_wire_format(type),
        description: ""
      }
    end)
  end
  
  defp convert_type_to_wire_format(:string), do: "str"
  defp convert_type_to_wire_format(:integer), do: "int"
  defp convert_type_to_wire_format(:float), do: "float"
  defp convert_type_to_wire_format(:boolean), do: "bool"
  defp convert_type_to_wire_format({:list, inner}), do: "List[#{convert_type_to_wire_format(inner)}]"
  defp convert_type_to_wire_format(type), do: to_string(type)
  
  defp generate_protocol_compatible_outputs(inputs) do
    # Generate deterministic outputs that validate protocol format
    %{
      "result" => "mock_protocol_validated_output",
      "confidence" => 0.95,
      "reasoning" => ["Protocol validation", "Wire format test"],
      "input_echo" => inputs
    }
  end
end
```

### UPDATED MOCK ADAPTER (ENHANCED FOR LAYER 1)

**Enhanced Mock Implementation:**
```elixir
defmodule DSPex.Adapters.Mock do
  @moduledoc """
  Mock adapter for Layer 1 fast testing.
  
  Enhanced with test capabilities and integration with 3-layer architecture.
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  use GenServer
  
  defstruct [
    programs: %{}, 
    call_log: [], 
    config: %{},
    stats: %{
      programs_created: 0,
      programs_executed: 0,
      total_calls: 0
    }
  ]
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  # ... existing core implementations ...
  
  @impl true
  def supports_test_layer?(layer) do
    layer == :layer_1
  end
  
  @impl true
  def get_test_capabilities do
    %{
      deterministic_outputs: true,
      call_logging: true,
      fast_execution: true,
      python_execution: false,
      protocol_validation: false,
      performance: :fastest
    }
  end
  
  # Enhanced with configurable behavior for different test scenarios
  def configure_behavior(config) do
    GenServer.call(__MODULE__, {:configure, config})
  end
  
  def get_call_log do
    GenServer.call(__MODULE__, :get_call_log)
  end
  
  def reset do
    GenServer.call(__MODULE__, :reset)
  end
  
  # ... rest of existing implementation with enhancements ...
end
```

### PYTHON PORT ADAPTER (UPDATED FOR LAYER 3)

**Enhanced for Integration Testing:**
```elixir
defmodule DSPex.Adapters.PythonPort do
  @moduledoc """
  Python port adapter for Layer 3 full integration testing.
  
  Enhanced with test capabilities and robust error handling.
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  alias DSPex.PythonBridge.Bridge
  alias DSPex.Adapters.TypeConverter
  
  # ... existing core implementations ...
  
  @impl true
  def supports_test_layer?(layer) do
    layer == :layer_3
  end
  
  @impl true
  def get_test_capabilities do
    %{
      python_execution: true,
      real_ml_models: true,
      protocol_validation: true,
      deterministic_outputs: false,
      performance: :slowest,
      requires_environment: [:python, :dspy, :api_keys]
    }
  end
  
  @impl true
  def health_check do
    case Bridge.call(:ping, %{}, 5000) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, "Python bridge health check failed: #{reason}"}
    end
  end
  
  # ... enhanced implementations with better error handling ...
end
```

### TEST MODE INTEGRATION UPDATES

**Updated TestMode Module:**
```elixir
defmodule DSPex.Testing.TestMode do
  # ... existing functions ...
  
  @doc """
  Returns the appropriate adapter module for the current test mode.
  Now uses the Registry system for consistency.
  """
  @spec get_adapter_module() :: 
    DSPex.Adapters.Mock | DSPex.Adapters.BridgeMock | DSPex.Adapters.PythonPort
  def get_adapter_module do
    DSPex.Adapters.Registry.get_adapter()
  end
  
  def get_adapter_for_current_layer do
    case effective_test_mode() do
      :mock_adapter -> DSPex.Adapters.Registry.get_adapter_for_test_layer(:layer_1)
      :bridge_mock -> DSPex.Adapters.Registry.get_adapter_for_test_layer(:layer_2)
      :full_integration -> DSPex.Adapters.Registry.get_adapter_for_test_layer(:layer_3)
    end
  end
  
  def validate_adapter_compatibility do
    adapter = get_adapter_module()
    test_mode = effective_test_mode()
    
    case test_mode do
      :mock_adapter -> validate_layer_1_adapter(adapter)
      :bridge_mock -> validate_layer_2_adapter(adapter)
      :full_integration -> validate_layer_3_adapter(adapter)
    end
  end
  
  defp validate_layer_1_adapter(adapter) do
    capabilities = adapter.get_test_capabilities()
    
    if capabilities.fast_execution and capabilities.deterministic_outputs do
      :ok
    else
      {:error, "Adapter not suitable for Layer 1 fast testing"}
    end
  end
  
  defp validate_layer_2_adapter(adapter) do
    capabilities = adapter.get_test_capabilities()
    
    if capabilities.protocol_validation and not capabilities.python_execution do
      :ok
    else
      {:error, "Adapter not suitable for Layer 2 protocol testing"}
    end
  end
  
  defp validate_layer_3_adapter(adapter) do
    capabilities = adapter.get_test_capabilities()
    
    if capabilities.python_execution do
      :ok
    else
      {:error, "Adapter not suitable for Layer 3 integration testing"}
    end
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the adapter pattern system with **full integration to our 3-layer testing architecture** with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/adapters/
├── adapter.ex             # Core behavior definition with test layer support
├── python_port.ex         # Python bridge adapter (Layer 3)
├── bridge_mock.ex         # NEW: Bridge mock adapter (Layer 2)
├── mock.ex               # Enhanced mock adapter (Layer 1)
├── registry.ex           # Test-mode integrated adapter selection
├── factory.ex            # Adapter creation and execution
├── type_converter.ex     # Type conversion system
├── error_handler.ex      # Error handling and context
└── supervisor.ex         # Adapter supervision

test/dspex/adapters/
├── behavior_test.exs     # Adapter behavior compliance tests
├── python_port_test.exs  # Python port adapter tests (Layer 3 tagged)
├── bridge_mock_test.exs  # NEW: Bridge mock adapter tests (Layer 2 tagged)
├── mock_test.exs         # Enhanced mock adapter tests (Layer 1 tagged)
├── registry_test.exs     # Registry with test mode functionality
└── type_converter_test.exs # Type conversion tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Enhanced Adapter Behavior** (`lib/dspex/adapters/adapter.ex`):
   - Core behavior with test layer support callbacks
   - Test capability introspection
   - Layer compatibility validation
   - Performance characteristics metadata

2. **BridgeMock Adapter** (`lib/dspex/adapters/bridge_mock.ex`) **[NEW]**:
   - Layer 2 protocol testing without Python
   - Integration with existing BridgeMockServer
   - Wire protocol format validation
   - Deterministic mock responses for protocol testing

3. **Test-Integrated Registry** (`lib/dspex/adapters/registry.ex`):
   - Automatic adapter selection based on TEST_MODE
   - Test layer compatibility validation
   - Integration with existing TestMode module
   - Environment-aware adapter selection

4. **Enhanced Mock Adapter** (`lib/dspex/adapters/mock.ex`):
   - Test capability metadata
   - Configurable behavior for test scenarios
   - Integration with Layer 1 requirements
   - Call logging and state inspection

5. **Updated TestMode Integration**:
   - Update `DSPex.Testing.TestMode.get_adapter_module()` to use Registry
   - Add adapter validation for test layers
   - Maintain backwards compatibility with existing test helpers

### QUALITY REQUIREMENTS:

- **Test Layer Integration**: All adapters must declare layer compatibility
- **Backwards Compatibility**: Existing tests should continue working
- **Test Mode Awareness**: Registry automatically selects correct adapter for TEST_MODE
- **Layer Validation**: Ensure adapters are suitable for their assigned test layers
- **Performance Tracking**: Each adapter declares performance characteristics
- **Comprehensive Coverage**: All three layers have appropriate adapter implementations

### INTEGRATION POINTS:

- **Existing Test Infrastructure**: Must work with current test helpers and foundations
- **BridgeMockServer**: Layer 2 adapter integrates with existing mock server
- **Python Bridge**: Layer 3 adapter continues using existing bridge
- **TestMode System**: Registry integrates with existing test mode detection
- **Mix Aliases**: Existing `mix test.fast/protocol/integration` continue working

### SUCCESS CRITERIA:

1. **Three adapters support three test layers** correctly
2. **Registry automatically selects adapters** based on TEST_MODE
3. **All existing tests continue passing** with minimal changes
4. **Test layer validation** prevents adapter misuse
5. **Performance characteristics** are properly declared and validated
6. **Protocol testing works** without requiring Python/DSPy
7. **Integration with existing infrastructure** is seamless
8. **Future extensibility** for additional adapters is maintained

This enhanced adapter pattern provides a robust abstraction layer that fully integrates with our proven 3-layer testing architecture while maintaining all the benefits of the original prompt's comprehensive adapter system.