# Debug the call_dspy signature binding issue
# Run with: mix run debug_call_dspy.exs

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

IO.puts("=== Debugging call_dspy Signature Issue ===\n")

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

  # Debug 1: Test call_dspy with correct parameters
  IO.puts("\n1. Testing call_dspy with string signature...")
  result1 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy.Predict",
    "function_name" => "__init__",
    "args" => [],
    "kwargs" => %{"signature" => "question -> answer"}
  })
  IO.puts("Result: #{inspect(result1)}")

  # Debug 2: Test call_dspy with just the signature as string (no kwargs wrapper)
  IO.puts("\n2. Testing call_dspy with direct signature argument...")
  result2 = Snakepit.execute_in_session("debug_session", "call_dspy", %{
    "module_path" => "dspy.Predict", 
    "function_name" => "__init__",
    "args" => ["question -> answer"],
    "kwargs" => %{}
  })
  IO.puts("Result: #{inspect(result2)}")

  # Debug 3: Test schema discovery for Predict class to see its __init__ signature
  IO.puts("\n3. Discovering Predict schema...")
  case Snakepit.execute_in_session("debug_session", "discover_dspy_schema", %{}) do
    {:ok, %{"success" => true, "schema" => schema}} ->
      predict_info = schema["Predict"]
      if predict_info do
        init_method = predict_info["methods"]["__init__"]
        if init_method do
          IO.puts("Predict.__init__ signature: #{init_method["signature"]}")
          IO.puts("Parameters: #{inspect(init_method["parameters"])}")
        else
          IO.puts("No __init__ method found in schema")
        end
      else
        IO.puts("Predict class not found in schema")
      end
    {:error, error} ->
      IO.puts("Schema discovery failed: #{inspect(error)}")
  end

else
  IO.puts("⚠️  No API key found - skipping debug")
end

IO.puts("\n=== Debug Complete ===")