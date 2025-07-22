# Run with: mix run bench/state_comparison_bench.exs

defmodule StateComparisonBench do
  alias DSPex.Bridge.State.{Local, Bridged}
  alias Snakepit.Bridge.SessionStore
  
  def run do
    IO.puts "\n=== State Backend Performance Comparison ===\n"
    
    # Ensure SessionStore is running for BridgedState
    ensure_session_store()
    
    # Setup both backends
    {:ok, local_state} = Local.init(session_id: "bench_local")
    {:ok, bridged_state} = Bridged.init(session_id: "bench_bridged")
    
    # Pre-populate with variables
    IO.puts "Setting up test data..."
    {local_state, bridged_state} = setup_test_data(local_state, bridged_state)
    
    # Run comparisons
    IO.puts "\n--- Single Variable Operations ---\n"
    compare_get_variable(local_state, bridged_state)
    compare_set_variable(local_state, bridged_state)
    
    IO.puts "\n--- Batch Operations ---\n"
    compare_batch_get(local_state, bridged_state, 10)
    compare_batch_get(local_state, bridged_state, 50)
    compare_batch_update(local_state, bridged_state, 10)
    
    IO.puts "\n--- Complex Operations ---\n"
    compare_list_variables(local_state, bridged_state)
    compare_state_export(local_state, bridged_state)
    
    # Cleanup
    Local.cleanup(local_state)
    Bridged.cleanup(bridged_state)
    
    IO.puts "\n=== Comparison Complete ===\n"
  end
  
  defp ensure_session_store do
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> 
        IO.puts "Failed to start SessionStore: #{inspect(error)}"
        System.halt(1)
    end
  end
  
  defp setup_test_data(local_state, bridged_state) do
    # Add 100 variables to each
    {local_state, bridged_state} = Enum.reduce(1..100, {local_state, bridged_state}, 
      fn i, {local, bridged} ->
        {:ok, {_, new_local}} = Local.register_variable(
          local, :"var_#{i}", :integer, i, []
        )
        {:ok, {_, new_bridged}} = Bridged.register_variable(
          bridged, :"var_#{i}", :integer, i, []
        )
        {new_local, new_bridged}
      end)
    
    {local_state, bridged_state}
  end
  
  defp compare_get_variable(local_state, bridged_state) do
    IO.puts "Get Variable (single):"
    
    # LocalState
    local_times = measure_operation(1000, fn ->
      Local.get_variable(local_state, :var_50)
    end)
    
    # BridgedState
    bridged_times = measure_operation(1000, fn ->
      Bridged.get_variable(bridged_state, :var_50)
    end)
    
    print_comparison("get_variable", local_times, bridged_times)
  end
  
  defp compare_set_variable(local_state, bridged_state) do
    IO.puts "\nSet Variable (single):"
    
    # LocalState
    local_times = measure_operation(1000, fn ->
      Local.set_variable(local_state, :var_50, :rand.uniform(1000), %{})
    end)
    
    # BridgedState
    bridged_times = measure_operation(1000, fn ->
      Bridged.set_variable(bridged_state, :var_50, :rand.uniform(1000), %{})
    end)
    
    print_comparison("set_variable", local_times, bridged_times)
  end
  
  defp compare_batch_get(local_state, bridged_state, count) do
    IO.puts "\nBatch Get (#{count} variables):"
    
    identifiers = Enum.map(1..count, &:"var_#{&1}")
    
    # LocalState
    local_times = measure_operation(100, fn ->
      Local.get_variables(local_state, identifiers)
    end)
    
    # BridgedState
    bridged_times = measure_operation(100, fn ->
      Bridged.get_variables(bridged_state, identifiers)
    end)
    
    print_comparison("get_variables(#{count})", local_times, bridged_times)
  end
  
  defp compare_batch_update(local_state, bridged_state, count) do
    IO.puts "\nBatch Update (#{count} variables):"
    
    updates = Map.new(1..count, fn i -> {:"var_#{i}", :rand.uniform(1000)} end)
    
    # LocalState
    local_times = measure_operation(100, fn ->
      Local.update_variables(local_state, updates, %{})
    end)
    
    # BridgedState
    bridged_times = measure_operation(100, fn ->
      Bridged.update_variables(bridged_state, updates, %{})
    end)
    
    print_comparison("update_variables(#{count})", local_times, bridged_times)
  end
  
  defp compare_list_variables(local_state, bridged_state) do
    IO.puts "\nList Variables (100 total):"
    
    # LocalState
    local_times = measure_operation(100, fn ->
      Local.list_variables(local_state)
    end)
    
    # BridgedState
    bridged_times = measure_operation(100, fn ->
      Bridged.list_variables(bridged_state)
    end)
    
    print_comparison("list_variables", local_times, bridged_times)
  end
  
  defp compare_state_export(local_state, bridged_state) do
    IO.puts "\nExport State:"
    
    # LocalState
    local_times = measure_operation(100, fn ->
      Local.export_state(local_state)
    end)
    
    # BridgedState
    bridged_times = measure_operation(100, fn ->
      Bridged.export_state(bridged_state)
    end)
    
    print_comparison("export_state", local_times, bridged_times)
  end
  
  defp measure_operation(iterations, fun) do
    for _ <- 1..iterations do
      {time, _} = :timer.tc(fun)
      time
    end
  end
  
  defp print_comparison(operation, local_times, bridged_times) do
    local_stats = calculate_stats(local_times)
    bridged_stats = calculate_stats(bridged_times)
    
    speedup = bridged_stats.avg / local_stats.avg
    
    IO.puts """
      LocalState:
        Avg: #{format_time(local_stats.avg)}
        P50: #{format_time(local_stats.p50)}
        P95: #{format_time(local_stats.p95)}
        P99: #{format_time(local_stats.p99)}
      
      BridgedState:
        Avg: #{format_time(bridged_stats.avg)}
        P50: #{format_time(bridged_stats.p50)}
        P95: #{format_time(bridged_stats.p95)}
        P99: #{format_time(bridged_stats.p99)}
      
      Speedup: #{Float.round(speedup, 2)}x slower
    """
  end
  
  defp calculate_stats(times) do
    sorted = Enum.sort(times)
    count = length(times)
    
    %{
      avg: Enum.sum(times) / count,
      p50: Enum.at(sorted, div(count, 2)),
      p95: Enum.at(sorted, round(count * 0.95)),
      p99: Enum.at(sorted, round(count * 0.99))
    }
  end
  
  defp format_time(microseconds) when microseconds < 1000 do
    "#{Float.round(microseconds, 2)} μs"
  end
  
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1000, 2)} ms"
  end
end

# Run the comparison
StateComparisonBench.run()