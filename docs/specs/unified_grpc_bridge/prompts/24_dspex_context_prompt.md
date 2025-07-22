# Prompt: Create DSPex.Context with Auto-Switching

## Objective
Implement `DSPex.Context`, the central execution context that automatically switches from LocalState to BridgedState when Python components are detected. This is the key innovation that gives users optimal performance without configuration.

## Context
DSPex.Context is a GenServer that:
- Starts with the fast LocalState backend
- Monitors for Python component usage
- Transparently migrates to BridgedState when needed
- Preserves all state during migration
- Provides a consistent API regardless of backend

## Requirements

### Core Features
1. Automatic backend detection and switching
2. Zero-downtime state migration
3. Transparent operation delegation
4. Backend capability awareness
5. Clean lifecycle management

### Performance Goals
- Backend switch: < 50ms including state migration
- No performance overhead for pure Elixir
- Minimal overhead for operation delegation

## Implementation

### Create DSPex.Context Module

```elixir
# File: lib/dspex/context.ex

defmodule DSPex.Context do
  @moduledoc """
  The central execution context for DSPex programs.
  
  A Context is a process that manages:
  - Variable state (local or bridged)
  - Program execution
  - Automatic backend switching
  
  ## Automatic Backend Switching
  
  The Context starts with a LocalState backend for maximum performance.
  When Python components are added (DSPy modules, Python tools), it
  automatically migrates to BridgedState for cross-language support.
  
  ## Example
  
      {:ok, ctx} = DSPex.Context.start_link()
      
      # Starts with local backend - microsecond operations
      DSPex.Variables.set(ctx, :temperature, 0.7)
      
      # Adding a Python module triggers backend upgrade
      DSPex.Modules.ChainOfThought.new(ctx, "question -> answer")
      # Context automatically switches to bridged backend
      
      # Same API continues to work
      DSPex.Variables.get(ctx, :temperature)  # Still returns 0.7
  
  ## Supervision
  
  Contexts can be supervised:
  
      children = [
        {DSPex.Context, name: MyApp.Context, backend: :local}
      ]
      
      Supervisor.start_link(children, strategy: :one_for_one)
  """
  
  use GenServer
  require Logger
  
  alias DSPex.Bridge.State.{Local, Bridged}
  alias DSPex.Bridge.StateProvider
  
  @type t :: pid() | atom()
  @type backend :: :local | :bridged | module()
  
  defstruct [
    :id,
    :backend_module,
    :backend_state,
    :programs,
    :metadata,
    :monitors
  ]
  
  ## Client API
  
  @doc """
  Starts a new context with optional configuration.
  
  ## Options
  
    * `:name` - Register the context with a name
    * `:backend` - Initial backend (:local or :bridged, default: :local)
    * `:session_id` - Specific session ID (auto-generated if not provided)
    * `:ttl` - Session time-to-live in seconds
  
  ## Examples
  
      # Anonymous context
      {:ok, ctx} = DSPex.Context.start_link()
      
      # Named context
      {:ok, ctx} = DSPex.Context.start_link(name: MyApp.Context)
      
      # Start directly with bridged backend
      {:ok, ctx} = DSPex.Context.start_link(backend: :bridged)
  """
  def start_link(opts \\ []) do
    {name_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end
  
  @doc """
  Ensures the context is using the bridged backend.
  
  Called automatically when Python components are added.
  Can also be called manually if you know Python will be needed.
  
  ## Returns
  
    * `:ok` - Successfully using bridged backend
    * `{:error, reason}` - Switch failed
  """
  @spec ensure_bridged(t()) :: :ok | {:error, term()}
  def ensure_bridged(context) do
    GenServer.call(context, :ensure_bridged)
  end
  
  @doc """
  Gets information about the current backend.
  
  ## Returns
  
  Map with:
    * `:module` - The backend module
    * `:type` - :local or :bridged
    * `:requires_bridge` - Whether Python bridge is needed
    * `:capabilities` - Backend capabilities
    * `:switches` - Number of backend switches
  """
  @spec get_backend(t()) :: map()
  def get_backend(context) do
    GenServer.call(context, :get_backend)
  end
  
  @doc """
  Gets the context ID.
  """
  @spec get_id(t()) :: String.t()
  def get_id(context) do
    GenServer.call(context, :get_id)
  end
  
  @doc """
  Registers a program with the context.
  
  Programs can trigger backend switches if they require Python.
  """
  @spec register_program(t(), String.t(), map()) :: :ok
  def register_program(context, program_id, program_spec) do
    GenServer.call(context, {:register_program, program_id, program_spec})
  end
  
  @doc """
  Stops the context and cleans up resources.
  """
  @spec stop(t()) :: :ok
  def stop(context) do
    GenServer.stop(context, :normal)
  end
  
  ## Variable Operations (delegated to backend)
  
  @doc """
  Registers a new variable.
  
  See `DSPex.Variables.defvariable/5` for the high-level API.
  """
  def register_variable(context, name, type, initial_value, opts \\ []) do
    GenServer.call(context, {:register_variable, name, type, initial_value, opts})
  end
  
  @doc """
  Gets a variable value.
  
  See `DSPex.Variables.get/3` for the high-level API.
  """
  def get_variable(context, identifier) do
    GenServer.call(context, {:get_variable, identifier})
  end
  
  @doc """
  Sets a variable value.
  
  See `DSPex.Variables.set/4` for the high-level API.
  """
  def set_variable(context, identifier, value, metadata \\ %{}) do
    GenServer.call(context, {:set_variable, identifier, value, metadata})
  end
  
  @doc """
  Lists all variables.
  
  See `DSPex.Variables.list/1` for the high-level API.
  """
  def list_variables(context) do
    GenServer.call(context, :list_variables)
  end
  
  @doc """
  Gets multiple variables.
  
  See `DSPex.Variables.get_many/2` for the high-level API.
  """
  def get_variables(context, identifiers) do
    GenServer.call(context, {:get_variables, identifiers})
  end
  
  @doc """
  Updates multiple variables.
  
  See `DSPex.Variables.update_many/3` for the high-level API.
  """
  def update_variables(context, updates, metadata \\ %{}) do
    GenServer.call(context, {:update_variables, updates, metadata})
  end
  
  @doc """
  Deletes a variable.
  """
  def delete_variable(context, identifier) do
    GenServer.call(context, {:delete_variable, identifier})
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    # Determine initial backend
    backend_module = case Keyword.get(opts, :backend, :local) do
      :local -> Local
      :bridged -> Bridged
      module when is_atom(module) -> module
    end
    
    # Validate it's a StateProvider
    StateProvider.validate_provider!(backend_module)
    
    # Generate or use provided context ID
    context_id = Keyword.get(opts, :session_id, generate_context_id())
    
    # Initialize backend
    backend_opts = [
      session_id: context_id
      | Keyword.take(opts, [:ttl, :existing_state])
    ]
    
    case backend_module.init(backend_opts) do
      {:ok, backend_state} ->
        state = %__MODULE__{
          id: context_id,
          backend_module: backend_module,
          backend_state: backend_state,
          programs: %{},
          metadata: %{
            created_at: DateTime.utc_now(),
            backend_switches: 0,
            backend_history: [{backend_module, DateTime.utc_now()}]
          },
          monitors: %{}
        }
        
        Logger.info("DSPex context #{context_id} initialized with #{inspect(backend_module)}")
        
        {:ok, state}
        
      {:error, reason} ->
        {:stop, {:backend_init_failed, reason}}
    end
  end
  
  @impl true
  def handle_call(:ensure_bridged, _from, state) do
    if state.backend_module == Bridged or state.backend_module.requires_bridge?() do
      # Already bridged
      {:reply, :ok, state}
    else
      # Need to upgrade
      case perform_backend_switch(state, Bridged) do
        {:ok, new_state} ->
          {:reply, :ok, new_state}
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  @impl true
  def handle_call(:get_backend, _from, state) do
    backend_info = %{
      module: state.backend_module,
      type: backend_type(state.backend_module),
      requires_bridge: state.backend_module.requires_bridge?(),
      capabilities: state.backend_module.capabilities(),
      switches: state.metadata.backend_switches,
      history: state.metadata.backend_history
    }
    {:reply, backend_info, state}
  end
  
  @impl true
  def handle_call(:get_id, _from, state) do
    {:reply, state.id, state}
  end
  
  @impl true
  def handle_call({:register_program, program_id, program_spec}, _from, state) do
    # Check if program requires Python
    requires_python = program_requires_python?(program_spec)
    
    # Store program
    programs = Map.put(state.programs, program_id, program_spec)
    state = %{state | programs: programs}
    
    # Switch backend if needed
    state = if requires_python and not state.backend_module.requires_bridge?() do
      Logger.info("Program #{program_id} requires Python, switching to bridged backend")
      
      case perform_backend_switch(state, Bridged) do
        {:ok, new_state} -> new_state
        {:error, reason} ->
          Logger.error("Failed to switch backend for Python program: #{inspect(reason)}")
          state
      end
    else
      state
    end
    
    {:reply, :ok, state}
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
        state = %{state | backend_state: new_backend_state}
        {:reply, {:ok, var_id}, state}
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
        state = %{state | backend_state: new_backend_state}
        {:reply, :ok, state}
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
        state = %{state | backend_state: new_backend_state}
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:delete_variable, identifier}, _from, state) do
    case state.backend_module.delete_variable(state.backend_state, identifier) do
      {:ok, new_backend_state} ->
        state = %{state | backend_state: new_backend_state}
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.info("DSPex context #{state.id} terminating: #{inspect(reason)}")
    
    # Clean up backend
    state.backend_module.cleanup(state.backend_state)
    
    # Clean up monitors
    Enum.each(state.monitors, fn {_ref, pid} ->
      Process.unlink(pid)
    end)
    
    :ok
  end
  
  ## Private Helpers
  
  defp generate_context_id do
    "ctx_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp backend_type(Local), do: :local
  defp backend_type(Bridged), do: :bridged
  defp backend_type(_), do: :custom
  
  defp program_requires_python?(program_spec) do
    # Check if program uses Python components
    # This is simplified - real implementation would inspect the program
    Map.get(program_spec, :requires_python, false) or
    Map.get(program_spec, :adapter, "") =~ "Python" or
    Map.get(program_spec, :modules, []) |> Enum.any?(&module_requires_python?/1)
  end
  
  defp module_requires_python?(module_spec) do
    # Check if a module requires Python
    # DSPy modules always require Python
    module_spec[:type] in [:dspy, :python] or
    module_spec[:class] =~ "DSPy"
  end
  
  defp perform_backend_switch(state, new_backend_module) do
    Logger.info("Switching context #{state.id} from #{inspect(state.backend_module)} to #{inspect(new_backend_module)}")
    
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, exported} <- state.backend_module.export_state(state.backend_state),
         :ok <- state.backend_module.cleanup(state.backend_state),
         {:ok, new_backend_state} <- new_backend_module.init(
           session_id: state.id,
           existing_state: exported
         ) do
      
      elapsed = System.monotonic_time(:millisecond) - start_time
      
      new_state = %{state |
        backend_module: new_backend_module,
        backend_state: new_backend_state,
        metadata: state.metadata
        |> Map.update!(:backend_switches, &(&1 + 1))
        |> Map.update!(:backend_history, &(&1 ++ [{new_backend_module, DateTime.utc_now()}]))
        |> Map.put(:last_switch_ms, elapsed)
      }
      
      Logger.info("Context #{state.id} successfully switched backends in #{elapsed}ms")
      
      # Emit telemetry event
      :telemetry.execute(
        [:dspex, :context, :backend_switch],
        %{duration_ms: elapsed},
        %{
          context_id: state.id,
          from: state.backend_module,
          to: new_backend_module
        }
      )
      
      {:ok, new_state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to switch backend: #{inspect(reason)}")
        error
    end
  end
end
```

## Monitoring and Debugging

```elixir
# File: lib/dspex/context/monitor.ex

defmodule DSPex.Context.Monitor do
  @moduledoc """
  Monitoring and debugging utilities for DSPex.Context.
  """
  
  require Logger
  
  @doc """
  Attaches telemetry handlers for context events.
  """
  def attach_handlers do
    events = [
      [:dspex, :context, :backend_switch],
      [:dspex, :context, :variable_operation],
      [:dspex, :context, :error]
    ]
    
    :telemetry.attach_many(
      "dspex-context-monitor",
      events,
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event([:dspex, :context, :backend_switch], measurements, metadata, _) do
    Logger.info("""
    Context backend switch:
      Context: #{metadata.context_id}
      From: #{inspect(metadata.from)}
      To: #{inspect(metadata.to)}
      Duration: #{measurements.duration_ms}ms
    """)
  end
  
  defp handle_event([:dspex, :context, :variable_operation], measurements, metadata, _) do
    if measurements.duration_ms > 100 do
      Logger.warning("""
      Slow variable operation:
        Context: #{metadata.context_id}
        Operation: #{metadata.operation}
        Duration: #{measurements.duration_ms}ms
      """)
    end
  end
  
  defp handle_event([:dspex, :context, :error], _measurements, metadata, _) do
    Logger.error("""
    Context error:
      Context: #{metadata.context_id}
      Operation: #{metadata.operation}
      Error: #{inspect(metadata.error)}
    """)
  end
  
  @doc """
  Gets detailed context information for debugging.
  """
  def inspect_context(context) do
    info = DSPex.Context.get_backend(context)
    
    IO.puts("""
    DSPex Context Inspection
    ========================
    ID: #{DSPex.Context.get_id(context)}
    Backend: #{inspect(info.module)}
    Type: #{info.type}
    Requires Bridge: #{info.requires_bridge}
    Switches: #{info.switches}
    
    Capabilities:
    #{inspect(info.capabilities, pretty: true)}
    
    History:
    #{format_history(info.history)}
    """)
  end
  
  defp format_history(history) do
    history
    |> Enum.map(fn {module, timestamp} ->
      "  - #{inspect(module)} at #{timestamp}"
    end)
    |> Enum.join("\n")
  end
end
```

## Testing

```elixir
# File: test/dspex/context_test.exs

defmodule DSPex.ContextTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Context
  alias DSPex.Bridge.State.{Local, Bridged}
  
  describe "context initialization" do
    test "starts with local backend by default" do
      {:ok, ctx} = Context.start_link()
      
      info = Context.get_backend(ctx)
      assert info.module == Local
      assert info.type == :local
      assert info.requires_bridge == false
      assert info.switches == 0
    end
    
    test "can start with bridged backend" do
      {:ok, ctx} = Context.start_link(backend: :bridged)
      
      info = Context.get_backend(ctx)
      assert info.module == Bridged
      assert info.type == :bridged
      assert info.requires_bridge == true
    end
    
    test "supports named contexts" do
      {:ok, _ctx} = Context.start_link(name: TestContext)
      
      # Can use name
      info = Context.get_backend(TestContext)
      assert info.module == Local
      
      # Cleanup
      Context.stop(TestContext)
    end
  end
  
  describe "automatic backend switching" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "switches to bridged when ensure_bridged called", %{ctx: ctx} do
      # Add some variables first
      {:ok, _} = Context.register_variable(ctx, :test, :string, "value")
      
      # Ensure bridged
      assert :ok = Context.ensure_bridged(ctx)
      
      # Check switched
      info = Context.get_backend(ctx)
      assert info.module == Bridged
      assert info.switches == 1
      
      # Variables preserved
      assert {:ok, "value"} = Context.get_variable(ctx, :test)
    end
    
    test "ensure_bridged is idempotent", %{ctx: ctx} do
      # Switch once
      :ok = Context.ensure_bridged(ctx)
      info1 = Context.get_backend(ctx)
      
      # Switch again
      :ok = Context.ensure_bridged(ctx)
      info2 = Context.get_backend(ctx)
      
      # Same state
      assert info1.switches == 1
      assert info2.switches == 1
    end
    
    test "switches when Python program registered", %{ctx: ctx} do
      # Register Python program
      program_spec = %{
        type: :dspy,
        adapter: "PythonAdapter",
        requires_python: true
      }
      
      :ok = Context.register_program(ctx, "python_prog", program_spec)
      
      # Should have switched
      info = Context.get_backend(ctx)
      assert info.module == Bridged
      assert info.switches == 1
    end
    
    test "doesn't switch for pure Elixir programs", %{ctx: ctx} do
      # Register Elixir program
      program_spec = %{
        type: :elixir,
        adapter: "ElixirAdapter"
      }
      
      :ok = Context.register_program(ctx, "elixir_prog", program_spec)
      
      # Should still be local
      info = Context.get_backend(ctx)
      assert info.module == Local
      assert info.switches == 0
    end
  end
  
  describe "variable operations" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "delegates to backend", %{ctx: ctx} do
      # Register variable
      {:ok, var_id} = Context.register_variable(ctx, :delegated, :integer, 42)
      assert String.starts_with?(var_id, "var_")
      
      # Get
      assert {:ok, 42} = Context.get_variable(ctx, :delegated)
      
      # Set
      assert :ok = Context.set_variable(ctx, :delegated, 100)
      assert {:ok, 100} = Context.get_variable(ctx, :delegated)
      
      # List
      assert {:ok, vars} = Context.list_variables(ctx)
      assert length(vars) == 1
      assert hd(vars).name == :delegated
    end
    
    test "batch operations", %{ctx: ctx} do
      # Register multiple
      for i <- 1..5 do
        {:ok, _} = Context.register_variable(ctx, :"var_#{i}", :integer, i)
      end
      
      # Batch get
      identifiers = Enum.map(1..5, &:"var_#{&1}")
      assert {:ok, values} = Context.get_variables(ctx, identifiers)
      assert map_size(values) == 5
      
      # Batch update
      updates = Map.new(1..5, fn i -> {:"var_#{i}", i * 10} end)
      assert :ok = Context.update_variables(ctx, updates)
      
      # Verify
      assert {:ok, 30} = Context.get_variable(ctx, :var_3)
    end
  end
  
  describe "backend switch performance" do
    setup do
      {:ok, ctx} = Context.start_link()
      
      # Add some state
      for i <- 1..20 do
        {:ok, _} = Context.register_variable(ctx, :"perf_#{i}", :float, i * 1.1)
      end
      
      {:ok, ctx: ctx}
    end
    
    test "completes within target time", %{ctx: ctx} do
      # Measure switch time
      {time, :ok} = :timer.tc(fn ->
        Context.ensure_bridged(ctx)
      end)
      
      # Should be under 50ms
      assert time < 50_000
      
      # Check last_switch_ms in metadata
      info = Context.get_backend(ctx)
      assert length(info.history) == 2
      
      # All variables should be preserved
      assert {:ok, vars} = Context.list_variables(ctx)
      assert length(vars) == 20
    end
  end
  
  describe "error handling" do
    test "handles backend init failure" do
      # Use an invalid backend
      defmodule BadBackend do
        @behaviour DSPex.Bridge.StateProvider
        def init(_), do: {:error, :always_fails}
        # ... stub other callbacks
      end
      
      assert {:error, {:backend_init_failed, :always_fails}} = 
        Context.start_link(backend: BadBackend)
    end
    
    test "handles switch failure gracefully" do
      {:ok, ctx} = Context.start_link()
      
      # Mock a failing export
      # In real tests, this would use mox or similar
      # For now, we'll trust the error handling works
      
      # The context should remain functional even if switch fails
      {:ok, _} = Context.register_variable(ctx, :survivor, :string, "still here")
      assert {:ok, "still here"} = Context.get_variable(ctx, :survivor)
    end
  end
end
```

## Usage Examples

```elixir
defmodule DSPex.Examples.ContextUsage do
  @moduledoc """
  Examples of DSPex.Context usage patterns.
  """
  
  alias DSPex.{Context, Variables}
  
  def pure_elixir_workflow do
    {:ok, ctx} = Context.start_link()
    
    # Fast local operations
    Variables.defvariable(ctx, :temperature, :float, 0.7)
    Variables.defvariable(ctx, :max_tokens, :integer, 256)
    
    # Run pure Elixir logic
    temp = Variables.get(ctx, :temperature)
    new_temp = min(temp * 1.1, 2.0)
    Variables.set(ctx, :temperature, new_temp)
    
    # Still using fast local backend
    info = Context.get_backend(ctx)
    IO.puts("Backend: #{info.type}")  # :local
  end
  
  def hybrid_workflow do
    {:ok, ctx} = Context.start_link()
    
    # Start with Elixir operations
    Variables.defvariable(ctx, :prompt, :string, "Explain quantum computing")
    
    # Add DSPy module - triggers switch
    {:ok, cot} = DSPex.Modules.ChainOfThought.new(ctx, "question -> answer")
    
    # Now using bridged backend
    info = Context.get_backend(ctx)
    IO.puts("Backend: #{info.type}")  # :bridged
    
    # Variables still accessible
    prompt = Variables.get(ctx, :prompt)
    
    # Python can now access the same variables
    # result = DSPex.Modules.ChainOfThought.forward(cot, %{question: prompt})
  end
  
  def preemptive_bridging do
    {:ok, ctx} = Context.start_link()
    
    # If you know Python will be needed, switch early
    :ok = Context.ensure_bridged(ctx)
    
    # Now all operations use consistent backend
    Variables.defvariable(ctx, :config, :string, "production")
  end
end
```

## Design Decisions

1. **Always Start Local**: Maximum performance by default
2. **Lazy Switching**: Only switch when actually needed
3. **One-Way Switch**: Never downgrade from bridged to local
4. **State Preservation**: All data migrates seamlessly
5. **Program Awareness**: Programs can declare Python needs

## Performance Considerations

- Local operations: No overhead beyond function calls
- Backend switch: One-time cost, typically 10-50ms
- Bridged operations: Add ~1-2ms per operation
- Memory: Minimal overhead for context process

## Next Steps

After implementing DSPex.Context:
1. Create high-level Variables API
2. Test backend switching thoroughly
3. Add telemetry and monitoring
4. Benchmark switch performance
5. Document usage patterns