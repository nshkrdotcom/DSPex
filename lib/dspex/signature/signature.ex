defmodule DSPex.Signature do
  @moduledoc """
  Core signature behavior and DSL for defining native Elixir DSPy signatures.

  This module provides the foundation for the signature system that enables
  native Elixir syntax like:

      defmodule QA do
        use DSPex.Signature
        
        signature question: :string -> answer: :string
      end

  The signature DSL compiles to both runtime metadata and validation functions,
  enabling seamless integration with DSPy programs through the adapter pattern.

  ## Features

  - Native Elixir syntax for signature definitions
  - Compile-time AST processing and code generation
  - Runtime validation for inputs and outputs
  - JSON schema generation for provider compatibility
  - Type safety with comprehensive error handling
  - Support for basic and ML-specific types

  ## Example Usage

      defmodule BasicQA do
        use DSPex.Signature
        
        signature question: :string -> answer: :string
      end

      defmodule ComplexSignature do
        use DSPex.Signature
        
        signature query: :string, context: {:list, :string} -> 
                 answer: :string, confidence: :float, reasoning: {:list, :string}
      end

      # Runtime usage
      {:ok, validated} = BasicQA.validate_inputs(%{question: "What is 2+2?"})
      schema = BasicQA.to_json_schema(:openai)
  """

  @doc """
  Sets up the signature DSL and compile-time processing for a module.

  When `use DSPex.Signature` is called, this macro:
  1. Imports the signature DSL
  2. Sets up module attributes for signature metadata
  3. Registers compile-time hooks for code generation
  4. Enables enhanced metadata generation for dynamic signatures

  ## Module Attributes

  - `@signature_ast` - Stores the raw AST from the signature definition
  - `@signature_compiled` - Stores the compiled signature metadata
  - `@signature_description` - Optional description for enhanced metadata

  ## Options

  - `:description` - Custom description for the signature
  - `:dynamic_compatible` - Generate enhanced metadata for Python bridge (default: true)
  """
  defmacro __using__(opts) do
    quote do
      import DSPex.Signature.DSL
      Module.register_attribute(__MODULE__, :signature_ast, accumulate: false)
      Module.register_attribute(__MODULE__, :signature_compiled, accumulate: false)
      Module.register_attribute(__MODULE__, :signature_description, accumulate: false)

      # Store options for use in compiler
      @signature_opts unquote(opts)

      @before_compile DSPex.Signature.Compiler
    end
  end

  defmodule DSL do
    @moduledoc """
    Domain-specific language for defining signatures with native Elixir syntax.

    This module provides the `signature` macro that captures signature definitions
    and stores them for compile-time processing.
    """

    @doc """
    Defines a signature with native Elixir syntax.

    The signature macro supports several syntax patterns:

    ## Basic Pattern
        signature input_field: :type -> output_field: :type

    ## Multiple Fields
        signature field1: :type, field2: :type -> output1: :type, output2: :type

    ## Complex Types
        signature query: :string, context: {:list, :string} -> 
                 answer: :string, confidence: :probability

    ## Supported Types

    ### Basic Types
    - `:string` - Text data
    - `:integer` - Whole numbers
    - `:float` - Decimal numbers  
    - `:boolean` - True/false values
    - `:atom` - Enumerated values
    - `:any` - Unconstrained values
    - `:map` - Structured data

    ### ML-Specific Types
    - `:embedding` - Vector embeddings
    - `:probability` - Values 0.0-1.0
    - `:confidence_score` - Model confidence
    - `:reasoning_chain` - Step-by-step reasoning

    ### Composite Types
    - `{:list, inner_type}` - Arrays
    - `{:dict, key_type, value_type}` - Key-value mappings
    - `{:union, [type1, type2, ...]}` - One of multiple types

    ## Examples

        # Simple Q&A
        signature question: :string -> answer: :string

        # Complex reasoning
        signature problem: :string, hints: {:list, :string} -> 
                 solution: :string, 
                 steps: {:list, :string}, 
                 confidence: :probability

        # Classification
        signature text: :string -> category: :atom, score: :float
    """
    defmacro signature(do: signature_ast) do
      quote do
        @signature_ast unquote(Macro.escape(signature_ast))
      end
    end

    defmacro signature(signature_ast) do
      quote do
        @signature_ast unquote(Macro.escape(signature_ast))
      end
    end

    @doc """
    Sets a description for the signature.

    This description will be used in enhanced metadata generation
    for better documentation and Python bridge integration.

    ## Examples

        defmodule MySignature do
          use DSPex.Signature

          description "Analyzes text sentiment and extracts key themes"
          signature text: :string -> sentiment: :string, themes: {:list, :string}
        end
    """
    defmacro description(desc) when is_binary(desc) do
      quote do
        @signature_description unquote(desc)
      end
    end
  end
end
