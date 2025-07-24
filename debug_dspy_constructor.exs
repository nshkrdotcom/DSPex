# Debug DSPy constructor calls specifically
# Run with: mix run debug_dspy_constructor.exs

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

IO.puts("=== Debugging DSPy Constructor Calls ===\n")

# Configure LM first
config_path = Path.join(__DIR__, "examples/config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  case Snakepit.execute_in_session("debug_session", "configure_lm", %{
    "model_type" => "gemini", 
    "api_key" => api_key,
    "model" => config_data.model
  }) do
    {:ok, %{"success" => true}} -> IO.puts("✓ LM configured")
    {:ok, %{"success" => false, "error" => error}} -> IO.puts("✗ LM config failed: #{error}")
  end

  # Test 1: Try creating Predict directly with correct arguments
  IO.puts("\n1. Testing direct Predict creation with simple signature...")
  result1 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy",
    "function_name" => "Predict",
    "args" => ["question -> answer"],
    "kwargs" => %{}
  })
  IO.puts("Result: #{inspect(result1)}")

  # Test 2: Test calling the class constructor directly
  IO.puts("\n2. Testing Predict constructor call...")
  result2 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy.Predict",
    "function_name" => "__init__", 
    "args" => ["question -> answer"],
    "kwargs" => %{}
  })
  IO.puts("Result: #{inspect(result2)}")

  # Test 3: Test with kwargs signature
  IO.puts("\n3. Testing Predict with kwargs signature...")
  result3 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy.Predict",
    "function_name" => "__init__",
    "args" => [],
    "kwargs" => %{"signature" => "question -> answer"}
  })
  IO.puts("Result: #{inspect(result3)}")

  # Test 4: Try using the class directly without __init__
  IO.puts("\n4. Testing calling dspy.Predict as function...")
  result4 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy",
    "function_name" => "Predict",
    "args" => [],
    "kwargs" => %{"signature" => "question -> answer"}
  })
  IO.puts("Result: #{inspect(result4)}")

else
  IO.puts("⚠️  No API key found - skipping debug")
end

IO.puts("\n=== Debug Complete ===")