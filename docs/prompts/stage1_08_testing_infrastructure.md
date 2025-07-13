# Stage 1 Prompt 8: Basic Testing Infrastructure

## OBJECTIVE

Implement a comprehensive testing infrastructure that ensures reliability, performance, and correctness of the DSPy-Ash integration across all components. This includes unit tests, integration tests, property-based testing, performance benchmarks, mock systems, and automated test suites that validate signature compilation, adapter functionality, type validation, and end-to-end workflows.

## COMPLETE IMPLEMENTATION CONTEXT

### TESTING ARCHITECTURE OVERVIEW

From Elixir testing best practices and Stage 1 implementation requirements:

```
┌─────────────────────────────────────────────────────────────┐
│                Testing Infrastructure Architecture          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Unit Tests      │  │ Integration     │  │ Property     ││
│  │ - Signature     │  │ Tests           │  │ Based Tests  ││
│  │ - Type system   │  │ - End-to-end    │  │ - Generators ││
│  │ - Validation    │  │ - Cross-system  │  │ - Invariants ││
│  │ - Adapters      │  │ - Workflows     │  │ - Edge cases ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Performance     │  │ Mock Systems    │  │ Test Data    ││
│  │ Tests           │  │ - Adapters      │  │ Generation   ││
│  │ - Benchmarks    │  │ - Bridge        │  │ - Signatures ││
│  │ - Load testing  │  │ - External APIs │  │ - Fixtures   ││
│  │ - Memory usage  │  │ - Databases     │  │ - Factories  ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### ELIXIR TESTING PATTERNS

From Elixir testing best practices:

**ExUnit Framework Usage:**
```elixir
defmodule MyModuleTest do
  use ExUnit.Case
  
  # Async tests for independent tests
  use ExUnit.Case, async: true
  
  # Setup and teardown
  setup do
    # Per-test setup
    {:ok, context}
  end
  
  setup_all do
    # One-time setup for all tests
    {:ok, global_context}
  end
  
  # Test patterns
  test "descriptive test name", context do
    # Test implementation
  end
  
  describe "group of related tests" do
    test "specific functionality" do
      # Test implementation
    end
  end
end
```

### COMPREHENSIVE TEST SUITE FOUNDATION

**Core Testing Framework Setup:**
```elixir
defmodule AshDSPy.TestSupport do
  @moduledoc """
  Shared testing utilities and helpers for the DSPy-Ash integration test suite.
  Provides factories, fixtures, mocks, and common test patterns.
  """
  
  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, unquote(opts)
      
      import AshDSPy.TestSupport.{
        Factories,
        Fixtures,
        Assertions,
        Helpers
      }
      
      alias AshDSPy.TestSupport.{MockAdapter, TestSignatures}
      
      # Common setup for DSPy tests
      setup do
        # Reset global state
        AshDSPy.TestSupport.reset_test_state()
        
        # Start necessary services
        start_test_services()
        
        {:ok, %{}}
      end
    end
  end
  
  def reset_test_state do
    # Reset any global state between tests
    if Process.whereis(AshDSPy.Adapters.Mock) do
      AshDSPy.Adapters.Mock.reset()
    end
    
    # Clear ETS tables used for caching
    :ets.delete_all_objects(:type_validation_cache)
    :ets.delete_all_objects(:type_serialization_cache)
  rescue
    # Tables might not exist yet
    _ -> :ok
  end
  
  defp start_test_services do
    # Start mock adapter if not running
    case Process.whereis(AshDSPy.Adapters.Mock) do
      nil -> 
        {:ok, _} = AshDSPy.Adapters.Mock.start_link()
      _ -> 
        :ok
    end
    
    # Start other test services as needed
    :ok
  end
end
```

### SIGNATURE SYSTEM TESTING

**Comprehensive Signature Testing:**
```elixir
defmodule AshDSPy.Signature.CompilerTest do
  use AshDSPy.TestSupport, async: true
  
  describe "signature compilation" do
    test "compiles basic signatures correctly" do
      defmodule BasicSignature do
        use AshDSPy.Signature
        
        signature question: :string -> answer: :string
      end
      
      signature = BasicSignature.__signature__()
      
      assert signature.inputs == [{:question, :string, []}]
      assert signature.outputs == [{:answer, :string, []}]
      assert signature.module == BasicSignature
    end
    
    test "compiles complex signatures with multiple fields" do
      defmodule ComplexSignature do
        use AshDSPy.Signature
        
        signature query: :string, context: {:list, :string}, max_tokens: :integer ->
                 answer: :string, confidence: :probability, reasoning: :reasoning_chain
      end
      
      signature = ComplexSignature.__signature__()
      
      assert length(signature.inputs) == 3
      assert length(signature.outputs) == 3
      
      # Verify field types
      input_types = Enum.map(signature.inputs, fn {_name, type, _constraints} -> type end)
      assert :string in input_types
      assert {:list, :string} in input_types
      assert :integer in input_types
      
      output_types = Enum.map(signature.outputs, fn {_name, type, _constraints} -> type end)
      assert :string in output_types
      assert :probability in output_types
      assert :reasoning_chain in output_types
    end
    
    test "handles signature constraints properly" do
      defmodule ConstrainedSignature do
        use AshDSPy.Signature
        
        signature name: {:string, min_length: 2, max_length: 50}, 
                 age: {:integer, min: 0, max: 150} ->
                 classification: {:atom, one_of: [:young, :adult, :senior]}
      end
      
      signature = ConstrainedSignature.__signature__()
      
      {_name, _type, name_constraints} = Enum.find(signature.inputs, fn {name, _, _} -> name == :name end)
      assert [min_length: 2, max_length: 50] == name_constraints
      
      {_name, _type, age_constraints} = Enum.find(signature.inputs, fn {name, _, _} -> name == :age end)
      assert [min: 0, max: 150] == age_constraints
      
      {_name, _type, class_constraints} = Enum.find(signature.outputs, fn {name, _, _} -> name == :classification end)
      assert [one_of: [:young, :adult, :senior]] == class_constraints
    end
    
    test "validates inputs correctly" do
      defmodule ValidationSignature do
        use AshDSPy.Signature
        
        signature question: :string, count: :integer -> answer: :string
      end
      
      # Valid inputs
      {:ok, validated} = ValidationSignature.validate_inputs(%{
        question: "What is AI?",
        count: 42
      })
      
      assert validated.question == "What is AI?"
      assert validated.count == 42
      
      # Invalid inputs - missing field
      {:error, reason} = ValidationSignature.validate_inputs(%{question: "test"})
      assert reason =~ "Missing field: count"
      
      # Invalid inputs - wrong type
      {:error, reason} = ValidationSignature.validate_inputs(%{
        question: "test",
        count: "not a number"
      })
      assert reason =~ "Expected :integer"
    end
    
    test "validates outputs correctly" do
      defmodule OutputValidationSignature do
        use AshDSPy.Signature
        
        signature input: :string -> result: :string, score: :probability
      end
      
      # Valid outputs
      {:ok, validated} = OutputValidationSignature.validate_outputs(%{
        result: "success",
        score: 0.85
      })
      
      assert validated.result == "success"
      assert validated.score == 0.85
      
      # Invalid outputs
      {:error, reason} = OutputValidationSignature.validate_outputs(%{
        result: "success",
        score: 1.5  # Invalid probability
      })
      assert reason =~ "Probability must be between 0.0 and 1.0"
    end
    
    test "generates JSON schemas correctly" do
      defmodule JsonSchemaSignature do
        use AshDSPy.Signature
        
        signature question: :string -> answer: :string, confidence: :probability
      end
      
      schema = JsonSchemaSignature.to_json_schema(:openai)
      
      assert schema.type == "object"
      assert Map.has_key?(schema.properties, :question)
      assert Map.has_key?(schema.properties, :answer)
      assert Map.has_key?(schema.properties, :confidence)
      
      # Verify probability constraints
      confidence_schema = schema.properties.confidence
      assert confidence_schema.type == "number"
      assert confidence_schema.minimum == 0.0
      assert confidence_schema.maximum == 1.0
    end
    
    test "rejects invalid signature syntax" do
      assert_raise RuntimeError, ~r/Invalid signature syntax/, fn ->
        defmodule InvalidSignature do
          use AshDSPy.Signature
          
          signature invalid_syntax_here
        end
      end
    end
    
    test "requires signature definition" do
      assert_raise RuntimeError, ~r/No signature defined/, fn ->
        defmodule NoSignature do
          use AshDSPy.Signature
          # No signature defined
        end
        
        NoSignature.__signature__()
      end
    end
  end
  
  describe "signature function generation" do
    defmodule FunctionTestSignature do
      use AshDSPy.Signature
      
      signature input: :string -> output: :string
    end
    
    test "generates required functions" do
      assert function_exported?(FunctionTestSignature, :__signature__, 0)
      assert function_exported?(FunctionTestSignature, :input_fields, 0)
      assert function_exported?(FunctionTestSignature, :output_fields, 0)
      assert function_exported?(FunctionTestSignature, :validate_inputs, 1)
      assert function_exported?(FunctionTestSignature, :validate_outputs, 1)
      assert function_exported?(FunctionTestSignature, :to_json_schema, 0)
      assert function_exported?(FunctionTestSignature, :to_json_schema, 1)
    end
    
    test "input_fields returns correct fields" do
      input_fields = FunctionTestSignature.input_fields()
      assert input_fields == [{:input, :string, []}]
    end
    
    test "output_fields returns correct fields" do
      output_fields = FunctionTestSignature.output_fields()
      assert output_fields == [{:output, :string, []}]
    end
  end
end
```

### TYPE SYSTEM TESTING

**Comprehensive Type System Testing:**
```elixir
defmodule AshDSPy.Types.ValidatorTest do
  use AshDSPy.TestSupport, async: true
  
  alias AshDSPy.Types.Validator
  
  describe "basic type validation" do
    test "validates strings" do
      assert {:ok, "hello"} = Validator.validate_value("hello", :string)
      assert {:error, _} = Validator.validate_value(123, :string)
      assert {:error, _} = Validator.validate_value(nil, :string)
    end
    
    test "validates integers with coercion" do
      assert {:ok, 42} = Validator.validate_value(42, :integer)
      assert {:ok, 42} = Validator.validate_value("42", :integer)
      assert {:error, _} = Validator.validate_value("not a number", :integer)
      assert {:error, _} = Validator.validate_value(3.14, :integer)
    end
    
    test "validates floats with coercion" do
      assert {:ok, 3.14} = Validator.validate_value(3.14, :float)
      assert {:ok, 42.0} = Validator.validate_value(42, :float)
      assert {:ok, 3.14} = Validator.validate_value("3.14", :float)
      assert {:error, _} = Validator.validate_value("not a number", :float)
    end
    
    test "validates booleans with coercion" do
      # Native booleans
      assert {:ok, true} = Validator.validate_value(true, :boolean)
      assert {:ok, false} = Validator.validate_value(false, :boolean)
      
      # String coercion
      assert {:ok, true} = Validator.validate_value("true", :boolean)
      assert {:ok, false} = Validator.validate_value("false", :boolean)
      
      # Integer coercion
      assert {:ok, true} = Validator.validate_value(1, :boolean)
      assert {:ok, false} = Validator.validate_value(0, :boolean)
      
      # Invalid values
      assert {:error, _} = Validator.validate_value("maybe", :boolean)
      assert {:error, _} = Validator.validate_value(2, :boolean)
    end
    
    test "validates atoms with coercion" do
      assert {:ok, :test} = Validator.validate_value(:test, :atom)
      assert {:ok, :test} = Validator.validate_value("test", :atom)
      assert {:error, _} = Validator.validate_value(123, :atom)
    end
  end
  
  describe "ML type validation" do
    test "validates embeddings" do
      valid_embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
      assert {:ok, ^valid_embedding} = Validator.validate_value(valid_embedding, :embedding)
      
      # Coerces integers to floats
      mixed_embedding = [1, 0.2, 3, 0.4]
      {:ok, coerced} = Validator.validate_value(mixed_embedding, :embedding)
      assert Enum.all?(coerced, &is_float/1)
      
      # Rejects non-numeric values
      assert {:error, _} = Validator.validate_value([1, "two", 3], :embedding)
      assert {:error, _} = Validator.validate_value("not a list", :embedding)
    end
    
    test "validates probabilities" do
      assert {:ok, 0.5} = Validator.validate_value(0.5, :probability)
      assert {:ok, 0.0} = Validator.validate_value(0.0, :probability)
      assert {:ok, 1.0} = Validator.validate_value(1.0, :probability)
      
      # Coerces integers
      assert {:ok, 0.0} = Validator.validate_value(0, :probability)
      assert {:ok, 1.0} = Validator.validate_value(1, :probability)
      
      # Rejects out of range
      assert {:error, _} = Validator.validate_value(-0.1, :probability)
      assert {:error, _} = Validator.validate_value(1.1, :probability)
      assert {:error, _} = Validator.validate_value("0.5", :probability)
    end
    
    test "validates confidence scores" do
      # Same as probability validation
      assert {:ok, 0.85} = Validator.validate_value(0.85, :confidence_score)
      assert {:error, _} = Validator.validate_value(1.5, :confidence_score)
    end
    
    test "validates reasoning chains" do
      valid_chain = ["step 1", "step 2", "step 3"]
      assert {:ok, ^valid_chain} = Validator.validate_value(valid_chain, :reasoning_chain)
      
      # Rejects non-string items
      assert {:error, _} = Validator.validate_value([1, 2, 3], :reasoning_chain)
      assert {:error, _} = Validator.validate_value("not a list", :reasoning_chain)
    end
    
    test "validates token counts" do
      assert {:ok, 100} = Validator.validate_value(100, :token_count)
      assert {:ok, 0} = Validator.validate_value(0, :token_count)
      
      # Rejects negative values
      assert {:error, _} = Validator.validate_value(-1, :token_count)
      assert {:error, _} = Validator.validate_value("100", :token_count)
    end
  end
  
  describe "composite type validation" do
    test "validates lists" do
      list_type = {:list, :string}
      valid_list = ["a", "b", "c"]
      assert {:ok, ^valid_list} = Validator.validate_value(valid_list, list_type)
      
      # Rejects items of wrong type
      assert {:error, _} = Validator.validate_value([1, 2, 3], list_type)
      assert {:error, _} = Validator.validate_value("not a list", list_type)
      
      # Works with empty lists
      assert {:ok, []} = Validator.validate_value([], list_type)
    end
    
    test "validates nested lists" do
      nested_type = {:list, {:list, :integer}}
      valid_nested = [[1, 2], [3, 4], [5, 6]]
      assert {:ok, ^valid_nested} = Validator.validate_value(valid_nested, nested_type)
      
      # Rejects invalid nested structure
      assert {:error, _} = Validator.validate_value([[1, "two"], [3, 4]], nested_type)
    end
    
    test "validates dictionaries" do
      dict_type = {:dict, :string, :integer}
      valid_dict = %{"a" => 1, "b" => 2}
      assert {:ok, ^valid_dict} = Validator.validate_value(valid_dict, dict_type)
      
      # Rejects wrong key/value types
      assert {:error, _} = Validator.validate_value(%{1 => "a"}, dict_type)
      assert {:error, _} = Validator.validate_value(%{"a" => "not integer"}, dict_type)
      assert {:error, _} = Validator.validate_value("not a map", dict_type)
    end
    
    test "validates unions" do
      union_type = {:union, [:string, :integer]}
      
      assert {:ok, "hello"} = Validator.validate_value("hello", union_type)
      assert {:ok, 42} = Validator.validate_value(42, union_type)
      
      # Rejects values not matching any type
      assert {:error, _} = Validator.validate_value(3.14, union_type)
      assert {:error, _} = Validator.validate_value(true, union_type)
    end
  end
  
  describe "constraint validation" do
    test "validates string constraints" do
      constraints = [min_length: 3, max_length: 10]
      
      assert {:ok, "hello"} = Validator.validate_value("hello", :string, constraints)
      assert {:error, _} = Validator.validate_value("hi", :string, constraints)
      assert {:error, _} = Validator.validate_value("this is too long", :string, constraints)
    end
    
    test "validates pattern constraints" do
      constraints = [pattern: ~r/^[a-z]+$/]
      
      assert {:ok, "hello"} = Validator.validate_value("hello", :string, constraints)
      assert {:error, _} = Validator.validate_value("Hello", :string, constraints)
      assert {:error, _} = Validator.validate_value("hello123", :string, constraints)
    end
    
    test "validates numeric constraints" do
      constraints = [min: 0, max: 100]
      
      assert {:ok, 50} = Validator.validate_value(50, :integer, constraints)
      assert {:ok, 0} = Validator.validate_value(0, :integer, constraints)
      assert {:ok, 100} = Validator.validate_value(100, :integer, constraints)
      
      assert {:error, _} = Validator.validate_value(-1, :integer, constraints)
      assert {:error, _} = Validator.validate_value(101, :integer, constraints)
    end
    
    test "validates atom constraints" do
      constraints = [one_of: [:red, :green, :blue]]
      
      assert {:ok, :red} = Validator.validate_value(:red, :atom, constraints)
      assert {:ok, :green} = Validator.validate_value("green", :atom, constraints)
      assert {:error, _} = Validator.validate_value(:yellow, :atom, constraints)
    end
    
    test "validates embedding constraints" do
      constraints = [dimensions: 3]
      
      assert {:ok, [1.0, 2.0, 3.0]} = Validator.validate_value([1.0, 2.0, 3.0], :embedding, constraints)
      assert {:error, _} = Validator.validate_value([1.0, 2.0], :embedding, constraints)
      assert {:error, _} = Validator.validate_value([1.0, 2.0, 3.0, 4.0], :embedding, constraints)
    end
    
    test "validates list constraints" do
      list_type = {:list, :string}
      constraints = [min_length: 2, max_length: 5, unique: true]
      
      assert {:ok, ["a", "b", "c"]} = Validator.validate_value(["a", "b", "c"], list_type, constraints)
      assert {:error, _} = Validator.validate_value(["a"], list_type, constraints)  # Too short
      assert {:error, _} = Validator.validate_value(["a", "b", "c", "d", "e", "f"], list_type, constraints)  # Too long
      assert {:error, _} = Validator.validate_value(["a", "b", "a"], list_type, constraints)  # Not unique
    end
  end
  
  describe "error handling" do
    test "provides descriptive error messages" do
      {:error, message} = Validator.validate_value(123, :string)
      assert message =~ "Expected :string"
      assert message =~ "got 123"
      
      {:error, message} = Validator.validate_value("hello", :integer, [min: 10])
      assert message =~ "Cannot convert to integer"
      
      {:error, message} = Validator.validate_value(5, :integer, [min: 10])
      assert message =~ "Value too small"
      assert message =~ "minimum 10"
    end
    
    test "handles unknown types gracefully" do
      {:error, message} = Validator.validate_value("test", :unknown_type)
      assert message =~ "Unknown type"
      assert message =~ "unknown_type"
    end
    
    test "handles malformed constraints" do
      {:error, message} = Validator.validate_value("test", :string, [invalid_constraint: "value"])
      assert message =~ "Unsupported constraint"
    end
  end
end
```

### ADAPTER TESTING FRAMEWORK

**Mock Adapter and Adapter Testing:**
```elixir
defmodule AshDSPy.Adapters.MockTest do
  use AshDSPy.TestSupport, async: false  # Mock adapter uses global state
  
  alias AshDSPy.Adapters.Mock
  
  setup do
    {:ok, _pid} = Mock.start_link()
    Mock.reset()
    :ok
  end
  
  describe "mock adapter functionality" do
    test "creates programs successfully" do
      config = %{
        id: "test_program",
        signature: create_test_signature(),
        modules: []
      }
      
      {:ok, program_id} = Mock.create_program(config)
      assert program_id == "test_program"
      
      # Verify program was stored
      {:ok, programs} = Mock.list_programs()
      assert "test_program" in programs
    end
    
    test "executes programs with mock outputs" do
      # Create program first
      config = %{
        id: "test_program", 
        signature: create_test_signature(),
        modules: []
      }
      {:ok, _} = Mock.create_program(config)
      
      # Execute program
      inputs = %{question: "What is 2+2?"}
      {:ok, outputs} = Mock.execute_program("test_program", inputs)
      
      # Mock should generate outputs based on signature
      assert Map.has_key?(outputs, :answer)
      assert Map.has_key?(outputs, :confidence)
      assert is_binary(outputs.answer)
      assert is_float(outputs.confidence)
      assert outputs.confidence >= 0.0 and outputs.confidence <= 1.0
    end
    
    test "returns error for non-existent program" do
      inputs = %{question: "test"}
      {:error, error} = Mock.execute_program("nonexistent", inputs)
      assert error =~ "Program not found"
    end
    
    test "tracks call log" do
      config = %{id: "test", signature: create_test_signature(), modules: []}
      Mock.create_program(config)
      Mock.execute_program("test", %{question: "test"})
      Mock.list_programs()
      
      call_log = Mock.get_call_log()
      assert length(call_log) == 3
      
      # Verify call types
      call_types = Enum.map(call_log, fn {type, _, _} -> type end)
      assert :create_program in call_types
      assert :execute_program in call_types
      assert :list_programs in call_types
    end
    
    test "generates appropriate mock values for different types" do
      signature_module = create_signature_with_various_types()
      
      config = %{
        id: "test_types",
        signature: signature_module,
        modules: []
      }
      
      {:ok, _} = Mock.create_program(config)
      {:ok, outputs} = Mock.execute_program("test_types", %{input: "test"})
      
      # Verify mock outputs match expected types
      assert is_binary(outputs.text_output)
      assert is_integer(outputs.number_output)
      assert is_float(outputs.score_output)
      assert is_boolean(outputs.flag_output)
      assert is_list(outputs.list_output)
      assert Enum.all?(outputs.list_output, &is_binary/1)
    end
    
    test "resets state correctly" do
      # Create some programs
      Mock.create_program(%{id: "test1", signature: create_test_signature(), modules: []})
      Mock.create_program(%{id: "test2", signature: create_test_signature(), modules: []})
      
      {:ok, programs} = Mock.list_programs()
      assert length(programs) == 2
      
      # Reset and verify clean state
      Mock.reset()
      
      {:ok, programs} = Mock.list_programs()
      assert Enum.empty?(programs)
      
      call_log = Mock.get_call_log()
      assert length(call_log) == 1  # Only the list_programs call after reset
    end
  end
  
  defp create_test_signature do
    defmodule TestSignature do
      use AshDSPy.Signature
      
      signature question: :string -> answer: :string, confidence: :probability
    end
    
    TestSignature
  end
  
  defp create_signature_with_various_types do
    defmodule VariousTypesSignature do
      use AshDSPy.Signature
      
      signature input: :string -> 
               text_output: :string,
               number_output: :integer,
               score_output: :probability,
               flag_output: :boolean,
               list_output: {:list, :string}
    end
    
    VariousTypesSignature
  end
end

defmodule AshDSPy.Adapters.BehaviorTest do
  use AshDSPy.TestSupport, async: false
  
  alias AshDSPy.Adapters.{Mock, Registry, Factory}
  
  @adapters_to_test [Mock]  # Add more adapters as they become available
  
  describe "adapter behavior compliance" do
    setup do
      # Ensure mock adapter is running
      {:ok, _} = Mock.start_link()
      Mock.reset()
      :ok
    end
    
    for adapter <- @adapters_to_test do
      test "#{adapter} implements required callbacks" do
        adapter = unquote(adapter)
        
        # Verify behavior implementation
        assert function_exported?(adapter, :create_program, 1)
        assert function_exported?(adapter, :execute_program, 2)
        assert function_exported?(adapter, :list_programs, 0)
      end
      
      test "#{adapter} handles program lifecycle correctly" do
        adapter = unquote(adapter)
        
        signature_module = create_test_signature()
        config = %{
          id: "lifecycle_test",
          signature: signature_module,
          modules: []
        }
        
        # Create program
        {:ok, program_id} = adapter.create_program(config)
        assert program_id == "lifecycle_test"
        
        # List programs
        {:ok, programs} = adapter.list_programs()
        assert "lifecycle_test" in programs
        
        # Execute program
        inputs = %{question: "test question"}
        {:ok, outputs} = adapter.execute_program("lifecycle_test", inputs)
        assert is_map(outputs)
        assert Map.has_key?(outputs, :answer)
      end
      
      test "#{adapter} validates inputs properly" do
        adapter = unquote(adapter)
        
        # Test with non-existent program
        {:error, _reason} = adapter.execute_program("nonexistent", %{})
      end
    end
  end
  
  describe "adapter factory" do
    test "creates adapters correctly" do
      {:ok, adapter} = Factory.create_adapter(:mock)
      assert adapter == Mock
    end
    
    test "validates unknown adapters" do
      {:error, _reason} = Factory.create_adapter(:unknown_adapter)
    end
    
    test "executes with retry logic" do
      signature_module = create_test_signature()
      config = %{id: "retry_test", signature: signature_module, modules: []}
      
      {:ok, _} = Mock.create_program(config)
      
      # This should succeed with mock adapter
      {:ok, result} = Factory.execute_with_adapter(
        Mock,
        :execute_program,
        ["retry_test", %{question: "test"}],
        max_retries: 2
      )
      
      assert is_map(result)
    end
  end
  
  describe "adapter registry" do
    test "returns correct adapters" do
      adapter = Registry.get_adapter(:mock)
      assert adapter == Mock
      
      adapter = Registry.get_adapter(nil)  # Should return default
      assert adapter != nil
    end
    
    test "lists available adapters" do
      adapters = Registry.list_adapters()
      assert :mock in adapters
    end
    
    test "validates adapter modules" do
      {:ok, adapter} = Registry.validate_adapter(Mock)
      assert adapter == Mock
      
      {:error, _reason} = Registry.validate_adapter(NonExistentAdapter)
    end
  end
  
  defp create_test_signature do
    defmodule AdapterTestSignature do
      use AshDSPy.Signature
      
      signature question: :string -> answer: :string
    end
    
    AdapterTestSignature
  end
end
```

### PROPERTY-BASED TESTING

**Property-Based Testing with StreamData:**
```elixir
defmodule AshDSPy.PropertyTest do
  use AshDSPy.TestSupport, async: true
  use ExUnitProperties
  
  alias AshDSPy.Types.Validator
  
  describe "type system properties" do
    property "string validation always accepts valid strings" do
      check all string <- string(:printable) do
        case Validator.validate_value(string, :string) do
          {:ok, validated} -> assert validated == string
          {:error, _} -> flunk("Valid string rejected: #{inspect(string)}")
        end
      end
    end
    
    property "integer validation accepts all integers" do
      check all int <- integer() do
        {:ok, validated} = Validator.validate_value(int, :integer)
        assert validated == int
      end
    end
    
    property "probability validation rejects out-of-range values" do
      check all value <- one_of([
        float(min: -1000.0, max: -0.01),  # Negative values
        float(min: 1.01, max: 1000.0)    # > 1.0 values
      ]) do
        {:error, _reason} = Validator.validate_value(value, :probability)
      end
    end
    
    property "probability validation accepts valid range" do
      check all value <- float(min: 0.0, max: 1.0) do
        {:ok, validated} = Validator.validate_value(value, :probability)
        assert validated == value
        assert validated >= 0.0 and validated <= 1.0
      end
    end
    
    property "list validation preserves order and content" do
      check all list <- list_of(string(:printable)) do
        {:ok, validated} = Validator.validate_value(list, {:list, :string})
        assert validated == list
        assert length(validated) == length(list)
      end
    end
    
    property "embedding validation handles numeric lists" do
      check all embedding <- list_of(float(), min_length: 1, max_length: 1000) do
        {:ok, validated} = Validator.validate_value(embedding, :embedding)
        assert length(validated) == length(embedding)
        assert Enum.all?(validated, &is_float/1)
      end
    end
    
    property "constraint validation is consistent" do
      check all {value, min_len, max_len} <- {
        string(:printable, min_length: 1, max_length: 100),
        positive_integer(),
        positive_integer()
      }, min_len <= max_len do
        constraints = [min_length: min_len, max_length: max_len]
        result = Validator.validate_value(value, :string, constraints)
        
        case result do
          {:ok, _} ->
            assert String.length(value) >= min_len
            assert String.length(value) <= max_len
          
          {:error, reason} ->
            assert String.length(value) < min_len or String.length(value) > max_len
            assert reason =~ "too short" or reason =~ "too long"
        end
      end
    end
  end
  
  describe "signature compilation properties" do
    property "compiled signatures preserve field information" do
      check all fields <- field_generator() do
        # This would require dynamic module generation
        # Simplified test for now
        
        # Test that field parsing is consistent
        parsed = AshDSPy.Signature.Compiler.parse_fields(fields)
        assert length(parsed) == length(fields)
      end
    end
  end
  
  # Generators for property-based testing
  defp field_generator do
    gen all field_name <- atom(:alphanumeric),
            field_type <- type_generator() do
      {field_name, field_type}
    end
    |> list_of(min_length: 1, max_length: 10)
  end
  
  defp type_generator do
    one_of([
      constant(:string),
      constant(:integer),
      constant(:float),
      constant(:boolean),
      constant(:probability),
      constant(:embedding),
      tuple({constant(:list), type_generator()}),
      tuple({constant(:dict), type_generator(), type_generator()})
    ])
  end
end
```

### PERFORMANCE TESTING

**Performance Benchmarks and Load Testing:**
```elixir
defmodule AshDSPy.PerformanceTest do
  use AshDSPy.TestSupport, async: false
  
  alias AshDSPy.Types.Validator
  alias AshDSPy.Protocol.WireProtocol
  alias AshDSPy.Adapters.Mock
  
  describe "type validation performance" do
    test "string validation performance" do
      strings = for _ <- 1..1000, do: random_string(100)
      
      {time_microseconds, results} = :timer.tc(fn ->
        Enum.map(strings, &Validator.validate_value(&1, :string))
      end)
      
      # Should validate 1000 strings in under 100ms
      assert time_microseconds < 100_000
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      avg_time_per_validation = time_microseconds / 1000
      # Each validation should take less than 100 microseconds
      assert avg_time_per_validation < 100
    end
    
    test "complex type validation performance" do
      embeddings = for _ <- 1..100, do: for(_ <- 1..512, do: :rand.uniform())
      
      {time_microseconds, results} = :timer.tc(fn ->
        Enum.map(embeddings, &Validator.validate_value(&1, :embedding))
      end)
      
      # Should validate 100 512-dimensional embeddings in under 100ms
      assert time_microseconds < 100_000
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
    
    test "constraint validation performance" do
      strings = for _ <- 1..1000, do: random_string(50)
      constraints = [min_length: 10, max_length: 100, pattern: ~r/^[a-zA-Z0-9]+$/]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        Enum.map(strings, &Validator.validate_value(&1, :string, constraints))
      end)
      
      # Constraint validation should still be fast
      assert time_microseconds < 200_000  # 200ms for 1000 constrained validations
    end
  end
  
  describe "signature compilation performance" do
    test "signature compilation is fast" do
      {time_microseconds, _result} = :timer.tc(fn ->
        for i <- 1..100 do
          module_name = String.to_atom("DynamicSignature#{i}")
          
          # This would require dynamic module compilation
          # For now, test signature function calls
          create_test_signature().__signature__()
        end
      end)
      
      # 100 signature accesses should be very fast
      assert time_microseconds < 50_000  # 50ms
    end
  end
  
  describe "protocol encoding/decoding performance" do
    test "message encoding performance" do
      messages = for i <- 1..1000 do
        %{
          command: "test_command_#{i}",
          args: %{
            param1: random_string(50),
            param2: :rand.uniform(1000),
            param3: for(_ <- 1..10, do: random_string(20))
          }
        }
      end
      
      {encode_time, encoded_messages} = :timer.tc(fn ->
        Enum.map(messages, &WireProtocol.encode_message/1)
      end)
      
      {decode_time, _decoded_messages} = :timer.tc(fn ->
        Enum.map(encoded_messages, fn {:ok, encoded} ->
          WireProtocol.decode_message(encoded)
        end)
      end)
      
      # Encoding 1000 messages should be fast
      assert encode_time < 500_000  # 500ms
      assert decode_time < 500_000  # 500ms
      
      avg_encode_time = encode_time / 1000
      avg_decode_time = decode_time / 1000
      
      # Each operation should be under 500 microseconds
      assert avg_encode_time < 500
      assert avg_decode_time < 500
    end
  end
  
  describe "adapter performance" do
    setup do
      {:ok, _} = Mock.start_link()
      Mock.reset()
      :ok
    end
    
    test "mock adapter execution performance" do
      # Create programs
      programs = for i <- 1..50 do
        program_id = "perf_test_#{i}"
        config = %{id: program_id, signature: create_test_signature(), modules: []}
        {:ok, ^program_id} = Mock.create_program(config)
        program_id
      end
      
      # Execute programs
      inputs = %{question: "Performance test question"}
      
      {time_microseconds, results} = :timer.tc(fn ->
        Enum.map(programs, fn program_id ->
          Mock.execute_program(program_id, inputs)
        end)
      end)
      
      # 50 program executions should complete quickly with mock adapter
      assert time_microseconds < 100_000  # 100ms
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      avg_execution_time = time_microseconds / 50
      # Each mock execution should be under 2ms
      assert avg_execution_time < 2000
    end
    
    test "concurrent adapter execution performance" do
      # Create a program
      config = %{id: "concurrent_test", signature: create_test_signature(), modules: []}
      {:ok, _} = Mock.create_program(config)
      
      inputs = %{question: "Concurrent test question"}
      
      # Execute 100 requests concurrently
      {time_microseconds, results} = :timer.tc(fn ->
        1..100
        |> Enum.map(fn _i ->
          Task.async(fn ->
            Mock.execute_program("concurrent_test", inputs)
          end)
        end)
        |> Task.await_many(10_000)  # 10 second timeout
      end)
      
      # 100 concurrent executions should complete in reasonable time
      assert time_microseconds < 1_000_000  # 1 second
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end
  
  describe "memory usage" do
    test "type validation memory usage" do
      # Create large dataset
      large_embeddings = for _ <- 1..1000, do: for(_ <- 1..1024, do: :rand.uniform())
      
      memory_before = :erlang.memory(:total)
      
      # Validate all embeddings
      results = Enum.map(large_embeddings, &Validator.validate_value(&1, :embedding))
      
      memory_after = :erlang.memory(:total)
      
      # Ensure all validations succeeded
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      # Memory usage should be reasonable (less than 100MB increase)
      memory_increase = memory_after - memory_before
      assert memory_increase < 100 * 1024 * 1024
    end
  end
  
  defp random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end
  
  defp create_test_signature do
    defmodule PerfTestSignature do
      use AshDSPy.Signature
      
      signature question: :string -> answer: :string, confidence: :probability
    end
    
    PerfTestSignature
  end
end
```

### TEST DATA FACTORIES AND FIXTURES

**Comprehensive Test Data Generation:**
```elixir
defmodule AshDSPy.TestSupport.Factories do
  @moduledoc """
  Factories for generating test data and fixtures.
  """
  
  def signature_module(fields \\ nil) do
    fields = fields || [
      {:question, :string, []},
      {:answer, :string, []},
      {:confidence, :probability, []}
    ]
    
    # Generate a unique module name
    module_name = :"TestSignature#{:rand.uniform(1_000_000)}"
    
    # This would require runtime module generation
    # For now, return a predefined signature
    create_dynamic_signature(module_name, fields)
  end
  
  def program_config(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, "test_program_#{:rand.uniform(1000)}"),
      signature: Keyword.get(opts, :signature, default_signature()),
      modules: Keyword.get(opts, :modules, []),
      adapter_type: Keyword.get(opts, :adapter_type, :mock)
    }
  end
  
  def execution_inputs(signature_module \\ nil) do
    signature_module = signature_module || default_signature()
    signature = signature_module.__signature__()
    
    Enum.reduce(signature.inputs, %{}, fn {name, type, _constraints}, acc ->
      value = generate_value_for_type(type)
      Map.put(acc, name, value)
    end)
  end
  
  def execution_outputs(signature_module \\ nil) do
    signature_module = signature_module || default_signature()
    signature = signature_module.__signature__()
    
    Enum.reduce(signature.outputs, %{}, fn {name, type, _constraints}, acc ->
      value = generate_value_for_type(type)
      Map.put(acc, name, value)
    end)
  end
  
  def wire_protocol_message(opts \\ []) do
    %{
      command: Keyword.get(opts, :command, "test_command"),
      args: Keyword.get(opts, :args, %{param: "value"}),
      id: Keyword.get(opts, :id, Ash.UUID.generate()),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end
  
  def embedding(dimensions \\ 512) do
    for _ <- 1..dimensions, do: :rand.uniform() * 2 - 1  # Values between -1 and 1
  end
  
  def reasoning_chain(steps \\ nil) do
    steps = steps || :rand.uniform(5) + 2  # 3-7 steps
    
    for i <- 1..steps do
      "Step #{i}: #{random_reasoning_step()}"
    end
  end
  
  def large_text(size_kb \\ 10) do
    size_bytes = size_kb * 1024
    
    words = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit"]
    word_cycle = Stream.cycle(words)
    
    word_cycle
    |> Enum.take_while(fn _ ->
      byte_size(Enum.join(Enum.take(word_cycle, 1000), " ")) < size_bytes
    end)
    |> Enum.join(" ")
  end
  
  defp generate_value_for_type(:string), do: "test_string_#{:rand.uniform(1000)}"
  defp generate_value_for_type(:integer), do: :rand.uniform(1000)
  defp generate_value_for_type(:float), do: :rand.uniform() * 100
  defp generate_value_for_type(:boolean), do: :rand.uniform(2) == 1
  defp generate_value_for_type(:probability), do: :rand.uniform()
  defp generate_value_for_type(:confidence_score), do: :rand.uniform()
  defp generate_value_for_type(:embedding), do: embedding()
  defp generate_value_for_type(:reasoning_chain), do: reasoning_chain()
  defp generate_value_for_type(:token_count), do: :rand.uniform(1000)
  defp generate_value_for_type({:list, inner_type}) do
    count = :rand.uniform(5) + 1
    for _ <- 1..count, do: generate_value_for_type(inner_type)
  end
  defp generate_value_for_type({:dict, key_type, value_type}) do
    count = :rand.uniform(3) + 1
    
    for i <- 1..count, into: %{} do
      key = case key_type do
        :string -> "key_#{i}"
        :atom -> :"key_#{i}"
        _ -> generate_value_for_type(key_type)
      end
      
      value = generate_value_for_type(value_type)
      {key, value}
    end
  end
  defp generate_value_for_type(_), do: "default_value"
  
  defp random_reasoning_step do
    steps = [
      "Analyze the input data",
      "Apply domain knowledge",
      "Consider multiple perspectives",
      "Evaluate evidence",
      "Draw logical conclusions",
      "Validate assumptions",
      "Generate response"
    ]
    
    Enum.random(steps)
  end
  
  defp default_signature do
    defmodule DefaultTestSignature do
      use AshDSPy.Signature
      
      signature question: :string -> answer: :string, confidence: :probability
    end
    
    DefaultTestSignature
  end
  
  defp create_dynamic_signature(module_name, fields) do
    # This would require runtime code generation
    # For now, return the default signature
    default_signature()
  end
end

defmodule AshDSPy.TestSupport.Fixtures do
  @moduledoc """
  Predefined test fixtures and scenarios.
  """
  
  def sample_signatures do
    [
      {QASignature, "question: :string -> answer: :string"},
      {ChatSignature, "message: :string, context: {:list, :string} -> response: :string, confidence: :probability"},
      {EmbeddingSignature, "text: :string -> embedding: :embedding, model: :string"},
      {ReasoningSignature, "problem: :string -> solution: :string, reasoning: :reasoning_chain, confidence: :probability"}
    ]
  end
  
  def sample_wire_protocol_messages do
    [
      %{
        command: "create_program",
        args: %{
          id: "test_program",
          signature: %{
            inputs: [%{name: "question", type: "str"}],
            outputs: [%{name: "answer", type: "str"}]
          }
        }
      },
      %{
        command: "execute_program",
        args: %{
          program_id: "test_program",
          inputs: %{question: "What is machine learning?"}
        }
      },
      %{
        command: "list_programs",
        args: %{}
      }
    ]
  end
  
  def performance_test_data do
    %{
      small_embedding: embedding(128),
      medium_embedding: embedding(512),
      large_embedding: embedding(1536),
      small_text: random_text(100),
      medium_text: random_text(1000),
      large_text: random_text(10000),
      simple_reasoning: ["step 1", "step 2", "step 3"],
      complex_reasoning: reasoning_with_details(10)
    }
  end
  
  defp embedding(size) do
    for _ <- 1..size, do: :rand.uniform() * 2 - 1
  end
  
  defp random_text(chars) do
    :crypto.strong_rand_bytes(chars) |> Base.encode64() |> binary_part(0, chars)
  end
  
  defp reasoning_with_details(steps) do
    for i <- 1..steps do
      "Step #{i}: #{random_text(100)}"
    end
  end
end

defmodule AshDSPy.TestSupport.Assertions do
  @moduledoc """
  Custom assertions for DSPy-Ash testing.
  """
  
  import ExUnit.Assertions
  
  def assert_valid_signature(signature) do
    assert is_map(signature)
    assert Map.has_key?(signature, :inputs)
    assert Map.has_key?(signature, :outputs)
    assert Map.has_key?(signature, :module)
    assert is_list(signature.inputs)
    assert is_list(signature.outputs)
  end
  
  def assert_valid_wire_protocol_message(message) do
    assert Map.has_key?(message, :version)
    assert Map.has_key?(message, :message_id)
    assert Map.has_key?(message, :message_type)
    assert Map.has_key?(message, :payload)
    assert message.message_type in [:request, :response, :notification, :stream]
  end
  
  def assert_probability(value) do
    assert is_number(value)
    assert value >= 0.0
    assert value <= 1.0
  end
  
  def assert_embedding(value, expected_dimensions \\ nil) do
    assert is_list(value)
    assert Enum.all?(value, &is_number/1)
    
    if expected_dimensions do
      assert length(value) == expected_dimensions
    end
  end
  
  def assert_reasoning_chain(value) do
    assert is_list(value)
    assert Enum.all?(value, &is_binary/1)
    assert length(value) > 0
  end
  
  def assert_adapter_response(response, expected_keys \\ []) do
    assert is_map(response)
    
    for key <- expected_keys do
      assert Map.has_key?(response, key), "Expected key #{key} in response"
    end
  end
  
  def assert_execution_time(fun, max_time_ms) do
    {time_microseconds, result} = :timer.tc(fun)
    time_ms = time_microseconds / 1000
    
    assert time_ms <= max_time_ms, 
           "Execution took #{time_ms}ms, expected <= #{max_time_ms}ms"
    
    result
  end
  
  def assert_memory_usage(fun, max_increase_mb) do
    memory_before = :erlang.memory(:total)
    result = fun.()
    memory_after = :erlang.memory(:total)
    
    increase_bytes = memory_after - memory_before
    increase_mb = increase_bytes / (1024 * 1024)
    
    assert increase_mb <= max_increase_mb,
           "Memory increased by #{increase_mb}MB, expected <= #{max_increase_mb}MB"
    
    result
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the comprehensive testing infrastructure with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
test/
├── support/
│   ├── test_support.ex          # Main testing framework
│   ├── factories.ex             # Test data factories
│   ├── fixtures.ex              # Predefined test fixtures
│   ├── assertions.ex            # Custom assertions
│   ├── helpers.ex               # Testing helper functions
│   └── mock_systems.ex          # Mock implementations
├── ash_dspy/
│   ├── signature/
│   │   ├── compiler_test.exs    # Signature compilation tests
│   │   ├── type_parser_test.exs # Type parsing tests
│   │   └── validator_test.exs   # Validation tests
│   ├── types/
│   │   ├── registry_test.exs    # Type registry tests
│   │   ├── validator_test.exs   # Type validation tests
│   │   └── serializer_test.exs  # Serialization tests
│   ├── adapters/
│   │   ├── mock_test.exs        # Mock adapter tests
│   │   ├── behavior_test.exs    # Adapter behavior tests
│   │   └── factory_test.exs     # Adapter factory tests
│   ├── protocol/
│   │   ├── wire_protocol_test.exs # Protocol tests
│   │   └── json_schema_test.exs   # Schema generation tests
│   └── integration/
│       ├── end_to_end_test.exs    # End-to-end tests
│       └── performance_test.exs   # Performance tests
└── property/
    └── property_test.exs          # Property-based tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Test Support Framework (`test/support/test_support.ex`)**:
   - Unified testing framework with common setup
   - Global state management and cleanup
   - Service startup and teardown automation
   - Import management for all testing utilities

2. **Data Factories (`test/support/factories.ex`)**:
   - Dynamic signature generation
   - Test data generation for all types
   - Realistic test scenarios and edge cases
   - Performance test data sets

3. **Property-Based Testing (`test/property/property_test.exs`)**:
   - StreamData generators for all types
   - Property verification for type system
   - Invariant testing for signatures
   - Edge case discovery through property testing

4. **Performance Testing (`test/ash_dspy/integration/performance_test.exs`)**:
   - Benchmark testing for all components
   - Memory usage validation
   - Concurrent execution testing
   - Performance regression detection

5. **Integration Testing (`test/ash_dspy/integration/end_to_end_test.exs`)**:
   - Complete workflow testing
   - Cross-component integration validation
   - Real-world scenario simulation
   - Error propagation testing

### QUALITY REQUIREMENTS:

- **Coverage**: Comprehensive test coverage for all components
- **Performance**: Performance tests with realistic benchmarks
- **Reliability**: Stable tests that don't flake
- **Maintainability**: Clear, readable test code
- **Isolation**: Proper test isolation and cleanup
- **Documentation**: Well-documented test scenarios
- **Automation**: Easy integration with CI/CD pipelines

### INTEGRATION POINTS:

- Must test all signature system components
- Should validate type system thoroughly
- Must test adapter pattern implementations
- Should verify protocol functionality
- Must validate end-to-end workflows

### SUCCESS CRITERIA:

1. All unit tests pass with high coverage
2. Integration tests validate complete workflows
3. Property-based tests discover edge cases
4. Performance tests meet benchmarks
5. Mock systems enable isolated testing
6. Test data factories generate realistic scenarios
7. Error handling is thoroughly tested
8. Memory usage and performance are validated
9. Tests run reliably in CI/CD environments
10. Test suite provides confidence in system reliability

This testing infrastructure provides the foundation for ensuring the DSPy-Ash integration is robust, performant, and reliable across all use cases and scenarios.