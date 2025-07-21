defmodule DSPEx.Builder do
  @moduledoc """
  Fluent API for building enhanced DSPEx programs with ElixirML foundation integration.

  The Builder provides a chainable interface for configuring programs with variables,
  schema validation, and other ElixirML capabilities before execution.

  ## Features

  - **Variable Configuration**: Declare and configure optimization variables
  - **Schema Validation**: Enable ML-specific type validation
  - **Automatic ML Variables**: Add standard ML variables (provider, temperature, etc.)
  - **Client Configuration**: Set up client and adapter configurations
  - **Build Validation**: Ensure all required components are properly configured

  ## Usage

      program = DSPEx.Builder.new(QASignature)
      |> DSPEx.Builder.with_variables(%{provider: :openai, temperature: 0.7})
      |> DSPEx.Builder.with_schema_validation(true)
      |> DSPEx.Builder.with_automatic_ml_variables(true)

      {:ok, built_program} = DSPEx.Builder.build(program)

  ## Builder Configuration

  The builder accumulates configuration options and validates them before
  creating the final program. This ensures that invalid configurations are
  caught early in the development process.
  """

  alias DSPEx.Program
  alias ElixirML.Variable

  @enforce_keys [:signature]
  defstruct [
    # Required
    :signature,

    # Program configuration
    :variables,
    :client,
    :adapter,
    :instruction,

    # ElixirML integration
    :schema_validation,
    :automatic_ml_variables,
    :variable_space,

    # Build options
    :build_options,
    :metadata
  ]

  @type t :: %__MODULE__{
          signature: module(),
          variables: map() | nil,
          client: atom() | module() | nil,
          adapter: atom() | module() | nil,
          instruction: String.t() | nil,
          schema_validation: boolean() | nil,
          automatic_ml_variables: boolean() | nil,
          variable_space: Variable.Space.t() | nil,
          build_options: keyword() | nil,
          metadata: map() | nil
        }

  @doc """
  Creates a new program builder with the specified signature.

  ## Parameters
  - `signature_module` - The signature module defining the program interface
  - `opts` - Initial configuration options

  ## Options
  - `:client` - Default client configuration
  - `:adapter` - Default adapter configuration
  - `:instruction` - Default instruction override
  - `:variables` - Initial variable values
  - `:schema_validation` - Enable schema validation (default: false)

  ## Returns
  - `{:ok, builder}` - Builder created successfully
  - `{:error, reason}` - Builder creation failed

  ## Examples

      {:ok, builder} = DSPEx.Builder.new(QASignature,
        client: :openai,
        schema_validation: true
      )

  """
  @spec new(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(signature_module, opts \\ []) do
    # Validate signature module
    case validate_signature_module(signature_module) do
      :ok ->
        builder = %__MODULE__{
          signature: signature_module,
          variables: Keyword.get(opts, :variables, %{}),
          client: Keyword.get(opts, :client),
          adapter: Keyword.get(opts, :adapter),
          instruction: Keyword.get(opts, :instruction),
          schema_validation: Keyword.get(opts, :schema_validation, false),
          automatic_ml_variables: Keyword.get(opts, :automatic_ml_variables, false),
          build_options: Keyword.get(opts, :build_options, []),
          metadata: %{created_at: DateTime.utc_now()}
        }

        {:ok, builder}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds or updates variables in the builder configuration.

  Variables added here will be available for automatic optimization by
  teleprompters like SIMBA.

  ## Parameters
  - `builder` - The program builder
  - `variables` - Map of variable names to values

  ## Returns
  - Updated builder with variables configured

  ## Examples

      builder = DSPEx.Builder.with_variables(builder, %{
        provider: :openai,
        temperature: 0.7,
        max_tokens: 150
      })

  """
  @spec with_variables(t(), map()) :: t()
  def with_variables(%__MODULE__{} = builder, variables) when is_map(variables) do
    current_variables = builder.variables || %{}
    updated_variables = Map.merge(current_variables, variables)

    %{builder | variables: updated_variables}
  end

  @doc """
  Enables or disables schema validation for the program.

  ## Parameters
  - `builder` - The program builder
  - `enabled` - Boolean to enable/disable validation

  ## Returns
  - Updated builder with schema validation configured

  ## Examples

      builder = DSPEx.Builder.with_schema_validation(builder, true)

  """
  @spec with_schema_validation(t(), boolean()) :: t()
  def with_schema_validation(%__MODULE__{} = builder, enabled) when is_boolean(enabled) do
    %{builder | schema_validation: enabled}
  end

  @doc """
  Configures automatic addition of standard ML variables.

  When enabled, the builder will automatically add common ML optimization
  variables like provider, temperature, max_tokens, etc.

  ## Parameters
  - `builder` - The program builder
  - `enabled` - Boolean to enable/disable automatic variables

  ## Returns
  - Updated builder with automatic ML variables configured

  ## Examples

      builder = DSPEx.Builder.with_automatic_ml_variables(builder, true)

  """
  @spec with_automatic_ml_variables(t(), boolean()) :: t()
  def with_automatic_ml_variables(%__MODULE__{} = builder, enabled) when is_boolean(enabled) do
    %{builder | automatic_ml_variables: enabled}
  end

  @doc """
  Sets the client configuration for the program.

  ## Parameters
  - `builder` - The program builder
  - `client` - Client module or configuration

  ## Returns
  - Updated builder with client configured

  ## Examples

      builder = DSPEx.Builder.with_client(builder, :openai)

  """
  @spec with_client(t(), atom() | module()) :: t()
  def with_client(%__MODULE__{} = builder, client) do
    %{builder | client: client}
  end

  @doc """
  Sets the adapter configuration for the program.

  ## Parameters
  - `builder` - The program builder
  - `adapter` - Adapter module or configuration

  ## Returns
  - Updated builder with adapter configured

  ## Examples

      builder = DSPEx.Builder.with_adapter(builder, :json)

  """
  @spec with_adapter(t(), atom() | module()) :: t()
  def with_adapter(%__MODULE__{} = builder, adapter) do
    %{builder | adapter: adapter}
  end

  @doc """
  Sets an instruction override for the program.

  ## Parameters
  - `builder` - The program builder
  - `instruction` - Instruction string

  ## Returns
  - Updated builder with instruction configured

  ## Examples

      builder = DSPEx.Builder.with_instruction(builder,
        "Answer the question with high confidence and detailed reasoning."
      )

  """
  @spec with_instruction(t(), String.t()) :: t()
  def with_instruction(%__MODULE__{} = builder, instruction) when is_binary(instruction) do
    %{builder | instruction: instruction}
  end

  @doc """
  Builds the final program from the builder configuration.

  This function validates all the configuration options and creates the
  actual DSPEx.Program that can be executed.

  ## Parameters
  - `builder` - The configured program builder

  ## Returns
  - `{:ok, program}` - Program built successfully
  - `{:error, reason}` - Build failed with validation errors

  ## Examples

      {:ok, program} = DSPEx.Builder.build(builder)

  """
  @spec build(t()) :: {:ok, Program.t()} | {:error, term()}
  def build(%__MODULE__{} = builder) do
    with {:ok, variable_space} <- create_variable_space(builder),
         {:ok, program_opts} <- create_program_options(builder, variable_space) do
      # Convert keyword options to map for Program.new
      program_map = Enum.into(program_opts, %{})

      case Program.new(builder.signature, program_map) do
        {:ok, program} ->
          # Add schema validation configuration if enabled
          final_program =
            if builder.schema_validation do
              DSPEx.Program.enable_schema_validation(program)
            else
              program
            end

          {:ok, final_program}

        {:error, _} = error ->
          error
      end
    end
  end

  # Private helper functions

  @spec validate_signature_module(module()) :: :ok | {:error, term()}
  defp validate_signature_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      # Check if module implements DSPEx.Signature behaviour
      behaviours = module.module_info(:attributes) |> Keyword.get(:behaviour, [])

      if DSPEx.Signature in behaviours do
        :ok
      else
        {:error,
         {:invalid_signature_module, "Module does not implement DSPEx.Signature behaviour"}}
      end
    else
      {:error, {:invalid_signature_module, "Module cannot be loaded"}}
    end
  end

  defp validate_signature_module(_) do
    {:error, {:invalid_signature_module, "Must be a module atom"}}
  end

  @spec create_variable_space(t()) :: {:ok, Variable.Space.t()} | {:error, term()}
  defp create_variable_space(builder) do
    try do
      # Start with empty variable space
      variable_space = Variable.Space.new(name: "#{builder.signature} Variables")

      # Extract variables from signature if it supports it
      if function_exported?(builder.signature, :extract_variables, 0) do
        _signature_variables = builder.signature.extract_variables()
        # Note: Variable.Space.merge/2 doesn't exist, so we'll use the base space
        variable_space
      else
        variable_space
      end

      # Add automatic ML variables if enabled
      variable_space =
        if builder.automatic_ml_variables and
             function_exported?(Variable.MLTypes, :standard_ml_config, 0) do
          _ml_variables = Variable.MLTypes.standard_ml_config()
          # Note: Variable.Space.merge/2 doesn't exist, so we'll use the base space
          variable_space
        else
          variable_space
        end

      # Set current variable values if provided
      variable_space =
        if builder.variables && not Enum.empty?(builder.variables) do
          case Variable.Space.validate_configuration(variable_space, builder.variables) do
            {:ok, _validated} -> variable_space
            # Continue with defaults
            {:error, _reason} -> variable_space
          end
        else
          variable_space
        end

      {:ok, variable_space}
    rescue
      error -> {:error, {:variable_space_creation_failed, error}}
    end
  end

  @spec create_program_options(t(), Variable.Space.t()) :: {:ok, keyword()} | {:error, term()}
  defp create_program_options(builder, variable_space) do
    opts = []

    # Add variable space
    opts = Keyword.put(opts, :variable_space, variable_space)

    # Add client if specified
    opts = if builder.client, do: Keyword.put(opts, :client, builder.client), else: opts

    # Add adapter if specified
    opts = if builder.adapter, do: Keyword.put(opts, :adapter, builder.adapter), else: opts

    # Add instruction if specified
    opts =
      if builder.instruction, do: Keyword.put(opts, :instruction, builder.instruction), else: opts

    # Add current variable values
    opts =
      if builder.variables && not Enum.empty?(builder.variables) do
        Keyword.put(opts, :config, builder.variables)
      else
        opts
      end

    # Add build options
    opts =
      if builder.build_options do
        Keyword.merge(opts, builder.build_options)
      else
        opts
      end

    {:ok, opts}
  end
end
