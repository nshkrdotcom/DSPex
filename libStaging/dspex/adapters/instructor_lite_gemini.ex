defmodule DSPEx.Adapters.InstructorLiteGemini do
  @moduledoc """
  DSPEx adapter that uses InstructorLite for structured outputs with Gemini.

  This adapter integrates InstructorLite's structured output capabilities
  with DSPEx's signature system, providing automatic JSON schema generation
  and validation for Gemini responses.

  ## Usage

      # Define a signature with structured outputs
      defmodule QASignature do
        use DSPEx.Signature, "question -> answer, reasoning, confidence"
      end

      # Create a predict program using InstructorLite adapter
      program = DSPEx.Predict.new(QASignature, :gemini,
        adapter: DSPEx.Adapters.InstructorLiteGemini)

      # Get structured response
      {:ok, result} = DSPEx.Program.forward(program, %{question: "What is 2+2?"})
      # result => %{answer: "4", reasoning: "Basic arithmetic", confidence: "high"}

  """

  # Note: DSPEx.Adapter is not a formal behavior, but we follow its interface

  @doc """
  Format messages for InstructorLite + Gemini structured output.

  Converts DSPEx signature and inputs into InstructorLite-compatible
  parameters with proper JSON schema for structured responses.
  """
  def format_messages(signature, demos, inputs) do
    with {:ok, question_text} <- build_question_text(signature, inputs, demos),
         {:ok, response_model} <- build_response_model(signature),
         {:ok, json_schema} <- build_json_schema(signature) do
      # Build Gemini contents format
      contents = [
        %{
          role: "user",
          parts: [%{text: question_text}]
        }
      ]

      # InstructorLite parameters
      params = %{contents: contents}

      instructor_opts = [
        response_model: response_model,
        json_schema: json_schema,
        adapter: InstructorLite.Adapters.Gemini,
        adapter_context: [
          model: get_gemini_model(),
          api_key: get_gemini_api_key()
        ],
        max_retries: 1
      ]

      {:ok, {params, instructor_opts}}
    end
  end

  @doc """
  Parse InstructorLite response into DSPEx format.

  Takes the structured response from InstructorLite and converts it
  back to the expected DSPEx signature output format.
  """
  def parse_response(signature, instructor_result) do
    case instructor_result do
      {:ok, parsed_data} when is_map(parsed_data) ->
        # Convert the Ecto struct back to a plain map if needed
        result_map = struct_to_map(parsed_data)

        # Validate that all expected output fields are present
        output_fields = signature.output_fields()

        if all_fields_present?(result_map, output_fields) do
          {:ok, result_map}
        else
          {:error, {:missing_fields, output_fields, Map.keys(result_map)}}
        end

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:error, {:validation_failed, changeset.errors}}

      {:error, reason} ->
        {:error, {:instructor_lite_error, reason}}

      # Handle case where instructor_result is already a plain map (not wrapped in {:ok, _})
      parsed_data when is_map(parsed_data) ->
        result_map = struct_to_map(parsed_data)
        output_fields = signature.output_fields()

        if all_fields_present?(result_map, output_fields) do
          {:ok, result_map}
        else
          {:error, {:missing_fields, output_fields, Map.keys(result_map)}}
        end
    end
  end

  # Private helper functions

  defp build_question_text(signature, inputs, demos) do
    input_text = format_inputs(signature, inputs)
    demo_text = format_demos(signature, demos)

    question =
      case demo_text do
        "" -> input_text
        demos -> "Here are some examples:\n\n#{demos}\n\nNow answer this:\n#{input_text}"
      end

    {:ok, question}
  end

  defp format_inputs(signature, inputs) do
    input_fields = signature.input_fields()

    Enum.map_join(input_fields, "\n", fn field ->
      value = Map.get(inputs, field) || Map.get(inputs, to_string(field))
      "#{field}: #{value}"
    end)
  end

  defp format_demos(signature, demos) when is_list(demos) do
    Enum.map_join(demos, "\n\n", &format_single_demo(signature, &1))
  end

  defp format_demos(_, _), do: ""

  defp format_single_demo(signature, demo) do
    input_text = format_inputs(signature, demo.inputs)
    output_text = format_outputs(signature, demo.outputs)

    "#{input_text}\n#{output_text}"
  end

  defp format_outputs(signature, outputs) do
    output_fields = signature.output_fields()

    Enum.map_join(output_fields, "\n", fn field ->
      value = Map.get(outputs, field) || Map.get(outputs, to_string(field))
      "#{field}: #{value}"
    end)
  end

  defp build_response_model(signature) do
    # Create a dynamic Ecto schema for the signature
    output_fields = signature.output_fields()

    # For now, create a simple map-based response model
    # InstructorLite can work with schemaless definitions
    field_types =
      output_fields
      |> Enum.map(fn field -> {field, :string} end)
      |> Enum.into(%{})

    {:ok, field_types}
  end

  defp build_json_schema(signature) do
    output_fields = signature.output_fields()

    properties =
      output_fields
      |> Enum.map(fn field ->
        {to_string(field), build_field_schema(field)}
      end)
      |> Enum.into(%{})

    schema = %{
      type: "object",
      required: Enum.map(output_fields, &to_string/1),
      properties: properties
    }

    {:ok, schema}
  end

  defp build_field_schema(:confidence) do
    %{
      type: "string",
      enum: ["low", "medium", "high"],
      description: "Confidence level in the response"
    }
  end

  defp build_field_schema(:reasoning) do
    %{
      type: "string",
      description: "Step-by-step reasoning behind the answer"
    }
  end

  defp build_field_schema(field) do
    %{
      type: "string",
      description: "The #{field} for this response"
    }
  end

  defp get_gemini_model do
    case DSPEx.Services.ConfigManager.get([:providers, :gemini]) do
      {:ok, config} -> config.default_model
      _ -> "gemini-1.5-flash"
    end
  end

  defp get_gemini_api_key do
    case DSPEx.Services.ConfigManager.get([:providers, :gemini]) do
      {:ok, config} ->
        case config.api_key do
          {:system, var_name} -> System.get_env(var_name)
          key when is_binary(key) -> key
          _ -> nil
        end

      _ ->
        System.get_env("GEMINI_API_KEY")
    end
  end

  defp struct_to_map(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp struct_to_map(map) when is_map(map), do: map

  defp all_fields_present?(result_map, expected_fields) do
    expected_fields
    |> Enum.all?(fn field ->
      Map.has_key?(result_map, field) || Map.has_key?(result_map, to_string(field))
    end)
  end
end
