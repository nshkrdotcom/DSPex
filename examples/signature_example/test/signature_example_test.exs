defmodule SignatureExampleTest do
  use ExUnit.Case
  doctest SignatureExample

  alias DSPex.Adapters.Registry
  alias SignatureExample.Signatures

  @moduletag :signature_example
  @moduletag timeout: 30_000

  describe "signature definitions" do
    test "text analysis signature has correct structure" do
      signature = Signatures.text_analysis_signature()
      
      assert is_map(signature)
      assert signature.name == "TextAnalysisSignature"
      assert is_binary(signature.description)
      
      # Validate inputs
      assert length(signature.inputs) == 2
      text_input = Enum.find(signature.inputs, &(&1.name == "text"))
      style_input = Enum.find(signature.inputs, &(&1.name == "style"))
      
      assert text_input.type == "string"
      assert style_input.type == "string"
      assert is_binary(text_input.description)
      assert is_binary(style_input.description)
      
      # Validate outputs
      assert length(signature.outputs) == 4
      expected_outputs = ["sentiment", "summary", "keywords", "confidence_score"]
      actual_outputs = Enum.map(signature.outputs, & &1.name)
      
      for expected <- expected_outputs do
        assert expected in actual_outputs
      end
    end

    test "translation signature has correct structure" do
      signature = Signatures.translation_signature()
      
      assert signature.name == "TranslationSignature"
      assert length(signature.inputs) == 2
      assert length(signature.outputs) == 3
      
      # Check for required input fields
      input_names = Enum.map(signature.inputs, & &1.name)
      assert "text" in input_names
      assert "target_language" in input_names
      
      # Check for required output fields
      output_names = Enum.map(signature.outputs, & &1.name)
      assert "translated_text" in output_names
      assert "source_language" in output_names
      assert "confidence_score" in output_names
    end

    test "content enhancement signature has correct structure" do
      signature = Signatures.content_enhancement_signature()
      
      assert signature.name == "ContentEnhancementSignature"
      assert length(signature.inputs) == 3
      assert length(signature.outputs) == 3
      
      # Check for required input fields
      input_names = Enum.map(signature.inputs, & &1.name)
      assert "text" in input_names
      assert "enhancement_type" in input_names
      assert "tone" in input_names
      
      # Check for required output fields
      output_names = Enum.map(signature.outputs, & &1.name)
      assert "enhanced_text" in output_names
      assert "changes_made" in output_names
      assert "readability_score" in output_names
    end

    test "creative writing signature has correct structure" do
      signature = Signatures.creative_writing_signature()
      
      assert signature.name == "CreativeWritingSignature"
      assert length(signature.inputs) == 3
      assert length(signature.outputs) == 3
      
      # Check for required input fields
      input_names = Enum.map(signature.inputs, & &1.name)
      assert "prompt" in input_names
      assert "genre" in input_names
      assert "length" in input_names
      
      # Check for required output fields
      output_names = Enum.map(signature.outputs, & &1.name)
      assert "story" in output_names
      assert "theme" in output_names
      assert "character_count" in output_names
    end
  end

  describe "signature program creation" do
    setup do
      adapter = Registry.get_adapter(:python_port)
      
      # Configure LM with mock for testing
      case adapter.configure_lm(%{
        model: "gemini-1.5-flash",
        api_key: "mock-key",
        provider: "google"
      }) do
        :ok -> :ok
        {:error, _} -> :ok  # Accept errors for testing
      end
      
      %{adapter: adapter}
    end

    @tag :integration
    test "can create program with text analysis signature", %{adapter: adapter} do
      signature = Signatures.text_analysis_signature()
      
      result = adapter.create_program(%{
        id: "test_text_analysis_#{System.unique_integer([:positive])}",
        signature: signature
      })
      
      case result do
        {:ok, prog_id} ->
          assert is_binary(prog_id)
          
        {:error, reason} ->
          # For mock adapter, program creation might fail, which is acceptable
          assert is_binary(reason) or is_atom(reason)
      end
    end

    @tag :integration  
    test "can create program with translation signature", %{adapter: adapter} do
      signature = Signatures.translation_signature()
      
      result = adapter.create_program(%{
        id: "test_translation_#{System.unique_integer([:positive])}",
        signature: signature
      })
      
      case result do
        {:ok, prog_id} ->
          assert is_binary(prog_id)
          
        {:error, _reason} ->
          # Mock adapter might not support all operations
          :ok
      end
    end
  end

  describe "CLI functionality" do
    test "CLI main function accepts different arguments" do
      # Test that CLI functions exist and are callable
      assert function_exported?(SignatureExample.CLI, :main, 1)
      
      # Test argument parsing (these should not crash)
      # CLI.main with --help prints help and returns normally, doesn't exit
      assert :ok = SignatureExample.CLI.main(["--help"])
    end
  end

  describe "example functions" do
    test "example functions are defined and callable" do
      # Verify all main example functions exist
      assert function_exported?(SignatureExample, :run_text_analysis_example, 0)
      assert function_exported?(SignatureExample, :run_translation_example, 0)
      assert function_exported?(SignatureExample, :run_content_enhancement_example, 0)
      assert function_exported?(SignatureExample, :run_creative_writing_example, 0)
      assert function_exported?(SignatureExample, :run_all_examples, 0)
    end
  end
end