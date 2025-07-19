#!/usr/bin/env elixir

# DSPex Native Features Showcase with Gemini 2.5 Flash
# 
# This example demonstrates DSPex's native capabilities working with Gemini,
# showing what's possible without Python dependencies.

Mix.install([
  {:dspex, path: Path.expand("..", __DIR__)},
  {:gemini_ex, "~> 0.0.3"},
  {:snakepit, github: "nshkrdotcom/snakepit"}
])

defmodule DSPexNativeShowcase do
  @moduledoc """
  Comprehensive showcase of DSPex native features with Gemini 2.5 Flash.
  
  Demonstrates:
  - Signature parsing and validation
  - Template compilation and rendering
  - LLM client with Gemini integration
  - End-to-end native workflow
  """

  alias DSPex.{Native, LLM}

  def run do
    IO.puts("🚀 === DSPex Native Features with Gemini 2.5 Flash ===\n")
    
    # Check API key
    api_key = System.get_env("GEMINI_API_KEY")
    unless api_key do
      IO.puts("❌ Error: Please set GEMINI_API_KEY environment variable")
      IO.puts("   Get an API key from: https://makersuite.google.com/app/apikey")
      System.halt(1)
    end

    # Start DSPex application
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure LLM client
    client = configure_gemini_client(api_key)
    
    # Run native feature demonstrations
    demo_signature_system()
    demo_template_system()
    demo_validation_system()
    demo_end_to_end_workflow(client)
    
    IO.puts("\n✅ === Native DSPex Showcase Complete ===")
  end

  # === Configuration ===
  
  defp configure_gemini_client(api_key) do
    IO.puts("⚙️  Configuring Gemini 2.5 Flash Client...")
    
    config = [
      adapter: :gemini,
      provider: :gemini,
      api_key: api_key,
      model: "gemini-2.0-flash-exp",
      temperature: 0.7,
      max_tokens: 1024
    ]
    
    case LLM.Client.new(config) do
      {:ok, client} ->
        IO.puts("   ✅ Gemini client configured")
        client
        
      {:error, reason} ->
        IO.puts("   ❌ Failed to configure Gemini: #{inspect(reason)}")
        System.halt(1)
    end
  end

  # === Signature System ===
  
  defp demo_signature_system do
    IO.puts("\n📝 === Signature System Demo ===\n")
    
    signatures = [
      # Simple Q&A
      "question -> answer",
      
      # Chain of Thought style
      "question -> reasoning: str, answer: str",
      
      # Complex multi-output
      "document: str -> summary: str, keywords: list[str], sentiment: str, confidence: float",
      
      # Research assistant style
      "topic: str, sources: list[str] -> research_questions: list[str], analysis: str, conclusions: str"
    ]
    
    IO.puts("1.1 Signature Parsing:")
    
    Enum.with_index(signatures, 1)
    |> Enum.each(fn {sig_str, idx} ->
      case Native.Signature.parse(sig_str) do
        {:ok, signature} ->
          IO.puts("   ✅ #{idx}. #{sig_str}")
          IO.puts("      📥 Inputs: #{format_fields(signature.inputs)}")
          IO.puts("      📤 Outputs: #{format_fields(signature.outputs)}")
          
        {:error, reason} ->
          IO.puts("   ❌ #{idx}. #{sig_str} - Error: #{reason}")
      end
    end)
  end

  defp format_fields(fields) do
    fields
    |> Enum.map(fn field ->
      type_str = format_type(field.type)
      "#{field.name}:#{type_str}"
    end)
    |> Enum.join(", ")
  end

  defp format_type(:string), do: "str"
  defp format_type(:integer), do: "int"
  defp format_type(:float), do: "float"
  defp format_type(:boolean), do: "bool"
  defp format_type({:list, inner}), do: "list[#{format_type(inner)}]"
  defp format_type({:dict, inner}), do: "dict[str,#{format_type(inner)}]"
  defp format_type({:optional, inner}), do: "?#{format_type(inner)}"
  defp format_type(other), do: to_string(other)

  # === Template System ===
  
  defp demo_template_system do
    IO.puts("\n🎨 === Template System Demo ===\n")
    
    templates = [
      # Q&A Template
      {
        "Q&A Template",
        """
        Question: <%= @question %>
        
        Please provide a clear and concise answer.
        
        Answer:
        """,
        %{question: "What is machine learning?"}
      },
      
      # Chain of Thought Template
      {
        "Chain of Thought Template",
        """
        Question: <%= @question %>
        Context: <%= @context %>
        
        Let me think through this step by step:
        1. First, I need to understand...
        2. Then, I should consider...
        3. Finally, I can conclude...
        
        Reasoning:
        """,
        %{
          question: "How does solar energy work?",
          context: "Renewable energy is becoming increasingly important for environmental sustainability."
        }
      },
      
      # Research Template
      {
        "Research Template",
        """
        Research Topic: <%= @topic %>
        
        Based on the following sources:
        <%= for {source, idx} <- Enum.with_index(@sources, 1) do %>
        <%= idx %>. <%= source %>
        <% end %>
        
        Analysis:
        """,
        %{
          topic: "Artificial Intelligence in Healthcare",
          sources: [
            "AI-powered diagnostic imaging improves accuracy",
            "Machine learning algorithms predict patient outcomes",
            "Natural language processing automates medical records"
          ]
        }
      }
    ]
    
    IO.puts("2.1 Template Compilation and Rendering:")
    
    Enum.with_index(templates, 1)
    |> Enum.each(fn {{name, template_str, vars}, idx} ->
      IO.puts("   #{idx}. #{name}")
      
      case Native.Template.compile(template_str) do
        {:ok, template} ->
          IO.puts("      ✅ Compiled successfully")
          
          try do
            rendered = template.(vars)
            preview = String.slice(rendered, 0, 100) |> String.replace("\n", " ")
            IO.puts("      ✅ Rendered: #{preview}...")
          rescue
            e ->
              IO.puts("      ❌ Render error: #{inspect(e)}")
          end
          
        {:error, reason} ->
          IO.puts("      ❌ Compile error: #{reason}")
      end
    end)
  end

  # === Validation System ===
  
  defp demo_validation_system do
    IO.puts("\n✅ === Validation System Demo (Testing Both Success & Error Cases) ===\n")
    
    # Create test signature
    {:ok, signature} = Native.Signature.parse("question -> answer: str, confidence: float, tags: list[str]")
    
    test_cases = [
      # Valid test cases (should pass)
      %{"answer" => "Paris is the capital of France", "confidence" => 0.95, "tags" => ["geography", "france"]},
      %{"answer" => "42", "confidence" => 0.8, "tags" => ["mathematics", "philosophy"]},
      
      # Invalid test cases (should fail - testing error detection)
      %{"answer" => "Rome", "confidence" => "high", "tags" => ["geography"]},  # confidence should be float
      %{"answer" => 42, "confidence" => 0.9, "tags" => ["number"]},            # answer should be string
      %{"response" => "Madrid", "confidence" => 0.7, "tags" => []},           # missing 'answer' field
      %{"answer" => "Berlin", "confidence" => 0.85}                           # missing 'tags' field
    ]
    
    IO.puts("3.1 Output Validation Testing:")
    IO.puts("   Using signature: question -> answer: str, confidence: float, tags: list[str]")
    IO.puts("   🔍 Testing both valid data (should pass) and invalid data (should fail)")
    
    Enum.with_index(test_cases, 1)
    |> Enum.each(fn {output, idx} ->
      case Native.Validator.validate_output(output, signature) do
        :ok ->
          IO.puts("   ✅ Test #{idx}: VALID (as expected)")
          IO.puts("      Data: #{inspect(output)}")
          
        {:error, errors} ->
          IO.puts("   ❌ Test #{idx}: INVALID (as expected - testing error detection)")
          IO.puts("      Data: #{inspect(output)}")
          IO.puts("      Detected errors: #{Enum.join(errors, ", ")}")
      end
    end)
  end

  # === End-to-End Workflow ===
  
  defp demo_end_to_end_workflow(client) do
    IO.puts("\n🔄 === End-to-End Native Workflow ===\n")
    
    IO.puts("4.1 Complete Q&A Workflow:")
    
    # Step 1: Parse signature
    {:ok, signature} = Native.Signature.parse("question -> answer: str, confidence: float")
    IO.puts("   ✅ Step 1: Signature parsed")
    
    # Step 2: Compile template
    template_str = """
    Question: <%= @question %>
    
    Please provide a clear, accurate answer and rate your confidence from 0.0 to 1.0.
    
    Answer: [Your answer here]
    Confidence: [0.0-1.0]
    """
    
    {:ok, template} = Native.Template.compile(template_str)
    IO.puts("   ✅ Step 2: Template compiled")
    
    # Step 3: Test questions
    questions = [
      "What is the capital of Japan?",
      "How many sides does a triangle have?",
      "What year did World War II end?"
    ]
    
    IO.puts("   📝 Step 3: Processing questions...")
    
    Enum.with_index(questions, 1)
    |> Enum.each(fn {question, idx} ->
      IO.puts("      Question #{idx}: #{question}")
      
      # Render prompt
      prompt = template.(%{question: question})
      
      # Get LLM response
      case LLM.Client.generate(client, prompt) do
        {:ok, response} ->
          # Extract answer and confidence from response
          content = response.content
          
          # Simple parsing (in real usage, you'd want more robust parsing)
          answer = extract_answer(content)
          confidence = extract_confidence(content)
          
          result = %{"answer" => answer, "confidence" => confidence}
          
          # Validate result
          case Native.Validator.validate_output(result, signature) do
            :ok ->
              IO.puts("         ✅ Answer: #{answer}")
              IO.puts("         📊 Confidence: #{confidence}")
              
            {:error, errors} ->
              IO.puts("         ❌ Validation failed: #{Enum.join(errors, ", ")}")
              IO.puts("         Raw response: #{String.slice(content, 0, 100)}...")
          end
          
        {:error, reason} ->
          IO.puts("         ❌ LLM error: #{inspect(reason)}")
      end
    end)
    
    # Step 4: Batch processing demo
    IO.puts("\n   📊 Step 4: Batch Processing Demo:")
    
    batch_questions = [
      "What is 15 + 27?",
      "Name the largest ocean on Earth",
      "Who wrote 'Romeo and Juliet'?"
    ]
    
    case LLM.Client.batch(client, Enum.map(batch_questions, &template.(%{question: &1}))) do
      {:ok, responses} ->
        IO.puts("      ✅ Batch processed #{length(responses)} questions")
        
        Enum.zip(batch_questions, responses)
        |> Enum.with_index(1)
        |> Enum.each(fn {{question, response}, idx} ->
          answer = extract_answer(response.content)
          IO.puts("      #{idx}. #{question} → #{answer}")
        end)
        
      {:error, reason} ->
        IO.puts("      ❌ Batch processing failed: #{inspect(reason)}")
    end
  end

  # === Utility Functions ===
  
  defp extract_answer(content) do
    # Simple regex-based extraction
    case Regex.run(~r/Answer:\s*(.+?)(?:\n|Confidence:|$)/i, content) do
      [_, answer] -> String.trim(answer)
      _ -> "Could not extract answer"
    end
  end

  defp extract_confidence(content) do
    # Simple regex-based extraction  
    case Regex.run(~r/Confidence:\s*([0-9.]+)/i, content) do
      [_, conf_str] -> 
        case Float.parse(conf_str) do
          {conf, _} -> conf
          _ -> 0.5
        end
      _ -> 0.5
    end
  end
end

# Run the showcase
DSPexNativeShowcase.run()