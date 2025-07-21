#!/usr/bin/env elixir

# Simple Q&A demo using default EnhancedPython adapter
# Run with: mix run examples/dspy/simple_qa_demo.exs

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

IO.puts("🚀 Simple DSPy Q&A Demo")
IO.puts("=" <> String.duplicate("=", 60))

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Load configuration
config_path = Path.join(__DIR__, "config.exs")
config = Code.eval_file(config_path) |> elem(0)

# Configure the language model
IO.puts("\nConfiguring language model...")
case DSPex.LM.configure(config.model, api_key: config.api_key) do
  {:ok, :configured} ->
    IO.puts("✓ Language model configured successfully")
    
  {:error, error} ->
    IO.puts("✗ Failed to configure LM: #{inspect(error)}")
    System.halt(1)
end

# Simple Q&A examples
defmodule QADemo do
  def run do
    questions = [
      "What is the capital of France?",
      "What is 25 * 4?",
      "Who wrote Romeo and Juliet?"
    ]
    
    IO.puts("\n📝 Running Q&A Examples:")
    IO.puts("-" <> String.duplicate("-", 40))
    
    # Create a predictor
    {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
    
    Enum.each(questions, fn question ->
      IO.puts("\nQ: #{question}")
      
      case DSPex.Modules.Predict.execute(predictor, %{question: question}) do
        {:ok, result} ->
          # Debug: show the full result structure
          # IO.inspect(result, label: "Full result")
          
          answer = get_in(result, ["result", "prediction_data", "answer"]) || "No answer found"
          IO.puts("A: #{answer}")
          
        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end)
  end
end

# Run the demo
try do
  QADemo.run()
  IO.puts("\n✅ Demo completed successfully!")
rescue
  e ->
    IO.puts("\n❌ Error during demo: #{inspect(e)}")
    IO.inspect(e, pretty: true)
end

# Graceful shutdown
IO.puts("\nShutting down...")
Application.stop(:dspex)
Application.stop(:snakepit)
IO.puts("Shutdown complete.")