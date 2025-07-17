#!/usr/bin/env elixir

# DSPex V3 Pool Demo with Built-in Cleanup
# Run with: elixir examples/pool_v3_clean_demo.exs

# Configure pooling BEFORE loading DSPex to prevent standalone bridge from starting
Application.put_env(:dspex, :pooling_enabled, true)
Application.put_env(:dspex, :pool_config, %{
  v2_enabled: false,
  v3_enabled: true,
  pool_size: 4
})

Mix.install([
  {:dspex, path: "."}
])

# Configure logging
Logger.configure(level: :info)

# Set test mode
System.put_env("TEST_MODE", "mock_adapter")

defmodule CleanPoolDemo do
  def run do
    IO.puts("\n🚀 DSPex V3 Pool Demo with Built-in Cleanup")
    IO.puts("=" |> String.duplicate(60))

    # Start the application
    {:ok, _} = Application.ensure_all_started(:dspex)

    # The pool is already running via the application supervisor
    pool_pid = Process.whereis(DSPex.Python.Pool)

    if pool_pid do
      IO.puts("\n✨ Using pool managed by application supervisor: #{inspect(pool_pid)}")

      # Test basic functionality
      test_basic_ping()
      test_concurrent_requests()

      IO.puts("\n🎯 Demo operations completed")
    else
      IO.puts("\n❌ Pool not found! Make sure pooling is enabled.")
    end

    IO.puts("\n✅ Demo complete!")
  end

  defp test_basic_ping do
    IO.puts("\n📤 Testing basic ping...")

    case DSPex.Python.Pool.execute("ping", %{demo: true}) do
      {:ok, result} ->
        IO.puts("✅ Ping successful: #{result["status"]}")
      {:error, reason} ->
        IO.puts("❌ Ping failed: #{inspect(reason)}")
    end
  end

  defp test_concurrent_requests do
    IO.puts("\n⚡ Testing concurrent requests...")

    start_time = System.monotonic_time(:millisecond)

    tasks = for i <- 1..8 do
      Task.async(fn ->
        DSPex.Python.Pool.execute("ping", %{id: i, concurrent: true})
      end)
    end

    results = Task.await_many(tasks, 10_000)
    success_count = Enum.count(results, &match?({:ok, _}, &1))

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("✅ #{success_count}/8 concurrent requests completed in #{elapsed}ms")
  end
end

# Run the demo
CleanPoolDemo.run()

# CRITICAL: Stop the application to trigger cleanup
IO.puts("\n🛑 Stopping DSPex application to clean up Python processes...")
Application.stop(:dspex)
