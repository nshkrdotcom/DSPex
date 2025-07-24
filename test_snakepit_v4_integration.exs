#!/usr/bin/env elixir

# Comprehensive test for the refactored Snakepit v0.4.1 integration
# Using the correct tool execution API

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

IO.puts("🚀 Testing Snakepit v0.4.1 Integration with Correct Tool API")
IO.puts("=" <> String.duplicate("=", 60))

session_id = "dspy_test_session"

# Test 1: Check tool registry and execute ping
IO.puts("\n1. Testing tool registry and basic connectivity...")

# First get the worker channel for our session
# We need to trigger a session to get a worker assigned
case Process.whereis(:snakepit_pool_supervisor) do
  nil ->
    IO.puts("✗ Snakepit pool supervisor not running")
    System.halt(1)
  
  _pid ->
    IO.puts("✓ Snakepit pool supervisor is running")
end

# Try to execute via the ToolRegistry
case Snakepit.Bridge.ToolRegistry.execute_local_tool(session_id, "ping", %{}) do
  {:ok, result} ->
    IO.puts("✓ Local tool execution successful: #{inspect(result)}")
  
  {:error, :tool_not_found} ->
    IO.puts("ℹ Tool not found in local registry, trying gRPC channel...")
    
    # Try to get a gRPC connection
    try do
      # We need to establish a connection first
      # Let's try a different approach - using the pool directly
      case Snakepit.Pool.checkout() do
        {:ok, worker_pid} ->
          IO.puts("✓ Got worker: #{inspect(worker_pid)}")
          
          # Now try to get the gRPC channel from the worker
          worker_info = GenServer.call(worker_pid, :get_info)
          IO.puts("Worker info: #{inspect(worker_info)}")
          
          Snakepit.Pool.checkin(worker_pid)
          
        {:error, error} ->
          IO.puts("✗ Failed to checkout worker: #{inspect(error)}")
          System.halt(1)
      end
    catch
      kind, reason ->
        IO.puts("✗ Exception during worker checkout: #{kind} - #{inspect(reason)}")
        System.halt(1)
    end
    
  {:error, error} ->
    IO.puts("✗ Local tool execution failed: #{inspect(error)}")
end

# Test 2: List available tools for the session
IO.puts("\n2. Listing available tools...")
case Snakepit.Bridge.ToolRegistry.list_tools(session_id) do
  {:ok, tools} when is_list(tools) ->
    IO.puts("✓ Found #{length(tools)} tools:")
    Enum.each(tools, fn tool -> IO.puts("  - #{tool}") end)
  
  {:ok, empty} when empty == [] ->
    IO.puts("ℹ No tools registered for this session yet")
  
  {:error, error} ->
    IO.puts("✗ Failed to list tools: #{inspect(error)}")
end

# Test 3: Try alternative approach - direct pool interaction
IO.puts("\n3. Testing direct pool interaction...")

defmodule TestHelper do
  def test_dspy_tools do
    # Try to execute a tool through the pool system
    case Snakepit.execute_in_session("dspy_session", "ping", %{}) do
      {:ok, result} ->
        IO.puts("✓ Pool execution successful: #{inspect(result)}")
        
        # Now try check_dspy
        case Snakepit.execute_in_session("dspy_session", "check_dspy", %{}) do
          {:ok, dspy_result} ->
            IO.puts("✓ DSPy check result: #{inspect(dspy_result)}")
            
            # Test statistics
            case Snakepit.execute_in_session("dspy_session", "get_stats", %{}) do
              {:ok, stats} ->
                IO.puts("✓ Stats: #{inspect(stats)}")
                {:ok, :all_tests_passed}
              
              {:error, stats_error} ->
                IO.puts("✗ Stats failed: #{inspect(stats_error)}")
                {:error, :stats_failed}
            end
            
          {:error, dspy_error} ->
            IO.puts("✗ DSPy check failed: #{inspect(dspy_error)}")
            {:error, :dspy_check_failed}
        end
        
      {:error, error} ->
        IO.puts("✗ Pool execution failed: #{inspect(error)}")
        {:error, :pool_execution_failed}
    end
  end
end

case TestHelper.test_dspy_tools() do
  {:ok, :all_tests_passed} ->
    IO.puts("\n✅ All tests passed! The Snakepit v0.4.1 integration is working correctly.")
    IO.puts("\nThe DSPy adapter can now be used with the new session-based API:")
    IO.puts("  - Use Snakepit.execute_in_session(session_id, tool_name, params)")
    IO.puts("  - Tools are properly registered and discoverable")
    IO.puts("  - DSPy functionality is available through the gRPC bridge")
    
  {:error, reason} ->
    IO.puts("\n❌ Tests failed with reason: #{reason}")
    IO.puts("Check the logs above for specific error details.")
end

# Test 4: Test DSPex module integration (if basic tests pass)
IO.puts("\n4. Testing DSPex module integration...")
try do
  # Test the updated Predict module
  case DSPex.Modules.Predict.create("question -> answer", session_id: "integration_test") do
    {:ok, {session_id, predictor_id}} ->
      IO.puts("✓ Predict module created: #{predictor_id} in session #{session_id}")
      
      # Try to execute it
      case DSPex.Modules.Predict.execute({session_id, predictor_id}, %{question: "What is 2+2?"}) do
        {:ok, result} ->
          IO.puts("✓ Predict execution successful: #{inspect(result)}")
        
        {:error, exec_error} ->
          IO.puts("✗ Predict execution failed: #{inspect(exec_error)}")
      end
      
    {:error, create_error} ->
      IO.puts("✗ Predict module creation failed: #{inspect(create_error)}")
  end
rescue
  e ->
    IO.puts("✗ DSPex module test failed with exception: #{inspect(e)}")
end

# Graceful shutdown
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Shutting down...")
Application.stop(:dspex)
Application.stop(:snakepit)
IO.puts("Integration test complete.")