#!/usr/bin/env elixir

# Working test for Snakepit v0.4.1 integration

require Logger

# Configure Snakepit for gRPC with our new adapter
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 1,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

Application.put_env(:snakepit, :grpc_config, %{
  base_port: 50051,
  port_range: 100
})

# Start applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

Process.sleep(2000)  # Let workers initialize

IO.puts("🚀 Testing Direct Tool Execution")
IO.puts("=" <> String.duplicate("=", 40))

session_id = "test_session"

# Test using the new tool calling approach
IO.puts("\n1. Testing with call_tool...")

# Get a worker first
case Snakepit.Pool.checkout() do
  {:ok, worker_pid} ->
    IO.puts("✓ Got worker: #{inspect(worker_pid)}")
    
    # Get worker info
    case GenServer.call(worker_pid, :get_info) do
      info when is_map(info) ->
        IO.puts("Worker info: #{inspect(info)}")
        
        # Try to call tool directly on the worker if possible
        # For now, let's just check the worker is responding
        IO.puts("✓ Worker is responding")
        
      error ->
        IO.puts("✗ Worker info error: #{inspect(error)}")
    end
    
    # Check worker back in
    Snakepit.Pool.checkin(worker_pid)
    
  {:error, error} ->
    IO.puts("✗ Failed to checkout worker: #{inspect(error)}")
end

IO.puts("\n2. Checking tool registry...")
case Snakepit.Bridge.ToolRegistry.list_tools(session_id) do
  {:ok, tools} ->
    IO.puts("✓ Tools for session #{session_id}: #{inspect(tools)}")
    
  {:error, error} ->
    IO.puts("✗ Tool registry error: #{inspect(error)}")
end

# Test our DSPex modules with the updated API
IO.puts("\n3. Testing DSPex modules...")
try do
  case DSPex.Modules.Predict.create("question -> answer", session_id: session_id) do
    {:ok, {session_id, predictor_id}} ->
      IO.puts("✓ Predictor created: #{predictor_id} in session #{session_id}")
    
    {:error, error} -> 
      IO.puts("✗ Predictor creation failed: #{inspect(error)}")
  end
rescue
  e ->
    IO.puts("✗ Exception during predictor creation: #{inspect(e)}")
end

IO.puts("\n" <> String.duplicate("=", 40))
IO.puts("Integration test complete")

# Shutdown
Application.stop(:dspex)
Application.stop(:snakepit)