# Prompt: Create Comprehensive Integration Tests

## Objective
Create integration tests that verify the complete unified gRPC bridge works correctly, testing both tool execution and variable management with streaming.

## Context
Integration tests are critical to ensure all components work together correctly. They should test real scenarios that exercise the full stack.

## Requirements

### Test Coverage
1. **Server Startup**: Stdout-based readiness detection
2. **Tool Execution**: Existing functionality must work
3. **Variable CRUD**: All variable operations
4. **Type System**: Each type with serialization
5. **Streaming**: Real-time updates with multiple watchers
6. **Error Handling**: Graceful degradation
7. **Performance**: Latency and throughput

### Test Scenarios
- Single session with multiple variables
- Multiple sessions with isolation
- Concurrent operations
- Stream lifecycle (connect, updates, disconnect)
- Python process crash recovery
- Type constraint violations

## Implementation Steps

### 1. Create Test Helpers

```elixir
# File: test/support/bridge_test_helper.ex

defmodule BridgeTestHelper do
  @moduledoc """
  Helper functions for bridge integration tests.
  """
  
  def start_bridge do
    # Ensure clean state
    cleanup_bridge()
    
    # Start the worker
    {:ok, _pid} = Snakepit.GRPC.Worker.start_link()
    
    # Wait for ready
    {:ok, channel} = Snakepit.GRPC.Worker.await_ready(30_000)
    
    channel
  end
  
  def cleanup_bridge do
    # Stop worker if running
    case Process.whereis(Snakepit.GRPC.Worker) do
      nil -> :ok
      pid -> 
        Process.exit(pid, :kill)
        Process.sleep(100)
    end
  end
  
  def create_test_session(channel) do
    session_id = "test_session_#{System.unique_integer([:positive])}"
    
    # Ensure session exists by making a call
    Snakepit.GRPC.Client.list_variables(channel, session_id)
    
    session_id
  end
  
  def with_timeout(timeout, fun) do
    task = Task.async(fun)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> flunk("Test timed out after #{timeout}ms")
    end
  end
  
  def wait_for_update(timeout \\ 5000) do
    receive do
      {:variable_update, update} -> update
    after
      timeout -> flunk("No update received within #{timeout}ms")
    end
  end
end
```

### 2. Test Server Startup

```elixir
# File: test/integration/server_startup_test.exs

defmodule ServerStartupTest do
  use ExUnit.Case
  import BridgeTestHelper
  
  @moduletag :integration
  
  describe "server startup" do
    test "detects GRPC_READY message via stdout" do
      # Start fresh
      cleanup_bridge()
      
      # Capture logs to verify stdout monitoring
      log_capture = ExUnit.CaptureLog.capture_log(fn ->
        {:ok, _pid} = Snakepit.GRPC.Worker.start_link()
        {:ok, _channel} = Snakepit.GRPC.Worker.await_ready(10_000)
      end)
      
      # Verify we saw the ready message
      assert log_capture =~ "Python gRPC server ready on port"
      assert log_capture =~ "GRPC_READY:"
    end
    
    test "handles server crash and restart" do
      channel = start_bridge()
      
      # Get the Python process port
      %{python_port: port} = :sys.get_state(Snakepit.GRPC.Worker)
      
      # Kill the Python process
      Port.close(port)
      
      # Wait a bit
      Process.sleep(100)
      
      # Worker should detect the crash
      refute Process.alive?(Process.whereis(Snakepit.GRPC.Worker))
    end
    
    test "concurrent startup requests" do
      cleanup_bridge()
      
      # Start multiple processes trying to connect
      tasks = for _ <- 1..5 do
        Task.async(fn ->
          {:ok, _pid} = Snakepit.GRPC.Worker.start_link()
          Snakepit.GRPC.Worker.await_ready(10_000)
        end)
      end
      
      # All should succeed with the same channel
      results = Task.await_many(tasks, 15_000)
      channels = Enum.map(results, fn {:ok, ch} -> ch end)
      
      # Should all be the same channel
      assert length(Enum.uniq(channels)) == 1
    end
  end
end
```

### 3. Test Variable Operations

```elixir
# File: test/integration/variable_operations_test.exs

defmodule VariableOperationsTest do
  use ExUnit.Case
  import BridgeTestHelper
  
  @moduletag :integration
  
  setup do
    channel = start_bridge()
    session_id = create_test_session(channel)
    
    {:ok, channel: channel, session_id: session_id}
  end
  
  describe "variable CRUD operations" do
    test "register and get variable", %{channel: channel, session_id: session_id} do
      # Register
      {:ok, var_id, variable} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "test_var",
        :float,
        3.14,
        metadata: %{"source" => "test"}
      )
      
      assert var_id
      assert variable.name == "test_var"
      assert variable.type == :float
      assert variable.value == 3.14
      
      # Get by name
      {:ok, retrieved} = Snakepit.GRPC.Client.get_variable(
        channel,
        session_id,
        "test_var"
      )
      
      assert retrieved.value == 3.14
      
      # Get by ID
      {:ok, retrieved} = Snakepit.GRPC.Client.get_variable(
        channel,
        session_id,
        var_id
      )
      
      assert retrieved.value == 3.14
    end
    
    test "update variable", %{channel: channel, session_id: session_id} do
      # Register
      {:ok, var_id, _} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "mutable_var",
        :integer,
        42
      )
      
      # Update
      :ok = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "mutable_var",
        100,
        %{"reason" => "test update"}
      )
      
      # Verify
      {:ok, updated} = Snakepit.GRPC.Client.get_variable(
        channel,
        session_id,
        var_id
      )
      
      assert updated.value == 100
      assert updated.version > 1
    end
    
    test "list variables", %{channel: channel, session_id: session_id} do
      # Register multiple
      variables = for i <- 1..5 do
        {:ok, _, var} = Snakepit.GRPC.Client.register_variable(
          channel,
          session_id,
          "var_#{i}",
          :integer,
          i * 10
        )
        var
      end
      
      # List
      {:ok, listed} = Snakepit.GRPC.Client.list_variables(channel, session_id)
      
      assert length(listed) >= 5
      names = Enum.map(listed, & &1.name)
      assert "var_1" in names
      assert "var_5" in names
    end
  end
  
  describe "type constraints" do
    test "validates numeric constraints", %{channel: channel, session_id: session_id} do
      # Register with constraints
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "constrained_float",
        :float,
        0.5,
        constraints: %{min: 0.0, max: 1.0}
      )
      
      # Valid update
      assert :ok = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "constrained_float",
        0.7
      )
      
      # Invalid update
      assert {:error, _} = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "constrained_float",
        1.5
      )
    end
    
    test "validates choice constraints", %{channel: channel, session_id: session_id} do
      # Register choice variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "model_choice",
        :choice,
        "gpt-4",
        constraints: %{choices: ["gpt-4", "claude-3", "gemini"]}
      )
      
      # Valid choice
      assert :ok = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "model_choice",
        "claude-3"
      )
      
      # Invalid choice
      assert {:error, _} = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "model_choice",
        "invalid-model"
      )
    end
  end
end
```

### 4. Test Streaming

```elixir
# File: test/integration/streaming_test.exs

defmodule StreamingTest do
  use ExUnit.Case
  import BridgeTestHelper
  
  @moduletag :integration
  
  setup do
    channel = start_bridge()
    session_id = create_test_session(channel)
    
    {:ok, channel: channel, session_id: session_id}
  end
  
  describe "variable watching" do
    test "receives initial values", %{channel: channel, session_id: session_id} do
      # Register variables
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "var1", :float, 1.0
      )
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "var2", :integer, 42
      )
      
      # Start watching with initial values
      {:ok, stream} = Snakepit.GRPC.Client.watch_variables(
        channel,
        session_id,
        ["var1", "var2"],
        include_initial: true
      )
      
      # Collect initial values
      test_pid = self()
      
      consumer = Task.async(fn ->
        stream
        |> Enum.take(2)
        |> Enum.each(fn {:ok, update} ->
          send(test_pid, {:initial, update.variable.name, update.variable.value})
        end)
      end)
      
      # Should receive both initial values
      assert_receive {:initial, "var1", 1.0}, 1000
      assert_receive {:initial, "var2", 42}, 1000
      
      Task.await(consumer)
    end
    
    test "receives updates in real-time", %{channel: channel, session_id: session_id} do
      # Register variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "watched_var", :float, 0.0
      )
      
      # Start watching
      {:ok, stream} = Snakepit.GRPC.Client.watch_variables(
        channel,
        session_id,
        ["watched_var"],
        include_initial: false
      )
      
      # Start consumer
      test_pid = self()
      
      _consumer = Task.async(fn ->
        Snakepit.GRPC.StreamHandler.consume_stream(stream, fn name, old, new, meta ->
          send(test_pid, {:update, name, old, new})
        end)
      end)
      
      # Wait a bit for stream to establish
      Process.sleep(100)
      
      # Make updates
      for value <- [0.1, 0.2, 0.3] do
        :ok = Snakepit.GRPC.Client.set_variable(
          channel, session_id, "watched_var", value
        )
        
        # Should receive update
        assert_receive {:update, "watched_var", _, ^value}, 1000
      end
    end
    
    test "multiple watchers", %{channel: channel, session_id: session_id} do
      # Register variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "multi_watched", :integer, 0
      )
      
      # Start multiple watchers
      watchers = for i <- 1..3 do
        {:ok, stream} = Snakepit.GRPC.Client.watch_variables(
          channel,
          session_id,
          ["multi_watched"],
          include_initial: false
        )
        
        test_pid = self()
        watcher_id = i
        
        Task.async(fn ->
          Snakepit.GRPC.StreamHandler.consume_stream(stream, fn name, _old, new, _meta ->
            send(test_pid, {:watcher_update, watcher_id, name, new})
          end)
        end)
        
        {i, stream}
      end
      
      # Wait for streams to establish
      Process.sleep(200)
      
      # Update variable
      :ok = Snakepit.GRPC.Client.set_variable(
        channel, session_id, "multi_watched", 999
      )
      
      # All watchers should receive the update
      for i <- 1..3 do
        assert_receive {:watcher_update, ^i, "multi_watched", 999}, 2000
      end
    end
    
    test "handles stream disconnection", %{channel: channel, session_id: session_id} do
      # Register variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "disconnect_test", :string, "initial"
      )
      
      # Start watching
      {:ok, stream} = Snakepit.GRPC.Client.watch_variables(
        channel,
        session_id,
        ["disconnect_test"],
        include_initial: false
      )
      
      # Start consumer that we'll kill
      test_pid = self()
      
      consumer = Task.async(fn ->
        Snakepit.GRPC.StreamHandler.consume_stream(stream, fn name, _old, new, _meta ->
          send(test_pid, {:update, name, new})
        end)
      end)
      
      # Wait for establishment
      Process.sleep(100)
      
      # Kill the consumer
      Task.shutdown(consumer, :brutal_kill)
      
      # Update should not crash anything
      :ok = Snakepit.GRPC.Client.set_variable(
        channel, session_id, "disconnect_test", "updated"
      )
      
      # Should not receive update (consumer is dead)
      refute_receive {:update, _, _}, 500
    end
  end
end
```

### 5. Test Complex Types

```elixir
# File: test/integration/complex_types_test.exs

defmodule ComplexTypesTest do
  use ExUnit.Case
  import BridgeTestHelper
  
  @moduletag :integration
  
  setup do
    channel = start_bridge()
    session_id = create_test_session(channel)
    
    {:ok, channel: channel, session_id: session_id}
  end
  
  describe "embedding type" do
    test "stores and retrieves embeddings", %{channel: channel, session_id: session_id} do
      embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
      
      {:ok, _, var} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "text_embedding",
        :embedding,
        embedding,
        constraints: %{dimensions: 5}
      )
      
      assert var.value == embedding
      
      # Update with wrong dimensions should fail
      assert {:error, _} = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "text_embedding",
        [0.1, 0.2]  # Wrong size
      )
    end
  end
  
  describe "tensor type" do
    test "stores and retrieves tensors", %{channel: channel, session_id: session_id} do
      tensor = %{
        "shape" => [2, 3],
        "data" => [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
      }
      
      {:ok, _, var} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "matrix",
        :tensor,
        tensor
      )
      
      assert var.value["shape"] == [2, 3]
      assert List.flatten(var.value["data"]) == [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    end
  end
  
  describe "module type" do
    test "stores DSPy module references", %{channel: channel, session_id: session_id} do
      {:ok, _, var} = Snakepit.GRPC.Client.register_variable(
        channel,
        session_id,
        "reasoning_module",
        :module,
        "ChainOfThought",
        constraints: %{choices: ["Predict", "ChainOfThought", "ReAct"]}
      )
      
      assert var.value == "ChainOfThought"
      
      # Can update to another valid module
      :ok = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "reasoning_module",
        "ReAct"
      )
      
      # Cannot use invalid module
      assert {:error, _} = Snakepit.GRPC.Client.set_variable(
        channel,
        session_id,
        "reasoning_module",
        "InvalidModule"
      )
    end
  end
end
```

### 6. Test Performance

```elixir
# File: test/integration/performance_test.exs

defmodule PerformanceTest do
  use ExUnit.Case
  import BridgeTestHelper
  
  @moduletag :integration
  @moduletag :performance
  
  setup do
    channel = start_bridge()
    session_id = create_test_session(channel)
    
    {:ok, channel: channel, session_id: session_id}
  end
  
  describe "latency benchmarks" do
    test "variable get latency", %{channel: channel, session_id: session_id} do
      # Register variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "perf_var", :float, 1.0
      )
      
      # Warmup
      for _ <- 1..10 do
        Snakepit.GRPC.Client.get_variable(channel, session_id, "perf_var")
      end
      
      # Measure
      latencies = for _ <- 1..100 do
        start = System.monotonic_time(:microsecond)
        {:ok, _} = Snakepit.GRPC.Client.get_variable(channel, session_id, "perf_var")
        System.monotonic_time(:microsecond) - start
      end
      
      avg_latency = Enum.sum(latencies) / length(latencies)
      p95_latency = Enum.at(Enum.sort(latencies), 95)
      
      IO.puts("Get latency - Avg: #{avg_latency}μs, P95: #{p95_latency}μs")
      
      # Should be under 5ms average
      assert avg_latency < 5000
    end
    
    test "streaming throughput", %{channel: channel, session_id: session_id} do
      # Register variable
      {:ok, _, _} = Snakepit.GRPC.Client.register_variable(
        channel, session_id, "stream_var", :integer, 0
      )
      
      # Start watcher
      {:ok, stream} = Snakepit.GRPC.Client.watch_variables(
        channel,
        session_id,
        ["stream_var"],
        include_initial: false
      )
      
      # Count updates
      test_pid = self()
      counter = Task.async(fn ->
        count = stream
        |> Stream.take_while(fn _ -> true end)
        |> Enum.reduce(0, fn {:ok, _update}, acc ->
          if acc == 0, do: send(test_pid, :first_update)
          acc + 1
        end)
        
        count
      end)
      
      # Wait for stream to establish
      assert_receive :first_update, 5000
      
      # Send rapid updates
      start_time = System.monotonic_time(:millisecond)
      
      for i <- 1..1000 do
        Snakepit.GRPC.Client.set_variable(channel, session_id, "stream_var", i)
      end
      
      # Wait a bit for propagation
      Process.sleep(1000)
      
      # Check throughput
      elapsed = System.monotonic_time(:millisecond) - start_time
      updates_per_second = 1000 / (elapsed / 1000)
      
      IO.puts("Streaming throughput: #{updates_per_second} updates/second")
      
      # Should handle at least 100 updates/second
      assert updates_per_second > 100
      
      Task.shutdown(counter)
    end
  end
end
```

### 7. Create Test Configuration

```elixir
# File: config/test.exs

import Config

# Configure test environment
config :snakepit,
  python_path: System.get_env("PYTHON_PATH", "python3"),
  grpc_timeout: 5_000,
  test_mode: true

# Reduce logs in test
config :logger, level: :warning

# Configure ExUnit
config :ex_unit,
  capture_log: true,
  exclude: [:performance]  # Exclude performance tests by default
```

### 8. Create Test Runner Script

```bash
#!/bin/bash
# File: scripts/run_integration_tests.sh

echo "Running DSPex gRPC Bridge Integration Tests"
echo "=========================================="

# Ensure Python dependencies are installed
echo "Installing Python dependencies..."
cd snakepit/priv/python
pip install -r requirements.txt
cd ../../..

# Compile protocol buffers
echo "Compiling protocol buffers..."
cd snakepit
mix protobuf.compile
cd ..

# Run tests
echo "Running integration tests..."
cd snakepit
mix test --only integration

# Run performance tests if requested
if [ "$1" == "--perf" ]; then
  echo "Running performance tests..."
  mix test --only performance
fi
```

## Testing Checklist

- [ ] Server starts correctly with stdout detection
- [ ] All variable types serialize/deserialize correctly
- [ ] Constraints are enforced properly
- [ ] Streaming delivers updates reliably
- [ ] Multiple sessions are isolated
- [ ] Concurrent operations don't conflict
- [ ] Performance meets requirements
- [ ] Error handling is graceful
- [ ] Python crashes are handled
- [ ] Memory usage is stable

## Files to Create/Modify

1. Create: `test/support/bridge_test_helper.ex`
2. Create: `test/integration/server_startup_test.exs`
3. Create: `test/integration/variable_operations_test.exs`
4. Create: `test/integration/streaming_test.exs`
5. Create: `test/integration/complex_types_test.exs`
6. Create: `test/integration/performance_test.exs`
7. Update: `config/test.exs`
8. Create: `scripts/run_integration_tests.sh`

## Next Steps

After creating integration tests:
1. Run all tests to ensure they pass
2. Fix any issues discovered
3. Add CI/CD integration
4. Document any performance findings
5. Create stress tests for production readiness

## Success Metrics

- All integration tests pass consistently
- Average latency < 5ms for variable operations  
- Streaming can handle > 100 updates/second
- No memory leaks over extended runs
- Graceful handling of all error conditions