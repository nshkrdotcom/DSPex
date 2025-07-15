defmodule SimpleDspyExample.CLI do
  @moduledoc """
  Command-line interface for the Simple DSPy Example.
  
  Provides a simple way to run the example from the command line without
  needing to start an IEx session.
  """

  @doc """
  Main entry point for the CLI application.
  
  ## Usage
  
      mix run -e "SimpleDspyExample.CLI.main()"
      
  Or with command-line arguments:
  
      mix run -e "SimpleDspyExample.CLI.main()" -- run
      mix run -e "SimpleDspyExample.CLI.main()" -- models
      mix run -e "SimpleDspyExample.CLI.main()" -- errors
  """
  def main(args \\ []) do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:simple_dspy_example)
    
    case args do
      [] -> 
        run_with_output()
        
      ["run"] -> 
        run_with_output()
        
      ["models"] -> 
        list_models_with_output()
        
      ["errors"] -> 
        demonstrate_errors_with_output()
        
      ["help"] -> 
        show_help()
        
      _ -> 
        IO.puts("Unknown command. Use 'help' for available commands.")
        show_help()
    end
  end

  defp run_with_output do
    IO.puts("\n=== Simple DSPy Example ===")
    IO.puts("Running complete DSPex workflow demonstration...")
    
    case SimpleDspyExample.run() do
      {:ok, result} ->
        IO.puts("\n✅ Success!")
        IO.puts("Result: #{inspect(result, pretty: true)}")
        
      {:error, error} ->
        IO.puts("\n❌ Error occurred:")
        IO.puts("#{inspect(error)}")
        System.halt(1)
    end
  end

  defp list_models_with_output do
    IO.puts("\n=== Available Language Models ===")
    
    models = SimpleDspyExample.list_models()
    
    IO.puts("Supported models:")
    Enum.each(models, fn model ->
      IO.puts("  • #{model}")
    end)
  end

  defp demonstrate_errors_with_output do
    IO.puts("\n=== Error Handling Demonstration ===")
    IO.puts("Testing error handling capabilities...")
    
    case SimpleDspyExample.demonstrate_error_handling() do
      {:error, error} ->
        IO.puts("✅ Expected error occurred:")
        IO.puts("#{inspect(error)}")
        
      :ok ->
        IO.puts("⚠️  No error occurred (unexpected)")
    end
  end

  defp show_help do
    IO.puts("""
    
    Simple DSPy Example CLI
    
    Usage:
      mix run -e "SimpleDspyExample.CLI.main()" -- [COMMAND]
    
    Commands:
      run     Run the complete DSPex workflow (default)
      models  List available language models
      errors  Demonstrate error handling
      help    Show this help message
    
    Environment:
      Set GEMINI_API_KEY environment variable before running
    
    Examples:
      export GEMINI_API_KEY="your-key-here"
      mix run -e "SimpleDspyExample.CLI.main()"
      mix run -e "SimpleDspyExample.CLI.main()" -- models
    """)
  end
end