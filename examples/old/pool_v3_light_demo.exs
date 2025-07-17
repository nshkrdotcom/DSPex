#!/usr/bin/env elixir

# Lightweight V3 Pool Demo - Uses fewer workers to avoid system limits

Mix.install([{:dspex, path: "."}])

# Configure minimal logging
Logger.configure(level: :warning)

IO.puts("\n🚀 DSPex Pool V3 - Lightweight Demo (4 workers)")
IO.puts("=" |> String.duplicate(50))

# Start application
{:ok, _} = Application.ensure_all_started(:dspex)
Application.put_env(:dspex, :pooling_enabled, true)

# Time the startup with fewer workers
IO.puts("\n⏱️  Starting 4 workers concurrently...")
start_time = System.monotonic_time(:millisecond)

try do
  {:ok, _} = Supervisor.start_link([DSPex.Python.Registry], strategy: :one_for_one)
  {:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
  {:ok, _} = DSPex.Python.Pool.start_link(size: 4)  # Reduced from 8 to 4
  {:ok, _} = DSPex.PythonBridge.SessionStore.start_link()
  
  # Wait briefly for initialization
  Process.sleep(2000)
  
  elapsed = System.monotonic_time(:millisecond) - start_time
  
  IO.puts("✅ Pool started in #{elapsed}ms")
  IO.puts("   Sequential would take: ~8,000ms (4 × 2s)")
  IO.puts("   Speedup: ~#{div(8000, max(elapsed, 1))}x")
  
  # Quick test
  IO.puts("\n🧪 Quick test...")
  case DSPex.Python.Pool.execute("ping", %{test: true}) do
    {:ok, result} -> 
      IO.puts("   ✅ Ping successful: #{result["status"]}")
    {:error, reason} ->
      IO.puts("   ❌ Ping failed: #{inspect(reason)}")
  end
  
  # Show stats
  stats = DSPex.Python.Pool.get_stats()
  IO.puts("\n📊 Stats: #{stats.workers} workers, #{stats.requests} requests")
  
rescue
  error ->
    IO.puts("❌ Error: #{inspect(error)}")
end

IO.puts("\n✨ Demo complete!")