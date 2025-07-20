defmodule DSPex.Config do
  @moduledoc """
  Configuration and initialization for DSPex.

  Handles DSPy environment setup and global configuration.
  """

  @doc """
  Initialize DSPex with DSPy.

  This should be called once at application startup to ensure
  DSPy is properly initialized in the Python environment.

  ## Examples

      # Basic initialization
      DSPex.Config.init()
      
      # With specific Python path
      DSPex.Config.init(python_path: "/usr/bin/python3.11")
  """
  def init(opts \\ []) do
    # Try to initialize DSPy, but don't fail if it's not available
    case test_dspy_available(opts) do
      {:ok, :available} ->
        case get_dspy_version(opts) do
          {:ok, version} ->
            {:ok,
             %{
               dspy_version: version,
               status: :ready
             }}

          _ ->
            {:ok,
             %{
               dspy_version: "unknown",
               status: :ready_without_version
             }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get DSPy version information.
  """
  def get_dspy_version(opts \\ []) do
    case Snakepit.Python.call("dspy.__version__", %{}, opts) do
      {:ok, %{"result" => %{"value" => version}}} -> {:ok, version}
      {:ok, %{"result" => version}} when is_binary(version) -> {:ok, version}
      error -> error
    end
  end

  defp test_dspy_available(opts) do
    # Test if dspy module is importable
    case Snakepit.Python.call("dspy.__name__", %{}, opts) do
      {:ok, %{"result" => %{"value" => "dspy"}}} ->
        {:ok, :available}

      # Any successful response means dspy is available
      {:ok, _} ->
        {:ok, :available}

      {:error, _} ->
        # Try to help by showing how to install
        {:error, "DSPy not found. Please install with: pip install dspy-ai"}
    end
  end

  @doc """
  Check if DSPy is properly initialized.
  """
  def ready?(opts \\ []) do
    case Snakepit.Python.call("dspy.__name__", %{}, opts) do
      {:ok, "dspy"} -> true
      _ -> false
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

  defp setup_retriever(retriever_config) do
    type = retriever_config[:type] || raise "Retriever type required"
    DSPex.Retrievers.Retrieve.init(type, retriever_config)
  end

  defp apply_settings(nil), do: {:ok, :default_settings}

  defp apply_settings(settings) do
    DSPex.Settings.configure(settings)
  end
end
