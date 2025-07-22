# Prompt: Build the DSPex.Variables User API

## Objective
Create `DSPex.Variables`, the high-level API that provides an intuitive interface for variable operations. This module abstracts away backend complexity and provides Elixir-idiomatic patterns for state management.

## Context
DSPex.Variables is the primary interface for users to work with variables. It should:
- Provide simple, intuitive functions
- Handle errors gracefully  
- Support multiple access patterns
- Feel natural to Elixir developers
- Work identically regardless of backend

## Requirements

### API Design Goals
1. Minimal cognitive overhead
2. Consistent with Elixir conventions
3. Comprehensive but not overwhelming
4. Clear error messages
5. Good default behaviors

### Core Functions
- `defvariable/5` - Define new variables with types
- `get/3` - Get values with defaults
- `set/4` - Update values
- `update/4` - Functional updates
- `get_many/2` - Batch retrieval
- `update_many/3` - Batch updates

## Implementation

### Create DSPex.Variables Module

```elixir
# File: lib/dspex/variables.ex

defmodule DSPex.Variables do
  @moduledoc """
  High-level API for working with variables in a DSPex context.
  
  This module provides the primary interface for variable operations,
  abstracting away the underlying backend complexity.
  
  ## Quick Start
  
      {:ok, ctx} = DSPex.Context.start_link()
      
      # Define variables with types and constraints
      defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Get and set values
      temp = get(ctx, :temperature)
      set(ctx, :temperature, 0.9)
      
      # Functional updates
      update(ctx, :temperature, &min(&1 * 1.1, 2.0))
      
      # Batch operations
      values = get_many(ctx, [:temperature, :max_tokens])
      update_many(ctx, %{temperature: 0.8, max_tokens: 512})
  
  ## Variable Types
  
  Supported types (from Stage 1):
  - `:float` - Floating point numbers
  - `:integer` - Whole numbers
  - `:string` - Text values
  - `:boolean` - True/false values
  
  Future types (Stage 3+):
  - `:choice` - Enumerated values
  - `:module` - DSPy module references
  - `:embedding` - Vector embeddings
  - `:tensor` - Multi-dimensional arrays
  
  ## Error Handling
  
  Most functions return values directly for convenience.
  Use the bang (!) variants if you need explicit error handling:
  
      # Returns nil on error
      value = get(ctx, :missing)  # nil
      
      # Raises on error  
      value = get!(ctx, :missing)  # raises VariableNotFoundError
  """
  
  alias DSPex.Context
  require Logger
  
  @type context :: Context.t()
  @type identifier :: atom() | String.t()
  @type variable_type :: :float | :integer | :string | :boolean | :choice | :module
  @type constraints :: map()
  
  defmodule VariableNotFoundError do
    @moduledoc "Raised when a variable doesn't exist."
    defexception [:message, :identifier]
    
    def exception(identifier) do
      %__MODULE__{
        message: "Variable not found: #{inspect(identifier)}",
        identifier: identifier
      }
    end
  end
  
  defmodule ValidationError do
    @moduledoc "Raised when a value fails validation."
    defexception [:message, :identifier, :value, :reason]
    
    def exception(opts) do
      %__MODULE__{
        message: "Validation failed for #{inspect(opts[:identifier])}: #{opts[:reason]}",
        identifier: opts[:identifier],
        value: opts[:value],
        reason: opts[:reason]
      }
    end
  end
  
  ## Core API
  
  @doc """
  Defines a new variable in the context.
  
  This is the primary way to create variables with full type information
  and constraints.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `name` - Variable name (atom or string)
    * `type` - Variable type
    * `initial_value` - Initial value
    * `opts` - Options:
      * `:constraints` - Type-specific constraints
      * `:description` - Human-readable description
      * `:metadata` - Additional metadata
  
  ## Examples
  
      # Simple variable
      defvariable(ctx, :temperature, :float, 0.7)
      
      # With constraints
      defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "LLM generation temperature"
      )
      
      # String with pattern
      defvariable(ctx, :model_name, :string, "gpt-4",
        constraints: %{
          pattern: "^(gpt-4|gpt-3.5-turbo|claude-3)$"
        }
      )
      
      # Integer with range
      defvariable(ctx, :max_tokens, :integer, 256,
        constraints: %{min: 1, max: 4096}
      )
  
  ## Returns
  
    * `{:ok, var_id}` - Successfully created with ID
    * `{:error, reason}` - Creation failed
  """
  @spec defvariable(context, atom(), variable_type(), any(), keyword()) :: 
    {:ok, String.t()} | {:error, term()}
  def defvariable(context, name, type, initial_value, opts \\ []) do
    Context.register_variable(context, name, type, initial_value, opts)
  end
  
  @doc """
  Defines a variable, raising on error.
  
  Same as `defvariable/5` but raises on failure.
  """
  @spec defvariable!(context, atom(), variable_type(), any(), keyword()) :: String.t()
  def defvariable!(context, name, type, initial_value, opts \\ []) do
    case defvariable(context, name, type, initial_value, opts) do
      {:ok, var_id} -> var_id
      {:error, reason} -> 
        raise ArgumentError, "Failed to define variable #{name}: #{inspect(reason)}"
    end
  end
  
  @doc """
  Gets a variable value.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `default` - Value to return if not found (default: nil)
  
  ## Examples
  
      temperature = get(ctx, :temperature)
      
      # With default
      tokens = get(ctx, :max_tokens, 256)
      
      # Using ID
      value = get(ctx, "var_temperature_12345")
  
  ## Returns
  
  The variable value or the default if not found.
  """
  @spec get(context, identifier, any()) :: any()
  def get(context, identifier, default \\ nil) do
    case Context.get_variable(context, identifier) do
      {:ok, value} -> value
      {:error, :not_found} -> default
      {:error, reason} -> 
        Logger.warning("Failed to get variable #{identifier}: #{inspect(reason)}")
        default
    end
  end
  
  @doc """
  Gets a variable value, raising if not found.
  
  Same as `get/3` but raises `VariableNotFoundError` if the variable doesn't exist.
  """
  @spec get!(context, identifier) :: any()
  def get!(context, identifier) do
    case Context.get_variable(context, identifier) do
      {:ok, value} -> value
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to get variable: #{inspect(reason)}"
    end
  end
  
  @doc """
  Sets a variable value.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `value` - New value (will be validated)
    * `opts` - Options:
      * `:metadata` - Metadata for this update
  
  ## Examples
  
      set(ctx, :temperature, 0.9)
      
      # With metadata
      set(ctx, :temperature, 0.9,
        metadata: %{"reason" => "user_adjustment"}
      )
  
  ## Returns
  
    * `:ok` - Successfully updated
    * `{:error, reason}` - Update failed
  """
  @spec set(context, identifier, any(), keyword()) :: :ok | {:error, term()}
  def set(context, identifier, value, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.set_variable(context, identifier, value, metadata)
  end
  
  @doc """
  Sets a variable value, raising on error.
  
  Same as `set/4` but raises on failure.
  """
  @spec set!(context, identifier, any(), keyword()) :: :ok
  def set!(context, identifier, value, opts \\ []) do
    case set(context, identifier, value, opts) do
      :ok -> :ok
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> 
        raise ValidationError, identifier: identifier, value: value, reason: reason
    end
  end
  
  @doc """
  Updates a variable using a function.
  
  The function receives the current value and should return the new value.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifier` - Variable name or ID
    * `update_fn` - Function that takes current value and returns new value
    * `opts` - Options passed to `set/4`
  
  ## Examples
  
      # Increment
      update(ctx, :counter, &(&1 + 1))
      
      # Complex update
      update(ctx, :temperature, fn temp ->
        min(temp * 1.1, 2.0)
      end)
      
      # With metadata
      update(ctx, :counter, &(&1 + 1),
        metadata: %{"operation" => "increment"}
      )
  
  ## Returns
  
    * `:ok` - Successfully updated
    * `{:error, reason}` - Update failed
  """
  @spec update(context, identifier, (any() -> any()), keyword()) :: :ok | {:error, term()}
  def update(context, identifier, update_fn, opts \\ []) when is_function(update_fn, 1) do
    case Context.get_variable(context, identifier) do
      {:ok, current_value} ->
        new_value = update_fn.(current_value)
        set(context, identifier, new_value, opts)
      {:error, :not_found} ->
        {:error, :not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Updates a variable using a function, raising on error.
  """
  @spec update!(context, identifier, (any() -> any()), keyword()) :: :ok
  def update!(context, identifier, update_fn, opts \\ []) do
    case update(context, identifier, update_fn, opts) do
      :ok -> :ok
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to update variable: #{inspect(reason)}"
    end
  end
  
  @doc """
  Gets multiple variables at once.
  
  Efficient batch retrieval of multiple variables.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifiers` - List of variable names or IDs
  
  ## Examples
  
      values = get_many(ctx, [:temperature, :max_tokens, :model])
      # %{temperature: 0.7, max_tokens: 256, model: "gpt-4"}
      
      # Missing variables are omitted
      values = get_many(ctx, [:exists, :missing])
      # %{exists: "value"}
  
  ## Returns
  
  Map of identifier => value for found variables.
  """
  @spec get_many(context, [identifier]) :: map()
  def get_many(context, identifiers) do
    case Context.get_variables(context, identifiers) do
      {:ok, values} -> 
        # Convert string keys back to atoms if needed
        Map.new(values, fn {k, v} ->
          key = if is_binary(k) and identifier_in_list?(k, identifiers),
            do: safe_to_atom(k, identifiers),
            else: k
          {key, v}
        end)
      {:error, reason} -> 
        Logger.warning("Failed to get variables: #{inspect(reason)}")
        %{}
    end
  end
  
  @doc """
  Updates multiple variables at once.
  
  Efficient batch update of multiple variables.
  
  ## Parameters
  
    * `context` - The DSPex context  
    * `updates` - Map of identifier => new value
    * `opts` - Options:
      * `:metadata` - Metadata for all updates
      * `:atomic` - If true, all updates must succeed (default: false)
  
  ## Examples
  
      update_many(ctx, %{
        temperature: 0.8,
        max_tokens: 512,
        model: "gpt-4"
      })
      
      # Atomic update
      update_many(ctx, updates, atomic: true)
  
  ## Returns
  
    * `:ok` - All updates succeeded
    * `{:error, {:partial_failure, errors}}` - Some updates failed (non-atomic)
    * `{:error, reason}` - Update failed (atomic)
  """
  @spec update_many(context, map(), keyword()) :: :ok | {:error, term()}
  def update_many(context, updates, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.update_variables(context, updates, metadata)
  end
  
  @doc """
  Updates multiple variables, raising on error.
  """
  @spec update_many!(context, map(), keyword()) :: :ok
  def update_many!(context, updates, opts \\ []) do
    case update_many(context, updates, opts) do
      :ok -> :ok
      {:error, {:partial_failure, errors}} ->
        raise "Failed to update variables: #{inspect(errors)}"
      {:error, reason} ->
        raise "Failed to update variables: #{inspect(reason)}"
    end
  end
  
  @doc """
  Lists all variables in the context.
  
  ## Parameters
  
    * `context` - The DSPex context
  
  ## Returns
  
  List of variable information maps containing:
    * `:id` - Variable ID
    * `:name` - Variable name
    * `:type` - Variable type
    * `:value` - Current value
    * `:constraints` - Type constraints
    * `:metadata` - Variable metadata
    * `:version` - Version number
  
  ## Examples
  
      variables = list(ctx)
      # [
      #   %{name: :temperature, type: :float, value: 0.7, ...},
      #   %{name: :max_tokens, type: :integer, value: 256, ...}
      # ]
  """
  @spec list(context) :: [map()]
  def list(context) do
    case Context.list_variables(context) do
      {:ok, variables} -> variables
      {:error, reason} -> 
        Logger.error("Failed to list variables: #{inspect(reason)}")
        []
    end
  end
  
  @doc """
  Checks if a variable exists.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifier` - Variable name or ID
  
  ## Examples
  
      if exists?(ctx, :temperature) do
        # Variable exists
      end
  """
  @spec exists?(context, identifier) :: boolean()
  def exists?(context, identifier) do
    case Context.get_variable(context, identifier) do
      {:ok, _} -> true
      _ -> false
    end
  end
  
  @doc """
  Deletes a variable.
  
  ## Parameters
  
    * `context` - The DSPex context
    * `identifier` - Variable name or ID
  
  ## Returns
  
    * `:ok` - Successfully deleted
    * `{:error, reason}` - Deletion failed
  """
  @spec delete(context, identifier) :: :ok | {:error, term()}
  def delete(context, identifier) do
    Context.delete_variable(context, identifier)
  end
  
  @doc """
  Deletes a variable, raising on error.
  """
  @spec delete!(context, identifier) :: :ok
  def delete!(context, identifier) do
    case delete(context, identifier) do
      :ok -> :ok
      {:error, :not_found} -> raise VariableNotFoundError, identifier
      {:error, reason} -> raise "Failed to delete variable: #{inspect(reason)}"
    end
  end
  
  ## Convenience Functions
  
  @doc """
  Gets a variable's metadata.
  
  ## Examples
  
      meta = get_metadata(ctx, :temperature)
      # %{"description" => "LLM generation temperature", ...}
  """
  @spec get_metadata(context, identifier) :: map() | nil
  def get_metadata(context, identifier) do
    case list(context) do
      [] -> nil
      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.metadata
        end
    end
  end
  
  @doc """
  Gets a variable's type.
  
  ## Examples
  
      type = get_type(ctx, :temperature)
      # :float
  """
  @spec get_type(context, identifier) :: atom() | nil
  def get_type(context, identifier) do
    case list(context) do
      [] -> nil
      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.type
        end
    end
  end
  
  @doc """
  Gets a variable's constraints.
  
  ## Examples
  
      constraints = get_constraints(ctx, :temperature)
      # %{min: 0.0, max: 2.0}
  """
  @spec get_constraints(context, identifier) :: map() | nil
  def get_constraints(context, identifier) do
    case list(context) do
      [] -> nil
      variables ->
        case Enum.find(variables, &match_identifier?(&1, identifier)) do
          nil -> nil
          var -> var.constraints
        end
    end
  end
  
  ## Private Helpers
  
  defp identifier_in_list?(string_id, identifiers) do
    Enum.any?(identifiers, fn id ->
      to_string(id) == string_id
    end)
  end
  
  defp safe_to_atom(string, identifiers) do
    # Find the original atom from the identifier list
    Enum.find(identifiers, fn id ->
      to_string(id) == string
    end) || string
  end
  
  defp match_identifier?(variable, identifier) do
    variable.id == to_string(identifier) or
    to_string(variable.name) == to_string(identifier)
  end
end
```

## Usage Examples

```elixir
# File: lib/dspex/examples/variables_usage.ex

defmodule DSPex.Examples.VariablesUsage do
  @moduledoc """
  Examples of DSPex.Variables usage patterns.
  """
  
  alias DSPex.{Context, Variables}
  
  def basic_usage do
    {:ok, ctx} = Context.start_link()
    
    # Define typed variables
    Variables.defvariable!(ctx, :temperature, :float, 0.7,
      constraints: %{min: 0.0, max: 2.0},
      description: "Controls randomness in generation"
    )
    
    Variables.defvariable!(ctx, :max_tokens, :integer, 256,
      constraints: %{min: 1, max: 4096}
    )
    
    Variables.defvariable!(ctx, :model, :string, "gpt-4",
      constraints: %{
        enum: ["gpt-4", "gpt-3.5-turbo", "claude-3", "gemini-pro"]
      }
    )
    
    # Use variables
    temp = Variables.get(ctx, :temperature)
    IO.puts("Current temperature: #{temp}")
    
    # Update with validation
    case Variables.set(ctx, :temperature, 1.5) do
      :ok -> IO.puts("Temperature updated")
      {:error, reason} -> IO.puts("Update failed: #{inspect(reason)}")
    end
    
    # Functional updates
    Variables.update(ctx, :max_tokens, &min(&1 * 2, 4096))
    
    ctx
  end
  
  def batch_operations do
    {:ok, ctx} = Context.start_link()
    
    # Define multiple variables
    for {name, type, value} <- [
      {:learning_rate, :float, 0.001},
      {:batch_size, :integer, 32},
      {:optimizer, :string, "adam"},
      {:use_cuda, :boolean, true}
    ] do
      Variables.defvariable!(ctx, name, type, value)
    end
    
    # Get all at once
    config = Variables.get_many(ctx, [:learning_rate, :batch_size, :optimizer, :use_cuda])
    IO.inspect(config, label: "Training config")
    
    # Update multiple
    Variables.update_many(ctx, %{
      learning_rate: 0.0001,
      batch_size: 64
    })
    
    ctx
  end
  
  def error_handling do
    {:ok, ctx} = Context.start_link()
    
    # Safe operations with defaults
    value = Variables.get(ctx, :missing, "default")
    IO.puts("Got: #{value}")  # "default"
    
    # Explicit error handling
    try do
      Variables.get!(ctx, :missing)
    rescue
      e in DSPex.Variables.VariableNotFoundError ->
        IO.puts("Variable #{e.identifier} not found")
    end
    
    # Validation errors
    Variables.defvariable!(ctx, :percentage, :float, 0.5,
      constraints: %{min: 0.0, max: 1.0}
    )
    
    case Variables.set(ctx, :percentage, 1.5) do
      :ok -> :ok
      {:error, reason} -> 
        IO.puts("Validation failed: #{inspect(reason)}")
    end
    
    ctx
  end
  
  def introspection do
    {:ok, ctx} = Context.start_link()
    
    # Define some variables
    Variables.defvariable!(ctx, :api_key, :string, "sk-...",
      metadata: %{"sensitive" => true}
    )
    
    Variables.defvariable!(ctx, :timeout, :integer, 30,
      constraints: %{min: 1, max: 300},
      description: "Request timeout in seconds"
    )
    
    # List all variables
    IO.puts("\nAll variables:")
    for var <- Variables.list(ctx) do
      IO.puts("  #{var.name} (#{var.type}): #{inspect(var.value)}")
    end
    
    # Get specific information
    IO.puts("\nTimeout type: #{Variables.get_type(ctx, :timeout)}")
    IO.puts("timeout constraints: #{inspect(Variables.get_constraints(ctx, :timeout))}")
    IO.puts("api_key metadata: #{inspect(Variables.get_metadata(ctx, :api_key))}")
    
    # Check existence
    IO.puts("\nExists? timeout: #{Variables.exists?(ctx, :timeout)}")
    IO.puts("Exists? missing: #{Variables.exists?(ctx, :missing)}")
    
    ctx
  end
end
```

## Testing

```elixir
# File: test/dspex/variables_test.exs

defmodule DSPex.VariablesTest do
  use ExUnit.Case, async: true
  
  alias DSPex.{Context, Variables}
  alias DSPex.Variables.{VariableNotFoundError, ValidationError}
  
  setup do
    {:ok, ctx} = Context.start_link()
    {:ok, ctx: ctx}
  end
  
  describe "defvariable/5" do
    test "creates typed variables", %{ctx: ctx} do
      assert {:ok, var_id} = Variables.defvariable(ctx, :test, :string, "hello")
      assert String.starts_with?(var_id, "var_")
      
      assert Variables.get(ctx, :test) == "hello"
    end
    
    test "enforces constraints", %{ctx: ctx} do
      assert {:ok, _} = Variables.defvariable(ctx, :score, :float, 0.5,
        constraints: %{min: 0.0, max: 1.0}
      )
      
      # Valid update
      assert :ok = Variables.set(ctx, :score, 0.8)
      
      # Invalid update
      assert {:error, _} = Variables.set(ctx, :score, 1.5)
    end
    
    test "bang variant raises", %{ctx: ctx} do
      var_id = Variables.defvariable!(ctx, :bang, :integer, 42)
      assert is_binary(var_id)
      
      # Try to create duplicate
      assert_raise ArgumentError, ~r/Failed to define variable/, fn ->
        Variables.defvariable!(ctx, :bang, :integer, 100)
      end
    end
  end
  
  describe "get/3 and get!/2" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :exists, :string, "value")
      :ok
    end
    
    test "get returns value or default", %{ctx: ctx} do
      assert Variables.get(ctx, :exists) == "value"
      assert Variables.get(ctx, :missing) == nil
      assert Variables.get(ctx, :missing, "default") == "default"
    end
    
    test "get! raises on missing", %{ctx: ctx} do
      assert Variables.get!(ctx, :exists) == "value"
      
      assert_raise VariableNotFoundError, ~r/Variable not found: :missing/, fn ->
        Variables.get!(ctx, :missing)
      end
    end
  end
  
  describe "update/4" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :counter, :integer, 0)
      :ok
    end
    
    test "applies function to current value", %{ctx: ctx} do
      assert :ok = Variables.update(ctx, :counter, &(&1 + 1))
      assert Variables.get(ctx, :counter) == 1
      
      assert :ok = Variables.update(ctx, :counter, &(&1 * 2))
      assert Variables.get(ctx, :counter) == 2
    end
    
    test "returns error for missing variable", %{ctx: ctx} do
      assert {:error, :not_found} = Variables.update(ctx, :missing, &(&1 + 1))
    end
    
    test "validates new value", %{ctx: ctx} do
      Variables.defvariable!(ctx, :limited, :integer, 5,
        constraints: %{max: 10}
      )
      
      # This would exceed constraint
      assert {:error, _} = Variables.update(ctx, :limited, &(&1 * 3))
    end
  end
  
  describe "batch operations" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :a, :integer, 1)
      Variables.defvariable!(ctx, :b, :integer, 2)
      Variables.defvariable!(ctx, :c, :integer, 3)
      :ok
    end
    
    test "get_many returns found variables", %{ctx: ctx} do
      values = Variables.get_many(ctx, [:a, :b, :missing])
      
      assert values == %{a: 1, b: 2}
      assert not Map.has_key?(values, :missing)
    end
    
    test "update_many updates multiple variables", %{ctx: ctx} do
      assert :ok = Variables.update_many(ctx, %{a: 10, b: 20})
      
      assert Variables.get(ctx, :a) == 10
      assert Variables.get(ctx, :b) == 20
      assert Variables.get(ctx, :c) == 3  # Unchanged
    end
    
    test "update_many handles partial failures", %{ctx: ctx} do
      Variables.defvariable!(ctx, :constrained, :integer, 5,
        constraints: %{max: 10}
      )
      
      # One update will fail
      result = Variables.update_many(ctx, %{
        a: 100,
        constrained: 50  # Exceeds max
      })
      
      assert {:error, {:partial_failure, _}} = result
      assert Variables.get(ctx, :a) == 100  # Updated
      assert Variables.get(ctx, :constrained) == 5  # Not updated
    end
  end
  
  describe "introspection" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :typed, :float, 3.14,
        constraints: %{min: 0},
        metadata: %{"unit" => "radians"}
      )
      :ok
    end
    
    test "list returns all variables", %{ctx: ctx} do
      vars = Variables.list(ctx)
      assert length(vars) == 1
      
      var = hd(vars)
      assert var.name == :typed
      assert var.type == :float
      assert var.value == 3.14
    end
    
    test "get_type returns variable type", %{ctx: ctx} do
      assert Variables.get_type(ctx, :typed) == :float
      assert Variables.get_type(ctx, :missing) == nil
    end
    
    test "get_constraints returns constraints", %{ctx: ctx} do
      assert Variables.get_constraints(ctx, :typed) == %{min: 0}
      assert Variables.get_constraints(ctx, :missing) == nil
    end
    
    test "get_metadata returns metadata", %{ctx: ctx} do
      meta = Variables.get_metadata(ctx, :typed)
      assert meta["unit"] == "radians"
    end
    
    test "exists? checks existence", %{ctx: ctx} do
      assert Variables.exists?(ctx, :typed) == true
      assert Variables.exists?(ctx, :missing) == false
    end
  end
  
  describe "delete operations" do
    setup %{ctx: ctx} do
      Variables.defvariable!(ctx, :deleteme, :string, "temp")
      :ok
    end
    
    test "delete removes variable", %{ctx: ctx} do
      assert Variables.exists?(ctx, :deleteme)
      assert :ok = Variables.delete(ctx, :deleteme)
      assert not Variables.exists?(ctx, :deleteme)
    end
    
    test "delete returns error for missing", %{ctx: ctx} do
      assert {:error, :not_found} = Variables.delete(ctx, :missing)
    end
    
    test "delete! raises on missing", %{ctx: ctx} do
      assert_raise VariableNotFoundError, fn ->
        Variables.delete!(ctx, :missing)
      end
    end
  end
end
```

## Design Philosophy

1. **Convenience First**: Common operations should be simple
2. **Safe Defaults**: Return nil/default rather than crash
3. **Explicit Errors**: Bang functions for when you need them
4. **Batch Efficiency**: Encourage batch operations
5. **Type Safety**: Validate at definition time

## Performance Tips

- Use batch operations for multiple variables
- Cache frequently accessed values locally
- Define constraints to catch errors early
- Use atoms for variable names when possible

## Next Steps

After implementing DSPex.Variables:
1. Create integration tests with Context
2. Add more convenience functions as needed
3. Document common patterns
4. Create Python variable integration
5. Build example applications