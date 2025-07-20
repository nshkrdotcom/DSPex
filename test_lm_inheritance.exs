# Test script to verify LM inheritance fix
# Run with: mix run test_lm_inheritance.exs

# Configure Snakepit
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :pool_config, %{pool_size: 1})

# Stop and restart applications
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Configure Gemini
api_key = System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
if api_key do
  IO.puts("✅ Configuring Gemini 2.0 Flash with API key...")
  case DSPex.LM.configure("gemini/gemini-2.0-flash", api_key: api_key) do
    {:ok, _} -> IO.puts("✅ LM configured successfully!")
    {:error, error} -> IO.puts("❌ Configuration error: #{inspect(error)}")
  end
  
  # Test 1: Check global LM configuration
  IO.puts("\n1. Testing global LM configuration...")
  case Snakepit.Python.call("dspy.settings.lm", %{}, []) do
    {:ok, result} ->
      IO.puts("✅ Global LM is configured: #{inspect(Map.get(result, "type"))}")
    {:error, error} ->
      IO.puts("❌ Error checking global LM: #{inspect(error)}")
  end
  
  # Test 2: Create and execute Predict module
  IO.puts("\n2. Testing Predict module with LM inheritance fix...")
  case DSPex.Modules.Predict.create("question -> answer") do
    {:ok, predictor} ->
      IO.puts("✅ Predict module created: #{predictor}")
      
      # Check if module has LM
      case Snakepit.Python.call("stored.#{predictor}.lm", %{}, []) do
        {:ok, lm_result} ->
          IO.puts("   Module LM type: #{inspect(Map.get(lm_result, "type"))}")
        _ ->
          IO.puts("   Module LM: Unable to check")
      end
      
      # Try to execute
      case DSPex.Modules.Predict.execute(predictor, %{question: "What is 2+2?"}) do
        {:ok, result} -> 
          IO.puts("✅ Execution succeeded!")
          IO.puts("   Answer: #{inspect(Map.get(result, "answer") || Map.get(result, :answer))}")
        {:error, %{"error" => "No LM is loaded." <> _}} ->
          IO.puts("❌ Still getting 'No LM is loaded' error")
          IO.puts("   Attempting manual LM assignment...")
          
          # Try manual fix
          case Snakepit.Python.call("""
          import dspy
          module = stored['#{predictor}']
          if hasattr(module, 'lm') and module.lm is None:
              module.lm = dspy.settings.lm or stored.get('default_lm')
              print(f"Manually assigned LM: {type(module.lm)}")
          """, %{}, []) do
            {:ok, _} ->
              # Retry execution
              case DSPex.Modules.Predict.execute(predictor, %{question: "What is 2+2?"}) do
                {:ok, result} -> 
                  IO.puts("✅ Manual fix worked! Answer: #{inspect(Map.get(result, "answer") || Map.get(result, :answer))}")
                {:error, error} ->
                  IO.puts("❌ Manual fix failed: #{inspect(error)}")
              end
            {:error, error} ->
              IO.puts("❌ Could not apply manual fix: #{inspect(error)}")
          end
        {:error, error} ->
          IO.puts("❌ Other error: #{inspect(error)}")
      end
    {:error, error} ->
      IO.puts("❌ Failed to create module: #{inspect(error)}")
  end
  
  # Test 3: Check if environment variable is set
  IO.puts("\n3. Checking Python environment variables...")
  case Snakepit.Python.call("""
  import os
  print(f"GOOGLE_API_KEY in env: {'GOOGLE_API_KEY' in os.environ}")
  print(f"GEMINI_API_KEY in env: {'GEMINI_API_KEY' in os.environ}")
  if 'GOOGLE_API_KEY' in os.environ:
      print(f"GOOGLE_API_KEY length: {len(os.environ['GOOGLE_API_KEY'])}")
  """, %{}, []) do
    {:ok, _} -> :ok
    {:error, error} -> IO.puts("Error: #{inspect(error)}")
  end
  
else
  IO.puts("❌ No API key found!")
end