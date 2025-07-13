defmodule AshDSPex.Adapters.Factory do
  @moduledoc """
  Factory for creating and managing adapter instances.

  Provides a unified interface for adapter creation with proper configuration,
  validation, and execution context. Supports dynamic adapter selection and
  configuration for different environments and test scenarios.
  """

  alias AshDSPex.Adapters.{Registry, ErrorHandler}

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
  Creates an adapter instance with the specified configuration.

  ## Options

  - `:adapter` - The adapter name or module (defaults to Registry selection)
  - `:options` - Adapter-specific options
  - `:validate` - Whether to validate the adapter (default: true)
  - `:start_services` - Whether to start required services (default: true)

  ## Examples

      # Use default adapter from Registry
      {:ok, adapter} = Factory.create_adapter()
      
      # Create specific adapter
      {:ok, adapter} = Factory.create_adapter(adapter: :mock)
      
      # With options
      {:ok, adapter} = Factory.create_adapter(
        adapter: :python_port,
        options: [timeout: 10_000]
      )
  """
  @spec create_adapter(keyword()) :: {:ok, module()} | {:error, term()}
  def create_adapter(opts \\ []) do
    with {:ok, adapter_module} <- resolve_adapter(opts),
         :ok <- validate_adapter(adapter_module, opts),
         :ok <- start_required_services(adapter_module, opts) do
      {:ok, adapter_module}
    end
  end

  @doc """
  Creates an adapter and executes a program in one operation.

  Handles the complete lifecycle of adapter creation, program execution,
  and cleanup with proper error handling and logging.

  ## Examples

      Factory.execute_with_adapter(:mock, "program_id", %{input: "test"})
  """
  @spec execute_with_adapter(atom() | module(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_with_adapter(adapter, program_id, inputs, opts \\ []) do
    context = create_execution_context(adapter, program_id)

    with {:ok, adapter_module} <- create_adapter([{:adapter, adapter} | opts]),
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
  @spec create_test_adapter(atom(), keyword()) :: {:ok, module()} | {:error, term()}
  def create_test_adapter(layer, opts \\ []) do
    adapter_name =
      case layer do
        :layer_1 -> :mock
        :layer_2 -> :bridge_mock
        :layer_3 -> :python_port
        _ -> nil
      end

    if adapter_name do
      create_adapter([{:adapter, adapter_name} | opts])
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
        case create_adapter(adapter: name) do
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

  defp validate_adapter(adapter_module, opts) do
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
    case create_adapter(adapter: adapter) do
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
