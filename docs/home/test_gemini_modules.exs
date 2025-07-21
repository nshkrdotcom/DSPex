# Test script to verify Gemini configuration and module fixes
# Run with: mix run test_gemini_modules.exs

# Configure Snakepit for pooling
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :wire_protocol, :auto)
Application.put_env(:snakepit, :pool_config, %{pool_size: 1})

# Stop and restart applications if already started
Application.stop(:dspex)
Application.stop(:snakepit)

# Start required applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Configure Gemini 2.0 Flash
api_key = System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
if api_key do
  IO.puts("✅ API key found, configuring Gemini 2.0 Flash...")
  case DSPex.LM.configure("gemini/gemini-2.0-flash", api_key: api_key) do
    {:ok, _} -> IO.puts("✅ Gemini configured successfully!")
    {:error, error} -> IO.puts("❌ Configuration error: #{inspect(error)}")
  end
else
  IO.puts("❌ No API key found!")
  System.halt(1)
end

# Test 1: Basic Predict
IO.puts("\n1. Testing Basic Predict...")
case DSPex.Modules.Predict.create("question -> answer") do
  {:ok, predictor} ->
    IO.puts("✅ Predict module created")
    case DSPex.Modules.Predict.execute(predictor, %{question: "What is 2+2?"}) do
      {:ok, result} -> 
        IO.puts("✅ Predict executed: #{inspect(Map.get(result, "answer") || Map.get(result, :answer))}")
      {:error, error} -> 
        IO.puts("❌ Predict error: #{inspect(error)}")
    end
  {:error, error} ->
    IO.puts("❌ Failed to create Predict: #{inspect(error)}")
end

# Test 2: ChainOfThought
IO.puts("\n2. Testing ChainOfThought...")
case DSPex.Modules.ChainOfThought.create("question -> answer") do
  {:ok, cot} ->
    IO.puts("✅ ChainOfThought module created")
    case DSPex.Modules.ChainOfThought.execute(cot, %{question: "Explain why the sky is blue"}) do
      {:ok, result} -> 
        IO.puts("✅ ChainOfThought executed")
        IO.puts("   Reasoning: #{String.slice(inspect(Map.get(result, "reasoning") || Map.get(result, :reasoning) || ""), 0, 100)}...")
      {:error, error} -> 
        IO.puts("❌ ChainOfThought error: #{inspect(error)}")
    end
  {:error, error} ->
    IO.puts("❌ Failed to create ChainOfThought: #{inspect(error)}")
end

# Test 3: ProgramOfThought (should work now)
IO.puts("\n3. Testing ProgramOfThought...")
case DSPex.Modules.ProgramOfThought.create("problem -> code, explanation") do
  {:ok, pot} ->
    IO.puts("✅ ProgramOfThought module created")
    case DSPex.Modules.ProgramOfThought.execute(pot, %{problem: "Write a function to calculate factorial"}) do
      {:ok, result} -> 
        IO.puts("✅ ProgramOfThought executed")
        IO.puts("   Code: #{String.slice(inspect(Map.get(result, "code") || Map.get(result, :code) || ""), 0, 50)}...")
      {:error, error} -> 
        IO.puts("❌ ProgramOfThought error: #{inspect(error)}")
    end
  {:error, error} ->
    IO.puts("❌ Failed to create ProgramOfThought: #{inspect(error)}")
end

# Test 4: Retry (using ChainOfThought fallback)
IO.puts("\n4. Testing Retry module (using ChainOfThought fallback)...")
case DSPex.Modules.Retry.create("task -> solution", max_attempts: 2) do
  {:ok, retry} ->
    IO.puts("✅ Retry module created (using ChainOfThought)")
    case DSPex.Modules.Retry.execute(retry, %{task: "Write a haiku about Elixir"}) do
      {:ok, result} -> 
        IO.puts("✅ Retry executed: #{inspect(Map.get(result, "solution") || Map.get(result, :solution))}")
      {:error, error} -> 
        IO.puts("❌ Retry error: #{inspect(error)}")
    end
  {:error, error} ->
    IO.puts("❌ Failed to create Retry: #{inspect(error)}")
end

IO.puts("\n✅ All tests completed!")