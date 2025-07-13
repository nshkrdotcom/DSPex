# Stage 1 Prompt 3: Adapter Pattern Implementation

## OBJECTIVE

Implement a robust adapter pattern that provides a clean abstraction layer for DSPy operations, enabling seamless switching between Python port implementation and future native Elixir implementations. This adapter system must provide consistent interfaces while hiding the complexity of underlying execution mechanisms.

## COMPLETE IMPLEMENTATION CONTEXT

### ADAPTER PATTERN ARCHITECTURE OVERVIEW

From DSPY_ADAPTER_LAYER_ARCHITECTURE.md and STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```
┌─────────────────────────────────────────────────────────────┐
│                    Adapter Layer Architecture              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Adapter         │  │ Python Port     │  │ Future       ││
│  │ Behavior        │  │ Adapter         │  │ Native       ││
│  │ - create_program│  │ - Bridge comm   │  │ Adapter      ││
│  │ - execute       │  │ - Type convert  │  │ - Pure Elixir││
│  │ - list_programs │  │ - Error handling│  │ - WebAssembly││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Core Design Principles:**
- Clean interface abstraction hiding implementation details
- Consistent error handling across all adapters
- Type conversion and validation at adapter boundaries
- Configuration-driven adapter selection
- Extensible architecture for future implementations

### ADAPTER BEHAVIOR DEFINITION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule DSPex.Adapters.Adapter do
  @moduledoc """
  Behavior for DSPy adapters.
  """
  
  @type program_config :: %{
    id: String.t(),
    signature: module(),
    modules: list(map())
  }
  
  @callback create_program(program_config()) :: {:ok, String.t()} | {:error, term()}
  @callback execute_program(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_programs() :: {:ok, list(String.t())} | {:error, term()}
end
```

**Extended Behavior Requirements:**
- Program lifecycle management (create, execute, destroy)
- Signature compatibility validation
- Resource management and cleanup
- Performance metrics and monitoring
- Error context and debugging information

### COMPLETE PYTHON PORT ADAPTER IMPLEMENTATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md with extensions:

```elixir
defmodule DSPex.Adapters.PythonPort do
  @moduledoc """
  Python port adapter for DSPy integration.
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  alias DSPex.PythonBridge.Bridge
  
  @impl true
  def create_program(config) do
    # Convert signature to Python format
    signature_def = convert_signature(config.signature)
    
    Bridge.call(:create_program, %{
      id: config.id,
      signature: signature_def,
      modules: config.modules || []
    })
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    Bridge.call(:execute_program, %{
      program_id: program_id,
      inputs: inputs
    })
  end
  
  @impl true
  def list_programs do
    Bridge.call(:list_programs, %{})
  end
  
  defp convert_signature(signature_module) do
    signature = signature_module.__signature__()
    
    %{
      inputs: convert_fields(signature.inputs),
      outputs: convert_fields(signature.outputs)
    }
  end
  
  defp convert_fields(fields) do
    Enum.map(fields, fn {name, type, _constraints} ->
      %{
        name: to_string(name),
        type: convert_type(type)
      }
    end)
  end
  
  defp convert_type(:string), do: "str"
  defp convert_type(:integer), do: "int"
  defp convert_type(:float), do: "float"
  defp convert_type(:boolean), do: "bool"
  defp convert_type({:list, inner}), do: "List[#{convert_type(inner)}]"
  defp convert_type(type), do: to_string(type)
end
```

### CONFIGURATION-DRIVEN ADAPTER SELECTION

From application configuration patterns:

```elixir
defmodule DSPex.Adapters.Registry do
  @moduledoc """
  Registry for managing available adapters and selection.
  """
  
  @default_adapter DSPex.Adapters.PythonPort
  
  @adapters %{
    python_port: DSPex.Adapters.PythonPort,
    native: DSPex.Adapters.Native,
    mock: DSPex.Adapters.Mock
  }
  
  def get_adapter(adapter_name \\ nil) do
    case adapter_name || Application.get_env(:dspex, :adapter) do
      nil -> @default_adapter
      atom when is_atom(atom) -> Map.get(@adapters, atom, @default_adapter)
      module when is_atom(module) -> module
      string when is_binary(string) -> 
        String.to_existing_atom(string) |> get_adapter()
    end
  end
  
  def list_adapters do
    Map.keys(@adapters)
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
end
```

### ENHANCED ADAPTER BEHAVIOR WITH EXTENDED OPERATIONS

**Extended Behavior Definition:**
```elixir
defmodule DSPex.Adapters.ExtendedAdapter do
  @moduledoc """
  Extended adapter behavior with additional operations.
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
  
  # Core operations
  @callback create_program(program_config()) :: {:ok, String.t()} | {:error, term()}
  @callback execute_program(String.t(), map(), execution_options()) :: {:ok, map()} | {:error, term()}
  @callback destroy_program(String.t()) :: :ok | {:error, term()}
  
  # Management operations
  @callback list_programs() :: {:ok, list(String.t())} | {:error, term()}
  @callback get_program_info(String.t()) :: {:ok, program_info()} | {:error, term()}
  @callback validate_signature(module()) :: :ok | {:error, term()}
  
  # Health and monitoring
  @callback health_check() :: :ok | {:error, term()}
  @callback get_stats() :: {:ok, map()} | {:error, term()}
  @callback cleanup() :: :ok | {:error, term()}
end
```

### TYPE CONVERSION AND VALIDATION SYSTEM

**Comprehensive Type Mapping:**
```elixir
defmodule DSPex.Adapters.TypeConverter do
  @moduledoc """
  Type conversion between Elixir and adapter-specific formats.
  """
  
  @type_mappings %{
    # Basic types
    :string => %{python: "str", json_schema: "string"},
    :integer => %{python: "int", json_schema: "integer"},
    :float => %{python: "float", json_schema: "number"},
    :boolean => %{python: "bool", json_schema: "boolean"},
    :atom => %{python: "str", json_schema: "string"},
    :any => %{python: "Any", json_schema: "any"},
    :map => %{python: "Dict", json_schema: "object"},
    
    # ML-specific types
    :embedding => %{python: "List[float]", json_schema: "array"},
    :probability => %{python: "float", json_schema: "number"},
    :confidence_score => %{python: "float", json_schema: "number"},
    :reasoning_chain => %{python: "List[str]", json_schema: "array"}
  }
  
  def convert_type(type, target_format) do
    case type do
      # Basic types
      basic when is_atom(basic) ->
        get_type_mapping(basic, target_format)
      
      # Composite types
      {:list, inner_type} ->
        inner_converted = convert_type(inner_type, target_format)
        case target_format do
          :python -> "List[#{inner_converted}]"
          :json_schema -> %{type: "array", items: inner_converted}
        end
      
      {:dict, key_type, value_type} ->
        key_converted = convert_type(key_type, target_format)
        value_converted = convert_type(value_type, target_format)
        case target_format do
          :python -> "Dict[#{key_converted}, #{value_converted}]"
          :json_schema -> %{
            type: "object",
            additionalProperties: value_converted
          }
        end
      
      {:union, types} ->
        converted_types = Enum.map(types, &convert_type(&1, target_format))
        case target_format do
          :python -> "Union[#{Enum.join(converted_types, ", ")}]"
          :json_schema -> %{anyOf: converted_types}
        end
    end
  end
  
  defp get_type_mapping(type, target_format) do
    case Map.get(@type_mappings, type) do
      nil -> {:error, "Unknown type: #{type}"}
      mapping -> Map.get(mapping, target_format, to_string(type))
    end
  end
  
  def validate_input(value, expected_type) do
    case {value, expected_type} do
      {v, :string} when is_binary(v) -> {:ok, v}
      {v, :integer} when is_integer(v) -> {:ok, v}
      {v, :float} when is_float(v) -> {:ok, v}
      {v, :boolean} when is_boolean(v) -> {:ok, v}
      {v, :any} -> {:ok, v}
      
      {v, {:list, inner_type}} when is_list(v) ->
        validate_list_items(v, inner_type)
      
      {v, :probability} when is_float(v) and v >= 0.0 and v <= 1.0 ->
        {:ok, v}
      
      {v, :confidence_score} when is_float(v) and v >= 0.0 and v <= 1.0 ->
        {:ok, v}
      
      {v, :embedding} when is_list(v) ->
        if Enum.all?(v, &is_float/1) do
          {:ok, v}
        else
          {:error, "Embedding must be a list of floats"}
        end
      
      {value, type} ->
        {:error, "Expected #{inspect(type)}, got #{inspect(value)}"}
    end
  end
  
  defp validate_list_items(list, inner_type) do
    case Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case validate_input(item, inner_type) do
        {:ok, validated_item} -> {:cont, {:ok, acc ++ [validated_item]}}
        error -> {:halt, error}
      end
    end) do
      {:ok, validated_list} -> {:ok, validated_list}
      error -> error
    end
  end
end
```

### ERROR HANDLING AND CONTEXT MANAGEMENT

**Comprehensive Error Handling:**
```elixir
defmodule DSPex.Adapters.ErrorHandler do
  @moduledoc """
  Standardized error handling for adapter operations.
  """
  
  defstruct [:type, :message, :context, :recoverable, :retry_after]
  
  @type adapter_error :: %__MODULE__{
    type: atom(),
    message: String.t(),
    context: map(),
    recoverable: boolean(),
    retry_after: pos_integer() | nil
  }
  
  def wrap_error(error, context \\ %{}) do
    case error do
      {:error, :timeout} ->
        %__MODULE__{
          type: :timeout,
          message: "Operation timed out",
          context: context,
          recoverable: true,
          retry_after: 5000
        }
      
      {:error, :connection_failed} ->
        %__MODULE__{
          type: :connection_failed,
          message: "Failed to connect to adapter backend",
          context: context,
          recoverable: true,
          retry_after: 10000
        }
      
      {:error, {:validation_failed, details}} ->
        %__MODULE__{
          type: :validation_failed,
          message: "Input validation failed: #{details}",
          context: context,
          recoverable: false,
          retry_after: nil
        }
      
      {:error, {:program_not_found, program_id}} ->
        %__MODULE__{
          type: :program_not_found,
          message: "Program not found: #{program_id}",
          context: Map.put(context, :program_id, program_id),
          recoverable: false,
          retry_after: nil
        }
      
      {:error, reason} when is_binary(reason) ->
        %__MODULE__{
          type: :unknown,
          message: reason,
          context: context,
          recoverable: false,
          retry_after: nil
        }
      
      other ->
        %__MODULE__{
          type: :unexpected,
          message: "Unexpected error: #{inspect(other)}",
          context: context,
          recoverable: false,
          retry_after: nil
        }
    end
  end
  
  def should_retry?(%__MODULE__{recoverable: recoverable}), do: recoverable
  
  def get_retry_delay(%__MODULE__{retry_after: delay}), do: delay
end
```

### MOCK ADAPTER FOR TESTING

**Complete Mock Implementation:**
```elixir
defmodule DSPex.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing and development.
  """
  
  @behaviour DSPex.Adapters.Adapter
  
  use GenServer
  
  defstruct programs: %{}, call_log: []
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def create_program(config) do
    GenServer.call(__MODULE__, {:create_program, config})
  end
  
  @impl true
  def execute_program(program_id, inputs) do
    GenServer.call(__MODULE__, {:execute_program, program_id, inputs})
  end
  
  @impl true
  def list_programs do
    GenServer.call(__MODULE__, :list_programs)
  end
  
  def get_call_log do
    GenServer.call(__MODULE__, :get_call_log)
  end
  
  def reset do
    GenServer.call(__MODULE__, :reset)
  end
  
  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end
  
  @impl true
  def handle_call({:create_program, config}, _from, state) do
    program_id = config.id
    new_programs = Map.put(state.programs, program_id, config)
    new_log = [{:create_program, config, DateTime.utc_now()} | state.call_log]
    
    new_state = %{state | programs: new_programs, call_log: new_log}
    {:reply, {:ok, program_id}, new_state}
  end
  
  def handle_call({:execute_program, program_id, inputs}, _from, state) do
    new_log = [{:execute_program, program_id, inputs, DateTime.utc_now()} | state.call_log]
    
    case Map.get(state.programs, program_id) do
      nil ->
        new_state = %{state | call_log: new_log}
        {:reply, {:error, "Program not found: #{program_id}"}, new_state}
      
      program_config ->
        # Generate mock response based on signature
        mock_outputs = generate_mock_outputs(program_config.signature)
        new_state = %{state | call_log: new_log}
        {:reply, {:ok, mock_outputs}, new_state}
    end
  end
  
  def handle_call(:list_programs, _from, state) do
    program_ids = Map.keys(state.programs)
    new_log = [{:list_programs, DateTime.utc_now()} | state.call_log]
    
    new_state = %{state | call_log: new_log}
    {:reply, {:ok, program_ids}, new_state}
  end
  
  def handle_call(:get_call_log, _from, state) do
    {:reply, Enum.reverse(state.call_log), state}
  end
  
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %__MODULE__{}}
  end
  
  defp generate_mock_outputs(signature_module) do
    signature = signature_module.__signature__()
    
    Enum.reduce(signature.outputs, %{}, fn {name, type, _constraints}, acc ->
      mock_value = generate_mock_value(type)
      Map.put(acc, name, mock_value)
    end)
  end
  
  defp generate_mock_value(:string), do: "mock_string_#{:rand.uniform(1000)}"
  defp generate_mock_value(:integer), do: :rand.uniform(100)
  defp generate_mock_value(:float), do: :rand.uniform() * 100
  defp generate_mock_value(:boolean), do: :rand.uniform(2) == 1
  defp generate_mock_value(:probability), do: :rand.uniform()
  defp generate_mock_value(:confidence_score), do: :rand.uniform()
  defp generate_mock_value({:list, inner_type}) do
    length = :rand.uniform(5)
    for _ <- 1..length, do: generate_mock_value(inner_type)
  end
  defp generate_mock_value(_), do: "mock_value"
end
```

### ADAPTER FACTORY AND MANAGER

**Factory Pattern Implementation:**
```elixir
defmodule DSPex.Adapters.Factory do
  @moduledoc """
  Factory for creating and managing adapter instances.
  """
  
  alias DSPex.Adapters.{Registry, ErrorHandler}
  
  def create_adapter(adapter_type, opts \\ []) do
    with {:ok, adapter_module} <- Registry.validate_adapter(adapter_type),
         {:ok, _} <- check_adapter_requirements(adapter_module, opts) do
      {:ok, adapter_module}
    else
      {:error, reason} -> {:error, ErrorHandler.wrap_error({:error, reason})}
    end
  end
  
  def execute_with_adapter(adapter, operation, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    execute_with_retry(adapter, operation, args, max_retries, timeout)
  end
  
  defp execute_with_retry(adapter, operation, args, retries_left, timeout) do
    case apply(adapter, operation, args) do
      {:ok, result} -> {:ok, result}
      {:error, error} ->
        wrapped_error = ErrorHandler.wrap_error(error)
        
        if retries_left > 0 and ErrorHandler.should_retry?(wrapped_error) do
          delay = ErrorHandler.get_retry_delay(wrapped_error) || 1000
          Process.sleep(delay)
          execute_with_retry(adapter, operation, args, retries_left - 1, timeout)
        else
          {:error, wrapped_error}
        end
    end
  end
  
  defp check_adapter_requirements(adapter_module, opts) do
    case adapter_module do
      DSPex.Adapters.PythonPort ->
        check_python_bridge_available()
      
      DSPex.Adapters.Mock ->
        ensure_mock_started(opts)
      
      _ ->
        {:ok, :no_requirements}
    end
  end
  
  defp check_python_bridge_available do
    case Process.whereis(DSPex.PythonBridge.Bridge) do
      nil -> {:error, "Python bridge not running"}
      _pid -> {:ok, :available}
    end
  end
  
  defp ensure_mock_started(opts) do
    case Process.whereis(DSPex.Adapters.Mock) do
      nil -> DSPex.Adapters.Mock.start_link(opts)
      _pid -> {:ok, :already_started}
    end
  end
end
```

### COMPREHENSIVE TESTING PATTERNS

**Adapter Behavior Testing:**
```elixir
defmodule DSPex.Adapters.BehaviorTest do
  use ExUnit.Case
  
  defmodule TestSignature do
    use DSPex.Signature
    
    signature question: :string -> answer: :string, confidence: :float
  end
  
  @adapters_to_test [
    DSPex.Adapters.Mock,
    # DSPex.Adapters.PythonPort  # Enable when bridge is available
  ]
  
  for adapter <- @adapters_to_test do
    describe "#{adapter} adapter behavior" do
      setup do
        if adapter == DSPex.Adapters.Mock do
          {:ok, _} = DSPex.Adapters.Mock.start_link()
          DSPex.Adapters.Mock.reset()
        end
        
        {:ok, adapter: adapter}
      end
      
      test "creates programs successfully", %{adapter: adapter} do
        config = %{
          id: "test_program",
          signature: TestSignature,
          modules: []
        }
        
        {:ok, program_id} = adapter.create_program(config)
        assert program_id == "test_program"
      end
      
      test "executes programs with valid inputs", %{adapter: adapter} do
        # Create program first
        config = %{
          id: "test_program",
          signature: TestSignature,
          modules: []
        }
        {:ok, _} = adapter.create_program(config)
        
        # Execute program
        inputs = %{question: "What is 2+2?"}
        {:ok, outputs} = adapter.execute_program("test_program", inputs)
        
        assert Map.has_key?(outputs, :answer) or Map.has_key?(outputs, "answer")
        assert Map.has_key?(outputs, :confidence) or Map.has_key?(outputs, "confidence")
      end
      
      test "returns error for non-existent program", %{adapter: adapter} do
        inputs = %{question: "test"}
        {:error, _reason} = adapter.execute_program("nonexistent", inputs)
      end
      
      test "lists programs correctly", %{adapter: adapter} do
        # Create a few programs
        for i <- 1..3 do
          config = %{
            id: "test_program_#{i}",
            signature: TestSignature,
            modules: []
          }
          {:ok, _} = adapter.create_program(config)
        end
        
        {:ok, programs} = adapter.list_programs()
        assert length(programs) >= 3
      end
    end
  end
  
  test "adapter factory creates correct adapters" do
    {:ok, adapter} = DSPex.Adapters.Factory.create_adapter(:mock)
    assert adapter == DSPex.Adapters.Mock
  end
  
  test "adapter factory validates unknown adapters" do
    {:error, _reason} = DSPex.Adapters.Factory.create_adapter(:unknown)
  end
  
  test "type converter handles basic types" do
    assert DSPex.Adapters.TypeConverter.convert_type(:string, :python) == "str"
    assert DSPex.Adapters.TypeConverter.convert_type(:integer, :python) == "int"
    assert DSPex.Adapters.TypeConverter.convert_type({:list, :string}, :python) == "List[str]"
  end
  
  test "type validator accepts valid inputs" do
    {:ok, "hello"} = DSPex.Adapters.TypeConverter.validate_input("hello", :string)
    {:ok, 42} = DSPex.Adapters.TypeConverter.validate_input(42, :integer)
    {:ok, [1, 2, 3]} = DSPex.Adapters.TypeConverter.validate_input([1, 2, 3], {:list, :integer})
  end
  
  test "type validator rejects invalid inputs" do
    {:error, _} = DSPex.Adapters.TypeConverter.validate_input(42, :string)
    {:error, _} = DSPex.Adapters.TypeConverter.validate_input("hello", :integer)
    {:error, _} = DSPex.Adapters.TypeConverter.validate_input([1, "two"], {:list, :integer})
  end
end
```

### INTEGRATION WITH ASH RESOURCE LIFECYCLE

**Resource Integration Patterns:**
```elixir
defmodule DSPex.ML.Program do
  # ... existing resource definition ...
  
  actions do
    # ... existing actions ...
    
    action :execute_with_adapter, :map do
      argument :inputs, :map, allow_nil?: false
      argument :adapter, :atom, default: nil
      argument :execution_options, :map, default: %{}
      
      run fn input, context ->
        program = context.resource
        adapter = DSPex.Adapters.Registry.get_adapter(input.arguments.adapter)
        
        case program.dspy_program_id do
          nil -> {:error, "Program not initialized"}
          program_id ->
            DSPex.Adapters.Factory.execute_with_adapter(
              adapter,
              :execute_program,
              [program_id, input.arguments.inputs],
              Map.to_list(input.arguments.execution_options)
            )
        end
      end
    end
    
    action :validate_with_adapter, :boolean do
      argument :adapter, :atom, default: nil
      
      run fn input, context ->
        program = context.resource
        adapter = DSPex.Adapters.Registry.get_adapter(input.arguments.adapter)
        signature_module = String.to_existing_atom(program.signature.module)
        
        case apply(adapter, :validate_signature, [signature_module]) do
          :ok -> {:ok, true}
          {:error, _reason} -> {:ok, false}
        end
      end
    end
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the adapter pattern system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/adapters/
├── adapter.ex             # Core behavior definition
├── python_port.ex         # Python bridge adapter
├── mock.ex               # Testing mock adapter
├── registry.ex           # Adapter selection and management
├── factory.ex            # Adapter creation and execution
├── type_converter.ex     # Type conversion system
├── error_handler.ex      # Error handling and context
└── supervisor.ex         # Adapter supervision

test/dspex/adapters/
├── behavior_test.exs     # Adapter behavior compliance tests
├── python_port_test.exs  # Python port adapter tests
├── mock_test.exs         # Mock adapter tests
├── registry_test.exs     # Registry functionality tests
└── type_converter_test.exs # Type conversion tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Adapter Behavior (`lib/dspex/adapters/adapter.ex`)**:
   - Define core behavior with comprehensive callbacks
   - Include proper typespecs for all operations
   - Document expected behavior and error patterns
   - Support extended operations for lifecycle management

2. **Python Port Adapter (`lib/dspex/adapters/python_port.ex`)**:
   - Complete implementation using Python bridge
   - Type conversion between Elixir and Python formats
   - Error handling with proper context
   - Performance optimization for common operations

3. **Mock Adapter (`lib/dspex/adapters/mock.ex`)**:
   - Full GenServer implementation for testing
   - Mock data generation based on signatures
   - Call logging for test verification
   - Configurable behavior for error testing

4. **Registry System (`lib/dspex/adapters/registry.ex`)**:
   - Configuration-driven adapter selection
   - Adapter validation and capability checking
   - Dynamic adapter loading and management
   - Environment-specific adapter selection

5. **Type Conversion (`lib/dspex/adapters/type_converter.ex`)**:
   - Comprehensive type mapping system
   - Validation for all supported types
   - Support for composite and ML-specific types
   - Target format support (Python, JSON Schema, etc.)

### QUALITY REQUIREMENTS:

- **Consistency**: All adapters must provide identical interfaces
- **Reliability**: Robust error handling with clear error contexts
- **Performance**: Efficient type conversion and minimal overhead
- **Testability**: Comprehensive mock support for testing
- **Extensibility**: Easy addition of new adapter implementations
- **Documentation**: Clear documentation for all public APIs
- **Configuration**: Flexible configuration for different environments

### INTEGRATION POINTS:

- Must integrate with Python bridge communication layer
- Should support Ash resource action execution
- Must provide consistent error handling across adapters
- Should support configuration-driven adapter selection
- Must enable seamless switching between implementations

### SUCCESS CRITERIA:

1. All adapters implement the behavior consistently
2. Type conversion handles all signature types correctly
3. Error handling provides meaningful context and recovery options
4. Mock adapter supports comprehensive testing scenarios
5. Registry enables flexible adapter selection
6. Integration with Ash resources works seamlessly
7. Performance meets requirements for ML workloads
8. All test scenarios pass with comprehensive coverage

This adapter pattern provides the crucial abstraction layer that enables the DSPy-Ash integration to work with multiple backend implementations while maintaining a consistent interface.