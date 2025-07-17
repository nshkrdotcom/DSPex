#!/usr/bin/env elixir

# Simple V3 Pool Test with Streamlined Setup
# Run with: elixir examples/pool_v3_simple_test.exs

# Configure pooling BEFORE loading DSPex
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 2
})

Mix.install([{:dspex, path: "."}])

# Configure logging and test mode
Logger.configure(level: :info)
System.put_env("TEST_MODE", "mock_adapter")

# Start the application (handles all pool setup automatically)
{:ok, _} = Application.ensure_all_started(:dspex)

# Wait for pool initialization
Process.sleep(2000)

# Check pool stats
IO.puts("\nPool stats:")
IO.inspect(DSPex.Python.Pool.get_stats())

# Try direct worker execute
workers = DSPex.Python.Registry.list_workers()
IO.puts("\nWorkers: #{inspect(workers)}")

if length(workers) > 0 do
  worker_id = hd(workers)
  IO.puts("\nTrying direct worker execute on #{worker_id}...")
  
  case DSPex.Python.Worker.execute(worker_id, "ping", %{test: true}) do
    {:ok, result} -> 
      IO.puts("Success! #{inspect(result)}")
    {:error, reason} ->
      IO.puts("Error: #{inspect(reason)}")
  end
end

# Try pool execute
IO.puts("\nTrying pool execute...")
case DSPex.Python.Pool.execute("ping", %{test: true}) do
  {:ok, result} -> 
    IO.puts("Success! #{inspect(result)}")
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Ensure proper cleanup by explicitly stopping the application
IO.puts("\n🛑 Stopping DSPex application to ensure cleanup...")
Application.stop(:dspex)
IO.puts("✅ Test complete - application stopped cleanly!")