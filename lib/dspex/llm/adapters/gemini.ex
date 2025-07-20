defmodule DSPex.LLM.Adapters.Gemini do
  @moduledoc """
  Adapter using gemini_ex for direct Gemini API interactions.

  This adapter provides native Gemini API access with support for:
  - Streaming responses
  - Multiple authentication strategies (Gemini API and Vertex AI)
  - Content generation and chat sessions
  - Model management
  """

  @behaviour DSPex.LLM.Adapter

  require Logger

  @default_model "gemini/gemini-2.0-flash-exp"
  @default_auth_strategy :gemini

  @impl true
  def configure(provider, config) when is_nil(provider) or provider == :gemini do
    # Validate required configuration
    auth_strategy = config[:auth_strategy] || @default_auth_strategy

    client_config =
      case auth_strategy do
        :gemini ->
          if config[:api_key] do
            %{
              adapter: __MODULE__,
              provider: :gemini,
              auth_strategy: :gemini,
              api_key: config[:api_key],
              model: config[:model] || @default_model,
              config: config
            }
          else
            {:error, :missing_api_key}
          end

        :vertex_ai ->
          if config[:project_id] && config[:location] do
            %{
              adapter: __MODULE__,
              provider: :gemini,
              auth_strategy: :vertex_ai,
              project_id: config[:project_id],
              location: config[:location],
              model: config[:model] || @default_model,
              config: config
            }
          else
            {:error, :missing_vertex_config}
          end

        _ ->
          {:error, {:unsupported_auth_strategy, auth_strategy}}
      end

    case client_config do
      {:error, _} = error -> error
      _ -> {:ok, client_config}
    end
  end

  def configure(provider, _config) do
    {:error, {:unsupported_provider, provider, [:gemini]}}
  end

  @impl true
  def generate(client, prompt, opts) do
    # Build auth options, including model
    auth_opts =
      build_auth_opts(client)
      |> Keyword.merge(opts)
      |> Keyword.put(:model, client.model)

    # Call gemini_ex - it accepts the prompt directly
    case Gemini.generate(prompt, auth_opts) do
      {:ok, response} ->
        {:ok, format_response(response, client)}

      {:error, reason} ->
        Logger.error("Gemini generation failed: #{inspect(reason)}")
        {:error, {:gemini_error, reason}}
    end
  end

  @impl true
  def stream(client, prompt, opts) do
    # Build auth options, including model
    auth_opts =
      build_auth_opts(client)
      |> Keyword.merge(opts)
      |> Keyword.put(:model, client.model)

    # Start streaming - pass callbacks if provided
    stream_opts =
      if opts[:on_chunk] || opts[:on_complete] do
        auth_opts
        |> Keyword.put(:on_chunk, opts[:on_chunk])
        |> Keyword.put(:on_complete, opts[:on_complete])
      else
        auth_opts
      end

    case Gemini.stream_generate(prompt, stream_opts) do
      {:ok, stream_id} ->
        # Return the stream ID for further control
        {:ok, stream_id}

      {:error, reason} ->
        Logger.error("Gemini streaming failed: #{inspect(reason)}")
        {:error, {:gemini_streaming_error, reason}}
    end
  end

  @impl true
  def batch(client, prompts, opts) do
    # Gemini doesn't have native batch support, fall back to concurrent generation
    tasks =
      Enum.map(prompts, fn prompt ->
        Task.async(fn -> generate(client, prompt, opts) end)
      end)

    results = Task.await_many(tasks, opts[:timeout] || 30_000)

    # Collect results
    results
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

  defp build_auth_opts(client) do
    base_opts = [
      auth: client.auth_strategy,
      model: client.model
    ]

    case client.auth_strategy do
      :gemini ->
        Keyword.put(base_opts, :api_key, client.api_key)

      :vertex_ai ->
        base_opts
        |> Keyword.put(:project_id, client.project_id)
        |> Keyword.put(:location, client.location)
    end
  end

  defp format_response(response, client) do
    # Extract text from Gemini response
    text = extract_text(response)

    %{
      content: text,
      model: client.model,
      provider: client.provider,
      adapter: :gemini,
      metadata: %{
        auth_strategy: client.auth_strategy,
        usage: extract_usage(response),
        raw_response: response
      }
    }
  end

  defp extract_text(%{candidates: [%{content: %{parts: parts}} | _]}) do
    parts
    |> Enum.map(fn
      %{text: text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_text(_), do: ""

  defp extract_usage(%{usage_metadata: usage}) when not is_nil(usage) do
    %{
      prompt_tokens: Map.get(usage, :prompt_token_count, 0),
      completion_tokens: Map.get(usage, :candidates_token_count, 0),
      total_tokens: Map.get(usage, :total_token_count, 0)
    }
  end

  defp extract_usage(_), do: %{}
end
