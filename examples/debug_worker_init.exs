#!/usr/bin/env elixir

# Debug worker initialization issues
# Run with: elixir examples/debug_worker_init.exs

Mix.install([
  {:dspex, path: "."}
])

Logger.configure(level: :debug)
System.put_env("TEST_MODE", "mock_adapter")

defmodule WorkerInitDebug do
  require Logger

  def run do
    IO.puts("\n🐛 Debug Worker Initialization")
    IO.puts("=" |> String.duplicate(40))
    
    # Configure for V3 pool
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: 1
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Start only essential dependencies
    {:ok, _} = Application.ensure_all_started(:logger)
    {:ok, _} = Application.ensure_all_started(:jason)
    
    debug_single_worker()
  end
  
  defp debug_single_worker do
    IO.puts("\n🔍 Testing single worker initialization...")
    
    # Start required components
    {:ok, _} = Registry.start_link(keys: :unique, name: DSPex.Python.Registry)
    {:ok, _} = DSPex.Python.ProcessRegistry.start_link()
    {:ok, _} = DSPex.Python.ApplicationCleanup.start_link()
    
    IO.puts("✅ Components started")
    
    # Try to start a single worker
    IO.puts("🚀 Starting single worker...")
    
    case DSPex.Python.Worker.start_link(id: "debug_worker_1") do
      {:ok, worker_pid} ->
        IO.puts("✅ Worker started: #{inspect(worker_pid)}")
        
        # Wait and see what happens
        Process.sleep(25000)  # Wait longer than init timeout
        
        if Process.alive?(worker_pid) do
          IO.puts("✅ Worker is still alive after 25 seconds")
          
          # Try to get stats
          try do
            stats = DSPex.Python.Worker.get_stats("debug_worker_1")
            IO.puts("📊 Worker stats: #{inspect(stats)}")
          rescue
            e -> IO.puts("❌ Failed to get stats: #{inspect(e)}")
          end
          
          # Try to execute a command
          try do
            result = DSPex.Python.Worker.execute("debug_worker_1", "ping", %{test: true}, 5000)
            IO.puts("📤 Ping result: #{inspect(result)}")
          rescue
            e -> IO.puts("❌ Failed to ping: #{inspect(e)}")
          end
        else
          IO.puts("💀 Worker died during initialization")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to start worker: #{inspect(reason)}")
    end
    
    # Check for any orphaned Python processes
    IO.puts("\n🔍 Checking for Python processes...")
    case System.cmd("pgrep", ["-f", "dspy_bridge.py"], stderr_to_stdout: true) do
      {output, 0} ->
        pids = output |> String.split("\n", trim: true)
        IO.puts("🐍 Found #{length(pids)} Python processes: #{inspect(pids)}")
      {_output, _} ->
        IO.puts("🐍 No Python processes found")
    end
  end
end

# Run the debug
WorkerInitDebug.run()