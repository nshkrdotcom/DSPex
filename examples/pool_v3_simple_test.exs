#!/usr/bin/env elixir

# Simple test to debug V3 pool
Mix.install([{:dspex, path: "."}])

# Start components
{:ok, _} = Supervisor.start_link([DSPex.Python.Registry], strategy: :one_for_one)
{:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
{:ok, _} = DSPex.Python.Pool.start_link(size: 2)

# Wait for initialization
Process.sleep(5000)

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