#!/usr/bin/env elixir

# Adapter Comparison Demo
# Shows the difference between EnhancedPython (stdin/stdout) and GRPCPython adapters

# Run with: mix run examples/dspy/adapter_comparison.exs

require Logger

IO.puts("📊 DSPex Adapter Comparison")
IO.puts("=" <> String.duplicate("=", 60))

defmodule AdapterDemo do
  def test_adapter(adapter_module, adapter_name) do
    IO.puts("\n🔧 Testing #{adapter_name}")
    IO.puts("-" <> String.duplicate("-", 40))
    
    # Configure adapter
    Application.put_env(:snakepit, :adapter_module, adapter_module)
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :pool_config, %{pool_size: 1})
    
    # Stop if running
    Application.stop(:dspex)
    Application.stop(:snakepit)
    
    # Start fresh
    {:ok, _} = Application.ensure_all_started(:snakepit)
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Initialize DSPex
    {:ok, _} = DSPex.Config.init()
    
    # Check adapter capabilities
    IO.puts("Module: #{inspect(adapter_module)}")
    
    has_grpc = if function_exported?(adapter_module, :uses_grpc?, 0) do
      adapter_module.uses_grpc?()
    else
      false
    end
    
    IO.puts("Uses gRPC: #{has_grpc}")
    IO.puts("Supports streaming: #{has_grpc}")
    
    # Load config and configure LM
    config_path = Path.join(__DIR__, "config.exs")
    config = Code.eval_file(config_path) |> elem(0)
    
    case DSPex.LM.configure(config.model, api_key: config.api_key) do
      {:ok, :configured} ->
        IO.puts("✓ LM configured")
        
        # Run a simple test
        {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
        
        start_time = System.monotonic_time(:millisecond)
        {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{
          question: "What is 2+2?"
        })
        end_time = System.monotonic_time(:millisecond)
        
        answer = result["result"]["prediction_data"]["answer"]
        IO.puts("✓ Test passed - Answer: #{answer}")
        IO.puts("⏱️  Time: #{end_time - start_time}ms")
        
      {:error, error} ->
        IO.puts("✗ Failed to configure: #{inspect(error)}")
    end
    
    # Cleanup
    Application.stop(:dspex)
    Application.stop(:snakepit)
    
    :ok
  end
end

# Test both adapters
IO.puts("\n📋 Available Adapters:")
IO.puts("1. EnhancedPython - stdin/stdout protocol, no streaming")
IO.puts("2. GRPCPython - gRPC protocol, supports streaming")

# Test Enhanced adapter
AdapterDemo.test_adapter(Snakepit.Adapters.EnhancedPython, "Enhanced Python (stdin/stdout)")

# Small pause between tests
Process.sleep(1000)

# Test gRPC adapter  
AdapterDemo.test_adapter(Snakepit.Adapters.GRPCPython, "gRPC Python")

IO.puts("\n📊 Summary:")
IO.puts("- EnhancedPython: Good for simple request/response, lower overhead")
IO.puts("- GRPCPython: Better for high throughput, supports streaming")
IO.puts("- Both work with DSPy, but DSPy itself doesn't stream")

IO.puts("\n✅ Comparison complete!")