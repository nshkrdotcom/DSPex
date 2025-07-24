#!/usr/bin/env elixir

# Simple working test with Snakepit v0.4.1

# Start applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

Process.sleep(2000)

IO.puts("🧪 Testing Snakepit v0.4.1 Integration")

# Test DSPy availability
case Snakepit.execute_in_session("test", "check_dspy", %{}) do
  {:ok, %{"available" => true, "version" => version}} ->
    IO.puts("✅ DSPy available: #{version}")
    
    # Test stats
    case Snakepit.execute_in_session("test", "get_stats", %{}) do
      {:ok, %{"success" => true, "stats" => stats}} ->
        IO.puts("✅ Stats: #{inspect(stats, pretty: true)}")
        IO.puts("\n🎉 Integration working perfectly!")
        
      error ->
        IO.puts("❌ Stats error: #{inspect(error)}")
    end
    
  error ->
    IO.puts("❌ DSPy check failed: #{inspect(error)}")
end

Application.stop(:dspex)
Application.stop(:snakepit)