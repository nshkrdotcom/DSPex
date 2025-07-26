defmodule DSPex.Types.ChainOfThoughtResult do
  @moduledoc """
  Represents the result of a Chain of Thought reasoning operation.
  
  This struct contains both the step-by-step reasoning and the final answer,
  providing transparency into the reasoning process.
  """
  
  @enforce_keys [:reasoning, :answer]
  defstruct [
    :reasoning,
    :answer,
    :confidence,
    :steps,
    :metadata,
    :raw_response
  ]
  
  @type t :: %__MODULE__{
    reasoning: String.t(),
    answer: String.t(),
    confidence: float() | nil,
    steps: list(String.t()) | nil,
    metadata: map() | nil,
    raw_response: any()
  }
  
  @doc """
  Creates a new ChainOfThoughtResult with validation.
  """
  def new(attrs) when is_map(attrs) do
    with {:ok, reasoning} <- validate_reasoning(attrs[:reasoning] || attrs["reasoning"]),
         {:ok, answer} <- validate_answer(attrs[:answer] || attrs["answer"]),
         {:ok, confidence} <- validate_confidence(attrs[:confidence] || attrs["confidence"]),
         {:ok, steps} <- validate_steps(attrs[:steps] || attrs["steps"]),
         {:ok, metadata} <- validate_metadata(attrs[:metadata] || attrs["metadata"]) do
      {:ok, %__MODULE__{
        reasoning: reasoning,
        answer: answer,
        confidence: confidence,
        steps: steps,
        metadata: metadata,
        raw_response: attrs[:raw_response] || attrs["raw_response"]
      }}
    end
  end
  
  @doc """
  Converts a Python ChainOfThought result to this struct.
  """
  def from_python_result(%{"reasoning" => reasoning, "answer" => answer} = result) do
    new(%{
      reasoning: reasoning,
      answer: answer,
      confidence: Map.get(result, "confidence"),
      steps: Map.get(result, "steps"),
      metadata: Map.get(result, "metadata"),
      raw_response: result
    })
  end
  
  def from_python_result(%{"rationale" => rationale, "answer" => answer} = result) do
    # Alternative format used by some DSPy versions
    new(%{
      reasoning: rationale,
      answer: answer,
      confidence: Map.get(result, "confidence"),
      steps: Map.get(result, "steps"),
      metadata: Map.get(result, "metadata"),
      raw_response: result
    })
  end
  
  def from_python_result(_), do: {:error, :invalid_chain_of_thought_format}
  
  @doc """
  Validates the struct instance.
  """
  def validate(%__MODULE__{} = result) do
    with {:ok, _} <- validate_reasoning(result.reasoning),
         {:ok, _} <- validate_answer(result.answer),
         {:ok, _} <- validate_confidence(result.confidence),
         {:ok, _} <- validate_steps(result.steps),
         {:ok, _} <- validate_metadata(result.metadata) do
      {:ok, result}
    end
  end
  
  def validate(_), do: {:error, :not_a_chain_of_thought_result}
  
  # Private validation functions
  defp validate_reasoning(nil), do: {:error, :reasoning_required}
  defp validate_reasoning(reasoning) when is_binary(reasoning) and byte_size(reasoning) > 0 do
    {:ok, reasoning}
  end
  defp validate_reasoning(_), do: {:error, :reasoning_must_be_non_empty_string}
  
  defp validate_answer(nil), do: {:error, :answer_required}
  defp validate_answer(answer) when is_binary(answer), do: {:ok, answer}
  defp validate_answer(_), do: {:error, :answer_must_be_string}
  
  defp validate_confidence(nil), do: {:ok, nil}
  defp validate_confidence(confidence) when is_float(confidence) and confidence >= 0.0 and confidence <= 1.0 do
    {:ok, confidence}
  end
  defp validate_confidence(confidence) when is_integer(confidence) and confidence >= 0 and confidence <= 1 do
    {:ok, confidence / 1.0}
  end
  defp validate_confidence(_), do: {:error, :confidence_must_be_between_0_and_1}
  
  defp validate_steps(nil), do: {:ok, nil}
  defp validate_steps(steps) when is_list(steps) do
    if Enum.all?(steps, &is_binary/1) do
      {:ok, steps}
    else
      {:error, :steps_must_be_list_of_strings}
    end
  end
  defp validate_steps(_), do: {:error, :steps_must_be_list}
  
  defp validate_metadata(nil), do: {:ok, nil}
  defp validate_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp validate_metadata(_), do: {:error, :metadata_must_be_map}
end