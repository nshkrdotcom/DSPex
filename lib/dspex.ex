defmodule DSPex do
  @moduledoc """
  DSPex provides a unified interface for DSPy functionality in Elixir.

  This is the main entry point for all DSPex operations. Implementation details
  are hidden - operations are automatically routed to native Elixir or Python
  implementations based on availability and performance characteristics.

  ## Basic Usage

      # Parse a signature
      {:ok, signature} = DSPex.signature("question: str -> answer: str")
      
      # Execute a prediction
      {:ok, result} = DSPex.predict(signature, %{question: "What is DSPy?"})
      
      # Use chain of thought
      {:ok, cot_result} = DSPex.chain_of_thought(signature, %{question: "Explain quantum computing"})
      
  ## Pipelines

      pipeline = DSPex.pipeline([
        {:native, DSPex.Native.Signature, spec: "query -> keywords: list[str]"},
        {:python, "dspy.ChainOfThought", signature: "keywords -> summary"},
        {:native, DSPex.Native.Template, template: "Summary: <%= @summary %>"}
      ])
      
      {:ok, result} = DSPex.run_pipeline(pipeline, %{query: "machine learning"})
  """

  alias DSPex.Router
  alias DSPex.Pipeline

  # Type aliases for cleaner specs
  @type signature :: DSPex.Native.Signature.t()
  @type signature_compiled :: map()

  # Signatures - always native for performance

  @doc """
  Parse a DSPy signature specification.

  Signatures define the input and output schema for ML operations.

  ## Examples

      # Simple signature
      DSPex.signature("question -> answer")
      
      # With types
      DSPex.signature("question: str -> answer: str, confidence: float")
      
      # With descriptions
      DSPex.signature("question: str 'User query' -> answer: str 'Generated response'")
  """
  @spec signature(String.t() | map()) :: {:ok, signature()} | {:error, term()}
  defdelegate signature(spec), to: DSPex.Native.Signature, as: :parse

  @doc """
  Compile a signature for optimized repeated use.
  """
  @spec compile_signature(String.t()) :: {:ok, signature_compiled()} | {:error, term()}
  defdelegate compile_signature(spec), to: DSPex.Native.Signature, as: :compile

  # Module operations - routed to appropriate implementation

  @doc """
  Basic prediction using a signature.

  ## Options

    * `:temperature` - LLM temperature (0.0-2.0)
    * `:max_tokens` - Maximum tokens to generate
    * `:model` - Specific model to use
    * `:stream` - Enable streaming responses
  """
  @spec predict(signature(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate predict(signature, inputs, opts \\ []), to: Router

  @doc """
  Chain of Thought reasoning.

  Generates step-by-step reasoning before the final answer.
  """
  @spec chain_of_thought(signature(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate chain_of_thought(signature, inputs, opts \\ []), to: Router

  @doc """
  ReAct pattern - Reasoning + Acting with tools.

  ## Example

      tools = [
        %{name: "search", description: "Search the web", function: &search/1},
        %{name: "calculate", description: "Perform calculations", function: &calc/1}
      ]
      
      DSPex.react(signature, inputs, tools)
  """
  @spec react(signature(), map(), list(map()), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate react(signature, inputs, tools, opts \\ []), to: Router

  # Pipeline operations

  @doc """
  Create a pipeline of operations.

  Pipelines can mix native and Python implementations seamlessly.
  """
  @spec pipeline(list(Pipeline.step())) :: Pipeline.t()
  defdelegate pipeline(steps), to: Pipeline, as: :new

  @doc """
  Execute a pipeline with given input.

  ## Options

    * `:timeout` - Overall pipeline timeout (default: 30000ms)
    * `:continue_on_error` - Continue execution on step failure
    * `:stream` - Enable streaming for supported steps
  """
  @spec run_pipeline(Pipeline.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  defdelegate run_pipeline(pipeline, input, opts \\ []), to: Pipeline, as: :run

  # Utility functions

  @doc """
  Validate data against a signature.
  """
  @spec validate(map(), signature()) :: :ok | {:error, list(String.t())}
  defdelegate validate(data, signature), to: DSPex.Native.Validator

  @doc """
  Render a template with context.
  """
  @spec render_template(String.t(), map()) :: String.t()
  defdelegate render_template(template, context), to: DSPex.Native.Template, as: :render

  @doc """
  Check system health and status.
  """
  @spec health_check() :: %{
          status: :ok,
          version: String.t(),
          pools: map(),
          native_modules: term(),
          python_modules: term()
        }
  def health_check do
    %{
      status: :ok,
      version: "0.1.0",
      pools: DSPex.Python.PoolManager.status(),
      native_modules: DSPex.Native.Registry.list(),
      python_modules: DSPex.Python.Registry.list()
    }
  end
end
