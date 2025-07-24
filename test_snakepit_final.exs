#!/usr/bin/env elixir

# Final test for Snakepit v0.4.1 integration
# Simplified approach using direct execute_in_session

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

IO.puts("🚀 Testing Snakepit v0.4.1 Integration - Final Test")
IO.puts("=" <> String.duplicate("=", 50))

# Give the system a moment to initialize
Process.sleep(1000)

session_id = "final_test_session"

IO.puts("\n1. Testing basic ping...")
case Snakepit.execute_in_session(session_id, "ping", %{}) do
  {:ok, result} ->
    IO.puts("✓ Ping successful: #{inspect(result)}")
    
    IO.puts("\n2. Checking DSPy availability...")
    case Snakepit.execute_in_session(session_id, "check_dspy", %{}) do
      {:ok, %{"available" => true, "version" => version}} ->
        IO.puts("✓ DSPy available, version: #{version}")
        
        IO.puts("\n3. Getting adapter statistics...")
        case Snakepit.execute_in_session(session_id, "get_stats", %{}) do
          {:ok, %{"success" => true, "stats" => stats}} ->
            IO.puts("✓ Statistics retrieved:")
            IO.inspect(stats, pretty: true, limit: :infinity)
            
            IO.puts("\n4. Testing DSPy program creation...")
            create_params = %{
              name: "test_predictor",
              program_type: "predict", 
              signature_name: "question -> answer"
            }
            
            case Snakepit.execute_in_session(session_id, "create_program", create_params) do
              {:ok, %{"success" => true, "name" => program_name}} ->
                IO.puts("✓ DSPy program created: #{program_name}")
                
                IO.puts("\n5. Testing program execution...")
                exec_params = %{
                  name: program_name,
                  inputs: %{"question" => "What is the capital of France?"}
                }
                
                case Snakepit.execute_in_session(session_id, "execute_program", exec_params) do
                  {:ok, %{"success" => true, "result" => result}} ->
                    IO.puts("✓ Program execution successful:")
                    IO.inspect(result, pretty: true)
                    
                    IO.puts("\n🎉 ALL TESTS PASSED!")
                    IO.puts("The Snakepit v0.4.1 integration is fully functional!")
                    
                  {:ok, %{"success" => false, "error" => error}} ->
                    IO.puts("✗ Program execution failed: #{error}")
                    
                  {:error, exec_error} ->
                    IO.puts("✗ Program execution error: #{inspect(exec_error)}")
                end
                
              {:ok, %{"success" => false, "error" => error}} ->
                IO.puts("✗ Program creation failed: #{error}")
                
              {:error, create_error} ->  
                IO.puts("✗ Program creation error: #{inspect(create_error)}")
            end
            
          {:ok, %{"success" => false, "error" => error}} ->
            IO.puts("✗ Statistics failed: #{error}")
            
          {:error, stats_error} ->
            IO.puts("✗ Statistics error: #{inspect(stats_error)}")
        end
        
      {:ok, %{"available" => false, "error" => error}} ->
        IO.puts("✗ DSPy not available: #{error}")
        IO.puts("Please install DSPy: pip install dspy-ai")
        
      {:error, dspy_error} ->
        IO.puts("✗ DSPy check error: #{inspect(dspy_error)}")
    end
    
  {:error, ping_error} ->
    IO.puts("✗ Ping failed: #{inspect(ping_error)}")
    IO.puts("The integration may not be working correctly.")
end

# Show session information
IO.puts("\n" <> String.duplicate("-", 50))
IO.puts("Session and tool information:")

try do
  case Snakepit.Bridge.SessionStore.get_session(session_id) do
    {:ok, session} ->
      IO.puts("✓ Session found: #{inspect(session, pretty: true, limit: 3)}")
    
    {:error, :not_found} ->
      IO.puts("ℹ Session not found in store")
      
    {:error, other} ->
      IO.puts("✗ Session lookup error: #{inspect(other)}")
  end
rescue
  e -> IO.puts("Exception getting session: #{inspect(e)}")
end

try do
  tools = Snakepit.Bridge.ToolRegistry.list_tools(session_id)
  IO.puts("Available tools: #{inspect(tools)}")
rescue
  e -> IO.puts("Exception listing tools: #{inspect(e)}")
end

# Graceful shutdown
IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("Shutting down...")
Application.stop(:dspex)
Application.stop(:snakepit)
IO.puts("Test complete.")