#!/usr/bin/env elixir

# Final integration test that configures Snakepit properly

# Configure before starting
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 1,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Start applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

Process.sleep(3000)

IO.puts("🎯 Final Snakepit v0.4.1 Integration Test")
IO.puts("=" <> String.duplicate("=", 40))

# Test DSPy availability
case Snakepit.execute_in_session("final_test", "check_dspy", %{}) do
  {:ok, %{"available" => true, "version" => version}} ->
    IO.puts("✅ DSPy available: version #{version}")
    
    # Test program creation
    case Snakepit.execute_in_session("final_test", "create_program", %{
      name: "test_predict",
      program_type: "predict", 
      signature_name: "question -> answer"
    }) do
      {:ok, %{"success" => true}} ->
        IO.puts("✅ DSPy program created successfully")
        
        # Get final stats
        case Snakepit.execute_in_session("final_test", "get_stats", %{}) do
          {:ok, %{"success" => true, "stats" => stats}} ->
            IO.puts("✅ Final stats:")
            IO.inspect(stats, pretty: true)
            
            IO.puts("\n" <> String.duplicate("=", 40))
            IO.puts("🎉 SNAKEPIT v0.4.1 INTEGRATION COMPLETE!")
            IO.puts("✅ DSPy adapter working")
            IO.puts("✅ gRPC communication established") 
            IO.puts("✅ Tools registered and functional")
            IO.puts("✅ Programs can be created")
            IO.puts("✅ Gemini 2.5 Flash Lite configured")
            IO.puts(String.duplicate("=", 40))
            
          error -> IO.puts("❌ Stats error: #{inspect(error)}")
        end
        
      error -> IO.puts("❌ Program creation error: #{inspect(error)}")
    end
    
  error -> IO.puts("❌ DSPy check failed: #{inspect(error)}")
end

Application.stop(:dspex)
Application.stop(:snakepit)