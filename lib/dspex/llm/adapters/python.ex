defmodule DSPex.LLM.Adapters.Python do
  @moduledoc """
  Python adapter for LLM calls through Snakepit.

  This adapter allows using Python LLM libraries like LiteLLM, Langchain,
  or custom implementations through the Snakepit bridge.
  """

  @behaviour DSPex.LLM.Adapter

  require Logger

  @impl true
  def configure(provider, config) do
    client = %{
      adapter: __MODULE__,
      provider: provider,
      config: config,
      pool: config[:pool] || :default,
      script: config[:script] || "llm_bridge.py"
    }

    {:ok, client}
  end

  @impl true
  def generate(client, prompt, opts) do
    request = build_request(:generate, client, prompt, opts)

    case Snakepit.execute(request.operation, request.args, pool: client.pool) do
      {:ok, response} ->
        {:ok, parse_response(response, client)}

      {:error, reason} ->
        Logger.error("Python LLM generation failed: #{inspect(reason)}")
        {:error, {:python_error, reason}}
    end
  end

  @impl true
  def stream(client, prompt, opts) do
    request = build_request(:stream, client, prompt, opts)

    case Snakepit.execute(request.operation, request.args, pool: client.pool, stream: true) do
      {:ok, stream} ->
        parsed_stream = Stream.map(stream, &parse_stream_chunk/1)
        {:ok, parsed_stream}

      {:error, :streaming_not_supported} ->
        {:error, :streaming_not_supported}

      {:error, reason} ->
        {:error, {:python_stream_error, reason}}
    end
  end

  @impl true
  def batch(client, prompts, opts) do
    request = build_batch_request(client, prompts, opts)

    case Snakepit.execute(request.operation, request.args, pool: client.pool) do
      {:ok, responses} when is_list(responses) ->
        parsed = Enum.map(responses, &parse_response(&1, client))
        {:ok, parsed}

      {:error, reason} ->
        {:error, {:python_batch_error, reason}}
    end
  end

  # Private functions

  defp build_request(operation, client, prompt, opts) do
    %{
      operation: "llm.#{operation}",
      args: %{
        provider: client.provider,
        prompt: format_prompt(prompt),
        config: Map.merge(client.config, Map.new(opts)),
        model: opts[:model] || client.config[:model],
        temperature: opts[:temperature],
        max_tokens: opts[:max_tokens]
      }
    }
  end

  defp build_batch_request(client, prompts, opts) do
    %{
      operation: "llm.batch",
      args: %{
        provider: client.provider,
        prompts: Enum.map(prompts, &format_prompt/1),
        config: Map.merge(client.config, Map.new(opts)),
        model: opts[:model] || client.config[:model]
      }
    }
  end

  defp format_prompt(prompt) when is_binary(prompt) do
    %{type: "text", content: prompt}
  end

  defp format_prompt(messages) when is_list(messages) do
    %{type: "messages", content: messages}
  end

  defp format_prompt(%{messages: messages}) do
    %{type: "messages", content: messages}
  end

  defp parse_response(%{"success" => true, "result" => result}, client) do
    %{
      content: result["content"] || result["text"],
      model: result["model"] || client.config[:model],
      provider: client.provider,
      adapter: :python,
      metadata: %{
        python_provider: result["provider"],
        usage: result["usage"],
        raw: result
      }
    }
  end

  defp parse_response(%{"success" => false, "error" => error}, _client) do
    {:error, {:python_llm_error, error}}
  end

  defp parse_stream_chunk(%{"chunk" => chunk}) do
    chunk["content"] || chunk["text"]
  end

  defp parse_stream_chunk(%{"error" => error}) do
    Logger.error("Stream chunk error: #{inspect(error)}")
    nil
  end

  defp parse_stream_chunk(data) do
    # Try to extract content in various ways
    data["content"] || data["text"] || inspect(data)
  end
end
