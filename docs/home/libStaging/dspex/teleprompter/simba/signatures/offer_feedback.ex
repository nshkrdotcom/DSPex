defmodule DSPEx.Teleprompter.SIMBA.Signatures.OfferFeedback do
  @moduledoc """
  Signature for LLM-generated instruction refinement based on trajectory analysis.

  This signature is used by the AppendRule strategy to analyze successful vs
  unsuccessful program execution trajectories and generate improved instructions
  that help the program perform better on similar tasks.

  Based on DSPy's OfferFeedback signature from simba_utils.py.
  """

  @doc """
  Returns the signature definition for validation and introspection.
  """
  def signature_definition do
    %{
      description: "Generate instruction improvements from trajectory analysis",
      inputs: %{
        program_code: %{
          type: :string,
          description: "Program code being analyzed",
          required: true
        },
        modules_defn: %{
          type: :string,
          description: "Module definitions",
          required: true
        },
        better_program_trajectory: %{
          type: :string,
          description: "Successful execution trace",
          required: true,
          min_length: 50
        },
        worse_program_trajectory: %{
          type: :string,
          description: "Failed execution trace",
          required: true,
          min_length: 50
        }
      },
      outputs: %{
        module_advice: %{
          type: :map,
          description: "Generated advice per module",
          required: true
        }
      }
    }
  end

  @doc """
  Validates module advice output format.
  """
  def validate_module_advice(advice) when is_map(advice) do
    # Must have at least one entry and all values must be strings with meaningful content
    case Map.values(advice) do
      # Empty advice is not valid
      [] -> false
      values -> Enum.all?(values, &(is_binary(&1) && String.length(&1) > 10))
    end
  end

  def validate_module_advice(_), do: false

  # Custom validation for input fields with trajectory length requirements
  def validate_inputs(inputs) when is_map(inputs) do
    # First do basic field presence validation
    case basic_field_validation(inputs) do
      {:ok, validated_inputs} ->
        # Then apply our custom validation rules
        validate_trajectory_lengths(validated_inputs)

      error ->
        error
    end
  end

  # Basic field presence validation (same logic as DSPEx.Signature generates)
  defp basic_field_validation(inputs) do
    required_inputs =
      MapSet.new([
        :program_code,
        :modules_defn,
        :better_program_trajectory,
        :worse_program_trajectory
      ])

    provided_inputs = MapSet.new(Map.keys(inputs))

    missing = MapSet.difference(required_inputs, provided_inputs)

    case MapSet.size(missing) do
      0 -> {:ok, inputs}
      _ -> {:error, {:missing_inputs, MapSet.to_list(missing)}}
    end
  end

  # Custom validation for trajectory field lengths
  defp validate_trajectory_lengths(inputs) do
    better_trajectory = inputs[:better_program_trajectory]
    worse_trajectory = inputs[:worse_program_trajectory]

    cond do
      String.length(better_trajectory) < 50 ->
        {:error, "better_program_trajectory must be at least 50 characters"}

      String.length(worse_trajectory) < 50 ->
        {:error, "worse_program_trajectory must be at least 50 characters"}

      true ->
        {:ok, inputs}
    end
  end

  # Use DSPEx.Signature after defining custom functions to prevent override
  use DSPEx.Signature,
      "program_code, modules_defn, better_program_trajectory, worse_program_trajectory -> module_advice"
end
