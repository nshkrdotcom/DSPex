defmodule DSPex.Types.Prediction do
  @moduledoc """
  Represents a prediction result from DSPy.
  
  This struct encapsulates the result of a prediction operation,
  including the answer and optional metadata like confidence scores.
  """
  
  @enforce_keys [:answer]
  defstruct [
    :answer,
    :confidence,
    :metadata,
    :raw_response,
    :reasoning
  ]
  
  @type t :: %__MODULE__{
    answer: String.t(),
    confidence: float() | nil,
    metadata: map() | nil,
    raw_response: any(),
    reasoning: String.t() | nil
  }
  
  @doc """
  Creates a new Prediction struct with validation.
  """
  def new(attrs) when is_map(attrs) do
    with {:ok, answer} <- validate_answer(attrs[:answer] || attrs["answer"]),
         {:ok, confidence} <- validate_confidence(attrs[:confidence] || attrs["confidence"]),
         {:ok, metadata} <- validate_metadata(attrs[:metadata] || attrs["metadata"]),
         {:ok, reasoning} <- validate_reasoning(attrs[:reasoning] || attrs["reasoning"]) do
      {:ok, %__MODULE__{
        answer: answer,
        confidence: confidence,
        metadata: metadata,
        raw_response: attrs[:raw_response] || attrs["raw_response"],
        reasoning: reasoning
      }}
    end
  end
  
  @doc """
  Converts a Python prediction result to this struct.
  
  Handles both simple string results and complex result dictionaries.
  """
  def from_python_result(%{"answer" => answer} = result) do
    # Extract known fields and convert answer to string if needed
    answer_str = if is_binary(answer), do: answer, else: to_string(answer)
    confidence = Map.get(result, "confidence")
    # Handle both "reasoning" and "rationale" fields
    reasoning = Map.get(result, "reasoning") || Map.get(result, "rationale")
    explicit_metadata = Map.get(result, "metadata", %{})
    
    # Collect any extra fields into metadata
    known_fields = ["answer", "confidence", "reasoning", "rationale", "metadata"]
    extra_fields = Map.drop(result, known_fields)
    
    # Merge explicit metadata with extra fields
    metadata = if map_size(extra_fields) > 0 do
      Map.merge(explicit_metadata, extra_fields)
    else
      if map_size(explicit_metadata) > 0, do: explicit_metadata, else: %{}
    end
    
    new(%{
      answer: answer_str,
      confidence: confidence,
      metadata: metadata,
      raw_response: result,
      reasoning: reasoning
    })
  end
  
  def from_python_result(%{answer: answer} = result) do
    # Extract known fields and convert answer to string if needed
    answer_str = if is_binary(answer), do: answer, else: to_string(answer)
    confidence = Map.get(result, :confidence)
    # Handle both "reasoning" and "rationale" fields
    reasoning = Map.get(result, :reasoning) || Map.get(result, :rationale)
    explicit_metadata = Map.get(result, :metadata, %{})
    
    # Collect any extra fields into metadata
    known_fields = [:answer, :confidence, :reasoning, :rationale, :metadata]
    extra_fields = Map.drop(result, known_fields)
    
    # Merge explicit metadata with extra fields
    metadata = if map_size(extra_fields) > 0 do
      Map.merge(explicit_metadata, extra_fields)
    else
      if map_size(explicit_metadata) > 0, do: explicit_metadata, else: %{}
    end
    
    new(%{
      answer: answer_str,
      confidence: confidence,
      metadata: metadata,
      raw_response: result,
      reasoning: reasoning
    })
  end
  
  def from_python_result(answer) when is_binary(answer) do
    new(%{answer: answer})
  end
  
  def from_python_result(answer) when is_number(answer) do
    new(%{answer: to_string(answer)})
  end
  
  def from_python_result(_), do: {:error, :invalid_prediction_format}
  
  @doc """
  Validates the struct instance.
  """
  def validate(%__MODULE__{} = prediction) do
    with {:ok, _} <- validate_answer(prediction.answer),
         {:ok, _} <- validate_confidence(prediction.confidence),
         {:ok, _} <- validate_metadata(prediction.metadata),
         {:ok, _} <- validate_reasoning(prediction.reasoning) do
      {:ok, prediction}
    end
  end
  
  def validate(_), do: {:error, :not_a_prediction}
  
  # Private validation functions
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
  
  defp validate_metadata(nil), do: {:ok, %{}}
  defp validate_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp validate_metadata(_), do: {:error, :metadata_must_be_map}
  
  defp validate_reasoning(nil), do: {:ok, nil}
  defp validate_reasoning(reasoning) when is_binary(reasoning), do: {:ok, reasoning}
  defp validate_reasoning(_), do: {:error, :reasoning_must_be_string}
end