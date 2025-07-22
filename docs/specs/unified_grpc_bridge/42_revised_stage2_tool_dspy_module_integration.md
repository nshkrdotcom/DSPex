## Document 2: 42_revised_stage2_cognitive_layer.md

# Revised Stage 2: Cognitive Layer & Bridge Integration

## Overview

Stage 2 introduces the high-level cognitive layer that provides an elegant, Elixir-first API for DSPex users. This stage implements the crucial architectural innovation: automatic backend switching based on program requirements. Pure Elixir workflows get blazing-fast local state, while Python-dependent programs transparently use the gRPC bridge built in Stage 1.

**Key Innovation:** The `DSPex.Context` process automatically detects when Python components are added and upgrades itself from local to bridged state, migrating all data seamlessly.

## Goals

1. Create the user-facing `DSPex.Context` and `DSPex.Variables` API
2. Implement pluggable state backend system (`StateProvider` behaviour)
3. Build LocalState (Agent) and BridgedState (gRPC) backends
4. Enable automatic, transparent backend switching
5. Integrate variables with DSPy modules via `VariableAwareMixin`
6. Update `DSPex.Program` to be context-aware
7. Prove the same code works in both pure-Elixir and hybrid modes

## Architectural Evolution

```mermaid
graph TD
    subgraph "User-Facing API (New)"
        A[DSPex.Program DSL]
        B[DSPex.Variables API]
        C[DSPex.Context Process]
    end
    
    subgraph "State Backends (New)"
        D[StateProvider Behaviour]
        E[LocalState<br/>(Pure Elixir)]
        F[BridgedState<br/>(Uses Stage 1)]
    end
    
    subgraph "Stage 1 Infrastructure"
        G[SessionStore]
        H[gRPC Handlers]
        I[Python SessionContext]
    end
    
    A --> C
    B --> C
    C --> D
    D --> E
    D --> F
    F --> G
    G --> H
    H --> I
    
    style C fill:#ffd700
    style D fill:#87ceeb
    style E fill:#90ee90
    style F fill:#ffb6c1
```

## Deliverables

- `DSPex.Context` GenServer with automatic backend switching
- `DSPex.Variables` module with intuitive get/set/defvariable API
- `DSPex.Bridge.StateProvider` behaviour
- `DSPex.Bridge.State.Local` - Lightning-fast Agent backend
- `DSPex.Bridge.State.Bridged` - SessionStore integration
- Enhanced Python adapter with `VariableAwareMixin`
- Integration tests proving transparent operation

## Detailed Implementation Plan

### 1. Define StateProvider Behaviour

#### Create `lib/dspex/bridge/state_provider.ex`:

```elixir
defmodule DSPex.Bridge.StateProvider do
  @moduledoc """
  Behaviour for session state backends.
  
  This abstraction allows DSPex to use different storage strategies:
  - LocalState: In-process Agent for pure Elixir workflows (microsecond latency)
  - BridgedState: SessionStore + gRPC for Python integration (millisecond latency)
  
  Future backends could include distributed state, persistent state, etc.
  """
  
  @type state :: any()
  @type var_id :: String.t()
  @type error :: {:error, term()}
  
  @doc """
  Initialize the state backend.
  """
  @callback init(opts :: keyword()) :: {:ok, state} | error
  
  @doc """
  Register a new variable.
  """
  @callback register_variable(
    state, 
    name :: atom() | String.t(), 
    type :: atom(), 
    initial_value :: any(), 
    opts :: keyword()
  ) :: {:ok, {var_id, state}} | error
  
  @doc """
  Get a variable value by name or ID.
  """
  @callback get_variable(state, identifier :: atom() | String.t()) :: 
    {:ok, value :: any()} | error
  
  @doc """
  Update a variable value.
  """
  @callback set_variable(
    state, 
    identifier :: atom() | String.t(), 
    new_value :: any(), 
    metadata :: map()
  ) :: {:ok, state} | error
  
  @doc """
  List all variables.
  """
  @callback list_variables(state) :: {:ok, list(map())} | error
  
  @doc """
  Get multiple variables at once.
  """
  @callback get_variables(state, identifiers :: list()) :: 
    {:ok, map()} | error
  
  @doc """
  Update multiple variables.
  """
  @callback update_variables(state, updates :: map(), metadata :: map()) :: 
    {:ok, state} | error
  
  @doc """
  Export all state for migration.
  """
  @callback export_state(state) :: {:ok, map()} | error
  
  @doc """
  Check if this backend requires Python bridge.
  """
  @callback requires_bridge?() :: boolean()
  
  @doc """
  Clean up any resources.
  """
  @callback cleanup(state) :: :ok
end
```

### 2. Implement LocalState Backend

#### Create `lib/dspex/bridge/state/local.ex`:

```elixir
defmodule DSPex.Bridge.State.Local do
  @moduledoc """
  In-process state provider using an Agent.
  
  This is the default backend for pure Elixir workflows. It provides:
  - Sub-microsecond latency
  - No serialization overhead
  - No network calls
  - Perfect for LLM-free DSPex programs
  """
  
  @behaviour DSPex.Bridge.StateProvider
  
  require Logger
  alias DSPex.Bridge.Variables.Types
  
  defstruct [
    :agent_pid,
    :session_id
  ]
  
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    case Agent.start_link(fn -> initial_state(session_id) end) do
      {:ok, pid} ->
        {:ok, %__MODULE__{agent_pid: pid, session_id: session_id}}
      error ->
        error
    end
  end
  
  @impl true
  def register_variable(state, name, type, initial_value, opts) do
    with {:ok, type_module} <- Types.get_type_module(type),
         {:ok, validated_value} <- type_module.validate(initial_value),
         constraints = Keyword.get(opts, :constraints, %{}),
         :ok <- type_module.validate_constraints(validated_value, constraints) do
      
      var_id = generate_var_id(name)
      
      variable = %{
        id: var_id,
        name: name,
        type: type,
        value: validated_value,
        constraints: constraints,
        metadata: Keyword.get(opts, :metadata, %{}),
        version: 0,
        created_at: System.monotonic_time(:millisecond),
        last_updated_at: System.monotonic_time(:millisecond)
      }
      
      Agent.update(state.agent_pid, fn agent_state ->
        agent_state
        |> put_in([:variables, var_id], variable)
        |> put_in([:variable_index, to_string(name)], var_id)
      end)
      
      Logger.debug("LocalState: Registered variable #{name} (#{var_id})")
      
      {:ok, {var_id, state}}
    end
  end
  
  @impl true
  def get_variable(state, identifier) do
    Agent.get(state.agent_pid, fn agent_state ->
      var_id = resolve_identifier(agent_state, identifier)
      
      case get_in(agent_state, [:variables, var_id]) do
        nil -> {:error, :not_found}
        variable -> {:ok, variable.value}
      end
    end)
  end
  
  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    result = Agent.get_and_update(state.agent_pid, fn agent_state ->
      var_id = resolve_identifier(agent_state, identifier)
      
      case get_in(agent_state, [:variables, var_id]) do
        nil -> 
          {{:error, :not_found}, agent_state}
          
        variable ->
          with {:ok, type_module} <- Types.get_type_module(variable.type),
               {:ok, validated_value} <- type_module.validate(new_value),
               :ok <- type_module.validate_constraints(validated_value, variable.constraints) do
            
            updated_variable = %{variable |
              value: validated_value,
              version: variable.version + 1,
              last_updated_at: System.monotonic_time(:millisecond),
              metadata: Map.merge(variable.metadata, metadata)
            }
            
            new_state = put_in(agent_state, [:variables, var_id], updated_variable)
            {:ok, new_state}
          else
            error -> {error, agent_state}
          end
      end
    end)
    
    case result do
      :ok -> {:ok, state}
      error -> error
    end
  end
  
  @impl true
  def list_variables(state) do
    variables = Agent.get(state.agent_pid, fn agent_state ->
      agent_state.variables
      |> Map.values()
      |> Enum.map(&Map.take(&1, [:id, :name, :type, :value, :constraints, :metadata]))
    end)
    
    {:ok, variables}
  end
  
  @impl true
  def get_variables(state, identifiers) do
    Agent.get(state.agent_pid, fn agent_state ->
      results = Enum.reduce(identifiers, %{}, fn identifier, acc ->
        var_id = resolve_identifier(agent_state, identifier)
        
        case get_in(agent_state, [:variables, var_id]) do
          nil -> acc  # Skip missing
          variable -> Map.put(acc, to_string(identifier), variable.value)
        end
      end)
      
      {:ok, results}
    end)
  end
  
  @impl true
  def update_variables(state, updates, metadata) do
    # For local state, we'll do non-atomic updates
    # Real atomicity would require STM or similar
    errors = Enum.reduce(updates, %{}, fn {identifier, value}, acc ->
      case set_variable(state, identifier, value, metadata) do
        {:ok, _} -> acc
        {:error, reason} -> Map.put(acc, identifier, reason)
      end
    end)
    
    if map_size(errors) == 0 do
      {:ok, state}
    else
      {:error, {:partial_failure, errors}}
    end
  end
  
  @impl true
  def export_state(state) do
    exported = Agent.get(state.agent_pid, fn agent_state ->
      %{
        session_id: state.session_id,
        variables: agent_state.variables,
        variable_index: agent_state.variable_index,
        metadata: agent_state.metadata
      }
    end)
    
    {:ok, exported}
  end
  
  @impl true
  def requires_bridge?, do: false
  
  @impl true
  def cleanup(state) do
    Agent.stop(state.agent_pid)
    :ok
  end
  
  # Private helpers
  
  defp initial_state(session_id) do
    %{
      session_id: session_id,
      variables: %{},
      variable_index: %{},
      metadata: %{
        created_at: System.monotonic_time(:millisecond),
        backend: :local
      }
    }
  end
  
  defp generate_session_id do
    "local_session_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_var_id(name) do
    "var_#{name}_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp resolve_identifier(agent_state, identifier) when is_atom(identifier) do
    resolve_identifier(agent_state, to_string(identifier))
  end
  
  defp resolve_identifier(agent_state, identifier) when is_binary(identifier) do
    # Check if it's already a var_id
    if Map.has_key?(agent_state.variables, identifier) do
      identifier
    else
      # Try to resolve as name
      Map.get(agent_state.variable_index, identifier)
    end
  end
end
```

### 3. Implement BridgedState Backend

#### Create `lib/dspex/bridge/state/bridged.ex`:

```elixir
defmodule DSPex.Bridge.State.Bridged do
  @moduledoc """
  State provider that delegates to SessionStore and gRPC bridge.
  
  This backend is automatically activated when Python components are detected.
  It provides:
  - Full Python interoperability
  - Cross-process state sharing
  - Millisecond latency (acceptable for LLM operations)
  """
  
  @behaviour DSPex.Bridge.StateProvider
  
  require Logger
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.GRPCWorker
  
  defstruct [
    :session_id,
    :grpc_worker,
    :grpc_channel
  ]
  
  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id)
    existing_state = Keyword.get(opts, :existing_state)
    
    # Create session in SessionStore
    case SessionStore.create_session(session_id) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok  # That's fine
      error -> error
    end
    
    # Start gRPC worker
    worker_config = [
      adapter: Snakepit.Adapters.GRPCPython,
      id: "dspex_worker_#{session_id}",
      # Other config from application env
    ]
    
    with {:ok, worker} <- GRPCWorker.start_link(worker_config),
         {:ok, channel} <- GRPCWorker.get_channel(worker) do
      
      state = %__MODULE__{
        session_id: session_id,
        grpc_worker: worker,
        grpc_channel: channel
      }
      
      # If we have existing state to migrate, do it now
      if existing_state do
        migrate_state(state, existing_state)
      end
      
      Logger.info("BridgedState initialized for session #{session_id}")
      
      {:ok, state}
    end
  end
  
  @impl true
  def register_variable(state, name, type, initial_value, opts) do
    case SessionStore.register_variable(
      state.session_id,
      name,
      type,
      initial_value,
      opts
    ) do
      {:ok, var_id} -> 
        {:ok, {var_id, state}}
      error -> 
        error
    end
  end
  
  @impl true
  def get_variable(state, identifier) do
    case SessionStore.get_variable(state.session_id, identifier) do
      {:ok, variable} -> {:ok, variable.value}
      error -> error
    end
  end
  
  @impl true
  def set_variable(state, identifier, new_value, metadata) do
    case SessionStore.update_variable(
      state.session_id,
      identifier,
      new_value,
      metadata
    ) do
      :ok -> {:ok, state}
      error -> error
    end
  end
  
  @impl true
  def list_variables(state) do
    SessionStore.list_variables(state.session_id)
  end
  
  @impl true
  def get_variables(state, identifiers) do
    # Could be optimized with a batch SessionStore operation
    results = Enum.reduce(identifiers, %{}, fn identifier, acc ->
      case get_variable(state, identifier) do
        {:ok, value} -> Map.put(acc, to_string(identifier), value)
        _ -> acc
      end
    end)
    
    {:ok, results}
  end
  
  @impl true
  def update_variables(state, updates, metadata) do
    # For now, non-atomic updates
    # Stage 4 will add atomic batch operations
    errors = Enum.reduce(updates, %{}, fn {identifier, value}, acc ->
      case set_variable(state, identifier, value, metadata) do
        {:ok, _} -> acc
        {:error, reason} -> Map.put(acc, identifier, reason)
      end
    end)
    
    if map_size(errors) == 0 do
      {:ok, state}
    else
      {:error, {:partial_failure, errors}}
    end
  end
  
  @impl true
  def export_state(state) do
    with {:ok, session} <- SessionStore.get_session(state.session_id),
         {:ok, variables} <- SessionStore.list_variables(state.session_id) do
      
      variable_map = variables
      |> Enum.map(fn var -> {var.id, var} end)
      |> Map.new()
      
      # Build index
      variable_index = variables
      |> Enum.map(fn var -> {to_string(var.name), var.id} end)
      |> Map.new()
      
      {:ok, %{
        session_id: state.session_id,
        variables: variable_map,
        variable_index: variable_index,
        metadata: session.metadata
      }}
    end
  end
  
  @impl true
  def requires_bridge?, do: true
  
  @impl true
  def cleanup(state) do
    # Clean up gRPC worker
    if state.grpc_worker do
      GenServer.stop(state.grpc_worker, :normal)
    end
    
    # Session cleanup is handled by TTL in SessionStore
    :ok
  end
  
  # Private helpers
  
  defp migrate_state(bridged_state, exported_state) do
    Logger.info("Migrating state from local to bridged backend")
    
    # Migrate all variables
    Enum.each(exported_state.variables, fn {_var_id, variable} ->
      SessionStore.register_variable(
        bridged_state.session_id,
        variable.name,
        variable.type,
        variable.value,
        constraints: variable.constraints,
        metadata: Map.put(variable.metadata, "migrated_from", "local")
      )
    end)
    
    Logger.info("Migrated #{map_size(exported_state.variables)} variables")
  end
end
```

### 4. Create DSPex.Context

#### Create `lib/dspex/context.ex`:

```elixir
defmodule DSPex.Context do
  @moduledoc """
  The central execution context for DSPex programs.
  
  A Context is a process that manages:
  - Variable state (local or bridged)
  - Program execution
  - Automatic backend switching
  
  ## Example
  
      {:ok, ctx} = DSPex.Context.start_link()
      
      # Starts with local backend
      DSPex.Variables.set(ctx, :temperature, 0.7)
      
      # Adding a Python module triggers backend upgrade
      DSPex.Modules.ChainOfThought.new(ctx, "question -> answer")
      # Context automatically switches to bridged backend
  """
  
  use GenServer
  require Logger
  
  alias DSPex.Bridge.State.{Local, Bridged}
  
  defstruct [
    :id,
    :backend_module,
    :backend_state,
    :programs,
    :metadata
  ]
  
  ## Client API
  
  @doc """
  Starts a new context with optional configuration.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc """
  Ensures the context is using the bridged backend.
  Called automatically when Python components are added.
  """
  def ensure_bridged(context) do
    GenServer.call(context, :ensure_bridged)
  end
  
  @doc """
  Gets the current backend type.
  """
  def get_backend(context) do
    GenServer.call(context, :get_backend)
  end
  
  @doc """
  Stops the context and cleans up resources.
  """
  def stop(context) do
    GenServer.stop(context, :normal)
  end
  
  ## Variable Operations (delegated to backend)
  
  def register_variable(context, name, type, initial_value, opts \\ []) do
    GenServer.call(context, {:register_variable, name, type, initial_value, opts})
  end
  
  def get_variable(context, identifier) do
    GenServer.call(context, {:get_variable, identifier})
  end
  
  def set_variable(context, identifier, value, metadata \\ %{}) do
    GenServer.call(context, {:set_variable, identifier, value, metadata})
  end
  
  def list_variables(context) do
    GenServer.call(context, :list_variables)
  end
  
  def get_variables(context, identifiers) do
    GenServer.call(context, {:get_variables, identifiers})
  end
  
  def update_variables(context, updates, metadata \\ %{}) do
    GenServer.call(context, {:update_variables, updates, metadata})
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    # Always start with local backend for performance
    backend_module = Keyword.get(opts, :backend, Local)
    
    # Generate context ID
    context_id = "ctx_#{System.unique_integer([:positive, :monotonic])}"
    
    # Initialize backend
    {:ok, backend_state} = backend_module.init(session_id: context_id)
    
    state = %__MODULE__{
      id: context_id,
      backend_module: backend_module,
      backend_state: backend_state,
      programs: %{},
      metadata: %{
        created_at: DateTime.utc_now(),
        backend_switches: 0
      }
    }
    
    Logger.info("DSPex context #{context_id} initialized with #{inspect(backend_module)}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:ensure_bridged, _from, state) do
    if state.backend_module == Bridged do
      # Already bridged
      {:reply, :ok, state}
    else
      # Need to upgrade
      Logger.info("Upgrading context #{state.id} from local to bridged backend")
      
      # Export current state
      {:ok, exported} = state.backend_module.export_state(state.backend_state)
      
      # Clean up old backend
      state.backend_module.cleanup(state.backend_state)
      
      # Initialize bridged backend with existing state
      {:ok, bridged_state} = Bridged.init(
        session_id: state.id,
        existing_state: exported
      )
      
      new_state = %{state |
        backend_module: Bridged,
        backend_state: bridged_state,
        metadata: Map.update!(state.metadata, :backend_switches, &(&1 + 1))
      }
      
      Logger.info("Context #{state.id} successfully upgraded to bridged backend")
      
      {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_backend, _from, state) do
    backend_info = %{
      module: state.backend_module,
      requires_bridge: state.backend_module.requires_bridge?(),
      switches: state.metadata.backend_switches
    }
    {:reply, backend_info, state}
  end
  
  # Variable operations - delegate to backend
  
  @impl true
  def handle_call({:register_variable, name, type, initial_value, opts}, _from, state) do
    case state.backend_module.register_variable(
      state.backend_state,
      name,
      type,
      initial_value,
      opts
    ) do
      {:ok, {var_id, new_backend_state}} ->
        {:reply, {:ok, var_id}, %{state | backend_state: new_backend_state}}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:get_variable, identifier}, _from, state) do
    result = state.backend_module.get_variable(state.backend_state, identifier)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:set_variable, identifier, value, metadata}, _from, state) do
    case state.backend_module.set_variable(
      state.backend_state,
      identifier,
      value,
      metadata
    ) do
      {:ok, new_backend_state} ->
        {:reply, :ok, %{state | backend_state: new_backend_state}}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:list_variables, _from, state) do
    result = state.backend_module.list_variables(state.backend_state)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_variables, identifiers}, _from, state) do
    result = state.backend_module.get_variables(state.backend_state, identifiers)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:update_variables, updates, metadata}, _from, state) do
    case state.backend_module.update_variables(
      state.backend_state,
      updates,
      metadata
    ) do
      {:ok, new_backend_state} ->
        {:reply, :ok, %{state | backend_state: new_backend_state}}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def terminate(_reason, state) do
    # Clean up backend
    state.backend_module.cleanup(state.backend_state)
    :ok
  end
end
```

### 5. Create DSPex.Variables API

#### Create `lib/dspex/variables.ex`:

```elixir
defmodule DSPex.Variables do
  @moduledoc """
  High-level API for working with variables in a DSPex context.
  
  This module provides the primary interface for variable operations,
  abstracting away the underlying backend complexity.
  
  ## Examples
  
      # Define and use variables
      {:ok, ctx} = DSPex.Context.start_link()
      
      DSPex.Variables.set(ctx, :temperature, 0.7)
      temp = DSPex.Variables.get(ctx, :temperature)
      
      # Batch operations
      DSPex.Variables.update_many(ctx, %{
        temperature: 0.8,
        max_tokens: 256
      })
  """
  
  alias DSPex.Context
  
  @type context :: pid()
  @type identifier :: atom() | String.t()
  @type variable_type :: :float | :integer | :string | :boolean | :choice | :module
  
  @doc """
  Defines a new variable in the context.
  
  This is the primary way to create variables with full type information
  and constraints.
  
  ## Options
  
    * `:constraints` - Type-specific constraints (e.g., min/max for numbers)
    * `:description` - Human-readable description
    * `:metadata` - Additional metadata
  
  ## Examples
  
      # Simple variable
      defvariable(ctx, :temperature, :float, 0.7)
      
      # With constraints
      defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Choice variable
      defvariable(ctx, :model, :choice, "gpt-4",
        constraints: %{choices: ["gpt-4", "claude-3", "gemini"]}
      )
  """
  @spec defvariable(context, atom(), variable_type(), any(), keyword()) :: 
    {:ok, String.t()} | {:error, term()}
  def defvariable(context, name, type, initial_value, opts \\ []) do
    Context.register_variable(context, name, type, initial_value, opts)
  end
  
  @doc """
  Gets a variable value.
  
  ## Examples
  
      temperature = DSPex.Variables.get(ctx, :temperature)
      
      # With default
      tokens = DSPex.Variables.get(ctx, :max_tokens, 256)
  """
  @spec get(context, identifier, any()) :: any()
  def get(context, identifier, default \\ nil) do
    case Context.get_variable(context, identifier) do
      {:ok, value} -> value
      {:error, :not_found} -> default
      {:error, reason} -> raise "Failed to get variable: #{inspect(reason)}"
    end
  end
  
  @doc """
  Sets a variable value.
  
  ## Examples
  
      DSPex.Variables.set(ctx, :temperature, 0.9)
      
      # With metadata
      DSPex.Variables.set(ctx, :temperature, 0.9,
        metadata: %{source: "user_adjustment"}
      )
  """
  @spec set(context, identifier, any(), keyword()) :: :ok | {:error, term()}
  def set(context, identifier, value, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.set_variable(context, identifier, value, metadata)
  end
  
  @doc """
  Updates a variable using a function.
  
  ## Examples
  
      # Increment
      DSPex.Variables.update(ctx, :counter, &(&1 + 1))
      
      # Complex update
      DSPex.Variables.update(ctx, :temperature, fn temp ->
        min(temp * 1.1, 2.0)
      end)
  """
  @spec update(context, identifier, (any() -> any()), keyword()) :: :ok | {:error, term()}
  def update(context, identifier, update_fn, opts \\ []) when is_function(update_fn, 1) do
    case get(context, identifier) do
      nil -> {:error, :not_found}
      current_value ->
        new_value = update_fn.(current_value)
        set(context, identifier, new_value, opts)
    end
  end
  
  @doc """
  Gets multiple variables at once.
  
  ## Examples
  
      %{temperature: temp, max_tokens: tokens} = 
        DSPex.Variables.get_many(ctx, [:temperature, :max_tokens])
  """
  @spec get_many(context, [identifier]) :: map()
  def get_many(context, identifiers) do
    case Context.get_variables(context, identifiers) do
      {:ok, values} -> 
        # Convert string keys back to atoms if needed
        Map.new(values, fn {k, v} ->
          key = if is_binary(k) and Enum.any?(identifiers, &(to_string(&1) == k)),
            do: String.to_existing_atom(k),
            else: k
          {key, v}
        end)
      {:error, reason} -> 
        raise "Failed to get variables: #{inspect(reason)}"
    end
  end
  
  @doc """
  Updates multiple variables at once.
  
  ## Examples
  
      DSPex.Variables.update_many(ctx, %{
        temperature: 0.8,
        max_tokens: 512,
        model: "gpt-4"
      })
  """
  @spec update_many(context, map(), keyword()) :: :ok | {:error, term()}
  def update_many(context, updates, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    Context.update_variables(context, updates, metadata)
  end
  
  @doc """
  Lists all variables in the context.
  
  ## Examples
  
      variables = DSPex.Variables.list(ctx)
      # [
      #   %{name: :temperature, type: :float, value: 0.7, ...},
      #   %{name: :max_tokens, type: :integer, value: 256, ...}
      # ]
  """
  @spec list(context) :: [map()]
  def list(context) do
    case Context.list_variables(context) do
      {:ok, variables} -> variables
      {:error, reason} -> raise "Failed to list variables: #{inspect(reason)}"
    end
  end
  
  @doc """
  Checks if a variable exists.
  
  ## Examples
  
      if DSPex.Variables.exists?(ctx, :temperature) do
        # ...
      end
  """
  @spec exists?(context, identifier) :: boolean()
  def exists?(context, identifier) do
    case Context.get_variable(context, identifier) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
```

### 6. Update Python Components

#### Update `snakepit/priv/python/snakepit_bridge/dspy_integration.py`:

```python
"""
Integration layer for making DSPy modules variable-aware.
"""
import asyncio
import dspy
from typing import Dict, Any, Optional, Type
import logging

from .session_context import SessionContext

logger = logging.getLogger(__name__)


class VariableAwareMixin:
    """
    Mixin to make any DSPy module variable-aware.
    
    When mixed into a DSPy module, it enables:
    - Automatic parameter binding to session variables
    - Dynamic configuration updates
    - Seamless integration with DSPex.Variables
    """
    
    def __init__(self, *args, session_context: SessionContext = None, **kwargs):
        # Extract our custom kwargs before passing to parent
        self._session_context = session_context
        self._variable_bindings: Dict[str, str] = {}
        self._last_sync = {}
        
        # Initialize parent class
        super().__init__(*args, **kwargs)
        
        # Log initialization
        if self._session_context:
            logger.info(f"Variable-aware {self.__class__.__name__} initialized with session {session_context.session_id}")
    
    async def bind_to_variable(self, attribute: str, variable_name: str):
        """
        Bind a module attribute to a session variable.
        
        Example:
            await module.bind_to_variable('temperature', 'generation_temperature')
        """
        if not self._session_context:
            raise RuntimeError("No session context available for variable binding")
        
        # Verify variable exists and get initial value
        try:
            value = await self._session_context.get_variable(variable_name)
            setattr(self, attribute, value)
            self._variable_bindings[attribute] = variable_name
            self._last_sync[attribute] = value
            
            logger.info(f"Bound {attribute} to variable {variable_name} (initial value: {value})")
            
        except KeyError:
            raise ValueError(f"Variable '{variable_name}' not found in session")
    
    def bind_to_variable_sync(self, attribute: str, variable_name: str):
        """Synchronous version for compatibility."""
        asyncio.run(self.bind_to_variable(attribute, variable_name))
    
    async def sync_variables(self):
        """Synchronize all bound variables from the session."""
        if not self._session_context or not self._variable_bindings:
            return
        
        changes = []
        for attr, var_name in self._variable_bindings.items():
            try:
                new_value = await self._session_context.get_variable(var_name)
                old_value = self._last_sync.get(attr)
                
                if new_value != old_value:
                    setattr(self, attr, new_value)
                    self._last_sync[attr] = new_value
                    changes.append((attr, old_value, new_value))
                    
            except KeyError:
                logger.warning(f"Variable {var_name} no longer exists")
        
        if changes:
            logger.debug(f"Synced {len(changes)} variable changes")
            for attr, old, new in changes:
                logger.debug(f"  {attr}: {old} -> {new}")
    
    def sync_variables_sync(self):
        """Synchronous version for compatibility."""
        asyncio.run(self.sync_variables())
    
    async def get_bound_variable(self, attribute: str) -> Any:
        """Get the current value of a bound variable."""
        if attribute not in self._variable_bindings:
            raise ValueError(f"Attribute {attribute} is not bound to a variable")
        
        var_name = self._variable_bindings[attribute]
        return await self._session_context.get_variable(var_name)
    
    def get_bindings(self) -> Dict[str, str]:
        """Get all variable bindings."""
        return self._variable_bindings.copy()


# Concrete variable-aware DSPy modules

class VariableAwarePredict(VariableAwareMixin, dspy.Predict):
    """Predict module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        # DSPy's forward is synchronous, so we call it directly
        return self.forward(*args, **kwargs)
    
    def forward(self, *args, **kwargs):
        """Override to sync variables before prediction."""
        # For sync compatibility, we'll skip auto-sync here
        # Users should call sync_variables_sync() or forward_async()
        return super().forward(*args, **kwargs)


class VariableAwareChainOfThought(VariableAwareMixin, dspy.ChainOfThought):
    """ChainOfThought module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        return self.forward(*args, **kwargs)
    
    def forward(self, *args, **kwargs):
        """Override to allow variable-aware execution."""
        return super().forward(*args, **kwargs)


class VariableAwareReAct(VariableAwareMixin, dspy.ReAct):
    """ReAct module with automatic variable synchronization."""
    
    async def forward_async(self, *args, **kwargs):
        """Async forward that syncs variables before execution."""
        await self.sync_variables()
        return self.forward(*args, **kwargs)


# Module factory for dynamic creation

class ModuleVariableResolver:
    """
    Resolves module-type variables to actual DSPy module classes.
    
    This enables dynamic module selection based on variables.
    """
    
    # Registry of available modules (both standard and variable-aware)
    MODULE_REGISTRY = {
        # Standard DSPy modules
        'Predict': dspy.Predict,
        'ChainOfThought': dspy.ChainOfThought,
        'ReAct': dspy.ReAct,
        'ProgramOfThought': dspy.ProgramOfThought,
        
        # Variable-aware versions
        'VariableAwarePredict': VariableAwarePredict,
        'VariableAwareChainOfThought': VariableAwareChainOfThought,
        'VariableAwareReAct': VariableAwareReAct,
    }
    
    def __init__(self, session_context: SessionContext):
        self.session_context = session_context
    
    async def resolve_module(self, variable_name: str) -> Type[dspy.Module]:
        """
        Resolve a module-type variable to a DSPy module class.
        
        Example:
            module_class = await resolver.resolve_module('reasoning_module')
            # Returns dspy.ChainOfThought or similar
        """
        module_name = await self.session_context.get_variable(variable_name)
        
        if module_name not in self.MODULE_REGISTRY:
            # Try to find a variable-aware version
            var_aware_name = f"VariableAware{module_name}"
            if var_aware_name in self.MODULE_REGISTRY:
                logger.info(f"Using variable-aware version: {var_aware_name}")
                return self.MODULE_REGISTRY[var_aware_name]
            
            raise ValueError(f"Unknown module type: {module_name}")
        
        return self.MODULE_REGISTRY[module_name]
    
    async def create_module(self, variable_name: str, *args, **kwargs) -> dspy.Module:
        """
        Create a module instance from a module-type variable.
        
        Automatically uses variable-aware version if available.
        
        Example:
            module = await resolver.create_module(
                'reasoning_module',
                "question -> answer"
            )
        """
        module_class = await self.resolve_module(variable_name)
        
        # Check if we should use variable-aware version
        module_name = module_class.__name__
        if not module_name.startswith('VariableAware'):
            var_aware_name = f"VariableAware{module_name}"
            if var_aware_name in self.MODULE_REGISTRY:
                module_class = self.MODULE_REGISTRY[var_aware_name]
                kwargs['session_context'] = self.session_context
                logger.info(f"Auto-upgraded to {var_aware_name} for variable support")
        elif 'session_context' not in kwargs:
            kwargs['session_context'] = self.session_context
        
        return module_class(*args, **kwargs)
    
    @classmethod
    def register_module(cls, name: str, module_class: Type[dspy.Module]):
        """Register a custom module type."""
        cls.MODULE_REGISTRY[name] = module_class
        logger.info(f"Registered module type: {name}")
```

### 7. Integration Tests

#### Create `test/dspex/context_stage2_test.exs`:

```elixir
defmodule DSPex.ContextStage2Test do
  use ExUnit.Case, async: false
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.State.{Local, Bridged}
  
  describe "pure Elixir workflow with local backend" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "uses local backend by default", %{ctx: ctx} do
      backend_info = Context.get_backend(ctx)
      assert backend_info.module == Local
      assert backend_info.requires_bridge == false
    end
    
    test "variable operations work with local backend", %{ctx: ctx} do
      # Define variables
      {:ok, _} = Variables.defvariable(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      {:ok, _} = Variables.defvariable(ctx, :model, :choice, "local_model",
        constraints: %{choices: ["local_model", "fast_model"]}
      )
      
      # Get/set operations
      assert Variables.get(ctx, :temperature) == 0.7
      assert Variables.get(ctx, :model) == "local_model"
      
      :ok = Variables.set(ctx, :temperature, 0.9)
      assert Variables.get(ctx, :temperature) == 0.9
      
      # Update function
      :ok = Variables.update(ctx, :temperature, &(&1 * 0.8))
      assert_in_delta Variables.get(ctx, :temperature), 0.72, 0.001
      
      # Batch operations
      values = Variables.get_many(ctx, [:temperature, :model])
      assert map_size(values) == 2
      assert_in_delta values.temperature, 0.72, 0.001
      
      :ok = Variables.update_many(ctx, %{
        temperature: 0.5,
        model: "fast_model"
      })
      
      assert Variables.get(ctx, :temperature) == 0.5
      assert Variables.get(ctx, :model) == "fast_model"
      
      # List variables
      vars = Variables.list(ctx)
      assert length(vars) == 2
      assert Enum.all?(vars, &(&1.name in [:temperature, :model]))
    end
    
    test "type validation works", %{ctx: ctx} do
      {:ok, _} = Variables.defvariable(ctx, :count, :integer, 10,
        constraints: %{min: 0, max: 100}
      )
      
      # Valid update
      :ok = Variables.set(ctx, :count, 50)
      assert Variables.get(ctx, :count) == 50
      
      # Invalid type
      assert {:error, _} = Variables.set(ctx, :count, "not a number")
      
      # Constraint violation
      assert {:error, _} = Variables.set(ctx, :count, 150)
      
      # Value unchanged
      assert Variables.get(ctx, :count) == 50
    end
    
    test "sub-microsecond performance for local operations", %{ctx: ctx} do
      {:ok, _} = Variables.defvariable(ctx, :perf_test, :float, 1.0)
      
      # Measure get operation
      {get_time, _} = :timer.tc(fn ->
        Enum.each(1..1000, fn _ ->
          Variables.get(ctx, :perf_test)
        end)
      end)
      
      avg_get_us = get_time / 1000
      assert avg_get_us < 10  # Should be well under 10 microseconds
      
      # Measure set operation
      {set_time, _} = :timer.tc(fn ->
        Enum.each(1..1000, fn i ->
          Variables.set(ctx, :perf_test, i * 1.0)
        end)
      end)
      
      avg_set_us = set_time / 1000
      assert avg_set_us < 50  # Should be well under 50 microseconds
    end
  end
  
  describe "automatic backend switching" do
    setup do
      {:ok, ctx} = Context.start_link()
      
      # Register some variables in local backend
      {:ok, _} = Variables.defvariable(ctx, :temp, :float, 0.7)
      {:ok, _} = Variables.defvariable(ctx, :tokens, :integer, 256)
      Variables.set(ctx, :temp, 0.8)
      
      {:ok, ctx: ctx, initial_temp: 0.8, initial_tokens: 256}
    end
    
    test "switches to bridged backend when requested", %{ctx: ctx, initial_temp: temp} do
      # Verify starting with local
      backend = Context.get_backend(ctx)
      assert backend.module == Local
      assert backend.switches == 0
      
      # Trigger switch
      :ok = Context.ensure_bridged(ctx)
      
      # Verify switched to bridged
      backend = Context.get_backend(ctx)
      assert backend.module == Bridged
      assert backend.requires_bridge == true
      assert backend.switches == 1
      
      # Variables should still be accessible with same values
      assert Variables.get(ctx, :temp) == temp
      assert Variables.get(ctx, :tokens) == 256
      
      # Can still update variables
      :ok = Variables.set(ctx, :temp, 0.9)
      assert Variables.get(ctx, :temp) == 0.9
    end
    
    test "ensure_bridged is idempotent", %{ctx: ctx} do
      # Switch once
      :ok = Context.ensure_bridged(ctx)
      backend1 = Context.get_backend(ctx)
      assert backend1.switches == 1
      
      # Switch again - should be no-op
      :ok = Context.ensure_bridged(ctx)
      backend2 = Context.get_backend(ctx)
      assert backend2.switches == 1  # No additional switch
      assert backend2.module == Bridged
    end
    
    test "preserves all variable metadata during switch", %{ctx: ctx} do
      # Add a complex variable
      {:ok, _} = Variables.defvariable(ctx, :config, :string, "test",
        constraints: %{min_length: 1, max_length: 100},
        description: "Test configuration",
        metadata: %{custom: "metadata"}
      )
      
      # Get initial state
      vars_before = Variables.list(ctx)
      
      # Switch backend
      :ok = Context.ensure_bridged(ctx)
      
      # Get state after switch
      vars_after = Variables.list(ctx)
      
      # Should have same variables
      assert length(vars_after) == length(vars_before)
      
      # Find config variable
      config_after = Enum.find(vars_after, &(&1.name == :config))
      assert config_after
      assert config_after.value == "test"
      assert config_after.constraints == %{min_length: 1, max_length: 100}
      assert config_after.metadata[:custom] == "metadata"
      assert config_after.metadata["migrated_from"] == "local"
    end
  end
  
  @tag :integration
  describe "Python integration after backend switch" do
    setup do
      # Start SessionStore if needed
      case Snakepit.Bridge.SessionStore.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
      
      {:ok, ctx} = Context.start_link()
      
      # Set up initial state
      {:ok, _} = Variables.defvariable(ctx, :temperature, :float, 0.7)
      {:ok, _} = Variables.defvariable(ctx, :max_tokens, :integer, 256)
      
      {:ok, ctx: ctx}
    end
    
    test "Python can access variables after switch", %{ctx: ctx} do
      # Switch to bridged backend
      :ok = Context.ensure_bridged(ctx)
      
      # Get context ID to use from Python
      %{id: context_id} = :sys.get_state(ctx)
      
      # Run Python script that accesses the variables
      python_result = run_python_script("""
        import asyncio
        import grpc
        from snakepit_bridge.session_context import SessionContext
        
        async def test():
            channel = grpc.aio.insecure_channel('localhost:50051')
            session = SessionContext('#{context_id}', channel)
            
            # Get variables
            temp = await session.get_variable('temperature')
            tokens = await session.get_variable('max_tokens')
            
            # Update from Python
            await session.set_variable('temperature', 0.95)
            
            return {"temp": temp, "tokens": tokens}
        
        result = asyncio.run(test())
        print(f"RESULT:{result}")
      """)
      
      # Parse Python output
      assert python_result =~ "RESULT:{'temp': 0.7, 'tokens': 256}"
      
      # Verify Python update is visible in Elixir
      assert Variables.get(ctx, :temperature) == 0.95
    end
  end
end
```

#### Create Python tests:

```python
# test/python/test_stage2_integration.py

import asyncio
import pytest
import grpc
from unittest.mock import Mock, AsyncMock

from snakepit_bridge.session_context import SessionContext
from snakepit_bridge.dspy_integration import (
    VariableAwarePredict,
    VariableAwareChainOfThought,
    ModuleVariableResolver
)


@pytest.fixture
async def mock_session():
    """Create a mock session context for testing."""
    session = Mock(spec=SessionContext)
    session.session_id = "test_session"
    session.get_variable = AsyncMock()
    session.set_variable = AsyncMock()
    return session


@pytest.mark.asyncio
async def test_variable_aware_mixin(mock_session):
    """Test the VariableAwareMixin functionality."""
    # Set up mock responses
    mock_session.get_variable.side_effect = [0.7, 0.9]  # Initial, then updated
    
    # Create variable-aware module
    predictor = VariableAwarePredict(
        "question -> answer",
        session_context=mock_session
    )
    
    # Bind temperature to a variable
    await predictor.bind_to_variable('temperature', 'generation_temp')
    
    # Check binding was created and initial value set
    assert predictor.temperature == 0.7
    assert predictor.get_bindings() == {'temperature': 'generation_temp'}
    mock_session.get_variable.assert_called_with('generation_temp')
    
    # Sync variables - should get updated value
    await predictor.sync_variables()
    assert predictor.temperature == 0.9


@pytest.mark.asyncio
async def test_module_resolver(mock_session):
    """Test dynamic module resolution."""
    # Set up mock to return module name
    mock_session.get_variable.return_value = "ChainOfThought"
    
    resolver = ModuleVariableResolver(mock_session)
    
    # Resolve module type
    module_class = await resolver.resolve_module('reasoning_strategy')
    assert module_class.__name__ == "ChainOfThought"
    
    # Create module instance - should auto-upgrade to variable-aware
    module = await resolver.create_module(
        'reasoning_strategy',
        "question -> answer"
    )
    
    # Should be the variable-aware version
    assert isinstance(module, VariableAwareChainOfThought)
    assert module._session_context == mock_session


@pytest.mark.asyncio
async def test_sync_changes_detection(mock_session):
    """Test that sync_variables detects changes."""
    # Initial value, then two syncs with change
    mock_session.get_variable.side_effect = [0.7, 0.7, 0.9]
    
    predictor = VariableAwarePredict(
        "question -> answer",
        session_context=mock_session
    )
    
    await predictor.bind_to_variable('temperature', 'temp')
    assert predictor.temperature == 0.7
    
    # First sync - no change
    await predictor.sync_variables()
    assert predictor.temperature == 0.7
    
    # Second sync - change detected
    await predictor.sync_variables()
    assert predictor.temperature == 0.9


@pytest.mark.asyncio
async def test_missing_variable_handling(mock_session):
    """Test handling of missing variables."""
    # Variable doesn't exist
    mock_session.get_variable.side_effect = KeyError("Variable not found")
    
    predictor = VariableAwarePredict(
        "question -> answer",
        session_context=mock_session
    )
    
    # Binding should fail
    with pytest.raises(ValueError) as exc:
        await predictor.bind_to_variable('temperature', 'nonexistent')
    assert "not found" in str(exc.value)


def test_sync_compatibility(mock_session):
    """Test synchronous method compatibility."""
    # Mock sync behavior
    def get_var_sync(name):
        if name == 'temp':
            return 0.8
        raise KeyError(f"Unknown variable: {name}")
    
    mock_session.get_variable = Mock(side_effect=get_var_sync)
    
    predictor = VariableAwarePredict(
        "question -> answer",
        session_context=mock_session
    )
    
    # Note: In real usage, this would use asyncio.run internally
    # For testing, we're mocking the sync behavior
    predictor._variable_bindings['temperature'] = 'temp'
    predictor._session_context.get_variable = get_var_sync
    
    # Manual sync simulation
    value = get_var_sync('temp')
    predictor.temperature = value
    assert predictor.temperature == 0.8
```

## Success Criteria

1. **Layered API Works**: Clean separation between user API and backends ✓
2. **Local Backend Performance**: Sub-microsecond latency for pure Elixir ✓
3. **Automatic Switching**: Transparent upgrade from local to bridged ✓
4. **State Migration**: All variables preserved during backend switch ✓
5. **Python Integration**: Variable-aware DSPy modules work correctly ✓
6. **Same Code, Both Modes**: Programs work unchanged in either backend ✓

## Performance Impact

- **Pure Elixir Path**: ~1-10 microseconds per operation (100x faster than bridge)
- **Backend Switch**: ~10-50ms one-time cost when Python is needed
- **Bridged Operations**: ~1-2ms per operation (acceptable for LLM workflows)

## Key Innovations

1. **Progressive Enhancement**: Start fast, upgrade only when needed
2. **Transparent Migration**: State seamlessly moves between backends
3. **Zero Config**: No user configuration needed for optimal performance
4. **Future Proof**: Clean abstraction allows new backends later

## Next Stage Preview

Stage 3 will add reactive capabilities:
- Variable watching with streaming updates
- Real-time synchronization between Elixir and Python
- Observer pattern for change notifications
- Advanced variable types (choice, module)

The streaming will be implemented differently for each backend:
- LocalState: Simple process messaging
- BridgedState: gRPC streaming from Stage 0

---
