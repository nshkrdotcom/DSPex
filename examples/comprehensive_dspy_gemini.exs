#!/usr/bin/env elixir

# Comprehensive DSPy + DSPex Example with Gemini 2.5 Flash
# 
# This example showcases both native DSPex features and Python DSPy integration
# Run with: elixir examples/comprehensive_dspy_gemini.exs

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)}
])

defmodule ComprehensiveDSPyGemini do
  @moduledoc """
  A comprehensive example showing DSPex native features and Python DSPy integration.
  """

  alias DSPex.{Native, LLM}

  def run do
    IO.puts("🚀 === Comprehensive DSPy + DSPex with Gemini ===\n")
    
    # Load config
    config_path = Path.join(__DIR__, "config.exs")
    config_data = Code.eval_file(config_path) |> elem(0)
    api_key = config_data.api_key
    
    unless api_key do
      IO.puts("❌ Error: Please set GEMINI_API_KEY environment variable")
      System.halt(1)
    end

    # Part 1: Native DSPex Features
    demo_native_features(api_key, config_data)
    
    # Part 2: Python DSPy Integration
    demo_python_dspy(api_key, config_data)
    
    # Part 3: Mixed Pipeline
    demo_mixed_pipeline(api_key, config_data)
    
    IO.puts("\n✅ === Comprehensive Example Complete ===")
  end

  # === Part 1: Native DSPex Features ===
  
  defp demo_native_features(api_key, config_data) do
    IO.puts("\n🔧 === Part 1: Native DSPex Features ===\n")
    
    # Start DSPex
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure LLM client
    {:ok, client} = LLM.Client.new([
      adapter: :gemini,
      provider: :gemini,
      api_key: api_key,
      model: config_data.model,
      temperature: 0.7,
      max_tokens: 1024
    ])
    
    # 1.1 Signature Parsing
    IO.puts("📝 1.1 Native Signature Parsing:")
    demo_signatures()
    
    # 1.2 Template Engine
    IO.puts("\n🎨 1.2 Native Template Engine:")
    demo_templates(client)
    
    # 1.3 Validation
    IO.puts("\n✅ 1.3 Native Validation:")
    demo_validation()
  end

  defp demo_signatures do
    signatures = [
      "question -> answer",
      "context, question -> reasoning: str, answer: str, confidence: float",
      "document: str -> summary: str, keywords: list[str], sentiment: str"
    ]
    
    Enum.each(signatures, fn sig_str ->
      case Native.Signature.parse(sig_str) do
        {:ok, signature} ->
          IO.puts("   ✅ #{sig_str}")
          IO.puts("      Inputs: #{Enum.map_join(signature.inputs, ", ", & &1.name)}")
          IO.puts("      Outputs: #{Enum.map_join(signature.outputs, ", ", & &1.name)}")
        {:error, reason} ->
          IO.puts("   ❌ #{sig_str} - Error: #{reason}")
      end
    end)
  end

  defp demo_templates(client) do
    # Compile template
    template_str = """
    Task: Answer the question based on the context.
    
    Context: <%= @context %>
    Question: <%= @question %>
    
    Instructions: Provide a clear, concise answer based only on the given context.
    
    Answer:
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    IO.puts("   ✅ Template compiled successfully")
    
    # Render and execute
    vars = %{
      context: "The Eiffel Tower is located in Paris, France. It was built in 1889.",
      question: "Where is the Eiffel Tower located?"
    }
    
    prompt = template.(vars)
    IO.puts("   ✅ Template rendered successfully")
    
    # Get LLM response
    case LLM.Client.generate(client, prompt) do
      {:ok, response} ->
        IO.puts("   ✅ LLM Response: #{String.slice(response.content, 0, 100)}...")
      {:error, reason} ->
        IO.puts("   ❌ LLM Error: #{inspect(reason)}")
    end
  end

  defp demo_validation do
    {:ok, signature} = Native.Signature.parse("question -> answer: str, confidence: float")
    
    test_outputs = [
      %{"answer" => "Paris", "confidence" => 0.95},
      %{"answer" => "Paris", "confidence" => "high"},  # Wrong type
      %{"answer" => 42, "confidence" => 0.9},         # Wrong type
      %{"answer" => "Paris"}                          # Missing field
    ]
    
    Enum.with_index(test_outputs, 1)
    |> Enum.each(fn {output, idx} ->
      case Native.Validator.validate_output(output, signature) do
        :ok ->
          IO.puts("   ✅ Test #{idx}: Valid - #{inspect(output)}")
        {:error, errors} ->
          IO.puts("   ❌ Test #{idx}: Invalid - #{Enum.join(errors, ", ")}")
      end
    end)
  end

  # === Part 2: Python DSPy Integration ===
  
  defp demo_python_dspy(api_key, config_data) do
    IO.puts("\n\n🐍 === Part 2: Python DSPy Integration ===\n")
    
    # Configure enhanced bridge
    configure_enhanced_bridge()
    
    # Configure DSPy
    IO.puts("⚙️  2.1 Configuring Python DSPy:")
    configure_dspy(api_key, config_data)
    
    # Create DSPy modules
    IO.puts("\n📚 2.2 Creating DSPy Modules:")
    create_dspy_modules()
    
    # Make predictions
    IO.puts("\n🧠 2.3 DSPy Predictions:")
    make_dspy_predictions()
  end

  defp configure_enhanced_bridge do
    Application.put_env(:snakepit, :pooling_enabled, true)
    Application.put_env(:snakepit, :adapter_module, Snakepit.Adapters.EnhancedPython)
    Application.put_env(:snakepit, :pool_config, %{pool_size: 2})
    
    # Restart applications
    Application.stop(:snakepit)
    Application.stop(:dspex)
    {:ok, _} = Application.ensure_all_started(:dspex)
    {:ok, _} = Application.ensure_all_started(:snakepit)
    
  end

  defp configure_dspy(api_key, config_data) do
    case Snakepit.execute("configure_lm", %{
      "provider" => "google",
      "api_key" => api_key,
      "model" => config_data.model
    }) do
      {:ok, result} ->
        IO.puts("   ✅ DSPy configured with Gemini")
        IO.puts("   📄 Status: #{result["status"]}")
      {:error, reason} ->
        IO.puts("   ❌ Configuration failed: #{inspect(reason)}")
    end
  end

  defp create_dspy_modules do
    # Create Predict module
    case Snakepit.execute("call", %{
      "target" => "dspy.Predict",
      "args" => ["question -> answer"],
      "store_as" => "qa_predictor"
    }) do
      {:ok, result} ->
        IO.puts("   ✅ Predict module created")
        IO.puts("   🏷️  Stored as: #{result["stored_as"]}")
      {:error, reason} ->
        IO.puts("   ❌ Module creation failed: #{inspect(reason)}")
    end
    
    # Create ChainOfThought module
    case Snakepit.execute("call", %{
      "target" => "dspy.ChainOfThought",
      "args" => ["question -> reasoning, answer"],
      "store_as" => "cot_predictor"
    }) do
      {:ok, result} ->
        IO.puts("   ✅ ChainOfThought module created")
        IO.puts("   🏷️  Stored as: #{result["stored_as"]}")
      {:error, reason} ->
        IO.puts("   ❌ Module creation failed: #{inspect(reason)}")
    end
  end

  defp make_dspy_predictions do
    # Simple prediction
    question = "What is the capital of Japan?"
    IO.puts("   ❓ Question: #{question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.qa_predictor.__call__",
      "kwargs" => %{"question" => question}
    }) do
      {:ok, result} ->
        if result["result"] && result["result"]["prediction_data"] do
          answer = result["result"]["prediction_data"]["answer"]
          IO.puts("   💡 Answer: #{answer}")
        end
      {:error, reason} ->
        IO.puts("   ❌ Prediction failed: #{inspect(reason)}")
    end
    
    # Chain of Thought
    complex_question = "Why do birds migrate?"
    IO.puts("\n   ❓ Complex Question: #{complex_question}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.cot_predictor.__call__",
      "kwargs" => %{"question" => complex_question}
    }) do
      {:ok, result} ->
        if result["result"] && result["result"]["prediction_data"] do
          reasoning = result["result"]["prediction_data"]["reasoning"]
          answer = result["result"]["prediction_data"]["answer"]
          IO.puts("   🤔 Reasoning: #{String.slice(reasoning, 0, 150)}...")
          IO.puts("   💡 Answer: #{answer}")
        end
      {:error, reason} ->
        IO.puts("   ❌ Chain of Thought failed: #{inspect(reason)}")
    end
  end

  # === Part 3: Mixed Pipeline ===
  
  defp demo_mixed_pipeline(_api_key, _config_data) do
    IO.puts("\n\n🔀 === Part 3: Mixed DSPex + DSPy Pipeline ===\n")
    
    # This demonstrates how to combine native and Python components
    IO.puts("This example shows how native DSPex and Python DSPy can work together:")
    IO.puts("1. Use native signature parsing for speed")
    IO.puts("2. Use Python DSPy for complex reasoning")
    IO.puts("3. Use native validation for output checking")
    
    # Example: Research Assistant Pipeline
    IO.puts("\n📚 Research Assistant Pipeline:")
    
    # Step 1: Native signature parsing
    {:ok, signature} = Native.Signature.parse(
      "topic: str -> research_questions: list[str], summary: str"
    )
    IO.puts("   ✅ Step 1: Native signature parsed")
    
    # Step 2: Python DSPy for research
    topic = "quantum computing applications"
    IO.puts("   🔍 Step 2: Using DSPy for research on: #{topic}")
    
    case Snakepit.execute("call", %{
      "target" => "stored.cot_predictor.__call__",
      "kwargs" => %{
        "question" => "Generate 3 research questions and a brief summary about: #{topic}"
      }
    }) do
      {:ok, result} ->
        if result["result"] && result["result"]["prediction_data"] do
          answer = result["result"]["prediction_data"]["answer"]
          IO.puts("   📝 Research output: #{String.slice(answer, 0, 200)}...")
          
          # Step 3: Native validation (in real usage, would parse the output)
          mock_output = %{
            "research_questions" => [
              "How can quantum computing revolutionize cryptography?",
              "What are the current limitations of quantum computers?",
              "Which industries will benefit most from quantum computing?"
            ],
            "summary" => "Quantum computing uses quantum mechanics principles..."
          }
          
          case Native.Validator.validate_output(mock_output, signature) do
            :ok ->
              IO.puts("   ✅ Step 3: Output validated successfully")
            {:error, errors} ->
              IO.puts("   ❌ Step 3: Validation failed: #{Enum.join(errors, ", ")}")
          end
        end
      {:error, reason} ->
        IO.puts("   ❌ Research failed: #{inspect(reason)}")
    end
  end
end

# Run the comprehensive example
ComprehensiveDSPyGemini.run()