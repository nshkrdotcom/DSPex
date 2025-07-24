defmodule DSPex.Modules.ChainOfThought do
  @moduledoc """
  Chain of Thought reasoning module.

  Enhanced with schema bridge for automatic DSPy integration.
  Generates step-by-step reasoning before producing the final answer.
  This helps with complex reasoning tasks and provides interpretability.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new ChainOfThought module instance.

  ## Examples

      {:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
      {:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{question: "Why is the sky blue?"})
      # Result includes: %{reasoning: "...", answer: "..."}
  """
  def create(signature, opts \\ []) do
    _session_id = opts[:session_id] || ID.generate("session")

    case DSPex.Bridge.create_instance("dspy.ChainOfThought", %{"signature" => signature}, opts) do
      {:ok, ref} ->
        {:ok, ref}

      {:error, error} ->
        require Logger
        Logger.error("ChainOfThought creation failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end

  @doc """
  Execute chain of thought reasoning with the given inputs.
  """
  def execute(cot_ref, inputs, opts \\ [])

  def execute({_session_id, _cot_id} = ref, inputs, opts) do
    case DSPex.Bridge.call_method(ref, "__call__", inputs, opts) do
      {:ok, %{"result" => raw_result}} ->
        {:ok, transform_cot_result(raw_result)}

      {:error, error} ->
        require Logger
        Logger.error("ChainOfThought execution failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end

  def execute(cot_id, inputs, opts) when is_binary(cot_id) do
    IO.warn("Using deprecated single-ID format. Please use {session_id, cot_id} format.")
    session_id = opts[:session_id] || ID.generate("session")
    execute({session_id, cot_id}, inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def think(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    with {:ok, cot_ref} <- create(signature, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- execute(cot_ref, inputs, opts) do
      {:ok, result}
    end
  end

  # Transform Python result to Elixir-friendly format
  defp transform_cot_result(raw_result) do
    case raw_result do
      %{"success" => true, "result" => %{"prediction_data" => _prediction_data}} ->
        # Already transformed by bridge
        raw_result

      %{"reasoning" => reasoning, "answer" => answer} ->
        # Handle DSPy ChainOfThought format
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"reasoning" => reasoning, "answer" => answer}}
        }

      %{"rationale" => rationale, "answer" => answer} ->
        # Alternative DSPy format
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"reasoning" => rationale, "answer" => answer}}
        }

      %{"completions" => completions} when is_list(completions) ->
        # Handle DSPy completion format
        completion = List.first(completions) || %{}
        %{"success" => true, "result" => %{"prediction_data" => completion}}

      result when is_map(result) ->
        %{"success" => true, "result" => %{"prediction_data" => result}}

      _ ->
        %{
          "success" => true,
          "result" => %{"prediction_data" => %{"answer" => to_string(raw_result)}}
        }
    end
  end

  # Parse Python traceback for meaningful error messages
  defp parse_dspy_error(error) do
    error_str = to_string(error)

    cond do
      String.contains?(error_str, "signature") ->
        "Invalid signature format"

      String.contains?(error_str, "LM not configured") ->
        "Language model not configured. Please call DSPex.LM.configure/2 first."

      String.contains?(error_str, "Invalid constructor arguments") ->
        "Invalid arguments for ChainOfThought constructor. Expected signature string."

      String.contains?(error_str, "worker_not_found") ->
        "No available workers to process request. Please check system resources."

      true ->
        error_str
    end
  end
end
