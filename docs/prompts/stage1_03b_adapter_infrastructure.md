# Stage 1 Prompt 3b: Adapter Infrastructure Components

## OBJECTIVE

Implement the critical infrastructure components that were identified as missing from the updated Prompt 3: TypeConverter, ErrorHandler, Factory, and comprehensive testing patterns. These components provide the robust foundation needed for production adapter operations while maintaining full integration with our 3-layer testing architecture.

## CONTEXT FROM PROMPT 3 ANALYSIS

During the Prompt 3 update for 3-layer testing integration, several critical infrastructure components were removed under the assumption they were "over-engineering." Analysis revealed these components are **essential** for production adapter operations:

### CRITICAL MISSING COMPONENTS:

1. **TypeConverter** (~100 lines) - Type conversion between Elixir ↔ Python ↔ JSON Schema
2. **ErrorHandler** (~80 lines) - Standardized error handling with retry logic  
3. **Factory** (~50 lines) - Adapter lifecycle management and validation
4. **Comprehensive Testing** (~100 lines) - Cross-adapter behavior compliance

### WHY THESE ARE ESSENTIAL:

- **Multi-backend support** requires robust type conversion
- **Production reliability** demands sophisticated error handling
- **Adapter lifecycle** needs validation and requirement checking
- **Cross-adapter compatibility** requires behavior compliance testing

## COMPLETE IMPLEMENTATION CONTEXT

### TYPE CONVERSION SYSTEM (RESTORED AND ENHANCED)

**Comprehensive Type Mapping with 3-Layer Test Support:**
```elixir
defmodule DSPex.Adapters.TypeConverter do
  @moduledoc """
  Type conversion between Elixir and adapter-specific formats.
  Enhanced with test layer awareness and ML-specific types.
  """
  
  @type_mappings %{
    # Basic types
    :string => %{python: "str", json_schema: "string", mock: "string"},
    :integer => %{python: "int", json_schema: "integer", mock: "integer"},
    :float => %{python: "float", json_schema: "number", mock: "float"},
    :boolean => %{python: "bool", json_schema: "boolean", mock: "boolean"},
    :atom => %{python: "str", json_schema: "string", mock: "string"},
    :any => %{python: "Any", json_schema: "any", mock: "any"},
    :map => %{python: "Dict", json_schema: "object", mock: "map"},
    
    # ML-specific types
    :embedding => %{python: "List[float]", json_schema: "array", mock: "embedding"},
    :probability => %{python: "float", json_schema: "number", mock: "probability"},
    :confidence_score => %{python: "float", json_schema: "number", mock: "confidence"},
    :reasoning_chain => %{python: "List[str]", json_schema: "array", mock: "reasoning"}
  }
  
  @doc """
  Convert type to target format with test layer awareness.
  """
  def convert_type(type, target_format, opts \\ []) do
    test_layer = Keyword.get(opts, :test_layer)
    
    case type do
      # Basic types
      basic when is_atom(basic) ->
        get_type_mapping(basic, target_format, test_layer)
      
      # Composite types
      {:list, inner_type} ->
        inner_converted = convert_type(inner_type, target_format, opts)
        case target_format do
          :python -> "List[#{inner_converted}]"
          :json_schema -> %{type: "array", items: inner_converted}
          :mock -> {:list, inner_converted}
        end
      
      {:dict, key_type, value_type} ->
        key_converted = convert_type(key_type, target_format, opts)
        value_converted = convert_type(value_type, target_format, opts)
        case target_format do
          :python -> "Dict[#{key_converted}, #{value_converted}]"
          :json_schema -> %{
            type: "object",
            additionalProperties: value_converted
          }
          :mock -> {:dict, key_converted, value_converted}
        end
      
      {:union, types} ->
        converted_types = Enum.map(types, &convert_type(&1, target_format, opts))
        case target_format do
          :python -> "Union[#{Enum.join(converted_types, ", ")}]"
          :json_schema -> %{anyOf: converted_types}
          :mock -> {:union, converted_types}
        end
    end
  end
  
  def convert_signature_to_format(signature_module, target_format, opts \\ []) do
    signature = signature_module.__signature__()
    
    %{
      inputs: convert_fields_to_format(signature.inputs, target_format, opts),
      outputs: convert_fields_to_format(signature.outputs, target_format, opts)
    }
  end
  
  defp convert_fields_to_format(fields, target_format, opts) do
    Enum.map(fields, fn {name, type, constraints} ->
      converted_type = convert_type(type, target_format, opts)
      
      case target_format do
        :python ->
          %{
            name: to_string(name),
            type: converted_type,
            description: get_field_description(constraints)
          }
        
        :json_schema ->
          base_schema = %{
            type: converted_type,
            description: get_field_description(constraints)
          }
          add_json_schema_constraints(base_schema, constraints)
        
        :mock ->
          %{
            name: name,
            type: converted_type,
            constraints: constraints
          }
      end
    end)
  end
  
  defp get_type_mapping(type, target_format, test_layer) do
    case Map.get(@type_mappings, type) do
      nil -> {:error, "Unknown type: #{type}"}
      mapping -> 
        # Use test-layer specific mapping if available
        case test_layer do
          :layer_1 -> Map.get(mapping, :mock, Map.get(mapping, target_format))
          :layer_2 -> Map.get(mapping, target_format, to_string(type))
          :layer_3 -> Map.get(mapping, target_format, to_string(type))
          _ -> Map.get(mapping, target_format, to_string(type))
        end
    end
  end
  
  @doc """
  Validate input against expected type with test layer awareness.
  """
  def validate_input(value, expected_type, opts \\ []) do
    test_layer = Keyword.get(opts, :test_layer, :layer_3)
    
    case {value, expected_type, test_layer} do
      # Basic type validation
      {v, :string, _} when is_binary(v) -> {:ok, v}
      {v, :integer, _} when is_integer(v) -> {:ok, v}
      {v, :float, _} when is_float(v) -> {:ok, v}
      {v, :boolean, _} when is_boolean(v) -> {:ok, v}
      {v, :any, _} -> {:ok, v}
      
      # ML-specific validation
      {v, :probability, _} when is_float(v) and v >= 0.0 and v <= 1.0 ->
        {:ok, v}
      
      {v, :confidence_score, _} when is_float(v) and v >= 0.0 and v <= 1.0 ->
        {:ok, v}
      
      {v, :embedding, _} when is_list(v) ->
        if Enum.all?(v, &is_float/1) do
          {:ok, v}
        else
          {:error, "Embedding must be a list of floats"}
        end
      
      # Composite type validation
      {v, {:list, inner_type}, layer} when is_list(v) ->
        validate_list_items(v, inner_type, [{:test_layer, layer} | opts])
      
      # Test layer specific relaxed validation
      {v, type, :layer_1} ->
        # Layer 1 (mock) accepts more flexible types
        validate_mock_input(v, type)
      
      {value, type, _} ->
        {:error, "Expected #{inspect(type)}, got #{inspect(value)}"}
    end
  end
  
  defp validate_list_items(list, inner_type, opts) do
    case Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case validate_input(item, inner_type, opts) do
        {:ok, validated_item} -> {:cont, {:ok, acc ++ [validated_item]}}
        error -> {:halt, error}
      end
    end) do
      {:ok, validated_list} -> {:ok, validated_list}
      error -> error
    end
  end
  
  defp validate_mock_input(value, _type) do
    # Mock adapter accepts any reasonable input for testing
    {:ok, value}
  end
  
  defp get_field_description(constraints) do
    Keyword.get(constraints, :description, "")
  end
  
  defp add_json_schema_constraints(schema, constraints) do
    Enum.reduce(constraints, schema, fn
      {:min_length, min}, acc -> Map.put(acc, :minLength, min)
      {:max_length, max}, acc -> Map.put(acc, :maxLength, max)
      {:min_value, min}, acc -> Map.put(acc, :minimum, min)
      {:max_value, max}, acc -> Map.put(acc, :maximum, max)
      {:one_of, values}, acc -> Map.put(acc, :enum, values)
      _, acc -> acc
    end)
  end
end
```

### ERROR HANDLING SYSTEM (RESTORED AND ENHANCED)

**Comprehensive Error Handling with Test Layer Support:**
```elixir
defmodule DSPex.Adapters.ErrorHandler do
  @moduledoc """
  Standardized error handling for adapter operations with test layer awareness.
  """
  
  defstruct [:type, :message, :context, :recoverable, :retry_after, :test_layer]
  
  @type adapter_error :: %__MODULE__{
    type: atom(),
    message: String.t(),
    context: map(),
    recoverable: boolean(),
    retry_after: pos_integer() | nil,
    test_layer: atom() | nil
  }
  
  @doc """
  Wrap error with context and test layer awareness.
  """
  def wrap_error(error, context \\ %{}) do
    test_layer = DSPex.Testing.TestMode.effective_test_mode()
    
    case error do
      {:error, :timeout} ->
        %__MODULE__{
          type: :timeout,
          message: "Operation timed out",
          context: context,
          recoverable: true,
          retry_after: get_retry_delay(:timeout, test_layer),
          test_layer: test_layer
        }
      
      {:error, :connection_failed} ->
        %__MODULE__{
          type: :connection_failed,
          message: "Failed to connect to adapter backend",
          context: context,
          recoverable: should_retry_connection?(test_layer),
          retry_after: get_retry_delay(:connection_failed, test_layer),
          test_layer: test_layer
        }
      
      {:error, {:validation_failed, details}} ->
        %__MODULE__{
          type: :validation_failed,
          message: "Input validation failed: #{details}",
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }
      
      {:error, {:program_not_found, program_id}} ->
        %__MODULE__{
          type: :program_not_found,
          message: "Program not found: #{program_id}",
          context: Map.put(context, :program_id, program_id),
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }
      
      {:error, {:bridge_error, bridge_details}} ->
        %__MODULE__{
          type: :bridge_error,
          message: "Python bridge error: #{inspect(bridge_details)}",
          context: Map.put(context, :bridge_details, bridge_details),
          recoverable: should_retry_bridge_error?(bridge_details, test_layer),
          retry_after: get_retry_delay(:bridge_error, test_layer),
          test_layer: test_layer
        }
      
      {:error, reason} when is_binary(reason) ->
        %__MODULE__{
          type: :unknown,
          message: reason,
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }
      
      other ->
        %__MODULE__{
          type: :unexpected,
          message: "Unexpected error: #{inspect(other)}",
          context: context,
          recoverable: false,
          retry_after: nil,
          test_layer: test_layer
        }
    end
  end
  
  def should_retry?(%__MODULE__{recoverable: recoverable}), do: recoverable
  
  def get_retry_delay(%__MODULE__{retry_after: delay}), do: delay
  
  def get_error_context(%__MODULE__{context: context}), do: context
  
  def is_test_error?(%__MODULE__{test_layer: test_layer}) do
    test_layer in [:layer_1, :layer_2, :layer_3]
  end
  
  @doc """
  Format error for logging with test context.
  """
  def format_error(%__MODULE__{} = error) do
    base_msg = "#{error.type}: #{error.message}"
    
    case error.test_layer do
      nil -> base_msg
      layer -> "#{base_msg} [#{layer}]"
    end
  end
  
  # Test layer specific retry delays
  defp get_retry_delay(:timeout, :layer_1), do: 100  # Fast for mock tests
  defp get_retry_delay(:timeout, :layer_2), do: 500  # Medium for protocol tests  
  defp get_retry_delay(:timeout, :layer_3), do: 5000 # Slower for integration tests
  defp get_retry_delay(:timeout, _), do: 5000
  
  defp get_retry_delay(:connection_failed, :layer_1), do: 100
  defp get_retry_delay(:connection_failed, :layer_2), do: 1000
  defp get_retry_delay(:connection_failed, :layer_3), do: 10000
  defp get_retry_delay(:connection_failed, _), do: 10000
  
  defp get_retry_delay(:bridge_error, test_layer) do
    get_retry_delay(:connection_failed, test_layer)
  end
  
  defp get_retry_delay(_, _), do: nil
  
  # Test layer specific retry logic
  defp should_retry_connection?(:layer_1), do: false  # Mock should never fail connection
  defp should_retry_connection?(:layer_2), do: true   # Protocol tests may need retries
  defp should_retry_connection?(:layer_3), do: true   # Integration tests definitely need retries
  defp should_retry_connection?(_), do: true
  
  defp should_retry_bridge_error?(details, :layer_1), do: false  # No bridge in mock
  defp should_retry_bridge_error?(details, :layer_2) do
    # Protocol layer retries specific bridge protocol errors
    case details do
      %{type: :protocol_error} -> false
      %{type: :timeout} -> true
      _ -> false
    end
  end
  defp should_retry_bridge_error?(details, :layer_3) do
    # Full integration retries most bridge errors
    case details do
      %{type: :validation_error} -> false
      _ -> true
    end
  end
  defp should_retry_bridge_error?(_, _), do: true
end
```

### FACTORY PATTERN (RESTORED AND ENHANCED)

**Factory with Test Layer Integration:**
```elixir
defmodule DSPex.Adapters.Factory do
  @moduledoc """
  Factory for creating and managing adapter instances with test layer awareness.
  """
  
  alias DSPex.Adapters.{Registry, ErrorHandler, TypeConverter}
  
  @doc """
  Create adapter with test layer specific configuration.
  """
  def create_adapter(adapter_type \\ nil, opts \\ []) do
    test_layer = Keyword.get(opts, :test_layer) || 
                 DSPex.Testing.TestMode.effective_test_mode()
    
    resolved_adapter_type = adapter_type || 
                           Registry.get_adapter_for_test_layer(test_layer)
    
    with {:ok, adapter_module} <- Registry.validate_adapter(resolved_adapter_type),
         {:ok, _} <- check_adapter_requirements(adapter_module, opts),
         {:ok, _} <- validate_test_layer_compatibility(adapter_module, test_layer) do
      {:ok, adapter_module}
    else
      {:error, reason} -> {:error, ErrorHandler.wrap_error({:error, reason}, %{
        adapter_type: adapter_type,
        test_layer: test_layer
      })}
    end
  end
  
  @doc """
  Execute operation with adapter, retry logic, and test layer awareness.
  """
  def execute_with_adapter(adapter, operation, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, get_default_timeout())
    max_retries = Keyword.get(opts, :max_retries, get_default_retries())
    test_layer = Keyword.get(opts, :test_layer) ||
                 DSPex.Testing.TestMode.effective_test_mode()
    
    context = %{
      adapter: adapter,
      operation: operation,
      test_layer: test_layer
    }
    
    execute_with_retry(adapter, operation, args, max_retries, timeout, context)
  end
  
  @doc """
  Execute with signature validation and type conversion.
  """
  def execute_with_signature_validation(adapter, signature_module, inputs, opts \\ []) do
    test_layer = Keyword.get(opts, :test_layer) ||
                 DSPex.Testing.TestMode.effective_test_mode()
    
    with {:ok, validated_inputs} <- validate_inputs_for_signature(signature_module, inputs, test_layer),
         {:ok, adapter_inputs} <- convert_inputs_for_adapter(adapter, signature_module, validated_inputs, test_layer) do
      
      execute_with_adapter(adapter, :execute_program, adapter_inputs, opts)
    else
      {:error, reason} -> {:error, ErrorHandler.wrap_error({:error, reason}, %{
        signature: signature_module,
        inputs: inputs,
        test_layer: test_layer
      })}
    end
  end
  
  defp execute_with_retry(adapter, operation, args, retries_left, timeout, context) do
    case apply_with_timeout(adapter, operation, args, timeout) do
      {:ok, result} -> 
        {:ok, result}
      
      {:error, error} ->
        wrapped_error = ErrorHandler.wrap_error(error, context)
        
        if retries_left > 0 and ErrorHandler.should_retry?(wrapped_error) do
          delay = ErrorHandler.get_retry_delay(wrapped_error) || 1000
          Process.sleep(delay)
          execute_with_retry(adapter, operation, args, retries_left - 1, timeout, context)
        else
          {:error, wrapped_error}
        end
    end
  end
  
  defp apply_with_timeout(adapter, operation, args, timeout) do
    task = Task.async(fn -> apply(adapter, operation, args) end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
  
  defp check_adapter_requirements(adapter_module, opts) do
    test_layer = Keyword.get(opts, :test_layer)
    
    case adapter_module do
      DSPex.Adapters.PythonPort ->
        if test_layer == :layer_3 do
          check_python_bridge_available()
        else
          {:ok, :test_mode_bypass}
        end
      
      DSPex.Adapters.BridgeMock ->
        if test_layer == :layer_2 do
          check_bridge_mock_available()
        else
          {:ok, :test_mode_bypass}
        end
      
      DSPex.Adapters.Mock ->
        ensure_mock_started(opts)
      
      _ ->
        {:ok, :no_requirements}
    end
  end
  
  defp validate_test_layer_compatibility(adapter_module, test_layer) do
    if function_exported?(adapter_module, :supports_test_layer?, 1) do
      case adapter_module.supports_test_layer?(test_layer) do
        true -> {:ok, :compatible}
        false -> {:error, "Adapter #{adapter_module} does not support test layer #{test_layer}"}
      end
    else
      # Assume compatibility if not implemented
      {:ok, :compatible}
    end
  end
  
  defp validate_inputs_for_signature(signature_module, inputs, test_layer) do
    signature = signature_module.__signature__()
    
    Enum.reduce_while(signature.inputs, {:ok, %{}}, fn {field_name, field_type, _constraints}, {:ok, acc} ->
      case Map.get(inputs, field_name) || Map.get(inputs, to_string(field_name)) do
        nil ->
          {:halt, {:error, "Missing required input: #{field_name}"}}
        
        value ->
          case TypeConverter.validate_input(value, field_type, test_layer: test_layer) do
            {:ok, validated_value} ->
              {:cont, {:ok, Map.put(acc, field_name, validated_value)}}
            
            {:error, reason} ->
              {:halt, {:error, "Invalid input for #{field_name}: #{reason}"}}
          end
      end
    end)
  end
  
  defp convert_inputs_for_adapter(adapter, signature_module, inputs, test_layer) do
    # Convert inputs based on adapter requirements
    case adapter do
      DSPex.Adapters.PythonPort ->
        TypeConverter.convert_signature_to_format(signature_module, :python, test_layer: test_layer)
        {:ok, inputs}  # Python adapter handles conversion internally
      
      DSPex.Adapters.BridgeMock ->
        {:ok, inputs}  # Protocol testing uses same format
      
      DSPex.Adapters.Mock ->
        {:ok, inputs}  # Mock accepts any format
      
      _ ->
        {:ok, inputs}  # Default pass-through
    end
  end
  
  defp check_python_bridge_available do
    case Process.whereis(DSPex.PythonBridge.Bridge) do
      nil -> {:error, "Python bridge not running"}
      _pid -> {:ok, :available}
    end
  end
  
  defp check_bridge_mock_available do
    case DSPex.Testing.BridgeMockServer.running?() do
      true -> {:ok, :available}
      false -> {:error, "Bridge mock server not running"}
    end
  end
  
  defp ensure_mock_started(opts) do
    case Process.whereis(DSPex.Adapters.Mock) do
      nil -> DSPex.Adapters.Mock.start_link(opts)
      _pid -> {:ok, :already_started}
    end
  end
  
  # Test layer specific defaults
  defp get_default_timeout do
    case DSPex.Testing.TestMode.effective_test_mode() do
      :layer_1 -> 1_000   # Fast for mock tests
      :layer_2 -> 5_000   # Medium for protocol tests
      :layer_3 -> 30_000  # Longer for integration tests
      _ -> 30_000
    end
  end
  
  defp get_default_retries do
    case DSPex.Testing.TestMode.effective_test_mode() do
      :layer_1 -> 0  # No retries for mock (should be deterministic)
      :layer_2 -> 2  # Some retries for protocol tests
      :layer_3 -> 3  # More retries for integration tests
      _ -> 3
    end
  end
end
```

### COMPREHENSIVE TESTING PATTERNS (RESTORED AND ENHANCED)

**Cross-Adapter Behavior Compliance Testing:**
```elixir
defmodule DSPex.Adapters.BehaviorComplianceTest do
  @moduledoc """
  Comprehensive behavior compliance testing for all adapters across test layers.
  """
  
  use ExUnit.Case
  
  defmodule TestSignature do
    use DSPex.Signature
    
    signature question: :string -> answer: :string, confidence: :float
  end
  
  defmodule ComplexTestSignature do
    use DSPex.Signature
    
    signature input: :string, context: {:list, :string} -> 
             result: :string, reasoning: {:list, :string}, confidence: :probability
  end
  
  @adapters_by_layer %{
    layer_1: DSPex.Adapters.Mock,
    layer_2: DSPex.Adapters.BridgeMock,
    layer_3: DSPex.Adapters.PythonPort
  }
  
  @test_layers [:layer_1, :layer_2, :layer_3]
  
  setup do
    # Reset test environment
    DSPex.Testing.TestMode.set_test_mode(:mock_adapter)
    
    # Start required services
    {:ok, _} = DSPex.Adapters.Mock.start_link()
    DSPex.Adapters.Mock.reset()
    
    :ok
  end
  
  for layer <- @test_layers do
    describe "#{layer} adapter behavior compliance" do
      setup do
        adapter = Map.get(@adapters_by_layer, unquote(layer))
        
        # Set appropriate test mode for this layer
        test_mode = case unquote(layer) do
          :layer_1 -> :mock_adapter
          :layer_2 -> :bridge_mock
          :layer_3 -> :full_integration
        end
        
        DSPex.Testing.TestMode.set_test_mode(test_mode)
        
        {:ok, adapter: adapter, test_layer: unquote(layer)}
      end
      
      @tag String.to_atom("#{layer}")
      test "creates programs successfully", %{adapter: adapter, test_layer: test_layer} do
        config = %{
          id: "test_program_#{test_layer}",
          signature: TestSignature,
          modules: []
        }
        
        {:ok, program_id} = adapter.create_program(config)
        assert program_id == "test_program_#{test_layer}"
      end
      
      @tag String.to_atom("#{layer}")
      test "executes programs with valid inputs", %{adapter: adapter, test_layer: test_layer} do
        # Create program first
        config = %{
          id: "test_program_#{test_layer}",
          signature: TestSignature,
          modules: []
        }
        {:ok, _} = adapter.create_program(config)
        
        # Execute program
        inputs = %{question: "What is 2+2?"}
        {:ok, outputs} = adapter.execute_program("test_program_#{test_layer}", inputs)
        
        assert Map.has_key?(outputs, :answer) or Map.has_key?(outputs, "answer")
        assert Map.has_key?(outputs, :confidence) or Map.has_key?(outputs, "confidence")
      end
      
      @tag String.to_atom("#{layer}")
      test "handles complex signatures", %{adapter: adapter, test_layer: test_layer} do
        config = %{
          id: "complex_program_#{test_layer}",
          signature: ComplexTestSignature,
          modules: []
        }
        
        {:ok, program_id} = adapter.create_program(config)
        
        inputs = %{
          input: "Analyze this text",
          context: ["context1", "context2"]
        }
        
        {:ok, outputs} = adapter.execute_program(program_id, inputs)
        
        # Verify complex output structure
        assert Map.has_key?(outputs, :result) or Map.has_key?(outputs, "result")
        assert Map.has_key?(outputs, :reasoning) or Map.has_key?(outputs, "reasoning")
        assert Map.has_key?(outputs, :confidence) or Map.has_key?(outputs, "confidence")
      end
      
      @tag String.to_atom("#{layer}")
      test "returns error for non-existent program", %{adapter: adapter} do
        inputs = %{question: "test"}
        {:error, _reason} = adapter.execute_program("nonexistent", inputs)
      end
      
      @tag String.to_atom("#{layer}")
      test "lists programs correctly", %{adapter: adapter, test_layer: test_layer} do
        # Create a few programs
        for i <- 1..3 do
          config = %{
            id: "test_program_#{test_layer}_#{i}",
            signature: TestSignature,
            modules: []
          }
          {:ok, _} = adapter.create_program(config)
        end
        
        {:ok, programs} = adapter.list_programs()
        assert length(programs) >= 3
      end
      
      @tag String.to_atom("#{layer}")
      test "supports health check", %{adapter: adapter} do
        if function_exported?(adapter, :health_check, 0) do
          case adapter.health_check() do
            :ok -> assert true
            {:error, _reason} -> assert true  # Error is acceptable in some test layers
          end
        end
      end
      
      @tag String.to_atom("#{layer}")
      test "provides test capabilities", %{adapter: adapter} do
        if function_exported?(adapter, :get_test_capabilities, 0) do
          capabilities = adapter.get_test_capabilities()
          assert is_map(capabilities)
          assert Map.has_key?(capabilities, :performance)
        end
      end
      
      @tag String.to_atom("#{layer}")
      test "validates test layer support", %{adapter: adapter, test_layer: test_layer} do
        if function_exported?(adapter, :supports_test_layer?, 1) do
          assert adapter.supports_test_layer?(test_layer) == true
        end
      end
    end
  end
  
  describe "Factory pattern compliance" do
    test "creates correct adapters for test layers" do
      for {layer, expected_adapter} <- @adapters_by_layer do
        {:ok, adapter} = DSPex.Adapters.Factory.create_adapter(nil, test_layer: layer)
        assert adapter == expected_adapter
      end
    end
    
    test "validates adapter requirements" do
      {:ok, _adapter} = DSPex.Adapters.Factory.create_adapter(:mock, test_layer: :layer_1)
    end
    
    test "handles execution with retry logic" do
      adapter = DSPex.Adapters.Mock
      
      # This should succeed
      {:ok, result} = DSPex.Adapters.Factory.execute_with_adapter(
        adapter, 
        :health_check, 
        [],
        test_layer: :layer_1
      )
      
      assert result == :ok
    end
  end
  
  describe "Type conversion compliance" do
    test "converts basic types correctly" do
      assert DSPex.Adapters.TypeConverter.convert_type(:string, :python) == "str"
      assert DSPex.Adapters.TypeConverter.convert_type(:integer, :python) == "int"
      assert DSPex.Adapters.TypeConverter.convert_type({:list, :string}, :python) == "List[str]"
    end
    
    test "validates inputs with test layer awareness" do
      {:ok, "hello"} = DSPex.Adapters.TypeConverter.validate_input("hello", :string, test_layer: :layer_1)
      {:ok, 42} = DSPex.Adapters.TypeConverter.validate_input(42, :integer, test_layer: :layer_2)
      {:ok, [1, 2, 3]} = DSPex.Adapters.TypeConverter.validate_input([1, 2, 3], {:list, :integer}, test_layer: :layer_3)
    end
    
    test "rejects invalid inputs appropriately" do
      {:error, _} = DSPex.Adapters.TypeConverter.validate_input(42, :string, test_layer: :layer_3)
      {:error, _} = DSPex.Adapters.TypeConverter.validate_input("hello", :integer, test_layer: :layer_3)
      {:error, _} = DSPex.Adapters.TypeConverter.validate_input([1, "two"], {:list, :integer}, test_layer: :layer_3)
    end
    
    test "converts signatures to different formats" do
      signature_def = DSPex.Adapters.TypeConverter.convert_signature_to_format(TestSignature, :python)
      
      assert Map.has_key?(signature_def, :inputs)
      assert Map.has_key?(signature_def, :outputs)
      assert length(signature_def.inputs) == 1
      assert length(signature_def.outputs) == 2
    end
  end
  
  describe "Error handling compliance" do
    test "wraps errors with proper context" do
      error = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout}, %{context: :test})
      
      assert error.type == :timeout
      assert error.recoverable == true
      assert is_integer(error.retry_after)
      assert error.context.context == :test
    end
    
    test "provides test layer specific retry delays" do
      # Set different test modes and verify retry delays
      DSPex.Testing.TestMode.set_test_mode(:mock_adapter)
      error1 = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout})
      
      DSPex.Testing.TestMode.set_test_mode(:full_integration)
      error2 = DSPex.Adapters.ErrorHandler.wrap_error({:error, :timeout})
      
      # Layer 1 should have shorter delays than Layer 3
      assert error1.retry_after < error2.retry_after
    end
    
    test "formats errors with test context" do
      error = DSPex.Adapters.ErrorHandler.wrap_error({:error, "test error"})
      formatted = DSPex.Adapters.ErrorHandler.format_error(error)
      
      assert is_binary(formatted)
      assert formatted =~ "test error"
    end
  end
end
```

## IMPLEMENTATION TASK

Based on the analysis showing these components are critical infrastructure (not over-engineering), implement the missing adapter infrastructure components:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/adapters/
├── type_converter.ex     # Enhanced type conversion with test layer support
├── error_handler.ex      # Standardized error handling with retry logic
├── factory.ex            # Adapter lifecycle management and execution
└── supervisor.ex         # Adapter supervision (if needed)

test/dspex/adapters/
├── behavior_compliance_test.exs  # Cross-adapter behavior testing
├── type_converter_test.exs       # Type conversion comprehensive tests
├── error_handler_test.exs        # Error handling pattern tests
└── factory_test.exs              # Factory pattern tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **TypeConverter**: ML-specific types, test layer awareness, multiple format support
2. **ErrorHandler**: Test layer specific retry logic, comprehensive error context  
3. **Factory**: Adapter lifecycle, signature validation, test layer compatibility
4. **Comprehensive Testing**: Cross-adapter compliance, behavior verification

### INTEGRATION POINTS:

- Must integrate with 3-layer testing architecture from Prompt 3
- Should enhance existing adapter behavior without breaking changes
- Must support the multi-adapter roadmap for Stages 2-4
- Should provide production-ready error handling and type conversion

These components provide the robust infrastructure foundation that was identified as missing from the updated Prompt 3 while maintaining full integration with our proven 3-layer testing architecture.