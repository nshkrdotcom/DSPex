#!/usr/bin/env elixir

# Simple debug script to trace anonymous program execution
Mix.install([
  {:dspex, path: "."}
])

require Logger
alias DSPex.PythonBridge.{SessionPoolV2, SessionStore}

# Start the application 
Application.start(:dspex)

:timer.sleep(2000)  # Wait for startup

Logger.info("🔍 Testing Anonymous Program Execution Debug...")

# Ensure pool is started
case Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
  nil ->
    Logger.info("Starting SessionPoolV2...")
    case DSPex.PythonBridge.SessionPoolV2.start_link(
      name: DSPex.PythonBridge.SessionPoolV2,
      pool_size: 2,
      overflow: 1
    ) do
      {:ok, _pid} ->
        Logger.info("✅ SessionPoolV2 started")
        :timer.sleep(5000)  # Wait for workers to initialize
      {:error, {:already_started, _pid}} ->
        Logger.info("✅ SessionPoolV2 already running")
      error ->
        Logger.error("Failed to start SessionPoolV2: #{inspect(error)}")
        exit(error)
    end
  _pid ->
    Logger.info("✅ SessionPoolV2 already running")
end

Logger.info("📦 Creating anonymous program...")

# Create an anonymous program
create_result = SessionPoolV2.execute_anonymous(:create_program, %{
  id: "debug_anon_#{System.unique_integer([:positive])}",
  signature: %{
    inputs: [%{name: "test", type: "string"}],
    outputs: [%{name: "result", type: "string"}]
  }
})

case create_result do
  {:ok, response} ->
    program_id = response["program_id"]
    Logger.info("✅ Created anonymous program: #{program_id}")
    
    # Check if it's in global storage
    case SessionStore.get_global_program(program_id) do
      {:ok, program_data} ->
        Logger.info("✅ Program found in global storage!")
        Logger.info("   Data: #{inspect(program_data)}")
        
        # Now try to execute it anonymously on a different worker
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
    end
    
  {:error, reason} ->
    Logger.error("❌ Failed to create program: #{inspect(reason)}")
end

Logger.info("🏁 Debug complete!")