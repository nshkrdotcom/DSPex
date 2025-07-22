# Prompt: Define the StateProvider Behaviour

## Objective
Create the `StateProvider` behaviour that defines the contract for all state backends. This abstraction enables DSPex to seamlessly switch between different storage strategies based on program requirements.

## Context
The StateProvider behaviour is the foundation of Stage 2's automatic backend switching. It allows DSPex to use:
- LocalState: In-process Agent for pure Elixir workflows (microsecond latency)
- BridgedState: SessionStore + gRPC for Python integration (millisecond latency)
- Future backends: Distributed state, persistent state, etc.

## Requirements

### Core Operations
1. State initialization and cleanup
2. Variable CRUD operations
3. Batch operations for efficiency
4. State export for migration
5. Backend capability detection

### Design Principles
- Consistent API across all backends
- Support for atomic operations where possible
- Efficient batch operations
- Clean resource management
- Metadata preservation

## Implementation

### Create the StateProvider Behaviour

```elixir
# File: lib/dspex/bridge/state_provider.ex

defmodule DSPex.Bridge.StateProvider do
  @moduledoc """
  Behaviour for session state backends.
  
  This abstraction allows DSPex to use different storage strategies:
  - LocalState: In-process Agent for pure Elixir workflows (microsecond latency)
  - BridgedState: SessionStore + gRPC for Python integration (millisecond latency)
  
  Future backends could include distributed state, persistent state, etc.
  
  ## Implementing a Backend
  
  A backend must implement all callbacks and maintain consistency between
  operations. The state type is backend-specific and opaque to callers.
  
  ## Example Implementation
  
      defmodule MyBackend do
        @behaviour DSPex.Bridge.StateProvider
        
        defstruct [:storage]
        
        @impl true
        def init(opts) do
          {:ok, %__MODULE__{storage: %{}}}
        end
        
        @impl true
        def register_variable(state, name, type, value, opts) do
          # Implementation
        end
        
        # ... other callbacks
      end
  """
  
  @type state :: any()
  @type var_id :: String.t()
  @type identifier :: atom() | String.t()
  @type error :: {:error, term()}
  
  @doc """
  Initialize the state backend.
  
  ## Options
  
    * `:session_id` - The session identifier
    * `:existing_state` - Optional state to import (for migrations)
    * Backend-specific options
  
  ## Returns
  
    * `{:ok, state}` - Successfully initialized with opaque state
    * `{:error, reason}` - Initialization failed
  """
  @callback init(opts :: keyword()) :: {:ok, state} | error
  
  @doc """
  Register a new variable.
  
  Creates a new variable with the given name, type, and initial value.
  Type validation and constraint checking should be performed.
  
  ## Parameters
  
    * `state` - The backend state
    * `name` - Variable name (atom or string)
    * `type` - Variable type atom (e.g., :float, :integer)
    * `initial_value` - The initial value
    * `opts` - Options including:
      * `:constraints` - Type-specific constraints
      * `:metadata` - Additional metadata
      * `:description` - Human-readable description
  
  ## Returns
  
    * `{:ok, {var_id, new_state}}` - Variable created with ID
    * `{:error, reason}` - Creation failed
  """
  @callback register_variable(
    state, 
    name :: identifier, 
    type :: atom(), 
    initial_value :: any(), 
    opts :: keyword()
  ) :: {:ok, {var_id, state}} | error
  
  @doc """
  Get a variable value by name or ID.
  
  ## Parameters
  
    * `state` - The backend state
    * `identifier` - Variable name or ID
  
  ## Returns
  
    * `{:ok, value}` - The current value
    * `{:error, :not_found}` - Variable doesn't exist
    * `{:error, reason}` - Other error
  """
  @callback get_variable(state, identifier) :: 
    {:ok, value :: any()} | error
  
  @doc """
  Update a variable value.
  
  Type validation and constraint checking should be performed.
  The variable's version should be incremented.
  
  ## Parameters
  
    * `state` - The backend state
    * `identifier` - Variable name or ID
    * `new_value` - The new value
    * `metadata` - Metadata for this update
  
  ## Returns
  
    * `{:ok, new_state}` - Successfully updated
    * `{:error, :not_found}` - Variable doesn't exist
    * `{:error, reason}` - Validation or other error
  """
  @callback set_variable(
    state, 
    identifier, 
    new_value :: any(), 
    metadata :: map()
  ) :: {:ok, state} | error
  
  @doc """
  List all variables.
  
  Returns a list of all variables with their metadata.
  The exact structure is backend-specific but should include
  at least: id, name, type, value, constraints, metadata.
  
  ## Returns
  
    * `{:ok, variables}` - List of variable maps
    * `{:error, reason}` - Failed to list
  """
  @callback list_variables(state) :: {:ok, list(map())} | error
  
  @doc """
  Get multiple variables at once.
  
  Batch operation for efficiency. Returns all found variables.
  Missing variables are silently skipped.
  
  ## Parameters
  
    * `state` - The backend state
    * `identifiers` - List of variable names or IDs
  
  ## Returns
  
    * `{:ok, values}` - Map of identifier => value for found variables
    * `{:error, reason}` - Failed to get variables
  """
  @callback get_variables(state, identifiers :: list(identifier)) :: 
    {:ok, map()} | error
  
  @doc """
  Update multiple variables.
  
  Batch operation for efficiency. Backends should implement this
  as atomically as possible, but may fall back to sequential updates.
  
  ## Parameters
  
    * `state` - The backend state
    * `updates` - Map of identifier => new_value
    * `metadata` - Metadata for all updates
  
  ## Returns
  
    * `{:ok, new_state}` - All updates succeeded
    * `{:error, {:partial_failure, errors}}` - Some updates failed
    * `{:error, reason}` - Complete failure
  """
  @callback update_variables(state, updates :: map(), metadata :: map()) :: 
    {:ok, state} | error
  
  @doc """
  Delete a variable.
  
  ## Parameters
  
    * `state` - The backend state
    * `identifier` - Variable name or ID
  
  ## Returns
  
    * `{:ok, new_state}` - Successfully deleted
    * `{:error, :not_found}` - Variable doesn't exist
    * `{:error, reason}` - Deletion failed
  """
  @callback delete_variable(state, identifier) :: 
    {:ok, state} | error
  
  @doc """
  Export all state for migration.
  
  Returns the complete state in a format suitable for importing
  into another backend. Used for transparent backend switching.
  
  The returned map should include:
    * `:session_id` - The session identifier
    * `:variables` - Map of var_id => variable data
    * `:variable_index` - Map of name => var_id
    * `:metadata` - Session metadata
  
  ## Returns
  
    * `{:ok, exported_state}` - Complete state export
    * `{:error, reason}` - Export failed
  """
  @callback export_state(state) :: {:ok, map()} | error
  
  @doc """
  Import state from another backend.
  
  Used during backend migration to restore state.
  
  ## Parameters
  
    * `state` - The backend state
    * `exported_state` - State exported from another backend
  
  ## Returns
  
    * `{:ok, new_state}` - Successfully imported
    * `{:error, reason}` - Import failed
  """
  @callback import_state(state, exported_state :: map()) :: 
    {:ok, state} | error
  
  @doc """
  Check if this backend requires Python bridge.
  
  Used by DSPex.Context to determine if backend switching is needed.
  
  ## Returns
  
    * `true` - Requires Python bridge (e.g., BridgedState)
    * `false` - Pure Elixir backend (e.g., LocalState)
  """
  @callback requires_bridge?() :: boolean()
  
  @doc """
  Get backend capabilities.
  
  Returns information about what this backend supports.
  
  ## Returns
  
  Map with capability flags:
    * `:atomic_updates` - Supports truly atomic batch updates
    * `:streaming` - Supports change streaming (Stage 3)
    * `:persistence` - Data survives process restart
    * `:distribution` - Works across nodes
  """
  @callback capabilities() :: map()
  
  @doc """
  Clean up any resources.
  
  Called when the backend is no longer needed. Should release
  all resources (processes, connections, etc.).
  
  ## Returns
  
    * `:ok` - Cleanup successful
  """
  @callback cleanup(state) :: :ok
  
  ## Optional Callbacks
  
  @doc """
  Subscribe to variable changes (Stage 3).
  
  Optional callback for backends that support streaming.
  
  ## Parameters
  
    * `state` - The backend state
    * `pattern` - Variable name pattern (supports wildcards)
    * `subscriber` - Process to receive notifications
  
  ## Returns
  
    * `{:ok, subscription_ref}` - Successfully subscribed
    * `{:error, :not_supported}` - Backend doesn't support streaming
    * `{:error, reason}` - Subscription failed
  """
  @callback subscribe(state, pattern :: String.t(), subscriber :: pid()) ::
    {:ok, reference()} | error
  @optional_callbacks subscribe: 3
  
  @doc """
  Unsubscribe from variable changes (Stage 3).
  
  ## Parameters
  
    * `state` - The backend state
    * `subscription_ref` - Reference returned by subscribe/3
  
  ## Returns
  
    * `:ok` - Successfully unsubscribed
    * `{:error, reason}` - Unsubscribe failed
  """
  @callback unsubscribe(state, subscription_ref :: reference()) ::
    :ok | error
  @optional_callbacks unsubscribe: 2
  
  ## Helper Functions
  
  @doc """
  Checks if a module implements the StateProvider behaviour.
  """
  @spec is_provider?(module()) :: boolean()
  def is_provider?(module) do
    DSPex.Bridge.StateProvider in Keyword.get(
      module.__info__(:attributes), 
      :behaviour, 
      []
    )
  end
  
  @doc """
  Gets the capabilities of a provider module.
  """
  @spec get_capabilities(module()) :: map()
  def get_capabilities(module) when is_atom(module) do
    if is_provider?(module) do
      module.capabilities()
    else
      raise ArgumentError, "#{inspect(module)} is not a StateProvider"
    end
  end
  
  @doc """
  Validates that all required callbacks are exported.
  """
  @spec validate_provider!(module()) :: :ok
  def validate_provider!(module) do
    required_callbacks = [
      {:init, 1},
      {:register_variable, 5},
      {:get_variable, 2},
      {:set_variable, 4},
      {:list_variables, 1},
      {:get_variables, 2},
      {:update_variables, 3},
      {:delete_variable, 2},
      {:export_state, 1},
      {:import_state, 2},
      {:requires_bridge?, 0},
      {:capabilities, 0},
      {:cleanup, 1}
    ]
    
    missing = for {fun, arity} <- required_callbacks,
                  not function_exported?(module, fun, arity),
                  do: {fun, arity}
    
    if missing != [] do
      raise ArgumentError, """
      #{inspect(module)} is missing required StateProvider callbacks:
      #{inspect(missing)}
      """
    end
    
    :ok
  end
end
```

## Usage Example

```elixir
defmodule Example do
  def demo do
    # Initialize a backend
    {:ok, state} = MyBackend.init(session_id: "test_session")
    
    # Register a variable
    {:ok, {var_id, state}} = MyBackend.register_variable(
      state,
      :temperature,
      :float,
      0.7,
      constraints: %{min: 0.0, max: 2.0}
    )
    
    # Get the value
    {:ok, value} = MyBackend.get_variable(state, :temperature)
    
    # Update the value
    {:ok, state} = MyBackend.set_variable(state, :temperature, 0.9, %{})
    
    # Batch operations
    {:ok, values} = MyBackend.get_variables(state, [:temperature, :max_tokens])
    
    {:ok, state} = MyBackend.update_variables(
      state,
      %{temperature: 0.8, max_tokens: 512},
      %{source: "batch_update"}
    )
    
    # Export for migration
    {:ok, exported} = MyBackend.export_state(state)
    
    # Clean up
    :ok = MyBackend.cleanup(state)
  end
end
```

## Testing StateProvider Implementations

```elixir
# File: test/support/state_provider_test.ex

defmodule DSPex.Bridge.StateProviderTest do
  @moduledoc """
  Shared tests for StateProvider implementations.
  
  Use this module in your backend tests:
  
      defmodule MyBackendTest do
        use DSPex.Bridge.StateProviderTest, provider: MyBackend
      end
  """
  
  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    
    quote do
      use ExUnit.Case, async: true
      
      @provider unquote(provider)
      
      describe "StateProvider compliance for #{@provider}" do
        test "implements all required callbacks" do
          assert DSPex.Bridge.StateProvider.validate_provider!(@provider) == :ok
        end
        
        test "basic variable lifecycle" do
          {:ok, state} = @provider.init(session_id: "test")
          
          # Register
          assert {:ok, {var_id, state}} = @provider.register_variable(
            state, :test_var, :string, "hello", []
          )
          assert is_binary(var_id)
          
          # Get
          assert {:ok, "hello"} = @provider.get_variable(state, :test_var)
          assert {:ok, "hello"} = @provider.get_variable(state, var_id)
          
          # Update
          assert {:ok, state} = @provider.set_variable(state, :test_var, "world", %{})
          assert {:ok, "world"} = @provider.get_variable(state, :test_var)
          
          # Delete
          assert {:ok, state} = @provider.delete_variable(state, :test_var)
          assert {:error, :not_found} = @provider.get_variable(state, :test_var)
          
          # Cleanup
          assert :ok = @provider.cleanup(state)
        end
        
        test "batch operations" do
          {:ok, state} = @provider.init(session_id: "test")
          
          # Register multiple
          {:ok, {_, state}} = @provider.register_variable(state, :a, :integer, 1, [])
          {:ok, {_, state}} = @provider.register_variable(state, :b, :integer, 2, [])
          {:ok, {_, state}} = @provider.register_variable(state, :c, :integer, 3, [])
          
          # Batch get
          assert {:ok, values} = @provider.get_variables(state, [:a, :b, :c])
          assert values[:a] == 1
          assert values[:b] == 2
          assert values[:c] == 3
          
          # Batch update
          assert {:ok, state} = @provider.update_variables(
            state,
            %{a: 10, b: 20, c: 30},
            %{}
          )
          
          assert {:ok, 10} = @provider.get_variable(state, :a)
          assert {:ok, 20} = @provider.get_variable(state, :b)
          assert {:ok, 30} = @provider.get_variable(state, :c)
          
          :ok = @provider.cleanup(state)
        end
        
        test "export and import state" do
          {:ok, state1} = @provider.init(session_id: "test")
          
          # Create some state
          {:ok, {_, state1}} = @provider.register_variable(state1, :x, :float, 3.14, [])
          {:ok, {_, state1}} = @provider.register_variable(state1, :y, :string, "test", [])
          
          # Export
          assert {:ok, exported} = @provider.export_state(state1)
          assert exported.session_id == "test"
          assert map_size(exported.variables) == 2
          
          # Import into new backend
          {:ok, state2} = @provider.init(session_id: "test2")
          assert {:ok, state2} = @provider.import_state(state2, exported)
          
          # Verify imported state
          assert {:ok, 3.14} = @provider.get_variable(state2, :x)
          assert {:ok, "test"} = @provider.get_variable(state2, :y)
          
          :ok = @provider.cleanup(state1)
          :ok = @provider.cleanup(state2)
        end
        
        test "capabilities and metadata" do
          caps = @provider.capabilities()
          assert is_map(caps)
          assert is_boolean(caps[:atomic_updates])
          assert is_boolean(caps[:streaming])
          
          assert is_boolean(@provider.requires_bridge?())
        end
      end
    end
  end
end
```

## Design Decisions

1. **Opaque State Type**: Each backend defines its own state structure
2. **Batch Operations**: Essential for performance with remote backends
3. **Export/Import**: Enables transparent backend switching
4. **Optional Streaming**: Prepared for Stage 3 without requiring it
5. **Capability Detection**: Allows Context to make intelligent decisions

## Error Handling

- Use tagged tuples consistently: `{:ok, result}` or `{:error, reason}`
- Provide descriptive error reasons
- `:not_found` for missing variables
- `{:partial_failure, errors}` for batch operations
- Type and constraint errors should be informative

## Next Steps

After implementing the StateProvider behaviour:
1. Implement LocalState backend (fast Agent-based)
2. Implement BridgedState backend (SessionStore integration)
3. Create DSPex.Context that uses these backends
4. Add comprehensive tests for both backends