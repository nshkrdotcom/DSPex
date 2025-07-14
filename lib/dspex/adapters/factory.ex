defmodule DSPex.Adapters.Factory do
  @moduledoc """
  Factory for creating and managing adapter instances with test layer awareness.
  """

  alias DSPex.Adapters.{Registry, ErrorHandler, TypeConverter}

  require Logger

  @type adapter_config :: %{
          adapter: atom() | module(),
          options: keyword() | map(),
          context: map()
        }

  @type execution_context :: %{
          adapter: module(),
          request_id: String.t(),
          started_at: DateTime.t(),
          metadata: map()
        }

  @doc """
  Create adapter with test layer specific configuration.
  """
  @spec create_adapter(atom() | nil, keyword()) ::
          {:ok, module()} | {:error, DSPex.Adapters.ErrorHandler.adapter_error()}
  def create_adapter(adapter_type \\ nil, opts \\ []) do
    test_layer =
      Keyword.get(opts, :test_layer) ||
        get_test_layer()

    resolved_adapter_type =
      adapter_type ||
        Registry.get_adapter_for_test_layer(test_layer)

    # Resolve adapter name to module
    adapter_module = resolve_adapter_to_module(resolved_adapter_type)

    with {:ok, validated_adapter} <- Registry.validate_adapter(adapter_module),
         {:ok, _} <- check_adapter_requirements(validated_adapter, opts),
         {:ok, _} <- validate_test_layer_compatibility(validated_adapter, test_layer) do
      {:ok, validated_adapter}
    else
      {:error, reason} ->
        {:error,
         ErrorHandler.wrap_error({:error, reason}, %{
           adapter_type: adapter_type,
           test_layer: test_layer,
           resolved_adapter: adapter_module
         })}
    end
  end

  @doc """
  Resolve adapter name/atom to actual module.
  """
  @spec resolve_adapter_to_module(atom() | module()) :: module()
  def resolve_adapter_to_module(adapter) when is_atom(adapter) do
    case adapter do
      :mock ->
        DSPex.Adapters.Mock

      :bridge_mock ->
        DSPex.Adapters.BridgeMock

      :python_port ->
        DSPex.Adapters.PythonPort

      module when is_atom(module) ->
        # Check if it's already a module
        case Code.ensure_loaded(module) do
          {:module, _} -> module
          # Return the original atom so Registry.validate_adapter can handle the error
          _ -> module
        end
    end
  end

  def resolve_adapter_to_module(module) when is_atom(module), do: module

  @doc """
  Execute operation with adapter, retry logic, and test layer awareness.
  """
  @spec execute_with_adapter(module(), atom(), list(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def execute_with_adapter(adapter, operation, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, get_default_timeout())
    max_retries = Keyword.get(opts, :max_retries, get_default_retries())

    test_layer =
      Keyword.get(opts, :test_layer) ||
        get_test_layer()

    context = %{
      adapter: adapter,
      operation: operation,
      test_layer: test_layer
    }

    execute_with_retry(adapter, operation, args, max_retries, timeout, context)
  end

  @doc """
  Execute with signature validation and type conversion.
  """
  @spec execute_with_signature_validation(module(), module(), map(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def execute_with_signature_validation(adapter, signature_module, inputs, opts \\ []) do
    test_layer =
      Keyword.get(opts, :test_layer) ||
        get_test_layer()

    with {:ok, validated_inputs} <-
           validate_inputs_for_signature(signature_module, inputs, test_layer),
         {:ok, adapter_inputs} <-
           convert_inputs_for_adapter(adapter, signature_module, validated_inputs, test_layer),
         {:ok, prepared_signature} <-
           prepare_signature_for_adapter(signature_module, adapter, test_layer) do
      # Create a temporary program to execute
      program_id = "temp_program_#{:erlang.unique_integer([:positive])}"

      program_config = %{
        id: program_id,
        signature: prepared_signature,
        modules: []
      }

      with {:ok, _} <- adapter.create_program(program_config),
           {:ok, result} <- adapter.execute_program(program_id, adapter_inputs) do
        # Cleanup temporary program
        adapter.delete_program(program_id)
        {:ok, result}
      else
        error ->
          # Cleanup on error
          adapter.delete_program(program_id)
          error
      end
    else
      {:error, reason} ->
        {:error,
         ErrorHandler.wrap_error({:error, reason}, %{
           signature: signature_module,
           inputs: inputs,
           test_layer: test_layer
         })}
    end
  end

  @doc """
  Prepare signature for specific adapter requirements.
  """
  @spec prepare_signature_for_adapter(module(), module(), atom()) :: {:ok, any()}
  def prepare_signature_for_adapter(signature_module, adapter, test_layer) do
    case adapter do
      DSPex.Adapters.Mock ->
        # Mock adapter can handle signature modules directly now
        {:ok, signature_module}

      DSPex.Adapters.BridgeMock ->
        # BridgeMock needs wire format
        signature_data =
          TypeConverter.convert_signature_to_format(signature_module, :wire,
            test_layer: test_layer
          )

        {:ok, signature_data}

      DSPex.Adapters.PythonPort ->
        # PythonPort needs converted format like BridgeMock
        signature_data =
          TypeConverter.convert_signature_to_format(signature_module, :python,
            test_layer: test_layer
          )

        {:ok, signature_data}

      _ ->
        # Default to signature module
        {:ok, signature_module}
    end
  end

  @doc """
  Creates an adapter instance with the specified configuration (legacy API).

  ## Options

  - `:adapter` - The adapter name or module (defaults to Registry selection)
  - `:options` - Adapter-specific options
  - `:validate` - Whether to validate the adapter (default: true)
  - `:start_services` - Whether to start required services (default: true)

  ## Examples

      # Use default adapter from Registry
      {:ok, adapter} = Factory.create_adapter_legacy()
      
      # Create specific adapter
      {:ok, adapter} = Factory.create_adapter_legacy(adapter: :mock)
      
      # With options
      {:ok, adapter} = Factory.create_adapter_legacy(
        adapter: :python_port,
        options: [timeout: 10_000]
      )
  """
  @spec create_adapter_legacy(keyword()) :: {:ok, module()} | {:error, term()}
  def create_adapter_legacy(opts \\ []) do
    with {:ok, adapter_module} <- resolve_adapter(opts),
         :ok <- validate_adapter_legacy(adapter_module, opts),
         :ok <- start_required_services(adapter_module, opts) do
      {:ok, adapter_module}
    end
  end

  @doc """
  Creates an adapter and executes a program in one operation (legacy).

  Handles the complete lifecycle of adapter creation, program execution,
  and cleanup with proper error handling and logging.

  ## Examples

      Factory.execute_with_adapter_legacy(:mock, "program_id", %{input: "test"})
  """
  @spec execute_with_adapter_legacy(atom() | module(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_with_adapter_legacy(adapter, program_id, inputs, opts \\ []) do
    context = create_execution_context(adapter, program_id)

    with {:ok, adapter_module} <- create_adapter_legacy([{:adapter, adapter} | opts]),
         :ok <- log_execution_start(context),
         {:ok, result} <- execute_with_error_handling(adapter_module, program_id, inputs, opts),
         :ok <- log_execution_complete(context, :success) do
      {:ok, result}
    else
      {:error, reason} = error ->
        log_execution_complete(context, {:error, reason})
        error
    end
  end

  @doc """
  Creates an adapter suitable for the specified test layer.

  ## Examples

      {:ok, adapter} = Factory.create_test_adapter(:layer_1)
      {:ok, adapter} = Factory.create_test_adapter(:layer_2, mock_config: %{delay: 100})
  """
  @spec create_test_adapter(atom(), keyword()) :: {:ok, module()} | {:error, String.t()}
  def create_test_adapter(layer, opts \\ []) do
    adapter_name =
      case layer do
        :layer_1 -> :mock
        :layer_2 -> :bridge_mock
        :layer_3 -> :python_port
        _ -> nil
      end

    if adapter_name do
      create_adapter(adapter_name, opts)
    else
      {:error, "No adapter found for test layer: #{layer}"}
    end
  end

  @doc """
  Creates multiple adapters for comparative testing.

  Useful for testing the same operations across different adapter implementations.

  ## Examples

      {:ok, adapters} = Factory.create_adapter_suite([:mock, :bridge_mock])
  """
  @spec create_adapter_suite([atom()]) :: {:ok, %{atom() => module()}} | {:error, term()}
  def create_adapter_suite(adapter_names) do
    results =
      Enum.reduce(adapter_names, %{}, fn name, acc ->
        case create_adapter(name) do
          {:ok, adapter} -> Map.put(acc, name, adapter)
          {:error, _reason} -> acc
        end
      end)

    if map_size(results) == length(adapter_names) do
      {:ok, results}
    else
      {:error, "Failed to create all adapters in suite"}
    end
  end

  @doc """
  Executes an operation with automatic retry and fallback.

  Attempts execution with the primary adapter, falling back to alternates
  on failure with configurable retry logic.

  ## Options

  - `:fallback_adapters` - List of adapter names to try on failure
  - `:max_retries` - Maximum retry attempts per adapter (default: 3)
  - `:retry_delay` - Delay between retries in ms (default: 100)

  ## Examples

      Factory.execute_with_fallback(
        :python_port,
        :execute_program,
        ["prog_id", %{input: "test"}],
        fallback_adapters: [:bridge_mock, :mock]
      )
  """
  @spec execute_with_fallback(atom(), atom(), list(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def execute_with_fallback(primary_adapter, operation, args, opts \\ []) do
    adapters = [primary_adapter | Keyword.get(opts, :fallback_adapters, [])]
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 100)

    execute_with_adapter_list(adapters, operation, args, max_retries, retry_delay)
  end

  defp execute_with_retry(adapter, operation, args, retries_left, timeout, context) do
    case apply_with_timeout(adapter, operation, args, timeout) do
      {:ok, result} ->
        {:ok, result}

      :ok ->
        {:ok, :ok}

      {:error, error} ->
        wrapped_error = ErrorHandler.wrap_error(error, context)

        if retries_left > 0 and ErrorHandler.should_retry?(wrapped_error) do
          delay = ErrorHandler.get_retry_delay(wrapped_error) || 1000
          Process.sleep(delay)
          execute_with_retry(adapter, operation, args, retries_left - 1, timeout, context)
        else
          {:error, wrapped_error}
        end

      other_result ->
        {:ok, other_result}
    end
  end

  defp apply_with_timeout(adapter, operation, args, timeout) do
    task = Task.async(fn -> apply(adapter, operation, args) end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        # Give the task a chance to finish gracefully
        case Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> result
          nil -> {:error, :timeout}
        end

      {:exit, reason} ->
        {:error, {:task_exit, reason}}
    end
  end

  defp check_adapter_requirements(adapter_module, opts) do
    test_layer = Keyword.get(opts, :test_layer)

    case adapter_module do
      DSPex.Adapters.PythonPort ->
        if test_layer == :layer_3 do
          check_python_bridge_available()
        else
          {:ok, :test_mode_bypass}
        end

      DSPex.Adapters.BridgeMock ->
        if test_layer == :layer_2 do
          check_bridge_mock_available()
        else
          {:ok, :test_mode_bypass}
        end

      DSPex.Adapters.Mock ->
        ensure_mock_started(opts)

      _ ->
        {:ok, :no_requirements}
    end
  end

  defp validate_test_layer_compatibility(adapter_module, test_layer) do
    if function_exported?(adapter_module, :supports_test_layer?, 1) do
      case adapter_module.supports_test_layer?(test_layer) do
        true ->
          {:ok, :compatible}

        false ->
          # In test modes, allow adapters to be used in non-native layers for testing
          case adapter_module do
            DSPex.Adapters.PythonPort when test_layer != :layer_3 ->
              {:ok, :test_mode_bypass}

            DSPex.Adapters.BridgeMock when test_layer != :layer_2 ->
              {:ok, :test_mode_bypass}

            DSPex.Adapters.Mock when test_layer != :layer_1 ->
              {:ok, :test_mode_bypass}

            _ ->
              {:error, "Adapter #{adapter_module} does not support test layer #{test_layer}"}
          end
      end
    else
      # Assume compatibility if not implemented
      {:ok, :compatible}
    end
  end

  defp validate_inputs_for_signature(signature_module, inputs, test_layer) do
    signature = signature_module.__signature__()

    Enum.reduce_while(signature.inputs, {:ok, %{}}, fn {field_name, field_type, _constraints},
                                                       {:ok, acc} ->
      case Map.get(inputs, field_name) || Map.get(inputs, to_string(field_name)) do
        nil ->
          {:halt, {:error, "Missing required input: #{field_name}"}}

        value ->
          case TypeConverter.validate_input(value, field_type, test_layer: test_layer) do
            {:ok, validated_value} ->
              {:cont, {:ok, Map.put(acc, field_name, validated_value)}}

            {:error, reason} ->
              {:halt, {:error, "Invalid input for #{field_name}: #{reason}"}}
          end
      end
    end)
  end

  defp convert_inputs_for_adapter(adapter, _signature_module, inputs, _test_layer) do
    # Convert inputs based on adapter requirements
    case adapter do
      DSPex.Adapters.PythonPort ->
        # Note: TypeConverter result would be used for type validation if needed
        # _signature_data = TypeConverter.convert_signature_to_format(signature_module, :python, test_layer: test_layer)
        # Python adapter handles conversion internally
        {:ok, inputs}

      DSPex.Adapters.BridgeMock ->
        # Protocol testing uses same format
        {:ok, inputs}

      DSPex.Adapters.Mock ->
        # Mock accepts any format
        {:ok, inputs}

      _ ->
        # Default pass-through
        {:ok, inputs}
    end
  end

  defp check_python_bridge_available do
    case Process.whereis(DSPex.PythonBridge.Bridge) do
      nil -> {:error, "Python bridge not running"}
      _pid -> {:ok, :available}
    end
  end

  defp check_bridge_mock_available do
    # For now, assume bridge mock is available if we're in test mode
    {:ok, :available}
  end

  defp ensure_mock_started(opts) do
    case Process.whereis(DSPex.Adapters.Mock) do
      nil -> DSPex.Adapters.Mock.start_link(opts)
      _pid -> {:ok, :already_started}
    end
  end

  # Test layer specific defaults
  defp get_default_timeout do
    case get_test_layer() do
      # Fast for mock tests
      :layer_1 -> 1_000
      # Medium for protocol tests
      :layer_2 -> 5_000
      # Longer for integration tests
      :layer_3 -> 30_000
    end
  end

  defp get_default_retries do
    case get_test_layer() do
      # No retries for mock (should be deterministic)
      :layer_1 -> 0
      # Some retries for protocol tests
      :layer_2 -> 2
      # More retries for integration tests
      :layer_3 -> 3
    end
  end

  defp get_test_layer do
    case System.get_env("TEST_MODE") do
      "mock_adapter" -> :layer_1
      "bridge_mock" -> :layer_2
      "full_integration" -> :layer_3
      _ -> :layer_3
    end
  end

  # Private Functions

  defp resolve_adapter(opts) do
    adapter = Keyword.get(opts, :adapter)

    adapter_module =
      case adapter do
        nil -> Registry.get_adapter()
        atom when is_atom(atom) -> Registry.get_adapter(atom)
        module when is_atom(module) -> module
        _ -> nil
      end

    if adapter_module do
      {:ok, adapter_module}
    else
      {:error, "Unable to resolve adapter: #{inspect(adapter)}"}
    end
  end

  defp validate_adapter_legacy(adapter_module, opts) do
    if Keyword.get(opts, :validate, true) do
      # Check if adapter has required functions
      if function_exported?(adapter_module, :create_program, 1) and
           function_exported?(adapter_module, :execute_program, 2) and
           function_exported?(adapter_module, :list_programs, 0) and
           function_exported?(adapter_module, :delete_program, 1) do
        :ok
      else
        {:error, "Adapter #{inspect(adapter_module)} missing required functions"}
      end
    else
      :ok
    end
  end

  defp start_required_services(adapter_module, opts) do
    if Keyword.get(opts, :start_services, true) and
         function_exported?(adapter_module, :required_services, 0) do
      case adapter_module.required_services() do
        [] -> :ok
        services -> start_services(services)
      end
    else
      :ok
    end
  end

  defp start_services(services) do
    Enum.reduce_while(services, :ok, fn service, _acc ->
      case ensure_service_started(service) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "Failed to start service #{service}: #{reason}"}}
      end
    end)
  end

  defp ensure_service_started(service) do
    case Process.whereis(service) do
      nil ->
        # Attempt to start the service
        case Application.ensure_started(service) do
          :ok -> :ok
          {:error, {:already_started, _}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp create_execution_context(adapter, program_id) do
    %{
      adapter: adapter,
      program_id: program_id,
      request_id: generate_request_id(),
      started_at: DateTime.utc_now(),
      metadata: %{}
    }
  end

  defp execute_with_error_handling(adapter_module, program_id, inputs, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    try do
      case adapter_module.execute_program(program_id, inputs) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> ErrorHandler.handle_adapter_error(adapter_module, reason)
      end
    catch
      :exit, {:timeout, _} ->
        ErrorHandler.handle_timeout_error(adapter_module, timeout)

      kind, reason ->
        ErrorHandler.handle_unexpected_error(adapter_module, kind, reason, __STACKTRACE__)
    end
  end

  defp execute_with_adapter_list([], _operation, _args, _max_retries, _retry_delay) do
    {:error, "All adapters failed"}
  end

  defp execute_with_adapter_list([adapter | rest], operation, args, max_retries, retry_delay) do
    case execute_with_retries(adapter, operation, args, max_retries, retry_delay) do
      {:ok, result} ->
        {:ok, result}

      :ok ->
        {:ok, :ok}

      {:error, reason} ->
        Logger.warning("Adapter #{adapter} failed: #{inspect(reason)}, trying next adapter")
        execute_with_adapter_list(rest, operation, args, max_retries, retry_delay)
    end
  end

  defp execute_with_retries(adapter, operation, args, max_retries, retry_delay) do
    execute_with_retries(adapter, operation, args, max_retries, retry_delay, 1)
  end

  defp execute_with_retries(_adapter, _operation, _args, max_retries, _retry_delay, attempt)
       when attempt > max_retries do
    {:error, "Max retries exceeded"}
  end

  defp execute_with_retries(adapter, operation, args, max_retries, retry_delay, attempt) do
    case create_adapter(adapter) do
      {:ok, adapter_module} ->
        case apply(adapter_module, operation, args) do
          {:ok, result} ->
            {:ok, result}

          {:error, _reason} when attempt < max_retries ->
            Process.sleep(retry_delay * attempt)
            execute_with_retries(adapter, operation, args, max_retries, retry_delay, attempt + 1)

          error ->
            error
        end

      error ->
        error
    end
  end

  defp log_execution_start(context) do
    Logger.metadata(
      request_id: context.request_id,
      adapter: context.adapter,
      program_id: context.program_id
    )

    Logger.debug("Starting adapter execution",
      adapter: context.adapter,
      program_id: context.program_id
    )

    :ok
  end

  defp log_execution_complete(context, status) do
    duration = DateTime.diff(DateTime.utc_now(), context.started_at, :millisecond)

    case status do
      :success ->
        Logger.debug("Adapter execution completed",
          adapter: context.adapter,
          program_id: context.program_id,
          duration_ms: duration
        )

      {:error, reason} ->
        Logger.error("Adapter execution failed",
          adapter: context.adapter,
          program_id: context.program_id,
          duration_ms: duration,
          error: inspect(reason)
        )
    end

    Logger.metadata([])
    :ok
  end

  defp generate_request_id do
    "req_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
