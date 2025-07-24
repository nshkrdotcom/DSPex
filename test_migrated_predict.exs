# Test the migrated Predict module using schema bridge
# Run with: mix run test_migrated_predict.exs

# Configure Snakepit for pooling BEFORE starting
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 4,
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Stop and restart applications if already started
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

IO.puts("=== Testing Migrated Predict Module ===\n")

# Configure LM first
config_path = Path.join(__DIR__, "examples/config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  IO.puts("1. Configuring LM...")
  case Snakepit.execute_in_session("test_session", "configure_lm", %{
    "model_type" => "gemini", 
    "api_key" => api_key,
    "model" => config_data.model
  }) do
    {:ok, %{"success" => true}} -> IO.puts("✓ LM configured")
    {:ok, %{"success" => false, "error" => error}} -> IO.puts("✗ LM config failed: #{error}")
    {:error, error} -> IO.puts("✗ LM config error: #{inspect(error)}")
  end

  # Test 1: Create Predict instance using new schema bridge
  IO.puts("\n2. Testing Predict.create...")
  case DSPex.Modules.Predict.create("question -> answer", session_id: "test_session") do
    {:ok, predictor_ref} ->
      IO.puts("✓ Created Predict instance: #{inspect(predictor_ref)}")
      
      # Test 2: Execute prediction
      IO.puts("\n3. Testing Predict.execute...")
      case DSPex.Modules.Predict.execute(predictor_ref, %{"question" => "What is 2+2?"}) do
        {:ok, result} ->
          IO.puts("✓ Predict execution successful!")
          IO.puts("Result: #{inspect(result)}")
        {:error, error} ->
          IO.puts("✗ Predict execution failed: #{error}")
      end
      
      # Test 3: Stateless predict call
      IO.puts("\n4. Testing Predict.predict (stateless)...")
      case DSPex.Modules.Predict.predict("question -> answer", %{"question" => "What is the capital of France?"}, session_id: "test_session") do
        {:ok, result} ->
          IO.puts("✓ Stateless predict successful!")
          IO.puts("Result: #{inspect(result)}")
        {:error, error} ->
          IO.puts("✗ Stateless predict failed: #{error}")
      end
      
    {:error, error} ->
      IO.puts("✗ Predict creation failed: #{error}")
  end
else
  IO.puts("⚠️  No API key found - testing error handling...")
  
  case DSPex.Modules.Predict.create("question -> answer") do
    {:ok, predictor_ref} ->
      IO.puts("✓ Created Predict instance without LM: #{inspect(predictor_ref)}")
      
      case DSPex.Modules.Predict.execute(predictor_ref, %{"question" => "What is 2+2?"}) do
        {:ok, result} ->
          IO.puts("✓ Unexpected success: #{inspect(result)}")
        {:error, error} ->
          IO.puts("✓ Expected failure (no LM): #{error}")
      end
    {:error, error} ->
      IO.puts("✓ Expected creation failure (no LM): #{error}")
  end
end

IO.puts("\n=== Test Complete ===")