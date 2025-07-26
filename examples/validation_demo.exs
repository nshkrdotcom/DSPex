#!/usr/bin/env elixir

# Simple demonstration of the validation and type casting functionality
# Run with: mix run examples/validation_demo.exs

alias DSPex.Contract.Validation
alias DSPex.Contracts.TypeCasting

IO.puts("\n=== DSPex Contract Validation Demo ===\n")

# Example 1: Basic parameter validation
IO.puts("1. Basic Parameter Validation")
IO.puts("-----------------------------")

# Define a simple parameter specification
spec = [
  name: {:required, :string},
  age: {:required, :integer},
  email: {:optional, :string, "no-email@example.com"}
]

# Valid parameters
valid_params = %{name: "Alice", age: 30}
IO.puts("Valid params: #{inspect(valid_params)}")
IO.puts("Result: #{inspect(Validation.validate_params(valid_params, spec))}")

# Invalid type
invalid_params = %{name: "Bob", age: "thirty"}
IO.puts("\nInvalid params: #{inspect(invalid_params)}")
IO.puts("Result: #{inspect(Validation.validate_params(invalid_params, spec))}")

# Missing required parameter
missing_params = %{name: "Charlie"}
IO.puts("\nMissing params: #{inspect(missing_params)}")
IO.puts("Result: #{inspect(Validation.validate_params(missing_params, spec))}")

# Example 2: Complex type validation
IO.puts("\n\n2. Complex Type Validation")
IO.puts("--------------------------")

complex_spec = [
  tags: {:required, {:list, :string}},
  metadata: {:required, :map},
  active: {:required, :boolean}
]

complex_valid = %{
  tags: ["elixir", "dspy", "ai"],
  metadata: %{version: "1.0"},
  active: true
}
IO.puts("Valid complex params: #{inspect(complex_valid)}")
IO.puts("Result: #{inspect(Validation.validate_params(complex_valid, complex_spec))}")

complex_invalid = %{
  tags: ["elixir", 123, "ai"],  # Mixed types in list
  metadata: %{version: "1.0"},
  active: true
}
IO.puts("\nInvalid complex params: #{inspect(complex_invalid)}")
IO.puts("Result: #{inspect(Validation.validate_params(complex_invalid, complex_spec))}")

# Example 3: Type casting
IO.puts("\n\n3. Type Casting")
IO.puts("----------------")

# Integer to float
IO.puts("Cast 42 to float: #{inspect(TypeCasting.cast_result(42, :float))}")

# List casting
IO.puts("Cast [1, 2, 3] to list of floats: #{inspect(TypeCasting.cast_result([1, 2, 3], {:list, :float}))}")

# String to atom
IO.puts("Cast \"active\" to atom: #{inspect(TypeCasting.cast_result("active", :atom))}")

# Tuple conversion
IO.puts("Cast [1, 2, 3] to tuple: #{inspect(TypeCasting.cast_result([1, 2, 3], :tuple))}")

# Example 4: Variable keyword parameters
IO.puts("\n\n4. Variable Keyword Parameters")
IO.puts("------------------------------")

arbitrary_params = %{
  foo: "bar",
  baz: 123,
  nested: %{key: "value"}
}
IO.puts("Arbitrary params: #{inspect(arbitrary_params)}")
IO.puts("Result: #{inspect(Validation.validate_params(arbitrary_params, :variable_keyword))}")

# Example 5: Struct handling
IO.puts("\n\n5. Struct Type Casting")
IO.puts("----------------------")

prediction_data = %{
  "answer" => "The sky is blue due to Rayleigh scattering",
  "confidence" => 0.95
}
IO.puts("Prediction data: #{inspect(prediction_data)}")
IO.puts("Cast to struct: #{inspect(TypeCasting.cast_result(prediction_data, {:struct, DSPex.Types.Prediction}))}")

IO.puts("\n=== Demo Complete ===\n")