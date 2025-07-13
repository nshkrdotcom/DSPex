defmodule AshDSPex.Signature.Compiler do
  @moduledoc """
  Compile-time processing for signature definitions.

  This module handles the `@before_compile` callback that processes signature AST
  and generates runtime functions for validation, introspection, and JSON schema
  generation.

  ## Generated Functions

  When a module uses `AshDSPex.Signature` and defines a signature, this compiler
  generates the following functions:

  - `__signature__/0` - Returns compiled signature metadata
  - `input_fields/0` - Returns list of input field definitions
  - `output_fields/0` - Returns list of output field definitions
  - `validate_inputs/1` - Validates input data against signature
  - `validate_outputs/1` - Validates output data against signature
  - `to_json_schema/1` - Generates JSON schema for provider compatibility

  ## Signature Metadata Structure

  The compiled signature metadata is a map with the following structure:

      %{
        inputs: [{field_name, type, constraints}, ...],
        outputs: [{field_name, type, constraints}, ...],
        module: ModuleName
      }

  ## AST Parsing

  The compiler supports several signature syntax patterns:

  ### Single Input/Output
      signature input: :type -> output: :type

  ### Multiple Fields
      signature in1: :type, in2: :type -> out1: :type, out2: :type

  ### Complex Types
      signature query: :string, context: {:list, :string} -> 
               answer: :string, confidence: :probability

  ## Error Handling

  The compiler provides comprehensive error messages for common mistakes:
  - Invalid type definitions
  - Missing signature definitions  
  - Malformed syntax
  - Type constraint violations
  """

  alias AshDSPex.Signature.TypeParser

  @doc """
  Compile-time callback that processes signature definitions.

  This function is called by the Elixir compiler for any module that has
  `@before_compile AshDSPex.Signature.Compiler` in its module definition.

  It extracts the signature AST, parses it, validates types, and generates
  the necessary runtime functions.
  """
  defmacro __before_compile__(env) do
    case Module.get_attribute(env.module, :signature_ast) do
      nil ->
        raise_missing_signature_error(env.module)

      ast ->
        case compile_signature(ast, env.module) do
          {:ok, quoted_code} -> quoted_code
          {:error, reason} -> raise_compilation_error(reason, ast, env.module)
        end
    end
  end

  @doc """
  Compiles a signature AST into runtime metadata and functions.

  This is the core compilation function that:
  1. Parses the signature AST into inputs and outputs
  2. Validates all type definitions
  3. Generates the signature metadata
  4. Creates quoted code for runtime functions

  Returns `{:ok, quoted_code}` on success or `{:error, reason}` on failure.
  """
  @spec compile_signature(Macro.t(), module()) :: {:ok, Macro.t()} | {:error, String.t()}
  def compile_signature(ast, module) do
    with {:ok, {inputs, outputs}} <- parse_signature_ast(ast),
         :ok <- validate_field_types(inputs ++ outputs),
         signature_metadata <- build_signature_metadata(inputs, outputs, module) do
      quoted_code = generate_signature_code(signature_metadata)
      {:ok, quoted_code}
    end
  end

  # AST Parsing Functions

  @doc """
  Parses signature AST into structured input and output field definitions.

  Handles various syntax patterns and extracts field names, types, and constraints.

  ## Examples

      # Simple pattern: input: :type -> output: :type
      parse_signature_ast(quote do: (question: :string -> answer: :string))

      # Multiple fields: in1: :type, in2: :type -> out1: :type, out2: :type  
      parse_signature_ast(quote do: (query: :string, context: :string -> answer: :string, score: :float))
  """
  @spec parse_signature_ast(Macro.t()) :: {:ok, {list(), list()}} | {:error, String.t()}
  def parse_signature_ast({:->, _, [left_side, right_side]}) do
    with {:ok, inputs} <- parse_fields_side(left_side),
         {:ok, outputs} <- parse_fields_side(right_side) do
      {:ok, {inputs, outputs}}
    end
  end

  def parse_signature_ast(invalid_ast) do
    {:error,
     "Invalid signature syntax. Expected: field: type -> field: type, got: #{inspect(invalid_ast)}"}
  end

  defp parse_fields_side(fields) when is_list(fields) do
    parse_field_list(fields, [])
  end

  defp parse_fields_side(single_field) do
    parse_field_list([single_field], [])
  end

  defp parse_field_list([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_field_list([{field_name, type} | rest], acc) when is_atom(field_name) do
    case TypeParser.parse_type(type) do
      {:ok, parsed_type} ->
        field_def = {field_name, parsed_type, []}
        parse_field_list(rest, [field_def | acc])

      {:error, reason} ->
        {:error, "Invalid type for field #{field_name}: #{reason}"}
    end
  end

  defp parse_field_list([invalid | _], _acc) do
    {:error, "Invalid field definition: #{inspect(invalid)}. Expected: field_name: type"}
  end

  # Validation Functions

  defp validate_field_types(fields) do
    case find_invalid_field(fields) do
      nil ->
        :ok

      {field_name, type, reason} ->
        {:error, "Field #{field_name} has invalid type #{inspect(type)}: #{reason}"}
    end
  end

  defp find_invalid_field([]), do: nil

  defp find_invalid_field([{field_name, type, _constraints} | rest]) do
    case TypeParser.validate_type_definition(type) do
      :ok -> find_invalid_field(rest)
      {:error, reason} -> {field_name, type, reason}
    end
  end

  # Metadata Generation

  defp build_signature_metadata(inputs, outputs, module) do
    %{
      inputs: inputs,
      outputs: outputs,
      module: module
    }
  end

  # Code Generation

  defp generate_signature_code(signature_metadata) do
    quote do
      @signature_compiled unquote(Macro.escape(signature_metadata))

      @doc """
      Returns the compiled signature metadata.

      The metadata includes input fields, output fields, and module information
      in a structured format for runtime introspection.
      """
      @spec __signature__() :: map()
      def __signature__, do: @signature_compiled

      @doc """
      Returns the input field definitions.

      Each field is a tuple of {name, type, constraints}.
      """
      @spec input_fields() :: [{atom(), any(), list()}]
      def input_fields, do: @signature_compiled.inputs

      @doc """
      Returns the output field definitions.

      Each field is a tuple of {name, type, constraints}.
      """
      @spec output_fields() :: [{atom(), any(), list()}]
      def output_fields, do: @signature_compiled.outputs

      @doc """
      Validates input data against the signature definition.

      Returns `{:ok, validated_data}` on success or `{:error, reason}` on failure.
      The validated data may have type coercions applied.
      """
      @spec validate_inputs(map()) :: {:ok, map()} | {:error, String.t()}
      def validate_inputs(data) do
        AshDSPex.Signature.Validator.validate_fields(data, input_fields())
      end

      @doc """
      Validates output data against the signature definition.

      Returns `{:ok, validated_data}` on success or `{:error, reason}` on failure.
      The validated data may have type coercions applied.
      """
      @spec validate_outputs(map()) :: {:ok, map()} | {:error, String.t()}
      def validate_outputs(data) do
        AshDSPex.Signature.Validator.validate_fields(data, output_fields())
      end

      @doc """
      Generates a JSON schema for the signature compatible with various providers.

      Supports providers like `:openai`, `:anthropic`, etc. The schema can be used
      for function calling, API validation, and documentation generation.
      """
      @spec to_json_schema(atom()) :: map()
      def to_json_schema(provider \\ :openai) do
        AshDSPex.Signature.JsonSchema.generate(__signature__(), provider)
      end

      @doc """
      Returns a human-readable description of the signature.

      Useful for debugging and documentation.
      """
      @spec describe() :: String.t()
      def describe do
        input_desc = describe_fields(input_fields())
        output_desc = describe_fields(output_fields())
        "#{input_desc} -> #{output_desc}"
      end

      defp describe_fields(fields) do
        fields
        |> Enum.map(fn {name, type, _} ->
          "#{name}: #{AshDSPex.Signature.TypeParser.describe_type(type)}"
        end)
        |> Enum.join(", ")
      end
    end
  end

  # Error Generation

  @spec raise_missing_signature_error(module()) :: no_return()
  defp raise_missing_signature_error(module) do
    raise """
    Module #{module} uses AshDSPex.Signature but does not define a signature.

    Add a signature definition like:

        defmodule #{module} do
          use AshDSPex.Signature
          
          signature question: :string -> answer: :string
        end
    """
  end

  @spec raise_compilation_error(String.t(), Macro.t(), module()) :: no_return()
  defp raise_compilation_error(reason, ast, module) do
    raise """
    Invalid signature definition in #{module}: #{reason}

    Expected syntax examples:
      signature question: :string -> answer: :string
      signature query: :string, context: :string -> answer: :string, confidence: :float

    Received AST: #{inspect(ast)}

    Supported types:
      Basic: #{Enum.join(TypeParser.basic_types(), ", ")}
      ML: #{Enum.join(TypeParser.ml_types(), ", ")}
      Composite: {:list, type}, {:dict, key_type, value_type}, {:union, [types]}
    """
  end
end
