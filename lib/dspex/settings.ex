defmodule DSPex.Settings do
  @moduledoc """
  Global settings and configuration for DSPex.

  Manages DSPy settings and provides utilities for configuration management.
  """

  @doc """
  Configure global DSPy settings.

  ## Examples

      DSPex.Settings.configure(
        lm: lm_instance,
        rm: retriever_instance,
        trace: [],
        explain: false
      )
  """
  def configure(settings, opts \\ []) do
    Snakepit.Python.call(
      "dspy.configure",
      Map.new(settings),
      opts
    )
  end

  @doc """
  Get current DSPy settings.
  """
  def get_settings(opts \\ []) do
    # DSPy settings doesn't have to_dict, just return the settings object
    Snakepit.Python.call(
      "dspy.settings",
      %{},
      opts
    )
  end

  @doc """
  Context manager for temporary settings.

  ## Examples

      DSPex.Settings.with_settings([trace: []], fn ->
        # Code that runs with tracing enabled
        DSPex.Modules.Predict.predict(sig, inputs)
      end)
  """
  def with_settings(temp_settings, fun) when is_function(fun, 0) do
    session_id = DSPex.Utils.ID.generate("settings_context")

    # Save current settings
    {:ok, original} = get_settings(session_id: session_id)

    try do
      # Apply temporary settings
      configure(temp_settings, session_id: session_id)

      # Execute function
      fun.()
    after
      # Restore original settings
      configure(original, session_id: session_id)
    end
  end

  @doc """
  Enable or disable experimental features.
  """
  def experimental(feature, enabled \\ true, opts \\ []) do
    Snakepit.Python.call(
      "dspy.experimental.set_#{feature}_enabled",
      %{enabled: enabled},
      opts
    )
  end

  @doc """
  Configure caching behavior.
  """
  def configure_cache(cache_opts, opts \\ []) do
    # dspy.configure_cache is in dspy.clients module
    cache_dir = cache_opts[:cache_dir] || ".dspy_cache"

    Snakepit.Python.call(
      "dspy.clients.configure_cache",
      %{cache_dir: cache_dir},
      opts
    )
  end
end
