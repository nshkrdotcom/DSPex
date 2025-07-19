defmodule DSPex.LLM.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing LLM interactions.

  This adapter returns predefined responses, making it ideal for testing
  without making actual API calls.
  """

  @behaviour DSPex.LLM.Adapter

  @impl true
  def configure(provider, config) do
    client = %{
      adapter: __MODULE__,
      provider: provider,
      config: config,
      responses: config[:responses] || [],
      response_index: 0
    }

    {:ok, client}
  end

  @impl true
  def generate(client, prompt, _opts) do
    case get_next_response(client) do
      {response, _updated_client} ->
        # In a real implementation, we'd need to track state
        # For testing, we'll just return the response
        {:ok, format_response(response, prompt)}

      :no_responses ->
        {:error, :no_mock_responses_configured}
    end
  end

  @impl true
  def stream(client, _prompt, _opts) do
    case client.config[:stream_responses] do
      chunks when is_list(chunks) ->
        stream =
          Stream.unfold(chunks, fn
            [] -> nil
            [chunk | rest] -> {chunk, rest}
          end)

        {:ok, stream}

      _ ->
        {:error, :streaming_not_configured}
    end
  end

  @impl true
  def batch(client, prompts, opts) do
    # Generate a response for each prompt
    results =
      Enum.map(prompts, fn prompt ->
        case generate(client, prompt, opts) do
          {:ok, response} -> response
          {:error, _} = error -> error
        end
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, r} -> r end)}
    else
      {:error, :batch_generation_failed}
    end
  end

  # Private functions

  defp get_next_response(%{responses: responses, response_index: index}) do
    case Enum.at(responses, index) do
      nil -> :no_responses
      response -> {response, index + 1}
    end
  end

  defp format_response(response, prompt) when is_binary(response) do
    %{
      content: response,
      model: "mock-model",
      provider: :mock,
      adapter: :mock,
      metadata: %{
        prompt: prompt,
        mocked: true
      }
    }
  end

  defp format_response(response, prompt) when is_map(response) do
    Map.merge(
      %{
        model: "mock-model",
        provider: :mock,
        adapter: :mock,
        metadata: %{prompt: prompt, mocked: true}
      },
      response
    )
  end
end
