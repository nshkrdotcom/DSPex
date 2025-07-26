defmodule DSPex.Bridge.Tools.Executor do
  @moduledoc """
  Safe execution layer for bidirectional tools.
  
  This module handles:
  - Safe tool execution with error handling
  - Timeout enforcement
  - Telemetry events
  - Input/output validation
  - Execution context management
  
  ## Telemetry Events
  
  Emits the following telemetry events:
  
  - `[:dspex, :tools, :execute, :start]` - When tool execution begins
  - `[:dspex, :tools, :execute, :stop]` - When tool execution completes successfully
  - `[:dspex, :tools, :execute, :exception]` - When tool execution fails
  
  ## Example
  
      {:ok, result} = Executor.execute("validate_email", 
        %{"email" => "test@example.com"},
        %{session_id: "sess-123", caller: :python}
      )
  """
  
  require Logger
  
  @default_timeout 5_000  # 5 seconds
  @max_timeout 60_000     # 1 minute
  
  @type execution_context :: %{
    required(:session_id) => String.t(),
    optional(:caller) => :python | :elixir,
    optional(:timeout) => pos_integer(),
    optional(:metadata) => map(),
    optional(:async) => boolean()
  }
  
  @doc """
  Executes a registered tool with the given arguments and context.
  
  ## Arguments
  
  - `tool_name` - Name of the registered tool
  - `args` - Arguments to pass to the tool (must be a map)
  - `context` - Execution context including session_id, timeout, etc.
  
  ## Options
  
  The context map supports:
  
  - `:session_id` (required) - Session identifier
  - `:caller` - Who is calling the tool (:python or :elixir), defaults to :elixir
  - `:timeout` - Execution timeout in milliseconds, defaults to 5000
  - `:metadata` - Additional metadata for telemetry
  - `:async` - If true, returns a Task instead of waiting for result
  
  ## Return Values
  
  - `{:ok, result}` - Tool executed successfully
  - `{:error, :not_found}` - Tool not registered
  - `{:error, :timeout}` - Tool execution timed out
  - `{:error, {:exception, error}}` - Tool raised an exception
  - `{:error, reason}` - Other errors
  
  When `async: true`, returns `{:ok, %Task{}}` instead.
  """
  @spec execute(String.t(), map(), execution_context()) :: 
    {:ok, any()} | {:ok, Task.t()} | {:error, term()}
  def execute(tool_name, args, context) when is_map(args) do
    with :ok <- validate_context(context),
         {:ok, {module, function, tool_metadata}} <- DSPex.Bridge.Tools.Registry.lookup(tool_name) do
      
      if Map.get(context, :async, false) do
        execute_async(tool_name, module, function, args, context, tool_metadata)
      else
        execute_sync(tool_name, module, function, args, context, tool_metadata)
      end
    end
  end
  
  def execute(tool_name, args, _context) when not is_map(args) do
    {:error, {:invalid_args, "Arguments must be a map, got: #{inspect(args)}"}}
  end
  
  @doc """
  Executes a tool asynchronously and returns a Task.
  
  The task can be awaited with `Task.await/2` or `Task.yield/2`.
  """
  @spec execute_async(String.t(), map(), execution_context()) :: {:ok, Task.t()} | {:error, term()}
  def execute_async(tool_name, args, context) do
    execute(tool_name, args, Map.put(context, :async, true))
  end
  
  # Private functions
  
  defp validate_context(context) do
    cond do
      not Map.has_key?(context, :session_id) ->
        {:error, :missing_session_id}
        
      not is_binary(context.session_id) ->
        {:error, {:invalid_session_id, "Session ID must be a string"}}
        
      Map.has_key?(context, :timeout) and context.timeout > @max_timeout ->
        {:error, {:invalid_timeout, "Timeout cannot exceed #{@max_timeout}ms"}}
        
      true ->
        :ok
    end
  end
  
  defp execute_sync(tool_name, module, function, args, context, tool_metadata) do
    timeout = Map.get(context, :timeout, @default_timeout)
    
    # Emit start event
    start_time = System.monotonic_time()
    start_metadata = build_telemetry_metadata(tool_name, context, tool_metadata)
    
    :telemetry.execute(
      [:dspex, :tools, :execute, :start],
      %{system_time: System.system_time()},
      start_metadata
    )
    
    # Execute with timeout
    try do
      task = Task.async(fn ->
        apply(module, function, [args])
      end)
      
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          # Emit stop event
          duration = System.monotonic_time() - start_time
          
          :telemetry.execute(
            [:dspex, :tools, :execute, :stop],
            %{duration: duration, system_time: System.system_time()},
            Map.put(start_metadata, :result_type, type_of(result))
          )
          
          Logger.debug("Tool #{tool_name} executed successfully in #{duration_ms(duration)}ms")
          
          {:ok, result}
          
        nil ->
          # Timeout
          duration = System.monotonic_time() - start_time
          
          :telemetry.execute(
            [:dspex, :tools, :execute, :exception],
            %{duration: duration, system_time: System.system_time()},
            Map.merge(start_metadata, %{
              kind: :timeout,
              reason: :timeout,
              timeout: timeout
            })
          )
          
          Logger.warning("Tool #{tool_name} timed out after #{timeout}ms")
          
          {:error, :timeout}
          
        {:exit, reason} ->
          # Task crashed
          duration = System.monotonic_time() - start_time
          
          :telemetry.execute(
            [:dspex, :tools, :execute, :exception],
            %{duration: duration, system_time: System.system_time()},
            Map.merge(start_metadata, %{
              kind: :exit,
              reason: reason
            })
          )
          
          Logger.error("Tool #{tool_name} crashed: #{inspect(reason)}")
          
          {:error, {:exception, reason}}
      end
    rescue
      error ->
        # This shouldn't happen, but just in case
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          [:dspex, :tools, :execute, :exception],
          %{duration: duration, system_time: System.system_time()},
          Map.merge(start_metadata, %{
            kind: :error,
            error: error,
            stacktrace: __STACKTRACE__
          })
        )
        
        Logger.error("Tool executor error for #{tool_name}: #{inspect(error)}")
        
        {:error, {:executor_error, error}}
    end
  end
  
  defp execute_async(tool_name, module, function, args, context, tool_metadata) do
    task = Task.async(fn ->
      # Run the sync version in the task
      execute_sync(tool_name, module, function, args, context, tool_metadata)
    end)
    
    {:ok, task}
  end
  
  defp build_telemetry_metadata(tool_name, context, tool_metadata) do
    %{
      tool_name: tool_name,
      session_id: context.session_id,
      caller: Map.get(context, :caller, :elixir),
      tool_metadata: tool_metadata,
      context_metadata: Map.get(context, :metadata, %{})
    }
  end
  
  defp type_of(value) do
    cond do
      is_nil(value) -> :nil
      is_binary(value) -> :string
      is_atom(value) -> :atom
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_list(value) -> :list
      is_map(value) -> :map
      is_tuple(value) -> :tuple
      is_pid(value) -> :pid
      is_reference(value) -> :reference
      is_function(value) -> :function
      true -> :unknown
    end
  end
  
  defp duration_ms(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end
end