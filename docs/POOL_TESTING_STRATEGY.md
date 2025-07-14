# Comprehensive Testing Strategy for DSPex Python Bridge Pool System

## Overview

This document outlines a robust testing strategy for the NimblePool-based Python bridge implementation. The strategy covers unit tests, integration tests, performance tests, and chaos engineering to ensure production readiness.

## Testing Philosophy

1. **Isolation**: Tests should be independent and not affect each other
2. **Determinism**: Tests should produce consistent results
3. **Coverage**: Test both happy paths and edge cases
4. **Performance**: Tests should run efficiently
5. **Observability**: Tests should provide clear failure diagnostics

## Test Architecture Layers

### Layer 1: Unit Tests (Fast, Isolated)
- Mock all external dependencies
- Test individual functions and modules
- Sub-second execution time
- Run on every commit

### Layer 2: Component Tests (Integration)
- Test component interactions
- Use test doubles for Python processes
- Focus on protocol correctness
- Run on every push

### Layer 3: System Tests (Full Integration)
- Real Python processes
- End-to-end scenarios
- Performance validation
- Run on CI/CD pipeline

### Layer 4: Stress & Chaos Tests
- Load testing
- Fault injection
- Resource exhaustion
- Run nightly or on-demand

## Component Testing Strategy

### 1. PoolWorker Tests

#### Unit Tests
```elixir
defmodule DSPex.PythonBridge.PoolWorkerTest do
  use ExUnit.Case, async: true
  alias DSPex.PythonBridge.PoolWorker
  
  describe "init_worker/1" do
    test "initializes worker with correct state" do
      pool_state = %{worker_id: "test_1"}
      {:ok, worker_state, updated_pool} = PoolWorker.init_worker(pool_state)
      
      assert worker_state.worker_id == "test_1"
      assert worker_state.status == :ready
      assert is_port(worker_state.port)
    end
    
    test "handles initialization failure gracefully" do
      # Mock port spawn failure
      with_mock Port, [open: fn(_, _) -> {:error, :enoent} end] do
        pool_state = %{worker_id: "test_fail"}
        assert {:error, :worker_init_failed} = PoolWorker.init_worker(pool_state)
      end
    end
  end
  
  describe "handle_checkout/4" do
    test "binds worker to session on checkout" do
      worker_state = %{session_id: nil, status: :ready}
      from = {:session, "user_123"}
      
      {:ok, _, updated_state, _} = PoolWorker.handle_checkout(:checkout, from, worker_state, %{})
      
      assert updated_state.session_id == "user_123"
      assert updated_state.status == :busy
    end
    
    test "maintains session affinity" do
      worker_state = %{session_id: "user_123", status: :ready}
      from = {:session, "user_123"}
      
      {:ok, _, updated_state, _} = PoolWorker.handle_checkout(:checkout, from, worker_state, %{})
      
      assert updated_state.session_id == "user_123"
    end
    
    test "rejects checkout for different session when bound" do
      worker_state = %{session_id: "user_123", status: :busy}
      from = {:session, "user_456"}
      
      {:error, :session_mismatch} = PoolWorker.handle_checkout(:checkout, from, worker_state, %{})
    end
  end
  
  describe "send_command/4" do
    setup do
      # Create a mock port
      {:ok, port} = MockPort.start_link()
      worker_state = %{port: port, session_id: "test", request_id: 0}
      {:ok, worker_state: worker_state}
    end
    
    test "sends command and receives response", %{worker_state: worker_state} do
      MockPort.expect_command(worker_state.port, "create_program", %{"id" => "prog_1"})
      
      {:ok, response, _} = PoolWorker.send_command(worker_state, :create_program, %{}, 5000)
      
      assert response["result"]["id"] == "prog_1"
    end
    
    test "handles timeout correctly", %{worker_state: worker_state} do
      MockPort.simulate_timeout(worker_state.port)
      
      assert {:error, :timeout} = PoolWorker.send_command(worker_state, :slow_op, %{}, 100)
    end
    
    test "correlates requests and responses", %{worker_state: worker_state} do
      # Send multiple concurrent requests
      tasks = for i <- 1..10 do
        Task.async(fn ->
          PoolWorker.send_command(worker_state, :echo, %{value: i}, 5000)
        end)
      end
      
      results = Task.await_many(tasks)
      values = Enum.map(results, fn {:ok, resp, _} -> resp["result"]["value"] end)
      
      assert Enum.sort(values) == Enum.to_list(1..10)
    end
  end
  
  describe "health_check/1" do
    test "reports healthy for responsive worker" do
      worker_state = %{port: MockPort.healthy(), last_health_check: 0}
      
      {:ok, :healthy, updated_state} = PoolWorker.health_check(worker_state)
      
      assert updated_state.last_health_check > 0
    end
    
    test "reports unhealthy for unresponsive worker" do
      worker_state = %{port: MockPort.unhealthy(), last_health_check: 0}
      
      {:ok, :unhealthy, updated_state} = PoolWorker.health_check(worker_state)
      
      assert updated_state.health_failures > 0
    end
  end
end
```

#### Integration Tests
```elixir
defmodule DSPex.PythonBridge.PoolWorkerIntegrationTest do
  use ExUnit.Case
  
  @moduletag :integration
  @moduletag timeout: 30_000
  
  setup do
    # Start real Python process
    {:ok, worker_state, _} = PoolWorker.init_worker(%{worker_id: "integration_test"})
    
    on_exit(fn ->
      PoolWorker.terminate_worker(:shutdown, worker_state, %{})
    end)
    
    {:ok, worker: worker_state}
  end
  
  test "full lifecycle with real Python process", %{worker: worker} do
    # Create program
    {:ok, create_resp, worker} = PoolWorker.send_command(
      worker, 
      :create_program,
      %{"signature" => %{"inputs" => ["query"], "outputs" => ["answer"]}},
      10_000
    )
    
    program_id = create_resp["result"]["program_id"]
    assert is_binary(program_id)
    
    # Execute program
    {:ok, exec_resp, worker} = PoolWorker.send_command(
      worker,
      :execute_program,
      %{"program_id" => program_id, "inputs" => %{"query" => "test"}},
      10_000
    )
    
    assert exec_resp["result"]["answer"] != nil
    
    # Cleanup
    {:ok, _, _} = PoolWorker.send_command(
      worker,
      :delete_program,
      %{"program_id" => program_id},
      5_000
    )
  end
end
```

### 2. SessionPool Tests

#### Unit Tests
```elixir
defmodule DSPex.PythonBridge.SessionPoolTest do
  use ExUnit.Case
  alias DSPex.PythonBridge.SessionPool
  
  describe "session management" do
    setup do
      {:ok, _} = SessionPool.start_link(name: :test_pool, pool_size: 2)
      :ok
    end
    
    test "tracks sessions correctly" do
      assert :ok = GenServer.call(:test_pool, {:track_session, "session_1"})
      assert :ok = GenServer.call(:test_pool, {:track_session, "session_2"})
      
      sessions = GenServer.call(:test_pool, :get_sessions)
      assert map_size(sessions) == 2
      assert Map.has_key?(sessions, "session_1")
      assert Map.has_key?(sessions, "session_2")
    end
    
    test "ends sessions and cleans up" do
      GenServer.call(:test_pool, {:track_session, "temp_session"})
      assert :ok = GenServer.call(:test_pool, {:end_session, "temp_session"})
      
      sessions = GenServer.call(:test_pool, :get_sessions)
      refute Map.has_key?(sessions, "temp_session")
    end
    
    test "handles non-existent session end" do
      assert {:error, :session_not_found} = 
        GenServer.call(:test_pool, {:end_session, "ghost_session"})
    end
  end
  
  describe "metrics tracking" do
    test "updates metrics on operations" do
      {:ok, pool} = SessionPool.start_link(pool_size: 1)
      
      initial_status = SessionPool.get_pool_status()
      assert initial_status.metrics.total_operations == 0
      
      # Perform operations
      SessionPool.execute_in_session("metric_test", :ping, %{})
      SessionPool.execute_in_session("metric_test", :ping, %{})
      
      updated_status = SessionPool.get_pool_status()
      assert updated_status.metrics.total_operations >= 2
    end
  end
  
  describe "pool overflow handling" do
    test "queues requests when pool is exhausted" do
      {:ok, _} = SessionPool.start_link(
        name: :small_pool,
        pool_size: 1,
        overflow: 0
      )
      
      # Occupy the single worker
      task1 = Task.async(fn ->
        SessionPool.execute_in_session("session_1", :sleep, %{duration: 500})
      end)
      
      # This should queue
      task2 = Task.async(fn ->
        SessionPool.execute_in_session("session_2", :ping, %{})
      end)
      
      # Both should eventually complete
      assert {:ok, _} = Task.await(task1, 1000)
      assert {:ok, _} = Task.await(task2, 1000)
    end
    
    test "respects checkout timeout" do
      {:ok, _} = SessionPool.start_link(
        name: :timeout_pool,
        pool_size: 1,
        overflow: 0,
        checkout_timeout: 100
      )
      
      # Occupy the worker
      Task.async(fn ->
        SessionPool.execute_in_session("blocker", :sleep, %{duration: 500})
      end)
      
      # This should timeout
      assert {:error, :pool_timeout} = 
        SessionPool.execute_in_session("waiter", :ping, %{}, pool_timeout: 100)
    end
  end
end
```

#### Concurrent Operation Tests
```elixir
defmodule DSPex.PythonBridge.SessionPoolConcurrencyTest do
  use ExUnit.Case
  
  @moduletag :integration
  @moduletag timeout: 60_000
  
  test "handles concurrent sessions without interference" do
    {:ok, _} = SessionPool.start_link(pool_size: 4)
    
    # Create multiple concurrent sessions
    sessions = for i <- 1..10, do: "concurrent_#{i}"
    
    tasks = Enum.map(sessions, fn session_id ->
      Task.async(fn ->
        # Each session creates its own program
        {:ok, program_id} = SessionPool.execute_in_session(
          session_id,
          :create_program,
          %{signature: TestSignatures.simple()}
        )
        
        # Execute multiple times
        for j <- 1..5 do
          {:ok, result} = SessionPool.execute_in_session(
            session_id,
            :execute_program,
            %{program_id: program_id, inputs: %{value: j}}
          )
          
          assert result["value"] == j * 2  # Assuming doubler program
        end
        
        # Cleanup
        SessionPool.end_session(session_id)
        
        :ok
      end)
    end)
    
    # All should complete successfully
    results = Task.await_many(tasks, 30_000)
    assert Enum.all?(results, &(&1 == :ok))
  end
  
  test "session isolation prevents cross-contamination" do
    {:ok, _} = SessionPool.start_link(pool_size: 2)
    
    # Session 1 creates a program
    {:ok, prog1} = SessionPool.execute_in_session(
      "user_1",
      :create_program,
      %{id: "prog_1", signature: TestSignatures.simple()}
    )
    
    # Session 2 creates a different program
    {:ok, prog2} = SessionPool.execute_in_session(
      "user_2", 
      :create_program,
      %{id: "prog_2", signature: TestSignatures.complex()}
    )
    
    # Session 1 should not see Session 2's program
    {:ok, programs1} = SessionPool.execute_in_session("user_1", :list_programs, %{})
    assert prog1 in programs1
    refute prog2 in programs1
    
    # Session 2 should not see Session 1's program
    {:ok, programs2} = SessionPool.execute_in_session("user_2", :list_programs, %{})
    assert prog2 in programs2
    refute prog1 in programs2
  end
end
```

### 3. Adapter Tests

```elixir
defmodule DSPex.Adapters.PythonPoolTest do
  use ExUnit.Case
  alias DSPex.Adapters.PythonPool
  
  describe "adapter interface compliance" do
    test "implements all required callbacks" do
      callbacks = [
        {:create_program, 1},
        {:execute_program, 2},
        {:execute_program, 3},
        {:list_programs, 0},
        {:delete_program, 1},
        {:get_program_info, 1},
        {:health_check, 0},
        {:get_stats, 0},
        {:supports_test_layer?, 1},
        {:get_test_capabilities, 0}
      ]
      
      for {func, arity} <- callbacks do
        assert function_exported?(PythonPool, func, arity),
          "Missing required function: #{func}/#{arity}"
      end
    end
  end
  
  describe "session adapter creation" do
    test "creates bound adapter instance" do
      adapter = PythonPool.session_adapter("test_user")
      
      assert is_map(adapter)
      assert adapter.session_id == "test_user"
      assert is_function(adapter.create_program, 1)
      assert is_function(adapter.execute_program, 3)
    end
    
    test "bound adapter maintains session context" do
      adapter = PythonPool.session_adapter("bound_test")
      
      with_mock SessionPool, [execute_in_session: fn(sid, _, _, _) -> 
        send(self(), {:session_id, sid})
        {:ok, %{}}
      end] do
        adapter.create_program(%{})
        assert_received {:session_id, "bound_test"}
      end
    end
  end
end
```

### 4. Property-Based Tests

```elixir
defmodule DSPex.PythonBridge.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "pool handles any valid session ID" do
    check all session_id <- string(:alphanumeric, min_length: 1) do
      assert :ok = SessionPool.execute_in_session(session_id, :ping, %{})
      assert :ok = SessionPool.end_session(session_id)
    end
  end
  
  property "worker state transitions are valid" do
    check all commands <- list_of(command_generator(), min_length: 1, max_length: 20) do
      worker_state = %{status: :ready, session_id: nil}
      
      final_state = Enum.reduce(commands, worker_state, fn cmd, state ->
        case PoolWorker.handle_checkout(cmd.type, cmd.from, state, %{}) do
          {:ok, _, new_state, _} -> new_state
          {:error, _} -> state
        end
      end)
      
      assert final_state.status in [:ready, :busy]
    end
  end
  
  defp command_generator do
    gen all type <- member_of([:checkout, :checkin]),
            session <- string(:alphanumeric, min_length: 1, max_length: 10) do
      %{type: type, from: {:session, session}}
    end
  end
end
```

## Stress & Performance Testing

### Load Testing
```elixir
defmodule DSPex.PythonBridge.LoadTest do
  use ExUnit.Case
  
  @moduletag :load_test
  @moduletag timeout: :infinity
  
  test "handles specified load profile" do
    config = %{
      duration_seconds: 60,
      concurrent_users: 100,
      operations_per_second: 10,
      pool_size: System.schedulers_online() * 2
    }
    
    {:ok, _} = SessionPool.start_link(pool_size: config.pool_size)
    
    results = LoadRunner.run(config)
    
    assert results.success_rate > 0.99
    assert results.p95_latency < 100  # milliseconds
    assert results.p99_latency < 500
    assert results.errors == []
  end
end
```

### Chaos Engineering Tests
```elixir
defmodule DSPex.PythonBridge.ChaosTest do
  use ExUnit.Case
  
  @moduletag :chaos
  @moduletag timeout: 120_000
  
  describe "fault injection" do
    test "recovers from worker crashes" do
      {:ok, _} = SessionPool.start_link(pool_size: 4)
      
      # Start normal operations
      operation_task = Task.async(fn ->
        for i <- 1..100 do
          SessionPool.execute_in_session("chaos_#{i}", :ping, %{})
          Process.sleep(100)
        end
      end)
      
      # Inject faults
      Process.sleep(5_000)
      ChaosMonkey.kill_random_worker()
      
      Process.sleep(5_000)
      ChaosMonkey.corrupt_worker_state()
      
      # Operations should continue
      assert Task.await(operation_task, 60_000)
      
      # Pool should be healthy
      assert {:ok, :healthy, _} = SessionPool.health_check()
    end
    
    test "handles memory pressure" do
      {:ok, _} = SessionPool.start_link(pool_size: 2)
      
      # Create memory pressure
      ChaosMonkey.consume_memory(0.8)  # Use 80% of available memory
      
      # Pool should still function
      assert {:ok, _} = SessionPool.execute_in_session("memory_test", :ping, %{})
    end
    
    test "handles network delays" do
      {:ok, _} = SessionPool.start_link(pool_size: 2)
      
      # Inject network delays
      ChaosMonkey.add_latency(:port_communication, 500)  # 500ms delay
      
      # Operations should complete, just slower
      assert {:ok, _} = SessionPool.execute_in_session(
        "latency_test", 
        :ping, 
        %{},
        timeout: 2000
      )
    end
  end
end
```

## Test Helpers and Fixtures

### Mock Port Implementation
```elixir
defmodule MockPort do
  use GenServer
  
  def start_link(opts \\\\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def expect_command(port, command, response) do
    GenServer.call(port, {:expect, command, response})
  end
  
  def simulate_timeout(port) do
    GenServer.call(port, :simulate_timeout)
  end
  
  def healthy do
    {:ok, port} = start_link()
    expect_command(port, "ping", %{"status" => "ok"})
    port
  end
  
  def unhealthy do
    {:ok, port} = start_link()
    simulate_timeout(port)
    port
  end
  
  # GenServer implementation...
end
```

### Test Data Generators
```elixir
defmodule TestDataGenerators do
  def session_id do
    "test_#{:rand.uniform(10000)}_#{System.unique_integer([:positive])}"
  end
  
  def program_config do
    %{
      id: "test_program_#{System.unique_integer([:positive])}",
      signature: Enum.random([
        TestSignatures.simple(),
        TestSignatures.complex(),
        TestSignatures.chain()
      ])
    }
  end
  
  def bulk_operations(count) do
    for _ <- 1..count do
      %{
        type: Enum.random([:create, :execute, :list, :delete]),
        data: random_operation_data()
      }
    end
  end
end
```

### Performance Measurement
```elixir
defmodule PerformanceHelpers do
  def measure_operation(fun) do
    start = System.monotonic_time(:microsecond)
    result = fun.()
    duration = System.monotonic_time(:microsecond) - start
    {result, duration}
  end
  
  def benchmark_pool(config) do
    warmup_iterations = config[:warmup] || 100
    test_iterations = config[:iterations] || 1000
    
    # Warmup
    for _ <- 1..warmup_iterations do
      config.operation.()
    end
    
    # Measure
    timings = for _ <- 1..test_iterations do
      {_, duration} = measure_operation(config.operation)
      duration
    end
    
    %{
      min: Enum.min(timings),
      max: Enum.max(timings),
      mean: mean(timings),
      median: median(timings),
      p95: percentile(timings, 95),
      p99: percentile(timings, 99)
    }
  end
end
```

## Test Isolation Strategies

### 1. Process Isolation
```elixir
defmodule IsolatedTest do
  use ExUnit.Case
  
  setup do
    # Start isolated supervision tree
    {:ok, sup} = IsolatedSupervisor.start_link()
    
    on_exit(fn ->
      Supervisor.stop(sup)
    end)
    
    {:ok, supervisor: sup}
  end
end
```

### 2. Port Isolation
```elixir
defmodule PortIsolation do
  def with_isolated_port(fun) do
    # Use unique port names
    port_id = "test_port_#{System.unique_integer([:positive])}"
    
    # Ensure cleanup
    try do
      fun.(port_id)
    after
      cleanup_port(port_id)
    end
  end
end
```

### 3. Configuration Isolation
```elixir
defmodule ConfigIsolation do
  def with_config(config, fun) do
    original = Application.get_all_env(:dspex)
    
    try do
      Enum.each(config, fn {key, value} ->
        Application.put_env(:dspex, key, value)
      end)
      
      fun.()
    after
      # Restore original config
      Enum.each(original, fn {key, value} ->
        Application.put_env(:dspex, key, value)
      end)
    end
  end
end
```

## Continuous Integration Setup

### Test Matrix
```yaml
test:
  strategy:
    matrix:
      elixir: ['1.17', '1.18']
      otp: ['26', '27']
      python: ['3.11', '3.12']
      pool_size: [1, 4, 16]
      
  steps:
    - name: Unit Tests
      run: mix test.fast
      
    - name: Integration Tests
      run: mix test.protocol
      
    - name: Full System Tests
      run: mix test.integration
      
    - name: Load Tests
      if: matrix.pool_size == 16
      run: mix test --only load_test
      
    - name: Chaos Tests
      if: github.event_name == 'schedule'
      run: mix test --only chaos
```

### Performance Benchmarks
```elixir
defmodule Benchmarks do
  def run do
    Benchee.run(%{
      "single_session" => fn ->
        SessionPool.execute_in_session("bench", :ping, %{})
      end,
      
      "concurrent_sessions" => fn ->
        tasks = for i <- 1..10 do
          Task.async(fn ->
            SessionPool.execute_in_session("bench_#{i}", :ping, %{})
          end)
        end
        Task.await_many(tasks)
      end,
      
      "session_creation" => fn ->
        session = "bench_#{System.unique_integer()}"
        SessionPool.execute_in_session(session, :ping, %{})
        SessionPool.end_session(session)
      end
    })
  end
end
```

## Test Execution Strategy

### Development
```bash
# Fast feedback loop
mix test.fast

# Before commit
mix test.protocol
```

### CI/CD Pipeline
```bash
# PR validation
mix check.ci

# Nightly
mix test.all
mix test --only load_test
mix test --only chaos
```

### Release Testing
```bash
# Full regression
mix test.all --cover

# Performance validation
mix run benchmarks.exs

# Stress testing
mix test --only stress --timeout infinity
```

## Summary

This comprehensive testing strategy ensures:

1. **Unit Test Coverage**: Every component tested in isolation
2. **Integration Validation**: Components work together correctly
3. **Concurrency Safety**: No race conditions or deadlocks
4. **Performance Goals**: Meet latency and throughput requirements
5. **Fault Tolerance**: System recovers from failures
6. **Production Readiness**: Confidence in deployment

The strategy emphasizes automated testing at multiple levels with clear isolation boundaries and comprehensive coverage of both happy paths and edge cases.