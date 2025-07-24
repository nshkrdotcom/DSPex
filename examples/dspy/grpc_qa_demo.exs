#!/usr/bin/env elixir

# Simple Q&A demo using gRPC adapter (non-streaming)
# This shows how to use DSPy with the gRPC transport

# IMPORTANT: This requires gRPC dependencies to be compiled
# If you get errors, make sure to run: mix deps.get && mix deps.compile

# Run with: mix run examples/dspy/grpc_qa_demo.exs

require Logger

# First ensure applications are loaded
Application.load(:snakepit)
Application.load(:dspex)

# Configure Snakepit for gRPC with DSPy adapter
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.GRPCPython)
Application.put_env(:snakepit, :pool_config, %{
  pool_size: 1,
  # Use the DSPy-enabled gRPC adapter
  adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
})

# Configure gRPC settings
Application.put_env(:snakepit, :grpc_config, %{
  base_port: 50051,
  port_range: 100  # Will use ports 50051-50151
})

# Stop any running instances
Application.stop(:dspex)
Application.stop(:snakepit)

# Start fresh
{:ok, _} = Application.ensure_all_started(:snakepit)
{:ok, _} = Application.ensure_all_started(:dspex)

IO.puts("🚀 DSPy gRPC Demo")
IO.puts("=" <> String.duplicate("=", 60))

# Initialize DSPex
{:ok, _} = DSPex.Config.init()

# Check adapter and gRPC availability
adapter = Application.get_env(:snakepit, :adapter_module)
IO.puts("Using adapter: #{inspect(adapter)}")

# Check if gRPC is available
grpc_available = Code.ensure_loaded?(GRPC.Channel) and Code.ensure_loaded?(Protobuf)

if not grpc_available do
  IO.puts("\n❌ gRPC dependencies not available!")
  IO.puts("Please ensure gRPC is included in your dependencies and compiled:")
  IO.puts("  1. Add {:grpc, \"~> 0.9\"} to your mix.exs dependencies")
  IO.puts("  2. Run: mix deps.get && mix deps.compile")
  IO.puts("\nFalling back to simple_qa_demo.exs example...")
  System.halt(1)
end

if function_exported?(adapter, :uses_grpc?, 0) and adapter.uses_grpc?() do
  IO.puts("✓ gRPC adapter confirmed and available")
else
  IO.puts("✗ gRPC adapter configured but not available!")
  System.halt(1)
end

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

# Test basic DSPy operations over gRPC
defmodule GRPCDemo do
  def run_examples do
    IO.puts("\n1. Basic Prediction")
    IO.puts("-" <> String.duplicate("-", 40))
    
    {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
    {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{
      question: "What is the speed of light?"
    })
    
    # Extract the answer from the result
    answer = get_in(result, ["result", "outputs", "answer"]) || "No answer found"
    IO.puts("Q: What is the speed of light?")
    IO.puts("A: #{answer}")
    
    IO.puts("\n2. Chain of Thought")
    IO.puts("-" <> String.duplicate("-", 40))
    
    {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
    {:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{
      question: "Why is the sky blue?"
    })
    
    # Extract the reasoning and answer from the result
    reasoning = get_in(result, ["result", "outputs", "reasoning"]) || "No reasoning found"
    answer = get_in(result, ["result", "outputs", "answer"]) || "No answer found"
    
    IO.puts("Q: Why is the sky blue?")
    IO.puts("\nReasoning: #{reasoning}")
    IO.puts("\nAnswer: #{answer}")
    
    IO.puts("\n3. Multi-hop Reasoning")
    IO.puts("-" <> String.duplicate("-", 40))
    
    {:ok, multi} = DSPex.Modules.ChainOfThought.create("context, question -> answer")
    {:ok, result} = DSPex.Modules.ChainOfThought.execute(multi, %{
      context: "Paris is the capital of France. The Eiffel Tower is in Paris.",
      question: "In which country is the Eiffel Tower located?"
    })
    
    # Extract the answer from the result
    answer = get_in(result, ["result", "outputs", "answer"]) || "No answer found"
    IO.puts("Context: Paris is the capital of France. The Eiffel Tower is in Paris.")
    IO.puts("Q: In which country is the Eiffel Tower located?")
    IO.puts("A: #{answer}")
  end
end

# Run the examples
try do
  GRPCDemo.run_examples()
  IO.puts("\n✅ gRPC demo completed successfully!")
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