defmodule Mix.Tasks.Test.Fallback do
  @moduledoc """
  Run tests with live API fallback to mock.

  Fallback mode attempts to use real API integration when keys are available,
  but seamlessly falls back to mock responses when they are not.

  ## Usage

      mix test.fallback
      mix test.fallback test/integration/
      mix test.fallback test/integration/specific_test.exs:42

  ## Behavior

  - Attempts real API calls when API keys are available
  - Seamlessly falls back to mock when no keys present
  - Validates both real API integration and mock behavior
  - Slower execution when using real APIs

  ## Equivalent Commands

      DSPEX_TEST_MODE=fallback mix test

  ## API Key Requirements

  Optional - tests will run with or without API keys:
  - GEMINI_API_KEY for Google Gemini
  - OPENAI_API_KEY for OpenAI
  - ANTHROPIC_API_KEY for Anthropic Claude

  """
  use Mix.Task

  @shortdoc "Run tests with live API fallback to mock"

  def run(args) do
    # Set test mode to fallback
    DSPEx.TestModeConfig.set_test_mode(:fallback)

    # Check available API keys
    available_keys = check_available_api_keys()

    # Show mode info
    IO.puts("""
    🟡 [FALLBACK MODE] Running tests with seamless API fallback
       Mode: Live API when available, mock fallback otherwise
       Available APIs: #{format_available_keys(available_keys)}
       Speed: Variable - depends on API availability
    """)

    # Run the actual tests
    Mix.Tasks.Test.run(args)
  end

  defp check_available_api_keys do
    [
      {:gemini, System.get_env("GEMINI_API_KEY")},
      {:openai, System.get_env("OPENAI_API_KEY")},
      {:anthropic, System.get_env("ANTHROPIC_API_KEY")}
    ]
    |> Enum.filter(fn {_, key} -> key && String.length(key) > 0 end)
    |> Enum.map(fn {provider, _} -> provider end)
  end

  defp format_available_keys([]), do: "None (will use mock fallback)"

  defp format_available_keys(keys) do
    Enum.map_join(keys, ", ", &Atom.to_string/1)
  end
end
