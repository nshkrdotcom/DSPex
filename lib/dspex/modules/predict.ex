defmodule DSPex.Modules.Predict do
  @moduledoc """
  Basic prediction module - the simplest DSPy predictor.

  Enhanced with schema bridge for automatic DSPy integration.
  Directly generates outputs based on the signature without intermediate reasoning.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new Predict module instance.

  ## Examples

      {:ok, predictor} = DSPex.Modules.Predict.create("question -> answer")
      {:ok, result} = DSPex.Modules.Predict.execute(predictor, %{question: "What is DSPy?"})
  """
  def create(signature, opts \\ []) do
    _session_id = opts[:session_id] || ID.generate("session")

    case DSPex.Bridge.create_instance("dspy.Predict", %{"signature" => signature}, opts) do
      {:ok, ref} ->
        {:ok, ref}

      {:error, error} ->
        require Logger
        Logger.error("Predict creation failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end

  @doc """
  Execute a prediction with the given inputs.
  """
  def execute(predictor_ref, inputs, opts \\ [])

  def execute({_session_id, _predictor_id} = ref, inputs, opts) do
    case DSPex.Bridge.call_method(ref, "__call__", inputs, opts) do
      {:ok, %{"result" => raw_result}} ->
        {:ok, transform_prediction_result(raw_result)}

      {:error, error} ->
        require Logger
        Logger.error("Predict execution failed: #{error}")
        {:error, parse_dspy_error(error)}
    end
  end

  def execute(predictor_id, inputs, opts) when is_binary(predictor_id) do
    IO.warn("Using deprecated single-ID format. Please use {session_id, predictor_id} format.")
    session_id = opts[:session_id] || DSPex.Utils.ID.generate("session")
    execute({session_id, predictor_id}, inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def predict(signature, inputs, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")

    with {:ok, predictor_ref} <- create(signature, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- execute(predictor_ref, inputs, opts) do
      {:ok, result}
    end
  end

  # Transform Python result to Elixir-friendly format
  defp transform_prediction_result(raw_result) do
    case raw_result do
      %{"success" => true, "result" => %{"prediction_data" => _prediction_data}} ->
        # Already transformed by bridge
        raw_result

      %{"completions" => completions} when is_list(completions) ->
        # Handle DSPy completion format
        %{"success" => true, "result" => %{"prediction_data" => List.first(completions)}}

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
        "Invalid arguments for Predict constructor. Expected signature string."

      String.contains?(error_str, "worker_not_found") ->
        "No available workers to process request. Please check system resources."

      true ->
        error_str
    end
  end
end
