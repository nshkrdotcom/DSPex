# Stage 3: Real-time Updates & Advanced Features

## Overview

Stage 3 transforms the bridge from a request-response system into a fully reactive, bidirectional communication channel. By implementing the `WatchVariables` gRPC stream, we enable Python to subscribe to real-time state changes from Elixir. This eliminates polling and allows for the creation of truly adaptive systems where Python logic can react instantly to updates driven by Elixir-side optimizers or UI events. This stage also introduces batch operations and support for more complex variable types, enhancing both performance and functionality.

## Goals

1.  **Implement `WatchVariables` Streaming:** Enable Python to subscribe to and receive real-time updates for specific session variables.
2.  **Enable Reactive Systems:** Allow a Python process to run continuously, reacting to state changes initiated from Elixir.
3.  **Optimize Performance:** Introduce batch operations for getting and setting multiple variables to reduce network overhead.
4.  **Enhance Functionality:** Add support for advanced variable types like `:choice` and `:module` to enable dynamic selection of models and strategies.
5.  **Prove Reactivity:** Demonstrate an end-to-end scenario where an Elixir process modifies a variable, and a watching Python process immediately receives and acts on the update.

## Deliverables

-   `WatchVariables` streaming RPC fully implemented on both Elixir and Python sides.
-   `BatchGetVariables` and `BatchSetVariables` RPCs implemented and integrated.
-   Support for `:choice` and `:module` variable types in the Elixir `SessionStore` and Python `SessionContext`.
-   Comprehensive integration tests verifying streaming functionality, including graceful stream termination and error handling.
-   A complete end-to-end example of a reactive system.

## Detailed Implementation Plan

### 1. Implement `WatchVariables` Streaming (Elixir Side)

The core of this stage is building the observer pattern within Elixir's `SessionStore` and exposing it via a gRPC stream.

#### Create `snakepit/lib/snakepit/bridge/variables/observer_manager.ex`:

This GenServer will manage subscriptions to prevent overwhelming the `SessionStore`.

```elixir
defmodule Snakepit.Bridge.Variables.ObserverManager do
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  # Public API
  def subscribe(variable_id, pid) do
    GenServer.cast(__MODULE__, {:subscribe, variable_id, pid})
    Process.monitor(pid)
  end

  def unsubscribe(variable_id, pid) do
    GenServer.cast(__MODULE__, {:unsubscribe, variable_id, pid})
  end

  def notify(variable_id, update_payload) do
    GenServer.cast(__MODULE__, {:notify, variable_id, update_payload})
  end

  # Server Callbacks
  def handle_cast({:subscribe, var_id, pid}, state) do
    new_state = Map.update(state, var_id, MapSet.new([pid]), &MapSet.put(&1, pid))
    {:noreply, new_state}
  end

  def handle_cast({:unsubscribe, var_id, pid}, state) do
    new_state = Map.update(state, var_id, MapSet.new(), &MapSet.delete(&1, pid))
    {:noreply, new_state}
  end

  def handle_cast({:notify, var_id, payload}, state) do
    if observers = state[var_id] do
      for pid <- observers do
        send(pid, {:variable_update, payload})
      end
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriptions for dead processes
    new_state = for {var_id, pids} <- state, into: %{} do
      {var_id, MapSet.delete(pids, pid)}
    end
    {:noreply, new_state}
  end
end
```

#### Update `snakepit/lib/snakepit/bridge/session_store.ex`:

```elixir
defmodule Snakepit.Bridge.SessionStore do
  # ... inside the handle_call for :update_variable ...
  def handle_call({:update_variable, session_id, identifier, new_value, metadata}, _from, state) do
    # ... after successfully updating the variable ...
    
    # Notify observers via the manager
    update_payload = %{
      session_id: session_id,
      variable_id: var_id,
      variable: updated_variable,
      update_metadata: metadata
    }
    ObserverManager.notify(var_id, update_payload)
      
    {:reply, :ok, new_state}
  end
end
```

#### Update `snakepit/lib/snakepit/grpc/server.ex`:

```elixir
defmodule Snakepit.GRPC.Server do
  # ...
  alias Snakepit.Bridge.Variables.ObserverManager
  
  @impl true
  def watch_variables(request, stream) do
    watcher_pid = self()
    
    # Subscribe to updates for each requested variable
    for var_id <- request.variable_ids do
      ObserverManager.subscribe(var_id, watcher_pid)
    end

    # Enter a loop to wait for messages and push them to the stream
    receive_updates(stream, request.variable_ids)
    
    # When the loop exits (stream closes), unsubscribe
    for var_id <- request.variable_ids do
      ObserverManager.unsubscribe(var_id, watcher_pid)
    end
  end

  defp receive_updates(stream, watched_ids) do
    receive do
      {:variable_update, payload} ->
        # Check if this update is for one of the watched variables
        if payload.variable_id in watched_ids do
          # Create the protobuf message
          proto_update = Snakepit.Bridge.VariableUpdate.new(
            variable_id: payload.variable_id,
            variable: Variable.to_proto(payload.variable),
            # ... other fields ...
          )
          
          # Send the update on the gRPC stream
          case GRPC.Server.send(stream, proto_update) do
            :ok -> 
              # Continue listening for more updates
              receive_updates(stream, watched_ids)
            {:error, _reason} ->
              # Client disconnected, end the loop
              Logger.info("Client disconnected from WatchVariables stream.")
          end
        end
      after
        # Add a timeout to periodically check if the stream is still alive
        30_000 ->
          if GRPC.Server.alive?(stream) do
            receive_updates(stream, watched_ids)
          else
            Logger.info("WatchVariables stream appears to be dead.")
          end
    end
  end
end
```

### 2. Implement `WatchVariables` Streaming (Python Side)

#### Update `snakepit/priv/python/snakepit_bridge/session_context.py`:

```python
class SessionContext:
    # ... existing methods ...

    async def watch_variable(self, name: str) -> AsyncIterator[Dict[str, Any]]:
        """Watches a single variable for changes."""
        yield await self.watch_variables([name])

    async def watch_variables(self, names: List[str]) -> AsyncIterator[Dict[str, Any]]:
        """Watches multiple variables for changes, yielding updates."""
        request = pb2.WatchVariablesRequest(
            session_id=self.session_id,
            variable_ids=names
        )
        
        try:
            stream = self.stub.WatchVariables(request)
            async for update in stream:
                # Deserialize the update
                value = self._serializer.deserialize(
                    update.variable.value,
                    update.variable.type
                )
                
                # Update local cache
                self._variable_cache.set(update.variable_id, value)
                
                yield {
                    'variable_id': update.variable_id,
                    'value': value,
                    'metadata': dict(update.update_metadata),
                    'source': update.update_source,
                    'timestamp': update.timestamp.ToDatetime()
                }
        except grpc.aio.AioRpcError as e:
            logger.error(f"WatchVariables stream failed: {e}")
            # The stream is closed, so the iterator will naturally end.
```

### 3. Implement Batch Operations

This was partially implemented in Stage 1's plans but is a key deliverable here. The gRPC handlers in Elixir and the `get_variables`/`update_variables` methods in Python should be fully implemented as per the Stage 1 documentation.

### 4. Implement Advanced Types

#### Update `snakepit/lib/snakepit/bridge/variables/types.ex`:

```elixir
defmodule Snakepit.Bridge.Variables.Types do
  @type_modules %{
    # ... existing types ...
    choice: Snakepit.Bridge.Variables.Types.Choice,
    module: Snakepit.Bridge.Variables.Types.Module
  }
  # ...
end

defmodule Snakepit.Bridge.Variables.Types.Choice do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_binary(value) or is_atom(value), do: {:ok, to_string(value)}
  def validate(_), do: {:error, "must be a string or atom"}
  
  @impl true
  def validate_constraints(value, %{choices: choices}) when is_list(choices) do
    if value in choices do
      :ok
    else
      {:error, "value '#{value}' is not in allowed choices: #{inspect(choices)}"}
    end
  end
  def validate_constraints(_value, _constraints), do: :ok # No constraints to check
  
  # ... serialize/deserialize are same as String ...
end

defmodule Snakepit.Bridge.Variables.Types.Module do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  # Validation is the same as Choice
  def validate(value), do: Snakepit.Bridge.Variables.Types.Choice.validate(value)
  def validate_constraints(value, constraints), do: Snakepit.Bridge.Variables.Types.Choice.validate_constraints(value, constraints)
  
  # ... serialize/deserialize are same as String ...
end
```

#### Update `snakepit/priv/python/snakepit_bridge/serialization.py`:

The `VariableSerializer` already handles string-based types like `choice` and `module` correctly, so no changes are needed for these specific types. The logic is robust enough to handle them as strings, which is all that's required.

### 5. Integration Tests

#### Create `test/snakepit/grpc_stage3_integration_test.exs`:

```elixir
defmodule Snakepit.GRPCStage3IntegrationTest do
  use ExUnit.Case, async: false
  
  alias Snakepit.Bridge.SessionStore
  alias Snakepit.GRPC.Client
  
  @moduletag :integration
  
  setup do
    # ... (same setup as Stage 2 test) ...
    {:ok, session_id: session_id, channel: channel}
  end

  describe "Real-time Streaming" do
    test "Python client receives variable updates in real-time", %{session_id: session_id, channel: channel} do
      # Register a variable to watch
      {:ok, var_id} = SessionStore.register_variable(session_id, "counter", :integer, 0)

      # Start a Task that will listen on the gRPC stream
      # This test requires a helper to run a Python script and capture its output
      python_listener_task = Task.async(fn ->
        run_python_script("
          import asyncio, grpc
          from snakepit_bridge.session_context import SessionContext
          
          async def watch():
              channel = grpc.aio.insecure_channel('localhost:#{@port}')
              session = SessionContext('#{session_id}', channel)
              async for update in session.watch_variables(['#{var_id}']):
                  print(f\"UPDATE:{update['value']}\", flush=True)

          asyncio.run(watch())
        ")
      end)
      
      # Give Python time to connect
      Process.sleep(500)
      
      # Update the variable from Elixir multiple times
      :ok = SessionStore.update_variable(session_id, var_id, 1)
      Process.sleep(50)
      :ok = SessionStore.update_variable(session_id, var_id, 2)
      Process.sleep(50)
      :ok = SessionStore.update_variable(session_id, var_id, 3)
      
      # Give Python time to receive updates
      Process.sleep(500)
      
      # Stop the listener and check its output
      Process.exit(python_listener_task.pid, :kill)
      output = Task.await(python_listener_task, 5000)
      
      assert output =~ "UPDATE:1"
      assert output =~ "UPDATE:2"
      assert output =~ "UPDATE:3"
    end
  end
end
```

## Success Criteria

1.  **Streaming Works:** The `WatchVariables` end-to-end test passes, proving that updates in Elixir are pushed to and received by a Python client in near real-time.
2.  **Batch Operations Implemented:** Both Elixir and Python APIs for `get_variables` and `update_variables` are complete and tested.
3.  **Advanced Types Supported:** Tests pass for creating and updating variables of type `:choice` and `:module`, including constraint validation (e.g., value must be one of the choices).
4.  **Graceful Termination:** When a Python client disconnects its `WatchVariables` stream, the corresponding Elixir processes (`ObserverManager` subscription) are cleaned up correctly without leaking resources.
5.  **Reactive System Demonstrated:** A complete example, either as a test or a demo script, shows a Python process that changes its behavior based on a variable update initiated from Elixir.

## Common Issues and Solutions

-   **Issue:** Elixir gRPC stream handler blocks or doesn't exit.
    -   **Solution:** Use a `receive` loop with a timeout and a check for `GRPC.Server.alive?/1` to ensure the process can exit if the client disconnects unexpectedly.
-   **Issue:** `ObserverManager` becomes a bottleneck.
    -   **Solution:** Ensure notifications are sent asynchronously (`Task.start`) so that a slow observer does not block notifications for others.
-   **Issue:** Race conditions with stream setup and variable updates.
    -   **Solution:** The `WatchVariables` implementation should have an option to send the current value immediately upon subscription to avoid missing updates that happen between the subscription call and the first `receive` block.

## Next Stage

With the reactive foundation now in place, Stage 4 will focus on production hardening and adding the sophisticated logic needed for complex optimization workflows. This includes implementing dependency management, optimizer coordination, history/versioning, and security features, turning the robust communication bridge into a true orchestration platform.
