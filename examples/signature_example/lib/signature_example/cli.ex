defmodule SignatureExample.CLI do
  @moduledoc """
  Command-line interface for the DSPex Dynamic Signature Example.
  
  This module provides an interactive CLI for demonstrating dynamic signature
  capabilities with various real-world use cases.
  """

  require Logger

  @doc """
  Main CLI entry point with interactive menu.
  """
  def main(args \\ []) when is_list(args) do
    IO.puts("\n🚀 DSPex Dynamic Signature Example")
    IO.puts("====================================")
    IO.puts("This example demonstrates dynamic signatures that go beyond 'question → answer'")
    IO.puts("and can handle any combination of input/output fields.\n")

    case args do
      [] -> 
        show_interactive_menu()
      ["--all"] ->
        SignatureExample.run_all_examples()
      ["--text-analysis"] ->
        SignatureExample.run_text_analysis_example()
      ["--translation"] ->
        SignatureExample.run_translation_example()
      ["--enhancement"] ->
        SignatureExample.run_content_enhancement_example()
      ["--creative"] ->
        SignatureExample.run_creative_writing_example()
      ["--help"] ->
        show_help()
        :ok
      _ ->
        show_help()
        :ok
    end
  end

  defp show_interactive_menu do
    IO.puts("Choose an example to run:")
    IO.puts("1. Text Analysis (sentiment + summary + keywords + confidence)")
    IO.puts("2. Translation (source detection + translation + confidence)")
    IO.puts("3. Content Enhancement (text improvement + changes + readability)")
    IO.puts("4. Creative Writing (story generation + theme + character count)")
    IO.puts("5. Run All Examples")
    IO.puts("6. Show Technical Details")
    IO.puts("7. Exit")
    
    case get_user_choice() do
      "1" ->
        SignatureExample.run_text_analysis_example()
        continue_or_exit()
        
      "2" ->
        SignatureExample.run_translation_example()
        continue_or_exit()
        
      "3" ->
        SignatureExample.run_content_enhancement_example()
        continue_or_exit()
        
      "4" ->
        SignatureExample.run_creative_writing_example()
        continue_or_exit()
        
      "5" ->
        SignatureExample.run_all_examples()
        continue_or_exit()
        
      "6" ->
        show_technical_details()
        continue_or_exit()
        
      "7" ->
        IO.puts("👋 Goodbye!")
        
      _ ->
        IO.puts("❌ Invalid choice. Please try again.\n")
        show_interactive_menu()
    end
  end

  defp get_user_choice do
    IO.write("\nEnter your choice (1-7): ")
    IO.read(:line) |> String.trim()
  end

  defp continue_or_exit do
    IO.write("\nPress Enter to return to menu, or 'q' to quit: ")
    case IO.read(:line) |> String.trim() do
      "q" -> IO.puts("👋 Goodbye!")
      _ -> show_interactive_menu()
    end
  end

  defp show_help do
    IO.puts("""
    DSPex Dynamic Signature Example
    
    Usage:
      mix run -e "SignatureExample.CLI.main()"                  # Interactive menu
      mix run -e "SignatureExample.CLI.main(['--all'])"         # Run all examples
      mix run -e "SignatureExample.CLI.main(['--text-analysis'])" # Text analysis only
      mix run -e "SignatureExample.CLI.main(['--translation'])"   # Translation only
      mix run -e "SignatureExample.CLI.main(['--enhancement'])"   # Content enhancement only
      mix run -e "SignatureExample.CLI.main(['--creative'])"      # Creative writing only
      mix run -e "SignatureExample.CLI.main(['--help'])"         # Show this help
    
    Environment Variables:
      GEMINI_API_KEY    Your Google Gemini API key (required for real ML operations)
    
    Examples demonstrate:
    - Multi-input signatures (text + style, text + target_language, etc.)
    - Multi-output signatures (sentiment + summary + keywords + confidence)
    - Dynamic signature generation and caching
    - Fallback mechanisms when signatures fail
    - Real-world use cases beyond simple Q&A
    """)
  end

  defp show_technical_details do
    IO.puts("""
    🔧 Technical Implementation Details
    ===================================
    
    The DSPex dynamic signature system works through several layers:
    
    1. 📝 Signature Definition (Elixir)
       • Define inputs/outputs with types and descriptions
       • No hardcoded field names like "question" and "answer"
       • Flexible schema for any use case
    
    2. 🔄 Type Conversion (Bridge Layer)
       • TypeConverter creates enriched Python payload
       • Converts Elixir types to Python types
       • Adds metadata for dynamic generation
    
    3. 🏭 Dynamic Generation (Python Side)
       • DSPy signature classes created on-the-fly
       • Field names become class attributes
       • Signature caching for performance
    
    4. ⚡ Execution (Runtime)
       • Uses **inputs unpacking for flexible I/O
       • Extracts outputs based on signature definition
       • Fallback to Q&A format if dynamic signatures fail
    
    5. 🎯 Benefits
       • Any input/output combination
       • Type safety and validation
       • Performance through caching
       • Reliability through fallbacks
       • Easy to extend with new signatures
    
    Architecture:
    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
    │   Elixir App    │───▶│  DSPex Bridge    │───▶│  Python DSPy        │
    │                 │    │                  │    │                     │
    │ Dynamic         │    │ TypeConverter    │    │ Dynamic Signature   │
    │ Signatures      │    │ Enhanced Payload │    │ Factory & Caching   │
    └─────────────────┘    └──────────────────┘    └─────────────────────┘
    
    This replaces the old hardcoded "question → answer" approach with a 
    flexible system that can handle any signature pattern!
    """)
  end
end