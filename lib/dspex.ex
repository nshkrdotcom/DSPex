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

  alias SnakepitGRPCBridge.API

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
  def signature(spec) do
    # TODO: Implement via platform API
    {:error, :not_implemented}
  end

  @doc """
  Compile a signature for optimized repeated use.
  """
  @spec compile_signature(binary()) :: {:ok, signature_compiled()} | {:error, term()}
  def compile_signature(spec) do
    # TODO: Implement via platform API
    {:error, :not_implemented}
  end

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
    with {:ok, session_id} <- get_or_create_session(opts) do
      API.DSPy.predict(session_id, signature, inputs, opts)
    end
  end

  @doc """
  Chain of Thought reasoning.

  Generates step-by-step reasoning before the final answer.
  """
  @spec chain_of_thought(signature(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chain_of_thought(signature, inputs, opts \\ []) do
    with {:ok, session_id} <- get_or_create_session(opts) do
      config = Map.new(opts)
      {:ok, module_id} = API.DSPy.create_module(session_id, "dspy.ChainOfThought", config)
      API.DSPy.execute_module(session_id, module_id, inputs, opts)
    end
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
    with {:ok, session_id} <- get_or_create_session(opts) do
      # Register tools
      Enum.each(tools, fn tool ->
        API.Tools.register_elixir_tool(session_id, tool, tool.function)
      end)
      
      config = Map.merge(%{tools: tools}, Map.new(opts))
      {:ok, module_id} = API.DSPy.create_module(session_id, "dspy.ReAct", config)
      API.DSPy.execute_module(session_id, module_id, inputs, opts)
    end
  end

  # Pipeline operations

  @doc """
  Create a pipeline of operations.

  Pipelines can mix native and Python implementations seamlessly.
  """
  @spec pipeline(list(map())) :: map()
  def pipeline(steps) do
    %{steps: steps, id: generate_id()}
  end

  @doc """
  Execute a pipeline with given input.

  ## Options

    * `:timeout` - Overall pipeline timeout (default: 30000ms)
    * `:continue_on_error` - Continue execution on step failure
    * `:stream` - Enable streaming for supported steps
  """
  @spec run_pipeline(map(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def run_pipeline(pipeline, input, opts \\ []) do
    # TODO: Implement pipeline execution via platform API
    {:error, :not_implemented}
  end

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
  def lm_client(opts) do
    with {:ok, session_id} <- get_or_create_session(opts) do
      API.DSPy.configure_lm(session_id, Map.new(opts))
      {:ok, %{session_id: session_id}}
    end
  end

  @doc """
  Generate text using an LLM client.
  """
  @spec lm_generate(
          %{:session_id => String.t(), any() => any()},
          binary() | list(map()),
          Keyword.t()
        ) :: {:error, any()} | {:ok, map()}
  def lm_generate(%{session_id: session_id}, prompt, opts \\ []) do
    API.DSPy.predict(session_id, "prompt -> response", %{prompt: prompt}, opts)
  end

  # Utility functions

  @doc """
  Validate data against a signature.
  """
  @spec validate(map(), signature()) :: :ok | {:error, list(String.t())}
  def validate(data, signature) do
    # TODO: Implement validation via platform API
    {:error, :not_implemented}
  end

  @doc """
  Render a template with context.
  """
  @spec render_template(String.t(), map()) :: String.t()
  def render_template(template, context) do
    # Simple EEx rendering as fallback
    EEx.eval_string(template, assigns: Map.to_list(context))
  end

  @doc """
  Check system health and status.
  """
  @spec health_check() :: %{
          status: :ok,
          version: String.t(),
          platform_status: map()
        }
  def health_check do
    %{
      status: :ok,
      version: "0.2.0",
      platform_status: platform_status()
    }
  end

  defp platform_status do
    # TODO: Get actual platform status
    %{status: :ok}
  end
  
  # Helper functions
  
  defp get_or_create_session(opts) do
    case Keyword.get(opts, :session_id) do
      nil -> 
        session_id = generate_id()
        API.Sessions.create_session(session_id)
      session_id -> 
        {:ok, session_id}
    end
  end
  
  defp generate_id do
    "dspex_#{:erlang.system_time(:microsecond)}_#{:rand.uniform(10000)}"
  end
end
