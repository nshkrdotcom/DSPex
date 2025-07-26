defmodule DSPex.Types.ReactResult do
  @moduledoc """
  Represents the result of a ReAct (Reasoning and Acting) operation.
  
  This struct contains the thought process, actions taken, observations made,
  and the final answer, representing the full ReAct loop.
  """
  
  @enforce_keys [:thought, :action, :observation, :answer]
  defstruct [
    :thought,
    :action,
    :observation,
    :answer,
    :iterations,
    :tool_calls,
    :metadata,
    :raw_response
  ]
  
  @type iteration :: %{
    thought: String.t(),
    action: String.t(),
    observation: String.t()
  }
  
  @type tool_call :: %{
    tool: String.t(),
    input: any(),
    output: any(),
    timestamp: DateTime.t() | nil
  }
  
  @type t :: %__MODULE__{
    thought: String.t(),
    action: String.t(),
    observation: String.t(),
    answer: String.t(),
    iterations: list(iteration()) | nil,
    tool_calls: list(tool_call()) | nil,
    metadata: map() | nil,
    raw_response: any()
  }
  
  @doc """
  Creates a new ReactResult with validation.
  """
  def new(attrs) when is_map(attrs) do
    with {:ok, thought} <- validate_thought(attrs[:thought] || attrs["thought"]),
         {:ok, action} <- validate_action(attrs[:action] || attrs["action"]),
         {:ok, observation} <- validate_observation(attrs[:observation] || attrs["observation"]),
         {:ok, answer} <- validate_answer(attrs[:answer] || attrs["answer"]),
         {:ok, iterations} <- validate_iterations(attrs[:iterations] || attrs["iterations"]),
         {:ok, tool_calls} <- validate_tool_calls(attrs[:tool_calls] || attrs["tool_calls"]),
         {:ok, metadata} <- validate_metadata(attrs[:metadata] || attrs["metadata"]) do
      {:ok, %__MODULE__{
        thought: thought,
        action: action,
        observation: observation,
        answer: answer,
        iterations: iterations,
        tool_calls: tool_calls,
        metadata: metadata,
        raw_response: attrs[:raw_response] || attrs["raw_response"]
      }}
    end
  end
  
  @doc """
  Converts a Python ReAct result to this struct.
  """
  def from_python_result(%{"thought" => thought, "action" => action, 
                          "observation" => observation, "answer" => answer} = result) do
    new(%{
      thought: thought,
      action: action,
      observation: observation,
      answer: answer,
      iterations: Map.get(result, "iterations"),
      tool_calls: Map.get(result, "tool_calls"),
      metadata: Map.get(result, "metadata"),
      raw_response: result
    })
  end
  
  def from_python_result(_), do: {:error, :invalid_react_format}
  
  @doc """
  Validates the struct instance.
  """
  def validate(%__MODULE__{} = result) do
    with {:ok, _} <- validate_thought(result.thought),
         {:ok, _} <- validate_action(result.action),
         {:ok, _} <- validate_observation(result.observation),
         {:ok, _} <- validate_answer(result.answer),
         {:ok, _} <- validate_iterations(result.iterations),
         {:ok, _} <- validate_tool_calls(result.tool_calls),
         {:ok, _} <- validate_metadata(result.metadata) do
      {:ok, result}
    end
  end
  
  def validate(_), do: {:error, :not_a_react_result}
  
  # Private validation functions
  defp validate_thought(nil), do: {:error, :thought_required}
  defp validate_thought(thought) when is_binary(thought), do: {:ok, thought}
  defp validate_thought(_), do: {:error, :thought_must_be_string}
  
  defp validate_action(nil), do: {:error, :action_required}
  defp validate_action(action) when is_binary(action), do: {:ok, action}
  defp validate_action(_), do: {:error, :action_must_be_string}
  
  defp validate_observation(nil), do: {:error, :observation_required}
  defp validate_observation(observation) when is_binary(observation), do: {:ok, observation}
  defp validate_observation(_), do: {:error, :observation_must_be_string}
  
  defp validate_answer(nil), do: {:error, :answer_required}
  defp validate_answer(answer) when is_binary(answer), do: {:ok, answer}
  defp validate_answer(_), do: {:error, :answer_must_be_string}
  
  defp validate_iterations(nil), do: {:ok, nil}
  defp validate_iterations(iterations) when is_list(iterations) do
    if Enum.all?(iterations, &valid_iteration?/1) do
      {:ok, iterations}
    else
      {:error, :invalid_iteration_format}
    end
  end
  defp validate_iterations(_), do: {:error, :iterations_must_be_list}
  
  defp validate_tool_calls(nil), do: {:ok, nil}
  defp validate_tool_calls(tool_calls) when is_list(tool_calls) do
    if Enum.all?(tool_calls, &valid_tool_call?/1) do
      {:ok, tool_calls}
    else
      {:error, :invalid_tool_call_format}
    end
  end
  defp validate_tool_calls(_), do: {:error, :tool_calls_must_be_list}
  
  defp validate_metadata(nil), do: {:ok, nil}
  defp validate_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp validate_metadata(_), do: {:error, :metadata_must_be_map}
  
  defp valid_iteration?(iteration) when is_map(iteration) do
    is_binary(iteration[:thought] || iteration["thought"]) and
    is_binary(iteration[:action] || iteration["action"]) and
    is_binary(iteration[:observation] || iteration["observation"])
  end
  defp valid_iteration?(_), do: false
  
  defp valid_tool_call?(tool_call) when is_map(tool_call) do
    is_binary(tool_call[:tool] || tool_call["tool"])
  end
  defp valid_tool_call?(_), do: false
end