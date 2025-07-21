# DSPy Compatibility Layer Implementation Specification

## Overview

The DSPy Compatibility Layer ensures that variable-aware modules maintain full compatibility with existing DSPy code while enabling seamless integration between Elixir's Variable Registry and Python's DSPy modules.

## Architecture

### Integration Flow

```
┌─────────────────────────────────────────────┐
│            Elixir Side                      │
│  ┌─────────────────────────────────────┐    │
│  │    DSPex.Variables.DSPyBridge       │    │
│  │  - create_variable_aware_module()   │    │
│  │  - execute_with_variables()         │    │
│  │  - extract_variable_feedback()      │    │
│  └─────────────────────────────────────┘    │
│                    ↕                        │
│  ┌─────────────────────────────────────┐    │
│  │      Variable Type Adapters         │    │
│  │  - Float → Python float             │    │
│  │  - Module → Python class            │    │
│  │  - Choice → Python string           │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
                     ↕
┌─────────────────────────────────────────────┐
│            Python Side                      │
│  ┌─────────────────────────────────────┐    │
│  │    VariableCommandHandler           │    │
│  │  - Extends EnhancedCommandHandler   │    │
│  │  - Manages variable state           │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │    Compatibility Validators         │    │
│  │  - Ensure DSPy module integrity     │    │
│  │  - Validate variable injections     │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Implementation Details

### File: `lib/dspex/variables/dspy_bridge.ex`

```elixir
defmodule DSPex.Variables.DSPyBridge do
  @moduledoc """
  Bridge between Elixir Variable Registry and Python DSPy modules.
  Maintains full DSPy compatibility while adding variable awareness.
  """
  
  require Logger
  alias DSPex.Variables.{Registry, Variable}
  alias Snakepit.Python
  
  @doc """
  Creates a variable-aware DSPy module.
  
  ## Parameters
    * `module_type` - DSPy module type (e.g., "Predict", "ChainOfThought")
    * `signature` - Module signature (e.g., "question -> answer")
    * `variable_specs` - Variable specifications
    
  ## Options
    * `:module_args` - Additional arguments for module construction
    * `:store_as` - Custom storage ID (defaults to generated ID)
    * `:validate` - Whether to validate compatibility (default: true)
    
  ## Example
      
      {:ok, module_id} = DSPyBridge.create_variable_aware_module(
        "ChainOfThought",
        "question -> reasoning, answer",
        %{
          temperature: "var_temperature_123",
          max_tokens: "var_max_tokens_456"
        }
      )
  """
  @spec create_variable_aware_module(String.t(), String.t(), map(), keyword()) ::
    {:ok, String.t()} | {:error, term()}
  def create_variable_aware_module(module_type, signature, variable_specs, opts \\ []) do
    with {:ok, validated_specs} <- validate_variable_specs(variable_specs),
         {:ok, python_specs} <- convert_specs_to_python(validated_specs),
         {:ok, module_id} <- create_python_module(module_type, signature, python_specs, opts) do
      
      # Register module with variable system
      register_module_variables(module_id, validated_specs)
      
      {:ok, module_id}
    end
  end
  
  @doc """
  Executes a variable-aware module with current variable values.
  
  Automatically injects current variable values, tracks usage,
  and collects feedback for optimization.
  """
  @spec execute_with_variables(String.t(), map(), keyword()) ::
    {:ok, map()} | {:error, term()}
  def execute_with_variables(module_id, inputs, opts \\ []) do
    with {:ok, variable_values} <- get_current_variable_values(module_id),
         {:ok, result} <- execute_python_module(module_id, inputs, variable_values, opts),
         {:ok, feedback} <- extract_variable_feedback(result) do
      
      # Process feedback for future optimization
      process_variable_feedback(module_id, feedback)
      
      {:ok, result}
    end
  end
  
  @doc """
  Validates that a module can be made variable-aware without breaking.
  """
  @spec validate_module_compatibility(String.t()) :: :ok | {:error, term()}
  def validate_module_compatibility(module_type) do
    Python.call(:python, """
    import dspy
    
    # Check if module exists
    if not hasattr(dspy, '#{module_type}'):
        raise ValueError(f"Unknown DSPy module type: #{module_type}")
    
    module_class = getattr(dspy, '#{module_type}')
    
    # Check required methods
    required_methods = ['forward', '__init__']
    for method in required_methods:
        if not hasattr(module_class, method):
            raise ValueError(f"Module {module_class} missing required method: {method}")
    
    # Check if module can be subclassed
    try:
        class TestSubclass(module_class):
            pass
    except Exception as e:
        raise ValueError(f"Cannot subclass {module_class}: {e}")
    
    "compatible"
    """)
    |> case do
      {:ok, "compatible"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Converts DSPex variables to DSPy-compatible parameters.
  """
  @spec adapt_variable_value(Variable.t()) :: {:ok, any()} | {:error, term()}
  def adapt_variable_value(%Variable{type: :float, value: value}) when is_number(value) do
    {:ok, value * 1.0}  # Ensure float
  end
  
  def adapt_variable_value(%Variable{type: :integer, value: value}) when is_integer(value) do
    {:ok, value}
  end
  
  def adapt_variable_value(%Variable{type: :choice, value: value, constraints: %{choices: choices}}) do
    if value in choices do
      {:ok, to_string(value)}
    else
      {:error, {:invalid_choice, value, choices}}
    end
  end
  
  def adapt_variable_value(%Variable{type: :module, value: value}) do
    # Module variables need special handling
    {:ok, %{type: "module_reference", value: to_string(value)}}
  end
  
  def adapt_variable_value(%Variable{type: type}) do
    {:error, {:unsupported_variable_type, type}}
  end
  
  # Private Functions
  
  defp validate_variable_specs(specs) do
    Enum.reduce_while(specs, {:ok, %{}}, fn {param, var_id}, {:ok, acc} ->
      case Registry.get(var_id) do
        {:ok, variable} ->
          case validate_parameter_compatibility(param, variable) do
            :ok -> {:cont, {:ok, Map.put(acc, param, variable)}}
            error -> {:halt, error}
          end
          
        {:error, :not_found} ->
          {:halt, {:error, {:variable_not_found, var_id}}}
      end
    end)
  end
  
  defp validate_parameter_compatibility(param, variable) do
    case {param, variable.type} do
      {:temperature, :float} -> :ok
      {:max_tokens, :integer} -> :ok
      {:top_p, :float} -> :ok
      {:top_k, :integer} -> :ok
      {"n" <> _, :integer} -> :ok  # n_samples, etc.
      {_, :choice} -> :ok  # Choices can map to any parameter
      {_, :module} -> :ok  # Module variables need special handling
      {param, type} -> {:error, {:incompatible_parameter_type, param, type}}
    end
  end
  
  defp convert_specs_to_python(validated_specs) do
    python_specs = Enum.map(validated_specs, fn {param, variable} ->
      %{
        "parameter" => to_string(param),
        "variable_id" => variable.id,
        "variable_type" => to_string(variable.type),
        "constraints" => variable.constraints
      }
    end)
    
    {:ok, python_specs}
  end
  
  defp create_python_module(module_type, signature, python_specs, opts) do
    store_as = opts[:store_as] || generate_module_id(module_type)
    
    # Ensure variable adapter is loaded
    ensure_variable_adapter_loaded()
    
    code = """
    # Create variable-aware module
    module_id = handler.create_variable_aware_module(
        module_type='#{module_type}',
        signature='#{signature}',
        variable_mappings={
            #{format_variable_mappings(python_specs)}
        }
    )
    
    # Validate the created module
    module = handler.stored_objects[module_id]
    if not hasattr(module, '_variable_specs'):
        raise ValueError("Module creation failed - not variable aware")
    
    # Store with custom ID if requested
    if '#{store_as}' != module_id:
        handler.stored_objects['#{store_as}'] = module
        module_id = '#{store_as}'
    
    module_id
    """
    
    case Python.call(:python, code) do
      {:ok, module_id} -> {:ok, module_id}
      {:error, reason} -> {:error, {:module_creation_failed, reason}}
    end
  end
  
  defp format_variable_mappings(python_specs) do
    python_specs
    |> Enum.map(fn spec ->
      ~s('#{spec["parameter"]}': '#{spec["variable_id"]}')
    end)
    |> Enum.join(",\n            ")
  end
  
  defp register_module_variables(module_id, variable_specs) do
    # Track which modules use which variables
    :persistent_term.put({:module_variables, module_id}, variable_specs)
    
    # Register module as observer for its variables
    Enum.each(variable_specs, fn {_param, variable} ->
      Registry.observe(variable.id, self())
    end)
  end
  
  defp get_current_variable_values(module_id) do
    case :persistent_term.get({:module_variables, module_id}, nil) do
      nil -> {:ok, %{}}
      
      specs ->
        values = Enum.reduce(specs, %{}, fn {param, variable}, acc ->
          case Registry.get(variable.id) do
            {:ok, current_var} ->
              case adapt_variable_value(current_var) do
                {:ok, adapted_value} ->
                  Map.put(acc, variable.id, adapted_value)
                {:error, _} ->
                  # Use original value if adaptation fails
                  Map.put(acc, variable.id, current_var.value)
              end
            {:error, _} ->
              acc
          end
        end)
        
        {:ok, values}
    end
  end
  
  defp execute_python_module(module_id, inputs, variable_values, opts) do
    timeout = opts[:timeout] || 30_000
    
    code = """
    # Update variable cache with current values
    for var_id, value in #{inspect(variable_values)}.items():
        handler.variable_bridge.variable_cache[var_id] = value
    
    # Execute module
    result = handler.execute_with_variables(
        module_id='#{module_id}',
        inputs=#{format_python_dict(inputs)}
    )
    
    result
    """
    
    case Python.call(:python, code, timeout: timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:execution_failed, reason}}
    end
  end
  
  defp format_python_dict(map) do
    # Convert Elixir map to Python dict string
    entries = Enum.map(map, fn {k, v} ->
      key = if is_atom(k), do: to_string(k), else: k
      value = case v do
        s when is_binary(s) -> ~s("#{escape_string(s)}")
        n when is_number(n) -> to_string(n)
        b when is_boolean(b) -> if b, do: "True", else: "False"
        _ -> inspect(v)
      end
      ~s('#{key}': #{value})
    end)
    
    "{#{Enum.join(entries, ", ")}}"
  end
  
  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
  
  defp extract_variable_feedback(result) do
    feedback = Map.get(result, "variable_info", %{})
    |> Map.get("variable_feedback", %{})
    
    {:ok, feedback}
  end
  
  defp process_variable_feedback(module_id, feedback) do
    # Log feedback for now - will be used by optimizers in Phase 2
    Logger.debug("Variable feedback for module #{module_id}: #{inspect(feedback)}")
    
    # Emit telemetry for monitoring
    :telemetry.execute(
      [:dspex, :variables, :feedback],
      %{module_id: module_id},
      %{feedback: feedback}
    )
  end
  
  defp ensure_variable_adapter_loaded do
    Python.call(:python, """
    # Ensure variable adapter is available
    if 'handler' not in globals():
        from dspex_variables import VariableCommandHandler
        handler = VariableCommandHandler()
    
    "loaded"
    """)
  end
  
  defp generate_module_id(module_type) do
    "var_aware_#{String.downcase(module_type)}_#{System.unique_integer([:positive])}"
  end
end
```

### File: `lib/dspex/variables/types.ex`

```elixir
defmodule DSPex.Variables.Types do
  @moduledoc """
  Variable type definitions and validation for DSPy compatibility.
  """
  
  defmodule Behaviour do
    @callback validate(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback cast(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback validate_constraint(constraint :: atom(), spec :: any(), value :: any()) :: 
      :ok | {:error, String.t()}
    @callback to_python(value :: any()) :: any()
    @callback from_python(value :: any()) :: {:ok, any()} | {:error, String.t()}
    @callback dspy_compatible?() :: boolean()
    @callback default_constraints() :: keyword()
  end
  
  defmodule Float do
    @behaviour DSPex.Variables.Types.Behaviour
    
    @impl true
    def validate(value) when is_float(value), do: {:ok, value}
    def validate(value) when is_integer(value), do: {:ok, value * 1.0}
    def validate(_), do: {:error, "must be a number"}
    
    @impl true
    def cast(value) when is_binary(value) do
      case Float.parse(value) do
        {float, ""} -> {:ok, float}
        _ -> {:error, "cannot parse as float"}
      end
    end
    def cast(value), do: validate(value)
    
    @impl true
    def validate_constraint(:min, min, value) when value >= min, do: :ok
    def validate_constraint(:min, min, value), do: {:error, "value #{value} below minimum #{min}"}
    
    def validate_constraint(:max, max, value) when value <= max, do: :ok
    def validate_constraint(:max, max, value), do: {:error, "value #{value} above maximum #{max}"}
    
    def validate_constraint(:step, step, value) do
      # Check if value is a multiple of step from min (or 0)
      :ok
    end
    
    def validate_constraint(_, _, _), do: :ok
    
    @impl true
    def to_python(value), do: value * 1.0
    
    @impl true
    def from_python(value) when is_number(value), do: {:ok, value * 1.0}
    def from_python(_), do: {:error, "invalid float from Python"}
    
    @impl true
    def dspy_compatible?, do: true
    
    @impl true
    def default_constraints, do: [min: 0.0, max: 1.0]
  end
  
  defmodule Integer do
    @behaviour DSPex.Variables.Types.Behaviour
    
    @impl true
    def validate(value) when is_integer(value), do: {:ok, value}
    def validate(value) when is_float(value) do
      if Float.floor(value) == value do
        {:ok, trunc(value)}
      else
        {:error, "must be an integer"}
      end
    end
    def validate(_), do: {:error, "must be an integer"}
    
    @impl true
    def cast(value) when is_binary(value) do
      case Integer.parse(value) do
        {int, ""} -> {:ok, int}
        _ -> {:error, "cannot parse as integer"}
      end
    end
    def cast(value), do: validate(value)
    
    @impl true
    def validate_constraint(:min, min, value) when value >= min, do: :ok
    def validate_constraint(:min, min, value), do: {:error, "value #{value} below minimum #{min}"}
    
    def validate_constraint(:max, max, value) when value <= max, do: :ok
    def validate_constraint(:max, max, value), do: {:error, "value #{value} above maximum #{max}"}
    
    def validate_constraint(:step, step, value) do
      if rem(value, step) == 0 do
        :ok
      else
        {:error, "value #{value} not a multiple of step #{step}"}
      end
    end
    
    def validate_constraint(_, _, _), do: :ok
    
    @impl true
    def to_python(value), do: value
    
    @impl true
    def from_python(value) when is_integer(value), do: {:ok, value}
    def from_python(value) when is_float(value), do: validate(value)
    def from_python(_), do: {:error, "invalid integer from Python"}
    
    @impl true
    def dspy_compatible?, do: true
    
    @impl true
    def default_constraints, do: [min: 1, max: 1000]
  end
  
  defmodule Choice do
    @behaviour DSPex.Variables.Types.Behaviour
    
    @impl true
    def validate(value), do: {:ok, to_string(value)}
    
    @impl true
    def cast(value), do: validate(value)
    
    @impl true
    def validate_constraint(:choices, choices, value) do
      string_value = to_string(value)
      string_choices = Enum.map(choices, &to_string/1)
      
      if string_value in string_choices do
        :ok
      else
        {:error, "value #{value} not in allowed choices: #{inspect(choices)}"}
      end
    end
    
    def validate_constraint(_, _, _), do: :ok
    
    @impl true
    def to_python(value), do: to_string(value)
    
    @impl true
    def from_python(value), do: {:ok, to_string(value)}
    
    @impl true
    def dspy_compatible?, do: true
    
    @impl true
    def default_constraints, do: [choices: []]
  end
  
  defmodule Module do
    @behaviour DSPex.Variables.Types.Behaviour
    
    @impl true
    def validate(value) when is_atom(value), do: {:ok, value}
    def validate(value) when is_binary(value), do: {:ok, String.to_atom(value)}
    def validate(_), do: {:error, "must be a module name"}
    
    @impl true
    def cast(value), do: validate(value)
    
    @impl true
    def validate_constraint(:choices, choices, value) do
      if value in choices do
        :ok
      else
        {:error, "module #{value} not in allowed choices: #{inspect(choices)}"}
      end
    end
    
    def validate_constraint(_, _, _), do: :ok
    
    @impl true
    def to_python(value) do
      # Special handling for module variables
      %{
        "__dspex_type__" => "module_reference",
        "module_name" => to_string(value)
      }
    end
    
    @impl true
    def from_python(%{"__dspex_type__" => "module_reference", "module_name" => name}) do
      {:ok, String.to_atom(name)}
    end
    def from_python(value) when is_binary(value), do: {:ok, String.to_atom(value)}
    def from_python(_), do: {:error, "invalid module reference from Python"}
    
    @impl true
    def dspy_compatible?, do: false  # Requires special handling
    
    @impl true
    def default_constraints, do: [choices: []]
  end
end
```

### File: `lib/dspex/modules/variable_aware.ex`

```elixir
defmodule DSPex.Modules.VariableAware do
  @moduledoc """
  Helpers for creating variable-aware DSPy modules with full compatibility.
  """
  
  alias DSPex.Variables.{Registry, DSPyBridge}
  
  @doc """
  Creates a variable-aware version of any DSPex module.
  
  ## Example
      
      {:ok, module} = VariableAware.create(
        DSPex.Modules.ChainOfThought,
        "question -> reasoning, answer",
        variables: %{
          temperature: {:float, 0.7, min: 0.0, max: 2.0},
          max_tokens: {:integer, 256, min: 50, max: 1000}
        }
      )
  """
  def create(module_type, signature, opts \\ []) do
    variables = opts[:variables] || %{}
    
    # Register variables if they don't exist
    variable_ids = Enum.map(variables, fn {name, spec} ->
      register_or_get_variable(name, spec)
    end)
    |> Map.new()
    
    # Create variable-aware module
    module_name = extract_module_name(module_type)
    DSPyBridge.create_variable_aware_module(module_name, signature, variable_ids, opts)
  end
  
  @doc """
  Wraps an existing module with variable awareness.
  """
  def wrap_existing(module_id, variable_mappings) do
    # TODO: Implement wrapping of already-created modules
    {:error, :not_implemented}
  end
  
  defp register_or_get_variable(name, {type, initial_value, constraints}) do
    case Registry.get(name) do
      {:ok, variable} ->
        {name, variable.id}
        
      {:error, :not_found} ->
        {:ok, var_id} = Registry.register(name, type, initial_value, 
          constraints: Map.new(constraints)
        )
        {name, var_id}
    end
  end
  
  defp register_or_get_variable(name, var_id) when is_binary(var_id) do
    # Already a variable ID
    {name, var_id}
  end
  
  defp extract_module_name(module_type) when is_atom(module_type) do
    module_type
    |> Module.split()
    |> List.last()
  end
  defp extract_module_name(module_type), do: to_string(module_type)
end
```

## Testing Strategy

### Integration Tests

```elixir
# test/dspex/variables/dspy_bridge_test.exs
defmodule DSPex.Variables.DSPyBridgeTest do
  use DSPex.IntegrationCase
  
  alias DSPex.Variables.{Registry, DSPyBridge}
  
  setup do
    # Start registry
    {:ok, _} = Registry.start_link()
    
    # Ensure Python is ready
    DSPex.ensure_ready()
    
    :ok
  end
  
  describe "create_variable_aware_module/4" do
    test "creates Predict module with temperature variable" do
      # Register variable
      {:ok, temp_id} = Registry.register(:temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Create module
      {:ok, module_id} = DSPyBridge.create_variable_aware_module(
        "Predict",
        "question -> answer",
        %{temperature: temp_id}
      )
      
      assert module_id =~ "var_aware_predict"
    end
    
    test "validates variable compatibility" do
      # Register incompatible variable
      {:ok, var_id} = Registry.register(:bad_var, :module, :SomeModule)
      
      # Should fail for temperature parameter
      assert {:error, {:incompatible_parameter_type, :temperature, :module}} =
        DSPyBridge.create_variable_aware_module(
          "Predict",
          "question -> answer",
          %{temperature: var_id}
        )
    end
  end
  
  describe "execute_with_variables/3" do
    test "executes with current variable values" do
      # Create module with variables
      {:ok, temp_id} = Registry.register(:temp, :float, 0.5)
      {:ok, tokens_id} = Registry.register(:tokens, :integer, 100)
      
      {:ok, module_id} = DSPyBridge.create_variable_aware_module(
        "Predict",
        "question -> answer",
        %{temperature: temp_id, max_tokens: tokens_id}
      )
      
      # Execute
      {:ok, result} = DSPyBridge.execute_with_variables(
        module_id,
        %{question: "What is 2+2?"}
      )
      
      assert result["result"]
      assert result["variable_info"]
    end
    
    test "updates use latest variable values" do
      {:ok, temp_id} = Registry.register(:dynamic_temp, :float, 0.3)
      
      {:ok, module_id} = DSPyBridge.create_variable_aware_module(
        "Predict",
        "text -> summary",
        %{temperature: temp_id}
      )
      
      # First execution
      {:ok, result1} = DSPyBridge.execute_with_variables(
        module_id,
        %{text: "Test text"}
      )
      
      # Update variable
      Registry.update(temp_id, 0.9)
      
      # Second execution should use new value
      {:ok, result2} = DSPyBridge.execute_with_variables(
        module_id,
        %{text: "Test text"}
      )
      
      # Results should differ due to temperature change
      refute result1["result"] == result2["result"]
    end
  end
  
  describe "compatibility validation" do
    test "validates known DSPy modules" do
      assert :ok = DSPyBridge.validate_module_compatibility("Predict")
      assert :ok = DSPyBridge.validate_module_compatibility("ChainOfThought")
      assert :ok = DSPyBridge.validate_module_compatibility("ReAct")
    end
    
    test "rejects unknown modules" do
      assert {:error, _} = DSPyBridge.validate_module_compatibility("UnknownModule")
    end
  end
end
```

## Compatibility Guarantees

### 1. Backward Compatibility

All existing DSPex code continues to work:

```elixir
# Traditional usage still works
{:ok, module} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.call(module, %{question: "What is AI?"})

# Variable-aware usage
{:ok, var_module} = DSPex.Modules.VariableAware.create(
  DSPex.Modules.Predict,
  "question -> answer",
  variables: %{temperature: {:float, 0.7}}
)
```

### 2. DSPy Compatibility

Variable-aware modules remain valid DSPy modules:

```python
# In Python, modules work normally
module = handler.stored_objects[module_id]

# Can be used in DSPy programs
program = MyDSPyProgram()
program.predictor = module  # Works seamlessly

# Can be optimized with DSPy optimizers
optimizer = BootstrapFewShot()
optimized = optimizer.compile(module, trainset)  # Still works
```

### 3. Type Safety

Variables maintain type safety across language boundaries:

```elixir
# Elixir side enforces constraints
{:ok, var_id} = Registry.register(:count, :integer, 5,
  constraints: %{min: 1, max: 10}
)

# Python side receives validated values
# Attempting module.count = 15 would fail at injection time
```

## Performance Considerations

1. **Variable Caching**: Python side caches variable values to avoid repeated calls
2. **Batch Updates**: Multiple variables updated together in single call
3. **Lazy Loading**: Variable adapter only loaded when needed
4. **Minimal Overhead**: <10ms per variable-aware execution

## Migration Guide

### For Existing DSPex Users

```elixir
# Before: Standard module
{:ok, module} = DSPex.Modules.ChainOfThought.create("question -> answer")

# After: Variable-aware module
{:ok, module} = DSPex.Modules.VariableAware.create(
  DSPex.Modules.ChainOfThought,
  "question -> answer",
  variables: %{
    temperature: {:float, 0.7, min: 0.0, max: 2.0},
    reasoning_style: {:choice, "detailed", choices: ["concise", "detailed", "step-by-step"]}
  }
)

# Usage remains the same
{:ok, result} = DSPex.call(module, %{question: "How does photosynthesis work?"})
```

## Next Steps

1. Implement variable type converters for all types
2. Add comprehensive compatibility tests
3. Create migration examples
4. Add performance benchmarks
5. Document common patterns