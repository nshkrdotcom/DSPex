defmodule DSPEx.Program do
  @moduledoc """
  Enhanced DSPEx program behavior with ElixirML foundation integration.

  This module defines the core behavior that all DSPEx programs must implement,
  providing a unified interface for forward execution with built-in telemetry,
  correlation tracking, error handling, enhanced SIMBA optimization support,
  and revolutionary Variable System integration for automatic parameter optimization.

  ## Basic Program Implementation

      defmodule MyProgram do
        use DSPEx.Program

        defstruct [:signature, :client, :demos]

        @impl DSPEx.Program
        def forward(program, inputs, opts \\ []) do
          # Implementation here
          {:ok, %{answer: "result"}}
        end
      end

  ## Variable-Enhanced Program Implementation

      defmodule MyEnhancedProgram do
        use DSPEx.Program

        defstruct [:signature, :client, :demos, :variable_space, :config]

        # Declare variables for automatic optimization
        variable :temperature, :float, range: {0.0, 2.0}, default: 0.7
        variable :provider, :choice, choices: [:openai, :anthropic, :groq]
        variable :reasoning_strategy, :module,
          modules: [DSPEx.Reasoning.Predict, DSPEx.Reasoning.ChainOfThought]

        @impl DSPEx.Program
        def forward(program, inputs, opts \\ []) do
          # Variables are automatically resolved from opts[:variables]
          resolved_config = resolve_variables(program, opts)
          # Use resolved_config.temperature, resolved_config.provider, etc.
          {:ok, %{answer: "optimized result"}}
        end
      end

  ## Telemetry

  All programs automatically emit telemetry events:
  - `[:dspex, :program, :forward, :start]`
  - `[:dspex, :program, :forward, :stop]`
  - `[:dspex, :program, :forward, :exception]`
  - `[:dspex, :program, :variable, :resolution]` (new)

  """

  @type t :: struct()
  @type program :: struct()
  @type inputs :: map()
  @type outputs :: map()
  @type options :: keyword()
  @type variable_configuration :: %{atom() => any()}
  @type enhanced_options :: keyword() | %{optional(:variables) => variable_configuration()}

  @doc """
  Execute a program with the given inputs.

  This is the core behavior callback that all programs must implement.
  It should take a program struct and input map, and return either
  `{:ok, outputs}` or `{:error, reason}`.

  ## Parameters

  - `program` - The program struct containing configuration
  - `inputs` - Map of input field values

  ## Returns

  - `{:ok, outputs}` - Successful execution with result map
  - `{:error, reason}` - Error during execution

  """
  @callback forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}

  @doc """
  Execute a program with the given inputs and options.

  Optional callback for programs that need configuration options.

  """
  @callback forward(program(), inputs(), enhanced_options()) ::
              {:ok, outputs()} | {:error, term()}

  @optional_callbacks forward: 3

  # Variable System Integration
  @doc """
  Declare a variable for automatic optimization in a program.

  This macro allows programs to declare parameters that can be automatically
  optimized by SIMBA and other teleprompters using the ElixirML Variable System.

  ## Parameters

  - `name` - Variable name (atom)
  - `type` - Variable type (:float, :integer, :choice, :module, :composite)
  - `opts` - Variable configuration options

  ## Variable Types

  - `:float` - Continuous parameters with range constraints
  - `:integer` - Discrete numeric parameters  
  - `:choice` - Categorical selection from predefined options
  - `:module` - Automatic module selection for algorithm switching
  - `:composite` - Computed variables with dependencies

  ## Examples

      # Continuous parameter
      variable :temperature, :float, range: {0.0, 2.0}, default: 0.7

      # Provider selection
      variable :provider, :choice, choices: [:openai, :anthropic, :groq]

      # Automatic module selection
      variable :reasoning_strategy, :module,
        modules: [DSPEx.Reasoning.Predict, DSPEx.Reasoning.ChainOfThought]

  """
  defmacro variable(name, type, opts \\ []) do
    quote do
      variable_struct =
        case unquote(type) do
          :float ->
            ElixirML.Variable.float(unquote(name), unquote(opts))

          :integer ->
            ElixirML.Variable.integer(unquote(name), unquote(opts))

          :choice ->
            choices = Keyword.get(unquote(opts), :choices, [])

            ElixirML.Variable.choice(
              unquote(name),
              choices,
              Keyword.drop(unquote(opts), [:choices])
            )

          :module ->
            ElixirML.Variable.module(unquote(name), unquote(opts))

          :composite ->
            ElixirML.Variable.composite(unquote(name), unquote(opts))
        end

      @variables Map.put(@variables || %{}, unquote(name), variable_struct)
    end
  end

  @doc """
  Create a variable space from declared variables.

  This function creates an ElixirML Variable.Space from all variables
  declared using the `variable/3` macro, enabling automatic optimization.
  """
  def create_variable_space(program_module) when is_atom(program_module) do
    variables = get_declared_variables(program_module)

    if Enum.empty?(variables) do
      # Add standard ML variables for programs without explicit declarations
      ElixirML.Variable.MLTypes.standard_ml_config()
    else
      # Create space from declared variables
      Enum.reduce(variables, ElixirML.Variable.Space.new(), fn {_name, variable}, space ->
        ElixirML.Variable.Space.add_variable(space, variable)
      end)
    end
  end

  @doc """
  Get variables declared by a program module.

  Returns the variables declared using the `variable/3` macro.
  """
  def get_declared_variables(program_module) when is_atom(program_module) do
    if function_exported?(program_module, :__variables__, 0) do
      program_module.__variables__()
    else
      %{}
    end
  end

  @doc """
  Resolve variable configuration for a program.

  Takes variable values from options and resolves them to concrete values
  using the program's variable space.

  ## Parameters

  - `program` - Program struct with variable space
  - `opts` - Options containing `:variables` key with variable values

  ## Returns

  Resolved configuration map with concrete variable values.
  """
  def resolve_variables(program, opts) when is_struct(program) do
    variable_config = get_variable_config(opts)

    cond do
      # Program has variable_space field
      Map.has_key?(program, :variable_space) and program.variable_space ->
        resolve_with_space(program.variable_space, variable_config)

      # Program module has declared variables
      not Enum.empty?(get_declared_variables(program.__struct__)) ->
        space = create_variable_space(program.__struct__)
        resolve_with_space(space, variable_config)

      # No variables - return empty config
      true ->
        %{}
    end
  end

  @doc """
  Execute a program with Foundation observability and correlation tracking.

  This is the main entry point that wraps the behavior callback with
  automatic telemetry, correlation tracking, and error handling.

  """
  @spec forward(program(), inputs()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs) do
    forward(program, inputs, [])
  end

  @spec forward(program(), inputs(), options()) :: {:ok, outputs()} | {:error, term()}
  def forward(program, inputs, opts) when is_map(inputs) do
    # PERFORMANCE INSTRUMENTATION - Start
    total_start = System.monotonic_time()

    # Step 1: Extract and validate options (SIMBA critical feature)
    {timeout, model_config, correlation_id, execution_opts} = extract_execution_options(opts)

    # Step 2: Program name resolution
    program_name_start = System.monotonic_time()
    program_name = program_name(program)

    _program_name_duration =
      System.convert_time_unit(
        System.monotonic_time() - program_name_start,
        :native,
        :microsecond
      )

    # Step 2.5: Variable resolution (ElixirML integration)
    variable_resolution_start = System.monotonic_time()
    resolved_variables = resolve_variables(program, opts)
    has_variables = not Enum.empty?(resolved_variables)

    _variable_resolution_duration =
      System.convert_time_unit(
        System.monotonic_time() - variable_resolution_start,
        :native,
        :microsecond
      )

    # Step 3: Start telemetry
    telemetry_start_time = System.monotonic_time()
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :program, :forward, :start],
      %{system_time: System.system_time()},
      %{
        program: program_name,
        correlation_id: correlation_id,
        input_count: map_size(inputs),
        timeout: timeout,
        model_config: model_config,
        has_variables: has_variables,
        variable_count: map_size(resolved_variables)
      }
    )

    _telemetry_start_duration =
      System.convert_time_unit(
        System.monotonic_time() - telemetry_start_time,
        :native,
        :microsecond
      )

    # Step 4: Actual program execution with timeout and model config support
    execution_start = System.monotonic_time()

    result =
      if timeout != 30_000 do
        # Custom timeout specified - use task wrapper for timeout support
        task =
          Task.async(fn ->
            try do
              execute_with_model_config(
                program,
                inputs,
                model_config,
                resolved_variables,
                execution_opts
              )
            catch
              kind, reason ->
                {:error, {kind, reason}}
            end
          end)

        case Task.yield(task, timeout) do
          {:ok, {:error, {kind, reason}}} ->
            # Re-raise the original exception to maintain compatibility
            :erlang.raise(kind, reason, [])

          {:ok, program_result} ->
            program_result

          nil ->
            # Timeout occurred - kill the task and return timeout error
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
      else
        # Default timeout - execute directly for backward compatibility and performance
        execute_with_model_config(
          program,
          inputs,
          model_config,
          resolved_variables,
          execution_opts
        )
      end

    _execution_duration =
      System.convert_time_unit(System.monotonic_time() - execution_start, :native, :microsecond)

    # Step 5: Stop telemetry
    telemetry_stop_start = System.monotonic_time()
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :program, :forward, :stop],
      %{duration: duration, success: success},
      %{
        program: program_name,
        correlation_id: correlation_id,
        timeout_used: timeout,
        was_timeout: match?({:error, :timeout}, result),
        model_config: model_config
      }
    )

    _telemetry_stop_duration =
      System.convert_time_unit(
        System.monotonic_time() - telemetry_stop_start,
        :native,
        :microsecond
      )

    # PERFORMANCE INSTRUMENTATION - Report
    _total_duration =
      System.convert_time_unit(System.monotonic_time() - total_start, :native, :microsecond)

    result
  end

  def forward(_, inputs, _) when not is_map(inputs),
    do: {:error, {:invalid_inputs, "inputs must be a map"}}

  # Private function to extract execution options for SIMBA support
  defp extract_execution_options(opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Extract model configuration for SIMBA
    model_config =
      %{
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens),
        model: Keyword.get(opts, :model),
        provider: Keyword.get(opts, :provider)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        nil ->
          # Use fast UUID generation to avoid crypto cold start
          node_hash = :erlang.phash2(node(), 65_536)
          timestamp = System.unique_integer([:positive])
          random = :erlang.unique_integer([:positive])
          "prog-#{node_hash}-#{timestamp}-#{random}"

        existing_id ->
          existing_id
      end

    execution_opts =
      Keyword.drop(opts, [:timeout, :temperature, :max_tokens, :model, :provider, :correlation_id])

    {timeout, model_config, correlation_id, execution_opts}
  end

  # Enhanced execution function that handles model configuration and variable resolution
  defp execute_with_model_config(
         program,
         inputs,
         model_config,
         resolved_variables,
         execution_opts
       ) do
    # Merge model configuration and resolved variables into execution options
    enhanced_opts =
      case program do
        # For programs that support model configuration directly
        %{client: _} when map_size(model_config) > 0 ->
          model_config_list = Map.to_list(model_config)
          base_opts = Keyword.merge(execution_opts, model_config_list)

          # Add resolved variables
          if Enum.empty?(resolved_variables) do
            base_opts
          else
            Keyword.put(base_opts, :variables, resolved_variables)
          end

        # For other programs, pass as execution context
        _ when map_size(model_config) > 0 ->
          base_opts = Keyword.put(execution_opts, :model_config, model_config)

          # Add resolved variables
          if Enum.empty?(resolved_variables) do
            base_opts
          else
            Keyword.put(base_opts, :variables, resolved_variables)
          end

        # No model config but may have variables
        _ ->
          if Enum.empty?(resolved_variables) do
            execution_opts
          else
            Keyword.put(execution_opts, :variables, resolved_variables)
          end
      end

    # Execute the program with enhanced options
    if function_exported?(program.__struct__, :forward, 3) do
      program.__struct__.forward(program, inputs, enhanced_opts)
    else
      program.__struct__.forward(program, inputs)
    end
  end

  @doc """
  Macro for implementing program behavior with automatic telemetry setup.

  This macro adds the behavior, provides default implementations, and sets up
  the necessary infrastructure for telemetry and correlation tracking.

  ## Options

  - `:telemetry_prefix` - Custom telemetry event prefix (default: program module name)

  """
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour DSPEx.Program

      # Initialize variables storage
      Module.register_attribute(__MODULE__, :variables, accumulate: false)
      @variables %{}

      # Import variable declaration macro
      import DSPEx.Program, only: [variable: 2, variable: 3]

      @impl DSPEx.Program
      def forward(program, inputs, opts \\ []) do
        {:error, {:not_implemented, "#{__MODULE__} must implement forward/2 or forward/3"}}
      end

      # Compile-time hook to expose declared variables
      @before_compile DSPEx.Program

      defoverridable forward: 3
    end
  end

  # Compile-time hook to generate __variables__ function
  defmacro __before_compile__(_env) do
    quote do
      def __variables__, do: @variables
    end
  end

  @doc """
  Get a human-readable name for a program.

  Extracts the module name and converts it to a readable format for telemetry
  and logging purposes.

  """
  @spec program_name(program()) :: atom()
  def program_name(program) when is_struct(program) do
    program.__struct__
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  def program_name(_), do: :unknown

  @doc """
  Check if a module implements the DSPEx.Program behavior.

  Useful for validation and introspection.

  """
  @spec implements_program?(module()) :: boolean()
  def implements_program?(module) when is_atom(module) do
    module.module_info(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(DSPEx.Program)
  rescue
    UndefinedFunctionError -> false
  end

  def implements_program?(_), do: false

  @doc """
  Create a program struct with validation.

  Helper function for creating program structs with automatic validation
  of required fields and behavior implementation.

  """
  @spec new(module(), map()) :: {:ok, program()} | {:error, term()}
  def new(module, fields) when is_atom(module) and is_map(fields) do
    if implements_program?(module) do
      try do
        program = struct(module, fields)
        {:ok, program}
      rescue
        error -> {:error, {:struct_creation_failed, error}}
      end
    else
      {:error, {:invalid_program_module, module}}
    end
  end

  def new(nil, _), do: {:error, {:invalid_program_module, nil}}
  def new(_, _), do: {:error, :invalid_arguments}

  @doc """
  Determine the type of a program.

  Returns the general category of the program based on its struct type.
  Useful for optimization and introspection workflows.

  ## Returns

  - `:predict` - For DSPEx.Predict programs
  - `:predict_structured` - For DSPEx.PredictStructured programs
  - `:optimized` - For DSPEx.OptimizedProgram programs
  - `:custom` - For other program types

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> DSPEx.Program.program_type(predict)
      :predict

      iex> optimized = %DSPEx.OptimizedProgram{program: predict, demos: []}
      iex> DSPEx.Program.program_type(optimized)
      :optimized

  """
  @spec program_type(t()) :: :predict | :predict_structured | :optimized | :custom
  def program_type(program) when is_struct(program) do
    case program.__struct__ |> Module.split() |> List.last() do
      "Predict" -> :predict
      "PredictStructured" -> :predict_structured
      "OptimizedProgram" -> :optimized
      _ -> :custom
    end
  end

  def program_type(_), do: :custom

  @doc """
  Check if a program has demonstration examples.

  Returns true if the program contains demonstration examples that can
  be used for few-shot learning or optimization.

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai, demos: []}
      iex> DSPEx.Program.has_demos?(predict)
      false

      iex> predict_with_demos = %DSPEx.Predict{signature: MySignature, client: :openai, demos: [%{}]}
      iex> DSPEx.Program.has_demos?(predict_with_demos)
      true

  """
  @spec has_demos?(t()) :: boolean()
  def has_demos?(program) when is_struct(program) do
    cond do
      # Check OptimizedProgram wrapper
      Map.has_key?(program, :demos) and is_list(program.demos) ->
        length(program.demos) > 0

      # Check nested program in OptimizedProgram
      Map.has_key?(program, :program) and is_struct(program.program) ->
        has_demos?(program.program)

      true ->
        false
    end
  end

  def has_demos?(_), do: false

  @doc """
  Check if a program supports native instruction field.

  Returns true if the program struct has an instruction field, indicating
  it can store optimization instructions directly.

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> DSPEx.Program.supports_native_instruction?(predict)
      false  # Predict doesn't have instruction field

  """
  @spec supports_native_instruction?(t()) :: boolean()
  def supports_native_instruction?(program) when is_struct(program) do
    Map.has_key?(program, :instruction)
  end

  def supports_native_instruction?(_), do: false

  @doc """
  Check if a program supports native demo storage.

  Returns true if the program struct has a demos field, indicating
  it can store demonstrations directly.

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai, demos: []}
      iex> DSPEx.Program.supports_native_demos?(predict)
      true

  """
  @spec supports_native_demos?(t()) :: boolean()
  def supports_native_demos?(program) when is_struct(program) do
    Map.has_key?(program, :demos)
  end

  def supports_native_demos?(_), do: false

  @doc """
  Get sanitized information about a program.

  Returns a map with safe information about the program that doesn't
  expose sensitive data like API keys or internal prompts.

  ## Parameters

  - `program` - The program struct to introspect

  ## Returns

  Map with keys:
  - `:type` - Program type (see `program_type/1`)
  - `:has_demos` - Whether the program has demonstration examples
  - `:name` - Human-readable program name
  - `:signature` - Signature module name (if available)
  - `:demo_count` - Number of demonstrations (if applicable)
  - `:supports_native_demos` - Whether program can store demos natively
  - `:supports_native_instruction` - Whether program can store instructions natively

  """
  @spec safe_program_info(t()) :: %{
          type: atom(),
          has_demos: boolean(),
          name: String.t(),
          signature: atom() | nil,
          demo_count: integer(),
          supports_native_demos: boolean(),
          supports_native_instruction: boolean()
        }
  def safe_program_info(program) when is_struct(program) do
    type = program_type(program)
    demo_count = demo_count(program)

    %{
      type: type,
      has_demos: has_demos?(program),
      name: program_name(program) |> Atom.to_string(),
      signature: get_signature_module(program),
      demo_count: demo_count,
      supports_native_demos: supports_native_demos?(program),
      supports_native_instruction: supports_native_instruction?(program)
    }
  end

  def safe_program_info(_) do
    %{
      type: :unknown,
      has_demos: false,
      name: "unknown",
      signature: nil,
      demo_count: 0,
      supports_native_demos: false,
      supports_native_instruction: false
    }
  end

  @doc """
  Determine SIMBA enhancement strategy for a program.

  Returns the optimal strategy for enhancing a program with SIMBA optimizations:
  - `:native_full` - Program supports both demos and instructions natively
  - `:native_demos` - Program supports demos but not instructions natively
  - `:wrap_optimized` - Program needs OptimizedProgram wrapper for enhancements

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> DSPEx.Program.simba_enhancement_strategy(predict)
      :native_demos  # Has demos field but no instruction field

  """
  @spec simba_enhancement_strategy(t()) :: :native_full | :native_demos | :wrap_optimized
  def simba_enhancement_strategy(program) when is_struct(program) do
    cond do
      supports_native_demos?(program) and supports_native_instruction?(program) ->
        :native_full

      supports_native_demos?(program) ->
        :native_demos

      true ->
        :wrap_optimized
    end
  end

  def simba_enhancement_strategy(_), do: :wrap_optimized

  @doc """
  Check if a program can be executed concurrently.

  Analyzes the program structure to determine if it's safe for concurrent execution.
  This is critical for SIMBA's trajectory sampling which uses heavy concurrency.

  """
  @spec concurrent_safe?(t()) :: boolean()
  def concurrent_safe?(program) when is_struct(program) do
    # Most DSPEx programs are concurrent-safe by design (immutable)
    # But we check for obvious issues
    case program do
      # Programs with mutable state indicators
      %{state: _} -> false
      %{cache: _} when not is_map(program.cache) -> false
      # Most standard programs are safe
      _ -> true
    end
  end

  def concurrent_safe?(_), do: false

  @doc """
  Enables schema validation for a program.

  Adds schema validation capabilities to the program, allowing ML-specific
  type validation during execution using the ElixirML Schema Engine.

  ## Parameters
  - `program` - The program struct to enhance

  ## Returns
  - Updated program with schema validation enabled

  ## Examples

      program = DSPEx.Program.enable_schema_validation(program)
      assert DSPEx.Program.schema_validation_enabled?(program)

  """
  @spec enable_schema_validation(t()) :: t()
  def enable_schema_validation(program) when is_struct(program) do
    # Add schema validation flag to program metadata
    current_metadata = Map.get(program, :metadata, %{})
    updated_metadata = Map.put(current_metadata, :schema_validation_enabled, true)

    Map.put(program, :metadata, updated_metadata)
  end

  @doc """
  Checks if schema validation is enabled for a program.

  Returns true if the program has schema validation enabled, allowing
  ML-specific type validation during execution.

  ## Parameters
  - `program` - The program struct to check

  ## Returns
  - Boolean indicating if schema validation is enabled

  ## Examples

      if DSPEx.Program.schema_validation_enabled?(program) do
        # Use enhanced validation
      else
        # Use basic validation
      end

  """
  @spec schema_validation_enabled?(t()) :: boolean()
  def schema_validation_enabled?(program) when is_struct(program) do
    program
    |> Map.get(:metadata, %{})
    |> Map.get(:schema_validation_enabled, false)
  end

  def schema_validation_enabled?(_), do: false

  # Private helper functions

  defp demo_count(program) when is_struct(program) do
    cond do
      # Direct demos field
      Map.has_key?(program, :demos) and is_list(program.demos) ->
        length(program.demos)

      # Nested program in OptimizedProgram
      Map.has_key?(program, :program) and is_struct(program.program) ->
        demo_count(program.program)

      true ->
        0
    end
  end

  defp get_signature_module(program) when is_struct(program) do
    cond do
      # Direct signature field
      Map.has_key?(program, :signature) and is_atom(program.signature) ->
        program.signature

      # Nested program in OptimizedProgram
      Map.has_key?(program, :program) and is_struct(program.program) ->
        get_signature_module(program.program)

      true ->
        nil
    end
  end

  # Private helper functions for Variable System integration

  defp get_variable_config(opts) when is_list(opts) do
    Keyword.get(opts, :variables, %{})
  end

  defp get_variable_config(opts) when is_map(opts) do
    Map.get(opts, :variables, %{})
  end

  defp get_variable_config(_), do: %{}

  defp resolve_with_space(variable_space, variable_config) do
    case ElixirML.Variable.Space.validate_configuration(variable_space, variable_config) do
      {:ok, validated_config} ->
        validated_config

      {:error, _reason} ->
        # Fall back to defaults if validation fails
        variable_space.variables
        |> Enum.map(fn {name, variable} -> {name, variable.default} end)
        |> Enum.into(%{})
    end
  rescue
    # Graceful degradation if ElixirML modules are not available
    _ -> %{}
  end
end
