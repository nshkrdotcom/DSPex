defmodule DSPEx.Adapter do
  @moduledoc """
  Translation layer between DSPEx signatures and LLM API messages.

  Handles conversion of signature inputs to API request messages and parsing
  of API responses back to signature outputs.

  ## Examples

      iex> signature = MySignature  # has fields: question -> answer
      iex> inputs = %{question: "What is 2+2?"}
      iex> messages = DSPEx.Adapter.format_messages(signature, inputs)
      iex> messages
      [%{role: "user", content: "What is 2+2?"}]
      
      iex> response = %{choices: [%{message: %{content: "4"}}]}
      iex> {:ok, outputs} = DSPEx.Adapter.parse_response(signature, response)
      iex> outputs
      %{answer: "4"}

  """

  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type messages :: [DSPEx.Client.message()]
  @type api_response :: DSPEx.Client.response()

  @doc """
  Convert signature inputs to LLM API messages.

  Takes a signature module and input values, formats them into a message
  list suitable for the LLM API.

  ## Parameters

  - `signature` - Signature module defining input/output fields
  - `inputs` - Map of input field values

  ## Returns

  - `{:ok, messages}` - Formatted message list
  - `{:error, reason}` - Error with validation or formatting

  """
  @spec format_messages(signature(), inputs()) :: {:ok, messages()} | {:error, atom()}
  def format_messages(signature, inputs) do
    with {:ok, input_fields} <- get_input_fields(signature),
         {:ok, validated_inputs} <- validate_inputs(input_fields, inputs),
         {:ok, prompt} <- build_prompt(signature, validated_inputs) do
      messages = [%{role: "user", content: prompt}]
      {:ok, messages}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parse LLM API response to signature outputs.

  Takes an API response and extracts the output values according to
  the signature's output field definitions.

  ## Parameters

  - `signature` - Signature module defining input/output fields
  - `response` - API response with choices

  ## Returns

  - `{:ok, outputs}` - Parsed output values map
  - `{:error, reason}` - Error with parsing or validation

  """
  @spec parse_response(signature(), api_response()) :: {:ok, outputs()} | {:error, atom()}
  def parse_response(signature, response) do
    with {:ok, output_fields} <- get_output_fields(signature),
         {:ok, response_text} <- extract_response_text(response),
         {:ok, parsed_outputs} <- parse_output_text(output_fields, response_text) do
      {:ok, parsed_outputs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  @spec get_input_fields(signature()) :: {:ok, [atom()]} | {:error, :invalid_signature}
  defp get_input_fields(signature) do
    if function_exported?(signature, :input_fields, 0) do
      {:ok, signature.input_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  @spec get_output_fields(signature()) :: {:ok, [atom()]} | {:error, :invalid_signature}
  defp get_output_fields(signature) do
    if function_exported?(signature, :output_fields, 0) do
      {:ok, signature.output_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  @spec validate_inputs([atom()], inputs()) ::
          {:ok, inputs()} | {:error, :missing_inputs | :invalid_input}
  defp validate_inputs(required_fields, inputs) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(inputs, field)
      end)

    # Also check for nil values in required fields
    nil_fields =
      Enum.filter(required_fields, fn field ->
        Map.has_key?(inputs, field) && is_nil(Map.get(inputs, field))
      end)

    cond do
      not Enum.empty?(missing_fields) -> {:error, :missing_inputs}
      not Enum.empty?(nil_fields) -> {:error, :invalid_input}
      true -> {:ok, inputs}
    end
  end

  @spec build_prompt(signature(), inputs()) ::
          {:ok, String.t()} | {:error, :prompt_generation_failed}
  defp build_prompt(signature, inputs) do
    # Try to get signature description for context
    description =
      if function_exported?(signature, :description, 0) do
        signature.description()
      else
        "Please process the following input"
      end

    # Build a simple prompt with the inputs
    input_text =
      Enum.map_join(inputs, "\n", fn {key, value} ->
        "#{key}: #{value}"
      end)

    prompt = "#{description}\n\n#{input_text}"
    {:ok, prompt}
  rescue
    _ -> {:error, :prompt_generation_failed}
  end

  @spec extract_response_text(api_response()) :: {:ok, String.t()} | {:error, :invalid_response}
  defp extract_response_text(%{choices: choices}) when is_list(choices) and length(choices) > 0 do
    case List.first(choices) do
      %{message: %{content: content}} when is_binary(content) ->
        {:ok, content}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp extract_response_text(_), do: {:error, :invalid_response}

  @spec parse_output_text([atom()], String.t()) :: {:ok, outputs()} | {:error, :parsing_failed}
  defp parse_output_text(output_fields, response_text) do
    # For now, use simple parsing - put all response text in first output field
    # In a more sophisticated implementation, this would parse structured output
    case output_fields do
      [single_field] ->
        {:ok, %{single_field => String.trim(response_text)}}

      multiple_fields ->
        # For multiple fields, try to split by lines or use first field as fallback
        lines = String.split(response_text, "\n", trim: true)

        if length(lines) >= length(multiple_fields) do
          outputs = Enum.zip(multiple_fields, lines) |> Enum.into(%{})
          {:ok, outputs}
        else
          # Fallback: put all text in first field
          [first_field | _] = multiple_fields
          {:ok, %{first_field => String.trim(response_text)}}
        end
    end
  rescue
    _ -> {:error, :parsing_failed}
  end
end
