# Test the new schema bridge functionality
# Run with: mix run test_schema_bridge.exs

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

IO.puts("=== Testing Schema Bridge ===\n")

# Test 1: Discover DSPy schema
IO.puts("1. Discovering DSPy schema...")
case Snakepit.execute_in_session("schema_test", "discover_dspy_schema", %{}) do
  {:ok, %{"success" => true, "schema" => schema, "discovered_count" => count}} ->
    IO.puts("✓ Discovered #{count} DSPy classes/functions")
    
    # Show some key classes
    for {class_name, class_info} <- Enum.take(schema, 3) do
      IO.puts("\n#{class_name} (#{class_info["type"]}):")
      IO.puts("  #{class_info["docstring"]}")
      
      if class_info["methods"] do
        method_count = map_size(class_info["methods"])
        IO.puts("  Methods: #{method_count}")
        
        # Show a few methods
        for {method_name, method_info} <- Enum.take(class_info["methods"], 2) do
          IO.puts("    #{method_name}#{method_info["signature"]}")
        end
      end
    end
    
  {:ok, %{"success" => false, "error" => error}} ->
    IO.puts("✗ Schema discovery failed: #{error}")
  {:error, error} ->
    IO.puts("✗ Schema discovery error: #{inspect(error)}")
end

# Test 2: Use call_dspy to create a Predict instance
IO.puts("\n\n2. Testing call_dspy with Predict...")

# Configure LM first
config_path = Path.join(__DIR__, "examples/config.exs")
config_data = Code.eval_file(config_path) |> elem(0)
api_key = config_data.api_key

if api_key do
  case Snakepit.execute_in_session("schema_test", "configure_lm", %{
    "model_type" => "gemini", 
    "api_key" => api_key,
    "model" => config_data.model
  }) do
    {:ok, %{"success" => true}} -> IO.puts("✓ LM configured")
    {:ok, %{"success" => false, "error" => error}} -> IO.puts("✗ LM config failed: #{error}")
    {:error, error} -> IO.puts("✗ LM config error: #{inspect(error)}")
  end
  
  # Create Predict instance using call_dspy
  case Snakepit.execute_in_session("schema_test", "call_dspy", %{
    "module_path" => "dspy.Predict",
    "function_name" => "__init__", 
    "args" => [],
    "kwargs" => %{"signature" => "question -> answer"}
  }) do
    {:ok, %{"success" => true, "instance_id" => instance_id, "type" => "constructor"}} ->
      IO.puts("✓ Created Predict instance: #{instance_id}")
      
      # Test calling the instance
      case Snakepit.execute_in_session("schema_test", "call_dspy", %{
        "module_path" => "stored.#{instance_id}",
        "function_name" => "__call__",
        "args" => [],
        "kwargs" => %{"question" => "What is 2+2?"}
      }) do
        {:ok, %{"success" => true, "result" => result, "type" => "method"}} ->
          IO.puts("✓ Predict execution successful!")
          IO.puts("Result: #{inspect(result)}")
        {:ok, %{"success" => false, "error" => error}} ->
          IO.puts("✗ Predict execution failed: #{error}")
        {:error, error} ->
          IO.puts("✗ Predict execution error: #{inspect(error)}")
      end
      
    {:ok, %{"success" => false, "error" => error}} ->
      IO.puts("✗ Predict creation failed: #{error}")
    {:error, error} ->
      IO.puts("✗ Predict creation error: #{inspect(error)}")
  end
else
  IO.puts("⚠️  No API key found - skipping LM tests")
end

# Test 3: Discover specific submodules
IO.puts("\n\n3. Testing submodule discovery...")

submodules = ["dspy", "dspy.teleprompt"]
for submodule <- submodules do
  case Snakepit.execute_in_session("schema_test", "discover_dspy_schema", %{
    "module_path" => submodule
  }) do
    {:ok, %{"success" => true, "discovered_count" => count}} ->
      IO.puts("✓ #{submodule}: #{count} items discovered")
    {:ok, %{"success" => false, "error" => error}} ->
      IO.puts("✗ #{submodule}: #{error}")
    {:error, error} ->
      IO.puts("✗ #{submodule}: #{inspect(error)}")
  end
end

IO.puts("\n=== Schema Bridge Test Complete ===")