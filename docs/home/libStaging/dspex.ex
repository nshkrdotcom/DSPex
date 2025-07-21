defmodule DSPEx do
  @moduledoc """
  Enhanced entry point for DSPEx with ElixirML foundation integration.

  DSPEx is an Elixir implementation of the DSPy framework enhanced with the revolutionary
  ElixirML foundation, providing universal parameter optimization, ML-native validation,
  and automatic module selection capabilities.

  ## Key Features

  - **Declarative Signatures**: Define program interfaces with ML-specific types
  - **Universal Variable System**: Automatic optimization of ANY parameter
  - **ML-Native Validation**: Schema validation with embeddings, probabilities, etc.
  - **Automatic Optimization**: SIMBA teleprompter with variable-aware optimization
  - **Process Orchestration**: Advanced supervision and fault tolerance
  - **Schema Integration**: ElixirML Schema Engine for comprehensive validation

  ## Enhanced Quick Start

      # Define an ML-aware signature
      defmodule QASignature do
        use DSPEx.Signature, :schema_dsl
        
        input :question, :string
        input :context, :embedding, dimensions: 1536
        output :answer, :string
        output :confidence, :confidence_score
      end

      # Create an enhanced program with variables
      program = DSPEx.program(QASignature)
      |> DSPEx.with_variables(%{provider: :openai, temperature: 0.7})
      |> DSPEx.with_schema_validation(true)

      # Execute with automatic validation
      {:ok, result} = DSPEx.forward(program, %{
        question: "What is ML?",
        context: [0.1, 0.2, ...] # 1536-dimensional embedding
      })

  ## Enhanced Modules

  - `DSPEx.Signature` - ML-aware program interfaces with schema validation
  - `DSPEx.Program` - Enhanced program execution with variable optimization
  - `DSPEx.Builder` - Fluent API for program configuration
  - `ElixirML.Variable` - Universal parameter optimization system
  - `ElixirML.Schema` - ML-native validation engine
  """

  alias DSPEx.{Program, Builder}
  # ElixirML integration handled dynamically to avoid circular dependencies

  @doc """
  Creates an enhanced DSPEx program with ElixirML foundation integration.

  This is the primary entry point for creating programs that leverage the
  ElixirML foundation's variable system, schema validation, and process orchestration.

  ## Parameters
  - `signature` - Signature module defining program interface
  - `opts` - Optional configuration parameters

  ## Options
  - `:variables` - Map of variable overrides
  - `:schema_validation` - Enable schema validation (default: false)
  - `:client` - Client configuration
  - `:adapter` - Adapter configuration

  ## Returns
  - `{:ok, program}` - Enhanced program ready for execution
  - `{:error, reason}` - Program creation failed

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_variables(%{temperature: 0.8})
      |> DSPEx.with_schema_validation(true)

  """
  @spec program(module(), keyword()) :: {:ok, Builder.t()} | {:error, term()}
  def program(signature_module, opts \\ []) do
    Builder.new(signature_module, opts)
  end

  @doc """
  Adds variables to a program builder for automatic optimization.

  Variables specified here can be automatically optimized by SIMBA and other
  teleprompters, enabling parameter tuning without manual intervention.

  ## Parameters
  - `builder` - Program builder from DSPEx.program/2
  - `variables` - Map of variable names to values

  ## Returns
  - Updated program builder with variables configured

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_variables(%{
        provider: :openai,
        temperature: 0.7,
        max_tokens: 150
      })

  """
  @spec with_variables(Builder.t(), map()) :: Builder.t()
  def with_variables(%Builder{} = builder, variables) when is_map(variables) do
    Builder.with_variables(builder, variables)
  end

  @doc """
  Enables or disables schema validation for the program.

  When enabled, all inputs and outputs are validated using the ElixirML
  Schema Engine with ML-specific type checking.

  ## Parameters
  - `builder` - Program builder from DSPEx.program/2
  - `enabled` - Boolean to enable/disable validation

  ## Returns
  - Updated program builder with schema validation configured

  ## Examples

      program = DSPEx.program(QASignature)
      |> DSPEx.with_schema_validation(true)

  """
  @spec with_schema_validation(Builder.t(), boolean()) :: Builder.t()
  def with_schema_validation(%Builder{} = builder, enabled) when is_boolean(enabled) do
    Builder.with_schema_validation(builder, enabled)
  end

  @doc """
  Executes a program with the given inputs using the Process Orchestrator.

  This function leverages the ElixirML Process Orchestrator for execution,
  providing fault tolerance, telemetry, and performance optimization.

  ## Parameters
  - `program` - Program or builder to execute
  - `inputs` - Map of input values
  - `opts` - Execution options

  ## Options
  - `:validate_inputs` - Validate inputs before execution (default: true)
  - `:validate_outputs` - Validate outputs after execution (default: true)
  - `:timeout` - Execution timeout in milliseconds

  ## Returns
  - `{:ok, outputs}` - Execution successful with validated outputs
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = DSPEx.forward(program, %{
        question: "What is machine learning?",
        context: embedding_vector
      })

  """
  @spec forward(Builder.t() | struct(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def forward(program_or_builder, inputs, opts \\ [])

  def forward(%Builder{} = builder, inputs, opts) do
    case Builder.build(builder) do
      {:ok, program} -> forward(program, inputs, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def forward(program, inputs, opts) when is_struct(program) do
    validate_inputs = Keyword.get(opts, :validate_inputs, true)
    validate_outputs = Keyword.get(opts, :validate_outputs, true)

    with {:ok, validated_inputs} <- maybe_validate_inputs(program, inputs, validate_inputs),
         {:ok, outputs} <- Program.forward(program, validated_inputs, opts),
         {:ok, validated_outputs} <- maybe_validate_outputs(program, outputs, validate_outputs) do
      {:ok, validated_outputs}
    end
  end

  @doc """
  Optimizes a program using the enhanced SIMBA teleprompter with variable awareness.

  This function leverages the ElixirML Variable System to automatically
  optimize any parameters declared as variables in the program.

  ## Parameters
  - `program` - Program or builder to optimize
  - `training_data` - List of training examples
  - `opts` - Optimization options

  ## Options
  - `:variables` - List of variable names to optimize (default: all)
  - `:objectives` - List of optimization objectives (default: [:accuracy])
  - `:teleprompter` - Teleprompter module (default: DSPEx.Teleprompter.SIMBA)

  ## Returns
  - `{:ok, optimized_program}` - Optimization successful
  - `{:error, reason}` - Optimization failed

  ## Examples

      {:ok, optimized} = DSPEx.optimize(program, training_data,
        variables: [:temperature, :provider],
        objectives: [:accuracy, :cost, :latency]
      )

  """
  @spec optimize(Builder.t() | struct(), [DSPEx.Example.t()], keyword()) ::
          {:ok, struct()} | {:error, term()}
  def optimize(program_or_builder, training_data, opts \\ []) do
    teleprompter = Keyword.get(opts, :teleprompter, DSPEx.Teleprompter.SIMBA)

    case ensure_program(program_or_builder) do
      {:ok, program} -> teleprompter.optimize(program, training_data, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns a greeting atom for basic library verification.

  This function is primarily used for testing the library installation
  and basic functionality.

  ## Returns

  The atom `:world`

  ## Examples

      iex> DSPEx.hello()
      :world

  """
  @spec hello() :: :world
  def hello do
    :world
  end

  # Private helper functions

  @spec ensure_program(Builder.t() | struct()) :: {:ok, struct()} | {:error, term()}
  defp ensure_program(%Builder{} = builder) do
    Builder.build(builder)
  end

  defp ensure_program(program) when is_struct(program) do
    {:ok, program}
  end

  @spec maybe_validate_inputs(struct(), map(), boolean()) :: {:ok, map()} | {:error, term()}
  defp maybe_validate_inputs(program, inputs, true) do
    if DSPEx.Program.schema_validation_enabled?(program) do
      program.signature.validate_inputs_with_schema(inputs)
    else
      program.signature.validate_inputs(inputs)
      {:ok, inputs}
    end
  end

  defp maybe_validate_inputs(_program, inputs, false) do
    {:ok, inputs}
  end

  @spec maybe_validate_outputs(struct(), map(), boolean()) :: {:ok, map()} | {:error, term()}
  defp maybe_validate_outputs(program, outputs, true) do
    if DSPEx.Program.schema_validation_enabled?(program) do
      program.signature.validate_outputs_with_schema(outputs)
    else
      program.signature.validate_outputs(outputs)
      {:ok, outputs}
    end
  end

  defp maybe_validate_outputs(_program, outputs, false) do
    {:ok, outputs}
  end
end
