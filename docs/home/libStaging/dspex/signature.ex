defmodule DSPEx.Signature do
  @moduledoc """
  Defines the `@behaviour` and `use` macro for creating DSPEx Signatures.

  A signature declaratively defines the inputs and outputs of a DSPEx program.
  Using this macro at compile-time generates an efficient struct and the necessary
  functions to interact with the framework.

  ## Example

      defmodule QASignature do
        @moduledoc "Answer questions with detailed reasoning"
        use DSPEx.Signature, "question -> answer"
      end

  This generates a module that implements the DSPEx.Signature behaviour and provides:
  - A struct with the specified fields
  - Functions to access input/output field lists
  - Validation functions for inputs and outputs
  - Instructions extracted from the module's @moduledoc

  ## Behaviour Callbacks

  - `instructions/0` - Returns the instruction string for this signature
  - `input_fields/0` - Returns list of input field names as atoms
  - `output_fields/0` - Returns list of output field names as atoms
  - `fields/0` - Returns all fields as a combined list

  ## Generated Functions

  When using this module, the following functions are automatically generated:
  - `new/1` - Creates a new struct instance
  - `validate_inputs/1` - Validates input field completeness
  - `validate_outputs/1` - Validates output field completeness

  See the type specification `t()` for the generated struct type.
  """

  @typedoc "Validation result for input/output field checking"
  @type validation_result :: :ok | {:error, {:missing_inputs | :missing_outputs, [atom()]}}

  @doc "Returns the instruction string for this signature"
  @callback instructions() :: String.t()

  @doc "Returns list of input field names as atoms"
  @callback input_fields() :: [atom()]

  @doc "Returns list of output field names as atoms"
  @callback output_fields() :: [atom()]

  @doc "Returns all fields as a combined list"
  @callback fields() :: [atom()]

  @doc """
  Extends a signature with additional fields, creating a new signature module.

  This is primarily used for ChainOfThought patterns where base signatures
  need additional reasoning fields.

  ## Parameters
  - `base_signature` - The module implementing DSPEx.Signature to extend
  - `additional_fields` - Map of field names to types/descriptions

  ## Returns
  - `{:ok, module()}` - New signature module with extended fields
  - `{:error, term()}` - Error if extension fails

  ## Examples

      {:ok, extended} = DSPEx.Signature.extend(
        QASignature,
        %{reasoning: :text, confidence: :float}
      )

      # Can now use extended signature with reasoning field
      result = extended.new(%{question: "What is 2+2?", reasoning: "Basic math", answer: "4"})
  """
  # Module aliases for nested modules
  alias DSPEx.Signature.{EnhancedParser, Parser}

  @spec extend(module(), map()) :: {:ok, module()} | {:error, term()}
  def extend(base_signature, additional_fields)
      when is_atom(base_signature) and is_map(additional_fields) do
    # Validate base signature implements behavior
    unless Code.ensure_loaded?(base_signature) and
             function_exported?(base_signature, :input_fields, 0) and
             function_exported?(base_signature, :output_fields, 0) and
             function_exported?(base_signature, :instructions, 0) do
      raise ArgumentError, "Base module must implement DSPEx.Signature behavior"
    end

    # Get existing fields from base signature
    base_inputs = base_signature.input_fields()
    base_outputs = base_signature.output_fields()
    base_instructions = base_signature.instructions()

    # Process additional fields
    {new_inputs, new_outputs} =
      categorize_additional_fields(additional_fields, base_inputs, base_outputs)

    # Create extended field lists
    extended_inputs = base_inputs ++ new_inputs
    extended_outputs = base_outputs ++ new_outputs
    all_extended_fields = extended_inputs ++ extended_outputs

    # Generate unique module name based on base signature and extension
    module_name = generate_extended_module_name(base_signature, additional_fields)

    # Create new signature string for the extended signature
    _extended_signature_string = create_signature_string(extended_inputs, extended_outputs)

    # Create the extended module definition
    module_definition =
      create_extended_module(
        module_name,
        base_instructions,
        extended_inputs,
        extended_outputs,
        all_extended_fields
      )

    # Check if module already exists and purge it if necessary
    if Code.ensure_loaded?(module_name) do
      :code.purge(module_name)
      :code.delete(module_name)
    end

    # Compile and load the new module
    {_result, _binding} = Code.eval_quoted(module_definition)

    {:ok, module_name}
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Gets information about a specific field in a signature.

  ## Parameters
  - `signature` - The signature module
  - `field` - The field name as an atom

  ## Returns
  - `{:ok, map()}` - Field information including type and category
  - `{:error, :field_not_found}` - If field doesn't exist
  """
  @spec get_field_info(module(), atom()) :: {:ok, map()} | {:error, :field_not_found}
  def get_field_info(signature, field) when is_atom(signature) and is_atom(field) do
    cond do
      field in signature.input_fields() ->
        {:ok, %{name: field, type: :input, category: :input}}

      field in signature.output_fields() ->
        {:ok, %{name: field, type: :output, category: :output}}

      true ->
        {:error, :field_not_found}
    end
  end

  # Private helper functions for signature extension

  @spec categorize_additional_fields(map(), [atom()], [atom()]) :: {[atom()], [atom()]}
  defp categorize_additional_fields(additional_fields, base_inputs, base_outputs) do
    # For now, assume all additional fields are outputs unless specified
    # This is the most common case for ChainOfThought (adding reasoning fields)
    new_field_names = Map.keys(additional_fields)

    # Check for conflicts with existing fields
    existing_fields = base_inputs ++ base_outputs
    conflicts = Enum.filter(new_field_names, &(&1 in existing_fields))

    if not Enum.empty?(conflicts) do
      raise ArgumentError, "Field name conflicts: #{inspect(conflicts)}"
    end

    # For simplicity, add all new fields as outputs
    # Future enhancement could allow specifying input vs output
    {[], new_field_names}
  end

  @spec generate_extended_module_name(module(), map()) :: atom()
  defp generate_extended_module_name(base_signature, additional_fields) do
    # Use full module name instead of just the last part to avoid conflicts
    full_base_name = base_signature |> Module.split() |> Enum.join(".")
    field_hash = additional_fields |> inspect() |> :erlang.phash2() |> Integer.to_string()
    # Add timestamp and random component to ensure uniqueness across test runs
    timestamp = System.system_time(:microsecond) |> Integer.to_string()
    random_suffix = :rand.uniform(999_999) |> Integer.to_string()

    :"#{full_base_name}.Extended.#{field_hash}.#{timestamp}.#{random_suffix}"
  end

  @spec create_signature_string([atom()], [atom()]) :: String.t()
  defp create_signature_string(inputs, outputs) do
    inputs_str = Enum.map_join(inputs, ", ", &Atom.to_string/1)
    outputs_str = Enum.map_join(outputs, ", ", &Atom.to_string/1)

    "#{inputs_str} -> #{outputs_str}"
  end

  @spec create_extended_module(atom(), String.t(), [atom()], [atom()], [atom()]) :: Macro.t()
  defp create_extended_module(module_name, base_instructions, inputs, outputs, all_fields) do
    quote do
      defmodule unquote(module_name) do
        @behaviour DSPEx.Signature

        unquote(create_struct_definition(all_fields))
        unquote(create_type_specification(all_fields))
        unquote(create_module_attributes(base_instructions, inputs, outputs, all_fields))
        unquote(create_behavior_implementations())
        unquote(create_helper_functions())
      end
    end
  end

  defp create_struct_definition(all_fields) do
    quote do
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))
    end
  end

  defp create_type_specification(all_fields) do
    quote do
      @type t :: %__MODULE__{
              unquote_splicing(
                all_fields
                |> Enum.map(fn field ->
                  {field, quote(do: any())}
                end)
              )
            }
    end
  end

  defp create_module_attributes(base_instructions, inputs, outputs, all_fields) do
    quote do
      @instructions unquote(base_instructions)
      @input_fields unquote(inputs)
      @output_fields unquote(outputs)
      @all_fields unquote(all_fields)
    end
  end

  defp create_behavior_implementations do
    quote do
      @impl DSPEx.Signature
      def instructions, do: @instructions

      @impl DSPEx.Signature
      def input_fields, do: @input_fields

      @impl DSPEx.Signature
      def output_fields, do: @output_fields

      @impl DSPEx.Signature
      def fields, do: @all_fields
    end
  end

  defp create_helper_functions do
    quote do
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end

      def validate_inputs(inputs) when is_map(inputs) do
        unquote(__MODULE__).validate_field_set(@input_fields, inputs, :missing_inputs)
      end

      def validate_outputs(outputs) when is_map(outputs) do
        unquote(__MODULE__).validate_field_set(@output_fields, outputs, :missing_outputs)
      end
    end
  end

  def validate_field_set(required_fields, provided_map, error_type) do
    required = MapSet.new(required_fields)
    provided = MapSet.new(Map.keys(provided_map))
    missing = MapSet.difference(required, provided)

    if MapSet.size(missing) == 0 do
      :ok
    else
      {:error, {error_type, MapSet.to_list(missing)}}
    end
  end

  @doc """
  Defines a DSPEx signature with the given signature string.

  The signature string follows the format: "input1, input2 -> output1, output2"

  ## Parameters
  - `signature_string` - A binary string defining the input/output signature

  ## Generated Module Features
  - Implements the DSPEx.Signature behaviour
  - Creates a struct with all specified fields
  - Generates validation and accessor functions
  - Extracts documentation from the module's @moduledoc

  ## Examples

      defmodule MySignature do
        use DSPEx.Signature, "question, context -> answer, confidence"
      end

      %MySignature{question: "test", context: "info", answer: "result", confidence: 0.9}
  """
  @spec __using__(binary()) :: Macro.t()
  defmacro __using__(signature_string) when is_binary(signature_string) do
    # Check if this is an enhanced signature
    is_enhanced = DSPEx.Signature.EnhancedParser.enhanced_signature?(signature_string)

    if is_enhanced do
      generate_enhanced_signature(signature_string)
    else
      generate_basic_signature(signature_string)
    end
  end

  @spec __using__(atom()) :: Macro.t()
  defmacro __using__(:schema_dsl) do
    generate_schema_dsl_signature()
  end

  @doc """
  Defines an input field with optional ML-specific type and constraints.

  ## Parameters
  - `name` - Field name as atom
  - `type` - Field type (supports ElixirML types like :embedding, :confidence_score)
  - `opts` - Additional constraints and options

  ## Examples
      input :question, :string
      input :context, :embedding, dimensions: 1536
      input :threshold, :probability, default: 0.8
  """
  defmacro input(name, type \\ :string, opts \\ []) do
    quote do
      @schema_input_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Defines an output field with optional ML-specific type and constraints.

  ## Parameters
  - `name` - Field name as atom
  - `type` - Field type (supports ElixirML types like :confidence_score, :model_response)
  - `opts` - Additional constraints and options

  ## Examples
      output :answer, :string
      output :confidence, :confidence_score
      output :reasoning, :reasoning_chain
  """
  defmacro output(name, type \\ :string, opts \\ []) do
    quote do
      @schema_output_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  # Generate schema DSL-based signature
  @spec generate_schema_dsl_signature() :: Macro.t()
  defp generate_schema_dsl_signature do
    quote do
      # Initialize field accumulators
      Module.register_attribute(__MODULE__, :schema_input_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :schema_output_fields, accumulate: true)

      # Import DSL macros
      import DSPEx.Signature, only: [input: 2, input: 3, output: 2, output: 3]

      # Add schema integration
      alias ElixirML.{Schema, Variable}

      @before_compile DSPEx.Signature
    end
  end

  # Compile-time callback to generate signature struct and methods
  defmacro __before_compile__(env) do
    # Get field definitions at compile time
    input_field_defs =
      Module.get_attribute(env.module, :schema_input_fields, []) |> Enum.reverse()

    output_field_defs =
      Module.get_attribute(env.module, :schema_output_fields, []) |> Enum.reverse()

    # Extract field names for compatibility
    input_field_names = Enum.map(input_field_defs, fn {name, _type, _opts} -> name end)
    output_field_names = Enum.map(output_field_defs, fn {name, _type, _opts} -> name end)
    all_field_names = input_field_names ++ output_field_names

    # Generate enhanced field definitions for schema integration
    enhanced_input_fields =
      Enum.map(input_field_defs, fn {name, type, opts} ->
        %{
          name: name,
          type: type,
          constraints: Map.new(opts),
          required: Keyword.get(opts, :required, true),
          default: Keyword.get(opts, :default, nil)
        }
      end)

    enhanced_output_fields =
      Enum.map(output_field_defs, fn {name, type, opts} ->
        %{
          name: name,
          type: type,
          constraints: Map.new(opts),
          required: Keyword.get(opts, :required, true),
          default: Keyword.get(opts, :default, nil)
        }
      end)

    all_enhanced_fields = enhanced_input_fields ++ enhanced_output_fields

    # Generate the signature struct and methods
    generate_signature_struct_with_schema(
      input_field_names,
      output_field_names,
      all_field_names,
      all_enhanced_fields
    )
  end

  # Generate enhanced signature with Sinter support
  @spec generate_enhanced_signature(binary()) :: Macro.t()
  defp generate_enhanced_signature(signature_string) do
    # Parse with enhanced parser
    {enhanced_input_fields, enhanced_output_fields} =
      EnhancedParser.parse(signature_string)

    # Convert to simple format for compatibility
    {input_fields, output_fields} =
      EnhancedParser.to_simple_signature({enhanced_input_fields, enhanced_output_fields})

    all_fields = input_fields ++ output_fields
    all_enhanced_fields = enhanced_input_fields ++ enhanced_output_fields

    generate_signature_struct(input_fields, output_fields, all_fields, all_enhanced_fields)
  end

  # Generate basic signature for backward compatibility
  @spec generate_basic_signature(binary()) :: Macro.t()
  defp generate_basic_signature(signature_string) do
    # Parse with basic parser for backward compatibility
    {input_fields, output_fields} = Parser.parse(signature_string)
    all_fields = input_fields ++ output_fields

    generate_signature_struct(input_fields, output_fields, all_fields, nil)
  end

  # Generate signature struct with schema integration
  @spec generate_signature_struct_with_schema(list(atom()), list(atom()), list(atom()), list()) ::
          Macro.t()
  defp generate_signature_struct_with_schema(
         input_fields,
         output_fields,
         all_fields,
         enhanced_fields
       ) do
    quote do
      @behaviour DSPEx.Signature

      # Create struct with all fields, defaulting to nil
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))

      # Define comprehensive type specification
      @type t :: %__MODULE__{
              unquote_splicing(
                all_fields
                |> Enum.map(fn field ->
                  {field, quote(do: any())}
                end)
              )
            }

      # Extract instructions from module doc at compile time
      @instructions @moduledoc ||
                      "Given the fields #{inspect(unquote(input_fields))}, produce the fields #{inspect(unquote(output_fields))}."

      # Store field lists as module attributes for efficiency
      @input_fields unquote(input_fields)
      @output_fields unquote(output_fields)
      @all_fields unquote(all_fields)

      # Store enhanced field definitions for schema integration
      @enhanced_fields unquote(Macro.escape(enhanced_fields))

      unquote(generate_signature_methods_with_schema())
      unquote(generate_schema_integration_methods())
    end
  end

  # Generate the main signature struct with all methods
  @spec generate_signature_struct(list(atom()), list(atom()), list(atom()), list() | nil) ::
          Macro.t()
  defp generate_signature_struct(input_fields, output_fields, all_fields, enhanced_fields) do
    quote do
      @behaviour DSPEx.Signature

      # Create struct with all fields, defaulting to nil
      defstruct unquote(all_fields |> Enum.map(&{&1, nil}))

      # Define comprehensive type specification
      @type t :: %__MODULE__{
              unquote_splicing(
                all_fields
                |> Enum.map(fn field ->
                  {field, quote(do: any())}
                end)
              )
            }

      # Extract instructions from module doc at compile time
      @instructions @moduledoc ||
                      "Given the fields #{inspect(unquote(input_fields))}, produce the fields #{inspect(unquote(output_fields))}."

      # Store field lists as module attributes for efficiency
      @input_fields unquote(input_fields)
      @output_fields unquote(output_fields)
      @all_fields unquote(all_fields)

      unquote(generate_enhanced_fields_if_present(enhanced_fields))

      unquote(generate_signature_methods())
    end
  end

  # Generate enhanced fields support if present
  @spec generate_enhanced_fields_if_present(list() | nil) :: Macro.t() | nil
  defp generate_enhanced_fields_if_present(nil), do: nil

  defp generate_enhanced_fields_if_present(enhanced_fields) do
    quote do
      # Store enhanced field definitions for Sinter integration
      @enhanced_fields unquote(Macro.escape(enhanced_fields))

      # Provide access to enhanced field definitions
      def __enhanced_fields__, do: @enhanced_fields
    end
  end

  # Generate signature methods with schema validation
  @spec generate_signature_methods_with_schema() :: Macro.t()
  defp generate_signature_methods_with_schema do
    quote do
      # Implement behaviour callbacks with proper specs
      @doc "Returns the instruction string extracted from @moduledoc or auto-generated"
      @spec instructions() :: String.t()
      @impl DSPEx.Signature
      def instructions, do: @instructions

      @doc "Returns the list of input field names as atoms"
      @spec input_fields() :: [atom()]
      @impl DSPEx.Signature
      def input_fields, do: @input_fields

      @doc "Returns the list of output field names as atoms"
      @spec output_fields() :: [atom()]
      @impl DSPEx.Signature
      def output_fields, do: @output_fields

      @doc "Returns all fields (inputs + outputs) as a combined list"
      @spec fields() :: [atom()]
      @impl DSPEx.Signature
      def fields, do: @all_fields

      @doc "Returns enhanced field definitions for schema integration"
      @spec __enhanced_fields__() :: [map()]
      def __enhanced_fields__, do: @enhanced_fields

      @doc """
      Creates a new signature struct instance.

      ## Parameters
      - `fields` - A map of field names to values (optional, defaults to empty map)

      ## Returns
      - A new struct instance with the given field values

      ## Examples

          iex> MySignature.new(%{question: "test"})
          %MySignature{question: "test", answer: nil, ...}
      """
      @spec new(map()) :: t()
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end

      unquote(generate_validation_methods_with_schema())
    end
  end

  # Generate schema integration methods
  @spec generate_schema_integration_methods() :: Macro.t()
  defp generate_schema_integration_methods do
    quote do
      @doc """
      Validates inputs using ElixirML Schema Engine with ML-specific type validation.

      ## Parameters
      - `inputs` - A map containing input field values

      ## Returns
      - `{:ok, validated_inputs}` if validation passes
      - `{:error, validation_errors}` if validation fails
      """
      @spec validate_inputs_with_schema(map()) :: {:ok, map()} | {:error, term()}
      def validate_inputs_with_schema(inputs) when is_map(inputs) do
        DSPEx.Signature.SchemaIntegration.validate_fields(__MODULE__, inputs, :input)
      end

      @doc """
      Validates outputs using ElixirML Schema Engine with ML-specific type validation.

      ## Parameters
      - `outputs` - A map containing output field values

      ## Returns
      - `{:ok, validated_outputs}` if validation passes
      - `{:error, validation_errors}` if validation fails
      """
      @spec validate_outputs_with_schema(map()) :: {:ok, map()} | {:error, term()}
      def validate_outputs_with_schema(outputs) when is_map(outputs) do
        DSPEx.Signature.SchemaIntegration.validate_fields(__MODULE__, outputs, :output)
      end

      @doc """
      Extracts variables from signature field definitions for optimization.

      ## Returns
      - Variable space containing extractable variables from field types and constraints
      """
      @spec extract_variables() :: ElixirML.Variable.Space.t()
      def extract_variables do
        DSPEx.Signature.SchemaIntegration.extract_variables(__MODULE__)
      end
    end
  end

  # Generate validation methods with schema integration
  @spec generate_validation_methods_with_schema() :: Macro.t()
  defp generate_validation_methods_with_schema do
    quote do
      @doc """
      Validates that all required input fields are present and non-nil.

      Uses basic field presence validation for backward compatibility.
      For ML-specific type validation, use validate_inputs_with_schema/1.

      ## Parameters
      - `inputs` - A map containing input field values

      ## Returns
      - `:ok` if all required input fields are present
      - `{:error, {:missing_inputs, [atom()]}}` if any required fields are missing
      """
      @spec validate_inputs(map()) :: DSPEx.Signature.validation_result()
      def validate_inputs(inputs) when is_map(inputs) do
        required_inputs = MapSet.new(@input_fields)
        provided_inputs = MapSet.new(Map.keys(inputs))

        missing = MapSet.difference(required_inputs, provided_inputs)

        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
      end

      @doc """
      Validates that all required output fields are present and non-nil.

      Uses basic field presence validation for backward compatibility.
      For ML-specific type validation, use validate_outputs_with_schema/1.

      ## Parameters
      - `outputs` - A map containing output field values

      ## Returns
      - `:ok` if all required output fields are present
      - `{:error, {:missing_outputs, [atom()]}}` if any required fields are missing
      """
      @spec validate_outputs(map()) :: DSPEx.Signature.validation_result()
      def validate_outputs(outputs) when is_map(outputs) do
        required_outputs = MapSet.new(@output_fields)
        provided_outputs = MapSet.new(Map.keys(outputs))

        missing = MapSet.difference(required_outputs, provided_outputs)

        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_outputs, MapSet.to_list(missing)}}
        end
      end
    end
  end

  # Generate common signature methods
  @spec generate_signature_methods() :: Macro.t()
  defp generate_signature_methods do
    quote do
      # Implement behaviour callbacks with proper specs
      @doc "Returns the instruction string extracted from @moduledoc or auto-generated"
      @spec instructions() :: String.t()
      @impl DSPEx.Signature
      def instructions, do: @instructions

      @doc "Returns the list of input field names as atoms"
      @spec input_fields() :: [atom()]
      @impl DSPEx.Signature
      def input_fields, do: @input_fields

      @doc "Returns the list of output field names as atoms"
      @spec output_fields() :: [atom()]
      @impl DSPEx.Signature
      def output_fields, do: @output_fields

      @doc "Returns all fields (inputs + outputs) as a combined list"
      @spec fields() :: [atom()]
      @impl DSPEx.Signature
      def fields, do: @all_fields

      @doc """
      Creates a new signature struct instance.

      ## Parameters
      - `fields` - A map of field names to values (optional, defaults to empty map)

      ## Returns
      - A new struct instance with the given field values

      ## Examples

          iex> MySignature.new(%{question: "test"})
          %MySignature{question: "test", answer: nil, ...}
      """
      @spec new(map()) :: t()
      def new(fields \\ %{}) when is_map(fields) do
        struct(__MODULE__, fields)
      end

      unquote(generate_validation_methods())
    end
  end

  # Generate input/output validation methods
  @spec generate_validation_methods() :: Macro.t()
  defp generate_validation_methods do
    quote do
      @doc """
      Validates that all required input fields are present and non-nil.

      ## Parameters
      - `inputs` - A map containing input field values

      ## Returns
      - `:ok` if all required input fields are present
      - `{:error, {:missing_inputs, [atom()]}}` if any required fields are missing

      ## Examples

          iex> MySignature.validate_inputs(%{question: "test", context: "info"})
          :ok

          iex> MySignature.validate_inputs(%{question: "test"})
          {:error, {:missing_inputs, [:context]}}
      """
      @spec validate_inputs(map()) :: DSPEx.Signature.validation_result()
      def validate_inputs(inputs) when is_map(inputs) do
        required_inputs = MapSet.new(@input_fields)
        provided_inputs = MapSet.new(Map.keys(inputs))

        missing = MapSet.difference(required_inputs, provided_inputs)

        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_inputs, MapSet.to_list(missing)}}
        end
      end

      @doc """
      Validates that all required output fields are present and non-nil.

      ## Parameters
      - `outputs` - A map containing output field values

      ## Returns
      - `:ok` if all required output fields are present
      - `{:error, {:missing_outputs, [atom()]}}` if any required fields are missing

      ## Examples

          iex> MySignature.validate_outputs(%{answer: "result", confidence: 0.9})
          :ok

          iex> MySignature.validate_outputs(%{answer: "result"})
          {:error, {:missing_outputs, [:confidence]}}
      """
      @spec validate_outputs(map()) :: DSPEx.Signature.validation_result()
      def validate_outputs(outputs) when is_map(outputs) do
        required_outputs = MapSet.new(@output_fields)
        provided_outputs = MapSet.new(Map.keys(outputs))

        missing = MapSet.difference(required_outputs, provided_outputs)

        case MapSet.size(missing) do
          0 -> :ok
          _ -> {:error, {:missing_outputs, MapSet.to_list(missing)}}
        end
      end
    end
  end

  @doc """
  Validates compatibility between two signature modules.

  Checks if the output fields of a producer signature are compatible
  with the input fields of a consumer signature, useful for chaining
  programs together in optimization workflows.

  ## Parameters
  - `producer_sig` - Module that produces outputs
  - `consumer_sig` - Module that consumes inputs

  ## Returns
  - `:ok` - If signatures are compatible
  - `{:error, String.t()}` - Description of incompatibility

  ## Examples

      iex> DSPEx.Signature.validate_signature_compatibility(QASignature, ReasoningSignature)
      :ok

      iex> DSPEx.Signature.validate_signature_compatibility(QASignature, IncompatibleSignature)
      {:error, "Producer outputs [:answer] do not match consumer inputs [:question, :context]"}

  """
  @spec validate_signature_compatibility(module(), module()) :: :ok | {:error, String.t()}
  def validate_signature_compatibility(producer_sig, consumer_sig)
      when is_atom(producer_sig) and is_atom(consumer_sig) do
    # Validate both modules implement the signature behavior
    with :ok <- validate_signature_implementation(producer_sig),
         :ok <- validate_signature_implementation(consumer_sig) do
      producer_outputs = MapSet.new(producer_sig.output_fields())
      consumer_inputs = MapSet.new(consumer_sig.input_fields())

      # Check if producer outputs can satisfy consumer inputs
      missing_inputs = MapSet.difference(consumer_inputs, producer_outputs)

      case MapSet.size(missing_inputs) do
        0 ->
          :ok

        _ ->
          {:error,
           "Producer outputs #{inspect(MapSet.to_list(producer_outputs))} " <>
             "do not match consumer inputs #{inspect(MapSet.to_list(consumer_inputs))}. " <>
             "Missing: #{inspect(MapSet.to_list(missing_inputs))}"}
      end
    end
  rescue
    error -> {:error, "Compatibility check failed: #{inspect(error)}"}
  end

  @doc """
  Introspects a signature module to return detailed information.

  Returns comprehensive information about a signature including its
  fields, types, instructions, and other metadata useful for
  optimization and debugging workflows.

  ## Parameters
  - `signature_module` - The signature module to introspect

  ## Returns
  - `{:ok, map()}` - Detailed signature information
  - `{:error, String.t()}` - Error description

  ## Example Return Value

      {:ok, %{
        module: QASignature,
        instructions: "Answer questions with reasoning",
        inputs: [:question, :context],
        outputs: [:answer, :confidence],
        all_fields: [:question, :context, :answer, :confidence],
        field_count: %{inputs: 2, outputs: 2, total: 4},
        created_at: ~U[2025-06-10 19:37:00Z]
      }}

  """
  @spec introspect(module()) :: {:ok, map()} | {:error, String.t()}
  def introspect(signature_module) when is_atom(signature_module) do
    case validate_signature_implementation(signature_module) do
      :ok ->
        inputs = signature_module.input_fields()
        outputs = signature_module.output_fields()
        all_fields = signature_module.fields()

        introspection_data = %{
          module: signature_module,
          instructions: signature_module.instructions(),
          inputs: inputs,
          outputs: outputs,
          all_fields: all_fields,
          field_count: %{
            inputs: length(inputs),
            outputs: length(outputs),
            total: length(all_fields)
          },
          introspected_at: DateTime.utc_now()
        }

        {:ok, introspection_data}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, "Introspection failed: #{inspect(error)}"}
  end

  @doc """
  Validates that a module properly implements the DSPEx.Signature behavior.

  Checks that the module implements all required callbacks and that
  the implementation is consistent and functional.

  ## Parameters
  - `module` - The module to validate

  ## Returns
  - `:ok` - If implementation is valid
  - `{:error, String.t()}` - Description of validation failure

  ## Examples

      iex> DSPEx.Signature.validate_signature_implementation(QASignature)
      :ok

      iex> DSPEx.Signature.validate_signature_implementation(InvalidModule)
      {:error, "Module does not implement DSPEx.Signature behavior"}

  """
  @spec validate_signature_implementation(module()) :: :ok | {:error, String.t()}
  def validate_signature_implementation(module) when is_atom(module) do
    with :ok <- validate_module_loadable(module),
         :ok <- validate_module_behavior(module),
         :ok <- validate_required_functions(module),
         :ok <- validate_field_lists(module),
         :ok <- validate_instructions(module) do
      :ok
    else
      error -> error
    end
  rescue
    error -> {:error, "Validation failed: #{inspect(error)}"}
  end

  defp validate_module_loadable(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, "Module #{inspect(module)} cannot be loaded"}
    end
  end

  defp validate_module_behavior(module) do
    behaviors = module.module_info(:attributes) |> Keyword.get(:behaviour, [])

    if DSPEx.Signature in behaviors do
      :ok
    else
      {:error, "Module does not implement DSPEx.Signature behavior"}
    end
  end

  defp validate_required_functions(module) do
    required_functions = [
      {:instructions, 0},
      {:input_fields, 0},
      {:output_fields, 0},
      {:fields, 0}
    ]

    missing_functions =
      required_functions
      |> Enum.reject(fn {func, arity} ->
        function_exported?(module, func, arity)
      end)

    if Enum.empty?(missing_functions) do
      :ok
    else
      {:error, "Missing required functions: #{inspect(missing_functions)}"}
    end
  end

  @doc """
  Returns field statistics for a signature module.

  Provides count information about input and output fields,
  useful for optimization and analysis workflows.

  ## Parameters
  - `signature_module` - The signature module to analyze

  ## Returns
  - `%{input_count: integer(), output_count: integer()}` - Field counts

  ## Examples

      iex> DSPEx.Signature.field_statistics(QASignature)
      %{input_count: 1, output_count: 1}

  """
  @spec field_statistics(module()) :: %{input_count: integer(), output_count: integer()}
  def field_statistics(signature_module) when is_atom(signature_module) do
    try do
      input_count = length(signature_module.input_fields())
      output_count = length(signature_module.output_fields())

      %{
        input_count: input_count,
        output_count: output_count
      }
    rescue
      _error ->
        %{input_count: 0, output_count: 0}
    end
  end

  # Private helper functions for validation

  defp validate_field_lists(module) do
    try do
      inputs = module.input_fields()
      outputs = module.output_fields()
      all_fields = module.fields()

      with :ok <- validate_field_types(inputs, outputs, all_fields),
           :ok <- validate_field_consistency(inputs, outputs, all_fields),
           :ok <- validate_field_uniqueness(inputs, outputs),
           :ok <- validate_field_overlap(inputs, outputs) do
        :ok
      else
        error -> error
      end
    rescue
      error -> {:error, "Field list validation failed: #{inspect(error)}"}
    end
  end

  defp validate_field_types(inputs, outputs, all_fields) do
    cond do
      not (is_list(inputs) and Enum.all?(inputs, &is_atom/1)) ->
        {:error, "input_fields/0 must return a list of atoms"}

      not (is_list(outputs) and Enum.all?(outputs, &is_atom/1)) ->
        {:error, "output_fields/0 must return a list of atoms"}

      not (is_list(all_fields) and Enum.all?(all_fields, &is_atom/1)) ->
        {:error, "fields/0 must return a list of atoms"}

      true ->
        :ok
    end
  end

  defp validate_field_consistency(inputs, outputs, all_fields) do
    expected_all_fields = inputs ++ outputs

    if MapSet.new(all_fields) != MapSet.new(expected_all_fields) do
      {:error, "fields/0 return value is inconsistent with input_fields/0 + output_fields/0"}
    else
      :ok
    end
  end

  defp validate_field_uniqueness(inputs, outputs) do
    cond do
      length(inputs) != length(Enum.uniq(inputs)) ->
        {:error, "Duplicate fields in input_fields/0"}

      length(outputs) != length(Enum.uniq(outputs)) ->
        {:error, "Duplicate fields in output_fields/0"}

      true ->
        :ok
    end
  end

  defp validate_field_overlap(inputs, outputs) do
    input_set = MapSet.new(inputs)
    output_set = MapSet.new(outputs)
    overlap = MapSet.intersection(input_set, output_set)

    if MapSet.size(overlap) == 0 do
      :ok
    else
      {:error, "Fields cannot be both input and output: #{inspect(MapSet.to_list(overlap))}"}
    end
  end

  defp validate_instructions(module) do
    try do
      instructions = module.instructions()

      cond do
        not is_binary(instructions) ->
          {:error, "instructions/0 must return a binary string"}

        String.trim(instructions) == "" ->
          {:error, "instructions/0 must return a non-empty string"}

        true ->
          :ok
      end
    rescue
      error -> {:error, "Instructions validation failed: #{inspect(error)}"}
    end
  end
end

defmodule DSPEx.Signature.Parser do
  @moduledoc false
  # This module is private and only used by the macro at compile time.

  @typedoc "Parsed signature result as input and output field lists"
  @type parsed_signature :: {[atom()], [atom()]}

  @doc """
  Parses signature string into input and output field lists.

  Equivalent to Python's _parse_signature() function.

  ## Parameters
  - `signature_string` - The signature string to parse

  ## Returns
  - A tuple `{input_fields, output_fields}` where both are lists of atoms

  ## Raises
  - `CompileError` for invalid signature formats

  ## Examples

      iex> DSPEx.Signature.Parser.parse("question -> answer")
      {[:question], [:answer]}

      iex> DSPEx.Signature.Parser.parse("question, context -> answer, confidence")
      {[:question, :context], [:answer, :confidence]}

  """
  @spec parse(String.t()) :: parsed_signature() | no_return()
  def parse(signature_string) when is_binary(signature_string) do
    signature_string
    |> String.trim()
    |> validate_format()
    |> split_signature()
    |> parse_fields()
    |> validate_fields()
  end

  # Validates basic format with arrow separator
  @spec validate_format(String.t()) :: String.t() | no_return()
  defp validate_format(str) do
    unless String.contains?(str, "->") do
      raise CompileError,
        description: "DSPEx signature must contain '->' separator. Example: 'question -> answer'",
        file: __ENV__.file,
        line: __ENV__.line
    end

    str
  end

  # Splits on arrow, handles whitespace
  @spec split_signature(String.t()) :: {String.t(), String.t()} | no_return()
  defp split_signature(str) do
    case String.split(str, "->", parts: 2) do
      [inputs_str, outputs_str] ->
        {String.trim(inputs_str), String.trim(outputs_str)}

      _ ->
        raise CompileError,
          description: "Invalid DSPEx signature format. Must contain exactly one '->' separator.",
          file: __ENV__.file,
          line: __ENV__.line
    end
  end

  # Parses comma-separated field lists
  @spec parse_fields({String.t(), String.t()}) :: parsed_signature() | no_return()
  defp parse_fields({inputs_str, outputs_str}) do
    inputs = parse_field_list(inputs_str)
    outputs = parse_field_list(outputs_str)

    # Validate that both inputs and outputs are non-empty
    if Enum.empty?(inputs) do
      raise CompileError,
        description: "DSPEx signature must have at least one input field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    if Enum.empty?(outputs) do
      raise CompileError,
        description: "DSPEx signature must have at least one output field",
        file: __ENV__.file,
        line: __ENV__.line
    end

    {inputs, outputs}
  end

  @spec parse_field_list(String.t()) :: [atom()]
  defp parse_field_list(""), do: []

  defp parse_field_list(str) do
    fields =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    # Check for empty fields before rejecting them
    if Enum.any?(fields, &(&1 == "")) do
      raise CompileError,
        description: "Empty field names are not allowed in DSPEx signatures",
        file: __ENV__.file,
        line: __ENV__.line
    end

    fields
    |> Enum.map(&validate_field_name/1)
    |> Enum.map(&String.to_atom/1)
  end

  # Validates field names are valid Elixir atoms
  @spec validate_field_name(String.t()) :: String.t() | no_return()
  defp validate_field_name(name) do
    unless Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, name) do
      raise CompileError,
        description:
          "Invalid field name '#{name}'. Must be a valid Elixir atom starting with lowercase letter.",
        file: __ENV__.file,
        line: __ENV__.line
    end

    name
  end

  # Validates no duplicate fields
  @spec validate_fields(parsed_signature()) :: parsed_signature() | no_return()
  defp validate_fields({inputs, outputs}) do
    all_fields = inputs ++ outputs
    unique_fields = Enum.uniq(all_fields)

    if length(all_fields) != length(unique_fields) do
      duplicates = all_fields -- unique_fields

      raise CompileError,
        description: "Duplicate fields found: #{inspect(duplicates)}",
        file: __ENV__.file,
        line: __ENV__.line
    end

    {inputs, outputs}
  end
end
