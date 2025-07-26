# Prompt: Implement Tools System

## Context

You are implementing the **Tools System** for the SnakepitGRPCBridge ML platform. This prompt covers **Phase 1, Day 4** of the implementation plan.

## Required Reading

Before starting, read these documents in order:
1. `docs/specs/threeLayerRevised/03_SNAKEPIT_GRPC_BRIDGE_PLATFORM_SPECIFICATION.md` - Platform specification (Tools section)
2. `docs/specs/threeLayerRevised/07_DETAILED_IN_PLACE_IMPLEMENTATION_PLAN.md` - Implementation plan (Day 4)

## Prerequisites

Complete the previous phases:
- SnakepitGRPCBridge package bootstrapped
- Variables system fully implemented and tested
- Basic adapter routing working

## Current State Analysis

Examine the current tool implementations:
- `./lib/dspex/tools/` (if exists) - Current DSPex tool logic
- `./snakepit/lib/snakepit/bridge/` (if exists) - Current bridge tool logic
- Look for any existing tool registration and execution code
- Identify current Python ↔ Elixir communication mechanisms

Identify:
1. Current tool registration patterns
2. Existing function calling mechanisms
3. Parameter serialization/validation approaches
4. Any bidirectional communication code

## Objective

Implement a complete tools system that:
1. Registers Elixir functions as callable tools from Python
2. Registers Python functions as callable tools from Elixir
3. Provides safe parameter serialization and validation
4. Enables bidirectional function calling
5. Supports tool discovery and metadata
6. Includes comprehensive error handling and telemetry

## Implementation Tasks

### Task 1: Implement Tools Registry

Create `lib/snakepit_grpc_bridge/tools/registry.ex`:

```elixir
defmodule SnakepitGRPCBridge.Tools.Registry do
  @moduledoc """
  Tool registration and discovery for the ML platform.
  
  Manages registration of both Elixir and Python functions as callable tools,
  with metadata, validation, and discovery capabilities.
  """
  
  use GenServer
  require Logger

  defstruct [
    :tools,              # ETS table for registered tools
    :sessions,           # ETS table for session metadata
    :telemetry_collector,
    :stats
  ]

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an Elixir function as a tool.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.Tools.Registry.register_tool(
        "session_123",
        "validate_email", 
        &MyApp.Validators.validate_email/1,
        %{
          description: "Validate email address format",
          parameters: [%{name: "email", type: "string", required: true}],
          returns: %{type: "boolean", description: "true if valid email"}
        }
      )
  """
  def register_tool(session_id, name, function, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_tool, session_id, name, function, metadata})
  end

  @doc """
  Register a Python function as a tool.
  
  ## Examples
  
      :ok = SnakepitGRPCBridge.Tools.Registry.register_python_tool(
        "session_123",
        "calculate_similarity",
        "similarity_module.cosine_similarity",
        %{
          description: "Calculate cosine similarity between vectors",
          parameters: [
            %{name: "vector1", type: "list", required: true},
            %{name: "vector2", type: "list", required: true}
          ]
        }
      )
  """
  def register_python_tool(session_id, name, python_function_path, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_python_tool, session_id, name, python_function_path, metadata})
  end

  @doc """
  Unregister a tool from a session.
  """
  def unregister_tool(session_id, name) do
    GenServer.call(__MODULE__, {:unregister_tool, session_id, name})
  end

  @doc """
  List all registered tools in a session.
  """
  def list_tools(session_id) do
    GenServer.call(__MODULE__, {:list_tools, session_id})
  end

  @doc """
  Get detailed information about a specific tool.
  """
  def get_tool(session_id, name) do
    GenServer.call(__MODULE__, {:get_tool, session_id, name})
  end

  @doc """
  Search for tools by name pattern or metadata.
  """
  def search_tools(session_id, query) do
    GenServer.call(__MODULE__, {:search_tools, session_id, query})
  end

  @doc """
  Get tools statistics for a session.
  """
  def get_session_stats(session_id) do
    GenServer.call(__MODULE__, {:get_session_stats, session_id})
  end

  # GenServer callbacks

  def init(_opts) do
    state = %__MODULE__{
      tools: :ets.new(:tools_registry, [:set, :public, :named_table]),
      sessions: :ets.new(:tool_sessions, [:set, :public, :named_table]),
      telemetry_collector: initialize_telemetry_collector(),
      stats: initialize_stats()
    }
    
    Logger.info("Tools registry started")
    {:ok, state}
  end

  def handle_call({:register_tool, session_id, name, function, metadata}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    tool_key = {session_id, name}
    
    # Validate function
    case validate_elixir_function(function) do
      :ok ->
        tool = %{
          name: name,
          type: :elixir_function,
          function: function,
          metadata: enrich_metadata(metadata, :elixir_function),
          registered_at: DateTime.utc_now(),
          session_id: session_id,
          call_count: 0,
          last_called: nil,
          avg_execution_time: 0
        }
        
        :ets.insert(state.tools, {tool_key, tool})
        update_session_stats(session_id, :tool_registered, state)
        
        Logger.debug("Elixir tool registered", 
                    session_id: session_id, 
                    name: name, 
                    arity: get_function_arity(function))
        
        # Collect telemetry
        execution_time = System.monotonic_time(:microsecond) - start_time
        collect_registry_telemetry(:register_elixir, session_id, name, :ok, execution_time)
        
        {:reply, :ok, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_python_tool, session_id, name, python_function_path, metadata}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    tool_key = {session_id, name}
    
    # Create wrapper function that calls into Python
    python_wrapper = create_python_wrapper(python_function_path)
    
    tool = %{
      name: name,
      type: :python_function,
      function: python_wrapper,
      python_path: python_function_path,
      metadata: enrich_metadata(metadata, :python_function),
      registered_at: DateTime.utc_now(),
      session_id: session_id,
      call_count: 0,
      last_called: nil,
      avg_execution_time: 0
    }
    
    :ets.insert(state.tools, {tool_key, tool})
    update_session_stats(session_id, :python_tool_registered, state)
    
    Logger.debug("Python tool registered", 
                session_id: session_id, 
                name: name, 
                python_path: python_function_path)
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_registry_telemetry(:register_python, session_id, name, :ok, execution_time)
    
    {:reply, :ok, state}
  end

  def handle_call({:unregister_tool, session_id, name}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    tool_key = {session_id, name}
    
    result = case :ets.lookup(state.tools, tool_key) do
      [{^tool_key, tool}] ->
        :ets.delete(state.tools, tool_key)
        update_session_stats(session_id, :tool_unregistered, state)
        
        Logger.debug("Tool unregistered", 
                    session_id: session_id, 
                    name: name, 
                    type: tool.type)
        :ok
      
      [] ->
        {:error, :tool_not_found}
    end
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_registry_telemetry(:unregister, session_id, name, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:list_tools, session_id}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    pattern = {{session_id, :_}, :_}
    tools = :ets.match_object(state.tools, pattern)
    
    tool_list = Enum.map(tools, fn {{_session, name}, tool} ->
      %{
        name: name,
        type: tool.type,
        metadata: tool.metadata,
        registered_at: tool.registered_at,
        call_count: tool.call_count,
        last_called: tool.last_called,
        avg_execution_time: tool.avg_execution_time
      }
    end)
    
    result = {:ok, tool_list}
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_registry_telemetry(:list, session_id, :all, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:get_tool, session_id, name}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    tool_key = {session_id, name}
    
    result = case :ets.lookup(state.tools, tool_key) do
      [{^tool_key, tool}] -> 
        {:ok, tool}
      [] -> 
        {:error, :tool_not_found}
    end
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_registry_telemetry(:get, session_id, name, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:search_tools, session_id, query}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    pattern = {{session_id, :_}, :_}
    all_tools = :ets.match_object(state.tools, pattern)
    
    matching_tools = Enum.filter(all_tools, fn {{_session, name}, tool} ->
      tool_matches_query(name, tool, query)
    end)
    
    tool_list = Enum.map(matching_tools, fn {{_session, name}, tool} ->
      %{
        name: name,
        type: tool.type,
        metadata: tool.metadata,
        relevance_score: calculate_relevance_score(name, tool, query)
      }
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
    
    result = {:ok, tool_list}
    
    # Collect telemetry
    execution_time = System.monotonic_time(:microsecond) - start_time
    collect_registry_telemetry(:search, session_id, query, result, execution_time)
    
    {:reply, result, state}
  end

  def handle_call({:get_session_stats, session_id}, _from, state) do
    pattern = {{session_id, :_}, :_}
    tools = :ets.match_object(state.tools, pattern)
    
    stats = %{
      total_tools: length(tools),
      elixir_tools: count_tools_by_type(tools, :elixir_function),
      python_tools: count_tools_by_type(tools, :python_function),
      total_calls: sum_tool_calls(tools),
      avg_execution_time: calculate_avg_execution_time(tools),
      most_used_tool: find_most_used_tool(tools),
      session_id: session_id,
      generated_at: DateTime.utc_now()
    }
    
    {:reply, {:ok, stats}, state}
  end

  # Tool execution tracking (called by executor)
  def record_tool_execution(session_id, tool_name, execution_time, result) do
    GenServer.cast(__MODULE__, {:record_execution, session_id, tool_name, execution_time, result})
  end

  def handle_cast({:record_execution, session_id, tool_name, execution_time, result}, state) do
    tool_key = {session_id, tool_name}
    
    case :ets.lookup(state.tools, tool_key) do
      [{^tool_key, tool}] ->
        # Update tool statistics
        new_call_count = tool.call_count + 1
        new_avg_time = calculate_new_average(tool.avg_execution_time, tool.call_count, execution_time)
        
        updated_tool = %{tool |
          call_count: new_call_count,
          last_called: DateTime.utc_now(),
          avg_execution_time: new_avg_time
        }
        
        :ets.insert(state.tools, {tool_key, updated_tool})
        
        Logger.debug("Tool execution recorded", 
                    session_id: session_id, 
                    tool_name: tool_name, 
                    execution_time: execution_time,
                    success: match?({:ok, _}, result))
      
      [] ->
        Logger.warning("Attempted to record execution for unknown tool", 
                      session_id: session_id, 
                      tool_name: tool_name)
    end
    
    {:noreply, state}
  end

  # Private implementation functions

  defp validate_elixir_function(function) when is_function(function) do
    case Function.info(function) do
      [{:module, _module}, {:name, _name}, {:arity, arity}, {:env, _env}, {:type, _type}] ->
        if arity == 1 do
          :ok
        else
          {:error, {:invalid_arity, arity, "Tools must accept exactly 1 parameter (a map)"}}
        end
      
      _ ->
        {:error, :invalid_function_info}
    end
  end
  defp validate_elixir_function(_), do: {:error, :not_a_function}

  defp get_function_arity(function) when is_function(function) do
    case Function.info(function) do
      [{:module, _}, {:name, _}, {:arity, arity}, {:env, _}, {:type, _}] -> arity
      _ -> :unknown
    end
  end

  defp enrich_metadata(metadata, :elixir_function) do
    Map.merge(%{
      type: "elixir_function",
      description: "Elixir function tool",
      parameters: [],
      returns: %{type: "any", description: "Function return value"},
      platform: "elixir"
    }, metadata)
  end

  defp enrich_metadata(metadata, :python_function) do
    Map.merge(%{
      type: "python_function", 
      description: "Python function tool",
      parameters: [],
      returns: %{type: "any", description: "Function return value"},
      platform: "python"
    }, metadata)
  end

  defp create_python_wrapper(python_function_path) do
    fn parameters ->
      # This wrapper will call into the Python bridge
      SnakepitGRPCBridge.Python.Bridge.call_function(python_function_path, parameters)
    end
  end

  defp update_session_stats(session_id, event, state) do
    # Update session statistics
    case :ets.lookup(state.sessions, session_id) do
      [{^session_id, session_stats}] ->
        updated_stats = increment_session_stat(session_stats, event)
        :ets.insert(state.sessions, {session_id, updated_stats})
      
      [] ->
        # Initialize session stats
        initial_stats = %{
          session_id: session_id,
          tools_registered: 0,
          python_tools_registered: 0,
          tools_unregistered: 0,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
        updated_stats = increment_session_stat(initial_stats, event)
        :ets.insert(state.sessions, {session_id, updated_stats})
    end
  end

  defp increment_session_stat(stats, :tool_registered) do
    %{stats | 
      tools_registered: stats.tools_registered + 1,
      last_activity: DateTime.utc_now()
    }
  end

  defp increment_session_stat(stats, :python_tool_registered) do
    %{stats | 
      tools_registered: stats.tools_registered + 1,
      python_tools_registered: stats.python_tools_registered + 1,
      last_activity: DateTime.utc_now()
    }
  end

  defp increment_session_stat(stats, :tool_unregistered) do
    %{stats | 
      tools_unregistered: stats.tools_unregistered + 1,
      last_activity: DateTime.utc_now()
    }
  end

  defp tool_matches_query(name, tool, query) when is_binary(query) do
    # Simple text matching
    query_lower = String.downcase(query)
    name_matches = String.contains?(String.downcase(name), query_lower)
    description_matches = String.contains?(String.downcase(tool.metadata[:description] || ""), query_lower)
    
    name_matches or description_matches
  end

  defp tool_matches_query(name, tool, %{type: type}) do
    tool.type == type
  end

  defp tool_matches_query(_name, _tool, _query), do: true

  defp calculate_relevance_score(name, tool, query) when is_binary(query) do
    query_lower = String.downcase(query)
    
    # Name exact match gets highest score
    name_score = if String.downcase(name) == query_lower, do: 100, else: 0
    
    # Name contains gets medium score
    name_contains_score = if String.contains?(String.downcase(name), query_lower), do: 50, else: 0
    
    # Description contains gets low score
    description_score = if String.contains?(String.downcase(tool.metadata[:description] || ""), query_lower), do: 25, else: 0
    
    # Recent usage boosts score
    usage_score = min(tool.call_count, 10)
    
    name_score + name_contains_score + description_score + usage_score
  end

  defp calculate_relevance_score(_name, _tool, _query), do: 50

  defp count_tools_by_type(tools, type) do
    Enum.count(tools, fn {_key, tool} -> tool.type == type end)
  end

  defp sum_tool_calls(tools) do
    Enum.reduce(tools, 0, fn {_key, tool}, acc -> acc + tool.call_count end)
  end

  defp calculate_avg_execution_time(tools) do
    if length(tools) > 0 do
      total_time = Enum.reduce(tools, 0, fn {_key, tool}, acc -> 
        acc + (tool.avg_execution_time * tool.call_count)
      end)
      total_calls = sum_tool_calls(tools)
      
      if total_calls > 0, do: total_time / total_calls, else: 0
    else
      0
    end
  end

  defp find_most_used_tool(tools) do
    case Enum.max_by(tools, fn {_key, tool} -> tool.call_count end, fn -> nil end) do
      {{_session, name}, tool} -> %{name: name, call_count: tool.call_count}
      nil -> nil
    end
  end

  defp calculate_new_average(current_avg, current_count, new_value) do
    if current_count == 0 do
      new_value
    else
      (current_avg * current_count + new_value) / (current_count + 1)
    end
  end

  defp collect_registry_telemetry(operation, session_id, identifier, result, execution_time) do
    telemetry_data = %{
      operation: operation,
      session_id: session_id,
      identifier: identifier,
      success: result == :ok or match?({:ok, _}, result),
      execution_time_microseconds: execution_time,
      timestamp: DateTime.utc_now()
    }
    
    :telemetry.execute([:snakepit_grpc_bridge, :tools, :registry], telemetry_data)
  end

  defp initialize_telemetry_collector do
    %{
      operations_count: 0,
      total_execution_time: 0,
      last_operation: nil
    }
  end

  defp initialize_stats do
    %{
      total_registrations: 0,
      total_unregistrations: 0,
      total_lookups: 0,
      total_searches: 0
    }
  end
end
```

### Task 2: Implement Tools Executor

Create `lib/snakepit_grpc_bridge/tools/executor.ex`:

```elixir
defmodule SnakepitGRPCBridge.Tools.Executor do
  @moduledoc """
  Tool execution engine with parameter validation and error handling.
  
  Provides safe execution of both Elixir and Python tools with comprehensive
  parameter validation, serialization, and telemetry collection.
  """
  
  require Logger

  @doc """
  Execute a registered tool with given parameters.
  
  ## Examples
  
      {:ok, result} = SnakepitGRPCBridge.Tools.Executor.execute_tool(
        "session_123",
        "validate_email",
        %{"email" => "user@example.com"}
      )
  """
  def execute_tool(session_id, tool_name, parameters) do
    start_time = System.monotonic_time(:microsecond)
    
    Logger.debug("Executing tool", 
                session_id: session_id, 
                tool_name: tool_name, 
                params_count: map_size(parameters))
    
    case SnakepitGRPCBridge.Tools.Registry.get_tool(session_id, tool_name) do
      {:ok, tool} ->
        execute_tool_impl(tool, parameters, session_id, start_time)
      
      {:error, :tool_not_found} ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        collect_execution_telemetry(tool_name, parameters, {:error, :tool_not_found}, execution_time, session_id)
        {:error, {:tool_not_found, tool_name}}
    end
  end

  @doc """
  Execute a tool with streaming results.
  
  Calls the callback function for each result chunk.
  """
  def execute_tool_stream(session_id, tool_name, parameters, callback_fn) do
    case SnakepitGRPCBridge.Tools.Registry.get_tool(session_id, tool_name) do
      {:ok, tool} ->
        if supports_streaming?(tool) do
          execute_streaming_tool(tool, parameters, callback_fn, session_id)
        else
          {:error, {:streaming_not_supported, tool_name}}
        end
      
      {:error, :tool_not_found} ->
        {:error, {:tool_not_found, tool_name}}
    end
  end

  @doc """
  Validate tool parameters against metadata schema.
  """
  def validate_parameters(tool, parameters) do
    SnakepitGRPCBridge.Tools.Validation.validate_parameters(tool, parameters)
  end

  # Private implementation functions

  defp execute_tool_impl(tool, parameters, session_id, start_time) do
    # Validate parameters against tool metadata
    case validate_parameters(tool, parameters) do
      :ok ->
        execute_validated_tool(tool, parameters, session_id, start_time)
      
      {:error, validation_errors} ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        result = {:error, {:validation_failed, validation_errors}}
        collect_execution_telemetry(tool.name, parameters, result, execution_time, session_id)
        result
    end
  end

  defp execute_validated_tool(tool, parameters, session_id, start_time) do
    try do
      # Serialize parameters based on tool type
      serialized_params = serialize_parameters(parameters, tool.type)
      
      # Execute the tool function
      raw_result = tool.function.(serialized_params)
      
      # Deserialize result
      result = deserialize_result(raw_result, tool.type)
      
      execution_time = System.monotonic_time(:microsecond) - start_time
      
      # Record execution statistics
      SnakepitGRPCBridge.Tools.Registry.record_tool_execution(
        session_id, tool.name, execution_time, result
      )
      
      # Collect telemetry
      collect_execution_telemetry(tool.name, parameters, result, execution_time, session_id)
      
      Logger.debug("Tool executed successfully", 
                  session_id: session_id, 
                  tool_name: tool.name, 
                  execution_time_ms: execution_time / 1000)
      
      result
      
    rescue
      exception ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        error_message = Exception.message(exception)
        result = {:error, {:execution_failed, error_message}}
        
        # Record failed execution
        SnakepitGRPCBridge.Tools.Registry.record_tool_execution(
          session_id, tool.name, execution_time, result
        )
        
        # Collect error telemetry
        collect_execution_telemetry(tool.name, parameters, result, execution_time, session_id)
        
        Logger.error("Tool execution failed", 
                    session_id: session_id, 
                    tool_name: tool.name, 
                    error: error_message, 
                    exception: exception)
        
        result
    end
  end

  defp execute_streaming_tool(tool, parameters, callback_fn, session_id) do
    start_time = System.monotonic_time(:microsecond)
    
    try do
      # For streaming tools, we expect the function to call the callback
      result = tool.function.(parameters, callback_fn)
      
      execution_time = System.monotonic_time(:microsecond) - start_time
      collect_execution_telemetry(tool.name, parameters, {:ok, :streaming_completed}, execution_time, session_id)
      
      result
      
    rescue
      exception ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        error_message = Exception.message(exception)
        result = {:error, {:streaming_execution_failed, error_message}}
        
        collect_execution_telemetry(tool.name, parameters, result, execution_time, session_id)
        
        Logger.error("Streaming tool execution failed", 
                    session_id: session_id, 
                    tool_name: tool.name, 
                    error: error_message)
        
        result
    end
  end

  defp serialize_parameters(parameters, :elixir_function) do
    # For Elixir functions, pass parameters as-is (they're already Elixir terms)
    parameters
  end

  defp serialize_parameters(parameters, :python_function) do
    # For Python functions, ensure parameters are JSON-serializable
    SnakepitGRPCBridge.Tools.Serialization.serialize_for_python(parameters)
  end

  defp deserialize_result(result, :elixir_function) do
    # Elixir function results are already in the correct format
    {:ok, result}
  end

  defp deserialize_result(result, :python_function) do
    # Deserialize Python function results
    SnakepitGRPCBridge.Tools.Serialization.deserialize_from_python(result)
  end

  defp supports_streaming?(tool) do
    # Check if tool metadata indicates streaming support
    get_in(tool.metadata, [:capabilities, :streaming]) == true
  end

  defp collect_execution_telemetry(tool_name, parameters, result, execution_time, session_id) do
    telemetry_data = %{
      tool_name: tool_name,
      session_id: session_id,
      parameters_count: map_size(parameters),
      parameters_size: :erlang.external_size(parameters),
      success: match?({:ok, _}, result),
      execution_time_microseconds: execution_time,
      timestamp: DateTime.utc_now()
    }
    
    # Add error details if execution failed
    telemetry_data = case result do
      {:error, {error_type, _details}} ->
        Map.put(telemetry_data, :error_type, error_type)
      _ ->
        telemetry_data
    end
    
    :telemetry.execute([:snakepit_grpc_bridge, :tools, :execution], telemetry_data)
  end
end
```

### Task 3: Implement Parameter Validation

Create `lib/snakepit_grpc_bridge/tools/validation.ex`:

```elixir
defmodule SnakepitGRPCBridge.Tools.Validation do
  @moduledoc """
  Parameter validation for tool execution.
  
  Validates tool parameters against metadata schemas to ensure safe execution.
  """

  @doc """
  Validate parameters against tool metadata schema.
  
  Returns :ok if all validations pass, or {:error, errors} with detailed error information.
  """
  def validate_parameters(tool, parameters) do
    case tool.metadata[:parameters] do
      nil ->
        # No parameter schema defined, accept anything
        :ok
      
      parameter_schema when is_list(parameter_schema) ->
        validate_against_schema(parameters, parameter_schema)
      
      _ ->
        {:error, [:invalid_parameter_schema]}
    end
  end

  defp validate_against_schema(parameters, schema) do
    errors = []
    
    # Check required parameters
    errors = check_required_parameters(parameters, schema, errors)
    
    # Check parameter types
    errors = check_parameter_types(parameters, schema, errors)
    
    # Check parameter constraints
    errors = check_parameter_constraints(parameters, schema, errors)
    
    # Check for unknown parameters
    errors = check_unknown_parameters(parameters, schema, errors)
    
    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp check_required_parameters(parameters, schema, errors) do
    required_params = Enum.filter(schema, fn param -> 
      Map.get(param, :required, false) or Map.get(param, "required", false)
    end)
    
    Enum.reduce(required_params, errors, fn param, acc ->
      param_name = get_param_name(param)
      
      if Map.has_key?(parameters, param_name) do
        acc
      else
        [{:missing_required_parameter, param_name} | acc]
      end
    end)
  end

  defp check_parameter_types(parameters, schema, errors) do
    Enum.reduce(schema, errors, fn param, acc ->
      param_name = get_param_name(param)
      param_type = get_param_type(param)
      
      case Map.get(parameters, param_name) do
        nil ->
          # Parameter not provided, skip type check
          acc
        
        value ->
          if validate_type(value, param_type) do
            acc
          else
            [{:invalid_type, param_name, param_type, typeof(value)} | acc]
          end
      end
    end)
  end

  defp check_parameter_constraints(parameters, schema, errors) do
    Enum.reduce(schema, errors, fn param, acc ->
      param_name = get_param_name(param)
      constraints = get_param_constraints(param)
      
      case Map.get(parameters, param_name) do
        nil ->
          # Parameter not provided, skip constraint check
          acc
        
        value ->
          constraint_errors = validate_constraints(value, constraints, param_name)
          constraint_errors ++ acc
      end
    end)
  end

  defp check_unknown_parameters(parameters, schema, errors) do
    known_params = Enum.map(schema, &get_param_name/1) |> MapSet.new()
    provided_params = Map.keys(parameters) |> MapSet.new()
    unknown_params = MapSet.difference(provided_params, known_params)
    
    Enum.reduce(unknown_params, errors, fn param_name, acc ->
      [{:unknown_parameter, param_name} | acc]
    end)
  end

  defp get_param_name(param) do
    Map.get(param, :name) || Map.get(param, "name")
  end

  defp get_param_type(param) do
    Map.get(param, :type) || Map.get(param, "type") || "any"
  end

  defp get_param_constraints(param) do
    Map.get(param, :constraints) || Map.get(param, "constraints") || %{}
  end

  defp validate_type(value, "string"), do: is_binary(value)
  defp validate_type(value, "integer"), do: is_integer(value)
  defp validate_type(value, "float"), do: is_float(value)
  defp validate_type(value, "number"), do: is_number(value)
  defp validate_type(value, "boolean"), do: is_boolean(value)
  defp validate_type(value, "list"), do: is_list(value)
  defp validate_type(value, "map"), do: is_map(value)
  defp validate_type(value, "object"), do: is_map(value)
  defp validate_type(_value, "any"), do: true
  defp validate_type(_value, _unknown_type), do: true  # Accept unknown types

  defp validate_constraints(value, constraints, param_name) do
    Enum.reduce(constraints, [], fn {constraint, constraint_value}, acc ->
      case validate_constraint(value, constraint, constraint_value) do
        true -> acc
        false -> [{:constraint_violation, param_name, constraint, constraint_value} | acc]
      end
    end)
  end

  defp validate_constraint(value, "min_length", min_length) when is_binary(value) do
    String.length(value) >= min_length
  end

  defp validate_constraint(value, "max_length", max_length) when is_binary(value) do
    String.length(value) <= max_length
  end

  defp validate_constraint(value, "min", min_value) when is_number(value) do
    value >= min_value
  end

  defp validate_constraint(value, "max", max_value) when is_number(value) do
    value <= max_value
  end

  defp validate_constraint(value, "pattern", pattern) when is_binary(value) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, value)
      {:error, _} -> true  # Invalid regex, skip validation
    end
  end

  defp validate_constraint(value, "enum", allowed_values) when is_list(allowed_values) do
    value in allowed_values
  end

  defp validate_constraint(_value, _constraint, _constraint_value) do
    # Unknown constraint, assume valid
    true
  end

  defp typeof(value) do
    cond do
      is_binary(value) -> "string"
      is_integer(value) -> "integer"
      is_float(value) -> "float"
      is_boolean(value) -> "boolean"
      is_list(value) -> "list"
      is_map(value) -> "map"
      true -> "unknown"
    end
  end
end
```

### Task 4: Implement Serialization

Create `lib/snakepit_grpc_bridge/tools/serialization.ex`:

```elixir
defmodule SnakepitGRPCBridge.Tools.Serialization do
  @moduledoc """
  Serialization utilities for tool parameters and results.
  
  Handles conversion between Elixir and Python data formats.
  """

  @doc """
  Serialize parameters for Python function calls.
  """
  def serialize_for_python(parameters) when is_map(parameters) do
    try do
      # Convert Elixir atoms to strings for JSON compatibility
      parameters
      |> convert_atoms_to_strings()
      |> ensure_json_compatible()
    rescue
      exception ->
        {:error, {:serialization_failed, Exception.message(exception)}}
    end
  end

  @doc """
  Deserialize results from Python function calls.
  """
  def deserialize_from_python({:ok, result}) do
    {:ok, convert_strings_to_atoms(result)}
  end

  def deserialize_from_python({:error, reason}) do
    {:error, reason}
  end

  def deserialize_from_python(result) do
    # Handle raw Python results
    {:ok, convert_strings_to_atoms(result)}
  end

  @doc """
  Serialize parameters for Elixir function calls.
  """
  def serialize_for_elixir(parameters) do
    # Elixir functions receive parameters as-is
    parameters
  end

  @doc """
  Check if data is JSON-compatible.
  """
  def json_compatible?(data) do
    case Jason.encode(data) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Private implementation functions

  defp convert_atoms_to_strings(data) when is_map(data) do
    for {key, value} <- data, into: %{} do
      new_key = if is_atom(key), do: Atom.to_string(key), else: key
      new_value = convert_atoms_to_strings(value)
      {new_key, new_value}
    end
  end

  defp convert_atoms_to_strings(data) when is_list(data) do
    Enum.map(data, &convert_atoms_to_strings/1)
  end

  defp convert_atoms_to_strings(data) when is_atom(data) do
    if data in [nil, true, false] do
      data
    else
      Atom.to_string(data)
    end
  end

  defp convert_atoms_to_strings(data), do: data

  defp convert_strings_to_atoms(data) when is_map(data) do
    for {key, value} <- data, into: %{} do
      new_key = if is_binary(key) and valid_atom_string?(key) do
        String.to_atom(key)
      else
        key
      end
      new_value = convert_strings_to_atoms(value)
      {new_key, new_value}
    end
  end

  defp convert_strings_to_atoms(data) when is_list(data) do
    Enum.map(data, &convert_strings_to_atoms/1)
  end

  defp convert_strings_to_atoms(data), do: data

  defp valid_atom_string?(string) do
    # Only convert simple, safe strings to atoms
    String.match?(string, ~r/^[a-z_][a-z0-9_]*$/) and String.length(string) < 100
  end

  defp ensure_json_compatible(data) do
    case Jason.encode(data) do
      {:ok, _} ->
        data
      
      {:error, reason} ->
        # Try to fix common JSON incompatibility issues
        fixed_data = fix_json_incompatibility(data)
        
        case Jason.encode(fixed_data) do
          {:ok, _} -> fixed_data
          {:error, _} -> raise "Data cannot be made JSON compatible: #{inspect(reason)}"
        end
    end
  end

  defp fix_json_incompatibility(data) when is_map(data) do
    for {key, value} <- data, into: %{} do
      new_key = fix_json_incompatibility(key)
      new_value = fix_json_incompatibility(value)
      {new_key, new_value}
    end
  end

  defp fix_json_incompatibility(data) when is_list(data) do
    Enum.map(data, &fix_json_incompatibility/1)
  end

  defp fix_json_incompatibility(data) when is_pid(data) do
    inspect(data)
  end

  defp fix_json_incompatibility(data) when is_reference(data) do
    inspect(data)
  end

  defp fix_json_incompatibility(data) when is_function(data) do
    "#Function<#{inspect(data)}>"
  end

  defp fix_json_incompatibility(data) when is_tuple(data) do
    data |> Tuple.to_list() |> fix_json_incompatibility()
  end

  defp fix_json_incompatibility(data), do: data
end
```

### Task 5: Update Tools API

Update `lib/snakepit_grpc_bridge/api/tools.ex`:

```elixir
defmodule SnakepitGRPCBridge.API.Tools do
  @moduledoc """
  Clean API for tool bridge operations.
  """

  alias SnakepitGRPCBridge.Tools.{Registry, Executor}

  def register_elixir_function(session_id, name, function, opts \\ []) do
    metadata = %{
      description: Keyword.get(opts, :description, ""),
      parameters: Keyword.get(opts, :parameters, []),
      returns: Keyword.get(opts, :returns, %{}),
      type: :elixir_function,
      registered_at: DateTime.utc_now()
    }
    
    Registry.register_tool(session_id, name, function, metadata)
  end

  def register_python_function(session_id, name, python_function_path, opts \\ []) do
    metadata = %{
      description: Keyword.get(opts, :description, ""),
      parameters: Keyword.get(opts, :parameters, []),
      returns: Keyword.get(opts, :returns, %{}),
      type: :python_function,
      python_path: python_function_path,
      registered_at: DateTime.utc_now()
    }
    
    Registry.register_python_tool(session_id, name, python_function_path, metadata)
  end

  def call(session_id, tool_name, parameters) do
    Executor.execute_tool(session_id, tool_name, parameters)
  end

  def call_stream(session_id, tool_name, parameters, callback_fn) do
    Executor.execute_tool_stream(session_id, tool_name, parameters, callback_fn)
  end

  def list(session_id) do
    Registry.list_tools(session_id)
  end

  def get_info(session_id, tool_name) do
    Registry.get_tool(session_id, tool_name)
  end

  def search(session_id, query) do
    Registry.search_tools(session_id, query)
  end

  def unregister(session_id, tool_name) do
    Registry.unregister_tool(session_id, tool_name)
  end

  def get_session_stats(session_id) do
    Registry.get_session_stats(session_id)
  end

  def validate_parameters(tool, parameters) do
    SnakepitGRPCBridge.Tools.Validation.validate_parameters(tool, parameters)
  end
end
```

### Task 6: Update Adapter Routing

Update the `route_command/3` function in `lib/snakepit_grpc_bridge/adapter.ex` to handle tool commands:

```elixir
# Add these cases to the existing route_command function:

# Tool operations
"register_elixir_tool" -> 
  function = args["function"]  # This would come from serialized data
  metadata = args["metadata"] || %{}
  
  SnakepitGRPCBridge.API.Tools.register_elixir_function(
    opts[:session_id], 
    args["name"], 
    function,
    metadata
  )

"register_python_tool" ->
  SnakepitGRPCBridge.API.Tools.register_python_function(
    opts[:session_id],
    args["name"],
    args["python_function_path"],
    args["metadata"] || %{}
  )

"call_elixir_tool" -> 
  SnakepitGRPCBridge.API.Tools.call(
    opts[:session_id], 
    args["tool_name"], 
    args["parameters"] || %{}
  )

"list_elixir_tools" -> 
  SnakepitGRPCBridge.API.Tools.list(opts[:session_id])

"search_tools" ->
  SnakepitGRPCBridge.API.Tools.search(
    opts[:session_id],
    args["query"]
  )

"unregister_tool" ->
  SnakepitGRPCBridge.API.Tools.unregister(
    opts[:session_id],
    args["tool_name"]
  )

"get_tool_info" ->
  SnakepitGRPCBridge.API.Tools.get_info(
    opts[:session_id],
    args["tool_name"]
  )
```

### Task 7: Create Comprehensive Tests

Create `test/snakepit_grpc_bridge/tools/registry_test.exs`:

```elixir
defmodule SnakepitGRPCBridge.Tools.RegistryTest do
  use ExUnit.Case
  
  alias SnakepitGRPCBridge.Tools.Registry

  setup do
    {:ok, _pid} = start_supervised(Registry)
    session_id = "test_session_#{:rand.uniform(10000)}"
    %{session_id: session_id}
  end

  test "registers and retrieves Elixir tools", %{session_id: session_id} do
    test_function = fn params -> Map.get(params, "input", "default") end
    metadata = %{description: "Test function", parameters: []}
    
    assert :ok = Registry.register_tool(session_id, "test_tool", test_function, metadata)
    
    assert {:ok, tool} = Registry.get_tool(session_id, "test_tool")
    assert tool.name == "test_tool"
    assert tool.type == :elixir_function
    assert is_function(tool.function, 1)
  end

  test "registers Python tools", %{session_id: session_id} do
    python_path = "test_module.test_function"
    metadata = %{description: "Python test function"}
    
    assert :ok = Registry.register_python_tool(session_id, "python_tool", python_path, metadata)
    
    assert {:ok, tool} = Registry.get_tool(session_id, "python_tool")
    assert tool.name == "python_tool"
    assert tool.type == :python_function
    assert tool.python_path == python_path
  end

  test "lists all tools in session", %{session_id: session_id} do
    test_fn1 = fn _params -> "result1" end
    test_fn2 = fn _params -> "result2" end
    
    assert :ok = Registry.register_tool(session_id, "tool1", test_fn1)
    assert :ok = Registry.register_tool(session_id, "tool2", test_fn2)
    
    assert {:ok, tools} = Registry.list_tools(session_id)
    assert length(tools) == 2
    
    tool_names = Enum.map(tools, & &1.name)
    assert "tool1" in tool_names
    assert "tool2" in tool_names
  end

  test "unregisters tools", %{session_id: session_id} do
    test_function = fn _params -> "result" end
    
    assert :ok = Registry.register_tool(session_id, "to_unregister", test_function)
    assert {:ok, _tool} = Registry.get_tool(session_id, "to_unregister")
    
    assert :ok = Registry.unregister_tool(session_id, "to_unregister")
    assert {:error, :tool_not_found} = Registry.get_tool(session_id, "to_unregister")
  end

  test "searches tools by name and description", %{session_id: session_id} do
    test_fn = fn _params -> "result" end
    metadata = %{description: "Email validation function"}
    
    assert :ok = Registry.register_tool(session_id, "validate_email", test_fn, metadata)
    assert :ok = Registry.register_tool(session_id, "process_data", test_fn, %{description: "Data processing"})
    
    # Search by name
    assert {:ok, results} = Registry.search_tools(session_id, "email")
    assert length(results) == 1
    assert hd(results).name == "validate_email"
    
    # Search by description
    assert {:ok, results} = Registry.search_tools(session_id, "validation")
    assert length(results) == 1
    assert hd(results).name == "validate_email"
  end

  test "isolates tools by session", %{session_id: session_id} do
    other_session = "other_session_123"
    test_function = fn _params -> "result" end
    
    assert :ok = Registry.register_tool(session_id, "session_tool", test_function)
    assert :ok = Registry.register_tool(other_session, "other_tool", test_function)
    
    # Each session should only see its own tools
    assert {:ok, tools1} = Registry.list_tools(session_id)
    assert length(tools1) == 1
    assert hd(tools1).name == "session_tool"
    
    assert {:ok, tools2} = Registry.list_tools(other_session)
    assert length(tools2) == 1
    assert hd(tools2).name == "other_tool"
  end

  test "validates function arity", %{session_id: session_id} do
    invalid_function = fn a, b -> a + b end  # Arity 2, should be 1
    
    assert {:error, {:invalid_arity, 2, _message}} = 
      Registry.register_tool(session_id, "invalid_tool", invalid_function)
  end

  test "tracks tool execution statistics", %{session_id: session_id} do
    test_function = fn _params -> "result" end
    
    assert :ok = Registry.register_tool(session_id, "test_tool", test_function)
    
    # Record some executions
    Registry.record_tool_execution(session_id, "test_tool", 1000, {:ok, "result"})
    Registry.record_tool_execution(session_id, "test_tool", 2000, {:ok, "result"})
    
    assert {:ok, tool} = Registry.get_tool(session_id, "test_tool")
    assert tool.call_count == 2
    assert tool.avg_execution_time == 1500  # (1000 + 2000) / 2
    assert tool.last_called != nil
  end
end
```

Create `test/snakepit_grpc_bridge/tools/executor_test.exs`:

```elixir
defmodule SnakepitGRPCBridge.Tools.ExecutorTest do
  use ExUnit.Case
  
  alias SnakepitGRPCBridge.Tools.{Registry, Executor}

  setup do
    {:ok, _registry_pid} = start_supervised(Registry)
    session_id = "test_session_#{:rand.uniform(10000)}"
    %{session_id: session_id}
  end

  test "executes Elixir tools successfully", %{session_id: session_id} do
    test_function = fn params -> 
      "Hello, #{Map.get(params, "name", "World")}!"
    end
    
    assert :ok = Registry.register_tool(session_id, "greet", test_function)
    
    assert {:ok, result} = Executor.execute_tool(session_id, "greet", %{"name" => "Alice"})
    assert result == "Hello, Alice!"
  end

  test "handles tool execution errors", %{session_id: session_id} do
    failing_function = fn _params -> 
      raise "Something went wrong"
    end
    
    assert :ok = Registry.register_tool(session_id, "failing_tool", failing_function)
    
    assert {:error, {:execution_failed, error_message}} = 
      Executor.execute_tool(session_id, "failing_tool", %{})
    assert error_message =~ "Something went wrong"
  end

  test "validates parameters against schema", %{session_id: session_id} do
    test_function = fn params -> params["value"] * 2 end
    
    metadata = %{
      parameters: [
        %{name: "value", type: "integer", required: true}
      ]
    }
    
    assert :ok = Registry.register_tool(session_id, "double", test_function, metadata)
    
    # Valid parameters
    assert {:ok, 20} = Executor.execute_tool(session_id, "double", %{"value" => 10})
    
    # Invalid parameters (missing required)
    assert {:error, {:validation_failed, errors}} = 
      Executor.execute_tool(session_id, "double", %{})
    assert {:missing_required_parameter, "value"} in errors
    
    # Invalid parameters (wrong type)
    assert {:error, {:validation_failed, errors}} = 
      Executor.execute_tool(session_id, "double", %{"value" => "not_a_number"})
    assert Enum.any?(errors, fn error -> 
      match?({:invalid_type, "value", "integer", "string"}, error)
    end)
  end

  test "handles non-existent tools", %{session_id: session_id} do
    assert {:error, {:tool_not_found, "nonexistent"}} = 
      Executor.execute_tool(session_id, "nonexistent", %{})
  end

  test "serializes parameters correctly for different tool types", %{session_id: session_id} do
    # Test with complex data structures
    elixir_function = fn params -> 
      %{
        received_params: params,
        param_count: map_size(params),
        has_list: is_list(params["items"])
      }
    end
    
    assert :ok = Registry.register_tool(session_id, "complex_tool", elixir_function)
    
    complex_params = %{
      "name" => "test",
      "items" => [1, 2, 3],
      "nested" => %{"key" => "value"}
    }
    
    assert {:ok, result} = Executor.execute_tool(session_id, "complex_tool", complex_params)
    assert result.param_count == 3
    assert result.has_list == true
    assert result.received_params["name"] == "test"
  end
end
```

## Validation

After completing this implementation, verify:

1. ✅ Tools registry starts successfully and manages tool lifecycle
2. ✅ Elixir functions can be registered and executed
3. ✅ Python function registration creates proper wrappers
4. ✅ Parameter validation works against metadata schemas
5. ✅ Tool execution includes comprehensive error handling
6. ✅ Session isolation prevents cross-session tool access
7. ✅ Tool search and discovery work correctly
8. ✅ Execution statistics are tracked accurately
9. ✅ Serialization handles complex data structures
10. ✅ Comprehensive tests pass
11. ✅ Telemetry is collected for all operations
12. ✅ Adapter routes tool commands correctly

## Next Steps

The next prompt will implement the DSPy Integration system, which provides enhanced DSPy functionality with schema discovery and optimization.

## Files Modified/Created

- `lib/snakepit_grpc_bridge/tools/registry.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/tools/executor.ex` (complete implementation)  
- `lib/snakepit_grpc_bridge/tools/validation.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/tools/serialization.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/api/tools.ex` (complete implementation)
- `lib/snakepit_grpc_bridge/adapter.ex` (updated routing for tool commands)
- `test/snakepit_grpc_bridge/tools/registry_test.exs` (comprehensive tests)
- `test/snakepit_grpc_bridge/tools/executor_test.exs` (comprehensive tests)