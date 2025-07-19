defmodule DSPex.LLM.Adapters.InstructorLite do
  @moduledoc """
  Adapter using InstructorLite for structured LLM interactions.

  InstructorLite provides structured prompting capabilities with automatic
  validation and retry logic for multiple LLM providers.
  """

  @behaviour DSPex.LLM.Adapter

  require Logger

  @supported_providers [:openai, :anthropic, :gemini, :grok, :llamacpp]

  @impl true
  def configure(provider, config) when provider in @supported_providers do
    client_config = %{
      adapter: __MODULE__,
      provider: provider,
      config: config,
      response_model: config[:response_model]
    }

    {:ok, client_config}
  end

  def configure(provider, _config) do
    {:error, {:unsupported_provider, provider, @supported_providers}}
  end

  @impl true
  def generate(client, prompt, opts) do
    # Build the input based on provider and prompt type
    input = format_prompt(client.provider, prompt)

    # Build instructor options
    instructor_opts = build_instructor_opts(client, opts)

    # Call InstructorLite
    case InstructorLite.instruct(input, instructor_opts) do
      {:ok, result} ->
        {:ok, format_response(result, client)}

      {:error, reason} ->
        Logger.error("InstructorLite generation failed: #{inspect(reason)}")
        {:error, {:instructor_lite_error, reason}}
    end
  end

  @impl true
  def stream(_client, _prompt, _opts) do
    # InstructorLite doesn't support streaming yet
    {:error, :streaming_not_supported}
  end

  @impl true
  def batch(client, prompts, opts) do
    # Fall back to sequential generation
    prompts
    |> Enum.map(&generate(client, &1, opts))
    |> Enum.reduce({:ok, []}, fn
      {:ok, response}, {:ok, responses} ->
        {:ok, responses ++ [response]}

      {:error, reason}, {:ok, _} ->
        {:error, {:batch_error, reason}}

      _, error ->
        error
    end)
  end

  # Private functions

  defp format_prompt(:gemini, prompt) when is_binary(prompt) do
    %{
      contents: [
        %{
          role: "user",
          parts: [%{text: prompt}]
        }
      ]
    }
  end

  defp format_prompt(:gemini, messages) when is_list(messages) do
    contents =
      Enum.map(messages, fn msg ->
        %{
          role: msg[:role] || msg["role"] || "user",
          parts: [%{text: msg[:content] || msg["content"]}]
        }
      end)

    %{contents: contents}
  end

  defp format_prompt(_provider, prompt) when is_binary(prompt) do
    %{messages: [%{role: "user", content: prompt}]}
  end

  defp format_prompt(_provider, messages) when is_list(messages) do
    %{messages: messages}
  end

  defp format_prompt(_provider, %{messages: _} = input), do: input
  defp format_prompt(_provider, %{contents: _} = input), do: input

  defp build_instructor_opts(client, opts) do
    base_opts = [
      adapter: get_instructor_adapter(client.provider),
      adapter_context: build_adapter_context(client)
    ]

    # Add response model if provided
    response_model = opts[:response_model] || client[:response_model]

    base_opts =
      if response_model do
        Keyword.put(base_opts, :response_model, response_model)
      else
        base_opts
      end

    # Add optional parameters
    base_opts
    |> maybe_add_opt(:max_retries, opts[:max_retries])
    |> maybe_add_opt(:validation, opts[:validation])
  end

  defp get_instructor_adapter(:openai), do: InstructorLite.Adapters.OpenAI
  defp get_instructor_adapter(:anthropic), do: InstructorLite.Adapters.Anthropic
  defp get_instructor_adapter(:gemini), do: InstructorLite.Adapters.Gemini
  defp get_instructor_adapter(:grok), do: InstructorLite.Adapters.Grok
  defp get_instructor_adapter(:llamacpp), do: InstructorLite.Adapters.Llamacpp
  defp get_instructor_adapter(_), do: InstructorLite.Adapters.OpenAI

  defp build_adapter_context(client) do
    # Build provider-specific context - only include what the adapter expects
    case client.provider do
      :gemini ->
        [api_key: client.config[:api_key]]

      provider when provider in [:openai, :anthropic, :grok] ->
        [api_key: client.config[:api_key]]
        |> maybe_add_context_opt(:model, client.config[:model])

      :llamacpp ->
        [url: client.config[:url] || "http://localhost:8080"]

      _ ->
        []
    end
  end

  defp maybe_add_context_opt(context, _key, nil), do: context
  defp maybe_add_context_opt(context, key, value), do: Keyword.put(context, key, value)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_response(result, client) do
    %{
      content: result,
      model: client.config[:model],
      provider: client.provider,
      adapter: :instructor_lite,
      metadata: %{
        structured: true,
        response_model: client.response_model
      }
    }
  end
end
