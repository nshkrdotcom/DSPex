defmodule DSPex.Config do
  @moduledoc """
  Configuration and initialization for DSPex.

  Handles DSPy environment setup and global configuration.
  Migrated to Snakepit v0.4.3 API (execute_in_session).
  """

  alias DSPex.Utils.ID

  @doc """
  Initialize DSPex with DSPy.

  This should be called once at application startup to ensure
  DSPy is properly initialized in the Python environment.

  ## Examples

      # Basic initialization
      DSPex.Config.init()

      # With specific session
      DSPex.Config.init(session_id: "my_session")
  """
  def init(opts \\ []) do
    # Try to initialize DSPy, but don't fail if it's not available
    case check_dspy_available(opts) do
      {:ok, version} ->
        {:ok,
         %{
           dspy_version: version,
           status: :ready
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if DSPy is available and get version.
  """
  def check_dspy_available(opts \\ []) do
    session_id = opts[:session_id] || ID.generate("config_check")

    case Snakepit.execute_in_session(session_id, "check_dspy", %{}) do
      {:ok, %{"available" => true, "version" => version}} ->
        {:ok, version}

      {:ok, %{"available" => false, "error" => error}} ->
        {:error, "DSPy not available: #{error}"}

      {:error, error} ->
        {:error, "Failed to check DSPy: #{inspect(error)}"}
    end
  end

  @doc """
  Get DSPy version information.
  """
  def get_dspy_version(opts \\ []) do
    check_dspy_available(opts)
  end

  @doc """
  Check if DSPy is properly initialized.
  """
  def ready?(opts \\ []) do
    case check_dspy_available(opts) do
      {:ok, _version} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Set up a complete DSPex environment with LM and optional retriever.

  ## Examples

      DSPex.Config.setup(
        lm: [model: "openai/gpt-4", api_key: "..."],
        retriever: [type: :chromadb, collection: "docs"]
      )
  """
  def setup(config) do
    with :ok <- validate_config(config),
         {:ok, _} <- init(),
         {:ok, _} <- setup_lm(config[:lm]),
         {:ok, _} <- setup_retriever(config[:retriever]),
         {:ok, _} <- apply_settings(config[:settings]) do
      {:ok, :configured}
    end
  end

  defp validate_config(config) do
    cond do
      not Keyword.keyword?(config) ->
        {:error, "Configuration must be a keyword list"}

      not Keyword.has_key?(config, :lm) ->
        {:error, "Language model configuration (:lm) is required"}

      true ->
        :ok
    end
  end

  defp setup_lm(nil), do: {:error, "LM configuration required"}

  defp setup_lm(lm_config) do
    model = lm_config[:model] || raise "Model required in LM config"
    DSPex.LM.configure(model, lm_config)
  end

  defp setup_retriever(nil), do: {:ok, :no_retriever}

  defp setup_retriever(_retriever_config) do
    # Retriever module not yet implemented
    {:ok, :retriever_not_implemented}
  end

  defp apply_settings(nil), do: {:ok, :default_settings}

  defp apply_settings(settings) do
    DSPex.Settings.configure(settings)
  end
end
