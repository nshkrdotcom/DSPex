# Task NATIVE.1: Signature Parser Implementation

## Task Overview
**ID**: NATIVE.1  
**Component**: Native Implementation  
**Priority**: P0 (Critical)  
**Estimated Time**: 8 hours  
**Dependencies**: CORE.1 (Project setup must be complete)  
**Status**: Not Started

## Objective
Implement a native Elixir parser for DSPy signatures that can parse basic signatures (input -> output), typed signatures with type annotations, list types, optional fields, and descriptions. The parser must provide comprehensive error messages and achieve 100% test coverage.

## Required Reading

### 1. Current Implementation
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/signature.ex`
  - Review existing signature parsing implementation
  - Understand current capabilities and limitations

### 2. Architecture Context
- **File**: `/home/home/p/g/n/dspex/CLAUDE.md`
  - Lines 71-76: Native implementation strategy
  - Understand why signatures are always native

### 3. DSPy Signature Reference
DSPy signatures follow this format:
```
"input_field1, input_field2: type -> output_field1: type, output_field2"
```

Examples:
- Basic: `"question -> answer"`
- Typed: `"question: str -> answer: str"`
- Lists: `"documents: list[str] -> summary: str"`
- Optional: `"query: str, context?: str -> response: str"`
- Descriptions: `"question: str 'user question' -> answer: str 'detailed response'"`

## Implementation Requirements

### Signature Structure
The parser must produce this structure:

```elixir
%DSPex.Native.Signature{
  inputs: [
    %Field{
      name: :question,
      type: :string,
      optional: false,
      description: "user question"
    }
  ],
  outputs: [
    %Field{
      name: :answer,
      type: :string,
      optional: false,
      description: "detailed response"
    }
  ],
  raw: "question: str 'user question' -> answer: str 'detailed response'"
}
```

### Type Mapping
- `str` or `string` → `:string`
- `int` or `integer` → `:integer`
- `float` or `number` → `:float`
- `bool` or `boolean` → `:boolean`
- `list[T]` or `List[T]` → `{:list, T}`
- `dict` or `Dict` → `:map`
- No type specified → `:any`

## Implementation Steps

### Step 1: Update Signature Module Structure
Update `/home/home/p/g/n/dspex/lib/dspex/native/signature.ex`:

```elixir
defmodule DSPex.Native.Signature do
  @moduledoc """
  Native Elixir implementation of DSPy signature parsing.
  
  Parses DSPy-style signatures into structured data for use in prompts.
  """
  
  defstruct [:inputs, :outputs, :raw]
  
  @type field_type :: 
    :string | :integer | :float | :boolean | :any | :map |
    {:list, field_type()}
  
  @type field :: %{
    name: atom(),
    type: field_type(),
    optional: boolean(),
    description: String.t() | nil
  }
  
  @type t :: %__MODULE__{
    inputs: [field()],
    outputs: [field()],
    raw: String.t()
  }
  
  @doc """
  Parse a DSPy signature string into a structured signature.
  
  ## Examples
  
      iex> parse("question -> answer")
      {:ok, %Signature{
        inputs: [%{name: :question, type: :any, optional: false, description: nil}],
        outputs: [%{name: :answer, type: :any, optional: false, description: nil}],
        raw: "question -> answer"
      }}
      
      iex> parse("docs: list[str] -> summary: str")
      {:ok, %Signature{
        inputs: [%{name: :docs, type: {:list, :string}, optional: false, description: nil}],
        outputs: [%{name: :summary, type: :string, optional: false, description: nil}],
        raw: "docs: list[str] -> summary: str"
      }}
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(signature_string) when is_binary(signature_string) do
    with {:ok, {inputs, outputs}} <- split_signature(signature_string),
         {:ok, parsed_inputs} <- parse_fields(inputs),
         {:ok, parsed_outputs} <- parse_fields(outputs) do
      {:ok, %__MODULE__{
        inputs: parsed_inputs,
        outputs: parsed_outputs,
        raw: signature_string
      }}
    end
  end
  
  # Private functions follow...
end
```

### Step 2: Implement Core Parsing Functions

```elixir
# Add to signature.ex

@signature_separator "->"

defp split_signature(signature_string) do
  case String.split(signature_string, @signature_separator, parts: 2) do
    [inputs, outputs] ->
      {:ok, {String.trim(inputs), String.trim(outputs)}}
    
    _ ->
      {:error, "Invalid signature format. Expected 'inputs -> outputs' but got: #{signature_string}"}
  end
end

defp parse_fields(fields_string) do
  fields_string
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.reduce_while({:ok, []}, fn field_str, {:ok, acc} ->
    case parse_single_field(field_str) do
      {:ok, field} -> {:cont, {:ok, acc ++ [field]}}
      {:error, _} = error -> {:halt, error}
    end
  end)
end

defp parse_single_field(field_string) do
  # Pattern: name[?][:type]['description']
  regex = ~r/^
    (?<name>[a-zA-Z_][a-zA-Z0-9_]*)     # Field name
    (?<optional>\?)?                     # Optional marker
    (?:\s*:\s*                           # Type separator
      (?<type>[a-zA-Z_]+                # Type name
        (?:\[                            # List bracket
          (?<list_type>[a-zA-Z_]+)      # List element type
        \])?
      )
    )?
    (?:\s*'(?<desc>[^']*)')?            # Description in quotes
  $/x
  
  case Regex.named_captures(regex, field_string) do
    %{"name" => name} = captures ->
      field = %{
        name: String.to_atom(name),
        type: parse_type(captures["type"], captures["list_type"]),
        optional: captures["optional"] == "?",
        description: captures["desc"]
      }
      {:ok, field}
    
    nil ->
      {:error, "Invalid field format: '#{field_string}'. Expected format: 'name[?][:type]['description']'"}
  end
end
```

### Step 3: Implement Type Parsing

```elixir
# Add to signature.ex

@type_mappings %{
  "str" => :string,
  "string" => :string,
  "int" => :integer,
  "integer" => :integer,
  "float" => :float,
  "number" => :float,
  "bool" => :boolean,
  "boolean" => :boolean,
  "dict" => :map,
  "Dict" => :map,
  "list" => :list,
  "List" => :list
}

defp parse_type(nil, _), do: :any
defp parse_type("", _), do: :any

defp parse_type(type_string, list_element_type) do
  base_type = String.downcase(type_string)
  
  cond do
    base_type in ["list", "List"] and list_element_type ->
      {:list, parse_simple_type(list_element_type)}
    
    Map.has_key?(@type_mappings, base_type) ->
      @type_mappings[base_type]
    
    true ->
      # Unknown type, treat as any
      :any
  end
end

defp parse_simple_type(type_string) do
  base_type = String.downcase(type_string)
  Map.get(@type_mappings, base_type, :any)
end
```

### Step 4: Add Validation and Error Handling

```elixir
# Add to signature.ex

@doc """
Validate a parsed signature for common issues.
"""
@spec validate(t()) :: :ok | {:error, String.t()}
def validate(%__MODULE__{inputs: inputs, outputs: outputs}) do
  with :ok <- validate_fields(inputs, "input"),
       :ok <- validate_fields(outputs, "output"),
       :ok <- validate_no_duplicates(inputs, "input"),
       :ok <- validate_no_duplicates(outputs, "output") do
    :ok
  end
end

defp validate_fields(fields, field_type) do
  if Enum.empty?(fields) do
    {:error, "Signature must have at least one #{field_type} field"}
  else
    :ok
  end
end

defp validate_no_duplicates(fields, field_type) do
  names = Enum.map(fields, & &1.name)
  unique_names = Enum.uniq(names)
  
  if length(names) != length(unique_names) do
    duplicates = names -- unique_names
    {:error, "Duplicate #{field_type} field names: #{inspect(duplicates)}"}
  else
    :ok
  end
end
```

### Step 5: Add Convenience Functions

```elixir
# Add to signature.ex

@doc """
Get all required input fields.
"""
@spec required_inputs(t()) :: [field()]
def required_inputs(%__MODULE__{inputs: inputs}) do
  Enum.reject(inputs, & &1.optional)
end

@doc """
Convert signature back to string format (normalize).
"""
@spec to_string(t()) :: String.t()
def to_string(%__MODULE__{inputs: inputs, outputs: outputs}) do
  input_str = Enum.map_join(inputs, ", ", &field_to_string/1)
  output_str = Enum.map_join(outputs, ", ", &field_to_string/1)
  "#{input_str} -> #{output_str}"
end

defp field_to_string(field) do
  name = Atom.to_string(field.name)
  optional = if field.optional, do: "?", else: ""
  type = type_to_string(field.type)
  desc = if field.description, do: " '#{field.description}'", else: ""
  
  if type == "" do
    "#{name}#{optional}#{desc}"
  else
    "#{name}#{optional}: #{type}#{desc}"
  end
end

defp type_to_string(:any), do: ""
defp type_to_string(:string), do: "str"
defp type_to_string(:integer), do: "int"
defp type_to_string(:float), do: "float"
defp type_to_string(:boolean), do: "bool"
defp type_to_string(:map), do: "dict"
defp type_to_string({:list, element_type}), do: "list[#{type_to_string(element_type)}]"
```

### Step 6: Create Comprehensive Tests
Create `/home/home/p/g/n/dspex/test/dspex/native/signature_test.exs`:

```elixir
defmodule DSPex.Native.SignatureTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Native.Signature
  
  describe "parse/1" do
    test "parses basic signature" do
      assert {:ok, sig} = Signature.parse("question -> answer")
      assert [%{name: :question, type: :any, optional: false}] = sig.inputs
      assert [%{name: :answer, type: :any, optional: false}] = sig.outputs
    end
    
    test "parses typed signature" do
      assert {:ok, sig} = Signature.parse("question: str -> answer: str")
      assert [%{name: :question, type: :string}] = sig.inputs
      assert [%{name: :answer, type: :string}] = sig.outputs
    end
    
    test "parses list types" do
      assert {:ok, sig} = Signature.parse("docs: list[str] -> summary: str")
      assert [%{name: :docs, type: {:list, :string}}] = sig.inputs
    end
    
    test "parses optional fields" do
      assert {:ok, sig} = Signature.parse("query: str, context?: str -> answer")
      assert [
        %{name: :query, optional: false},
        %{name: :context, optional: true}
      ] = sig.inputs
    end
    
    test "parses descriptions" do
      assert {:ok, sig} = Signature.parse("q: str 'user question' -> a: str 'bot answer'")
      assert [%{description: "user question"}] = sig.inputs
      assert [%{description: "bot answer"}] = sig.outputs
    end
    
    test "handles multiple inputs and outputs" do
      assert {:ok, sig} = Signature.parse("a: int, b: int -> sum: int, product: int")
      assert length(sig.inputs) == 2
      assert length(sig.outputs) == 2
    end
    
    test "returns error for invalid format" do
      assert {:error, msg} = Signature.parse("invalid signature")
      assert msg =~ "Invalid signature format"
    end
    
    test "returns error for invalid field" do
      assert {:error, msg} = Signature.parse("123invalid -> output")
      assert msg =~ "Invalid field format"
    end
  end
  
  describe "validate/1" do
    test "validates empty inputs" do
      sig = %Signature{inputs: [], outputs: [%{name: :out}]}
      assert {:error, msg} = Signature.validate(sig)
      assert msg =~ "at least one input"
    end
    
    test "validates duplicate field names" do
      sig = %Signature{
        inputs: [%{name: :a}, %{name: :a}],
        outputs: [%{name: :out}]
      }
      assert {:error, msg} = Signature.validate(sig)
      assert msg =~ "Duplicate"
    end
  end
  
  describe "type parsing" do
    test "recognizes all type aliases" do
      types = [
        {"str", :string},
        {"string", :string},
        {"int", :integer},
        {"integer", :integer},
        {"float", :float},
        {"number", :float},
        {"bool", :boolean},
        {"boolean", :boolean},
        {"dict", :map},
        {"Dict", :map}
      ]
      
      for {type_str, expected} <- types do
        assert {:ok, sig} = Signature.parse("x: #{type_str} -> y")
        assert [%{type: ^expected}] = sig.inputs
      end
    end
  end
  
  describe "to_string/1" do
    test "converts signature back to normalized string" do
      original = "q:str'desc',ctx?:str -> ans:str"
      assert {:ok, sig} = Signature.parse(original)
      normalized = Signature.to_string(sig)
      
      # Parse normalized version and compare
      assert {:ok, sig2} = Signature.parse(normalized)
      assert sig.inputs == sig2.inputs
      assert sig.outputs == sig2.outputs
    end
  end
end
```

## Acceptance Criteria

- [ ] Parse basic signatures (input -> output)
- [ ] Parse typed signatures with type annotations
- [ ] Parse list types (list[str], List[int])
- [ ] Parse optional fields (field?)
- [ ] Parse descriptions in single quotes
- [ ] Handle multiple inputs and outputs
- [ ] Provide comprehensive error messages for invalid signatures
- [ ] Validate parsed signatures (no empty, no duplicates)
- [ ] 100% test coverage for all parsing functions
- [ ] Support all DSPy type aliases

## Expected Deliverables

1. Complete implementation in `/lib/dspex/native/signature.ex`
2. Comprehensive test suite in `/test/dspex/native/signature_test.exs`
3. 100% test coverage verified with `mix test --cover`
4. All tests passing
5. Documentation complete with examples
6. Type specs for all public functions

## Verification

Run these commands to verify implementation:

```bash
# Run tests
mix test test/dspex/native/signature_test.exs

# Check coverage
mix test test/dspex/native/signature_test.exs --cover

# Verify no warnings
mix compile --warnings-as-errors

# Run dialyzer
mix dialyzer
```

## Notes

- Focus on clear error messages - this is user-facing
- Maintain compatibility with Python DSPy signatures
- Consider edge cases like empty strings, special characters
- The parser is performance-critical - optimize where possible
- This is a foundational component - get it right!