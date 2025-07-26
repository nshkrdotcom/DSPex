defmodule Performance.CriticalPathTest do
  use ExUnit.Case
  @moduletag :performance
  @moduletag timeout: 300_000 # 5 minutes

  describe "critical path performance" do
    setup_all do
      {:ok, _} = Application.ensure_all_started(:snakepit)
      {:ok, _} = Application.ensure_all_started(:snakepit_grpc_bridge)
      {:ok, _} = Application.ensure_all_started(:dspex)
      
      Process.sleep(100) # Let services stabilize
      :ok
    end

    test "DSPy prediction latency under load" do
      alias DSPex.Modules.Predict
      alias DSPex.Native.Signature
      
      predictor = Predict.new(Signature.new("q -> a"))
      
      # Warmup
      for _ <- 1..10 do
        Predict.forward(predictor, %{q: "warmup"})
      end
      
      # Measure latencies
      latencies = for i <- 1..100 do
        start = System.monotonic_time(:microsecond)
        {:ok, _} = Predict.forward(predictor, %{q: "Question #{i}?"})
        System.monotonic_time(:microsecond) - start
      end
      
      # Calculate statistics
      avg_latency = Enum.sum(latencies) / length(latencies) / 1000 # Convert to ms
      p95_latency = percentile(latencies, 0.95) / 1000
      p99_latency = percentile(latencies, 0.99) / 1000
      max_latency = Enum.max(latencies) / 1000
      
      IO.puts("\nPrediction Latency Stats:")
      IO.puts("  Average: #{Float.round(avg_latency, 2)}ms")
      IO.puts("  P95: #{Float.round(p95_latency, 2)}ms")
      IO.puts("  P99: #{Float.round(p99_latency, 2)}ms")
      IO.puts("  Max: #{Float.round(max_latency, 2)}ms")
      
      # Performance assertions
      assert avg_latency < 100, "Average latency #{avg_latency}ms exceeds 100ms"
      assert p95_latency < 200, "P95 latency #{p95_latency}ms exceeds 200ms"
      assert p99_latency < 500, "P99 latency #{p99_latency}ms exceeds 500ms"
    end

    test "throughput under sustained load" do
      alias DSPex.Modules.Predict
      alias DSPex.Native.Signature
      
      predictor = Predict.new(Signature.new("q -> a"))
      duration_seconds = 30
      
      start_time = System.monotonic_time(:second)
      end_time = start_time + duration_seconds
      
      {count, errors} = execute_until(predictor, end_time, 0, 0)
      
      actual_duration = System.monotonic_time(:second) - start_time
      throughput = count / actual_duration
      error_rate = errors / count * 100
      
      IO.puts("\nThroughput Test Results:")
      IO.puts("  Duration: #{actual_duration}s")
      IO.puts("  Total operations: #{count}")
      IO.puts("  Throughput: #{Float.round(throughput, 2)} ops/sec")
      IO.puts("  Error rate: #{Float.round(error_rate, 2)}%")
      
      # Performance assertions
      assert throughput > 10, "Throughput #{throughput} ops/sec below minimum 10"
      assert error_rate < 1.0, "Error rate #{error_rate}% exceeds 1%"
    end

    test "memory stability under load" do
      initial_memory = :erlang.memory(:total)
      
      alias DSPex.Modules.Predict
      alias DSPex.Native.Signature
      
      # Create many sessions with data
      sessions = for i <- 1..100 do
        session_id = "mem_test_#{i}"
        SnakepitGrpcBridge.initialize_session(session_id)
        
        # Store some data
        for j <- 1..10 do
          SnakepitGrpcBridge.Variables.set(session_id, "var_#{j}", 
            String.duplicate("data", 100))
        end
        
        session_id
      end
      
      # Execute operations
      predictor = Predict.new(Signature.new("q -> a"))
      
      for session_id <- sessions do
        Predict.forward(predictor, %{q: "test"}, session_id: session_id)
      end
      
      # Measure memory before cleanup
      peak_memory = :erlang.memory(:total)
      memory_increase_mb = (peak_memory - initial_memory) / 1024 / 1024
      
      IO.puts("\nMemory before cleanup: +#{Float.round(memory_increase_mb, 2)}MB")
      
      # Cleanup sessions
      for session_id <- sessions do
        SnakepitGrpcBridge.cleanup_session(session_id)
      end
      
      # Force GC and measure final memory
      :erlang.garbage_collect()
      Process.sleep(100)
      :erlang.garbage_collect()
      
      final_memory = :erlang.memory(:total)
      final_increase_mb = (final_memory - initial_memory) / 1024 / 1024
      
      IO.puts("Memory after cleanup: +#{Float.round(final_increase_mb, 2)}MB")
      
      # Memory assertions
      assert memory_increase_mb < 200, "Peak memory increase #{memory_increase_mb}MB exceeds 200MB"
      assert final_increase_mb < 50, "Memory not properly released: #{final_increase_mb}MB still allocated"
    end

    test "concurrent session handling" do
      session_count = 50
      ops_per_session = 20
      
      alias DSPex.Modules.Predict
      alias DSPex.Native.Signature
      
      predictor = Predict.new(Signature.new("q -> a"))
      
      start_time = System.monotonic_time(:millisecond)
      
      # Launch concurrent sessions
      tasks = for i <- 1..session_count do
        Task.async(fn ->
          session_id = "concurrent_#{i}"
          SnakepitGrpcBridge.initialize_session(session_id)
          
          results = for j <- 1..ops_per_session do
            case rem(j, 3) do
              0 -> 
                SnakepitGrpcBridge.Variables.set(session_id, "counter", j)
                :set
              1 ->
                SnakepitGrpcBridge.Variables.get(session_id, "counter", 0)
                :get
              2 ->
                Predict.forward(predictor, %{q: "Q#{j}"}, session_id: session_id)
                :predict
            end
          end
          
          SnakepitGrpcBridge.cleanup_session(session_id)
          
          results
        end)
      end
      
      # Wait for all tasks
      results = Task.await_many(tasks, 60_000)
      
      duration_ms = System.monotonic_time(:millisecond) - start_time
      total_ops = session_count * ops_per_session
      ops_per_second = total_ops / (duration_ms / 1000)
      
      IO.puts("\nConcurrent Session Test:")
      IO.puts("  Sessions: #{session_count}")
      IO.puts("  Operations per session: #{ops_per_session}")
      IO.puts("  Total operations: #{total_ops}")
      IO.puts("  Duration: #{duration_ms}ms")
      IO.puts("  Throughput: #{Float.round(ops_per_second, 2)} ops/sec")
      
      # All tasks should complete successfully
      assert length(results) == session_count
      assert Enum.all?(results, fn result -> length(result) == ops_per_session end)
      
      # Performance assertions
      assert duration_ms < 30_000, "Test took too long: #{duration_ms}ms"
      assert ops_per_second > 50, "Throughput too low: #{ops_per_second} ops/sec"
    end

    test "schema caching effectiveness" do
      # First discovery (uncached)
      {time1, {:ok, schema1}} = :timer.tc(fn ->
        SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
      end)
      
      # Subsequent discoveries (should be cached)
      times = for _ <- 1..10 do
        {time, {:ok, _}} = :timer.tc(fn ->
          SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
        end)
        time
      end
      
      uncached_ms = time1 / 1000
      cached_avg_ms = Enum.sum(times) / length(times) / 1000
      speedup = uncached_ms / cached_avg_ms
      
      IO.puts("\nSchema Caching Performance:")
      IO.puts("  Uncached: #{Float.round(uncached_ms, 2)}ms")
      IO.puts("  Cached average: #{Float.round(cached_avg_ms, 2)}ms")
      IO.puts("  Speedup: #{Float.round(speedup, 2)}x")
      
      # Caching assertions
      assert cached_avg_ms < 10, "Cached access too slow: #{cached_avg_ms}ms"
      assert speedup > 10, "Caching speedup too low: #{speedup}x"
    end
  end

  # Helper functions
  
  defp percentile(list, p) do
    sorted = Enum.sort(list)
    k = round(p * length(sorted))
    Enum.at(sorted, k - 1)
  end

  defp execute_until(predictor, end_time, count, errors) do
    if System.monotonic_time(:second) < end_time do
      case DSPex.Modules.Predict.forward(predictor, %{q: "Q#{count}"}) do
        {:ok, _} -> execute_until(predictor, end_time, count + 1, errors)
        {:error, _} -> execute_until(predictor, end_time, count + 1, errors + 1)
      end
    else
      {count, errors}
    end
  end
end