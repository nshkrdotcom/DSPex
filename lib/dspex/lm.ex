defmodule DSPex.LM do
  @moduledoc """
  Language Model client wrapper for DSPy.

  Provides a unified interface to configure and use various LLM providers
  through DSPy's LM abstraction powered by LiteLLM.
  """

  alias DSPex.Utils.ID

  @doc """
  Configure the default language model for DSPy.

  ## Examples

      # OpenAI
      DSPex.LM.configure("openai/gpt-4", api_key: System.get_env("OPENAI_API_KEY"))
      
      # Anthropic
      DSPex.LM.configure("anthropic/claude-3-opus", api_key: System.get_env("ANTHROPIC_API_KEY"))
      
      # Google
      DSPex.LM.configure("gemini/gemini-pro", api_key: System.get_env("GOOGLE_API_KEY"))
      
      # Local models
      DSPex.LM.configure("ollama/llama2", api_base: "http://localhost:11434")
  """
  def configure(model, opts \\ []) do
    lm_config =
      %{
        model: model,
        api_key: opts[:api_key],
        api_base: opts[:api_base],
        temperature: opts[:temperature],
        max_tokens: opts[:max_tokens],
        top_p: opts[:top_p],
        frequency_penalty: opts[:frequency_penalty],
        presence_penalty: opts[:presence_penalty],
        n: opts[:n],
        stop: opts[:stop]
      }
      |> Enum.filter(fn {_, v} -> v != nil end)
      |> Map.new()

    # Create LM instance and store it
    with {:ok, _} <-
           Snakepit.Python.call(
             "dspy.LM",
             lm_config,
             Keyword.merge([store_as: "default_lm"], opts)
           ),
         # Configure DSPy to use this LM
         {:ok, _} <-
           Snakepit.Python.call(
             "dspy.configure",
             %{lm: "stored.default_lm"},
             opts
           ) do
      {:ok, :configured}
    end
  end

  @doc """
  Create a new LM instance without setting it as default.

  Useful for using multiple models in the same program.
  """
  def create(model, opts \\ []) do
    id = opts[:store_as] || ID.generate("lm")

    lm_config =
      %{
        model: model,
        api_key: opts[:api_key],
        api_base: opts[:api_base],
        temperature: opts[:temperature],
        max_tokens: opts[:max_tokens],
        top_p: opts[:top_p],
        frequency_penalty: opts[:frequency_penalty],
        presence_penalty: opts[:presence_penalty],
        n: opts[:n],
        stop: opts[:stop],
        cache: opts[:cache] || true
      }
      |> Enum.filter(fn {_, v} -> v != nil end)
      |> Map.new()

    case Snakepit.Python.call(
           "dspy.LM",
           lm_config,
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Directly call an LM for generation.

  Lower-level interface for custom use cases.
  """
  def generate(prompt, opts \\ []) do
    lm_id = opts[:lm_id] || "default_lm"

    Snakepit.Python.call(
      "stored.#{lm_id}.__call__",
      %{prompt: prompt},
      opts
    )
  end

  @doc """
  Get information about a configured LM.
  """
  def inspect(lm_id \\ "default_lm", opts \\ []) do
    Snakepit.Python.call(
      "stored.#{lm_id}.inspect_history",
      %{n: opts[:n] || 1},
      opts
    )
  end

  @doc """
  List all available models from a provider.
  """
  def list_models(provider, opts \\ []) do
    Snakepit.Python.call(
      "litellm.get_model_list",
      %{provider: provider},
      opts
    )
  end

  # Provider-specific helpers

  @doc """
  Configure OpenAI models.
  """
  def openai(model \\ "gpt-4", opts \\ []) do
    configure(
      "openai/#{model}",
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("OPENAI_API_KEY"))
    )
  end

  @doc """
  Configure Anthropic Claude models.
  """
  def anthropic(model \\ "claude-3-opus-20240229", opts \\ []) do
    configure(
      "anthropic/#{model}",
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("ANTHROPIC_API_KEY"))
    )
  end

  @doc """
  Configure Google Gemini models.
  """
  def gemini(model \\ "gemini-pro", opts \\ []) do
    configure(
      "gemini/#{model}",
      Keyword.put(opts, :api_key, opts[:api_key] || System.get_env("GOOGLE_API_KEY"))
    )
  end

  @doc """
  Configure local Ollama models.
  """
  def ollama(model \\ "llama2", opts \\ []) do
    configure(
      "ollama/#{model}",
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

    configure("azure/#{deployment_name}", azure_config ++ opts)
  end
end
