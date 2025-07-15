defmodule DSPex.EnhancedPoolTestHelpers do
  @moduledoc """
  Enhanced pool test helpers extending existing infrastructure.

  Provides pool-specific testing capabilities that build on:
  - DSPex.PoolV2TestHelpers (existing pool helpers)
  - DSPex.SupervisionTestHelpers (supervision patterns)
  - DSPex.UnifiedTestFoundation (isolation modes)

  Key capabilities:
  - Pool warming with performance monitoring
  - Concurrent pool operation testing
  - Session affinity testing and verification
  - Pool scaling and load testing utilities
  - Pool performance metrics collection
  """

  require Logger

  # Import existing helpers to extend them
  import DSPex.PoolV2TestHelpers
  alias DSPex.PythonBridge.SessionPoolV2

  @doc """
  Sets up an isolated pool with comprehensive monitoring and warmup.

  Extends existing pool helpers with enhanced configuration and monitoring.

  Options:
  - pool_size: Number of workers (default: 4)
  - overflow: Overflow workers (default: 2) 
  - worker_module: Worker module to use (default: PoolWorkerV2Enhanced)
  - pre_warm: Whether to pre-warm workers (default: true)
  - performance_monitoring: Enable performance monitoring (default: true)
  - session_affinity: Enable session affinity (default: true)
  """
  @spec setup_isolated_pool(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def setup_isolated_pool(pool_name, opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, 4)
    overflow = Keyword.get(opts, :overflow, 2)
    worker_module = Keyword.get(opts, :worker_module, DSPex.PythonBridge.PoolWorkerV2Enhanced)
    pre_warm = Keyword.get(opts, :pre_warm, true)
    performance_monitoring = Keyword.get(opts, :performance_monitoring, true)
    session_affinity = Keyword.get(opts, :session_affinity, true)

    # Use existing pool helper as base, extend with enhanced options
    pool_opts = [
      pool_size: pool_size,
      overflow: overflow,
      pre_warm: pre_warm,
      name_prefix: Atom.to_string(pool_name)
    ]

    case start_test_pool(pool_opts) do
      %{pool_pid: _pool_pid} = pool_info ->
        # Enhance with performance monitoring
        performance_context =
          if performance_monitoring do
            setup_performance_monitoring(pool_info)
          else
            %{}
          end

        # Enhance with session affinity testing
        session_context =
          if session_affinity do
            setup_session_affinity_testing(pool_info)
          else
            %{}
          end

        enhanced_info =
          Map.merge(pool_info, %{
            worker_module: worker_module,
            performance_monitoring: performance_monitoring,
            session_affinity: session_affinity,
            performance_context: performance_context,
            session_context: session_context
          })

        {:ok, enhanced_info}

      error ->
        error
    end
  end

  @doc """
  Warms pool workers with parallel initialization and performance tracking.

  Extends existing pre_warm_pool/2 with performance metrics and verification.
  """
  @spec warm_pool_workers(atom(), integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def warm_pool_workers(pool_name, worker_count, opts \\ []) do
    _timeout = Keyword.get(opts, :timeout, 60_000)
    track_performance = Keyword.get(opts, :track_performance, true)

    start_time = if track_performance, do: :erlang.monotonic_time(:microsecond), else: nil

    # Use existing pre_warm_pool implementation
    case pre_warm_pool(pool_name, worker_count) do
      :ok ->
        warmup_time =
          if track_performance do
            # Convert to ms
            (:erlang.monotonic_time(:microsecond) - start_time) / 1000
          else
            nil
          end

        # Verify all workers are healthy
        case verify_pool_health(pool_name, worker_count) do
          {:ok, health_stats} ->
            result = %{
              workers_created: worker_count,
              warmup_time_ms: warmup_time,
              health_stats: health_stats
            }

            {:ok, result}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Tests concurrent operations with performance tracking and verification.

  Extends existing concurrent operation testing with enhanced monitoring.
  """
  @spec test_concurrent_operations(map(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def test_concurrent_operations(_pool_info, operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    track_performance = Keyword.get(opts, :track_performance, true)
    verify_parallelism = Keyword.get(opts, :verify_parallelism, true)

    Logger.info("Testing #{length(operations)} concurrent operations")

    # Wrap operations with performance tracking if requested
    instrumented_operations =
      if track_performance do
        Enum.map(operations, fn operation ->
          fn ->
            start_time = :erlang.monotonic_time(:microsecond)
            result = operation.()
            end_time = :erlang.monotonic_time(:microsecond)
            duration_ms = (end_time - start_time) / 1000
            {result, duration_ms}
          end
        end)
      else
        operations
      end

    start_time = :erlang.monotonic_time(:microsecond)

    # Use existing concurrent operation runner
    results = run_concurrent_operations(instrumented_operations, timeout)

    total_time = (:erlang.monotonic_time(:microsecond) - start_time) / 1000

    # Extract performance data if tracking
    {operation_results, durations} =
      if track_performance do
        Enum.unzip(results)
      else
        {results, []}
      end

    # Verify concurrent execution if requested
    parallelism_result =
      if verify_parallelism and track_performance do
        verify_concurrent_execution(durations)
      else
        {:ok, %{}}
      end

    case parallelism_result do
      {:ok, parallelism_stats} ->
        success_count =
          Enum.count(operation_results, fn
            {:ok, _} -> true
            _ -> false
          end)

        final_result = %{
          total_operations: length(operations),
          successful_operations: success_count,
          total_time_ms: total_time,
          individual_durations: durations,
          parallelism_stats: parallelism_stats,
          operation_results: operation_results
        }

        Logger.info(
          "Concurrent operations completed: #{success_count}/#{length(operations)} successful"
        )

        {:ok, final_result}

      error ->
        error
    end
  end

  @doc """
  Verifies session affinity behavior and tracking.

  Tests that sessions are consistently routed to the same workers.
  """
  @spec verify_session_affinity(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify_session_affinity(pool_info, opts \\ []) do
    session_count = Keyword.get(opts, :session_count, 5)
    operations_per_session = Keyword.get(opts, :operations_per_session, 3)

    Logger.info(
      "Verifying session affinity for #{session_count} sessions, #{operations_per_session} ops each"
    )

    # Create test sessions
    session_ids =
      for i <- 1..session_count do
        "test_session_#{i}_#{:erlang.unique_integer([:positive])}"
      end

    # Track worker assignments per session
    _session_workers = %{}

    # Test each session multiple times
    session_results =
      for session_id <- session_ids do
        worker_ids =
          for _op <- 1..operations_per_session do
            case SessionPoolV2.execute_in_session(
                   session_id,
                   :ping,
                   %{test: "affinity"},
                   pool_name: pool_info.actual_pool_name,
                   timeout: 5000
                 ) do
              {:ok, response} ->
                response["worker_id"]

              error ->
                Logger.warning("Session operation failed: #{inspect(error)}")
                nil
            end
          end

        # Filter out failed operations
        valid_worker_ids = Enum.filter(worker_ids, &(&1 != nil))

        # Check if all operations used the same worker
        unique_workers = Enum.uniq(valid_worker_ids)
        affinity_maintained = length(unique_workers) == 1

        %{
          session_id: session_id,
          worker_ids: valid_worker_ids,
          unique_workers: unique_workers,
          affinity_maintained: affinity_maintained,
          success_rate: length(valid_worker_ids) / operations_per_session
        }
      end

    # Calculate overall affinity metrics
    successful_sessions = Enum.count(session_results, & &1.affinity_maintained)
    affinity_success_rate = successful_sessions / session_count

    overall_success_rate =
      session_results
      |> Enum.map(& &1.success_rate)
      |> Enum.sum()
      |> Kernel./(session_count)

    result = %{
      session_count: session_count,
      operations_per_session: operations_per_session,
      successful_sessions: successful_sessions,
      affinity_success_rate: affinity_success_rate,
      overall_success_rate: overall_success_rate,
      session_results: session_results
    }

    Logger.info(
      "Session affinity verification: #{successful_sessions}/#{session_count} sessions maintained affinity"
    )

    {:ok, result}
  end

  @doc """
  Monitors pool performance during operations.

  Collects comprehensive metrics about pool behavior and performance.
  """
  @spec monitor_pool_performance(map(), keyword()) :: {:ok, map()}
  def monitor_pool_performance(pool_info, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration_ms, 10_000)
    sample_interval_ms = Keyword.get(opts, :sample_interval_ms, 1000)

    Logger.info("Monitoring pool performance for #{duration_ms}ms")

    start_time = :erlang.monotonic_time(:millisecond)
    end_time = start_time + duration_ms

    # Collect performance samples
    samples = collect_performance_samples(pool_info, start_time, end_time, sample_interval_ms, [])

    # Calculate performance statistics
    stats = calculate_performance_stats(samples)

    result = %{
      monitoring_duration_ms: duration_ms,
      sample_count: length(samples),
      sample_interval_ms: sample_interval_ms,
      performance_stats: stats,
      raw_samples: samples
    }

    Logger.info("Pool performance monitoring completed: #{length(samples)} samples collected")
    {:ok, result}
  end

  ## Private Helper Functions

  defp setup_performance_monitoring(pool_info) do
    %{
      monitoring_enabled: true,
      start_time: :erlang.monotonic_time(:microsecond),
      pool_info: pool_info
    }
  end

  defp setup_session_affinity_testing(pool_info) do
    %{
      affinity_testing_enabled: true,
      test_sessions: [],
      pool_info: pool_info
    }
  end

  defp verify_pool_health(pool_name, expected_workers) do
    try do
      # Use the pool_name directly as it should be the GenServer name
      status = SessionPoolV2.get_pool_status(pool_name)

      health_stats = %{
        pool_size: status.pool_size,
        active_sessions: status.active_sessions,
        available_workers: status.pool_size - status.active_sessions,
        workers_match_expected: status.pool_size == expected_workers
      }

      if health_stats.workers_match_expected do
        {:ok, health_stats}
      else
        {:error, {:worker_count_mismatch, health_stats}}
      end
    catch
      error -> {:error, {:health_check_failed, error}}
    end
  end

  defp collect_performance_samples(pool_info, start_time, end_time, interval_ms, acc) do
    current_time = :erlang.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(acc)
    else
      # Collect current performance sample
      sample = collect_single_performance_sample(pool_info, current_time)

      # Wait for next sample interval
      :timer.sleep(interval_ms)

      collect_performance_samples(pool_info, start_time, end_time, interval_ms, [sample | acc])
    end
  end

  defp collect_single_performance_sample(pool_info, timestamp) do
    try do
      # Use the pool_name (GenServer name) instead of actual_pool_name (NimblePool name)
      genserver_name = Map.get(pool_info, :pool_name, pool_info.actual_pool_name)
      status = SessionPoolV2.get_pool_status(genserver_name)

      %{
        timestamp: timestamp,
        pool_size: status.pool_size,
        active_sessions: status.active_sessions,
        available_workers: status.pool_size - status.active_sessions,
        utilization:
          if(status.pool_size > 0, do: status.active_sessions / status.pool_size, else: 0)
      }
    catch
      _error ->
        %{
          timestamp: timestamp,
          error: "sample_collection_failed"
        }
    end
  end

  defp calculate_performance_stats(samples) do
    valid_samples =
      Enum.filter(samples, fn sample ->
        not Map.has_key?(sample, :error)
      end)

    if Enum.empty?(valid_samples) do
      %{error: "no_valid_samples"}
    else
      utilizations = Enum.map(valid_samples, & &1.utilization)
      active_sessions = Enum.map(valid_samples, & &1.active_sessions)

      %{
        sample_count: length(valid_samples),
        avg_utilization: Enum.sum(utilizations) / length(utilizations),
        max_utilization: Enum.max(utilizations),
        min_utilization: Enum.min(utilizations),
        avg_active_sessions: Enum.sum(active_sessions) / length(active_sessions),
        max_active_sessions: Enum.max(active_sessions),
        min_active_sessions: Enum.min(active_sessions)
      }
    end
  end
end
