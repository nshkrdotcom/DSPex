defmodule DSPex.Python.DemoRunner do
  @moduledoc """
  Convenience module for running V3 pool demos with proper cleanup.
  
  This module ensures that all Python processes are properly terminated
  when the demo exits, preventing orphaned process accumulation.
  """
  
  require Logger
  
  @doc """
  Starts a V3 pool system with proper cleanup guarantees.
  
  Unlike manual setup, this function ensures that when the calling
  process exits, all Python workers are properly terminated.
  
  ## Options
  
  - `:size` - Number of workers (default: 8)
  - `:cleanup_timeout` - Time to wait for graceful shutdown (default: 5000ms)
  
  ## Example
  
      DSPex.Python.DemoRunner.with_pool([size: 4], fn ->
        {:ok, response} = DSPex.Python.Pool.execute("ping", %{test: true})
        IO.puts("Ping successful!")
        response
      end)
  """
  def with_pool(opts \\ [], fun) when is_function(fun, 0) do
    size = Keyword.get(opts, :size, 8)
    _cleanup_timeout = Keyword.get(opts, :cleanup_timeout, 5000)
    
    # Check if pool is already running (from application supervisor)
    case Process.whereis(DSPex.Python.Pool) do
      nil ->
        # No pool running, start one with global cleanup
        Logger.info("🚀 Starting V3 Pool with global cleanup (size: #{size})")
        
        case DSPex.Python.GlobalPoolManager.start_global_pool(size: size) do
          {:ok, pool_pid, cleanup_report} ->
            Logger.info("✅ Global cleanup report: #{inspect(cleanup_report)}")
            
            # Link to ensure cleanup happens when demo exits
            Process.link(pool_pid)
            
            run_demo_function(fun)
            
          {:error, reason} ->
            Logger.error("❌ Failed to start global pool: #{inspect(reason)}")
            {:error, reason}
        end
        
      pool_pid when is_pid(pool_pid) ->
        # Pool already running (from application supervisor)
        Logger.info("✅ Using existing V3 pool: #{inspect(pool_pid)}")
        
        # Link to ensure we notice if pool dies
        Process.link(pool_pid)
        
        run_demo_function(fun)
    end
  end
  
  defp run_demo_function(fun) do
    try do
      # Run the user's function
      result = fun.()
      Logger.info("✅ Demo completed successfully")
      result
    catch
      kind, error ->
        Logger.error("❌ Demo failed: #{inspect({kind, error})}")
        reraise error, __STACKTRACE__
    after
      # Cleanup is handled automatically by application supervisor or GlobalPoolManager
      Logger.info("🧹 Demo finished - automatic cleanup will handle Python processes")
    end
  end
  
  @doc """
  Runs the detailed demo with proper cleanup.
  """
  def run_detailed_demo(opts \\ []) do
    with_pool(opts, fn ->
      demo_detailed_operations()
      demo_concurrent_execution() 
      show_pool_stats()
    end)
  end
  
  # Private Functions
  
  # Demo functions (simplified versions)
  
  defp demo_detailed_operations do
    IO.puts("\\n🔍 Running detailed operations...")
    
    # Simple ping test
    case DSPex.Python.Pool.execute("ping", %{test: true}) do
      {:ok, result} -> 
        IO.puts("✅ Ping successful: #{result["status"]}")
      {:error, reason} ->
        IO.puts("❌ Ping failed: #{inspect(reason)}")
    end
  end
  
  defp demo_concurrent_execution do
    IO.puts("\\n⚡ Running concurrent execution test...")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Run 10 concurrent requests
    tasks = for i <- 1..10 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("ping", %{id: i, test: "concurrent"})
      end)
    end
    
    results = Task.await_many(tasks, 30_000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("✅ Completed #{success_count}/10 requests in #{elapsed}ms")
  end
  
  defp show_pool_stats do
    IO.puts("\\n📊 Pool Statistics:")
    stats = DSPex.Python.Pool.get_stats()
    
    IO.puts("   Workers: #{stats.workers}")
    IO.puts("   Available: #{stats.available}") 
    IO.puts("   Busy: #{stats.busy}")
    IO.puts("   Total Requests: #{stats.requests}")
    IO.puts("   Errors: #{stats.errors}")
  end
end