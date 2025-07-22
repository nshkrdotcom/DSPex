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
  Calls a registered program with the given inputs.
  
  ## Example
  
      Context.register_program(ctx, "qa_bot", %{
        type: :dspy,
        module_type: "chain_of_thought",
        signature: %{
          inputs: [%{name: "question", type: "string"}],
          outputs: [%{name: "answer", type: "string"}]
        }
      })
      
      {:ok, result} = Context.call(ctx, "qa_bot", %{
        question: "What is DSPy?"
      })
  """
  @spec call(t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def call(context, program_id, inputs) do
    GenServer.call(context, {:call_program, program_id, inputs})
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
    backend_module =
      case Keyword.get(opts, :backend, :local) do
        :local -> Local
        :bridged -> Bridged
        module when is_atom(module) -> module
      end

    # Validate it's a StateProvider
    StateProvider.validate_provider!(backend_module)

    # Generate or use provided context ID
    context_id = Keyword.get(opts, :session_id, generate_context_id())

    # Initialize backend
    backend_opts =
      [session_id: context_id] ++
        Keyword.take(opts, [:ttl, :existing_state])

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
    state =
      if requires_python and not state.backend_module.requires_bridge?() do
        Logger.info("Program #{program_id} requires Python, switching to bridged backend")

        case perform_backend_switch(state, Bridged) do
          {:ok, new_state} ->
            new_state

          {:error, reason} ->
            Logger.error("Failed to switch backend for Python program: #{inspect(reason)}")
            state
        end
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:call_program, program_id, inputs}, _from, state) do
    case Map.get(state.programs, program_id) do
      nil ->
        {:reply, {:error, :program_not_found}, state}
      
      program_spec ->
        result = execute_program(program_spec, inputs, state)
        {:reply, result, state}
    end
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

  defp execute_program(program_spec, inputs, state) do
    case program_spec do
      %{type: :dspy} ->
        # DSPy programs need to be executed through the Python bridge
        execute_dspy_program(program_spec, inputs, state)
        
      %{type: :native} ->
        # Native Elixir programs (future enhancement)
        {:error, :native_programs_not_implemented}
        
      _ ->
        {:error, :unknown_program_type}
    end
  end
  
  defp execute_dspy_program(program_spec, inputs, state) do
    # Ensure we have a bridged backend
    if not state.backend_module.requires_bridge?() do
      {:error, :dspy_requires_bridged_backend}
    else
      # Get the session ID from the backend state
      session_id = state.backend_state.session_id
      
      # Execute through the Python bridge
      case Snakepit.PythonWorker.execute_program(
        program_id: Map.get(program_spec, :id, "unknown"),
        program_type: Map.get(program_spec, :module_type, "predict"),
        signature: Map.get(program_spec, :signature, %{}),
        inputs: inputs,
        session_id: session_id,
        variable_aware: Map.get(program_spec, :variable_aware, false),
        variable_bindings: Map.get(program_spec, :variable_bindings, %{})
      ) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp perform_backend_switch(state, new_backend_module) do
    Logger.info(
      "Switching context #{state.id} from #{inspect(state.backend_module)} to #{inspect(new_backend_module)}"
    )

    start_time = System.monotonic_time(:millisecond)

    with {:ok, exported} <- state.backend_module.export_state(state.backend_state),
         :ok <- state.backend_module.cleanup(state.backend_state),
         {:ok, new_backend_state} <-
           new_backend_module.init(
             session_id: state.id,
             existing_state: exported
           ) do
      elapsed = System.monotonic_time(:millisecond) - start_time

      new_state = %{
        state
        | backend_module: new_backend_module,
          backend_state: new_backend_state,
          metadata:
            state.metadata
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
