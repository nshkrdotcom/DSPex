defmodule DSPex.LM do
  @moduledoc """
  Language Model client wrapper for DSPy.

  Provides a unified interface to configure and use various LLM providers
  through DSPy's LM abstraction powered by LiteLLM.

  Migrated to Snakepit v0.4.3 API (execute_in_session).
  """

  alias DSPex.Utils.ID

  @doc """
  Configure the default language model for DSPy.

  ## Examples

      # OpenAI
      DSPex.LM.configure("gpt-4", api_key: System.get_env("OPENAI_API_KEY"))

      # Anthropic
      DSPex.LM.configure("claude-3-opus", api_key: System.get_env("ANTHROPIC_API_KEY"))

      # Google Gemini
      DSPex.LM.configure("gemini-pro", api_key: System.get_env("GOOGLE_API_KEY"))

      # With full model path
      DSPex.LM.configure("gemini/gemini-2.5-flash-lite", api_key: key)
  """
  def configure(model, opts \\ []) do
    api_key = opts[:api_key] || get_api_key_from_env(model)
    session_id = opts[:session_id] || ID.generate("lm_config")
    model_type = infer_model_type(model)

    case Snakepit.execute_in_session(session_id, "configure_lm", %{
           "model_type" => model_type,
           "api_key" => api_key,
           "model" => normalize_model_name(model, model_type)
         }) do
      {:ok, %{"success" => true}} ->
        {:ok, %{model: model, configured: true}}

      {:ok, %{"success" => false, "error" => error}} ->
        {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Create a new LM instance without setting it as default.

  Useful for using multiple models in the same program.
  """
  def create(model, opts \\ []) do
    # For now, create uses the same pattern as configure
    # In future, could use call_dspy to create LM instances
    configure(model, opts)
  end

  @doc """
  Directly call an LM for generation.

  Lower-level interface for custom use cases.
  """
  def generate(_prompt, _opts \\ []) do
    # This would need a custom tool in dspy_grpc.py
    # For now, return not implemented
    {:error, :not_implemented}
  end

  @doc """
  Get information about a configured LLM.
  """
  def inspect(_lm_id \\ "default_lm", opts \\ []) do
    session_id = opts[:session_id] || ID.generate("lm_inspect")

    case Snakepit.execute_in_session(session_id, "get_settings", %{}) do
      {:ok, settings} -> {:ok, settings}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  List all available models from a provider.
  """
  def list_models(_provider, _opts \\ []) do
    # Would need integration with LiteLLM's model list
    {:error, :not_implemented}
  end

  # Provider-specific helpers

  @doc """
  Configure OpenAI models.
  """
  def openai(model \\ "gpt-4", opts \\ []) do
    configure(
      model,
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("OPENAI_API_KEY"))
    )
  end

  @doc """
  Configure Anthropic Claude models.
  """
  def anthropic(model \\ "claude-3-opus-20240229", opts \\ []) do
    configure(
      model,
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("ANTHROPIC_API_KEY"))
    )
  end

  @doc """
  Configure Google Gemini models.
  """
  def gemini(model \\ "gemini-pro", opts \\ []) do
    configure(
      model,
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("GOOGLE_API_KEY"))
    )
  end

  @doc """
  Configure local Ollama models.
  """
  def ollama(model \\ "llama2", opts \\ []) do
    configure(
      model,
      Keyword.put(opts, :api_base, opts[:api_base] || "http://localhost:11434")
    )
  end

  @doc """
  Configure Azure OpenAI models.
  """
  def azure(deployment_name, opts \\ []) do
    azure_config = [
      api_key: opts[:api_key] || System.get_env("AZURE_API_KEY"),
      api_base: opts[:api_base] || System.get_env("AZURE_API_BASE"),
      api_version: opts[:api_version] || "2023-05-15"
    ]

    configure(deployment_name, azure_config ++ opts)
  end

  # Private helpers

  defp infer_model_type(model) do
    cond do
      String.contains?(model, "gemini") or String.contains?(model, "google") -> "gemini"
      String.contains?(model, "gpt") or String.contains?(model, "openai") -> "openai"
      String.contains?(model, "claude") or String.contains?(model, "anthropic") -> "anthropic"
      String.contains?(model, "ollama") -> "ollama"
      # Default to gemini
      true -> "gemini"
    end
  end

  defp normalize_model_name(model, _model_type) do
    # Remove provider prefix if present
    model
    |> String.replace(~r/^(openai|anthropic|gemini|google|ollama)\//, "")
  end

  defp get_api_key_from_env(model) do
    cond do
      String.contains?(model, "gemini") or String.contains?(model, "google") ->
        System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")

      String.contains?(model, "gpt") or String.contains?(model, "openai") ->
        System.get_env("OPENAI_API_KEY")

      String.contains?(model, "claude") or String.contains?(model, "anthropic") ->
        System.get_env("ANTHROPIC_API_KEY")

      true ->
        nil
    end
  end
end
