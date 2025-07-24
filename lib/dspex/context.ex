defmodule DSPex.Context do
  @moduledoc """
  The central execution context for DSPex programs.

  Simplified to use Snakepit's SessionStore directly instead of 
  maintaining a custom state management layer.

  ## Architecture

  Context is now a lightweight wrapper around Snakepit.Bridge.SessionStore:

      DSPex.Context
           ↓
      Snakepit.Bridge.SessionStore ←→ gRPC ←→ Python

  ## Example

      # Create a session-based context
      {:ok, ctx} = DSPex.Context.start_link()
      
      # All operations use SessionStore directly
      DSPex.Variables.set(ctx, :temperature, 0.7)
      
      # DSPy modules share the same session
      DSPex.Modules.ChainOfThought.new(ctx, "question -> answer")

  ## Supervision

  Contexts can be supervised:

      children = [
        {DSPex.Context, name: MyApp.Context, session_id: "my_session"}
      ]
      
      Supervisor.start_link(children, strategy: :one_for_one)
  """

  use GenServer
  require Logger

  alias Snakepit.Bridge.SessionStore

  @type t :: pid() | atom()

  defstruct [
    :session_id,
    :programs,
    :metadata
  ]

  ## Client API

  @doc """
  Starts a new context with optional configuration.

  ## Options

    * `:name` - Register the context with a name
    * `:session_id` - Specific session ID (auto-generated if not provided)
    * `:ttl` - Session time-to-live in seconds

  ## Examples

      # Anonymous context
      {:ok, ctx} = DSPex.Context.start_link()
      
      # Named context
      {:ok, ctx} = DSPex.Context.start_link(name: MyApp.Context)
      
      # Specific session ID
      {:ok, ctx} = DSPex.Context.start_link(session_id: "my_session")
  """
  def start_link(opts \\ []) do
    {name_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end

  @doc """
  Gets the session ID for this context.
  """
  @spec get_session_id(t()) :: String.t()
  def get_session_id(context) do
    GenServer.call(context, :get_session_id)
  end

  @doc """
  Gets the context session information.
  """
  @spec get_info(t()) :: map()
  def get_info(context) do
    GenServer.call(context, :get_info)
  end

  @doc """
  Registers a program with the context.
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

  ## Variable Operations (delegated to SessionStore)

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

  See `DSPex.Variables.list/2` for the high-level API.
  """
  def list_variables(context) do
    GenServer.call(context, :list_variables)
  end

  @doc """
  Gets multiple variables at once.

  See `DSPex.Variables.get_many/3` for the high-level API.
  """
  def get_variables(context, identifiers) do
    GenServer.call(context, {:get_variables, identifiers})
  end

  @doc """
  Updates multiple variables atomically.

  See `DSPex.Variables.set_many/4` for the high-level API.
  """
  def update_variables(context, updates, metadata \\ %{}) do
    GenServer.call(context, {:update_variables, updates, metadata})
  end

  @doc """
  Deletes a variable.

  See `DSPex.Variables.delete/2` for the high-level API.
  """
  def delete_variable(context, identifier) do
    GenServer.call(context, {:delete_variable, identifier})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    ttl = Keyword.get(opts, :ttl, 3600)

    # Ensure SessionStore is available
    ensure_session_store!()

    # Create session in SessionStore
    case SessionStore.create_session(session_id, ttl: ttl) do
      {:ok, _session} ->
        state = %__MODULE__{
          session_id: session_id,
          programs: %{},
          metadata: %{
            created_at: DateTime.utc_now(),
            backend: :session_store
          }
        }

        Logger.debug("DSPex.Context initialized with session #{session_id}")
        {:ok, state}

      {:error, :already_exists} ->
        # Session already exists, that's fine
        state = %__MODULE__{
          session_id: session_id,
          programs: %{},
          metadata: %{
            created_at: DateTime.utc_now(),
            backend: :session_store,
            reused_session: true
          }
        }

        Logger.debug("DSPex.Context reusing existing session #{session_id}")
        {:ok, state}

      {:error, reason} ->
        {:error, {:session_creation_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_id: state.session_id,
      programs: Map.keys(state.programs),
      program_count: map_size(state.programs),
      metadata: state.metadata
    }
    {:reply, info, state}
  end

  @impl true
  def handle_call({:register_program, program_id, program_spec}, _from, state) do
    new_programs = Map.put(state.programs, program_id, program_spec)
    new_state = %{state | programs: new_programs}

    Logger.debug("Registered program #{program_id} in session #{state.session_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:call_program, program_id, inputs}, _from, state) do
    case Map.get(state.programs, program_id) do
      nil ->
        {:reply, {:error, {:program_not_found, program_id}}, state}

      _program_spec ->
        # For now, delegate to Snakepit execution
        # In a full implementation, this would use the program_spec
        # to determine how to execute the program
        result = Snakepit.execute_in_session(state.session_id, "call_dspy", inputs)
        {:reply, result, state}
    end
  end

  ## Variable operations - delegate to SessionStore

  @impl true
  def handle_call({:register_variable, name, type, initial_value, opts}, _from, state) do
    case SessionStore.register_variable(state.session_id, name, type, initial_value, opts) do
      {:ok, var_id} ->
        {:reply, {:ok, var_id}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_variable, identifier}, _from, state) do
    case SessionStore.get_variable(state.session_id, identifier) do
      {:ok, variable} ->
        {:reply, {:ok, variable.value}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:set_variable, identifier, value, metadata}, _from, state) do
    case SessionStore.update_variable(state.session_id, identifier, value, metadata) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_variables, _from, state) do
    case SessionStore.list_variables(state.session_id) do
      {:ok, variables} ->
        {:reply, {:ok, variables}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_variables, identifiers}, _from, state) do
    case SessionStore.get_variables(state.session_id, identifiers) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_variables, updates, metadata}, _from, state) do
    case SessionStore.update_variables(state.session_id, updates, metadata: metadata) do
      {:ok, _results} ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_variable, identifier}, _from, state) do
    case SessionStore.delete_variable(state.session_id, identifier) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("DSPex.Context terminating for session #{state.session_id}")
    # SessionStore handles cleanup via TTL, no explicit cleanup needed
    :ok
  end

  ## Private Helpers

  defp generate_session_id do
    "dspex_session_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp ensure_session_store! do
    case Process.whereis(SessionStore) do
      nil ->
        # Try to start it
        case SessionStore.start_link() do
          {:ok, _} ->
            :ok
          {:error, reason} ->
            raise "Failed to start SessionStore: #{inspect(reason)}"
        end
      _pid ->
        :ok
    end
  end
end