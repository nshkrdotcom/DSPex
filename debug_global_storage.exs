#!/usr/bin/env elixir

# Debug script to check if global program storage is working
Mix.install([
  {:dspex, path: "."}
])

require Logger
alias DSPex.PythonBridge.{SessionPoolV2, SessionStore}

# Start everything
Application.start(:dspex)

:timer.sleep(2000)  # Wait for startup

Logger.info("🔍 Testing Anonymous Program Storage Debug...")

# Test 1: Create anonymous program and check if it's stored globally
Logger.info("📦 Creating anonymous program...")

result = SessionPoolV2.execute_anonymous(:create_program, %{
  id: "debug_anon_#{System.unique_integer([:positive])}",
  signature: %{
    inputs: [%{name: "test", type: "string"}],
    outputs: [%{name: "result", type: "string"}]
  }
})

case result do
  {:ok, response} ->
    program_id = response["program_id"]
    Logger.info("✅ Created program: #{program_id}")
    
    # Check if it's in global storage
    case SessionStore.get_global_program(program_id) do
      {:ok, program_data} ->
        Logger.info("✅ Program found in global storage!")
        Logger.info("   Data: #{inspect(program_data)}")
        
        # Now try to execute it anonymously
        Logger.info("🚀 Attempting cross-worker execution...")
        exec_result = SessionPoolV2.execute_anonymous(:execute_program, %{
          program_id: program_id,
          inputs: %{test: "hello world"}
        })
        
        case exec_result do
          {:ok, exec_response} ->
            Logger.info("✅ Cross-worker execution SUCCESS!")
            Logger.info("   Result: #{inspect(exec_response)}")
          
          {:error, reason} ->
            Logger.error("❌ Cross-worker execution FAILED: #{inspect(reason)}")
        end
        
      {:error, :not_found} ->
        Logger.error("❌ Program NOT found in global storage!")
        Logger.error("   This means store_anonymous_program_globally is not working")
    end
    
  {:error, reason} ->
    Logger.error("❌ Failed to create program: #{inspect(reason)}")
end

# Test 2: Check what's in global storage
Logger.info("\n🗄️  Checking all global programs...")
# We don't have a list function, so we'll check if the table exists
try do
  case :ets.tab2list(:dspex_sessions_global_programs) do
    [] -> 
      Logger.warning("📭 Global programs table is empty")
    
    programs -> 
      Logger.info("📋 Global programs found:")
      Enum.each(programs, fn {id, data, timestamp} ->
        Logger.info("   • #{id}: #{inspect(data)} (created: #{timestamp})")
      end)
  end
rescue
  ArgumentError ->
    Logger.error("❌ Global programs table doesn't exist!")
end

Logger.info("🏁 Debug complete!")