defmodule DSPex.Telemetry.OpenTelemetry do
  @moduledoc """
  OpenTelemetry integration for DSPex.
  
  This module provides:
  - Automatic span creation for DSPex operations
  - Context propagation
  - Metric recording
  - Trace exporting
  
  ## Setup
  
  Add to your application supervision tree:
  
      children = [
        DSPex.Telemetry.OpenTelemetry
      ]
      
  ## Configuration
  
      config :opentelemetry, :resource,
        service: [
          name: "dspex",
          version: "1.0.0"
        ]
        
      config :opentelemetry, :processors,
        otel_batch_processor: %{
          exporter: {:otel_exporter_otlp, endpoint: "http://localhost:4317"}
        }
  """
  
  use GenServer
  require Logger
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Start a new span for a DSPex operation.
  """
  def start_span(name, attributes \\ %{}) do
    if otel_available?() do
      :otel_tracer.start_span(name, %{attributes: attributes})
    else
      {:ok, :noop_span}
    end
  end
  
  @doc """
  End a span with optional status.
  """
  def end_span(span, status \\ :ok) do
    if otel_available?() && span != :noop_span do
      :otel_tracer.end_span(span, %{status: status})
    end
  end
  
  @doc """
  Record a metric value.
  """
  def record_metric(name, value, attributes \\ %{}) do
    if otel_available?() do
      # OpenTelemetry metrics API
      :otel_meter.record(name, value, attributes)
    end
  end
  
  @doc """
  Add event to current span.
  """
  def add_event(name, attributes \\ %{}) do
    if otel_available?() do
      :otel_tracer.add_event(name, attributes)
    end
  end
  
  @doc """
  Set span attributes.
  """
  def set_attributes(attributes) do
    if otel_available?() do
      :otel_tracer.set_attributes(attributes)
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Attach to telemetry events
    if otel_available?() do
      attach_handlers()
    else
      Logger.info("OpenTelemetry not available, skipping integration")
    end
    
    {:ok, %{opts: opts}}
  end
  
  # Private functions
  
  defp otel_available? do
    Code.ensure_loaded?(:otel_tracer)
  end
  
  defp attach_handlers do
    handlers = [
      {[:dspex, :bridge, :call], &handle_bridge_call/4},
      {[:dspex, :bridge, :create_instance], &handle_bridge_create/4},
      {[:dspex, :bridge, :call_method], &handle_bridge_method/4},
      {[:dspex, :tools, :execute], &handle_tool_execute/4},
      {[:dspex, :contract, :validate], &handle_contract_validate/4},
      {[:dspex, :types, :cast], &handle_type_cast/4},
      {[:dspex, :session, :created], &handle_session_created/4},
      {[:dspex, :session, :variable, :set], &handle_session_var_set/4},
      {[:dspex, :session, :variable, :get], &handle_session_var_get/4}
    ]
    
    Enum.each(handlers, fn {event_prefix, handler} ->
      events = [
        event_prefix ++ [:start],
        event_prefix ++ [:stop],
        event_prefix ++ [:exception]
      ]
      
      :telemetry.attach_many(
        "otel-#{Enum.join(event_prefix, "-")}",
        events,
        handler,
        nil
      )
    end)
  end
  
  # Bridge call handlers
  
  defp handle_bridge_call(event, measurements, metadata, _config) do
    case event do
      [:dspex, :bridge, :call, :start] ->
        span = start_span("dspex.bridge.call", %{
          "bridge.module" => metadata[:module],
          "bridge.function" => metadata[:function],
          "bridge.session_id" => metadata[:session_id]
        })
        
        Process.put({:otel_span, :bridge_call}, span)
        
      [:dspex, :bridge, :call, :stop] ->
        span = Process.delete({:otel_span, :bridge_call})
        
        if span do
          set_attributes(%{
            "bridge.success" => metadata[:success],
            "bridge.duration_ms" => measurements[:duration] / 1_000
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :bridge, :call, :exception] ->
        span = Process.delete({:otel_span, :bridge_call})
        
        if span do
          set_attributes(%{
            "bridge.error" => inspect(metadata[:error]),
            "bridge.duration_ms" => measurements[:duration] / 1_000
          })
          
          add_event("exception", %{
            "exception.type" => to_string(metadata[:kind] || :error),
            "exception.message" => inspect(metadata[:error])
          })
          
          end_span(span, :error)
        end
    end
  end
  
  # Bridge create instance handlers
  
  defp handle_bridge_create(event, measurements, metadata, _config) do
    case event do
      [:dspex, :bridge, :create_instance, :start] ->
        span = start_span("dspex.bridge.create_instance", %{
          "bridge.python_class" => metadata[:python_class],
          "bridge.session_id" => metadata[:session_id]
        })
        
        Process.put({:otel_span, :bridge_create}, span)
        
      [:dspex, :bridge, :create_instance, :stop] ->
        span = Process.delete({:otel_span, :bridge_create})
        
        if span do
          set_attributes(%{
            "bridge.success" => metadata[:success],
            "bridge.duration_ms" => measurements[:duration] / 1_000
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :bridge, :create_instance, :exception] ->
        span = Process.delete({:otel_span, :bridge_create})
        
        if span do
          set_attributes(%{
            "bridge.error" => inspect(metadata[:error])
          })
          
          end_span(span, :error)
        end
    end
  end
  
  # Bridge method call handlers
  
  defp handle_bridge_method(event, measurements, metadata, _config) do
    case event do
      [:dspex, :bridge, :call_method, :start] ->
        span = start_span("dspex.bridge.call_method", %{
          "bridge.instance_id" => metadata[:instance_id],
          "bridge.method_name" => metadata[:method_name],
          "bridge.session_id" => metadata[:session_id]
        })
        
        Process.put({:otel_span, :bridge_method}, span)
        
      [:dspex, :bridge, :call_method, :stop] ->
        span = Process.delete({:otel_span, :bridge_method})
        
        if span do
          set_attributes(%{
            "bridge.success" => metadata[:success],
            "bridge.duration_ms" => measurements[:duration] / 1_000
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :bridge, :call_method, :exception] ->
        span = Process.delete({:otel_span, :bridge_method})
        
        if span do
          end_span(span, :error)
        end
    end
  end
  
  # Tool execution handlers
  
  defp handle_tool_execute(event, measurements, metadata, _config) do
    case event do
      [:dspex, :tools, :execute, :start] ->
        span = start_span("dspex.tools.execute", %{
          "tool.name" => metadata[:tool_name],
          "tool.caller" => to_string(metadata[:caller]),
          "tool.session_id" => metadata[:session_id]
        })
        
        Process.put({:otel_span, :tool_execute}, span)
        
      [:dspex, :tools, :execute, :stop] ->
        span = Process.delete({:otel_span, :tool_execute})
        
        if span do
          set_attributes(%{
            "tool.result_type" => to_string(metadata[:result_type]),
            "tool.duration_ms" => measurements[:duration] / 1_000
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :tools, :execute, :exception] ->
        span = Process.delete({:otel_span, :tool_execute})
        
        if span do
          set_attributes(%{
            "tool.error.kind" => to_string(metadata[:kind]),
            "tool.error.reason" => inspect(metadata[:reason])
          })
          
          end_span(span, :error)
        end
    end
  end
  
  # Contract validation handlers
  
  defp handle_contract_validate(event, measurements, metadata, _config) do
    case event do
      [:dspex, :contract, :validate, :start] ->
        span = start_span("dspex.contract.validate", %{
          "contract.param_count" => metadata[:param_count],
          "contract.spec_count" => metadata[:spec_count]
        })
        
        Process.put({:otel_span, :contract_validate}, span)
        
      [:dspex, :contract, :validate, :stop] ->
        span = Process.delete({:otel_span, :contract_validate})
        
        if span do
          set_attributes(%{
            "contract.success" => true,
            "contract.duration_us" => measurements[:duration]
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :contract, :validate, :exception] ->
        span = Process.delete({:otel_span, :contract_validate})
        
        if span do
          set_attributes(%{
            "contract.error" => inspect(metadata[:error])
          })
          
          end_span(span, :error)
        end
    end
  end
  
  # Type cast handlers
  
  defp handle_type_cast(event, measurements, metadata, _config) do
    case event do
      [:dspex, :types, :cast, :start] ->
        span = start_span("dspex.types.cast", %{
          "types.input_type" => to_string(metadata[:input_type]),
          "types.target_type" => inspect(metadata[:target_type])
        })
        
        Process.put({:otel_span, :type_cast}, span)
        
      [:dspex, :types, :cast, :stop] ->
        span = Process.delete({:otel_span, :type_cast})
        
        if span do
          set_attributes(%{
            "types.success" => true,
            "types.duration_us" => measurements[:duration]
          })
          
          end_span(span, :ok)
        end
        
      [:dspex, :types, :cast, :exception] ->
        span = Process.delete({:otel_span, :type_cast})
        
        if span do
          set_attributes(%{
            "types.error" => inspect(metadata[:error])
          })
          
          end_span(span, :error)
        end
    end
  end
  
  # Session handlers
  
  defp handle_session_created([:dspex, :session, :created], measurements, metadata, _config) do
    add_event("session.created", %{
      "session.id" => metadata[:session_id],
      "session.initial_vars" => inspect(metadata[:initial_vars])
    })
    
    record_metric("dspex.session.created", 1, %{})
  end
  
  defp handle_session_var_set([:dspex, :session, :variable, :set], measurements, metadata, _config) do
    record_metric("dspex.session.variable.set", 1, %{
      "var.name" => metadata[:var_name],
      "var.type" => metadata[:var_type]
    })
    
    record_metric("dspex.session.variable.size", measurements[:size], %{
      "var.type" => metadata[:var_type]
    })
  end
  
  defp handle_session_var_get([:dspex, :session, :variable, :get], measurements, metadata, _config) do
    record_metric("dspex.session.variable.get", 1, %{
      "var.found" => to_string(metadata[:found])
    })
    
    if metadata[:found] do
      record_metric("dspex.session.variable.get.size", measurements[:size], %{})
    end
  end
end