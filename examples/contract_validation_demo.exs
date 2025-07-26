# Contract Validation Demo
# This example demonstrates the DSPex contract validation system

# Load the DSPex application
Code.require_file("../lib/dspex/contract.ex", __DIR__)
Code.require_file("../lib/dspex/contract/validation.ex", __DIR__)
Code.require_file("../lib/dspex/contracts/type_casting.ex", __DIR__)

# Define a contract for a hypothetical TextSummarizer
defmodule MyApp.Contracts.TextSummarizer do
  @python_class "myapp.TextSummarizer"
  @contract_version "1.0.0"
  
  use DSPex.Contract
  
  defmethod :create, :__init__,
    params: [
      model_name: {:required, :string},
      max_length: {:optional, :integer, 100},
      temperature: {:optional, :float, 0.7}
    ],
    returns: :reference,
    description: "Create a new TextSummarizer instance"
    
  defmethod :summarize, :summarize,
    params: [
      text: {:required, :string},
      style: {:optional, :atom, :concise}
    ],
    returns: {:struct, MyApp.Types.Summary},
    description: "Summarize the given text"
    
  defmethod :batch_summarize, :batch_summarize,
    params: [
      texts: {:required, {:list, :string}}
    ],
    returns: {:list, {:struct, MyApp.Types.Summary}},
    description: "Summarize multiple texts at once"
end

# Define the Summary struct
defmodule MyApp.Types.Summary do
  @enforce_keys [:text]
  defstruct [:text, :word_count, :key_points]
  
  def from_python_result(%{"text" => text} = result) do
    {:ok, %__MODULE__{
      text: text,
      word_count: Map.get(result, "word_count"),
      key_points: Map.get(result, "key_points", [])
    }}
  end
end

# Demo usage
alias DSPex.Contract.Validation
alias DSPex.Contracts.TypeCasting

IO.puts("=== Contract Validation Demo ===\n")

# Example 1: Validate create parameters
IO.puts("1. Validating create parameters:")
create_spec = [
  model_name: {:required, :string},
  max_length: {:optional, :integer, 100},
  temperature: {:optional, :float, 0.7}
]

valid_params = %{model_name: "gpt-3.5-turbo"}
IO.inspect(Validation.validate_params(valid_params, create_spec), label: "Valid params")

invalid_params = %{model_name: 123}
IO.inspect(Validation.validate_params(invalid_params, create_spec), label: "Invalid params")

missing_params = %{}
IO.inspect(Validation.validate_params(missing_params, create_spec), label: "Missing params")

# Example 2: Type casting
IO.puts("\n2. Type casting examples:")

# Cast integer to float
IO.inspect(TypeCasting.cast_result(42, :float), label: "Integer to float")

# Cast list of integers to list of floats
IO.inspect(TypeCasting.cast_result([1, 2, 3], {:list, :float}), label: "List casting")

# Cast map to struct
summary_data = %{"text" => "This is a summary", "word_count" => 4, "key_points" => ["concise", "clear"]}
IO.inspect(TypeCasting.cast_result(summary_data, {:struct, MyApp.Types.Summary}), label: "Map to struct")

# Example 3: Variable keyword parameters
IO.puts("\n3. Variable keyword parameters:")
IO.inspect(Validation.validate_params(%{any: "param", another: 123}, :variable_keyword), label: "Variable keywords")

IO.puts("\n=== Demo Complete ===")