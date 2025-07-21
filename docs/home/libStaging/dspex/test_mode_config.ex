defmodule DSPEx.TestModeConfig do
  @moduledoc """
  Test mode configuration system for DSPEx.

  Manages three distinct test modes:
  - :mock - Pure mock mode, no network attempts (default)
  - :fallback - Live API with seamless fallback to mock
  - :live - Live API only, fails without API keys

  ## Precedence Order:
  1. CLI flags (via environment variables set by mix tasks)
  2. DSPEX_TEST_MODE environment variable
  3. Default (:mock)
  """

  @modes [:mock, :fallback, :live]
  @default_mode :mock

  @doc """
  Get the current test mode.

  ## Examples

      iex> DSPEx.TestModeConfig.get_test_mode()
      :mock

      # With DSPEX_TEST_MODE=fallback
      iex> DSPEx.TestModeConfig.get_test_mode()
      :fallback
  """
  @spec get_test_mode() :: :mock | :fallback | :live
  def get_test_mode do
    case System.get_env("DSPEX_TEST_MODE") do
      "mock" ->
        :mock

      "fallback" ->
        :fallback

      "live" ->
        :live

      nil ->
        @default_mode

      invalid ->
        IO.warn("Invalid DSPEX_TEST_MODE: #{invalid}. Using default: #{@default_mode}")
        @default_mode
    end
  end

  @doc """
  Set the test mode programmatically.

  Used by mix tasks to override the default behavior.
  """
  @spec set_test_mode(:mock | :fallback | :live) :: :ok
  def set_test_mode(mode) when mode in @modes do
    System.put_env("DSPEX_TEST_MODE", Atom.to_string(mode))
    :ok
  end

  def set_test_mode(invalid_mode) do
    raise ArgumentError,
          "Invalid test mode: #{inspect(invalid_mode)}. Must be one of: #{inspect(@modes)}"
  end

  @doc """
  Check if the current mode is pure mock (no network attempts).
  """
  @spec pure_mock_mode?() :: boolean()
  def pure_mock_mode? do
    get_test_mode() == :mock
  end

  @doc """
  Check if the current mode allows fallback behavior.
  """
  @spec fallback_mode?() :: boolean()
  def fallback_mode? do
    get_test_mode() == :fallback
  end

  @doc """
  Check if the current mode requires live API keys.
  """
  @spec live_only_mode?() :: boolean()
  def live_only_mode? do
    get_test_mode() == :live
  end

  @doc """
  Get a human-readable description of the current test mode.
  """
  @spec describe_current_mode() :: String.t()
  def describe_current_mode do
    case get_test_mode() do
      :mock ->
        "Pure Mock Mode - No network requests, deterministic mock responses only"

      :fallback ->
        "Fallback Mode - Live API with seamless fallback to mock when keys unavailable"

      :live ->
        "Live API Mode - Real API integration required, fails without valid keys"
    end
  end

  @doc """
  Get the emoji indicator for the current test mode.
  """
  @spec mode_emoji() :: String.t()
  def mode_emoji do
    case get_test_mode() do
      # Blue square for pure mock
      :mock -> "🟦"
      # Yellow circle for fallback
      :fallback -> "🟡"
      # Green circle for live
      :live -> "🟢"
    end
  end

  @doc """
  Get all available test modes with descriptions.
  """
  @spec available_modes() :: [{atom(), String.t()}]
  def available_modes do
    [
      {:mock, "Pure mock mode - no network requests (default)"},
      {:fallback, "Live API with seamless mock fallback"},
      {:live, "Live API only - requires valid API keys"}
    ]
  end

  @doc """
  Print current test mode configuration for debugging.
  """
  @spec debug_info() :: :ok
  def debug_info do
    current_mode = get_test_mode()
    env_var = System.get_env("DSPEX_TEST_MODE")

    IO.puts("""

    === DSPEx Test Mode Configuration ===
    Current Mode: #{current_mode}
    Environment Variable: #{inspect(env_var)}
    Description: #{describe_current_mode()}
    Emoji: #{mode_emoji()}
    =====================================
    """)
  end
end
