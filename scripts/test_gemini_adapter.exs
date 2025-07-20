#!/usr/bin/env elixir

# Test script for Gemini adapter

Mix.install([
  {:dspex, path: "."},
  {:gemini_ex, "~> 0.0.3"},
  {:sinter, "~> 0.0.1"}
])

# Start applications
Application.ensure_all_started(:req)
Application.ensure_all_started(:gemini_ex)

defmodule TestGemini do
  def run do
    IO.puts("\n=== Testing Gemini Adapter ===\n")
    
    # Test 1: Basic configuration
    IO.puts("1. Testing configuration...")
    
    config = [
      api_key: System.get_env("GEMINI_API_KEY"),
      model: "gemini/gemini-2.0-flash-exp"
    ]
    
    case DSPex.LLM.Adapters.Gemini.configure(:gemini, config) do
      {:ok, client} ->
        IO.puts("✓ Configuration successful")
        IO.inspect(client, label: "Client config")
        
        # Test 2: Basic generation
        IO.puts("\n2. Testing basic generation...")
        test_generation(client)
        
        # Test 3: Streaming
        IO.puts("\n3. Testing streaming...")
        test_streaming(client)
        
        # Test 4: Batch generation
        IO.puts("\n4. Testing batch generation...")
        test_batch(client)
        
      {:error, reason} ->
        IO.puts("✗ Configuration failed: #{inspect(reason)}")
        IO.puts("\nMake sure to set GEMINI_API_KEY environment variable")
    end
  end
  
  defp test_generation(client) do
    prompt = "Write a haiku about Elixir programming"
    
    case DSPex.LLM.Adapters.Gemini.generate(client, prompt, []) do
      {:ok, response} ->
        IO.puts("✓ Generation successful")
        IO.puts("Response: #{response.content}")
        IO.puts("Model: #{response.model}")
        IO.puts("Adapter: #{response.adapter}")
        
      {:error, reason} ->
        IO.puts("✗ Generation failed: #{inspect(reason)}")
    end
  end
  
  defp test_streaming(client) do
    prompt = "Count from 1 to 5 slowly"
    
    # Define callbacks to handle streaming chunks
    on_chunk = fn chunk -> 
      # Extract text from the chunk if it's a map
      text = case chunk do
        %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]} ->
          text
        text when is_binary(text) ->
          text
        _ ->
          ""
      end
      IO.write(text)
    end
    
    on_complete = fn -> 
      IO.puts("\n✓ Streaming completed")
    end
    
    case DSPex.LLM.Adapters.Gemini.stream(client, prompt, [on_chunk: on_chunk, on_complete: on_complete]) do
      {:ok, _result} ->
        IO.puts("✓ Streaming started")
        
      {:error, reason} ->
        IO.puts("✗ Streaming failed: #{inspect(reason)}")
    end
  end
  
  defp test_batch(client) do
    prompts = [
      "What is 2+2?",
      "What is the capital of France?",
      "Name a primary color"
    ]
    
    case DSPex.LLM.Adapters.Gemini.batch(client, prompts, []) do
      {:ok, responses} ->
        IO.puts("✓ Batch generation successful")
        
        Enum.with_index(responses, fn response, i ->
          IO.puts("Response #{i + 1}: #{response.content}")
        end)
        
      {:error, reason} ->
        IO.puts("✗ Batch generation failed: #{inspect(reason)}")
    end
  end
end

TestGemini.run()