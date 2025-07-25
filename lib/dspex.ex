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

  alias DSPex.Pipeline

  # Type aliases for cleaner specs
  @type signature :: DSPex.Native.Signature.t()
  @type signature_compiled :: %{
          signature: DSPex.Native.Signature.t(),
          validator: (map() -> {:ok, map()} | {:error, term()}),
          serializer: (map() -> {binary(), map()}),
          compiled_at: DateTime.t()
        }

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
  @spec compile_signature(binary()) :: {:ok, signature_compiled()} | {:error, term()}
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
  def predict(signature, inputs, opts \\ []) do
    DSPex.Modules.Predict.predict(signature, inputs, opts)
  end

  @doc """
  Chain of Thought reasoning.

  Generates step-by-step reasoning before the final answer.
  """
  @spec chain_of_thought(signature(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chain_of_thought(signature, inputs, opts \\ []) do
    DSPex.Modules.ChainOfThought.think(signature, inputs, opts)
  end

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
  def react(signature, inputs, tools, opts \\ []) do
    DSPex.Modules.ReAct.reason_and_act(signature, inputs, tools, opts)
  end

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

  # LLM operations

  @doc """
  Create a new LLM client for direct model interactions.

  ## Examples

      # Using InstructorLite
      {:ok, client} = DSPex.lm_client(
        adapter: :instructor_lite,
        provider: :openai,
        api_key: System.get_env("OPENAI_API_KEY")
      )
      
      # Using HTTP adapter
      {:ok, client} = DSPex.lm_client(
        adapter: :http,
        provider: :anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY")
      )
  """
  @spec lm_client(keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate lm_client(opts), to: DSPex.LLM.Client, as: :new

  @doc """
  Generate text using an LLM client.
  """
  @spec lm_generate(
          %{:adapter_module => atom(), any() => any()},
          binary() | list(map()),
          Keyword.t()
        ) :: {:error, any()} | {:ok, map()}
  defdelegate lm_generate(client, prompt, opts \\ []), to: DSPex.LLM.Client, as: :generate

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
      snakepit_status: snakepit_status(),
      native_modules: DSPex.Native.Registry.list()
    }
  end

  defp snakepit_status do
    case Snakepit.get_stats() do
      stats when is_map(stats) ->
        Map.put(stats, :status, :running)

      _ ->
        %{status: :not_available}
    end
  catch
    _, _ -> %{status: :error}
  end
end
