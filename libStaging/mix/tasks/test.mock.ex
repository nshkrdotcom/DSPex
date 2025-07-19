defmodule Mix.Tasks.Test.Mock do
  @moduledoc """
  Run tests in pure mock mode.

  Pure mock mode ensures no network requests are made during testing,
  providing fast, deterministic test execution.

  ## Usage

      mix test.mock
      mix test.mock test/unit/
      mix test.mock test/unit/specific_test.exs:42

  ## Behavior

  - Forces all tests to use mock clients
  - No API key validation or network attempts
  - Contextual mock responses based on test content
  - Fast execution with deterministic results

  ## Equivalent Commands

      DSPEX_TEST_MODE=mock mix test
      mix test  # (default behavior)

  """
  use Mix.Task

  @shortdoc "Run tests in pure mock mode (no network requests)"

  def run(args) do
    # Set test mode to mock
    DSPEx.TestModeConfig.set_test_mode(:mock)

    # Show mode info
    IO.puts("""
    🟦 [PURE MOCK MODE] Running tests with no network requests
       Mode: Pure mock - deterministic responses only
       Speed: Fast execution, no API dependencies
    """)

    # Run the actual tests
    Mix.Tasks.Test.run(args)
  end
end
