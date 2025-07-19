defmodule DSPex.LLM.Client do
  @moduledoc """
  Main client module for LLM interactions.

  This module provides a unified interface for working with different LLM
  providers through various adapters. It handles adapter selection, client
  configuration, and request routing.
  """

  require Logger

  @default_adapter_priority [:instructor_lite, :http, :python]

  @adapters %{
    instructor_lite: DSPex.LLM.Adapters.InstructorLite,
    gemini: DSPex.LLM.Adapters.Gemini,
    http: DSPex.LLM.Adapters.HTTP,
    python: DSPex.LLM.Adapters.Python,
    mock: DSPex.LLM.Adapters.Mock
  }

  @doc """
  Create a new LLM client with the specified configuration.

  ## Options

    * `:adapter` - The adapter to use (:instructor_lite, :http, :python)
    * `:provider` - The LLM provider (e.g., :openai, :anthropic)
    * `:api_key` - API key for the provider
    * `:model` - Model to use
    * `:response_model` - Ecto schema for structured output (InstructorLite)
    * `:pool` - Snakepit pool name (Python adapter)
    
  ## Examples

      # Using InstructorLite for structured output
      {:ok, client} = Client.new(
        adapter: :instructor_lite,
        provider: :openai,
        api_key: "sk-...",
        response_model: MySchema
      )
      
      # Using HTTP adapter for streaming
      {:ok, client} = Client.new(
        adapter: :http,
        provider: :anthropic,
        api_key: "sk-ant-..."
      )
  """
  @spec new(keyword()) :: {:ok, map()} | {:error, term()}
  def new(opts \\ []) do
    # Get defaults from configuration
    defaults = get_config_defaults()

    # Select adapter based on requirements BEFORE merging defaults
    adapter_type = opts[:adapter] || select_best_adapter(opts) || defaults[:adapter]

    # Now merge defaults, but preserve the selected adapter
    opts =
      defaults
      |> Keyword.merge(opts)
      |> Keyword.put(:adapter, adapter_type)

    case Map.get(@adapters, adapter_type) do
      nil ->
        {:error, {:unknown_adapter, adapter_type}}

      adapter_module ->
        provider = opts[:provider] || get_default_provider(adapter_type)
        config = build_config(opts, adapter_type, provider)

        with {:ok, client} <- adapter_module.configure(provider, config) do
          enriched = enrich_client(client, adapter_type, opts)
          {:ok, enriched}
        end
    end
  end

  @doc """
  Generate a response using the configured client.

  ## Parameters

    * `client` - The configured LLM client
    * `prompt` - String prompt or list of messages
    * `opts` - Generation options
    
  ## Options

    * `:temperature` - Sampling temperature (0.0-2.0)
    * `:max_tokens` - Maximum tokens to generate
    * `:response_model` - Override response model for this request
    * `:timeout` - Request timeout in milliseconds
    
  ## Examples

      {:ok, response} = Client.generate(client, "What is Elixir?")
      
      {:ok, response} = Client.generate(client, 
        [%{role: "system", content: "You are helpful."},
         %{role: "user", content: "Explain OTP"}],
        temperature: 0.7,
        max_tokens: 500
      )
  """
  @spec generate(map(), String.t() | list(map()), keyword()) ::
          {:ok, map()} | {:error, term()}
  def generate(%{adapter_module: module} = client, prompt, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    result = module.generate(client, prompt, opts)

    duration = System.monotonic_time(:millisecond) - start_time
    emit_telemetry(:generate, duration, client, result)

    result
  end

  @doc """
  Stream a response using the configured client.

  Returns a stream of response chunks. Not all adapters support streaming.

  ## Examples

      {:ok, stream} = Client.stream(client, "Tell me a story")
      
      stream
      |> Stream.each(&IO.write/1)
      |> Stream.run()
  """
  @spec stream(map(), String.t() | list(map()), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream(%{adapter_module: module} = client, prompt, opts \\ []) do
    module.stream(client, prompt, opts)
  end

  @doc """
  Generate responses for multiple prompts in a batch.

  ## Examples

      prompts = ["What is Elixir?", "What is OTP?", "What is BEAM?"]
      {:ok, responses} = Client.batch(client, prompts)
  """
  @spec batch(map(), list(String.t() | list(map())), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def batch(%{adapter_module: module} = client, prompts, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    result = module.batch(client, prompts, opts)

    duration = System.monotonic_time(:millisecond) - start_time
    emit_telemetry(:batch, duration, client, result)

    result
  end

  @doc """
  Check if the client supports streaming.
  """
  @spec supports_streaming?(map()) :: boolean()
  def supports_streaming?(%{adapter_type: :http}), do: true
  def supports_streaming?(%{adapter_type: :python}), do: true
  def supports_streaming?(%{adapter_type: :gemini}), do: true
  def supports_streaming?(_), do: false

  @doc """
  Check if the client supports structured output.
  """
  @spec supports_structured_output?(map()) :: boolean()
  def supports_structured_output?(%{adapter_type: :instructor_lite}), do: true
  def supports_structured_output?(_), do: false

  # Private functions

  defp select_best_adapter(opts) do
    cond do
      # Need structured output? Use InstructorLite
      opts[:response_model] ->
        :instructor_lite

      # Need streaming? Use HTTP
      opts[:stream] ->
        :http

      # Have a local model? Use Python
      opts[:local_model] ->
        :python

      # Default to first priority
      true ->
        hd(@default_adapter_priority)
    end
  end

  defp get_config_defaults do
    config = Application.get_env(:dspex, :llm, [])

    [
      adapter: config[:default_adapter],
      provider: config[:default_provider],
      model: config[:default_model]
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp get_default_provider(adapter_type) do
    config = Application.get_env(:dspex, :llm, [])
    adapter_config = get_in(config, [:adapters, adapter_type]) || []

    adapter_config[:default_provider] || config[:default_provider]
  end

  defp build_config(opts, adapter_type, provider) do
    # Get adapter and provider specific config
    config = Application.get_env(:dspex, :llm, [])
    adapter_config = get_in(config, [:adapters, adapter_type]) || []
    provider_config = get_in(adapter_config, [:providers, provider]) || []

    # Resolve environment variables
    provider_config = resolve_env_vars(provider_config)

    # Merge all configs: provider defaults < adapter defaults < user opts
    opts
    |> Keyword.drop([:adapter, :provider])
    |> Keyword.merge(provider_config)
    |> Map.new()
  end

  defp resolve_env_vars(config) do
    Enum.map(config, fn
      {:api_key, {:system, env_var}} ->
        {:api_key, System.get_env(env_var)}

      other ->
        other
    end)
  end

  defp enrich_client(client, adapter_type, opts) do
    client
    |> Map.put(:adapter_type, adapter_type)
    |> Map.put(:adapter_module, @adapters[adapter_type])
    |> Map.put(:created_at, DateTime.utc_now())
    |> Map.put(:id, generate_client_id())
    |> maybe_add_defaults(opts)
  end

  defp maybe_add_defaults(client, opts) do
    defaults = %{
      temperature: opts[:default_temperature],
      max_tokens: opts[:default_max_tokens],
      timeout: opts[:default_timeout] || 30_000
    }

    Map.put(client, :defaults, compact_map(defaults))
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp generate_client_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp emit_telemetry(operation, duration, client, result) do
    metadata = %{
      adapter: client.adapter_type,
      provider: client.provider,
      success: match?({:ok, _}, result)
    }

    :telemetry.execute(
      [:dspex, :llm, operation],
      %{duration: duration},
      metadata
    )
  end
end
