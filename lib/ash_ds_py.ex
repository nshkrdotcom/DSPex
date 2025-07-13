defmodule AshDSPex do
  @moduledoc """
  AshDSPex: Native Elixir DSPy integration with the Ash framework.

  AshDSPex provides a signature system that enables native Elixir syntax for
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
        use AshDSPex.Signature
        
        signature question: :string -> answer: :string
      end

      # Validate inputs
      {:ok, validated} = QA.validate_inputs(%{question: "What is 2+2?"})
      
      # Generate JSON schema
      schema = QA.to_json_schema(:openai)

  ## Architecture

  AshDSPex follows a modular architecture:

  - `AshDSPex.Signature` - Core signature behavior and DSL
  - `AshDSPex.Signature.Compiler` - Compile-time processing
  - `AshDSPex.Signature.TypeParser` - Type system parser
  - `AshDSPex.Signature.Validator` - Runtime validation
  - `AshDSPex.Signature.JsonSchema` - Provider schema generation
  """

  @doc """
  Returns the version of AshDSPex.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:ash_dspex, :vsn) |> to_string()
  end
end
