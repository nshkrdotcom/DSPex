defmodule DSPEx.Teleprompter.BEACON.ContinuousOptimizer do
  @moduledoc """
  GenServer for continuous program optimization in production environments.

  Provides automated, long-running optimization with quality monitoring,
  adaptive scheduling, and resource management.
  """

  use GenServer

  alias DSPEx.Teleprompter.BEACON.{Integration, Utils}

  # Client API

  @doc """
  Start continuous optimization for a program.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start continuous optimization for a specific program.
  """
  def start_optimization(program, opts \\ []) do
    # ms
    optimization_interval = Keyword.get(opts, :interval_hours, 24) * 3600 * 1000
    # ms
    quality_check_interval = Keyword.get(opts, :check_interval_hours, 6) * 3600 * 1000

    GenServer.start_link(
      __MODULE__,
      %{
        program: program,
        optimization_interval: optimization_interval,
        quality_check_interval: quality_check_interval,
        opts: opts
      },
      name: {:global, {:beacon_continuous_optimizer, program}}
    )
  end

  @doc """
  Get current optimization status.
  """
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Trigger immediate optimization.
  """
  def trigger_optimization(pid) do
    GenServer.cast(pid, :trigger_optimization)
  end

  @doc """
  Update optimization configuration.
  """
  def update_config(pid, new_config) do
    GenServer.call(pid, {:update_config, new_config})
  end

  @doc """
  Stop continuous optimization.
  """
  def stop_optimization(pid) do
    GenServer.call(pid, :stop)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(opts) when is_list(opts) do
    case Keyword.fetch(opts, :program) do
      {:ok, program} ->
        init_with_program(program, opts)

      :error ->
        {:stop, {:missing_required_option, :program}}
    end
  end

  def init(opts) when is_map(opts) do
    case Map.fetch(opts, :program) do
      {:ok, program} ->
        init_with_program_map(program, opts)

      :error ->
        {:stop, {:missing_required_option, :program}}
    end
  end

  defp init_with_program(program, opts) do
    state = %{
      program: program,
      original_program: program,
      optimization_interval: Keyword.get(opts, :optimization_interval, 24 * 3600 * 1000),
      quality_check_interval: Keyword.get(opts, :quality_check_interval, 6 * 3600 * 1000),
      quality_threshold: Keyword.get(opts, :quality_threshold, 0.7),
      trainset: Keyword.get(opts, :trainset, []),
      teacher: Keyword.get(opts, :teacher),
      metric_fn: Keyword.get(opts, :metric_fn),
      last_optimization: DateTime.utc_now(),
      last_quality_check: DateTime.utc_now(),
      optimization_count: 0,
      quality_history: [],
      status: :initialized,
      correlation_id: Utils.generate_correlation_id()
    }

    # Schedule first quality check
    Process.send_after(self(), :quality_check, state.quality_check_interval)

    # Schedule first optimization
    Process.send_after(self(), :optimize, state.optimization_interval)

    IO.puts("🚀 Started continuous optimizer for program (ID: #{state.correlation_id})")

    {:ok, Map.put(state, :status, :running)}
  end

  defp init_with_program_map(program, opts) do
    state = %{
      program: program,
      original_program: program,
      optimization_interval: Map.get(opts, :optimization_interval, 24 * 3600 * 1000),
      quality_check_interval: Map.get(opts, :quality_check_interval, 6 * 3600 * 1000),
      quality_threshold: Map.get(opts, :quality_threshold, 0.7),
      trainset: Map.get(opts, :trainset, []),
      teacher: Map.get(opts, :teacher),
      metric_fn: Map.get(opts, :metric_fn),
      last_optimization: DateTime.utc_now(),
      last_quality_check: DateTime.utc_now(),
      optimization_count: 0,
      quality_history: [],
      status: :initialized,
      correlation_id: Utils.generate_correlation_id()
    }

    # Schedule first quality check
    Process.send_after(self(), :quality_check, state.quality_check_interval)

    # Schedule first optimization
    Process.send_after(self(), :optimize, state.optimization_interval)

    IO.puts("🚀 Started continuous optimizer for program (ID: #{state.correlation_id})")

    {:ok, Map.put(state, :status, :running)}
  end

  @impl GenServer
  def handle_info(:quality_check, state) do
    IO.puts("🔍 Running quality check (ID: #{state.correlation_id})")

    # Assess current program quality
    current_quality = assess_program_quality(state.program, state)

    # Update quality history
    quality_entry = %{
      timestamp: DateTime.utc_now(),
      quality: current_quality,
      optimization_count: state.optimization_count
    }

    updated_quality_history = [quality_entry | Enum.take(state.quality_history, 9)]

    # Determine if immediate optimization is needed
    needs_optimization = should_optimize_immediately?(current_quality, state)

    if needs_optimization do
      IO.puts(
        "⚡ Quality check triggered immediate optimization (quality: #{Float.round(current_quality, 3)})"
      )

      send(self(), :optimize)
    else
      IO.puts("✅ Quality check passed (quality: #{Float.round(current_quality, 3)})")
    end

    # Schedule next quality check
    Process.send_after(self(), :quality_check, state.quality_check_interval)

    new_state = %{
      state
      | last_quality_check: DateTime.utc_now(),
        quality_history: updated_quality_history
    }

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:optimize, state) do
    IO.puts("🎯 Starting scheduled optimization (ID: #{state.correlation_id})")

    new_state = Map.put(state, :status, :optimizing)

    case run_optimization(state) do
      {:ok, optimized_program, improvement_metrics} ->
        updated_state = %{
          new_state
          | program: optimized_program,
            last_optimization: DateTime.utc_now(),
            optimization_count: state.optimization_count + 1,
            status: :running
        }

        IO.puts(
          "✅ Optimization completed (improvement: +#{Float.round(improvement_metrics.improvement_percentage, 1)}%)"
        )

        # Schedule next optimization
        Process.send_after(self(), :optimize, state.optimization_interval)

        {:noreply, updated_state}

      {:error, reason} ->
        IO.puts("❌ Optimization failed: #{inspect(reason)}")

        # Retry with exponential backoff
        # Max 30 minutes
        retry_delay = min(state.optimization_interval, 30 * 60 * 1000)
        Process.send_after(self(), :optimize, retry_delay)

        updated_state = Map.put(new_state, :status, :error)

        {:noreply, updated_state}
    end
  end

  @impl GenServer
  def handle_info(msg, state) do
    IO.puts("⚠️ Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:trigger_optimization, state) do
    IO.puts("🔄 Manual optimization triggered (ID: #{state.correlation_id})")
    send(self(), :optimize)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      correlation_id: state.correlation_id,
      last_optimization: state.last_optimization,
      last_quality_check: state.last_quality_check,
      optimization_count: state.optimization_count,
      current_quality: get_latest_quality(state.quality_history),
      quality_trend: analyze_quality_trend(state.quality_history)
    }

    {:reply, status_info, state}
  end

  @impl GenServer
  def handle_call({:update_config, new_config}, _from, state) do
    updated_state = Map.merge(state, new_config)

    IO.puts("⚙️  Configuration updated (ID: #{state.correlation_id})")

    {:reply, :ok, updated_state}
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    IO.puts("🛑 Stopping continuous optimizer (ID: #{state.correlation_id})")
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    IO.puts(
      "🔚 Continuous optimizer stopped (ID: #{state.correlation_id}, reason: #{inspect(reason)})"
    )

    :ok
  end

  # Private helper functions

  defp assess_program_quality(program, state) do
    # Use a sample of the training set for quality assessment
    sample_size = min(20, length(state.trainset))
    quality_sample = Enum.take_random(state.trainset, sample_size)

    if Enum.empty?(quality_sample) or is_nil(state.metric_fn) do
      # Fallback quality assessment
      assess_fallback_quality(program, state)
    else
      Integration.evaluate_program_quality(program, quality_sample, state.metric_fn)
    end
  end

  defp assess_fallback_quality(_program, state) do
    # Simple heuristic based on time since last optimization
    hours_since_optimization = DateTime.diff(DateTime.utc_now(), state.last_optimization, :hour)

    # Quality degrades over time (simulated)
    base_quality = 0.8
    degradation = min(hours_since_optimization * 0.01, 0.3)

    max(base_quality - degradation, 0.4)
  end

  defp should_optimize_immediately?(current_quality, state) do
    # Check multiple conditions for immediate optimization
    quality_below_threshold = current_quality < state.quality_threshold

    # Check quality trend
    quality_declining = quality_declining?(state.quality_history)

    # Check time since last optimization
    hours_since_optimization = DateTime.diff(DateTime.utc_now(), state.last_optimization, :hour)
    # More than 2 days
    overdue = hours_since_optimization >= 48

    quality_below_threshold or (quality_declining and hours_since_optimization >= 12) or overdue
  end

  defp quality_declining?(quality_history) when length(quality_history) < 3 do
    false
  end

  defp quality_declining?(quality_history) do
    recent_qualities =
      quality_history
      |> Enum.take(3)
      |> Enum.map(& &1.quality)
      |> Enum.reverse()

    case recent_qualities do
      [oldest, middle, newest] ->
        # Check if there's a declining trend
        newest < middle and middle < oldest

      _ ->
        false
    end
  end

  defp run_optimization(state) do
    if is_nil(state.teacher) or is_nil(state.metric_fn) or Enum.empty?(state.trainset) do
      {:error, :insufficient_configuration}
    else
      optimization_opts = [
        correlation_id: "#{state.correlation_id}_opt_#{state.optimization_count + 1}",
        num_candidates: determine_optimization_intensity(state),
        num_trials: determine_trial_count(state),
        quality_threshold: state.quality_threshold
      ]

      case Integration.optimize_for_production(
             state.program,
             state.teacher,
             state.trainset,
             state.metric_fn,
             optimization_opts
           ) do
        {:ok, optimized_program} ->
          validate_and_return_optimization_result(state, optimized_program)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp validate_and_return_optimization_result(state, optimized_program) do
    # Validate improvement
    case Integration.validate_optimization_result(
           state.program,
           optimized_program,
           state.trainset,
           state.metric_fn
         ) do
      {:ok, metrics} ->
        {:ok, optimized_program, metrics}

      {:error, reason} ->
        # If no improvement, return original program
        IO.puts("⚠️  No significant improvement detected: #{inspect(reason)}")
        {:ok, state.program, %{improvement_percentage: 0.0}}
    end
  end

  defp determine_optimization_intensity(state) do
    # Adjust optimization intensity based on quality and history
    base_candidates = 20

    current_quality = get_latest_quality(state.quality_history)

    cond do
      current_quality < 0.5 ->
        # Low quality, use more intensive optimization
        round(base_candidates * 1.5)

      current_quality > 0.8 ->
        # High quality, use lighter optimization
        round(base_candidates * 0.8)

      true ->
        base_candidates
    end
  end

  defp determine_trial_count(state) do
    # Adjust trial count based on optimization history
    base_trials = 40

    # If recent optimizations haven't been successful, increase trials
    recent_failures = count_recent_failures(state.quality_history)

    if recent_failures > 2 do
      round(base_trials * 1.5)
    else
      base_trials
    end
  end

  defp count_recent_failures(quality_history) do
    quality_history
    |> Enum.take(5)
    |> Enum.count(fn entry -> entry.quality < 0.6 end)
  end

  defp get_latest_quality([]), do: 0.5
  defp get_latest_quality([latest | _]), do: latest.quality

  defp analyze_quality_trend(quality_history) when length(quality_history) < 2 do
    :insufficient_data
  end

  defp analyze_quality_trend(quality_history) do
    recent_qualities =
      quality_history
      |> Enum.take(5)
      |> Enum.map(& &1.quality)
      |> Enum.reverse()

    if length(recent_qualities) < 2 do
      :insufficient_data
    else
      # Simple linear trend analysis
      first_half = Enum.take(recent_qualities, div(length(recent_qualities), 2))
      second_half = Enum.drop(recent_qualities, div(length(recent_qualities), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      diff = second_avg - first_avg

      cond do
        diff > 0.05 -> :improving
        diff < -0.05 -> :declining
        true -> :stable
      end
    end
  end
end
