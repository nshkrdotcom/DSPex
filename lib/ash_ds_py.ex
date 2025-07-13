defmodule DSPex do
  @moduledoc """
  DSPex: Native Elixir DSPy integration with the Ash framework.

  DSPex provides a signature system that enables native Elixir syntax for
  defining DSPy programs, with seamless integration into the Ash framework
  for domain modeling and resource management.

  ## Features

  - Native Elixir signature syntax: `signature question: :string -> answer: :string`
  - Compile-time AST processing and code generation
  - Runtime validation for inputs and outputs
  - JSON schema generation for AI provider compatibility
  - Type system supporting basic, ML-specific, and composite types
  - Integration with Ash resource lifecycle

  ## Quick Start

      defmodule QA do
        use DSPex.Signature
        
        signature question: :string -> answer: :string
      end

      # Validate inputs
      {:ok, validated} = QA.validate_inputs(%{question: "What is 2+2?"})
      
      # Generate JSON schema
      schema = QA.to_json_schema(:openai)

  ## Architecture

  DSPex follows a modular architecture:

  - `DSPex.Signature` - Core signature behavior and DSL
  - `DSPex.Signature.Compiler` - Compile-time processing
  - `DSPex.Signature.TypeParser` - Type system parser
  - `DSPex.Signature.Validator` - Runtime validation
  - `DSPex.Signature.JsonSchema` - Provider schema generation
  """

  @doc """
  Returns the version of DSPex.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:dspex, :vsn) |> to_string()
  end
end
