defmodule DSPex.Telemetry.Handler do
  @moduledoc """
  Central telemetry handler for DSPex.
  
  This module provides centralized telemetry event handling with support for:
  - Event registration and attachment
  - Standardized measurement collection
  - Error handling and recovery
  - Event filtering and routing
  
  ## Usage
  
  Start the handler in your application supervision tree:
  
      children = [
        DSPex.Telemetry.Handler
      ]
  
  ## Configuration
  
  Configure telemetry handlers in your config:
  
      config :dspex, :telemetry,
        handlers: [
          {DSPex.Telemetry.Metrics, []},
          {DSPex.Telemetry.Reporter, []}
        ]
  """
  
  use GenServer
  require Logger
  
  @telemetry_events [
    # Bridge operations
    [:dspex, :bridge, :create_instance, :start],
    [:dspex, :bridge, :create_instance, :stop],
    [:dspex, :bridge, :create_instance, :exception],
    [:dspex, :bridge, :call_method, :start],
    [:dspex, :bridge, :call_method, :stop],
    [:dspex, :bridge, :call_method, :exception],
    [:dspex, :bridge, :call, :start],
    [:dspex, :bridge, :call, :stop],
    [:dspex, :bridge, :call, :exception],
    
    # Tool executions
    [:dspex, :tools, :execute, :start],
    [:dspex, :tools, :execute, :stop],
    [:dspex, :tools, :execute, :exception],
    [:dspex, :tools, :call, :start],
    [:dspex, :tools, :call, :stop],
    [:dspex, :tools, :call, :exception],
    
    # Contract validations
    [:dspex, :contract, :validate, :start],
    [:dspex, :contract, :validate, :stop],
    [:dspex, :contract, :validate, :exception],
    
    # Type casting
    [:dspex, :types, :cast, :start],
    [:dspex, :types, :cast, :stop],
    [:dspex, :types, :cast, :exception],
    
    # Session operations
    [:dspex, :session, :created],
    [:dspex, :session, :variable, :set],
    [:dspex, :session, :variable, :get],
    [:dspex, :session, :expired],
    
    # Worker pool health (Snakepit)
    [:snakepit, :worker, :spawned],
    [:snakepit, :worker, :died],
    [:snakepit, :pool, :queue_time],
    
    # Application lifecycle
    [:dspex, :application, :start]
  ]
  
  @type handler_config :: {module(), keyword()}
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Attach a custom handler to telemetry events.
  """
  def attach_handler(handler_id, events, handler_fun, config \\ nil) do
    GenServer.call(__MODULE__, {:attach_handler, handler_id, events, handler_fun, config})
  end
  
  @doc """
  Detach a handler from telemetry events.
  """
  def detach_handler(handler_id) do
    GenServer.call(__MODULE__, {:detach_handler, handler_id})
  end
  
  @doc """
  List all attached handlers.
  """
  def list_handlers do
    GenServer.call(__MODULE__, :list_handlers)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Attach default handlers
    attach_default_handlers()
    
    # Attach configured handlers
    configured_handlers = Application.get_env(:dspex, :telemetry, [])[:handlers] || []
    
    for {module, config} <- configured_handlers do
      attach_module_handler(module, config)
    end
    
    state = %{
      handlers: %{},
      opts: opts
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:attach_handler, handler_id, events, handler_fun, config}, _from, state) do
    case :telemetry.attach_many(handler_id, events, handler_fun, config) do
      :ok ->
        state = put_in(state.handlers[handler_id], %{
          events: events,
          handler_fun: handler_fun,
          config: config
        })
        {:reply, :ok, state}
        
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:detach_handler, handler_id}, _from, state) do
    case :telemetry.detach(handler_id) do
      :ok ->
        {_, state} = pop_in(state.handlers[handler_id])
        {:reply, :ok, state}
        
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:list_handlers, _from, state) do
    {:reply, Map.keys(state.handlers), state}
  end
  
  # Private functions
  
  defp attach_default_handlers do
    # Attach basic logging handler
    :telemetry.attach_many(
      "dspex-default-logger",
      @telemetry_events,
      &__MODULE__.handle_event/4,
      %{log_level: :debug}
    )
  end
  
  defp attach_module_handler(module, config) do
    if function_exported?(module, :attach, 0) do
      apply(module, :attach, [])
    else
      Logger.warning("Telemetry handler module #{module} does not export attach/0")
    end
  end
  
  @doc false
  def handle_event(event, measurements, metadata, config) do
    log_level = config[:log_level] || :debug
    
    case event do
      [:dspex, :bridge, operation, :start] ->
        Logger.log(log_level, "Starting bridge #{operation}: #{inspect(metadata)}")
        
      [:dspex, :bridge, operation, :stop] ->
        duration_ms = duration_to_ms(measurements[:duration])
        Logger.log(log_level, "Completed bridge #{operation} in #{duration_ms}ms")
        
      [:dspex, :bridge, operation, :exception] ->
        duration_ms = duration_to_ms(measurements[:duration])
        Logger.error("Bridge #{operation} failed after #{duration_ms}ms: #{inspect(metadata[:error])}")
        
      [:dspex, :tools, :execute, :start] ->
        Logger.log(log_level, "Executing tool #{metadata.tool_name} from #{metadata.caller}")
        
      [:dspex, :tools, :execute, :stop] ->
        duration_ms = duration_to_ms(measurements[:duration])
        Logger.log(log_level, "Tool #{metadata.tool_name} completed in #{duration_ms}ms")
        
      [:dspex, :tools, :execute, :exception] ->
        duration_ms = duration_to_ms(measurements[:duration])
        Logger.error("Tool #{metadata.tool_name} failed after #{duration_ms}ms: #{inspect(metadata[:reason])}")
        
      [:dspex, :session, :created] ->
        Logger.log(log_level, "Session created: #{metadata.session_id}")
        
      [:dspex, :session, :expired] ->
        Logger.log(log_level, "Session expired: #{metadata.session_id} (lifetime: #{measurements.lifetime_ms}ms)")
        
      [:snakepit, :pool, :queue_time] ->
        if measurements.wait_time_us > 1_000_000 do
          Logger.warning("High queue time: #{measurements.wait_time_us / 1_000}ms")
        end
        
      _ ->
        Logger.log(log_level, "Telemetry event #{inspect(event)}: #{inspect(measurements)}")
    end
  rescue
    error ->
      Logger.error("Error in telemetry handler: #{inspect(error)}")
  end
  
  defp duration_to_ms(nil), do: 0
  defp duration_to_ms(duration) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end
end