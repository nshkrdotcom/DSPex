defmodule DSPex.Types.ProgramOfThoughtResult do
  @moduledoc """
  Represents the result of a Program of Thought operation.
  
  This struct contains the generated code, explanation, and execution result,
  representing the computational approach to problem-solving.
  """
  
  @enforce_keys [:code, :explanation]
  defstruct [
    :code,
    :explanation,
    :execution_result,
    :language,
    :variables,
    :imports,
    :metadata,
    :raw_response
  ]
  
  @type t :: %__MODULE__{
    code: String.t(),
    explanation: String.t(),
    execution_result: any() | nil,
    language: String.t() | nil,
    variables: map() | nil,
    imports: list(String.t()) | nil,
    metadata: map() | nil,
    raw_response: any()
  }
  
  @doc """
  Creates a new ProgramOfThoughtResult with validation.
  """
  def new(attrs) when is_map(attrs) do
    with {:ok, code} <- validate_code(attrs[:code] || attrs["code"]),
         {:ok, explanation} <- validate_explanation(attrs[:explanation] || attrs["explanation"]),
         {:ok, execution_result} <- validate_execution_result(attrs[:execution_result] || attrs["execution_result"]),
         {:ok, language} <- validate_language(attrs[:language] || attrs["language"]),
         {:ok, variables} <- validate_variables(attrs[:variables] || attrs["variables"]),
         {:ok, imports} <- validate_imports(attrs[:imports] || attrs["imports"]),
         {:ok, metadata} <- validate_metadata(attrs[:metadata] || attrs["metadata"]) do
      {:ok, %__MODULE__{
        code: code,
        explanation: explanation,
        execution_result: execution_result,
        language: language || "python",
        variables: variables,
        imports: imports,
        metadata: metadata,
        raw_response: attrs[:raw_response] || attrs["raw_response"]
      }}
    end
  end
  
  @doc """
  Converts a Python ProgramOfThought result to this struct.
  """
  def from_python_result(%{"code" => code, "explanation" => explanation} = result) do
    new(%{
      code: code,
      explanation: explanation,
      execution_result: Map.get(result, "execution_result"),
      language: Map.get(result, "language"),
      variables: Map.get(result, "variables"),
      imports: Map.get(result, "imports"),
      metadata: Map.get(result, "metadata"),
      raw_response: result
    })
  end
  
  def from_python_result(%{"program" => code, "rationale" => explanation} = result) do
    # Alternative format used by some DSPy versions
    new(%{
      code: code,
      explanation: explanation,
      execution_result: Map.get(result, "result"),
      language: Map.get(result, "language"),
      variables: Map.get(result, "variables"),
      imports: Map.get(result, "imports"),
      metadata: Map.get(result, "metadata"),
      raw_response: result
    })
  end
  
  def from_python_result(_), do: {:error, :invalid_program_of_thought_format}
  
  @doc """
  Validates the struct instance.
  """
  def validate(%__MODULE__{} = result) do
    with {:ok, _} <- validate_code(result.code),
         {:ok, _} <- validate_explanation(result.explanation),
         {:ok, _} <- validate_execution_result(result.execution_result),
         {:ok, _} <- validate_language(result.language),
         {:ok, _} <- validate_variables(result.variables),
         {:ok, _} <- validate_imports(result.imports),
         {:ok, _} <- validate_metadata(result.metadata) do
      {:ok, result}
    end
  end
  
  def validate(_), do: {:error, :not_a_program_of_thought_result}
  
  # Private validation functions
  defp validate_code(nil), do: {:error, :code_required}
  defp validate_code(code) when is_binary(code) and byte_size(code) > 0 do
    {:ok, code}
  end
  defp validate_code(_), do: {:error, :code_must_be_non_empty_string}
  
  defp validate_explanation(nil), do: {:error, :explanation_required}
  defp validate_explanation(explanation) when is_binary(explanation), do: {:ok, explanation}
  defp validate_explanation(_), do: {:error, :explanation_must_be_string}
  
  defp validate_execution_result(nil), do: {:ok, nil}
  defp validate_execution_result(result), do: {:ok, result}
  
  defp validate_language(nil), do: {:ok, nil}
  defp validate_language(language) when is_binary(language) do
    supported_languages = ["python", "javascript", "elixir", "ruby", "java", "c++", "go", "rust"]
    if String.downcase(language) in supported_languages do
      {:ok, String.downcase(language)}
    else
      {:ok, language} # Allow other languages but don't validate
    end
  end
  defp validate_language(_), do: {:error, :language_must_be_string}
  
  defp validate_variables(nil), do: {:ok, nil}
  defp validate_variables(variables) when is_map(variables), do: {:ok, variables}
  defp validate_variables(_), do: {:error, :variables_must_be_map}
  
  defp validate_imports(nil), do: {:ok, nil}
  defp validate_imports(imports) when is_list(imports) do
    if Enum.all?(imports, &is_binary/1) do
      {:ok, imports}
    else
      {:error, :imports_must_be_list_of_strings}
    end
  end
  defp validate_imports(_), do: {:error, :imports_must_be_list}
  
  defp validate_metadata(nil), do: {:ok, nil}
  defp validate_metadata(metadata) when is_map(metadata), do: {:ok, metadata}
  defp validate_metadata(_), do: {:error, :metadata_must_be_map}
end