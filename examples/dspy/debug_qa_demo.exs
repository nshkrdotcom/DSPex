#!/usr/bin/env elixir

# Debug Q&A demo to understand what's happening
# Run with: mix run examples/dspy/debug_qa_demo.exs

require Logger

# Ensure applications are loaded
Application.load(:snakepit)
Application.load(:dspex)

# Configure Snakepit with EnhancedPython adapter
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
Application.put_env(:snakepit, :pool_config, %{pool_size: 1})

# Stop any running instances
Application.stop(:dspex)
Application.stop(:snakepit)

# Start fresh
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

IO.puts("🔍 Debug DSPy Q&A Demo")
IO.puts("=" <> String.duplicate("=", 60))

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Load configuration
config_path = Path.join(__DIR__, "config.exs")
config = Code.eval_file(config_path) |> elem(0)

IO.puts("\nConfiguration:")
IO.inspect(config, label: "Config")

# Configure the language model
IO.puts("\nConfiguring language model...")
case DSPex.LM.configure(config.model, api_key: config.api_key) do
  {:ok, :configured} ->
    IO.puts("✓ Language model configured successfully")
    
  {:error, error} ->
    IO.puts("✗ Failed to configure LM: #{inspect(error)}")
    System.halt(1)
end

# Test basic prediction with full debugging
IO.puts("\n📝 Testing Basic Prediction:")
IO.puts("-" <> String.duplicate("-", 40))

# Create a predictor
{:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
IO.puts("✓ Predictor created: #{predictor}")

# Execute a simple question
question = "What is 2+2?"
IO.puts("\nQ: #{question}")

case DSPex.Modules.Predict.execute(predictor, %{question: question}) do
  {:ok, result} ->
    IO.puts("\n📊 Full result structure:")
    IO.inspect(result, label: "Result", pretty: true, limit: :infinity)
    
    # Try different paths to find the answer
    paths = [
      ["result", "prediction_data", "answer"],
      ["prediction_data", "answer"],
      ["result", "attributes", "answer", "value"],
      ["result", "answer"],
      ["answer"]
    ]
    
    IO.puts("\n🔍 Trying different paths:")
    Enum.each(paths, fn path ->
      value = get_in(result, path)
      IO.puts("  #{inspect(path)} => #{inspect(value)}")
    end)
    
    # Final answer extraction
    answer = get_in(result, ["result", "prediction_data", "answer"]) || 
             get_in(result, ["prediction_data", "answer"]) ||
             get_in(result, ["answer"]) ||
             "No answer found"
    
    IO.puts("\n💡 Final answer: #{answer}")
    
  {:error, error} ->
    IO.puts("\n❌ Error:")
    IO.inspect(error, pretty: true)
end

# Test DSPy settings
IO.puts("\n📋 Checking DSPy configuration:")
case Snakepit.Python.call("dspy.settings.__dict__", %{}) do
  {:ok, settings} ->
    IO.inspect(settings, label: "DSPy settings", pretty: true)
    
  {:error, error} ->
    IO.puts("Failed to get DSPy settings: #{inspect(error)}")
end

# Graceful shutdown
IO.puts("\nShutting down...")
Application.stop(:dspex)
Application.stop(:snakepit)
IO.puts("Shutdown complete.")