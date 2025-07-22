# Prompt: Update Elixir Client with Stdout-Based Readiness Detection

## Objective
Update the Elixir GRPCWorker to use stdout-based readiness detection instead of TCP polling, and implement the client-side protocol for the unified bridge.

## Context
The current implementation uses TCP polling which has race conditions. The new approach monitors stdout for a "GRPC_READY:port" message, which is more robust and faster.

## Requirements

### Core Updates

1. **GRPCWorker GenServer**
   - Replace TCP polling with stdout monitoring
   - Parse "GRPC_READY:port" message
   - Handle both stdout and stderr properly
   - Maintain backward compatibility

2. **gRPC Client Module**
   - Implement all new RPC methods
   - Handle streaming responses
   - Proper error handling
   - Connection pooling

3. **Integration Updates**
   - Update existing tool execution
   - Add variable management calls
   - Implement streaming handlers

## Implementation Steps

### 1. Update GRPCWorker with Stdout Monitoring

```elixir
# File: snakepit/lib/snakepit/grpc/worker.ex

defmodule Snakepit.GRPC.Worker do
  use GenServer
  require Logger
  
  defstruct [:port, :channel, :python_port, :ready, :buffer]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    python_path = opts[:python_path] || find_python()
    server_script = opts[:server_script] || server_script_path()
    
    # Start Python process with Port
    port_opts = [
      :binary,
      :exit_status,
      {:line, 1024},  # Line-buffered for easier parsing
      {:args, [server_script]},
      {:env, [{'PYTHONUNBUFFERED', '1'}]}  # Force unbuffered output
    ]
    
    port = Port.open({:spawn_executable, python_path}, port_opts)
    
    state = %__MODULE__{
      python_port: port,
      ready: false,
      buffer: ""
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{python_port: port} = state) do
    # Process complete line
    handle_output_line(line, state)
  end
  
  @impl true
  def handle_info({port, {:data, {:noeol, partial}}}, %{python_port: port} = state) do
    # Buffer partial line
    {:noreply, %{state | buffer: state.buffer <> partial}}
  end
  
  @impl true
  def handle_info({port, {:exit_status, status}}, %{python_port: port} = state) do
    Logger.error("Python process exited with status: #{status}")
    {:stop, {:python_exit, status}, state}
  end
  
  defp handle_output_line(line, state) do
    full_line = state.buffer <> line
    
    case parse_ready_message(full_line) do
      {:ok, port_number} ->
        # Server is ready!
        Logger.info("Python gRPC server ready on port #{port_number}")
        
        # Connect to gRPC
        {:ok, channel} = GRPC.Stub.connect("localhost:#{port_number}")
        
        new_state = %{state | 
          port: port_number,
          channel: channel,
          ready: true,
          buffer: ""
        }
        
        # Notify any waiters
        notify_ready(new_state)
        
        {:noreply, new_state}
        
      :not_ready ->
        # Log other output for debugging
        Logger.debug("Python output: #{full_line}")
        {:noreply, %{state | buffer: ""}}
    end
  end
  
  defp parse_ready_message(line) do
    case Regex.run(~r/^GRPC_READY:(\d+)/, line) do
      [_, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> {:ok, port}
          _ -> :not_ready
        end
      _ ->
        :not_ready
    end
  end
  
  defp notify_ready(state) do
    # Send notification to any processes waiting for ready state
    Registry.dispatch(Snakepit.Registry, :grpc_ready, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:grpc_ready, state.channel})
      end
    end)
  end
  
  @doc """
  Wait for the gRPC server to be ready.
  """
  def await_ready(timeout \\ 30_000) do
    case GenServer.call(__MODULE__, :get_channel, timeout) do
      {:ok, channel} -> {:ok, channel}
      error -> error
    end
  end
  
  @impl true
  def handle_call(:get_channel, from, state) do
    if state.ready do
      {:reply, {:ok, state.channel}, state}
    else
      # Register caller to be notified when ready
      Registry.register(Snakepit.Registry, :grpc_ready, from)
      {:noreply, state}
    end
  end
end
```

### 2. Implement gRPC Client Module

```elixir
# File: snakepit/lib/snakepit/grpc/client.ex

defmodule Snakepit.GRPC.Client do
  @moduledoc """
  Client for the unified bridge protocol.
  """
  
  alias Snakepit.Bridge.Proto.{
    BridgeService,
    RegisterVariableRequest,
    GetVariableRequest,
    SetVariableRequest,
    WatchVariablesRequest,
    Variable
  }
  
  require Logger
  
  @doc """
  Registers a new variable in a session.
  """
  def register_variable(channel, session_id, name, type, initial_value, opts \\ []) do
    request = RegisterVariableRequest.new(
      session_id: session_id,
      name: name,
      type: type,
      initial_value: serialize_value(initial_value, type),
      constraints: build_constraints(type, opts[:constraints] || %{}),
      metadata: opts[:metadata] || %{}
    )
    
    case BridgeService.Stub.register_variable(channel, request) do
      {:ok, response} ->
        {:ok, response.variable_id, deserialize_variable(response.variable)}
      {:error, %GRPC.RPCError{} = error} ->
        {:error, format_error(error)}
    end
  end
  
  @doc """
  Gets a variable's current value.
  """
  def get_variable(channel, session_id, identifier) do
    request = GetVariableRequest.new(
      session_id: session_id,
      identifier: identifier
    )
    
    case BridgeService.Stub.get_variable(channel, request) do
      {:ok, response} ->
        variable = deserialize_variable(response.variable)
        {:ok, variable}
      {:error, %GRPC.RPCError{} = error} ->
        {:error, format_error(error)}
    end
  end
  
  @doc """
  Updates a variable's value.
  """
  def set_variable(channel, session_id, identifier, value, metadata \\ %{}) do
    # First get the variable to know its type
    case get_variable(channel, session_id, identifier) do
      {:ok, variable} ->
        request = SetVariableRequest.new(
          session_id: session_id,
          identifier: identifier,
          value: serialize_value(value, variable.type),
          metadata: metadata
        )
        
        case BridgeService.Stub.set_variable(channel, request) do
          {:ok, _response} -> :ok
          {:error, error} -> {:error, format_error(error)}
        end
        
      error ->
        error
    end
  end
  
  @doc """
  Watches variables for changes (streaming).
  """
  def watch_variables(channel, session_id, identifiers, opts \\ []) do
    request = WatchVariablesRequest.new(
      session_id: session_id,
      variable_identifiers: identifiers,
      include_initial_values: Keyword.get(opts, :include_initial, true)
    )
    
    case BridgeService.Stub.watch_variables(channel, request) do
      {:ok, stream} ->
        {:ok, stream}
      {:error, error} ->
        {:error, format_error(error)}
    end
  end
  
  # Serialization helpers
  
  defp serialize_value(value, type) do
    json = case type do
      :float -> Jason.encode!(value)
      :integer -> Jason.encode!(value)
      :string -> Jason.encode!(value)
      :boolean -> Jason.encode!(value)
      :choice -> Jason.encode!(value)
      :module -> Jason.encode!(value)
      :embedding -> Jason.encode!(value)
      :tensor ->
        # Handle tensor serialization
        Jason.encode!(%{
          shape: tensor_shape(value),
          data: tensor_data(value)
        })
      _ ->
        Jason.encode!(value)
    end
    
    Google.Protobuf.Any.new(
      type_url: "dspex.variables/#{type}",
      value: json
    )
  end
  
  defp deserialize_variable(proto_var) do
    %{
      id: proto_var.id,
      name: proto_var.name,
      type: proto_var.type,
      value: deserialize_value(proto_var.value, proto_var.type),
      constraints: proto_var.constraints,
      metadata: proto_var.metadata,
      version: proto_var.version
    }
  end
  
  defp deserialize_value(any_value, type) do
    json = any_value.value
    
    case type do
      :float -> Jason.decode!(json)
      :integer -> Jason.decode!(json)
      :string -> Jason.decode!(json) 
      :boolean -> Jason.decode!(json)
      :choice -> Jason.decode!(json)
      :module -> Jason.decode!(json)
      :embedding -> Jason.decode!(json)
      :tensor ->
        data = Jason.decode!(json)
        # Could reconstruct tensor type if needed
        data
      _ ->
        Jason.decode!(json)
    end
  end
  
  defp build_constraints(:choice, user_constraints) do
    # Build choice constraints
    %{choices: Map.get(user_constraints, :choices, [])}
  end
  
  defp build_constraints(:float, user_constraints) do
    # Build numeric constraints
    %{
      min: Map.get(user_constraints, :min),
      max: Map.get(user_constraints, :max)
    }
  end
  
  defp build_constraints(_type, user_constraints) do
    user_constraints
  end
  
  defp format_error(%GRPC.RPCError{status: status, message: message}) do
    "gRPC error #{status}: #{message}"
  end
end
```

### 3. Create Stream Consumer for Variable Watching

```elixir
# File: snakepit/lib/snakepit/grpc/stream_handler.ex

defmodule Snakepit.GRPC.StreamHandler do
  @moduledoc """
  Handles gRPC streams for variable watching.
  """
  
  use Task
  require Logger
  
  def start_link(stream, callback) do
    Task.start_link(__MODULE__, :consume_stream, [stream, callback])
  end
  
  def consume_stream(stream, callback) do
    stream
    |> Enum.each(fn
      {:ok, update} ->
        handle_update(update, callback)
      {:error, reason} ->
        Logger.error("Stream error: #{inspect(reason)}")
    end)
  end
  
  defp handle_update(update, callback) do
    case update.update_type do
      "heartbeat" ->
        # Ignore heartbeats
        :ok
        
      "initial_value" ->
        # Handle initial value
        callback.(update.variable.name, nil, deserialize_value(update.variable.value), %{initial: true})
        
      "value_change" ->
        # Handle value change
        old_value = if update.old_value, do: deserialize_value(update.old_value), else: nil
        new_value = deserialize_value(update.variable.value)
        metadata = Map.merge(update.update_metadata, %{
          source: update.update_source,
          timestamp: update.timestamp
        })
        
        callback.(update.variable.name, old_value, new_value, metadata)
        
      other ->
        Logger.warning("Unknown update type: #{other}")
    end
  rescue
    e ->
      Logger.error("Error in stream callback: #{inspect(e)}")
  end
  
  defp deserialize_value(any_value) do
    # Reuse from client module
    Snakepit.GRPC.Client.deserialize_value(any_value, nil)
  end
end
```

### 4. Update Module Configuration

```elixir
# File: snakepit/lib/snakepit.ex

defmodule Snakepit do
  use Application
  
  def start(_type, _args) do
    children = [
      # Registry for coordination
      {Registry, keys: :duplicate, name: Snakepit.Registry},
      
      # Start gRPC worker
      Snakepit.GRPC.Worker,
      
      # Other supervisors...
    ]
    
    opts = [strategy: :one_for_one, name: Snakepit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Testing Steps

### 1. Test Server Startup
```elixir
# In IEx
{:ok, _} = Snakepit.GRPC.Worker.start_link()
{:ok, channel} = Snakepit.GRPC.Worker.await_ready()
```

### 2. Test Variable Operations
```elixir
# Register a variable
{:ok, var_id, var} = Snakepit.GRPC.Client.register_variable(
  channel,
  "test_session",
  "temperature",
  :float,
  0.7
)

# Get variable
{:ok, var} = Snakepit.GRPC.Client.get_variable(channel, "test_session", "temperature")

# Set variable
:ok = Snakepit.GRPC.Client.set_variable(
  channel, 
  "test_session",
  "temperature",
  0.9,
  %{"source" => "test"}
)
```

### 3. Test Streaming
```elixir
# Watch variables
{:ok, stream} = Snakepit.GRPC.Client.watch_variables(
  channel,
  "test_session", 
  ["temperature"]
)

# Start consumer
Snakepit.GRPC.StreamHandler.start_link(stream, fn name, old, new, meta ->
  IO.puts("#{name} changed from #{old} to #{new}")
end)
```

## Critical Implementation Notes

1. **Port Management**: Use Erlang Ports for reliable process management
2. **Output Parsing**: Handle both complete and partial lines from stdout
3. **Error Handling**: Gracefully handle Python process crashes
4. **Streaming**: Ensure streams are properly terminated on client disconnect
5. **Backward Compatibility**: Maintain existing tool execution functionality

## Files to Create/Modify

1. Update: `snakepit/lib/snakepit/grpc/worker.ex`
2. Create: `snakepit/lib/snakepit/grpc/client.ex`
3. Create: `snakepit/lib/snakepit/grpc/stream_handler.ex`
4. Update: `snakepit/lib/snakepit.ex`
5. Update: `snakepit/mix.exs` (ensure dependencies)

## Next Steps
After implementing the Elixir client:
1. Test the stdout-based startup detection
2. Verify all RPC methods work correctly
3. Test streaming stability
4. Proceed to implement serialization (next prompt)