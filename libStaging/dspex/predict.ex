defmodule DSPEx.Predict do
  @moduledoc """
  Core prediction orchestration program with Foundation integration and SIMBA model configuration support.

  Implements the DSPEx.Program behavior to provide a structured interface
  for language model predictions with comprehensive telemetry, error handling,
  observability through Foundation infrastructure, and enhanced support for
  SIMBA's dynamic model configuration requirements.

  ## Usage as a Program

      iex> predict = %DSPEx.Predict{
      ...>   signature: MySignature,
      ...>   client: :openai,
      ...>   adapter: DSPEx.Adapter.Chat
      ...> }
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Program.forward(predict, inputs)
      iex> outputs
      %{answer: "4"}

  ## SIMBA Model Configuration Support

      # SIMBA can dynamically configure model parameters
      iex> opts = [temperature: 0.9, max_tokens: 200, model: "gpt-4"]
      iex> {:ok, outputs} = DSPEx.Program.forward(predict, inputs, opts)

  ## Legacy API (maintained for compatibility)

      iex> signature = MySignature  # question -> answer
      iex> inputs = %{question: "What is 2+2?"}
      iex> {:ok, outputs} = DSPEx.Predict.forward(signature, inputs)
      iex> outputs
      %{answer: "4"}

  """

  use DSPEx.Program

  # Declare variables for automatic optimization
  variable(:temperature, :float,
    range: {0.0, 2.0},
    default: 0.7,
    description: "Sampling temperature for model response"
  )

  variable(:max_tokens, :integer,
    range: {50, 4000},
    default: 1000,
    description: "Maximum tokens in model response"
  )

  variable(:provider, :choice,
    choices: [:openai, :anthropic, :groq],
    description: "LLM provider selection"
  )

  variable(:model, :choice,
    choices: [:auto, "gpt-4", "gpt-3.5-turbo", "claude-3-opus"],
    description: "Model selection"
  )

  variable(:adapter, :module,
    modules: [DSPEx.Adapter, DSPEx.Adapter.Chat, DSPEx.Adapter.JSON],
    description: "Response format adapter"
  )

  @enforce_keys [:signature, :client]
  defstruct [:signature, :client, :adapter, :instruction, :variable_space, demos: []]

  @type t :: %__MODULE__{
          signature: module(),
          client: atom() | map(),
          adapter: module() | nil,
          instruction: String.t() | nil,
          variable_space: ElixirML.Variable.Space.t() | nil,
          demos: [map()]
        }
  @type signature :: module()
  @type inputs :: map()
  @type outputs :: map()
  @type prediction_options :: %{
          optional(:provider) => atom(),
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:correlation_id) => String.t(),
          optional(:timeout) => pos_integer()
        }

  @doc """
  Create a new Predict program with enhanced SIMBA support.

  ## Parameters

  - `signature` - Signature module defining input/output contract
  - `client` - Client identifier (atom) or client configuration
  - `opts` - Optional configuration

  ## Options

  - `:adapter` - Adapter module (default: nil, uses DSPEx.Adapter fallback)
  - `:demos` - List of demonstration examples
  - `:instruction` - Custom instruction text for the program

  """
  @spec new(signature(), atom() | map(), keyword() | map()) :: t()
  def new(signature, client, opts \\ []) do
    # Create variable space for this program
    variable_space = create_variable_space_for_predict(signature, opts)

    %__MODULE__{
      signature: signature,
      client: client,
      adapter: get_option(opts, :adapter, nil),
      demos: get_option(opts, :demos, []),
      instruction: get_option(opts, :instruction, nil),
      variable_space: variable_space
    }
  end

  # Create variable space combining declared variables with signature analysis
  defp create_variable_space_for_predict(signature, opts) do
    # Get declared variables from this module
    declared_vars = __MODULE__.__variables__()

    # Create base space from declared variables
    base_space =
      Enum.reduce(declared_vars, ElixirML.Variable.Space.new(), fn {_name, variable}, space ->
        ElixirML.Variable.Space.add_variable(space, variable)
      end)

    # Enhance with signature-specific variables if requested
    if get_option(opts, :auto_extract_variables, true) do
      DSPEx.Program.Variable.extract_from_signature(signature,
        # Don't duplicate our declared variables
        include_ml_variables: false
      )
      |> merge_variable_spaces(base_space)
    else
      base_space
    end
  rescue
    # Graceful degradation if ElixirML is not available
    _ -> nil
  end

  # Merge two variable spaces (simple implementation)
  defp merge_variable_spaces(source_space, target_space) do
    case {source_space, target_space} do
      {source, target} ->
        # Add variables from source to target (target takes precedence)
        source.variables
        |> Enum.reduce(target, fn {name, variable}, acc_space ->
          if Map.has_key?(target.variables, name) do
            # Keep target's version
            acc_space
          else
            ElixirML.Variable.Space.add_variable(acc_space, variable)
          end
        end)
    end
  rescue
    _ -> target_space
  end

  # Helper function to get options from either keyword list or map
  defp get_option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp get_option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  # DSPEx.Program behavior implementation with SIMBA enhancements
  @impl DSPEx.Program
  def forward(program_or_signature, inputs, opts)

  def forward(program, inputs, opts) when is_struct(program, __MODULE__) do
    # PREDICT PERFORMANCE INSTRUMENTATION
    _predict_start = System.monotonic_time()

    # Step 1: Correlation ID (optimized)
    correlation_start = System.monotonic_time()

    correlation_id =
      case Keyword.get(opts, :correlation_id) do
        nil ->
          # Use fast UUID generation to avoid crypto cold start
          node_hash = :erlang.phash2(node(), 65_536)
          timestamp = System.unique_integer([:positive])
          random = :erlang.unique_integer([:positive])
          "predict-#{node_hash}-#{timestamp}-#{random}"

        existing_id ->
          existing_id
      end

    _correlation_duration =
      System.convert_time_unit(System.monotonic_time() - correlation_start, :native, :microsecond)

    # Step 2: Extract model configuration for SIMBA support
    model_config = extract_model_configuration(opts)

    # Step 2.5: Resolve variables for automatic optimization
    resolved_variables = DSPEx.Program.resolve_variables(program, opts)

    # Merge resolved variables into model configuration
    enhanced_model_config = merge_variables_into_config(model_config, resolved_variables)

    # Step 3: Format messages with enhanced adapter support
    format_start = System.monotonic_time()

    format_result =
      format_messages_enhanced(program, inputs, enhanced_model_config, correlation_id)

    _format_duration =
      System.convert_time_unit(System.monotonic_time() - format_start, :native, :microsecond)

    # Step 4: Make request with model configuration
    request_start = System.monotonic_time()

    request_result =
      case format_result do
        {:ok, messages} ->
          make_request_with_config(program, messages, enhanced_model_config, opts, correlation_id)

        error ->
          error
      end

    _request_duration =
      System.convert_time_unit(System.monotonic_time() - request_start, :native, :microsecond)

    # Step 5: Parse response
    parse_start = System.monotonic_time()

    final_result =
      case request_result do
        {:ok, response} -> parse_response_enhanced(program, response, correlation_id)
        error -> error
      end

    _parse_duration =
      System.convert_time_unit(System.monotonic_time() - parse_start, :native, :microsecond)

    # Performance instrumentation (disabled for production)
    # total_duration = System.convert_time_unit(System.monotonic_time() - predict_start, :native, :microsecond)
    # IO.puts("  🎯 DSPEx.Predict.forward [#{total_duration}µs]: Format=#{format_duration}µs, Request=#{request_duration}µs, Parse=#{parse_duration}µs")

    final_result
  end

  # Legacy API for backward compatibility - signature as first argument
  @doc """
  Legacy forward API for backward compatibility - signature as first argument.

  Delegates to predict/2 for compatibility with existing code.
  """
  def forward(signature, inputs, opts) when is_atom(signature) do
    case opts do
      opts when is_map(opts) -> predict(signature, inputs, opts)
      [] -> predict(signature, inputs)
      opts when is_list(opts) -> predict(signature, inputs, Enum.into(opts, %{}))
    end
  end

  # Private helper functions for Program implementation with SIMBA support

  defp extract_model_configuration(opts) do
    # Extract model configuration parameters that SIMBA passes
    %{
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens),
      model: Keyword.get(opts, :model),
      provider: Keyword.get(opts, :provider),
      timeout: Keyword.get(opts, :timeout)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp merge_variables_into_config(model_config, resolved_variables)
       when is_map(resolved_variables) do
    # Merge resolved variables into model configuration
    # Variables take precedence over explicit model config
    Map.merge(model_config, resolved_variables)
  end

  defp merge_variables_into_config(model_config, _), do: model_config

  defp format_messages_enhanced(program, inputs, model_config, correlation_id) do
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(program.signature)

    :telemetry.execute(
      [:dspex, :adapter, :format, :start],
      %{system_time: System.system_time()},
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        has_model_config: map_size(model_config) > 0
      }
    )

    # Use adapter to format messages with signature, demos, and instruction
    result =
      if program.adapter && function_exported?(program.adapter, :format_messages, 3) do
        # Enhanced adapter that supports demos and instruction
        program.adapter.format_messages(program.signature, program.demos, inputs)
      else
        # Enhanced fallback adapter with demo and instruction support
        format_with_enhanced_adapter(program, inputs)
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :format, :stop],
      %{duration: duration, success: success},
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        adapter: adapter_name(program.adapter),
        demo_count: length(program.demos),
        has_instruction: not is_nil(program.instruction)
      }
    )

    result
  end

  defp format_with_enhanced_adapter(program, inputs) do
    # Enhanced adapter logic that incorporates demos and instruction
    with {:ok, base_messages} <- DSPEx.Adapter.format_messages(program.signature, inputs) do
      enhanced_messages = enhance_messages_with_context(base_messages, program)
      {:ok, enhanced_messages}
    end
  end

  defp enhance_messages_with_context(messages, program) do
    # Add instruction and demos to the messages
    enhanced_content = build_enhanced_content(messages, program)

    case messages do
      [%{role: "user", content: _original_content}] ->
        [%{role: "user", content: enhanced_content}]

      multiple_messages ->
        # For multi-turn conversations, enhance the last user message
        List.update_at(multiple_messages, -1, fn last_msg ->
          %{last_msg | content: enhanced_content}
        end)
    end
  end

  defp build_enhanced_content([%{role: "user", content: original_content} | _], program) do
    parts = []

    # Add instruction if present
    parts =
      if program.instruction do
        ["Instructions: #{program.instruction}" | parts]
      else
        parts
      end

    # Add demonstrations if present
    parts =
      if Enum.empty?(program.demos) do
        parts
      else
        demo_text = format_demonstrations(program.demos)
        ["Examples:\n#{demo_text}" | parts]
      end

    # Add original content
    parts = [original_content | parts]

    # Combine parts
    Enum.map_join(Enum.reverse(parts), "\n\n", & &1)
  end

  defp format_demonstrations(demos) do
    demos
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {demo, index} ->
      inputs = DSPEx.Example.inputs(demo)
      outputs = DSPEx.Example.outputs(demo)

      input_text = Enum.map_join(inputs, ", ", fn {k, v} -> "#{k}: #{v}" end)
      # Filter out metadata fields that shouldn't be stringified
      filtered_outputs =
        Enum.reject(outputs, fn {k, _v} ->
          String.starts_with?(to_string(k), "__") or String.ends_with?(to_string(k), "_metadata")
        end)

      output_text = Enum.map_join(filtered_outputs, ", ", fn {k, v} -> "#{k}: #{v}" end)

      "Example #{index}:\nInput: #{input_text}\nOutput: #{output_text}"
    end)
  end

  defp make_request_with_config(program, messages, model_config, opts, correlation_id) do
    # Build client options with model configuration
    opts_start = System.monotonic_time()

    # Merge model configuration with original options
    client_opts =
      opts
      |> Keyword.put(:correlation_id, correlation_id)
      |> merge_model_config(model_config)
      |> Enum.into(%{})

    _opts_duration =
      System.convert_time_unit(System.monotonic_time() - opts_start, :native, :microsecond)

    # Make request through client with enhanced configuration
    request_start = System.monotonic_time()
    result = DSPEx.Client.request(program.client, messages, client_opts)

    _request_duration =
      System.convert_time_unit(System.monotonic_time() - request_start, :native, :microsecond)

    result
  end

  defp merge_model_config(opts, model_config) when map_size(model_config) > 0 do
    # Convert model config to keyword list and merge
    model_config_list = Map.to_list(model_config)
    Keyword.merge(opts, model_config_list)
  end

  defp merge_model_config(opts, _model_config), do: opts

  defp parse_response_enhanced(program, response, correlation_id) do
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(program.signature)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :start],
      %{system_time: System.system_time()},
      %{
        signature: sig_name,
        correlation_id: correlation_id
      }
    )

    # Use adapter to parse response with Sinter validation
    result =
      with {:ok, outputs} <- parse_with_adapter(program, response),
           {:ok, validated_outputs} <- validate_outputs_with_sinter(program.signature, outputs) do
        {:ok, validated_outputs}
      else
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :stop],
      %{duration: duration, success: success},
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        adapter: adapter_name(program.adapter)
      }
    )

    result
  end

  defp parse_with_adapter(program, response) do
    if program.adapter && function_exported?(program.adapter, :parse_response, 2) do
      program.adapter.parse_response(program.signature, response)
    else
      # Fallback to basic adapter
      DSPEx.Adapter.parse_response(program.signature, response)
    end
  end

  defp adapter_name(nil), do: "default"

  defp adapter_name(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  defp adapter_name(_), do: "unknown"

  @doc """
  Execute a prediction using the given signature and inputs with Foundation observability.

  Legacy API for backward compatibility. For new code, prefer creating a DSPEx.Predict
  struct and using DSPEx.Program.forward/2.

  ## Parameters

  - `signature` - Signature module defining input/output contract
  - `inputs` - Map of input field values
  - `options` - Optional prediction configuration

  ## Returns

  - `{:ok, outputs}` - Successful prediction with parsed outputs
  - `{:error, reason}` - Error at any stage of the pipeline

  """
  @spec predict(signature(), inputs()) :: {:ok, outputs()} | {:error, atom()}
  def predict(signature, inputs) do
    predict(signature, inputs, %{})
  end

  @spec predict(signature(), inputs(), prediction_options()) ::
          {:ok, outputs()} | {:error, atom()}
  def predict(signature, inputs, options) do
    # Only generate correlation_id if not provided - avoid expensive UUID generation
    correlation_id =
      case Map.get(options, :correlation_id) do
        nil -> Foundation.Utils.generate_correlation_id()
        existing_id -> existing_id
      end

    # Start prediction telemetry
    start_time = System.monotonic_time()

    # Cache signature name to avoid repeated Module.split operations
    sig_name = signature_name(signature)

    :telemetry.execute(
      [:dspex, :predict, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        input_count: map_size(inputs)
      }
    )

    # Execute the prediction pipeline
    result = execute_prediction_pipeline(signature, inputs, options, correlation_id)

    # Calculate duration and success
    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    # Emit telemetry stop event
    :telemetry.execute(
      [:dspex, :predict, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: sig_name,
        correlation_id: correlation_id,
        provider: Map.get(options, :provider)
      }
    )

    result
  end

  @doc """
  Execute a prediction and return the result for a specific output field.

  Convenience function for signatures with a single primary output field.

  ## Parameters

  - `signature` - Signature module
  - `inputs` - Input field values
  - `output_field` - The specific output field to extract
  - `options` - Optional prediction configuration

  ## Returns

  - `{:ok, value}` - The value of the specified output field
  - `{:error, reason}` - Error during prediction or field not found

  """
  @spec predict_field(signature(), inputs(), atom()) :: {:ok, any()} | {:error, atom()}
  def predict_field(signature, inputs, output_field) do
    predict_field(signature, inputs, output_field, %{})
  end

  @spec predict_field(signature(), inputs(), atom(), prediction_options()) ::
          {:ok, any()} | {:error, atom()}
  def predict_field(signature, inputs, output_field, options) do
    # Only generate correlation_id if not provided - avoid expensive UUID generation
    correlation_id =
      case Map.get(options, :correlation_id) do
        nil -> Foundation.Utils.generate_correlation_id()
        existing_id -> existing_id
      end

    case forward(signature, inputs, Map.put(options, :correlation_id, correlation_id)) do
      {:ok, outputs} ->
        case Map.fetch(outputs, output_field) do
          {:ok, value} ->
            # Foundation v0.1.3 fixed - re-enabled!
            Foundation.Events.new_event(
              :field_extraction_success,
              %{
                signature: signature_name(signature),
                field: output_field,
                value_type: type_of(value)
              },
              correlation_id: correlation_id
            )
            |> Foundation.Events.store()

            {:ok, value}

          :error ->
            # Foundation v0.1.3 fixed - re-enabled!
            Foundation.Events.new_event(
              :field_extraction_error,
              %{
                signature: signature_name(signature),
                field: output_field,
                available_fields: Map.keys(outputs)
              },
              correlation_id: correlation_id
            )
            |> Foundation.Events.store()

            {:error, :field_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate that a signature is compatible with given inputs.

  Checks that all required input fields are present and validates them using Sinter
  if the signature supports schema validation. Useful for validation before batch processing.

  ## Parameters

  - `signature` - Signature module
  - `inputs` - Input field values to validate

  ## Returns

  - `:ok` - All required fields present and valid
  - `{:error, reason}` - Validation failed

  """
  @spec validate_inputs(signature(), inputs()) :: :ok | {:error, atom()}
  def validate_inputs(signature, inputs) do
    correlation_id = Foundation.Utils.generate_correlation_id()

    # Start validation telemetry
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :signature, :validation, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result =
      with {:ok, _messages} <- DSPEx.Adapter.format_messages(signature, inputs),
           :ok <- validate_inputs_with_sinter(signature, inputs) do
        :ok
      else
        {:error, reason} -> {:error, reason}
      end

    # Stop validation telemetry
    duration = System.monotonic_time() - start_time
    success = result == :ok

    :telemetry.execute(
      [:dspex, :signature, :validation, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result
  end

  @doc """
  Get the expected input and output fields for a signature.

  Utility function for introspecting signature requirements.

  ## Parameters

  - `signature` - Signature module

  ## Returns

  - `{:ok, %{inputs: [...], outputs: [...]}}` - Field lists
  - `{:error, reason}` - Invalid signature

  """
  @spec describe_signature(signature()) :: {:ok, map()} | {:error, atom()}
  def describe_signature(signature) do
    with {:ok, inputs} <- get_input_fields(signature),
         {:ok, outputs} <- get_output_fields(signature) do
      description = %{
        inputs: inputs,
        outputs: outputs,
        description: get_description(signature),
        name: signature_name(signature)
      }

      {:ok, description}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp execute_prediction_pipeline(signature, inputs, options, correlation_id) do
    with {:ok, messages} <- format_messages_with_telemetry(signature, inputs, correlation_id),
         {:ok, response} <- make_client_request(messages, options, correlation_id),
         {:ok, outputs} <- parse_response_with_telemetry(signature, response, correlation_id) do
      {:ok, outputs}
    else
      {:error, reason} ->
        # Emit exception telemetry
        :telemetry.execute([:dspex, :predict, :exception], %{}, %{
          signature: signature_name(signature),
          correlation_id: correlation_id,
          error_type: reason
        })

        {:error, reason}
    end
  end

  defp format_messages_with_telemetry(signature, inputs, correlation_id) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :adapter, :format, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result = DSPEx.Adapter.format_messages(signature, inputs)

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :format, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        adapter: "default"
      }
    )

    result
  end

  defp make_client_request(messages, options, correlation_id) do
    # Add correlation_id to options for client request
    client_options = Map.put(options, :correlation_id, correlation_id)
    DSPEx.Client.request(messages, client_options)
  end

  defp parse_response_with_telemetry(signature, response, correlation_id) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:dspex, :adapter, :parse, :start],
      %{
        system_time: System.system_time()
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id
      }
    )

    result =
      with {:ok, outputs} <- DSPEx.Adapter.parse_response(signature, response),
           {:ok, validated_outputs} <- validate_outputs_with_sinter(signature, outputs) do
        {:ok, validated_outputs}
      else
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:dspex, :adapter, :parse, :stop],
      %{
        duration: duration,
        success: success
      },
      %{
        signature: signature_name(signature),
        correlation_id: correlation_id,
        adapter: "default"
      }
    )

    result
  end

  defp get_input_fields(signature) do
    if function_exported?(signature, :input_fields, 0) do
      {:ok, signature.input_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  defp get_output_fields(signature) do
    if function_exported?(signature, :output_fields, 0) do
      {:ok, signature.output_fields()}
    else
      {:error, :invalid_signature}
    end
  end

  defp get_description(signature) do
    if function_exported?(signature, :description, 0) do
      signature.description()
    else
      "No description available"
    end
  end

  defp signature_name(signature) when is_atom(signature) do
    signature
    |> Module.split()
    |> List.last()
    |> String.to_atom()
  end

  defp signature_name(_signature), do: :unknown

  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_number(value), do: :number
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_map(value), do: :map
  defp type_of(_), do: :unknown

  # Sinter integration functions

  defp validate_inputs_with_sinter(_signature, _inputs) do
    # Graceful degradation - Sinter validation not yet implemented
    # This is a placeholder for future Sinter integration
    :ok
  end

  defp validate_outputs_with_sinter(_signature, outputs) do
    # Graceful degradation - Sinter validation not yet implemented
    # This is a placeholder for future Sinter integration
    {:ok, outputs}
  end
end
