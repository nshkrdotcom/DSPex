#!/usr/bin/env elixir

# Simple test script to verify global program storage
Mix.install([
  {:dspex, path: "."}
])

alias DSPex.PythonBridge.{SessionPoolV2, SessionStore}

defmodule GlobalProgramTest do
  def run do
    IO.puts("🧪 Testing Global Program Storage")
    
    # Start the services
    {:ok, _} = SessionStore.start_link()
    
    # Test global program storage directly
    test_direct_storage()
    
    # Test through pool operations (if pool is available)
    if Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
      test_pool_storage()
    else
      IO.puts("⚠️  Pool not available, skipping pool tests")
    end
    
    IO.puts("✅ Global Program Storage tests complete")
  end
  
  defp test_direct_storage do
    IO.puts("\n📦 Testing direct SessionStore global program storage...")
    
    program_id = "test_prog_#{System.unique_integer([:positive])}"
    program_data = %{
      program_id: program_id,
      signature_def: %{inputs: [%{name: "test", type: "string"}]},
      created_at: System.system_time(:second)
    }
    
    # Store program
    :ok = SessionStore.store_global_program(program_id, program_data)
    IO.puts("✅ Stored global program: #{program_id}")
    
    # Retrieve program
    {:ok, retrieved_data} = SessionStore.get_global_program(program_id)
    IO.puts("✅ Retrieved global program: #{inspect(retrieved_data)}")
    
    # Verify data matches
    if retrieved_data == program_data do
      IO.puts("✅ Program data matches!")
    else
      IO.puts("❌ Program data mismatch!")
    end
    
    # Delete program
    :ok = SessionStore.delete_global_program(program_id)
    IO.puts("✅ Deleted global program: #{program_id}")
    
    # Verify deletion
    case SessionStore.get_global_program(program_id) do
      {:error, :not_found} ->
        IO.puts("✅ Program correctly deleted")
      _ ->
        IO.puts("❌ Program not deleted!")
    end
  end
  
  defp test_pool_storage do
    IO.puts("\n🏊 Testing pool-based global program storage...")
    
    # Create an anonymous program
    create_result = SessionPoolV2.execute_anonymous(:create_program, %{
      id: "pool_test_#{System.unique_integer([:positive])}",
      signature: %{
        inputs: [%{name: "test_input", type: "string"}],
        outputs: [%{name: "test_output", type: "string"}]
      }
    })
    
    case create_result do
      {:ok, response} ->
        program_id = response["program_id"]
        IO.puts("✅ Created anonymous program: #{program_id}")
        
        # Check if it's in global storage
        case SessionStore.get_global_program(program_id) do
          {:ok, program_data} ->
            IO.puts("✅ Program found in global storage: #{inspect(program_data)}")
          
          {:error, :not_found} ->
            IO.puts("❌ Program not found in global storage!")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to create program: #{inspect(reason)}")
    end
  end
end

GlobalProgramTest.run()