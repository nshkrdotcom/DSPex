# Prompt: Create Comprehensive Stage 3 Integration Tests

## Objective
Develop thorough integration tests for Stage 3 streaming and reactive capabilities, validating real-time updates, advanced variable types, and cross-language reactive programming patterns.

## Context
Stage 3 transforms the bridge into a reactive platform. The tests must verify:
- Variable watching works across backends
- Streaming provides real-time updates
- Advanced types (choice, module) function correctly
- No stale reads occur
- Performance meets targets

## Requirements

### Test Coverage
1. LocalState watching with process messaging
2. BridgedState watching with gRPC streaming
3. Cross-language reactive updates
4. Advanced type validation and usage
5. Error recovery and reconnection
6. Performance benchmarks
7. Concurrent watcher stress tests

### Critical Tests
- Stale read prevention
- Observer cleanup on process death
- Stream reconnection
- High-frequency update handling

## Implementation

### Core Integration Tests

```elixir
# File: test/dspex/integration/stage3_reactive_test.exs

defmodule DSPex.Integration.Stage3ReactiveTest do
  @moduledoc """
  Comprehensive integration tests for Stage 3 reactive capabilities.
  
  Tests streaming, watching, and advanced variable types across
  both LocalState and BridgedState backends.
  """
  
  use ExUnit.Case, async: false
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.ObserverManager
  import DSPex.TestHelpers.{Timing, Python}
  
  setup do
    # Ensure services are running
    ensure_required_services()
    :ok
  end
  
  describe "LocalState reactive watching" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "receives real-time updates", %{ctx: ctx} do
      # Define variable
      Variables.defvariable!(ctx, :reactive_var, :float, 0.0)
      
      # Collect updates
      updates = []
      test_pid = self()
      
      {:ok, ref} = Variables.watch(ctx, [:reactive_var], 
        fn name, old, new, meta ->
          send(test_pid, {:update, name, old, new, meta})
        end,
        include_initial: false
      )
      
      # Perform rapid updates
      for i <- 1..10 do
        Variables.set(ctx, :reactive_var, i * 0.1)
        Process.sleep(1)
      end
      
      # Collect all updates
      updates = collect_updates(10, 100)
      
      # Should receive all updates in order
      assert length(updates) == 10
      assert Enum.map(updates, fn {_, _, new, _} -> new end) == 
             Enum.map(1..10, &(&1 * 0.1))
      
      Variables.unwatch(ctx, ref)
    end
    
    test "filtering reduces notifications", %{ctx: ctx} do
      Variables.defvariable!(ctx, :noisy_var, :integer, 0)
      
      updates = []
      test_pid = self()
      
      # Only notify on even values
      filter = fn _old, new -> rem(new, 2) == 0 end
      
      {:ok, ref} = Variables.watch(ctx, [:noisy_var], 
        fn name, old, new, _ ->
          send(test_pid, {:filtered, name, old, new})
        end,
        filter: filter,
        include_initial: true  # 0 is even, should notify
      )
      
      # Update with mixed values
      for i <- 1..10, do: Variables.set(ctx, :noisy_var, i)
      
      updates = collect_updates(6, 200)  # 0,2,4,6,8,10
      
      # Only even values
      values = Enum.map(updates, fn {_, _, new} -> new end)
      assert Enum.all?(values, &(rem(&1, 2) == 0))
      assert length(updates) == 6
      
      Variables.unwatch(ctx, ref)
    end
    
    test "automatic cleanup on process death", %{ctx: ctx} do
      Variables.defvariable!(ctx, :cleanup_test, :string, "initial")
      
      # Start watcher in separate process
      watcher_pid = spawn(fn ->
        {:ok, _ref} = Variables.watch(ctx, [:cleanup_test], 
          fn _, _, _, _ -> :ok end
        )
        
        # Signal ready then wait
        send(ctx, :watcher_ready)
        receive do: (:stop -> :ok)
      end)
      
      # Wait for watcher to be ready
      assert_receive :watcher_ready, 1000
      
      # Verify watcher exists
      assert observer_count(:cleanup_test) > 0
      
      # Kill watcher
      Process.exit(watcher_pid, :kill)
      Process.sleep(50)
      
      # Watcher should be cleaned up
      assert observer_count(:cleanup_test) == 0
      
      # Updates should not crash
      assert :ok = Variables.set(ctx, :cleanup_test, "updated")
    end
    
    test "handles concurrent watchers", %{ctx: ctx} do
      Variables.defvariable!(ctx, :concurrent_var, :integer, 0)
      
      # Start multiple watchers
      parent = self()
      watchers = for i <- 1..10 do
        Task.async(fn ->
          {:ok, ref} = Variables.watch(ctx, [:concurrent_var],
            fn _name, _old, new, _ ->
              send(parent, {:watcher, i, new})
            end
          )
          
          # Keep alive
          Process.sleep(1000)
          Variables.unwatch(ctx, ref)
        end)
      end
      
      # Wait for watchers to register
      Process.sleep(50)
      
      # Update variable
      Variables.set(ctx, :concurrent_var, 42)
      
      # Each watcher should receive update
      updates = collect_all_updates(:watcher, 10, 500)
      watcher_ids = Enum.map(updates, fn {:watcher, id, _} -> id end) |> Enum.uniq()
      
      assert length(watcher_ids) == 10
      assert Enum.all?(updates, fn {:watcher, _, value} -> value == 42 end)
      
      # Cleanup
      Task.await_many(watchers)
    end
  end
  
  describe "BridgedState streaming" do
    setup do
      {:ok, ctx} = Context.start_link()
      :ok = Context.ensure_bridged(ctx)
      {:ok, ctx: ctx}
    end
    
    test "gRPC streaming delivers updates", %{ctx: ctx} do
      Variables.defvariable!(ctx, :streamed_var, :float, 1.0)
      
      updates = []
      test_pid = self()
      
      {:ok, ref} = Variables.watch(ctx, [:streamed_var],
        fn name, old, new, meta ->
          send(test_pid, {:stream_update, name, old, new, meta})
        end,
        include_initial: false
      )
      
      # Update through different paths
      Variables.set(ctx, :streamed_var, 2.0)
      
      # Direct SessionStore update
      session_id = Context.get_id(ctx)
      :ok = Snakepit.Bridge.SessionStore.update_variable(
        session_id, :streamed_var, 3.0, %{source: "direct"}
      )
      
      updates = collect_updates(2, 2000)
      
      assert length(updates) == 2
      assert Enum.map(updates, fn {_, _, new, _} -> new end) == [2.0, 3.0]
      
      # Check metadata
      {_, _, _, meta} = List.last(updates)
      assert meta[:source] == "direct"
      
      Variables.unwatch(ctx, ref)
    end
    
    test "prevents stale reads with initial values", %{ctx: ctx} do
      Variables.defvariable!(ctx, :race_test, :integer, 1)
      
      test_pid = self()
      updates = []
      
      # Start watching with initial value
      watch_task = Task.async(fn ->
        Variables.watch(ctx, [:race_test],
          fn name, old, new, meta ->
            send(test_pid, {:ordered_update, name, old, new, meta})
          end,
          include_initial: true
        )
      end)
      
      # Immediately update the variable
      # This tests the atomic observer registration
      Variables.set(ctx, :race_test, 2)
      Variables.set(ctx, :race_test, 3)
      
      # Wait for watch to establish
      {:ok, ref} = Task.await(watch_task)
      
      # Collect updates
      updates = collect_ordered_updates(3, 2000)
      
      # Should see: initial(1), update(2), update(3)
      # Never miss the updates due to race condition
      assert length(updates) == 3
      
      values = Enum.map(updates, fn {_, _, new, _} -> new end)
      assert values == [1, 2, 3]
      
      # First should be marked as initial
      {_, _, _, meta} = hd(updates)
      assert meta[:initial] == true
      
      Variables.unwatch(ctx, ref)
    end
    
    test "heartbeats keep stream alive", %{ctx: ctx} do
      Variables.defvariable!(ctx, :heartbeat_test, :string, "alive")
      
      # Start watching but don't update
      {:ok, ref} = Variables.watch(ctx, [:heartbeat_test], 
        fn _, _, _, _ -> :ok end
      )
      
      # Stream should stay alive for extended period
      Process.sleep(35_000)  # Longer than heartbeat interval
      
      # Stream should still be active
      assert {:ok, watchers} = Context.list_watchers(ctx)
      assert Enum.any?(watchers, & &1.alive)
      
      # Should still receive updates
      test_pid = self()
      Variables.watch_one(ctx, :heartbeat_test,
        fn _, _, new, _ -> send(test_pid, {:still_alive, new}) end
      )
      
      Variables.set(ctx, :heartbeat_test, "still working")
      assert_receive {:still_alive, "still working"}, 2000
      
      Variables.unwatch(ctx, ref)
    end
  end
  
  describe "advanced variable types" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "choice type with validation", %{ctx: ctx} do
      # Define choice variable
      {:ok, _} = Variables.defvariable(ctx, :environment, :choice, "development",
        constraints: %{choices: ["development", "staging", "production"]},
        description: "Deployment environment"
      )
      
      # Valid choices
      assert :ok = Variables.set(ctx, :environment, "staging")
      assert Variables.get(ctx, :environment) == "staging"
      
      assert :ok = Variables.set(ctx, :environment, "production")
      assert Variables.get(ctx, :environment) == "production"
      
      # Invalid choice
      assert {:error, msg} = Variables.set(ctx, :environment, "testing")
      assert msg =~ "must be one of"
      
      # Watch for environment changes
      test_pid = self()
      Variables.watch_one(ctx, :environment,
        fn _, old, new, _ ->
          send(test_pid, {:env_change, old, new})
        end
      )
      
      Variables.set(ctx, :environment, "development")
      assert_receive {:env_change, "production", "development"}
    end
    
    test "module type for dynamic behavior", %{ctx: ctx} do
      # Define module variable
      {:ok, _} = Variables.defvariable(ctx, :strategy, :module, "Strategies.Default",
        constraints: %{
          namespace: "Strategies",
          choices: ["Default", "Optimized", "Experimental"]
        }
      )
      
      # Valid modules
      assert :ok = Variables.set(ctx, :strategy, "Strategies.Optimized")
      assert Variables.get(ctx, :strategy) == "Strategies.Optimized"
      
      # Invalid - wrong namespace
      assert {:error, _} = Variables.set(ctx, :strategy, "Other.Module")
      
      # Invalid - not in choices
      assert {:error, _} = Variables.set(ctx, :strategy, "Strategies.Custom")
      
      # Module without namespace constraint
      {:ok, _} = Variables.defvariable(ctx, :processor, :module, "DefaultProcessor",
        constraints: %{pattern: ".*Processor$"}
      )
      
      assert :ok = Variables.set(ctx, :processor, "CustomProcessor")
      assert :ok = Variables.set(ctx, :processor, "My.Deep.Nested.Processor")
      assert {:error, _} = Variables.set(ctx, :processor, "InvalidModule")
    end
    
    test "reactive type changes", %{ctx: ctx} do
      # Model that affects other variables
      Variables.defvariable!(ctx, :model, :choice, "gpt-3.5-turbo",
        constraints: %{choices: ["gpt-3.5-turbo", "gpt-4", "claude-3"]}
      )
      
      Variables.defvariable!(ctx, :max_tokens, :integer, 2048)
      Variables.defvariable!(ctx, :cost_per_1k, :float, 0.002)
      
      # Watch model changes and update related vars
      Variables.watch_one(ctx, :model, fn _, _, new, _ ->
        case new do
          "gpt-4" ->
            Variables.update_many(ctx, %{
              max_tokens: 4096,
              cost_per_1k: 0.03
            })
            
          "claude-3" ->
            Variables.update_many(ctx, %{
              max_tokens: 8192,
              cost_per_1k: 0.015
            })
            
          "gpt-3.5-turbo" ->
            Variables.update_many(ctx, %{
              max_tokens: 2048,
              cost_per_1k: 0.002
            })
        end
      end)
      
      # Change model
      Variables.set(ctx, :model, "gpt-4")
      Process.sleep(50)
      
      # Related variables should update
      assert Variables.get(ctx, :max_tokens) == 4096
      assert Variables.get(ctx, :cost_per_1k) == 0.03
    end
  end
  
  @tag :integration
  @tag :python
  describe "cross-language reactive updates" do
    setup do
      {:ok, ctx} = Context.start_link()
      :ok = Context.ensure_bridged(ctx)
      context_id = Context.get_id(ctx)
      {:ok, ctx: ctx, context_id: context_id}
    end
    
    test "Python watches Elixir updates", %{ctx: ctx, context_id: context_id} do
      Variables.defvariable!(ctx, :shared_counter, :integer, 0)
      
      # Run Python watcher
      python_script = """
      import asyncio
      from snakepit_bridge import SessionContext
      
      updates = []
      
      async def watch_counter():
          async with SessionContext.connect('localhost:50051', '#{context_id}') as session:
              async for update in session.watch_variables(['shared_counter']):
                  updates.append(update.value)
                  if update.value >= 5:
                      break
                      
              return updates
      
      result = asyncio.run(watch_counter())
      print(json.dumps(result))
      """
      
      # Start Python watcher
      watcher = Task.async(fn ->
        run_python_script(python_script)
      end)
      
      # Update from Elixir
      Process.sleep(100)  # Let Python connect
      for i <- 1..5 do
        Variables.set(ctx, :shared_counter, i)
        Process.sleep(50)
      end
      
      # Get Python results
      {:ok, output} = Task.await(watcher, 5000)
      updates = Jason.decode!(output)
      
      assert updates == [0, 1, 2, 3, 4, 5]
    end
    
    test "Elixir watches Python updates", %{ctx: ctx, context_id: context_id} do
      Variables.defvariable!(ctx, :python_state, :string, "initial")
      
      # Set up Elixir watcher
      test_pid = self()
      {:ok, _ref} = Variables.watch(ctx, [:python_state],
        fn _, _, new, meta ->
          send(test_pid, {:from_python, new, meta[:source]})
        end,
        include_initial: false
      )
      
      # Python updater
      python_script = """
      import asyncio
      from snakepit_bridge import SessionContext
      
      async def update_state():
          async with SessionContext.connect('localhost:50051', '#{context_id}') as session:
              for state in ['connecting', 'processing', 'complete']:
                  await session.set_variable('python_state', state, 
                                           metadata={'source': 'python'})
                  await asyncio.sleep(0.1)
      
      asyncio.run(update_state())
      """
      
      # Run Python updates
      run_python_script(python_script)
      
      # Collect updates
      updates = for _ <- 1..3 do
        assert_receive {:from_python, state, source}, 3000
        {state, source}
      end
      
      assert updates == [
        {"connecting", "python"},
        {"processing", "python"},
        {"complete", "python"}
      ]
    end
    
    test "bidirectional reactive flow", %{ctx: ctx, context_id: context_id} do
      # Define interacting variables
      Variables.defvariable!(ctx, :temperature, :float, 20.0)
      Variables.defvariable!(ctx, :fan_speed, :integer, 0)
      
      # Elixir watches temperature and adjusts fan
      Variables.watch_one(ctx, :temperature, fn _, _, temp, _ ->
        fan = cond do
          temp < 20 -> 0
          temp < 25 -> 1
          temp < 30 -> 2
          true -> 3
        end
        Variables.set(ctx, :fan_speed, fan)
      end)
      
      # Python simulation that adjusts temperature based on fan
      python_script = """
      import asyncio
      from snakepit_bridge import SessionContext
      
      async def temperature_simulation():
          async with SessionContext.connect('localhost:50051', '#{context_id}') as session:
              current_temp = 20.0
              
              async for update in session.watch_variables(['fan_speed']):
                  if update.variable_name == 'fan_speed':
                      # Fan affects temperature
                      cooling = update.value * 2.0
                      current_temp = max(15.0, current_temp - cooling)
                      
                      await session.set_variable('temperature', current_temp)
                      
                      if current_temp <= 15.0:
                          break
              
              return current_temp
      
      final_temp = asyncio.run(temperature_simulation())
      print(final_temp)
      """
      
      # Start with high temperature
      Variables.set(ctx, :temperature, 35.0)
      
      # Run simulation
      {:ok, output} = run_python_script(python_script)
      final_temp = String.trim(output) |> String.to_float()
      
      # Should stabilize at minimum
      assert final_temp == 15.0
      assert Variables.get(ctx, :fan_speed) == 0
    end
  end
  
  describe "performance characteristics" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "LocalState watching performance", %{ctx: ctx} do
      Variables.defvariable!(ctx, :perf_var, :integer, 0)
      
      # Measure notification latency
      latencies = []
      test_pid = self()
      
      {:ok, ref} = Variables.watch(ctx, [:perf_var],
        fn _, _, new, _ ->
          receive_time = System.monotonic_time(:microsecond)
          send(test_pid, {:latency, new, receive_time})
        end
      )
      
      # Perform updates with timestamps
      for i <- 1..100 do
        send_time = System.monotonic_time(:microsecond)
        Variables.set(ctx, :perf_var, i)
        
        assert_receive {:latency, ^i, receive_time}, 100
        latency = receive_time - send_time
        latencies = [latency | latencies]
      end
      
      # Calculate statistics
      avg_latency = Enum.sum(latencies) / length(latencies)
      p99_latency = latencies |> Enum.sort() |> Enum.at(98)
      
      # LocalState should be sub-microsecond
      assert avg_latency < 1000  # < 1ms
      assert p99_latency < 5000  # < 5ms for 99th percentile
      
      IO.puts("LocalState latency - Avg: #{avg_latency}μs, P99: #{p99_latency}μs")
      
      Variables.unwatch(ctx, ref)
    end
    
    test "BridgedState streaming performance", %{ctx: ctx} do
      :ok = Context.ensure_bridged(ctx)
      Variables.defvariable!(ctx, :stream_perf, :integer, 0)
      
      latencies = []
      test_pid = self()
      
      {:ok, ref} = Variables.watch(ctx, [:stream_perf],
        fn _, _, new, _ ->
          receive_time = System.monotonic_time(:microsecond)
          send(test_pid, {:stream_latency, new, receive_time})
        end
      )
      
      # Measure streaming latency
      for i <- 1..50 do
        send_time = System.monotonic_time(:microsecond)
        Variables.set(ctx, :stream_perf, i)
        
        assert_receive {:stream_latency, ^i, receive_time}, 5000
        latency = receive_time - send_time
        latencies = [latency | latencies]
        
        Process.sleep(10)  # Avoid overwhelming
      end
      
      avg_latency = Enum.sum(latencies) / length(latencies)
      p99_latency = latencies |> Enum.sort() |> Enum.at(48)
      
      # BridgedState should be low milliseconds
      assert avg_latency < 5000  # < 5ms average
      assert p99_latency < 20000  # < 20ms for 99th percentile
      
      IO.puts("BridgedState latency - Avg: #{avg_latency}μs, P99: #{p99_latency}μs")
      
      Variables.unwatch(ctx, ref)
    end
    
    test "high-frequency update handling", %{ctx: ctx} do
      Variables.defvariable!(ctx, :rapid_fire, :integer, 0)
      
      received = :counters.new(1, [:atomics])
      test_pid = self()
      
      # Watch with debouncing
      {:ok, ref} = Variables.watch(ctx, [:rapid_fire],
        fn _, _, new, _ ->
          :counters.add(received, 1, 1)
          send(test_pid, {:debounced, new})
        end,
        filter: fn old, new -> new - old >= 10 end  # Only significant changes
      )
      
      # Rapid updates
      for i <- 1..1000 do
        Variables.set(ctx, :rapid_fire, i)
      end
      
      Process.sleep(100)
      
      # Should have filtered most updates
      count = :counters.get(received, 1)
      assert count < 200  # Much less than 1000
      
      Variables.unwatch(ctx, ref)
    end
  end
  
  # Helper functions
  
  defp ensure_required_services do
    # Start services if needed
    services = [
      {Snakepit.Bridge.ObserverManager, []},
      {Snakepit.Bridge.SessionStore, []}
    ]
    
    for {module, args} <- services do
      case Process.whereis(module) do
        nil -> 
          {:ok, _} = apply(module, :start_link, [args])
        _ -> 
          :ok
      end
    end
  end
  
  defp observer_count(var_name) do
    var_id = "var_#{var_name}_#{:erlang.phash2(var_name)}"
    ObserverManager.observer_count(var_id)
  end
  
  defp collect_updates(count, timeout) do
    collect_updates([], count, timeout)
  end
  
  defp collect_updates(acc, 0, _timeout), do: Enum.reverse(acc)
  defp collect_updates(acc, count, timeout) do
    receive do
      {:update, name, old, new, meta} ->
        collect_updates([{name, old, new, meta} | acc], count - 1, timeout)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
  
  defp collect_ordered_updates(count, timeout) do
    updates = for _ <- 1..count do
      receive do
        {:ordered_update, name, old, new, meta} ->
          {name, old, new, meta}
      after
        timeout -> nil
      end
    end
    
    Enum.reject(updates, &is_nil/1)
  end
  
  defp collect_all_updates(tag, count, timeout) do
    collect_all_updates([], tag, count, timeout)
  end
  
  defp collect_all_updates(acc, _tag, 0, _timeout), do: acc
  defp collect_all_updates(acc, tag, count, timeout) do
    receive do
      {^tag, _, _} = msg ->
        collect_all_updates([msg | acc], tag, count - 1, timeout)
    after
      timeout -> acc
    end
  end
  
  defp run_python_script(script) do
    Python.run_python_test(script)
  end
end
```

### Performance Benchmarks

```elixir
# File: bench/stage3_streaming_benchmarks.exs

defmodule DSPex.Stage3StreamingBenchmarks do
  @moduledoc """
  Performance benchmarks for Stage 3 streaming features.
  """
  
  use Benchfella
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.ObserverManager
  
  @variables_count 100
  @watchers_count 10
  
  setup_all do
    # Start services
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Create contexts
    {:ok, local_ctx} = Context.start_link()
    {:ok, bridged_ctx} = Context.start_link()
    Context.ensure_bridged(bridged_ctx)
    
    # Populate variables
    for i <- 1..@variables_count do
      Variables.defvariable!(local_ctx, :"bench_var_#{i}", :integer, i)
      Variables.defvariable!(bridged_ctx, :"bench_var_#{i}", :integer, i)
    end
    
    {:ok, %{local: local_ctx, bridged: bridged_ctx}}
  end
  
  bench "LocalState watch setup", [contexts: bench_context] do
    {:ok, ref} = Variables.watch(
      contexts.local, 
      [:bench_var_1], 
      fn _, _, _, _ -> :ok end
    )
    Variables.unwatch(contexts.local, ref)
  end
  
  bench "BridgedState watch setup", [contexts: bench_context] do
    {:ok, ref} = Variables.watch(
      contexts.bridged,
      [:bench_var_1],
      fn _, _, _, _ -> :ok end
    )
    Variables.unwatch(contexts.bridged, ref)
  end
  
  bench "LocalState notification dispatch", [contexts: bench_context] do
    # Pre-setup watcher
    {:ok, ref} = Variables.watch(
      contexts.local,
      [:bench_var_50],
      fn _, _, _, _ -> :ok end
    )
    
    # Measure update
    Variables.set(contexts.local, :bench_var_50, :rand.uniform(1000))
    
    Variables.unwatch(contexts.local, ref)
  end
  
  bench "BridgedState notification dispatch", [contexts: bench_context] do
    # Pre-setup watcher
    {:ok, ref} = Variables.watch(
      contexts.bridged,
      [:bench_var_50],
      fn _, _, _, _ -> :ok end
    )
    
    # Measure update
    Variables.set(contexts.bridged, :bench_var_50, :rand.uniform(1000))
    
    Variables.unwatch(contexts.bridged, ref)
  end
  
  bench "ObserverManager with 100 observers" do
    var_id = "bench_var_#{:rand.uniform(1000)}"
    
    # Add observers
    refs = for _ <- 1..100 do
      ObserverManager.add_observer(var_id, self(), fn _, _, _, _ -> :ok end)
    end
    
    # Trigger notification
    ObserverManager.notify_observers(var_id, 1, 2, %{})
    
    # Cleanup
    for ref <- refs do
      ObserverManager.remove_observer(var_id, ref)
    end
  end
  
  bench "Choice type validation" do
    constraints = %{choices: ["option1", "option2", "option3", "option4"]}
    
    DSPex.Bridge.Variables.Types.Choice.validate_constraints(
      "option#{:rand.uniform(4)}",
      constraints
    )
  end
  
  bench "Module type validation" do
    constraints = %{namespace: "MyApp.Modules"}
    
    DSPex.Bridge.Variables.Types.Module.validate_constraints(
      "MyApp.Modules.Handler#{:rand.uniform(100)}",
      constraints
    )
  end
end
```

### Property-Based Tests

```elixir
# File: test/dspex/stage3_property_test.exs

defmodule DSPex.Stage3PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  alias DSPex.{Context, Variables}
  
  property "watchers always receive updates in order" do
    check all var_name <- atom(:alphanumeric),
              values <- list_of(integer(), min_length: 2, max_length: 20),
              max_runs: 20 do
      
      {:ok, ctx} = Context.start_link()
      Variables.defvariable!(ctx, var_name, :integer, 0)
      
      received = []
      test_pid = self()
      
      {:ok, ref} = Variables.watch(ctx, [var_name],
        fn _, _, new, _ ->
          send(test_pid, {:received, new})
        end
      )
      
      # Send all updates
      for value <- values do
        Variables.set(ctx, var_name, value)
      end
      
      # Collect all updates
      Process.sleep(50)
      received = collect_all_values(length(values))
      
      # Updates should arrive in order
      assert received == values
      
      Variables.unwatch(ctx, ref)
      Context.stop(ctx)
    end
  end
  
  property "filtered updates respect filter function" do
    check all threshold <- integer(1..100),
              values <- list_of(integer(0..200), min_length: 10),
              max_runs: 20 do
      
      {:ok, ctx} = Context.start_link()
      Variables.defvariable!(ctx, :filtered, :integer, 0)
      
      received = []
      test_pid = self()
      
      # Only values above threshold
      filter = fn _old, new -> new > threshold end
      
      {:ok, ref} = Variables.watch(ctx, [:filtered],
        fn _, _, new, _ ->
          send(test_pid, {:filtered, new})
        end,
        filter: filter,
        include_initial: false
      )
      
      # Send updates
      for value <- values do
        Variables.set(ctx, :filtered, value)
      end
      
      # Collect filtered
      Process.sleep(50)
      received = collect_all_filtered(length(values))
      
      # All received should be above threshold
      assert Enum.all?(received, & &1 > threshold)
      
      # Should match manual filter
      expected = Enum.filter(values, & &1 > threshold)
      assert length(received) == length(expected)
      
      Variables.unwatch(ctx, ref)
      Context.stop(ctx)
    end
  end
  
  property "choice constraints are enforced" do
    check all choices <- list_of(string(:alphanumeric), min_length: 2, max_length: 5),
              valid <- member_of(choices),
              invalid <- string(:alphanumeric),
              invalid not in choices,
              max_runs: 50 do
      
      {:ok, ctx} = Context.start_link()
      
      Variables.defvariable!(ctx, :choice_prop, :choice, hd(choices),
        constraints: %{choices: choices}
      )
      
      # Valid choice works
      assert :ok = Variables.set(ctx, :choice_prop, valid)
      assert Variables.get(ctx, :choice_prop) == valid
      
      # Invalid choice fails
      assert {:error, _} = Variables.set(ctx, :choice_prop, invalid)
      assert Variables.get(ctx, :choice_prop) == valid  # Unchanged
      
      Context.stop(ctx)
    end
  end
  
  defp collect_all_values(max) do
    collect_all_values([], max)
  end
  
  defp collect_all_values(acc, 0), do: Enum.reverse(acc)
  defp collect_all_values(acc, remaining) do
    receive do
      {:received, value} ->
        collect_all_values([value | acc], remaining - 1)
    after
      100 -> Enum.reverse(acc)
    end
  end
  
  defp collect_all_filtered(max) do
    collect_all_filtered([], max)
  end
  
  defp collect_all_filtered(acc, 0), do: Enum.reverse(acc)
  defp collect_all_filtered(acc, remaining) do
    receive do
      {:filtered, value} ->
        collect_all_filtered([value | acc], remaining - 1)
    after
      100 -> Enum.reverse(acc)
    end
  end
end
```

## Test Organization

### Test Suites

1. **Unit Tests**
   - Individual component testing
   - Type validation
   - Observer management

2. **Integration Tests**
   - Cross-backend watching
   - Python interop
   - End-to-end scenarios

3. **Performance Tests**
   - Latency measurements
   - Throughput benchmarks
   - Scalability tests

4. **Property Tests**
   - Invariant verification
   - Constraint enforcement
   - Ordering guarantees

## Success Metrics

### Functional
- All tests pass consistently
- No race conditions in watching
- Proper cleanup of resources
- Cross-language updates work

### Performance
- LocalState: < 1μs notification latency
- BridgedState: < 5ms notification latency
- Support 1000+ concurrent watchers
- Handle 10k+ updates/second

### Reliability
- Automatic reconnection works
- No memory leaks
- Graceful degradation
- Clear error messages

## Next Steps
After Stage 3 testing:
1. Create reactive programming guide
2. Build example applications
3. Document performance tuning
4. Prepare for Stage 4 production hardening
5. Create monitoring dashboards