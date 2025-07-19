defmodule DSPEx.Services.TelemetrySetup do
  @moduledoc """
  Sets up DSPEx-specific telemetry handlers and metrics using Foundation's telemetry system.
  """

  use GenServer
  require Logger

  @doc """
  Starts the telemetry setup service.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the telemetry setup service.
  """
  @impl GenServer
  @spec init(term()) :: {:ok, map()}
  def init(_opts) do
    # Wait for Foundation to be ready
    :ok = wait_for_foundation()

    # Set up DSPEx telemetry
    setup_dspex_telemetry()

    # Register with Foundation's service registry using a valid service name
    # Use :telemetry_service as it's in the allowed list
    :ok = Foundation.ServiceRegistry.register(:production, :telemetry_service, self())

    {:ok, %{telemetry_active: true, handlers_attached: true}}
  end

  @spec wait_for_foundation() :: :ok
  defp wait_for_foundation do
    case Foundation.available?() do
      true ->
        :ok

      false ->
        Process.sleep(100)
        wait_for_foundation()
    end
  end

  @spec setup_dspex_telemetry() :: :ok
  defp setup_dspex_telemetry do
    # Define DSPEx-specific telemetry events
    events = [
      [:dspex, :predict, :start],
      [:dspex, :predict, :stop],
      [:dspex, :predict, :exception],
      [:dspex, :client, :request, :start],
      [:dspex, :client, :request, :stop],
      [:dspex, :client, :request, :exception],
      [:dspex, :adapter, :format, :start],
      [:dspex, :adapter, :format, :stop],
      [:dspex, :adapter, :parse, :start],
      [:dspex, :adapter, :parse, :stop],
      [:dspex, :signature, :validation, :start],
      [:dspex, :signature, :validation, :stop],
      [:dspex, :program, :forward, :start],
      [:dspex, :program, :forward, :stop],
      [:dspex, :teleprompter, :bootstrap, :start],
      [:dspex, :teleprompter, :bootstrap, :stop],
      # BEACON-specific telemetry events
      [:dspex, :teleprompter, :beacon, :start],
      [:dspex, :teleprompter, :beacon, :stop],
      [:dspex, :teleprompter, :beacon, :optimization, :start],
      [:dspex, :teleprompter, :beacon, :optimization, :stop],
      [:dspex, :teleprompter, :beacon, :instruction, :start],
      [:dspex, :teleprompter, :beacon, :instruction, :stop],
      [:dspex, :teleprompter, :beacon, :trial, :start],
      [:dspex, :teleprompter, :beacon, :trial, :stop],
      [:dspex, :teleprompter, :beacon, :bayesian, :iteration, :start],
      [:dspex, :teleprompter, :beacon, :bayesian, :iteration, :stop]
    ]

    # Attach Foundation's telemetry handlers
    Foundation.Telemetry.attach_handlers(events)

    # Set up custom DSPEx handlers
    :telemetry.attach_many(
      "dspex-telemetry-handlers",
      events,
      &__MODULE__.handle_dspex_event/4,
      %{}
    )

    Logger.info("DSPEx telemetry setup complete")
    :ok
  end

  @impl GenServer
  @spec handle_info(term(), map()) :: {:noreply, map()}
  def handle_info(:prepare_for_shutdown, state) do
    Logger.debug("DSPEx Telemetry: Preparing for graceful shutdown")

    # Detach our telemetry handlers to prevent race conditions
    graceful_detach_handlers()

    {:noreply, %{state | telemetry_active: false, handlers_attached: false}}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec graceful_detach_handlers() :: :ok
  defp graceful_detach_handlers do
    :telemetry.detach("dspex-telemetry-handlers")
    Logger.debug("DSPEx Telemetry: Handlers detached successfully")
    :ok
  rescue
    error ->
      Logger.debug(
        "DSPEx Telemetry: Handler detach failed (expected during shutdown): #{inspect(error)}"
      )

      :ok
  end

  @impl GenServer
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, state) do
    if state[:handlers_attached] do
      graceful_detach_handlers()
    end

    :ok
  end

  @doc """
  Handles DSPEx telemetry events.

  Foundation has been proven stable and reliable, so we can trust it without
  extensive defensive programming.
  """
  @spec handle_dspex_event(list(atom()), map(), map(), map()) :: :ok
  def handle_dspex_event(event, measurements, metadata, config) do
    # Simple Foundation availability check - no complex error handling needed
    if Foundation.available?() do
      do_handle_dspex_event(event, measurements, metadata, config)
    end

    :ok
  end

  # Handle specific DSPEx telemetry events
  defp do_handle_dspex_event([:dspex, :predict, :stop], measurements, metadata, _config) do
    # Track prediction performance with Foundation telemetry (v0.1.2 has emit_histogram)
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :prediction_duration],
      measurements.duration,
      %{
        signature: metadata[:signature],
        provider: metadata[:provider],
        success: measurements[:success] || true
      }
    )

    # Track prediction success/failure
    status = if measurements[:success] != false, do: "success", else: "error"

    Foundation.Telemetry.emit_counter(
      [:dspex, :predictions, :total],
      %{
        signature: metadata[:signature],
        provider: metadata[:provider],
        status: status
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :client, :request, :stop], measurements, metadata, _config) do
    # Track client request performance with Foundation telemetry (v0.1.2 has emit_histogram)
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :client_request_duration],
      measurements.duration,
      %{
        provider: metadata[:provider],
        model: metadata[:model],
        success: measurements[:success] || true
      }
    )

    # Track token usage if available
    if token_usage = metadata[:token_usage] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :usage, :tokens_consumed],
        token_usage[:total] || token_usage[:input] + token_usage[:output],
        %{
          provider: metadata[:provider],
          model: metadata[:model],
          type: "total"
        }
      )

      if input_tokens = token_usage[:input] do
        Foundation.Telemetry.emit_gauge(
          [:dspex, :usage, :tokens_consumed],
          input_tokens,
          %{
            provider: metadata[:provider],
            model: metadata[:model],
            type: "input"
          }
        )
      end

      if output_tokens = token_usage[:output] do
        Foundation.Telemetry.emit_gauge(
          [:dspex, :usage, :tokens_consumed],
          output_tokens,
          %{
            provider: metadata[:provider],
            model: metadata[:model],
            type: "output"
          }
        )
      end
    end

    # Track API costs if available
    if cost = metadata[:cost] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :usage, :api_cost],
        cost,
        %{
          provider: metadata[:provider],
          model: metadata[:model]
        }
      )
    end
  end

  defp do_handle_dspex_event([:dspex, :predict, :start], _measurements, metadata, _config) do
    # Track prediction start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :predictions, :started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :predict, :exception], _measurements, metadata, _config) do
    # Track prediction exceptions
    Foundation.Telemetry.emit_counter(
      [:dspex, :errors, :predictions],
      %{
        signature: metadata[:signature],
        error_type: metadata[:error_type] || "unknown",
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :client, :request, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track client request start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :client_requests, :started],
      %{
        provider: metadata[:provider],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :client, :request, :exception],
         _measurements,
         metadata,
         _config
       ) do
    # Track client request failures with Foundation telemetry
    Foundation.Telemetry.emit_counter(
      [:dspex, :errors, :client_requests],
      %{
        provider: metadata[:provider],
        error_type: metadata[:error_type] || "unknown"
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :adapter, :format, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track adapter format start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :adapter, :format_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :parse, :start], _measurements, metadata, _config) do
    # Track adapter parse start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :adapter, :parse_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :signature, :validation, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track signature validation start events
    Foundation.Telemetry.emit_counter(
      [:dspex, :signature, :validation_started],
      %{
        signature: metadata[:signature],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :signature, :validation, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track signature validation performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :signature_validation_duration],
      measurements.duration,
      %{
        signature: metadata[:signature],
        success: measurements[:success] || true
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :format, :stop], measurements, metadata, _config) do
    # Track adapter formatting performance with Foundation telemetry
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :adapter_format_duration],
      measurements.duration,
      %{
        adapter: metadata[:adapter] || "default",
        signature: metadata[:signature]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :adapter, :parse, :stop], measurements, metadata, _config) do
    # Track adapter parsing performance with Foundation telemetry
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :adapter_parse_duration],
      measurements.duration,
      %{
        adapter: metadata[:adapter] || "default",
        signature: metadata[:signature],
        success: measurements[:success] || true
      }
    )
  end

  # BEACON telemetry handlers
  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track BEACON optimization start
    Foundation.Telemetry.emit_counter(
      [:dspex, :beacon, :optimizations_started],
      %{
        correlation_id: metadata[:correlation_id],
        student_type: metadata[:student_type],
        teacher_type: metadata[:teacher_type]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track BEACON optimization completion and performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :beacon_optimization_duration],
      measurements.duration,
      %{
        correlation_id: metadata[:correlation_id],
        success: measurements[:success] || true,
        trials_completed: metadata[:trials_completed]
      }
    )

    Foundation.Telemetry.emit_counter(
      [:dspex, :beacon, :optimizations_completed],
      %{
        status: if(measurements[:success] != false, do: "success", else: "error"),
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :optimization, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track individual optimization trial start
    Foundation.Telemetry.emit_counter(
      [:dspex, :beacon, :trials_started],
      %{
        correlation_id: metadata[:correlation_id],
        trial_number: metadata[:trial_number]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :optimization, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track optimization trial performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :beacon_trial_duration],
      measurements.duration,
      %{
        correlation_id: metadata[:correlation_id],
        trial_number: metadata[:trial_number],
        score: metadata[:score]
      }
    )

    # Track trial score distribution
    if score = metadata[:score] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :beacon, :trial_score],
        score,
        %{
          correlation_id: metadata[:correlation_id],
          trial_number: metadata[:trial_number]
        }
      )
    end
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :instruction, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track instruction generation start
    Foundation.Telemetry.emit_counter(
      [:dspex, :beacon, :instruction_generation_started],
      %{
        correlation_id: metadata[:correlation_id],
        instruction_model: metadata[:instruction_model]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :instruction, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track instruction generation performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :beacon_instruction_generation_duration],
      measurements.duration,
      %{
        correlation_id: metadata[:correlation_id],
        instruction_model: metadata[:instruction_model],
        success: measurements[:success] || true
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :bayesian, :iteration, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track Bayesian optimization iteration start
    Foundation.Telemetry.emit_counter(
      [:dspex, :beacon, :bayesian_iterations_started],
      %{
        correlation_id: metadata[:correlation_id],
        iteration_number: metadata[:iteration_number]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :beacon, :bayesian, :iteration, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track Bayesian optimization iteration performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :beacon_bayesian_iteration_duration],
      measurements.duration,
      %{
        correlation_id: metadata[:correlation_id],
        iteration_number: metadata[:iteration_number],
        acquisition_value: metadata[:acquisition_value]
      }
    )

    # Track acquisition function values for optimization monitoring
    if acquisition_value = metadata[:acquisition_value] do
      Foundation.Telemetry.emit_gauge(
        [:dspex, :beacon, :acquisition_value],
        acquisition_value,
        %{
          correlation_id: metadata[:correlation_id],
          iteration_number: metadata[:iteration_number]
        }
      )
    end
  end

  defp do_handle_dspex_event(
         [:dspex, :program, :forward, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track program forward execution start
    Foundation.Telemetry.emit_counter(
      [:dspex, :program, :forward_started],
      %{
        program: metadata[:program],
        correlation_id: metadata[:correlation_id]
      }
    )
  end

  defp do_handle_dspex_event([:dspex, :program, :forward, :stop], measurements, metadata, _config) do
    # Track program forward execution performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :program_forward_duration],
      measurements.duration,
      %{
        program: metadata[:program],
        correlation_id: metadata[:correlation_id],
        success: measurements[:success] || true,
        was_timeout: metadata[:was_timeout] || false
      }
    )

    # Track timeout events specifically
    if metadata[:was_timeout] do
      Foundation.Telemetry.emit_counter(
        [:dspex, :program, :timeouts],
        %{
          program: metadata[:program],
          timeout_used: metadata[:timeout_used]
        }
      )
    end
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :bootstrap, :start],
         _measurements,
         metadata,
         _config
       ) do
    # Track bootstrap teleprompter start
    Foundation.Telemetry.emit_counter(
      [:dspex, :teleprompter, :bootstrap_started],
      %{
        correlation_id: metadata[:correlation_id],
        student_type: metadata[:student_type]
      }
    )
  end

  defp do_handle_dspex_event(
         [:dspex, :teleprompter, :bootstrap, :stop],
         measurements,
         metadata,
         _config
       ) do
    # Track bootstrap teleprompter performance
    Foundation.Telemetry.emit_histogram(
      [:dspex, :performance, :bootstrap_duration],
      measurements.duration,
      %{
        correlation_id: metadata[:correlation_id],
        success: measurements[:success] || true,
        demos_generated: metadata[:demos_generated]
      }
    )
  end

  defp do_handle_dspex_event(event, _measurements, metadata, _config) do
    # Log unhandled events for debugging
    Logger.debug(
      "Unhandled DSPEx telemetry event: #{inspect(event)}, metadata: #{inspect(metadata)}"
    )
  end

  # Required GenServer callbacks for complete implementation
  @impl GenServer
  def handle_call(_msg, _from, state), do: {:reply, :ok, state}

  @impl GenServer
  def handle_cast(_msg, state), do: {:noreply, state}
end
