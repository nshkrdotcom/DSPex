defmodule DSPex.LLM.Adapters.HTTP do
  @moduledoc """
  HTTP adapter for direct LLM API calls.

  Supports multiple providers through their HTTP APIs with streaming support
  where available.
  """

  @behaviour DSPex.LLM.Adapter

  require Logger

  @provider_endpoints %{
    openai: "https://api.openai.com/v1/chat/completions",
    anthropic: "https://api.anthropic.com/v1/messages",
    groq: "https://api.groq.com/openai/v1/chat/completions",
    together: "https://api.together.xyz/v1/chat/completions"
  }

  @impl true
  def configure(provider, config) do
    endpoint =
      config[:endpoint] || @provider_endpoints[provider] ||
        build_gemini_endpoint(provider, config)

    if is_nil(endpoint) do
      {:error, {:missing_endpoint, provider}}
    else
      client = %{
        adapter: __MODULE__,
        provider: provider,
        endpoint: endpoint,
        headers: build_headers(provider, config),
        config: config
      }

      {:ok, client}
    end
  end

  @impl true
  def generate(client, prompt, opts) do
    body = build_request_body(client.provider, prompt, opts)

    request_opts = [
      headers: client.headers,
      json: body,
      receive_timeout: opts[:timeout] || 30_000
    ]

    case Req.post(client.endpoint, request_opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(client.provider, body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @impl true
  def stream(client, prompt, opts) do
    if supports_streaming?(client.provider) do
      body = build_request_body(client.provider, prompt, Keyword.put(opts, :stream, true))

      request_opts = [
        headers: client.headers,
        json: body,
        into: :stream
      ]

      case Req.post(client.endpoint, request_opts) do
        {:ok, response} ->
          stream = parse_sse_stream(response, client.provider)
          {:ok, stream}

        {:error, reason} ->
          {:error, {:stream_failed, reason}}
      end
    else
      {:error, :streaming_not_supported}
    end
  end

  @impl true
  def batch(client, prompts, opts) do
    # Most providers don't have native batch APIs, so we parallelize
    tasks =
      Enum.map(prompts, fn prompt ->
        Task.async(fn -> generate(client, prompt, opts) end)
      end)

    results = Task.await_many(tasks, opts[:timeout] || 30_000)

    # Check if all succeeded
    case Enum.reduce(results, {:ok, []}, &collect_results/2) do
      {:ok, responses} -> {:ok, Enum.reverse(responses)}
      error -> error
    end
  end

  # Private functions

  defp build_gemini_endpoint(:gemini, config) do
    model = config[:model] || "gemini/gemini-2.5-flash-lite"
    api_key = config[:api_key]

    if api_key do
      "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
    else
      nil
    end
  end

  defp build_gemini_endpoint(_, _), do: nil

  defp build_headers(:openai, config) do
    [
      {"Authorization", "Bearer #{config[:api_key]}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp build_headers(:anthropic, config) do
    [
      {"x-api-key", config[:api_key]},
      {"anthropic-version", "2023-06-01"},
      {"Content-Type", "application/json"}
    ]
  end

  defp build_headers(:gemini, _config) do
    # Gemini uses API key in URL, not headers
    [{"Content-Type", "application/json"}]
  end

  defp build_headers(_, config) do
    # Generic headers for other providers
    headers = [{"Content-Type", "application/json"}]

    if config[:api_key] do
      [{"Authorization", "Bearer #{config[:api_key]}"} | headers]
    else
      headers
    end
  end

  defp build_request_body(:openai, prompt, opts) do
    %{
      model: opts[:model] || "gpt-4",
      messages: format_messages(prompt),
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      stream: opts[:stream] || false
    }
    |> clean_nil_values()
  end

  defp build_request_body(:anthropic, prompt, opts) do
    %{
      model: opts[:model] || "claude-3-opus-20240229",
      messages: format_messages(prompt),
      max_tokens: opts[:max_tokens] || 1024,
      temperature: opts[:temperature],
      stream: opts[:stream] || false
    }
    |> clean_nil_values()
  end

  defp build_request_body(:gemini, prompt, opts) do
    generation_config =
      %{}
      |> maybe_put(:temperature, opts[:temperature])
      |> maybe_put(:maxOutputTokens, opts[:max_tokens])

    %{
      contents: format_gemini_content(prompt)
    }
    |> maybe_put(:generationConfig, generation_config)
  end

  defp build_request_body(_, prompt, opts) do
    # Generic OpenAI-compatible format
    %{
      model: opts[:model] || "default",
      messages: format_messages(prompt),
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens],
      stream: opts[:stream] || false
    }
    |> clean_nil_values()
  end

  defp format_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  defp format_messages(messages) when is_list(messages), do: messages

  defp format_gemini_content(prompt) when is_binary(prompt) do
    [%{parts: [%{text: prompt}]}]
  end

  defp format_gemini_content(messages) when is_list(messages) do
    Enum.map(messages, fn msg ->
      %{parts: [%{text: msg[:content] || msg["content"]}]}
    end)
  end

  defp clean_nil_values(map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, empty) when map_size(empty) == 0 and is_map(empty), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_response(:openai, %{"choices" => [%{"message" => message} | _]} = body) do
    %{
      content: message["content"],
      model: body["model"],
      provider: :openai,
      adapter: :http,
      metadata: %{
        usage: body["usage"],
        finish_reason: get_in(body, ["choices", Access.at(0), "finish_reason"])
      }
    }
  end

  defp parse_response(:anthropic, %{"content" => [%{"text" => text} | _]} = body) do
    %{
      content: text,
      model: body["model"],
      provider: :anthropic,
      adapter: :http,
      metadata: %{
        usage: body["usage"],
        stop_reason: body["stop_reason"]
      }
    }
  end

  defp parse_response(:gemini, %{"candidates" => [candidate | _]} = body) do
    text = get_in(candidate, ["content", "parts", Access.at(0), "text"])

    %{
      content: text,
      model: body["modelVersion"] || "gemini",
      provider: :gemini,
      adapter: :http,
      metadata: %{
        safety_ratings: candidate["safetyRatings"],
        usage: body["usageMetadata"]
      }
    }
  end

  defp parse_response(provider, body) do
    # Try to extract content in a generic way
    content =
      body["choices"] |> List.first() |> get_in(["message", "content"]) ||
        body["content"] ||
        body["text"] ||
        inspect(body)

    %{
      content: content,
      model: body["model"],
      provider: provider,
      adapter: :http,
      metadata: body
    }
  end

  defp supports_streaming?(provider) when provider in [:openai, :anthropic], do: true
  defp supports_streaming?(_), do: false

  defp parse_sse_stream(response, provider) do
    response.body
    |> Stream.map(&parse_sse_line(&1, provider))
    |> Stream.reject(&is_nil/1)
  end

  defp parse_sse_line("data: [DONE]" <> _, _), do: nil

  defp parse_sse_line("data: " <> json, provider) do
    case Jason.decode(json) do
      {:ok, data} -> parse_stream_chunk(provider, data)
      _ -> nil
    end
  end

  defp parse_sse_line(_, _), do: nil

  defp parse_stream_chunk(:openai, %{"choices" => [%{"delta" => delta} | _]}) do
    delta["content"]
  end

  defp parse_stream_chunk(:anthropic, %{"delta" => %{"text" => text}}) do
    text
  end

  defp parse_stream_chunk(_, _), do: nil

  defp collect_results({:ok, response}, {:ok, responses}) do
    {:ok, [response | responses]}
  end

  defp collect_results({:error, reason}, _) do
    {:error, {:batch_item_failed, reason}}
  end

  defp collect_results(_, error), do: error
end
