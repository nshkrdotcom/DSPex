defmodule SignatureExample do
  @moduledoc """
  DSPex Dynamic Signature Example
  
  This module demonstrates the powerful dynamic signature capabilities of DSPex,
  showing how to create programs with custom input/output fields beyond the 
  basic "question → answer" pattern.
  
  Features demonstrated:
  - Multi-input signatures (text + style, text + target_language, etc.)
  - Multi-output signatures (sentiment + summary + keywords + confidence)
  - Dynamic signature generation and caching
  - Fallback mechanisms for reliability
  - Real-world use cases (analysis, translation, enhancement, creative writing)
  """

  require Logger
  alias DSPex.Adapters.Registry
  alias SignatureExample.Signatures

  @doc """
  Run a text analysis example using dynamic signatures.
  
  This demonstrates how DSPex can analyze text with multiple outputs:
  - Sentiment detection
  - Content summarization 
  - Keyword extraction
  - Confidence scoring
  """
  def run_text_analysis_example do
    Logger.info("🔍 Running Text Analysis Example with Dynamic Signatures")
    
    # Get the Python adapter
    adapter = Registry.get_adapter(:python_port)
    
    # Configure the language model
    configure_language_model(adapter)
    
    # Create a program with the text analysis signature
    signature = Signatures.text_analysis_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "text_analysis_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    Logger.info("✅ Created text analysis program: #{prog_id}")
    
    # Example inputs
    examples = [
      %{
        text: "The weather is absolutely beautiful today! Perfect for a picnic in the park.",
        style: "detailed"
      },
      %{
        text: "I'm really disappointed with the customer service. They kept me waiting for an hour.",
        style: "brief"
      },
      %{
        text: "Machine learning algorithms are revolutionizing the field of artificial intelligence through advanced neural network architectures.",
        style: "academic"
      }
    ]
    
    # Run analysis on each example
    Enum.each(examples, fn inputs ->
      Logger.info("\n📝 Analyzing: \"#{String.slice(inputs.text, 0, 50)}...\"")
      Logger.info("   Style: #{inputs.style}")
      
      case adapter.execute_program(prog_id, inputs) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Analysis Results:")
          Logger.info("   Sentiment: #{outputs["sentiment"] || outputs[:sentiment]}")
          Logger.info("   Summary: #{outputs["summary"] || outputs[:summary]}")
          Logger.info("   Keywords: #{outputs["keywords"] || outputs[:keywords]}")
          Logger.info("   Confidence: #{outputs["confidence_score"] || outputs[:confidence_score]}")
          
        {:error, reason} ->
          Logger.warning("⚠️  Analysis failed: #{inspect(reason)}")
      end
    end)
    
    Logger.info("\n🎉 Text Analysis Example Complete!")
  end

  @doc """
  Run a translation example using dynamic signatures.
  
  This demonstrates multi-language translation with:
  - Source language detection
  - Target language translation
  - Translation confidence scoring
  """
  def run_translation_example do
    Logger.info("🌍 Running Translation Example with Dynamic Signatures")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = Signatures.translation_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "translation_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    Logger.info("✅ Created translation program: #{prog_id}")
    
    # Translation examples
    examples = [
      %{text: "Hello, how are you today?", target_language: "spanish"},
      %{text: "The meeting is scheduled for 3 PM.", target_language: "french"},
      %{text: "Thank you for your help!", target_language: "german"}
    ]
    
    Enum.each(examples, fn inputs ->
      Logger.info("\n🔤 Translating: \"#{inputs.text}\"")
      Logger.info("   Target: #{inputs.target_language}")
      
      case adapter.execute_program(prog_id, inputs) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Translation Results:")
          Logger.info("   Translated: #{outputs["translated_text"] || outputs[:translated_text]}")
          Logger.info("   Source Language: #{outputs["source_language"] || outputs[:source_language]}")
          Logger.info("   Confidence: #{outputs["confidence_score"] || outputs[:confidence_score]}")
          
        {:error, reason} ->
          Logger.warning("⚠️  Translation failed: #{inspect(reason)}")
      end
    end)
    
    Logger.info("\n🎉 Translation Example Complete!")
  end

  @doc """
  Run a content enhancement example using dynamic signatures.
  
  This demonstrates text improvement with:
  - Content enhancement for clarity/engagement/formality
  - Tone adjustment (professional/casual/friendly)
  - Readability assessment
  """
  def run_content_enhancement_example do
    Logger.info("✨ Running Content Enhancement Example with Dynamic Signatures")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = Signatures.content_enhancement_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "enhancement_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    Logger.info("✅ Created content enhancement program: #{prog_id}")
    
    # Enhancement examples
    examples = [
      %{
        text: "The thing is that we need to do something about this problem maybe.",
        enhancement_type: "clarity",
        tone: "professional"
      },
      %{
        text: "This report contains data and stuff about sales.",
        enhancement_type: "engagement", 
        tone: "friendly"
      },
      %{
        text: "Hey, can you check this out when you get a chance?",
        enhancement_type: "formality",
        tone: "professional"
      }
    ]
    
    Enum.each(examples, fn inputs ->
      Logger.info("\n📝 Enhancing: \"#{inputs.text}\"")
      Logger.info("   Enhancement: #{inputs.enhancement_type}")
      Logger.info("   Tone: #{inputs.tone}")
      
      case adapter.execute_program(prog_id, inputs) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Enhancement Results:")
          Logger.info("   Enhanced: #{outputs["enhanced_text"] || outputs[:enhanced_text]}")
          Logger.info("   Changes: #{outputs["changes_made"] || outputs[:changes_made]}")
          Logger.info("   Readability: #{outputs["readability_score"] || outputs[:readability_score]}")
          
        {:error, reason} ->
          Logger.warning("⚠️  Enhancement failed: #{inspect(reason)}")
      end
    end)
    
    Logger.info("\n🎉 Content Enhancement Example Complete!")
  end

  @doc """
  Run a creative writing example using dynamic signatures.
  
  This demonstrates story generation with:
  - Genre-specific content creation
  - Theme analysis
  - Character counting
  """
  def run_creative_writing_example do
    Logger.info("📚 Running Creative Writing Example with Dynamic Signatures")
    
    adapter = Registry.get_adapter(:python_port)
    configure_language_model(adapter)
    
    signature = Signatures.creative_writing_signature()
    
    {:ok, prog_id} = adapter.create_program(%{
      id: "creative_#{System.unique_integer([:positive])}",
      signature: signature
    })
    
    Logger.info("✅ Created creative writing program: #{prog_id}")
    
    # Creative writing examples
    examples = [
      %{
        prompt: "A robot discovers it can feel emotions",
        genre: "sci-fi",
        length: "short"
      },
      %{
        prompt: "An ancient map leads to an unexpected discovery",
        genre: "adventure",
        length: "medium"
      }
    ]
    
    Enum.each(examples, fn inputs ->
      Logger.info("\n✍️  Writing: \"#{inputs.prompt}\"")
      Logger.info("   Genre: #{inputs.genre}")
      Logger.info("   Length: #{inputs.length}")
      
      case adapter.execute_program(prog_id, inputs) do
        {:ok, result} ->
          outputs = extract_outputs(result)
          
          Logger.info("✅ Creative Writing Results:")
          Logger.info("   Story: #{String.slice(outputs["story"] || outputs[:story] || "", 0, 100)}...")
          Logger.info("   Theme: #{outputs["theme"] || outputs[:theme]}")
          Logger.info("   Characters: #{outputs["character_count"] || outputs[:character_count]}")
          
        {:error, reason} ->
          Logger.warning("⚠️  Creative writing failed: #{inspect(reason)}")
      end
    end)
    
    Logger.info("\n🎉 Creative Writing Example Complete!")
  end

  @doc """
  Run all signature examples sequentially.
  """
  def run_all_examples do
    Logger.info("🚀 Running All DSPex Dynamic Signature Examples\n")
    
    run_text_analysis_example()
    Process.sleep(1000)
    
    run_translation_example()
    Process.sleep(1000)
    
    run_content_enhancement_example()
    Process.sleep(1000)
    
    run_creative_writing_example()
    
    Logger.info("\n🎉 All Dynamic Signature Examples Complete!")
    Logger.info("💡 This demonstrates DSPex's ability to go beyond 'question → answer'")
    Logger.info("   and handle any combination of input/output fields dynamically!")
  end

  # Private helper functions

  defp configure_language_model(adapter) do
    api_key = System.get_env("GEMINI_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      Logger.warning("⚠️  GEMINI_API_KEY not set, using mock responses")
    end
    
    case adapter.configure_lm(%{
      model: "gemini-1.5-flash",
      api_key: api_key || "mock-key",
      provider: "google"
    }) do
      :ok -> 
        Logger.info("✅ Language model configured successfully")
      {:error, reason} -> 
        Logger.warning("⚠️  LM configuration issue: #{inspect(reason)}")
    end
  end

  defp extract_outputs(result) do
    # Handle different response formats
    result["outputs"] || result[:outputs] || result
  end
end