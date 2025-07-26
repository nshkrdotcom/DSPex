defmodule DSPex.Telemetry.Correlation do
  @moduledoc """
  Request correlation and distributed tracing support.
  
  This module provides:
  - Correlation ID generation and propagation
  - Request tracing across bridge calls
  - Parent-child span relationships
  - Trace context management
  
  ## Usage
  
      # Start a new trace
      correlation_id = DSPex.Telemetry.Correlation.start_trace()
      
      # Use in a request
      DSPex.Telemetry.Correlation.with_correlation(correlation_id, fn ->
        # All operations within this block will be correlated
        DSPex.Bridge.call_dspy("dspy", "Predict", %{})
      end)
      
      # Get current correlation ID
      current_id = DSPex.Telemetry.Correlation.current_correlation_id()
  """
  
  require Logger
  
  @correlation_key :dspex_correlation_id
  @trace_key :dspex_trace_context
  
  defmodule TraceContext do
    @moduledoc false
    defstruct [
      :trace_id,
      :span_id,
      :parent_span_id,
      :flags,
      :baggage
    ]
  end
  
  @doc """
  Generates a new correlation ID.
  """
  def generate_correlation_id do
    "dspex-#{System.system_time(:microsecond)}-#{:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)}"
  end
  
  @doc """
  Starts a new trace with a correlation ID.
  """
  def start_trace(correlation_id \\ nil) do
    correlation_id = correlation_id || generate_correlation_id()
    trace_id = generate_trace_id()
    span_id = generate_span_id()
    
    context = %TraceContext{
      trace_id: trace_id,
      span_id: span_id,
      parent_span_id: nil,
      flags: %{sampled: true},
      baggage: %{}
    }
    
    Process.put(@correlation_key, correlation_id)
    Process.put(@trace_key, context)
    
    Logger.metadata(correlation_id: correlation_id, trace_id: trace_id, span_id: span_id)
    
    :telemetry.execute(
      [:dspex, :trace, :started],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        trace_id: trace_id,
        span_id: span_id
      }
    )
    
    correlation_id
  end
  
  @doc """
  Executes a function with a specific correlation ID.
  """
  def with_correlation(correlation_id, fun) when is_function(fun, 0) do
    old_correlation = Process.get(@correlation_key)
    old_context = Process.get(@trace_key)
    
    try do
      Process.put(@correlation_key, correlation_id)
      
      # Create new span for this operation
      parent_context = old_context || %TraceContext{trace_id: generate_trace_id()}
      span_id = generate_span_id()
      
      new_context = %TraceContext{
        trace_id: parent_context.trace_id,
        span_id: span_id,
        parent_span_id: parent_context.span_id,
        flags: parent_context.flags,
        baggage: parent_context.baggage
      }
      
      Process.put(@trace_key, new_context)
      Logger.metadata(correlation_id: correlation_id, span_id: span_id)
      
      fun.()
    after
      Process.put(@correlation_key, old_correlation)
      Process.put(@trace_key, old_context)
      
      if old_correlation do
        Logger.metadata(correlation_id: old_correlation)
      end
    end
  end
  
  @doc """
  Gets the current correlation ID.
  """
  def current_correlation_id do
    Process.get(@correlation_key)
  end
  
  @doc """
  Gets the current trace context.
  """
  def current_trace_context do
    Process.get(@trace_key)
  end
  
  @doc """
  Adds baggage items to the current trace.
  """
  def add_baggage(key, value) do
    case Process.get(@trace_key) do
      %TraceContext{} = context ->
        updated_context = update_in(context.baggage, &Map.put(&1, key, value))
        Process.put(@trace_key, updated_context)
        :ok
        
      nil ->
        {:error, :no_active_trace}
    end
  end
  
  @doc """
  Gets baggage from the current trace.
  """
  def get_baggage(key) do
    case Process.get(@trace_key) do
      %TraceContext{baggage: baggage} ->
        Map.get(baggage, key)
        
      nil ->
        nil
    end
  end
  
  @doc """
  Creates a child span in the current trace.
  """
  def with_span(name, fun) when is_function(fun, 0) do
    case Process.get(@trace_key) do
      %TraceContext{} = parent_context ->
        span_id = generate_span_id()
        
        child_context = %TraceContext{
          trace_id: parent_context.trace_id,
          span_id: span_id,
          parent_span_id: parent_context.span_id,
          flags: parent_context.flags,
          baggage: parent_context.baggage
        }
        
        old_context = Process.put(@trace_key, child_context)
        
        start_time = System.monotonic_time()
        
        :telemetry.execute(
          [:dspex, :span, :start],
          %{system_time: System.system_time()},
          %{
            name: name,
            trace_id: child_context.trace_id,
            span_id: span_id,
            parent_span_id: parent_context.span_id
          }
        )
        
        try do
          result = fun.()
          
          duration = System.monotonic_time() - start_time
          
          :telemetry.execute(
            [:dspex, :span, :stop],
            %{duration: duration, system_time: System.system_time()},
            %{
              name: name,
              trace_id: child_context.trace_id,
              span_id: span_id,
              parent_span_id: parent_context.span_id
            }
          )
          
          result
        rescue
          error ->
            duration = System.monotonic_time() - start_time
            
            :telemetry.execute(
              [:dspex, :span, :exception],
              %{duration: duration, system_time: System.system_time()},
              %{
                name: name,
                trace_id: child_context.trace_id,
                span_id: span_id,
                parent_span_id: parent_context.span_id,
                error: error,
                stacktrace: __STACKTRACE__
              }
            )
            
            reraise error, __STACKTRACE__
        after
          Process.put(@trace_key, old_context)
        end
        
      nil ->
        # No active trace, just execute the function
        fun.()
    end
  end
  
  @doc """
  Injects trace context into a map for propagation.
  """
  def inject_context(headers \\ %{}) when is_map(headers) do
    correlation_id = current_correlation_id()
    
    headers = if correlation_id do
      Map.put(headers, "x-correlation-id", correlation_id)
    else
      headers
    end
    
    case current_trace_context() do
      %TraceContext{} = context ->
        headers
        |> Map.put("x-trace-id", context.trace_id)
        |> Map.put("x-span-id", context.span_id)
        |> Map.put("x-parent-span-id", context.parent_span_id || "")
        |> Map.put("x-trace-flags", encode_flags(context.flags))
        |> Map.put("x-trace-baggage", encode_baggage(context.baggage))
        
      nil ->
        headers
    end
  end
  
  @doc """
  Extracts trace context from a map.
  """
  def extract_context(headers) when is_map(headers) do
    correlation_id = Map.get(headers, "x-correlation-id")
    
    if correlation_id do
      Process.put(@correlation_key, correlation_id)
    end
    
    trace_id = Map.get(headers, "x-trace-id")
    span_id = Map.get(headers, "x-span-id")
    
    if trace_id && span_id do
      context = %TraceContext{
        trace_id: trace_id,
        span_id: generate_span_id(),  # New span for this process
        parent_span_id: span_id,       # Previous span becomes parent
        flags: decode_flags(Map.get(headers, "x-trace-flags", "")),
        baggage: decode_baggage(Map.get(headers, "x-trace-baggage", ""))
      }
      
      Process.put(@trace_key, context)
      Logger.metadata(correlation_id: correlation_id, trace_id: trace_id, span_id: context.span_id)
      
      {:ok, context}
    else
      {:error, :no_trace_context}
    end
  end
  
  # Private functions
  
  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end
  
  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end
  
  defp encode_flags(flags) when is_map(flags) do
    flags
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(",")
  end
  
  defp decode_flags(flags_string) when is_binary(flags_string) do
    flags_string
    |> String.split(",", trim: true)
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, "true"] -> {String.to_atom(key), true}
        [key, "false"] -> {String.to_atom(key), false}
        [key, value] -> {String.to_atom(key), value}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end
  
  defp encode_baggage(baggage) when is_map(baggage) do
    baggage
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode(to_string(v))}" end)
    |> Enum.join(",")
  end
  
  defp decode_baggage(baggage_string) when is_binary(baggage_string) do
    baggage_string
    |> String.split(",", trim: true)
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> {key, URI.decode(value)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end
end