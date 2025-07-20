# Simple script to debug DSPy response structure

# Start applications
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Configure Gemini 2.0 Flash as default if available
api_key = System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
if api_key do
  IO.puts("✓ Configuring Gemini 2.0 Flash...")
  DSPex.LM.configure("gemini/gemini-2.0-flash", api_key: api_key)
  IO.puts("  Successfully configured!")
else
  IO.puts("⚠️  No API key found - using mock LM")
  DSPex.LM.configure("mock/gemini")
end

# Test a simple DSPy prediction
IO.puts("\n=== Testing DSPy Response Structure ===")

{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
{:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is 2+2?"})

IO.puts("\n--- Raw Response ---")
IO.inspect(result, pretty: true, limit: :infinity)

IO.puts("\n--- Keys in Response ---")
if is_map(result) do
  IO.inspect(Map.keys(result))
else
  IO.puts("Response is not a map: #{inspect(result)}")
end

# Try different access patterns
IO.puts("\n--- Testing Different Access Patterns ---")
IO.puts("result[\"prediction_data\"][\"answer\"]: #{inspect(get_in(result, ["prediction_data", "answer"]))}")
IO.puts("result[\"answer\"]: #{inspect(get_in(result, ["answer"]))}")
IO.puts("result.answer: #{inspect(Map.get(result, "answer"))}")
IO.puts("result[:answer]: #{inspect(Map.get(result, :answer))}")

# If it's nested, check what's inside prediction_data
if is_map(result) and Map.has_key?(result, "prediction_data") do
  IO.puts("\n--- Prediction Data Contents ---")
  IO.inspect(result["prediction_data"], pretty: true)
end