defmodule DSPEx.Signature.EnhancedParser do
  @moduledoc """
  Enhanced parser for DSPEx signatures that supports Sinter-compatible field definitions with constraints.

  This parser extends the basic signature format to support advanced field definitions including:
  - Type specifications
  - Constraint definitions
  - Nested constraints with parameters
  - Backward compatibility with existing simple signatures

  ## Supported Syntax

  ### Basic Format (backward compatible)
      "question -> answer"
      "question, context -> answer, confidence"

  ### Enhanced Format with Types
      "question:string -> answer:string"
      "age:integer -> result:boolean"

  ### Enhanced Format with Constraints
      "name:string[min_length=2,max_length=50] -> greeting:string[max_length=100]"
      "score:integer[gteq=0,lteq=100] -> grade:string[choices=['A','B','C','D','F']]"
      "email:string[format=/^[^@]+@[^@]+$/] -> status:string[default='pending']"

  ### Array Types
      "tags:array(string)[min_items=1,max_items=10] -> summary:string"
      "scores:array(integer)[min_items=3] -> average:float[gteq=0.0]"

  ### Complex Constraints
      "user_input:string[min_length=1,max_length=500,format=/^[a-zA-Z0-9\\s]+$/] -> response:string[max_length=1000]"

  ## Field Definition Structure

  Each field can have:
  - **name**: The field identifier (required)
  - **type**: The field type (optional, defaults to :string)
  - **constraints**: List of validation constraints (optional)

  ## Constraint Types

  ### String Constraints
  - `min_length=N` - Minimum string length
  - `max_length=N` - Maximum string length
  - `format=/regex/` - Regex pattern matching
  - `choices=['a','b','c']` - Enumeration of allowed values

  ### Numeric Constraints
  - `gteq=N` - Greater than or equal to
  - `lteq=N` - Less than or equal to
  - `gt=N` - Greater than (exclusive)
  - `lt=N` - Less than (exclusive)

  ### Array Constraints
  - `min_items=N` - Minimum number of items
  - `max_items=N` - Maximum number of items

  ### General Constraints
  - `default=value` - Default value when field is omitted
  - `optional=true` - Field is not required (implies default=nil if not set)
  """

  @typedoc "Enhanced field definition with type and constraints"
  @type enhanced_field :: %{
          name: atom(),
          type: atom() | tuple(),
          constraints: %{atom() => term()},
          required: boolean(),
          default: term()
        }

  @typedoc "Parsed enhanced signature result"
  @type enhanced_parsed_signature :: {[enhanced_field()], [enhanced_field()]}

  @doc """
  Parses an enhanced signature string into detailed field definitions.

  Supports both basic and enhanced signature formats for backward compatibility.

  ## Parameters
  - `signature_string` - The signature string to parse

  ## Returns
  - A tuple `{input_fields, output_fields}` where each field is an enhanced_field map

  ## Examples

      iex> DSPEx.Signature.EnhancedParser.parse("question -> answer")
      {[%{name: :question, type: :string, constraints: %{}, required: true, default: nil}],
       [%{name: :answer, type: :string, constraints: %{}, required: true, default: nil}]}

      iex> DSPEx.Signature.EnhancedParser.parse("name:string[min_length=2] -> greeting:string[max_length=100]")
      {[%{name: :name, type: :string, constraints: %{min_length: 2}, required: true, default: nil}],
       [%{name: :greeting, type: :string, constraints: %{max_length: 100}, required: true, default: nil}]}
  """
  @spec parse(String.t()) :: enhanced_parsed_signature() | no_return()
  def parse(signature_string) when is_binary(signature_string) do
    signature_string
    |> String.trim()
    |> validate_format()
    |> split_signature()
    |> parse_enhanced_fields()
    |> validate_enhanced_fields()
  end

  @doc """
  Converts enhanced field definitions back to simple field names for compatibility.

  This allows the enhanced parser to work with existing DSPEx code that expects
  simple atom field lists.

  ## Parameters
  - `enhanced_signature` - Result from parse/1

  ## Returns
  - A tuple `{input_atoms, output_atoms}` compatible with existing DSPEx code

  ## Examples

      iex> enhanced = DSPEx.Signature.EnhancedParser.parse("name:string[min_length=2] -> greeting:string")
      iex> DSPEx.Signature.EnhancedParser.to_simple_signature(enhanced)
      {[:name], [:greeting]}
  """
  @spec to_simple_signature(enhanced_parsed_signature()) :: {[atom()], [atom()]}
  def to_simple_signature({input_fields, output_fields}) do
    input_names = Enum.map(input_fields, & &1.name)
    output_names = Enum.map(output_fields, & &1.name)
    {input_names, output_names}
  end

  @doc """
  Checks if a signature string uses enhanced features or is a basic signature.

  ## Parameters
  - `signature_string` - The signature string to analyze

  ## Returns
  - `true` if enhanced features are detected, `false` otherwise

  ## Examples

      iex> DSPEx.Signature.EnhancedParser.enhanced_signature?("question -> answer")
      false

      iex> DSPEx.Signature.EnhancedParser.enhanced_signature?("name:string -> greeting:string")
      true

      iex> DSPEx.Signature.EnhancedParser.enhanced_signature?("name[min_length=2] -> greeting")
      true
  """
  @spec enhanced_signature?(String.t()) :: boolean()
  def enhanced_signature?(signature_string) when is_binary(signature_string) do
    # Check for type annotations (contains :)
    has_types = String.contains?(signature_string, ":")

    # Check for constraint annotations (contains [ and ])
    has_constraints =
      String.contains?(signature_string, "[") and String.contains?(signature_string, "]")

    has_types or has_constraints
  end

  @doc """
  Converts enhanced field definitions to Sinter-compatible format.

  Takes the output from parse/1 and converts it to the format expected
  by Sinter for schema definition.

  ## Parameters
  - `enhanced_signature` - Result from parse/1

  ## Returns
  - A list of Sinter field tuples: `{name, type, constraints}`

  ## Examples

      iex> enhanced = DSPEx.Signature.EnhancedParser.parse("name:string[min_length=2] -> greeting:string")
      iex> sinter_fields = DSPEx.Signature.EnhancedParser.to_sinter_format(enhanced)
      iex> {name, type, constraints} = hd(sinter_fields)
      iex> {name, type, Keyword.get(constraints, :required), Keyword.get(constraints, :min_length)}
      {:name, :string, true, 2}
  """
  @spec to_sinter_format(enhanced_parsed_signature()) :: [tuple()]
  def to_sinter_format({input_fields, output_fields}) do
    all_fields = input_fields ++ output_fields

    Enum.map(all_fields, fn field ->
      {field.name, field.type, build_sinter_constraints(field)}
    end)
  end

  # Private helper to build Sinter constraint list from enhanced field
  defp build_sinter_constraints(field) do
    base_constraints = if field.required, do: [required: true], else: [optional: true]

    constraint_list =
      field.constraints
      |> Enum.reduce(base_constraints, fn {key, value}, acc ->
        case map_constraint_to_sinter(key, value) do
          {sinter_key, sinter_value} -> Keyword.put(acc, sinter_key, sinter_value)
          nil -> acc
        end
      end)

    # Add default if present  
    if field.default do
      Keyword.put(constraint_list, :default, field.default)
    else
      constraint_list
    end
  end

  # Map DSPEx constraint names to Sinter constraint names
  defp map_constraint_to_sinter(:min_length, value), do: {:min_length, value}
  defp map_constraint_to_sinter(:max_length, value), do: {:max_length, value}
  defp map_constraint_to_sinter(:min_items, value), do: {:min_items, value}
  defp map_constraint_to_sinter(:max_items, value), do: {:max_items, value}
  defp map_constraint_to_sinter(:gteq, value), do: {:gteq, value}
  defp map_constraint_to_sinter(:lteq, value), do: {:lteq, value}
  defp map_constraint_to_sinter(:gt, value), do: {:gt, value}
  defp map_constraint_to_sinter(:lt, value), do: {:lt, value}
  defp map_constraint_to_sinter(:format, value), do: {:format, value}
  defp map_constraint_to_sinter(:choices, value), do: {:choices, value}
  defp map_constraint_to_sinter(_key, _value), do: nil

  # Private implementation

  # Validates basic format with arrow separator
  @spec validate_format(String.t()) :: String.t() | no_return()
  defp validate_format(str) do
    unless String.contains?(str, "->") do
      raise CompileError,
        description: "DSPEx signature must contain '->' separator. Example: 'question -> answer'",
        file: __ENV__.file,
        line: __ENV__.line
    end

    str
  end

  # Splits on arrow, handles whitespace
  @spec split_signature(String.t()) :: {String.t(), String.t()} | no_return()
  defp split_signature(str) do
    case String.split(str, "->", parts: 2) do
      [inputs_str, outputs_str] ->
        {String.trim(inputs_str), String.trim(outputs_str)}

      _ ->
        raise CompileError,
          description: "Invalid DSPEx signature format. Must contain exactly one '->' separator.",
          file: __ENV__.file,
          line: __ENV__.line
    end
  end

  # Parses enhanced field definitions from input and output strings
  @spec parse_enhanced_fields({String.t(), String.t()}) ::
          enhanced_parsed_signature() | no_return()
  defp parse_enhanced_fields({inputs_str, outputs_str}) do
    input_fields = parse_enhanced_field_list(inputs_str)
    output_fields = parse_enhanced_field_list(outputs_str)

    # Validate that both inputs and outputs are non-empty
    if Enum.empty?(input_fields) do
      raise CompileError,
        description: "DSPEx signature must have at least one input field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    if Enum.empty?(output_fields) do
      raise CompileError,
        description: "DSPEx signature must have at least one output field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    {input_fields, output_fields}
  end

  # Parses a comma-separated list of enhanced field definitions
  @spec parse_enhanced_field_list(String.t()) :: [enhanced_field()]
  defp parse_enhanced_field_list(""), do: []

  defp parse_enhanced_field_list(str) do
    str
    |> split_fields_respecting_brackets()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_single_enhanced_field/1)
  end

  # Splits field list by commas but respects bracket boundaries
  # So "a:string[min=1,max=5], b:integer" becomes ["a:string[min=1,max=5]", "b:integer"]
  # Also handles regex patterns like "string[format=/^[A-Z]/]" correctly
  @spec split_fields_respecting_brackets(String.t()) :: [String.t()]
  defp split_fields_respecting_brackets(str) do
    str
    |> String.graphemes()
    |> Enum.reduce({[], "", 0, false}, fn char, {fields, current, bracket_depth, in_regex} ->
      case {char, in_regex} do
        # Handle regex delimiters - don't count brackets inside regex patterns
        {"/", false} when bracket_depth > 0 ->
          {fields, current <> char, bracket_depth, true}

        {"/", true} ->
          {fields, current <> char, bracket_depth, false}

        # Regular bracket handling when not in regex
        {"[", false} ->
          {fields, current <> char, bracket_depth + 1, in_regex}

        {"]", false} ->
          {fields, current <> char, bracket_depth - 1, in_regex}

        # Comma splitting only when not in brackets
        {",", false} when bracket_depth == 0 ->
          {fields ++ [current], "", 0, false}

        # Everything else just gets added
        _ ->
          {fields, current <> char, bracket_depth, in_regex}
      end
    end)
    |> case do
      {fields, "", 0, _} -> fields
      {fields, current, _, _} -> fields ++ [current]
    end
  end

  # Parses a single enhanced field definition
  @spec parse_single_enhanced_field(String.t()) :: enhanced_field() | no_return()
  defp parse_single_enhanced_field(field_str) do
    field_str = String.trim(field_str)

    # Check for constraint block first
    {base_field, constraints} = extract_constraints(field_str)

    # Parse name and type from base field
    {name, type} = parse_name_and_type(base_field)

    # Process constraints to determine if field is optional/has default
    {processed_constraints, required, default} = process_constraints(constraints)

    %{
      name: name,
      type: type,
      constraints: processed_constraints,
      required: required,
      default: default
    }
  end

  # Extracts constraint block from field definition
  @spec extract_constraints(String.t()) :: {String.t(), String.t()}
  defp extract_constraints(field_str) do
    # Find the last '[' that starts constraints, handle regex patterns correctly
    constraint_start = find_last_constraint_bracket(field_str)

    case constraint_start do
      nil ->
        # No constraints found
        {String.trim(field_str), ""}

      start_pos ->
        # Find matching ']' from start_pos
        case find_closing_bracket_pos(field_str, start_pos) do
          nil ->
            # Malformed constraint bracket
            {String.trim(field_str), ""}

          end_pos ->
            base_field = String.slice(field_str, 0, start_pos)
            constraints = String.slice(field_str, start_pos + 1, end_pos - start_pos - 1)
            {String.trim(base_field), String.trim(constraints)}
        end
    end
  end

  # Find the position of the last '[' that starts a constraint block
  @spec find_last_constraint_bracket(String.t()) :: integer() | nil
  defp find_last_constraint_bracket(field_str) do
    # Look for the last '[' that could be a constraint block
    # We work backwards to find the rightmost one
    String.reverse(field_str)
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.find(fn {char, _} -> char == "[" end)
    |> case do
      nil -> nil
      {_, rev_index} -> String.length(field_str) - rev_index - 1
    end
  end

  # Find the matching ']' for a '[' at the given position
  @spec find_closing_bracket_pos(String.t(), integer()) :: integer() | nil
  defp find_closing_bracket_pos(field_str, start_pos) do
    remaining = String.slice(field_str, (start_pos + 1)..-1//1)

    # Simple bracket counting approach
    remaining
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce_while({0, false}, fn {char, index}, {depth, in_regex} ->
      case {char, in_regex} do
        # Handle regex boundaries
        {"/", _} ->
          {:cont, {depth, not in_regex}}

        # Only count brackets when not in regex
        {"[", false} ->
          {:cont, {depth + 1, in_regex}}

        {"]", false} when depth == 0 ->
          {:halt, {:found, start_pos + 1 + index}}

        {"]", false} ->
          {:cont, {depth - 1, in_regex}}

        _ ->
          {:cont, {depth, in_regex}}
      end
    end)
    |> case do
      {:found, pos} -> pos
      _ -> nil
    end
  end

  # Parses field name and type from base field definition
  @spec parse_name_and_type(String.t()) :: {atom(), atom() | tuple()} | no_return()
  defp parse_name_and_type(base_field) do
    case String.split(base_field, ":", parts: 2) do
      [name_str] ->
        # Simple field name without type annotation
        name = validate_and_convert_field_name(name_str)
        # Default type
        {name, :string}

      [name_str, type_str] ->
        # Field with type annotation
        name = validate_and_convert_field_name(name_str)
        type = parse_field_type(type_str)
        {name, type}
    end
  end

  # Validates and converts field name to atom
  @spec validate_and_convert_field_name(String.t()) :: atom() | no_return()
  defp validate_and_convert_field_name(name_str) do
    name_str = String.trim(name_str)

    unless Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, name_str) do
      raise CompileError,
        description:
          "Invalid field name '#{name_str}'. Must be a valid Elixir atom starting with lowercase letter.",
        file: __ENV__.file,
        line: __ENV__.line
    end

    String.to_atom(name_str)
  end

  # Parses field type specification
  @spec parse_field_type(String.t()) :: atom() | tuple() | no_return()
  defp parse_field_type(type_str) do
    type_str = String.trim(type_str)

    if Regex.match?(~r/^array\s*\(\s*(\w+)\s*\)$/, type_str) do
      # Array types: array(string), array(integer), etc.
      [_full, inner_type] = Regex.run(~r/^array\s*\(\s*(\w+)\s*\)$/, type_str)
      inner_type_atom = parse_simple_type(String.trim(inner_type))
      {:array, inner_type_atom}
    else
      # Simple types: string, integer, float, boolean, any
      parse_simple_type(type_str)
    end
  end

  # Parses simple (non-compound) types
  @spec parse_simple_type(String.t()) :: atom() | no_return()
  defp parse_simple_type(type_str) do
    case type_str do
      "string" ->
        :string

      "integer" ->
        :integer

      "float" ->
        :float

      "boolean" ->
        :boolean

      "any" ->
        :any

      "map" ->
        :map

      other ->
        unless Regex.match?(~r/^[A-Z][a-zA-Z0-9_]*$/, other) do
          raise CompileError,
            description:
              "Invalid type '#{other}'. Must be a built-in type (string, integer, float, boolean, any, map) or a valid module name.",
            file: __ENV__.file,
            line: __ENV__.line
        end

        String.to_atom(other)
    end
  end

  # Processes constraint string into a constraints map and requirement settings
  @spec process_constraints(String.t()) :: {%{atom() => term()}, boolean(), term()}
  defp process_constraints("") do
    # No constraints, required by default, no default
    {%{}, true, nil}
  end

  defp process_constraints(constraints_str) do
    constraints = parse_constraints_string(constraints_str)

    # Check for special constraints that affect requirement status
    required =
      not Map.has_key?(constraints, :optional) and not Map.has_key?(constraints, :default)

    default = Map.get(constraints, :default)

    # Remove requirement-related constraints from the constraint map
    processed_constraints =
      constraints
      |> Map.delete(:optional)
      |> Map.delete(:default)

    {processed_constraints, required, default}
  end

  # Parses constraint string into a map of constraint name to value
  @spec parse_constraints_string(String.t()) :: %{atom() => term()}
  defp parse_constraints_string(constraints_str) do
    constraints_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_single_constraint/1)
    |> Enum.into(%{})
  end

  # Parses a single constraint like "min_length=5" or "choices=['A','B','C']"
  @spec parse_single_constraint(String.t()) :: {atom(), term()} | no_return()
  defp parse_single_constraint(constraint_str) do
    case String.split(constraint_str, "=", parts: 2) do
      [name_str] ->
        # Boolean constraint like "optional"
        constraint_name = String.trim(name_str) |> String.to_atom()
        {constraint_name, true}

      [name_str, value_str] ->
        constraint_name = String.trim(name_str) |> String.to_atom()
        constraint_value = parse_constraint_value(constraint_name, String.trim(value_str))
        {constraint_name, constraint_value}
    end
  end

  # Numeric constraint types
  @numeric_constraints [
    :min_length,
    :max_length,
    :min_items,
    :max_items,
    :gteq,
    :lteq,
    :gt,
    :lt
  ]

  # Parses constraint values based on constraint type
  @spec parse_constraint_value(atom(), String.t()) :: term() | no_return()
  defp parse_constraint_value(constraint_name, value_str) do
    cond do
      constraint_name in @numeric_constraints ->
        parse_numeric_constraint(constraint_name, value_str)

      constraint_name == :format ->
        parse_regex_value(value_str)

      constraint_name == :choices ->
        parse_choices_value(value_str)

      constraint_name == :default ->
        parse_default_value(value_str)

      constraint_name == :optional ->
        parse_boolean_constraint(constraint_name, value_str)

      true ->
        parse_unknown_constraint(value_str)
    end
  end

  defp parse_numeric_constraint(constraint_name, value_str) do
    case Integer.parse(value_str) do
      {int_value, ""} ->
        int_value

      _ ->
        case Float.parse(value_str) do
          {float_value, ""} ->
            float_value

          _ ->
            raise CompileError,
              description:
                "Invalid numeric value '#{value_str}' for constraint '#{constraint_name}'",
              file: __ENV__.file,
              line: __ENV__.line
        end
    end
  end

  defp parse_boolean_constraint(constraint_name, value_str) do
    case String.downcase(value_str) do
      "true" ->
        true

      "false" ->
        false

      _ ->
        raise CompileError,
          description:
            "Invalid boolean value '#{value_str}' for constraint '#{constraint_name}'. Use 'true' or 'false'.",
          file: __ENV__.file,
          line: __ENV__.line
    end
  end

  defp parse_unknown_constraint(value_str) do
    case Integer.parse(value_str) do
      {int_value, ""} ->
        int_value

      _ ->
        case Float.parse(value_str) do
          {float_value, ""} -> float_value
          # Keep as string
          _ -> value_str
        end
    end
  end

  # Parses regex patterns like /^pattern$/ or 'pattern'
  @spec parse_regex_value(String.t()) :: Regex.t() | no_return()
  defp parse_regex_value(value_str) do
    {pattern, flags} = extract_regex_pattern_and_flags(value_str)
    compile_regex_with_error_handling(pattern, flags)
  end

  defp extract_regex_pattern_and_flags(value_str) do
    cond do
      Regex.match?(~r|^/(.*)/(.*)?$|, value_str) ->
        [_full, pattern, flags] = Regex.run(~r|^/(.*)/(.*)?$|, value_str)
        {pattern, parse_regex_flags(flags)}

      String.starts_with?(value_str, "'") and String.ends_with?(value_str, "'") ->
        {String.slice(value_str, 1..-2//1), []}

      String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\"") ->
        {String.slice(value_str, 1..-2//1), []}

      true ->
        {value_str, []}
    end
  end

  defp compile_regex_with_error_handling(pattern, flags) do
    Regex.compile!(pattern, flags)
  rescue
    error ->
      reraise CompileError,
              [
                description: "Invalid regex pattern '#{pattern}': #{inspect(error)}",
                file: __ENV__.file,
                line: __ENV__.line
              ],
              __STACKTRACE__
  end

  # Parses regex flags like "i" for case-insensitive
  @spec parse_regex_flags(String.t()) :: String.t()
  defp parse_regex_flags(""), do: ""
  defp parse_regex_flags(flags) when is_binary(flags), do: flags

  # Parses choice arrays like ['A','B','C'] or ["a","b","c"]
  @spec parse_choices_value(String.t()) :: [term()] | no_return()
  defp parse_choices_value(value_str) do
    if String.starts_with?(value_str, "[") and String.ends_with?(value_str, "]") do
      # Array format: ['A','B','C'] or ["a","b","c"]
      array_content = String.slice(value_str, 1..-2//1) |> String.trim()

      if array_content == "" do
        []
      else
        array_content
        |> String.split(",")
        |> Enum.map(&parse_choice_item/1)
      end
    else
      # Single value (convert to single-item array)
      [parse_choice_item(value_str)]
    end
  end

  # Parses individual choice items, handling quoted strings and numbers
  @spec parse_choice_item(String.t()) :: term()
  defp parse_choice_item(item_str) do
    item_str = String.trim(item_str)

    cond do
      # Quoted string: 'value' or "value"
      String.starts_with?(item_str, "'") and String.ends_with?(item_str, "'") ->
        String.slice(item_str, 1..-2//1)

      String.starts_with?(item_str, "\"") and String.ends_with?(item_str, "\"") ->
        String.slice(item_str, 1..-2//1)

      # Number
      true ->
        parse_numeric_choice_item(item_str)
    end
  end

  defp parse_numeric_choice_item(item_str) do
    case Integer.parse(item_str) do
      {int_value, ""} ->
        int_value

      _ ->
        case Float.parse(item_str) do
          {float_value, ""} -> float_value
          # Keep as unquoted string
          _ -> item_str
        end
    end
  end

  # Parses default values with type inference
  @spec parse_default_value(String.t()) :: term()
  defp parse_default_value(value_str) do
    cond do
      quoted_string?(value_str) -> extract_quoted_string(value_str)
      boolean_string?(value_str) -> parse_boolean_string(value_str)
      null_string?(value_str) -> nil
      true -> parse_numeric_or_string(value_str)
    end
  end

  defp quoted_string?(value_str) do
    (String.starts_with?(value_str, "'") and String.ends_with?(value_str, "'")) or
      (String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\""))
  end

  defp extract_quoted_string(value_str) do
    String.slice(value_str, 1..-2//1)
  end

  defp boolean_string?(value_str) do
    String.downcase(value_str) in ["true", "false"]
  end

  defp parse_boolean_string(value_str) do
    String.downcase(value_str) == "true"
  end

  defp null_string?(value_str) do
    String.downcase(value_str) in ["null", "nil"]
  end

  defp parse_numeric_or_string(value_str) do
    case Integer.parse(value_str) do
      {int_value, ""} -> int_value
      _ -> parse_float_or_string(value_str)
    end
  end

  defp parse_float_or_string(value_str) do
    case Float.parse(value_str) do
      {float_value, ""} -> float_value
      _ -> value_str
    end
  end

  # Validates enhanced field definitions
  @spec validate_enhanced_fields(enhanced_parsed_signature()) ::
          enhanced_parsed_signature() | no_return()
  defp validate_enhanced_fields({input_fields, output_fields}) do
    all_fields = input_fields ++ output_fields
    all_names = Enum.map(all_fields, & &1.name)
    unique_names = Enum.uniq(all_names)

    if length(all_names) != length(unique_names) do
      duplicates = all_names -- unique_names

      raise CompileError,
        description: "Duplicate fields found: #{inspect(duplicates)}",
        file: __ENV__.file,
        line: __ENV__.line
    end

    # Validate individual field definitions
    Enum.each(all_fields, &validate_enhanced_field/1)

    {input_fields, output_fields}
  end

  # Validates a single enhanced field definition
  @spec validate_enhanced_field(enhanced_field()) :: :ok | no_return()
  defp validate_enhanced_field(field) do
    # Validate constraint compatibility with type
    validate_constraints_for_type(field.type, field.constraints, field.name)

    # Validate default value compatibility with type (if present)
    if field.default != nil do
      validate_default_for_type(field.type, field.default, field.name)
    end

    :ok
  end

  # Validates that constraints are compatible with the field type
  @spec validate_constraints_for_type(atom() | tuple(), %{atom() => term()}, atom()) ::
          :ok | no_return()
  defp validate_constraints_for_type(type, constraints, field_name) do
    Enum.each(constraints, fn {constraint_name, _value} ->
      unless constraint_compatible_with_type?(constraint_name, type) do
        raise CompileError,
          description:
            "Constraint '#{constraint_name}' is not compatible with type '#{inspect(type)}' for field '#{field_name}'",
          file: __ENV__.file,
          line: __ENV__.line
      end
    end)

    :ok
  end

  # Checks if a constraint is compatible with a given type
  @spec constraint_compatible_with_type?(atom(), atom() | tuple()) :: boolean()
  defp constraint_compatible_with_type?(constraint, type) do
    case {constraint, type} do
      # String constraints
      {c, :string} when c in [:min_length, :max_length, :format, :choices] -> true
      # Numeric constraints
      {c, t} when c in [:gteq, :lteq, :gt, :lt] and t in [:integer, :float] -> true
      # Array constraints
      {c, {:array, _}} when c in [:min_items, :max_items, :choices] -> true
      # Universal constraints
      {c, _} when c in [:default, :optional] -> true
      # Choices can apply to any type
      {:choices, _} -> true
      # Not compatible
      _ -> false
    end
  end

  # Validates that default value is compatible with the field type
  @spec validate_default_for_type(atom() | tuple(), term(), atom()) :: :ok | no_return()
  # nil is always valid
  defp validate_default_for_type(_type, nil, _field_name), do: :ok

  defp validate_default_for_type(type, default_value, field_name) do
    valid =
      case {type, default_value} do
        {:string, value} when is_binary(value) -> true
        {:integer, value} when is_integer(value) -> true
        {:float, value} when is_number(value) -> true
        {:boolean, value} when is_boolean(value) -> true
        {:any, _} -> true
        {{:array, _}, value} when is_list(value) -> true
        _ -> false
      end

    unless valid do
      raise CompileError,
        description:
          "Default value '#{inspect(default_value)}' is not compatible with type '#{inspect(type)}' for field '#{field_name}'",
        file: __ENV__.file,
        line: __ENV__.line
    end

    :ok
  end
end
