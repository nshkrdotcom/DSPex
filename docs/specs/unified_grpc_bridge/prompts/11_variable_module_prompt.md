# Prompt: Create Variable Module and Extend Session

## Objective
Create a proper Variable module as a first-class entity and extend the Session structure to support variables alongside programs. This establishes the foundation for all variable operations.

## Context
The Variable module needs to be well-designed as it will be used throughout the system. The Session extension must maintain backward compatibility while adding variable support.

## Requirements

### Variable Module Features
1. Comprehensive struct with all necessary fields
2. Helper functions for common operations
3. Version management
4. Metadata handling
5. Future optimization status tracking

### Session Extension Requirements
1. Store variables by ID
2. Maintain name-to-ID index for fast lookups
3. Support both atom and string identifiers
4. Preserve existing program functionality

## Implementation Steps

### 1. Create the Variable Module

```elixir
# File: snakepit/lib/snakepit/bridge/variables/variable.ex

defmodule Snakepit.Bridge.Variables.Variable do
  @moduledoc """
  Variable struct and related functions.
  
  Variables are typed, versioned values that can be synchronized
  between Elixir and Python processes. They form the core of the
  DSPex state management system.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t() | atom(),
    type: atom(),
    value: any(),
    constraints: map(),
    metadata: map(),
    version: integer(),
    created_at: integer(),
    last_updated_at: integer(),
    optimization_status: map(),
    access_rules: list()
  }
  
  @enforce_keys [:id, :name, :type, :value, :created_at]
  defstruct [
    :id,
    :name,
    :type,
    :value,
    constraints: %{},
    metadata: %{},
    version: 0,
    created_at: nil,
    last_updated_at: nil,
    optimization_status: %{
      optimizing: false,
      optimizer_id: nil,
      optimizer_pid: nil,
      started_at: nil
    },
    access_rules: []  # For future Stage 4
  ]
  
  @doc """
  Creates a new variable with validation.
  
  ## Examples
      
      iex> Variable.new(%{
      ...>   id: "var_temp_123",
      ...>   name: :temperature,
      ...>   type: :float,
      ...>   value: 0.7,
      ...>   created_at: System.monotonic_time(:second)
      ...> })
      %Variable{...}
  """
  def new(attrs) when is_map(attrs) do
    # Ensure required fields
    required = [:id, :name, :type, :value, :created_at]
    missing = required -- Map.keys(attrs)
    
    if missing != [] do
      raise ArgumentError, "Missing required fields: #{inspect(missing)}"
    end
    
    # Set last_updated_at if not provided
    attrs = Map.put_new(attrs, :last_updated_at, attrs.created_at)
    
    struct!(__MODULE__, attrs)
  end
  
  @doc """
  Updates a variable's value and increments version.
  
  ## Options
    * `:metadata` - Additional metadata to merge
    * `:source` - Source of the update (defaults to :elixir)
  """
  @spec update_value(t(), any(), keyword()) :: t()
  def update_value(%__MODULE__{} = variable, new_value, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    source = Keyword.get(opts, :source, :elixir)
    
    now = System.monotonic_time(:second)
    
    %{variable |
      value: new_value,
      version: variable.version + 1,
      last_updated_at: now,
      metadata: Map.merge(variable.metadata, Map.merge(metadata, %{
        "source" => to_string(source),
        "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }))
    }
  end
  
  @doc """
  Checks if a variable is currently being optimized.
  """
  @spec optimizing?(t()) :: boolean()
  def optimizing?(%__MODULE__{optimization_status: status}) do
    status.optimizing == true
  end
  
  @doc """
  Marks a variable as being optimized.
  """
  @spec start_optimization(t(), String.t(), pid()) :: t()
  def start_optimization(%__MODULE__{} = variable, optimizer_id, optimizer_pid) do
    %{variable |
      optimization_status: %{
        optimizing: true,
        optimizer_id: optimizer_id,
        optimizer_pid: optimizer_pid,
        started_at: System.monotonic_time(:second)
      }
    }
  end
  
  @doc """
  Clears optimization status.
  """
  @spec end_optimization(t()) :: t()
  def end_optimization(%__MODULE__{} = variable) do
    %{variable |
      optimization_status: %{
        optimizing: false,
        optimizer_id: nil,
        optimizer_pid: nil,
        started_at: nil
      }
    }
  end
  
  @doc """
  Converts variable to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = variable) do
    %{
      id: variable.id,
      name: to_string(variable.name),
      type: variable.type,
      value: variable.value,
      constraints: variable.constraints,
      metadata: variable.metadata,
      version: variable.version,
      created_at: variable.created_at,
      last_updated_at: variable.last_updated_at,
      optimizing: variable.optimization_status.optimizing
    }
  end
  
  @doc """
  Gets the age of the variable in seconds.
  """
  @spec age(t()) :: integer()
  def age(%__MODULE__{created_at: created_at}) do
    System.monotonic_time(:second) - created_at
  end
  
  @doc """
  Gets time since last update in seconds.
  """
  @spec time_since_update(t()) :: integer()
  def time_since_update(%__MODULE__{last_updated_at: last_updated}) do
    System.monotonic_time(:second) - last_updated
  end
end
```

### 2. Extend the Session Module

```elixir
# File: snakepit/lib/snakepit/bridge/session.ex

defmodule Snakepit.Bridge.Session do
  @moduledoc """
  Session data structure for centralized session management.
  
  Extended in Stage 1 to support variables alongside programs.
  Variables are stored by ID with a name index for fast lookups.
  """
  
  alias Snakepit.Bridge.Variables.Variable

  @type t :: %__MODULE__{
    id: String.t(),
    programs: map(),
    variables: %{String.t() => Variable.t()},
    variable_index: %{String.t() => String.t()}, # name -> id mapping
    metadata: map(),
    created_at: integer(),
    last_accessed: integer(),
    last_worker_id: String.t() | nil,
    ttl: integer(),
    stats: map()
  }

  @enforce_keys [:id, :created_at, :ttl]
  defstruct [
    :id,
    :created_at,
    :last_accessed,
    :last_worker_id,
    :ttl,
    programs: %{},
    variables: %{},
    variable_index: %{},
    metadata: %{},
    stats: %{
      variable_count: 0,
      program_count: 0,
      total_variable_updates: 0
    }
  ]
  
  @doc """
  Creates a new session with the given ID and options.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id) do
    now = System.monotonic_time(:second)
    ttl = Keyword.get(opts, :ttl, 3600) # 1 hour default
    metadata = Keyword.get(opts, :metadata, %{})
    
    %__MODULE__{
      id: id,
      created_at: now,
      last_accessed: now,
      ttl: ttl,
      metadata: metadata
    }
  end

  @doc """
  Adds or updates a variable in the session.
  
  Updates both the variables map and the name index.
  Also updates session statistics.
  """
  @spec put_variable(t(), String.t(), Variable.t()) :: t()
  def put_variable(%__MODULE__{} = session, var_id, %Variable{} = variable) 
      when is_binary(var_id) do
    # Check if it's an update
    is_update = Map.has_key?(session.variables, var_id)
    
    # Update variables map
    variables = Map.put(session.variables, var_id, variable)
    
    # Update name index
    variable_index = Map.put(session.variable_index, to_string(variable.name), var_id)
    
    # Update stats
    stats = if is_update do
      %{session.stats | total_variable_updates: session.stats.total_variable_updates + 1}
    else
      %{session.stats | 
        variable_count: session.stats.variable_count + 1,
        total_variable_updates: session.stats.total_variable_updates + 1
      }
    end
    
    %{session | 
      variables: variables, 
      variable_index: variable_index,
      stats: stats
    }
  end

  @doc """
  Gets a variable by ID or name.
  
  Supports both atom and string identifiers. Names are resolved
  through the variable index for O(1) lookup.
  """
  @spec get_variable(t(), String.t() | atom()) :: {:ok, Variable.t()} | {:error, :not_found}
  def get_variable(%__MODULE__{} = session, identifier) when is_atom(identifier) do
    get_variable(session, to_string(identifier))
  end
  
  def get_variable(%__MODULE__{} = session, identifier) when is_binary(identifier) do
    # First check if it's a direct ID
    case Map.get(session.variables, identifier) do
      nil ->
        # Try to resolve as a name through the index
        case Map.get(session.variable_index, identifier) do
          nil -> 
            {:error, :not_found}
          var_id -> 
            # Get by resolved ID
            case Map.get(session.variables, var_id) do
              nil -> {:error, :not_found}  # Shouldn't happen
              variable -> {:ok, variable}
            end
        end
      variable -> 
        {:ok, variable}
    end
  end

  @doc """
  Removes a variable from the session.
  """
  @spec delete_variable(t(), String.t() | atom()) :: t()
  def delete_variable(%__MODULE__{} = session, identifier) do
    case get_variable(session, identifier) do
      {:ok, variable} ->
        # Remove from variables
        variables = Map.delete(session.variables, variable.id)
        
        # Remove from index
        variable_index = Map.delete(session.variable_index, to_string(variable.name))
        
        # Update stats
        stats = %{session.stats | variable_count: session.stats.variable_count - 1}
        
        %{session | 
          variables: variables, 
          variable_index: variable_index,
          stats: stats
        }
        
      {:error, :not_found} ->
        session
    end
  end

  @doc """
  Lists all variables in the session.
  
  Returns them sorted by creation time (oldest first).
  """
  @spec list_variables(t()) :: [Variable.t()]
  def list_variables(%__MODULE__{} = session) do
    session.variables
    |> Map.values()
    |> Enum.sort_by(& &1.created_at)
  end
  
  @doc """
  Lists variables matching a pattern.
  
  Supports wildcards: "temp_*" matches "temp_1", "temp_2", etc.
  """
  @spec list_variables(t(), String.t()) :: [Variable.t()]
  def list_variables(%__MODULE__{} = session, pattern) when is_binary(pattern) do
    regex = pattern
    |> String.replace("*", ".*")
    |> Regex.compile!()
    
    session.variables
    |> Map.values()
    |> Enum.filter(fn var ->
      Regex.match?(regex, to_string(var.name))
    end)
    |> Enum.sort_by(& &1.created_at)
  end
  
  @doc """
  Checks if a variable exists by name or ID.
  """
  @spec has_variable?(t(), String.t() | atom()) :: boolean()
  def has_variable?(%__MODULE__{} = session, identifier) do
    case get_variable(session, identifier) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end
  
  @doc """
  Gets all variable names in the session.
  """
  @spec variable_names(t()) :: [String.t()]
  def variable_names(%__MODULE__{} = session) do
    Map.keys(session.variable_index)
  end
  
  @doc """
  Updates the last_accessed timestamp.
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = session) do
    %{session | last_accessed: System.monotonic_time(:second)}
  end
  
  @doc """
  Checks if the session has expired based on TTL.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{last_accessed: last_accessed, ttl: ttl}) do
    age = System.monotonic_time(:second) - last_accessed
    age > ttl
  end
  
  @doc """
  Gets session statistics.
  """
  @spec get_stats(t()) :: map()
  def get_stats(%__MODULE__{} = session) do
    Map.merge(session.stats, %{
      age: System.monotonic_time(:second) - session.created_at,
      time_since_access: System.monotonic_time(:second) - session.last_accessed,
      total_items: session.stats.variable_count + session.stats.program_count
    })
  end
  
  # Program-related functions remain unchanged
  
  @doc """
  Stores a program in the session.
  """
  @spec put_program(t(), String.t(), map()) :: t()
  def put_program(%__MODULE__{} = session, id, program) when is_binary(id) do
    is_update = Map.has_key?(session.programs, id)
    programs = Map.put(session.programs, id, program)
    
    stats = if not is_update do
      %{session.stats | program_count: session.stats.program_count + 1}
    else
      session.stats
    end
    
    %{session | programs: programs, stats: stats}
  end
  
  @doc """
  Gets a program by ID.
  """
  @spec get_program(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_program(%__MODULE__{} = session, id) when is_binary(id) do
    case Map.get(session.programs, id) do
      nil -> {:error, :not_found}
      program -> {:ok, program}
    end
  end
  
  @doc """
  Lists all programs in the session.
  """
  @spec list_programs(t()) :: [map()]
  def list_programs(%__MODULE__{} = session) do
    Map.values(session.programs)
  end
end
```

### 3. Create Supporting Types

```elixir
# File: snakepit/lib/snakepit/bridge/variables.ex

defmodule Snakepit.Bridge.Variables do
  @moduledoc """
  Main entry point for variable-related functionality.
  
  This module provides convenience functions and acts as the
  public API for variable operations.
  """
  
  alias Snakepit.Bridge.Variables.{Variable, Types}
  
  @doc """
  Lists all supported variable types.
  """
  @spec supported_types() :: [atom()]
  def supported_types do
    Types.list_types()
  end
  
  @doc """
  Validates a value against a type and constraints.
  """
  @spec validate(any(), atom(), map()) :: {:ok, any()} | {:error, String.t()}
  def validate(value, type, constraints \\ %{}) do
    with {:ok, type_module} <- Types.get_type_module(type),
         {:ok, validated} <- type_module.validate(value),
         :ok <- type_module.validate_constraints(validated, constraints) do
      {:ok, validated}
    end
  end
  
  @doc """
  Creates a properly typed variable.
  """
  @spec create_variable(map()) :: {:ok, Variable.t()} | {:error, term()}
  def create_variable(attrs) do
    with {:ok, type_module} <- Types.get_type_module(attrs.type),
         {:ok, validated_value} <- type_module.validate(attrs.value),
         constraints = Map.get(attrs, :constraints, %{}),
         :ok <- type_module.validate_constraints(validated_value, constraints) do
      
      variable = Variable.new(Map.put(attrs, :value, validated_value))
      {:ok, variable}
    end
  end
end
```

## Testing the Implementation

### Unit Tests for Variable Module

```elixir
# File: test/snakepit/bridge/variables/variable_test.exs

defmodule Snakepit.Bridge.Variables.VariableTest do
  use ExUnit.Case, async: true
  
  alias Snakepit.Bridge.Variables.Variable
  
  describe "new/1" do
    test "creates variable with required fields" do
      attrs = %{
        id: "var_test_123",
        name: :test_var,
        type: :float,
        value: 3.14,
        created_at: System.monotonic_time(:second)
      }
      
      variable = Variable.new(attrs)
      
      assert variable.id == "var_test_123"
      assert variable.name == :test_var
      assert variable.type == :float
      assert variable.value == 3.14
      assert variable.version == 0
      assert variable.last_updated_at == variable.created_at
    end
    
    test "raises on missing required fields" do
      assert_raise ArgumentError, ~r/Missing required fields/, fn ->
        Variable.new(%{name: :test})
      end
    end
  end
  
  describe "update_value/3" do
    setup do
      variable = Variable.new(%{
        id: "var_1",
        name: :counter,
        type: :integer,
        value: 0,
        created_at: System.monotonic_time(:second)
      })
      
      {:ok, variable: variable}
    end
    
    test "increments version", %{variable: variable} do
      updated = Variable.update_value(variable, 1)
      assert updated.version == 1
      assert updated.value == 1
      
      updated2 = Variable.update_value(updated, 2)
      assert updated2.version == 2
      assert updated2.value == 2
    end
    
    test "updates timestamp", %{variable: variable} do
      Process.sleep(10)
      updated = Variable.update_value(variable, 1)
      assert updated.last_updated_at > variable.created_at
    end
    
    test "merges metadata", %{variable: variable} do
      updated = Variable.update_value(variable, 1, metadata: %{"reason" => "test"})
      assert updated.metadata["reason"] == "test"
      assert updated.metadata["source"] == "elixir"
    end
  end
end
```

### Unit Tests for Session Extensions

```elixir
# File: test/snakepit/bridge/session_test.exs

defmodule Snakepit.Bridge.SessionTest do
  use ExUnit.Case, async: true
  
  alias Snakepit.Bridge.Session
  alias Snakepit.Bridge.Variables.Variable
  
  describe "variable operations" do
    setup do
      session = Session.new("test_session")
      {:ok, session: session}
    end
    
    test "put and get variable", %{session: session} do
      variable = Variable.new(%{
        id: "var_1",
        name: :my_var,
        type: :string,
        value: "hello",
        created_at: System.monotonic_time(:second)
      })
      
      session = Session.put_variable(session, "var_1", variable)
      
      # Get by ID
      assert {:ok, fetched} = Session.get_variable(session, "var_1")
      assert fetched.value == "hello"
      
      # Get by name (string)
      assert {:ok, fetched} = Session.get_variable(session, "my_var")
      assert fetched.value == "hello"
      
      # Get by name (atom)
      assert {:ok, fetched} = Session.get_variable(session, :my_var)
      assert fetched.value == "hello"
    end
    
    test "variable not found", %{session: session} do
      assert {:error, :not_found} = Session.get_variable(session, "nonexistent")
      assert {:error, :not_found} = Session.get_variable(session, :nonexistent)
    end
    
    test "list variables", %{session: session} do
      # Add multiple variables
      vars = for i <- 1..3 do
        Variable.new(%{
          id: "var_#{i}",
          name: "var_#{i}",
          type: :integer,
          value: i,
          created_at: System.monotonic_time(:second) + i
        })
      end
      
      session = Enum.reduce(vars, session, fn var, sess ->
        Session.put_variable(sess, var.id, var)
      end)
      
      listed = Session.list_variables(session)
      assert length(listed) == 3
      assert Enum.map(listed, & &1.value) == [1, 2, 3]
    end
    
    test "pattern matching", %{session: session} do
      # Add variables with pattern
      vars = [
        Variable.new(%{id: "1", name: "temp_cpu", type: :float, value: 45.0, created_at: 1}),
        Variable.new(%{id: "2", name: "temp_gpu", type: :float, value: 60.0, created_at: 2}),
        Variable.new(%{id: "3", name: "memory_used", type: :integer, value: 1024, created_at: 3})
      ]
      
      session = Enum.reduce(vars, session, fn var, sess ->
        Session.put_variable(sess, var.id, var)
      end)
      
      # Match pattern
      temps = Session.list_variables(session, "temp_*")
      assert length(temps) == 2
      assert Enum.all?(temps, fn v -> String.starts_with?(to_string(v.name), "temp_") end)
    end
    
    test "session stats", %{session: session} do
      assert session.stats.variable_count == 0
      
      # Add variable
      var = Variable.new(%{
        id: "var_1",
        name: :test,
        type: :integer,
        value: 1,
        created_at: 1
      })
      
      session = Session.put_variable(session, "var_1", var)
      assert session.stats.variable_count == 1
      assert session.stats.total_variable_updates == 1
      
      # Update variable
      updated_var = Variable.update_value(var, 2)
      session = Session.put_variable(session, "var_1", updated_var)
      assert session.stats.variable_count == 1
      assert session.stats.total_variable_updates == 2
    end
  end
end
```

## Key Implementation Notes

1. **Variable Module Design**:
   - Immutable updates (functional style)
   - Rich metadata support
   - Version tracking built-in
   - Optimization status for future use

2. **Session Extensions**:
   - Dual storage (by ID with name index)
   - Support for both atoms and strings
   - Pattern matching for listing
   - Statistics tracking

3. **Performance Considerations**:
   - O(1) lookups by both ID and name
   - Minimal memory overhead for index
   - Efficient batch operations

4. **Future-Proofing**:
   - Access rules field for Stage 4
   - Optimization status for coordinated updates
   - Extensible metadata system

## Files to Create/Modify

1. Create: `snakepit/lib/snakepit/bridge/variables/variable.ex`
2. Modify: `snakepit/lib/snakepit/bridge/session.ex`
3. Create: `snakepit/lib/snakepit/bridge/variables.ex`
4. Create: `test/snakepit/bridge/variables/variable_test.exs`
5. Create/Update: `test/snakepit/bridge/session_test.exs`

## Next Steps

After implementing the Variable module and Session extensions:
1. Run the unit tests to verify correctness
2. Ensure no regressions in existing Session functionality
3. Proceed to implement SessionStore extensions (next prompt)