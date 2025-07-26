# Bridge Function-Level Migration Guide

## Overview

This guide provides detailed function-by-function migration instructions for moving bridge functionality from DSPex/Snakepit to the cognitive-ready SnakepitGrpcBridge architecture.

## Core DSPy Bridge Functions

### 1. DSPy Execution Functions

#### `call_dspy/5` 
**Current Location**: `DSPex.Bridge`
**Target Module**: `SnakepitGrpcBridge.Schema.DSPy`

**Current Implementation**:
```elixir
def call_dspy(module_path, function_name, positional_args, keyword_args, opts \\ []) do
  session_id = Keyword.get(opts, :session_id, ID.generate("session"))
  
  result = Snakepit.execute_in_session(session_id, "call_dspy", %{
    "module_path" => module_path,
    "function_name" => function_name,
    "args" => positional_args,
    "kwargs" => keyword_args
  })
  # ... result handling
end
```

**Cognitive-Ready Implementation**:
```elixir
def call_dspy(module_path, function_name, positional_args, keyword_args, opts \\ []) do
  start_time = System.monotonic_time(:microsecond)
  session_id = Keyword.get(opts, :session_id, ID.generate("session"))
  
  # Route through cognitive scheduler
  case Cognitive.Scheduler.route_command("call_dspy", %{
    "module_path" => module_path,
    "function_name" => function_name,
    "args" => positional_args,
    "kwargs" => keyword_args
  }, [session_id: session_id]) do
    {:ok, worker_pid} ->
      result = Cognitive.Worker.execute(worker_pid, "call_dspy", args, opts)
      
      # Collect telemetry for future optimization
      duration = System.monotonic_time(:microsecond) - start_time
      record_dspy_call_telemetry(module_path, function_name, result, duration)
      
      result
    {:error, reason} ->
      {:error, reason}
  end
end
```

#### `discover_schema/2`
**Current Location**: `DSPex.Bridge`
**Target Module**: `SnakepitGrpcBridge.Schema.DSPy`

**Current Implementation**:
```elixir
def discover_schema(module_path \\ "dspy", opts \\ []) do
  session_id = Keyword.get(opts, :session_id, ID.generate("session"))
  
  case Snakepit.execute_in_session(session_id, "discover_dspy_schema", %{
    "module_path" => module_path
  }) do
    {:ok, %{"success" => true, "schema" => schema}} ->
      {:ok, schema}
    # ... error handling
  end
end
```

**Cognitive-Ready Implementation**:
```elixir
def discover_schema(module_path \\ "dspy", opts \\ []) do
  cache_key = {module_path, opts}
  
  # Check cache first (cognitive optimization)
  case get_cached_schema(cache_key) do
    {:ok, cached_schema} -> 
      record_cache_hit(module_path)
      {:ok, cached_schema}
    
    :not_found ->
      start_time = System.monotonic_time(:microsecond)
      session_id = Keyword.get(opts, :session_id, ID.generate("session"))
      
      result = perform_schema_discovery(session_id, module_path, opts)
      
      case result do
        {:ok, schema} ->
          # Cache for future use
          cache_schema(cache_key, schema)
          
          # Record telemetry for learning
          duration = System.monotonic_time(:microsecond) - start_time
          record_discovery_telemetry(module_path, schema, duration)
          
          {:ok, schema}
        error -> 
          error
      end
  end
end
```

### 2. Variable Management Functions

#### `set_variable/4`
**Current Location**: `DSPex.Variables` → `Snakepit.Bridge.SessionStore`
**Target Module**: `SnakepitGrpcBridge.Bridge.Variables`

**Current Implementation**:
```elixir
def set(context, name, value, opts \\ []) do
  session_id = get_session_id(context)
  type = Keyword.get(opts, :type) || infer_type(value)
  constraints = Keyword.get(opts, :constraints, %{})
  
  result = Snakepit.Bridge.SessionStore.set_variable(
    session_id, 
    to_string(name), 
    value, 
    type, 
    constraints
  )
  # ... result handling
end
```

**Cognitive-Ready Implementation**:
```elixir
def set(session_id, name, value, opts \\ []) do
  start_time = System.monotonic_time(:microsecond)
  
  # Validate and prepare variable
  with {:ok, variable} <- prepare_variable(name, value, opts),
       {:ok, _} <- validate_constraints(variable) do
    
    # Execute through cognitive infrastructure
    result = Cognitive.Worker.execute_variable_operation(
      :set, session_id, variable
    )
    
    # Record telemetry for optimization
    duration = System.monotonic_time(:microsecond) - start_time
    record_variable_telemetry(:set, name, variable.type, duration)
    
    result
  end
end
```

#### `get_variable/3`
**Current Location**: `DSPex.Variables` → `Snakepit.Bridge.SessionStore`
**Target Module**: `SnakepitGrpcBridge.Bridge.Variables`

**Current Implementation**:
```elixir
def get(context, name, default \\ nil) do
  session_id = get_session_id(context)
  
  case Snakepit.Bridge.SessionStore.get_variable(session_id, to_string(name)) do
    {:ok, variable} -> variable.value
    {:error, :not_found} -> default
    {:error, _reason} -> default
  end
end
```

**Cognitive-Ready Implementation**:
```elixir
def get(session_id, name, default \\ nil) do
  start_time = System.monotonic_time(:microsecond)
  
  # Check hot cache first (cognitive optimization)
  case check_variable_cache(session_id, name) do
    {:ok, cached_value} ->
      record_cache_hit(:variable, name)
      cached_value
    
    :miss ->
      # Fetch through cognitive worker
      result = Cognitive.Worker.execute_variable_operation(
        :get, session_id, name
      )
      
      # Update cache and telemetry
      case result do
        {:ok, value} ->
          cache_variable(session_id, name, value)
          duration = System.monotonic_time(:microsecond) - start_time
          record_variable_telemetry(:get, name, nil, duration)
          value
        
        {:error, :not_found} ->
          default
          
        {:error, _reason} ->
          default
      end
  end
end
```

### 3. Tool Management Functions

#### `register_elixir_tool/4`
**Current Location**: `DSPex.Bridge.Tools`
**Target Module**: `SnakepitGrpcBridge.Bridge.Tools`

**Current Implementation**:
```elixir
def register_tool(session_id, name, function, metadata \\ %{}) do
  tool_spec = %{
    "name" => name,
    "type" => "elixir",
    "parameters" => extract_parameters(function, metadata),
    "description" => Map.get(metadata, :description, ""),
    "exposed_to_python" => Map.get(metadata, :exposed_to_python, true)
  }
  
  Snakepit.execute_in_session(session_id, "register_elixir_tool", tool_spec)
end
```

**Cognitive-Ready Implementation**:
```elixir
def register_tool(session_id, name, function, metadata \\ %{}) do
  start_time = System.monotonic_time(:microsecond)
  
  # Prepare tool with cognitive metadata
  tool_spec = %{
    "name" => name,
    "type" => "elixir", 
    "handler" => function,
    "parameters" => extract_parameters(function, metadata),
    "description" => Map.get(metadata, :description, ""),
    "metadata" => Map.merge(metadata, %{
      registered_at: DateTime.utc_now(),
      usage_count: 0,
      avg_execution_time: nil
    })
  }
  
  # Register through cognitive infrastructure
  result = Cognitive.Worker.register_tool(session_id, tool_spec)
  
  # Record registration telemetry
  duration = System.monotonic_time(:microsecond) - start_time
  record_tool_registration(name, :elixir, duration)
  
  result
end
```

### 4. Session Management Functions

#### `create_session/2`
**Current Location**: `Snakepit.Bridge.SessionStore`
**Target Module**: `SnakepitGrpcBridge.Bridge.SessionStore`

**Current Implementation**:
```elixir
def create_session(session_id, opts \\ []) when is_binary(session_id) do
  GenServer.call(__MODULE__, {:create_session, session_id, opts})
end

def handle_call({:create_session, session_id, opts}, _from, state) do
  ttl = Keyword.get(opts, :ttl, state.default_ttl)
  
  case Session.new(session_id, Keyword.put(opts, :ttl, ttl)) do
    {:ok, session} ->
      # Store in ETS
      true = :ets.insert(state.table_name, {session_id, session})
      {:reply, {:ok, session}, state}
    {:error, reason} ->
      {:reply, {:error, reason}, state}
  end
end
```

**Cognitive-Ready Implementation**:
```elixir
def create_session(session_id, opts \\ []) do
  start_time = System.monotonic_time(:microsecond)
  
  # Create session with cognitive enhancements
  enhanced_opts = Keyword.merge(opts, [
    telemetry_enabled: true,
    performance_tracking: true,
    created_at: DateTime.utc_now()
  ])
  
  case Cognitive.Scheduler.create_session(session_id, enhanced_opts) do
    {:ok, session} ->
      # Initialize cognitive tracking
      init_session_telemetry(session_id)
      
      # Record creation metrics
      duration = System.monotonic_time(:microsecond) - start_time
      record_session_event(:created, session_id, duration)
      
      {:ok, session}
      
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 5. Macro and Code Generation Functions

#### `defdsyp/3` Macro
**Current Location**: `DSPex.Bridge`
**Target Module**: `SnakepitGrpcBridge.Codegen.DSPy`

**Current Implementation**:
```elixir
defmacro defdsyp(module_name, class_path, config \\ %{}) do
  quote bind_quoted: [module_name: module_name, class_path: class_path, config: config] do
    defmodule module_name do
      @class_path class_path
      @config config
      
      def create(args \\ %{}, opts \\ []) do
        # ... implementation
      end
      
      def execute(instance, inputs \\ %{}, opts \\ []) do
        # ... implementation
      end
    end
  end
end
```

**Cognitive-Ready Implementation**:
```elixir
defmacro defdsyp(module_name, class_path, config \\ %{}) do
  generation_id = generate_unique_id()
  
  # Record wrapper generation for learning
  record_wrapper_generation(module_name, class_path, config, generation_id)
  
  quote bind_quoted: [
    module_name: module_name, 
    class_path: class_path, 
    config: config,
    generation_id: generation_id
  ] do
    defmodule module_name do
      @class_path class_path
      @config config
      @generation_id generation_id
      
      def create(args \\ %{}, opts \\ []) do
        start_time = System.monotonic_time(:microsecond)
        
        # Create with cognitive tracking
        result = Cognitive.Evolution.create_instance(
          @class_path, args, opts, @generation_id
        )
        
        # Record creation pattern
        duration = System.monotonic_time(:microsecond) - start_time
        Codegen.Telemetry.record_instance_creation(
          @generation_id, args, result, duration
        )
        
        result
      end
      
      def execute(instance, inputs \\ %{}, opts \\ []) do
        start_time = System.monotonic_time(:microsecond)
        
        # Execute with performance tracking
        result = Cognitive.Evolution.execute_instance(
          instance, inputs, opts, @generation_id
        )
        
        # Record execution pattern
        duration = System.monotonic_time(:microsecond) - start_time
        Codegen.Telemetry.record_instance_execution(
          @generation_id, instance, inputs, result, duration
        )
        
        result
      end
    end
  end
end
```

## Migration Patterns

### Pattern 1: Add Telemetry Collection
Every function should collect timing and success metrics:

```elixir
# Before
def function(args) do
  do_work(args)
end

# After
def function(args) do
  start_time = System.monotonic_time(:microsecond)
  result = do_work(args)
  duration = System.monotonic_time(:microsecond) - start_time
  record_telemetry(:function, args, result, duration)
  result
end
```

### Pattern 2: Add Caching Layer
Frequently accessed data should be cached:

```elixir
# Before
def get_data(key) do
  fetch_from_source(key)
end

# After  
def get_data(key) do
  case check_cache(key) do
    {:ok, cached} -> 
      record_cache_hit(key)
      cached
    :miss ->
      data = fetch_from_source(key)
      cache_data(key, data)
      data
  end
end
```

### Pattern 3: Route Through Cognitive Infrastructure
All operations should go through cognitive modules:

```elixir
# Before
def execute(command, args) do
  Worker.execute(command, args)
end

# After
def execute(command, args) do
  case Cognitive.Scheduler.route_command(command, args) do
    {:ok, worker} ->
      Cognitive.Worker.execute(worker, command, args)
    {:error, reason} ->
      {:error, reason}
  end
end
```

## Function Categories

### High-Priority Functions (Core Operations)
1. `call_dspy/5` - Core DSPy execution
2. `discover_schema/2` - Schema discovery
3. `set_variable/4` - Variable management
4. `get_variable/3` - Variable retrieval
5. `register_elixir_tool/4` - Tool registration

### Medium-Priority Functions (Session Management)
1. `create_session/2` - Session creation
2. `get_session/1` - Session retrieval
3. `update_session/2` - Session updates
4. `delete_session/1` - Session cleanup

### Low-Priority Functions (Utilities)
1. Result transformation functions
2. Type inference functions
3. Validation helpers

## Testing Each Migration

For each migrated function:

1. **Unit Test**: Test the function in isolation
2. **Integration Test**: Test with real gRPC/Python bridge
3. **Performance Test**: Ensure no regression
4. **Telemetry Test**: Verify metrics collection

Example test pattern:
```elixir
test "call_dspy collects telemetry" do
  # Set up telemetry handler
  :telemetry.attach("test", [:snakepit_grpc_bridge, :schema, :call], &capture_telemetry/4, %{})
  
  # Execute function
  {:ok, result} = Schema.DSPy.call_dspy("dspy.Predict", "__init__", ["test"], %{})
  
  # Verify telemetry
  assert_receive {:telemetry_event, measurements, metadata}
  assert measurements.duration > 0
  assert metadata.success == true
end
```

## Success Criteria

Each migrated function must:
1. ✅ Maintain exact same public API
2. ✅ Pass all existing tests
3. ✅ Collect telemetry data
4. ✅ Show no performance regression
5. ✅ Be ready for cognitive enhancement