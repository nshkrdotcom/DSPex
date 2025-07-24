#!/usr/bin/env elixir

# Test script for the refactored Snakepit v0.4.1 integration
# This bypasses the old DSPex.Config.init() to test direct integration

require Logger

# Ensure required applications are loaded
Application.load(:snakepit)
Application.load(:dspex)

# Configure Snakepit for gRPC with our new adapter
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 1,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Configure gRPC settings
Application.put_env(:snakepit, :grpc_config, %{
  base_port: 50051,
  port_range: 100
})

# Stop any running instances
Application.stop(:dspex)
Application.stop(:snakepit)

# Start fresh
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

IO.puts("🚀 Testing New Snakepit v0.4.1 Integration")
IO.puts("=" <> String.duplicate("=", 50))

# Test 1: Basic adapter connectivity
IO.puts("\n1. Testing adapter connectivity...")
case Snakepit.execute_in_session("test_session", "ping", %{}) do
  {:ok, result} ->
    IO.puts("✓ Adapter ping successful: #{inspect(result)}")
  
  {:error, error} ->
    IO.puts("✗ Adapter ping failed: #{inspect(error)}")
    System.halt(1)
end

# Test 2: Check DSPy availability
IO.puts("\n2. Checking DSPy availability...")
case Snakepit.execute_in_session("test_session", "check_dspy", %{}) do
  {:ok, %{"available" => true, "version" => version}} ->
    IO.puts("✓ DSPy is available, version: #{version}")
  
  {:ok, %{"available" => false, "error" => error}} ->
    IO.puts("✗ DSPy not available: #{error}")
    IO.puts("Please install DSPy with: pip install dspy-ai")
    System.halt(1)
    
  {:error, error} ->
    IO.puts("✗ Failed to check DSPy: #{inspect(error)}")
    System.halt(1)
end

# Test 3: Get adapter statistics
IO.puts("\n3. Getting adapter statistics...")
case Snakepit.execute_in_session("test_session", "get_stats", %{}) do
  {:ok, %{"success" => true, "stats" => stats}} ->
    IO.puts("✓ Adapter statistics:")
    IO.inspect(stats, pretty: true)
  
  {:error, error} ->
    IO.puts("✗ Failed to get stats: #{inspect(error)}")
end

IO.puts("\n✅ Basic integration test completed successfully!")
IO.puts("The new Snakepit v0.4.1 integration is working correctly.")

# Graceful shutdown
IO.puts("\nShutting down...")
Application.stop(:dspex)
Application.stop(:snakepit)
IO.puts("Test complete.")