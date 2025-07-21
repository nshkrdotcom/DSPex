# Test LM Configuration
# Run with: mix run examples/dspy/test_lm_config.exs

# Configure Snakepit
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :wire_protocol, :auto)
Application.put_env(:snakepit, :pool_config, %{pool_size: 1})

# Stop and restart
Application.stop(:dspex)
Application.stop(:snakepit)

# Start
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

IO.puts("Testing LM Configuration...\n")

# Load config
config_path = Path.join(__DIR__, "../config.exs")
config_data = Code.eval_file(config_path) |> elem(0)

# Test 1: Check if we can create an LM
IO.puts("1. Creating LM instance...")
case Snakepit.Python.call("dspy.LM", %{model: config_data.model}, store_as: "test_lm") do
  {:ok, result} ->
    IO.puts("✓ LM created successfully")
    IO.inspect(result, label: "LM Result")
  {:error, error} ->
    IO.puts("✗ Failed to create LM")
    IO.inspect(error, label: "Error")
end

# Test 2: Check DSPy settings before configuration
IO.puts("\n2. Checking DSPy settings before configuration...")
case Snakepit.Python.call("dspy.settings.__dict__", %{}, []) do
  {:ok, result} ->
    IO.puts("✓ Got DSPy settings")
    # Check if lm is set
    lm_value = get_in(result, ["result", "value", "lm", "value"])
    IO.puts("  Current LM: #{inspect(lm_value)}")
  {:error, error} ->
    IO.puts("✗ Failed to get settings")
    IO.inspect(error)
end

# Test 3: Configure DSPy
IO.puts("\n3. Configuring DSPy with the LM...")
case Snakepit.Python.call("dspy.configure", %{lm: "stored.test_lm"}, []) do
  {:ok, _} ->
    IO.puts("✓ DSPy configured")
  {:error, error} ->
    IO.puts("✗ Failed to configure DSPy")
    IO.inspect(error)
end

# Test 4: Check DSPy settings after configuration
IO.puts("\n4. Checking DSPy settings after configuration...")
case Snakepit.Python.call("dspy.settings.__dict__", %{}, []) do
  {:ok, result} ->
    IO.puts("✓ Got DSPy settings")
    lm_value = get_in(result, ["result", "value", "lm"])
    IO.puts("  Current LM after config: #{inspect(lm_value)}")
  {:error, error} ->
    IO.puts("✗ Failed to get settings")
    IO.inspect(error)
end

# Test 5: Create a Predict module and check its LM
IO.puts("\n5. Creating Predict module...")
case Snakepit.Python.call("dspy.Predict", %{signature: "question -> answer"}, store_as: "test_predict") do
  {:ok, _} ->
    IO.puts("✓ Predict module created")
    
    # Check the module's LM
    case Snakepit.Python.call("stored.test_predict.lm", %{}, []) do
      {:ok, result} ->
        IO.puts("  Module's LM: #{inspect(result)}")
      {:error, error} ->
        IO.puts("  Error checking module's LM: #{inspect(error)}")
    end
  {:error, error} ->
    IO.puts("✗ Failed to create Predict module")
    IO.inspect(error)
end

# Test 6: Try to execute with the module
IO.puts("\n6. Trying to execute prediction...")
case Snakepit.Python.call("stored.test_predict.__call__", %{question: "What is 2+2?"}, []) do
  {:ok, result} ->
    IO.puts("✓ Execution succeeded!")
    IO.inspect(result, label: "Result")
  {:error, error} ->
    IO.puts("✗ Execution failed")
    IO.puts("  Error: #{inspect(error["error"])}")
end

IO.puts("\n\nConclusion:")
IO.puts("If you see 'No LM is loaded' error, it means DSPy modules aren't")
IO.puts("picking up the configured LM. This could be because:")
IO.puts("1. The API key isn't valid")
IO.puts("2. DSPy can't connect to the LLM provider")
IO.puts("3. The LM configuration isn't being passed correctly")