# Run with: mix run bench/local_state_bench.exs

defmodule LocalStateBench do
  alias DSPex.Bridge.State.Local
  
  def run do
    IO.puts "\n=== LocalState Performance Benchmark ===\n"
    
    # Setup
    {:ok, state} = Local.init(session_id: "bench")
    
    # Pre-populate with variables
    state = Enum.reduce(1..100, state, fn i, acc ->
      {:ok, {_, new_state}} = Local.register_variable(
        acc, :"bench_var_#{i}", :integer, i, []
      )
      new_state
    end)
    
    # Benchmark different operations
    benchmark_get(state)
    benchmark_set(state)
    benchmark_batch_get(state)
    benchmark_register(state)
    benchmark_list(state)
    
    # Cleanup
    Local.cleanup(state)
    
    IO.puts "\n=== Benchmark Complete ===\n"
  end
  
  defp benchmark_get(state) do
    IO.puts "Get Variable Performance:"
    
    times = for _ <- 1..10_000 do
      {time, _} = :timer.tc(fn ->
        Local.get_variable(state, :bench_var_50)
      end)
      time
    end
    
    print_stats("get_variable", times)
  end
  
  defp benchmark_set(state) do
    IO.puts "\nSet Variable Performance:"
    
    times = for i <- 1..10_000 do
      {time, _} = :timer.tc(fn ->
        Local.set_variable(state, :bench_var_50, i, %{})
      end)
      time
    end
    
    print_stats("set_variable", times)
  end
  
  defp benchmark_batch_get(state) do
    IO.puts "\nBatch Get Performance (10 variables):"
    
    identifiers = Enum.map(1..10, &:"bench_var_#{&1}")
    
    times = for _ <- 1..1_000 do
      {time, _} = :timer.tc(fn ->
        Local.get_variables(state, identifiers)
      end)
      time
    end
    
    print_stats("get_variables(10)", times)
    
    IO.puts "\nBatch Get Performance (50 variables):"
    
    identifiers_50 = Enum.map(1..50, &:"bench_var_#{&1}")
    
    times_50 = for _ <- 1..1_000 do
      {time, _} = :timer.tc(fn ->
        Local.get_variables(state, identifiers_50)
      end)
      time
    end
    
    print_stats("get_variables(50)", times_50)
  end
  
  defp benchmark_register(state) do
    IO.puts "\nRegister Variable Performance:"
    
    times = for i <- 1..1_000 do
      {time, _} = :timer.tc(fn ->
        Local.register_variable(state, :"new_var_#{i}", :string, "test", [])
      end)
      time
    end
    
    print_stats("register_variable", times)
  end
  
  defp benchmark_list(state) do
    IO.puts "\nList Variables Performance (100 variables):"
    
    times = for _ <- 1..1_000 do
      {time, _} = :timer.tc(fn ->
        Local.list_variables(state)
      end)
      time
    end
    
    print_stats("list_variables", times)
  end
  
  defp print_stats(operation, times) do
    sorted = Enum.sort(times)
    count = length(times)
    
    min = hd(sorted)
    max = List.last(sorted)
    avg = Enum.sum(times) / count
    median = Enum.at(sorted, div(count, 2))
    p95 = Enum.at(sorted, round(count * 0.95))
    p99 = Enum.at(sorted, round(count * 0.99))
    
    IO.puts """
      #{operation}:
        Min:    #{format_time(min)}
        Median: #{format_time(median)}
        Avg:    #{format_time(avg)}
        P95:    #{format_time(p95)}
        P99:    #{format_time(p99)}
        Max:    #{format_time(max)}
    """
  end
  
  defp format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)} μs"
  end
  
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end
end

# Run the benchmark
LocalStateBench.run()