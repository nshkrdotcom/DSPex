defmodule Mix.Tasks.Test.Live do
  @moduledoc """
  Run tests in live API mode only.

  Live mode requires valid API keys and will fail tests that cannot
  access real API endpoints. Use this for strict integration testing.

  ## Usage

      mix test.live
      mix test.live test/integration/
      mix test.live test/integration/specific_test.exs:42

  ## Behavior

  - Requires valid API keys for all providers being tested
  - No fallback to mock responses
  - Tests real API integration and error handling
  - Slower execution due to network requests
  - May fail due to API rate limits or network issues

  ## Equivalent Commands

      DSPEX_TEST_MODE=live mix test

  ## API Key Requirements

  Required for any provider being tested:
  - GEMINI_API_KEY for Google Gemini
  - OPENAI_API_KEY for OpenAI
  - ANTHROPIC_API_KEY for Anthropic Claude

  ## When to Use

  - Integration testing with real APIs
  - Validating actual API behavior and responses
  - Testing error handling for real API failures
  - Before production deployments

  """
  use Mix.Task

  alias Mix.Tasks.Test

  @shortdoc "Run tests in live API mode only (requires API keys)"

  def run(args) do
    # Set test mode to live
    DSPEx.TestModeConfig.set_test_mode(:live)

    # Check available API keys
    available_keys = check_available_api_keys()
    missing_keys = check_missing_api_keys()

    # Show mode info
    IO.puts("""
    🟢 [LIVE API MODE] Running tests with real API integration only
       Mode: Live API required - no mock fallback
       Available APIs: #{format_available_keys(available_keys)}
       Speed: Slower - network requests required
    """)

    # Warn about missing keys
    if length(missing_keys) > 0 do
      IO.puts("""
      ⚠️  WARNING: Missing API keys for: #{Enum.join(missing_keys, ", ")}
         Tests requiring these providers will fail.

         To set missing keys:
      #{format_key_instructions(missing_keys)}
      """)
    end

    # Run the actual tests
    Test.run(args)
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

  defp check_missing_api_keys do
    [
      {:gemini, "GEMINI_API_KEY"},
      {:openai, "OPENAI_API_KEY"},
      {:anthropic, "ANTHROPIC_API_KEY"}
    ]
    |> Enum.filter(fn {_, env_var} ->
      key = System.get_env(env_var)
      is_nil(key) || String.length(key) == 0
    end)
    |> Enum.map(fn {provider, _} -> provider end)
  end

  defp format_available_keys([]), do: "None - tests may fail"

  defp format_available_keys(keys) do
    Enum.map_join(keys, ", ", &Atom.to_string/1)
  end

  defp format_key_instructions(missing_providers) do
    Enum.map_join(missing_providers, "\n", fn provider ->
      env_var =
        case provider do
          :gemini -> "GEMINI_API_KEY"
          :openai -> "OPENAI_API_KEY"
          :anthropic -> "ANTHROPIC_API_KEY"
        end

      "       export #{env_var}=your_#{provider}_api_key"
    end)
  end
end
