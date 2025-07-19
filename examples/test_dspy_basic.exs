#!/usr/bin/env elixir

# Basic test to verify DSPex + DSPy integration works

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:gemini_ex, "~> 0.0.3"},
  {:snakepit, github: "nshkrdotcom/snakepit"}
])

defmodule BasicDSPyTest do
  def run do
    IO.puts("🧪 === Basic DSPy Integration Test ===\n")
    
    # Check if API key is available
    api_key = System.get_env("GEMINI_API_KEY")
    if api_key do
      IO.puts("✅ GEMINI_API_KEY found")
    else
      IO.puts("⚠️  GEMINI_API_KEY not set - will test without LLM calls")
    end
    
    # Start applications
    {:ok, _} = Application.ensure_all_started(:dspex)
    {:ok, _} = Application.ensure_all_started(:snakepit)
    IO.puts("✅ Applications started")
    
    # Test native DSPex signature parsing
    IO.puts("\n🔧 Testing Native DSPex Features:")
    
    case DSPex.Native.Signature.parse("question -> answer") do
      {:ok, signature} ->
        IO.puts("✅ Signature parsing works")
        IO.puts("   Inputs: #{Enum.map(signature.inputs, &(&1.name)) |> Enum.join(", ")}")
        IO.puts("   Outputs: #{Enum.map(signature.outputs, &(&1.name)) |> Enum.join(", ")}")
      {:error, reason} ->
        IO.puts("❌ Signature parsing failed: #{reason}")
    end
    
    # Test Snakepit connectivity
    IO.puts("\n🐍 Testing Snakepit Integration:")
    
    test_code = """
    import sys
    print(f"Python version: {sys.version}")
    print("Python environment ready")
    
    # Test if DSPy is available
    try:
        import dspy
        print("DSPy is available")
        print(f"DSPy version: {dspy.__version__ if hasattr(dspy, '__version__') else 'unknown'}")
    except ImportError:
        print("DSPy not available - install with: pip install dspy")
    """
    
    case Snakepit.execute("exec", %{"code" => test_code}) do
      {:ok, result} ->
        IO.puts("✅ Snakepit execution works")
        if result["output"] do
          IO.puts("   Output:")
          String.split(result["output"], "\n")
          |> Enum.each(&IO.puts("     #{&1}"))
        end
      {:error, reason} ->
        IO.puts("❌ Snakepit execution failed: #{inspect(reason)}")
    end
    
    # Test DSPex LLM client (if API key available)
    if api_key do
      IO.puts("\n🤖 Testing DSPex LLM Client:")
      
      config = [
        adapter: :gemini,
        provider: :gemini,
        api_key: api_key,
        model: "gemini-2.0-flash-exp"
      ]
      
      case DSPex.LLM.Client.new(config) do
        {:ok, client} ->
          IO.puts("✅ LLM client created")
          
          # Test simple generation
          case DSPex.LLM.Client.generate(client, "What is 2+2?") do
            {:ok, response} ->
              IO.puts("✅ LLM generation works")
              IO.puts("   Response: #{String.slice(response.content, 0, 100)}...")
            {:error, reason} ->
              IO.puts("❌ LLM generation failed: #{inspect(reason)}")
          end
          
        {:error, reason} ->
          IO.puts("❌ LLM client creation failed: #{inspect(reason)}")
      end
    else
      IO.puts("\n⏭️  Skipping LLM tests - no API key")
    end
    
    IO.puts("\n✅ === Basic Test Complete ===")
  end
end

BasicDSPyTest.run()