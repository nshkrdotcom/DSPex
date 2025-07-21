defmodule DSPEx.MockClientManager do
  @moduledoc """
  A dedicated mock implementation of ClientManager for testing purposes.

  This module provides a complete mock of the ClientManager interface without
  making real API calls or relying on global environment variables. It's designed
  to be used in test environments where API keys are not available or where
  deterministic, fast test execution is required.

  Key features:
  - Implements the full ClientManager behavior interface
  - Provides contextual responses based on message content
  - Maintains realistic request statistics
  - Supports configurable failure scenarios for robustness testing
  - Zero global state contamination
  - Telemetry integration for observability
  """

  use GenServer
  require Logger

  # Default configuration for mock behavior
  @default_opts %{
    simulate_delays: false,
    failure_rate: 0.0,
    base_delay_ms: 50,
    max_delay_ms: 200,
    responses: :contextual
  }

  @enforce_keys [:provider]
  defstruct [
    :provider,
    :opts,
    :stats,
    :responses,
    :request_count,
    :start_time
  ]

  @type t :: %__MODULE__{
          provider: atom(),
          opts: map(),
          stats: map(),
          responses: list() | atom(),
          request_count: non_neg_integer(),
          start_time: DateTime.t()
        }

  ## Public API

  @doc """
  Starts a mock client manager for the specified provider.

  ## Options

  - `:simulate_delays` - Add realistic response delays (default: false)
  - `:failure_rate` - Fraction of requests that should fail (0.0-1.0, default: 0.0)
  - `:base_delay_ms` - Base delay in milliseconds (default: 50)
  - `:max_delay_ms` - Maximum delay in milliseconds (default: 200)
  - `:responses` - Response strategy (:contextual, :fixed, or list of responses)

  ## Examples

      # Basic mock client
      {:ok, client} = MockClientManager.start_link(:gemini)

      # Mock client with failures for robustness testing
      {:ok, client} = MockClientManager.start_link(:gemini, %{failure_rate: 0.1})

      # Mock client with realistic delays
      {:ok, client} = MockClientManager.start_link(:openai, %{simulate_delays: true})
  """
  def start_link(provider, opts \\ %{}) do
    GenServer.start_link(__MODULE__, {provider, opts})
  end

  @doc """
  Makes a mock request that simulates the ClientManager.request/3 interface.

  Returns contextual responses based on message content or configured responses.
  """
  def request(client, messages, opts \\ %{}) do
    # Use timeout from options, default to 30 seconds
    timeout = Map.get(opts, :timeout, 30_000)
    GenServer.call(client, {:request, messages, opts}, timeout)
  end

  @doc """
  Gets statistics for the mock client, matching ClientManager.get_stats/1 interface.
  """
  def get_stats(client) do
    GenServer.call(client, :get_stats)
  end

  @doc """
  Gets the provider type for this mock client.
  """
  def get_provider(client) do
    GenServer.call(client, :get_provider)
  end

  ## GenServer Implementation

  @impl GenServer
  def init({provider, opts}) do
    # Merge provided options with defaults
    opts = Map.merge(@default_opts, opts)

    # Initialize state
    state = %__MODULE__{
      provider: provider,
      opts: opts,
      request_count: 0,
      start_time: DateTime.utc_now(),
      responses: load_responses(opts.responses),
      stats: initial_stats(provider)
    }

    Logger.debug("MockClientManager started for provider #{provider} with opts: #{inspect(opts)}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:request, messages, opts}, _from, state) do
    # Simulate processing delay if configured
    if state.opts.simulate_delays do
      delay = calculate_delay(state.opts)
      Process.sleep(delay)
    end

    # Check for configured failures
    response =
      if should_fail?(state.opts.failure_rate) do
        generate_error_response()
      else
        generate_success_response(messages, state.responses)
      end

    # Update state with request metrics
    new_state = update_request_stats(state, response)

    # Emit telemetry
    emit_request_telemetry(state.provider, response, opts)

    {:reply, response, new_state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = %{
      stats: state.stats,
      provider: state.provider,
      status: :active,
      last_request_at: DateTime.utc_now()
    }

    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_call(:get_provider, _from, state) do
    {:reply, state.provider, state}
  end

  ## Private Implementation

  defp initial_stats(provider) do
    %{
      requests_made: 0,
      successful_requests: 0,
      failed_requests: 0,
      total_duration_ms: 0,
      average_response_time_ms: 0.0,
      provider: provider,
      mock_mode: true
    }
  end

  defp load_responses(:contextual), do: :contextual
  defp load_responses(:fixed), do: [%{answer: "Mock response"}]
  defp load_responses(responses) when is_list(responses), do: responses
  defp load_responses(_), do: :contextual

  defp should_fail?(failure_rate) when failure_rate <= 0.0, do: false
  defp should_fail?(failure_rate) when failure_rate >= 1.0, do: true

  defp should_fail?(failure_rate) do
    :rand.uniform() < failure_rate
  end

  defp calculate_delay(opts) do
    base = opts.base_delay_ms
    max_extra = opts.max_delay_ms - base
    base + :rand.uniform(max(max_extra, 1))
  end

  defp generate_error_response do
    error_types = [:network_error, :api_error, :timeout, :rate_limit]
    error_type = Enum.random(error_types)
    {:error, error_type}
  end

  defp generate_success_response(messages, :contextual) do
    # Check if there are predefined responses for this provider first
    # Try multiple provider keys as fallback
    {provider_responses, used_provider} =
      [:gemini, :openai, :gpt4, :gpt3_5, :teacher, :student]
      |> Enum.find_value({[], nil}, fn provider ->
        responses = :persistent_term.get({:mock_responses, provider}, [])
        if Enum.empty?(responses), do: nil, else: {responses, provider}
      end)

    response_content =
      if Enum.empty?(provider_responses) do
        IO.puts("🔍 MockClientManager: No preset responses found, using contextual")
        # Generate contextual responses based on message content
        generate_contextual_response(messages)
      else
        IO.puts(
          "🔍 MockClientManager: Using preset responses from #{used_provider} (#{length(provider_responses)} available)"
        )

        # Use predefined responses, cycling through them
        index = rem(:rand.uniform(1000), length(provider_responses))
        response = Enum.at(provider_responses, index)

        case response do
          %{content: content} -> content
          content when is_binary(content) -> content
          _ -> generate_contextual_response(messages)
        end
      end

    # Return in the same format as real API responses
    {:ok,
     %{
       choices: [
         %{message: %{role: "assistant", content: response_content}}
       ]
     }}
  end

  defp generate_success_response(_messages, responses) when is_list(responses) do
    # Use predefined responses, cycling through them
    index = rem(:rand.uniform(1000), length(responses))
    response = Enum.at(responses, index)

    # Ensure response is in the correct API format
    case response do
      # Already in correct format
      {:ok, %{choices: _}} ->
        response

      {:ok, %{answer: content}} ->
        # Convert old format to new format
        {:ok,
         %{
           choices: [
             %{message: %{role: "assistant", content: content}}
           ]
         }}

      {:ok, content} when is_binary(content) ->
        {:ok,
         %{
           choices: [
             %{message: %{role: "assistant", content: content}}
           ]
         }}

      # Keep error responses as is
      {:error, _} = error ->
        error

      # Return as is for unknown formats
      _ ->
        response
    end
  end

  defp generate_contextual_response(messages) when is_list(messages) do
    # Extract content from the last user message
    content =
      messages
      |> Enum.reverse()
      |> Enum.find_value(fn msg ->
        case msg do
          %{role: "user", content: content} -> content
          %{"role" => "user", "content" => content} -> content
          _ -> nil
        end
      end)

    generate_contextual_response_for_content(content || "")
  end

  defp generate_contextual_response(content) when is_binary(content) do
    generate_contextual_response_for_content(content)
  end

  defp generate_contextual_response(_), do: "Mock response for unknown message format"

  # Mock response patterns organized by category
  @response_patterns [
    # Math questions - provide realistic answers
    {["2+2", "2 + 2", "what is 2+2"], "4"},
    {["3+3", "3 + 3", "what is 3+3"], "6"},
    {["25% of 80", "25 percent of 80"], "20"},
    {["15 apples", "sells 7", "gets 8"],
     "Starting with 15 apples. After selling 7: 15 - 7 = 8 apples. After getting 8 more: 8 + 8 = 16 apples. The answer is 16."},
    {["apples", "selling", "getting"], "16"},
    {["reasoning", "step-by-step", "chain of thought"],
     "Let me think step by step. First, I need to identify the problem. Then I'll work through each part systematically to reach the correct answer."},
    {["math", "calculate", "sum", "add"], "42"},
    # Capital questions
    {["capital of france", "capital france"], "Paris"},
    {["capital of", "capital"], "The capital city (mock response)"},
    # Greetings
    {["hello", "hi", "hey"], "Hello! This is a mock response."},
    # Questions about testing
    {["test", "testing", "mock"], "This is indeed a mock response for testing purposes."},
    # Integration test patterns
    {["integration", "client", "manager"], "Mock ClientManager integration test response."},
    # Network or API related
    {["network", "api", "request"], "Mock API response - no actual network request made."}
  ]

  defp generate_contextual_response_for_content(content) do
    content_lower = String.downcase(content)

    # Try pattern matching first
    case find_matching_response(content_lower, @response_patterns) do
      {:ok, response} -> response
      :not_found -> check_special_patterns(content, content_lower)
    end
  end

  defp find_matching_response(content_lower, patterns) do
    patterns
    |> Enum.find_value(:not_found, fn {keywords, response} ->
      if String.contains?(content_lower, keywords), do: {:ok, response}
    end)
  end

  defp check_special_patterns(content, content_lower) do
    cond do
      # Question answering patterns
      String.contains?(content_lower, ["question:", "answer:", "qa"]) ->
        generate_qa_response(content)

      # Chain of thought patterns
      String.contains?(content_lower, ["reasoning:", "think step", "step by step"]) ->
        generate_cot_response(content)

      # Default contextual response
      String.length(content) > 0 ->
        "Mock response for: #{String.slice(content, 0, 50)}#{if String.length(content) > 50, do: "...", else: ""}"

      # Empty content
      true ->
        "Mock response for empty or unrecognized input"
    end
  end

  defp generate_qa_response(content) do
    get_qa_responses()
    |> Enum.find_value(fn {pattern, response} ->
      if pattern_matches?(content, pattern), do: response
    end) || "This is a mock answer for testing."
  end

  defp get_qa_responses do
    [
      {["2+2"], "4"},
      {["3+3"], "6"},
      {["capital of France"], "Paris"},
      {["apples", "reasoning"],
       "Starting with 15 apples. After selling 7: 15 - 7 = 8 apples. After getting 8 more: 8 + 8 = 16 apples.\n16"},
      {["apples"], "16"},
      {["rectangle", "area"], "Area of rectangle = length × width. Area = 8 × 5 = 40.\n40"},
      {["books", "cost"], "3 books cost $15 total. Cost per book = $15 ÷ 3 = $5.\n$5"}
    ]
  end

  defp pattern_matches?(content, patterns) do
    Enum.all?(patterns, &String.contains?(content, &1))
  end

  defp generate_cot_response(content) do
    cond do
      String.contains?(content, "apples") ->
        "Starting with 15 apples. After selling 7: 15 - 7 = 8 apples. After getting 8 more: 8 + 8 = 16 apples.\n16"

      String.contains?(content, "25%") ->
        "25% means 25/100 or 0.25. To find 25% of 80: 80 × 0.25 = 20.\n20"

      String.contains?(content, "rectangle") ->
        "Area of rectangle = length × width. Area = 8 × 5 = 40.\n40"

      String.contains?(content, "books") ->
        "3 books cost $15 total. Cost per book = $15 ÷ 3 = $5.\n$5"

      true ->
        "Let me think about this step by step. First, I'll analyze the problem, then work through each component to reach a logical conclusion.\nGeneric answer"
    end
  end

  defp update_request_stats(state, response) do
    # Calculate simulated duration
    duration =
      if state.opts.simulate_delays do
        state.opts.base_delay_ms +
          :rand.uniform(state.opts.max_delay_ms - state.opts.base_delay_ms)
      else
        # Minimal duration for mock
        1
      end

    # Update counters
    new_count = state.request_count + 1

    {successful, failed} =
      case response do
        {:ok, _} -> {state.stats.successful_requests + 1, state.stats.failed_requests}
        {:error, _} -> {state.stats.successful_requests, state.stats.failed_requests + 1}
      end

    total_duration = state.stats.total_duration_ms + duration
    avg_response_time = if new_count > 0, do: total_duration / new_count, else: 0.0

    # Update state
    new_stats = %{
      state.stats
      | requests_made: new_count,
        successful_requests: successful,
        failed_requests: failed,
        total_duration_ms: total_duration,
        average_response_time_ms: avg_response_time
    }

    %{state | request_count: new_count, stats: new_stats}
  end

  defp emit_request_telemetry(provider, response, opts) do
    # Extract correlation_id if present
    correlation_id = opts[:correlation_id] || "mock-#{:rand.uniform(10000)}"

    # Emit telemetry events matching real ClientManager
    measurements = %{duration: 1, request_size: 100, response_size: 50}

    metadata = %{
      provider: provider,
      mock_mode: true,
      correlation_id: correlation_id,
      success: match?({:ok, _}, response)
    }

    :telemetry.execute([:dspex, :client_manager, :request], measurements, metadata)
  end

  ## Additional functions for BEACON test infrastructure

  @doc """
  Sets mock responses for a specific provider.

  This allows tests to configure specific responses that will be returned
  for requests to a given provider.
  """
  @spec set_mock_responses(atom(), list()) :: :ok
  def set_mock_responses(provider, responses) do
    # Store in a simple ETS table or process registry for now
    # This is a basic implementation for test support
    key = {:mock_responses, provider}
    :persistent_term.put(key, responses)
    :ok
  end

  @doc """
  Gets the configured mock responses for a provider.
  """
  @spec get_mock_responses(atom()) :: list()
  def get_mock_responses(provider) do
    key = {:mock_responses, provider}
    :persistent_term.get(key, [])
  catch
    :error, :badarg -> []
  end

  @doc """
  Clears mock responses for a specific provider.
  """
  @spec clear_mock_responses(atom()) :: :ok
  def clear_mock_responses(provider) do
    key = {:mock_responses, provider}
    :persistent_term.erase(key)
    :ok
  catch
    :error, :badarg -> :ok
  end

  @doc """
  Clears all mock responses.
  """
  @spec clear_all_mock_responses() :: :ok
  def clear_all_mock_responses do
    # Get all persistent_term keys and clear mock-related ones
    :persistent_term.get()
    |> Enum.each(fn
      {{:mock_responses, _provider}, _value} = key_value ->
        {key, _} = key_value
        :persistent_term.erase(key)

      _ ->
        :ok
    end)

    :ok
  end
end
