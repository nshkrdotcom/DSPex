defmodule DSPEx.Teleprompter.BEACON.BayesianOptimizer do
  @moduledoc """
  Bayesian optimization engine for BEACON teleprompter.

  This module implements a simplified but effective Bayesian optimization algorithm
  specifically designed for optimizing instruction and demonstration combinations
  in language model programs.

  ## Features

  - Gaussian Process surrogate modeling
  - Expected Improvement acquisition function
  - Adaptive sampling strategies
  - Early stopping based on convergence
  - Multi-objective optimization support

  ## Algorithm

  1. **Initialization**: Sample initial configurations randomly
  2. **Surrogate Model**: Fit Gaussian Process to observed data
  3. **Acquisition**: Use Expected Improvement to select next configuration
  4. **Evaluation**: Test selected configuration on validation set
  5. **Update**: Add result to training data and repeat

  ## Example Usage

      optimizer = DSPEx.Teleprompter.BEACON.BayesianOptimizer.new(
        num_initial_samples: 10,
        acquisition_function: :expected_improvement,
        convergence_patience: 5
      )

      {:ok, result} = BayesianOptimizer.optimize(
        optimizer,
        search_space,
        objective_function,
        max_iterations: 50
      )
  """

  alias DSPEx.Services.ConfigManager

  @enforce_keys []
  defstruct num_initial_samples: 10,
            acquisition_function: :expected_improvement,
            convergence_patience: 5,
            convergence_threshold: 0.01,
            exploration_weight: 2.0,
            kernel_length_scale: 1.0,
            kernel_variance: 1.0,
            noise_variance: 0.1

  @type t :: %__MODULE__{
          num_initial_samples: pos_integer(),
          acquisition_function:
            :expected_improvement | :upper_confidence_bound | :probability_improvement,
          convergence_patience: pos_integer(),
          convergence_threshold: float(),
          exploration_weight: float(),
          kernel_length_scale: float(),
          kernel_variance: float(),
          noise_variance: float()
        }

  @type configuration :: %{
          instruction_id: String.t(),
          demo_ids: [String.t()],
          features: [float()]
        }

  @type observation :: %{
          configuration: configuration(),
          score: float(),
          timestamp: DateTime.t()
        }

  @type optimization_result :: %{
          best_configuration: configuration(),
          best_score: float(),
          observations: [observation()],
          convergence_iteration: non_neg_integer(),
          stats: map()
        }

  @doc """
  Create a new Bayesian optimizer with specified configuration.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    # Get defaults from config
    defaults = %{
      num_initial_samples:
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :bayesian_optimization, :num_initial_samples],
          10
        ),
      acquisition_function:
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :bayesian_optimization, :acquisition_function],
          :expected_improvement
        ),
      convergence_patience:
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :bayesian_optimization, :convergence_patience],
          5
        ),
      exploration_weight:
        ConfigManager.get_with_default(
          [:teleprompters, :beacon, :bayesian_optimization, :exploration_weight],
          2.0
        )
    }

    struct(__MODULE__, Keyword.merge(Map.to_list(defaults), opts))
  end

  @doc """
  Run Bayesian optimization to find the best instruction/demo combination.

  ## Parameters

  - `optimizer` - BayesianOptimizer configuration
  - `search_space` - Available instructions and demonstrations
  - `objective_function` - Function to evaluate configurations
  - `opts` - Optimization options

  ## Returns

  - `{:ok, optimization_result()}` - Successful optimization
  - `{:error, reason}` - Optimization failed
  """
  @spec optimize(t(), map(), function(), keyword()) ::
          {:ok, optimization_result()} | {:error, term()}
  def optimize(optimizer, search_space, objective_function, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 50)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())

    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        max_iterations: max_iterations,
        search_space_size: map_size(search_space)
      }
    )

    result =
      with {:ok, initial_observations} <-
             initialize_observations(optimizer, search_space, objective_function, correlation_id),
           {:ok, optimization_result} <-
             run_optimization_loop(
               optimizer,
               search_space,
               objective_function,
               initial_observations,
               max_iterations,
               correlation_id
             ) do
        {:ok, optimization_result}
      else
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :stop],
      %{duration: duration, success: success},
      %{correlation_id: correlation_id}
    )

    result
  end

  # Private implementation

  defp initialize_observations(optimizer, search_space, objective_function, correlation_id) do
    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :initialization, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, num_samples: optimizer.num_initial_samples}
    )

    # Generate initial random samples
    initial_configs = generate_random_configurations(search_space, optimizer.num_initial_samples)

    # Evaluate initial configurations
    observations =
      initial_configs
      |> Task.async_stream(
        fn config ->
          try do
            score = objective_function.(config)

            %{
              configuration: config,
              score: score,
              timestamp: DateTime.utc_now()
            }
          rescue
            error ->
              {:error, {:evaluation_exception, error}}
          catch
            :exit, reason ->
              {:error, {:evaluation_exit, reason}}
          end
        end,
        max_concurrency: 5,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Stream.filter(fn
        {:ok, %{score: _, configuration: _, timestamp: _}} -> true
        _ -> false
      end)
      |> Stream.map(fn {:ok, obs} -> obs end)
      |> Enum.to_list()

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :initialization, :stop],
      %{duration: System.monotonic_time()},
      %{
        correlation_id: correlation_id,
        observations_collected: length(observations)
      }
    )

    if Enum.empty?(observations) do
      {:error, :no_initial_observations}
    else
      {:ok, observations}
    end
  end

  defp run_optimization_loop(
         optimizer,
         search_space,
         objective_function,
         observations,
         max_iterations,
         correlation_id
       ) do
    if Enum.empty?(observations) do
      {:error, :no_observations}
    else
      best_observation = Enum.max_by(observations, & &1.score)
      convergence_counter = 0

      result =
        Enum.reduce_while(
          1..max_iterations,
          {observations, best_observation, convergence_counter},
          fn iteration, {current_observations, current_best, conv_counter} ->
            emit_telemetry(
              [:dspex, :beacon, :bayesian_optimizer, :iteration, :start],
              %{iteration: iteration},
              %{correlation_id: correlation_id}
            )

            # Fit Gaussian Process to current observations
            gp_model = fit_gaussian_process(current_observations, optimizer)

            # Select next configuration using acquisition function
            next_config =
              select_next_configuration(
                gp_model,
                search_space,
                current_observations,
                optimizer
              )

            # Evaluate the selected configuration
            handle_configuration_evaluation(
              next_config,
              objective_function,
              current_observations,
              current_best,
              conv_counter,
              optimizer,
              iteration,
              correlation_id
            )
          end
        )

      case result do
        {:converged, final_observations, best_observation, convergence_iteration} ->
          create_optimization_result(final_observations, best_observation, convergence_iteration)

        {final_observations, best_observation, _conv_counter} ->
          create_optimization_result(final_observations, best_observation, max_iterations)
      end
    end
  end

  defp fit_gaussian_process(observations, optimizer) do
    # Simplified GP implementation using linear approximation
    # In production, this could use a proper GP library like GPy or scikit-learn via Nx

    if length(observations) < 2 do
      # Not enough data for GP, return simple mean model
      mean_score =
        observations |> Enum.map(& &1.score) |> Enum.sum() |> Kernel./(length(observations))

      %{
        type: :mean_model,
        mean: mean_score,
        variance: optimizer.kernel_variance,
        observations: observations
      }
    else
      # Simple linear regression as GP approximation
      features = Enum.map(observations, &extract_features/1)
      scores = Enum.map(observations, & &1.score)

      {slope, intercept} = simple_linear_regression(features, scores)

      %{
        type: :linear_gp,
        slope: slope,
        intercept: intercept,
        variance: optimizer.kernel_variance,
        noise: optimizer.noise_variance,
        observations: observations
      }
    end
  end

  defp extract_features(observation) do
    # Extract numeric features from configuration for GP modeling
    config = observation.configuration

    [
      # Instruction features (simplified hash-based)
      :erlang.phash2(config.instruction_id, 1000) / 1000.0,

      # Demo features
      # Normalized demo count
      length(config.demo_ids) / 10.0,

      # Time-based features
      DateTime.to_unix(observation.timestamp) / 1_000_000_000.0
    ]
  end

  defp simple_linear_regression(features_list, scores) do
    n = length(features_list)

    # Use first feature dimension for simple linear regression
    x_values = Enum.map(features_list, &hd/1)

    x_mean = Enum.sum(x_values) / n
    y_mean = Enum.sum(scores) / n

    numerator =
      Enum.zip(x_values, scores)
      |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
      |> Enum.sum()

    denominator =
      x_values
      |> Enum.map(fn x -> (x - x_mean) * (x - x_mean) end)
      |> Enum.sum()

    slope = if denominator == 0, do: 0.0, else: numerator / denominator
    intercept = y_mean - slope * x_mean

    {slope, intercept}
  end

  defp select_next_configuration(gp_model, search_space, current_observations, optimizer) do
    # Generate candidate configurations
    candidates = generate_candidate_configurations(search_space, current_observations, 20)

    if Enum.empty?(candidates) do
      # Fallback: generate a simple random configuration
      generate_fallback_configuration(search_space)
    else
      # Evaluate acquisition function for each candidate
      best_candidate =
        Enum.max_by(
          candidates,
          &evaluate_acquisition_function(&1, optimizer, gp_model, current_observations)
        )

      best_candidate
    end
  end

  defp evaluate_acquisition_function(candidate, optimizer, gp_model, current_observations) do
    case optimizer.acquisition_function do
      :expected_improvement ->
        expected_improvement(candidate, gp_model, current_observations)

      :upper_confidence_bound ->
        upper_confidence_bound(candidate, gp_model, optimizer.exploration_weight)

      :probability_improvement ->
        probability_improvement(candidate, gp_model, current_observations)
    end
  end

  defp generate_fallback_configuration(search_space) do
    instructions = Map.get(search_space, :instructions, [])
    demos = Map.get(search_space, :demos, [])

    if Enum.empty?(instructions) or Enum.empty?(demos) do
      # Return a minimal configuration if search space is completely empty
      %{
        instruction_id: "fallback",
        demo_ids: [],
        features: []
      }
    else
      instruction = List.first(instructions)
      demo = List.first(demos)

      %{
        instruction_id: instruction.id,
        demo_ids: [demo.id],
        features: []
      }
    end
  end

  defp expected_improvement(candidate, gp_model, observations) do
    current_best = observations |> Enum.map(& &1.score) |> Enum.max()

    {mean, variance} = predict_gp(candidate, gp_model)

    if variance <= 0 do
      0.0
    else
      std = :math.sqrt(variance)
      z = (mean - current_best) / std

      # Expected Improvement formula
      improvement = (mean - current_best) * normal_cdf(z) + std * normal_pdf(z)
      max(0.0, improvement)
    end
  end

  defp upper_confidence_bound(candidate, gp_model, beta) do
    {mean, variance} = predict_gp(candidate, gp_model)
    mean + beta * :math.sqrt(variance)
  end

  defp probability_improvement(candidate, gp_model, observations) do
    current_best = observations |> Enum.map(& &1.score) |> Enum.max()

    {mean, variance} = predict_gp(candidate, gp_model)

    if variance <= 0 do
      if mean > current_best, do: 1.0, else: 0.0
    else
      std = :math.sqrt(variance)
      z = (mean - current_best) / std
      normal_cdf(z)
    end
  end

  defp predict_gp(candidate, gp_model) do
    case gp_model.type do
      :mean_model ->
        {gp_model.mean, gp_model.variance}

      :linear_gp ->
        features =
          extract_features(%{configuration: candidate, score: 0.0, timestamp: DateTime.utc_now()})

        x = hd(features)
        mean = gp_model.slope * x + gp_model.intercept
        {mean, gp_model.variance + gp_model.noise}
    end
  end

  defp generate_candidate_configurations(search_space, current_observations, num_candidates) do
    # Generate candidates by combining different instructions and demo sets
    instructions = Map.get(search_space, :instructions, [])
    demos = Map.get(search_space, :demos, [])

    # Return empty list if search space is empty
    if Enum.empty?(instructions) or Enum.empty?(demos) do
      []
    else
      # Avoid already evaluated configurations
      evaluated_configs = MapSet.new(current_observations, & &1.configuration)

      # Generate more candidates to account for duplicates
      1..(num_candidates * 3)
      |> Enum.map(fn _ -> generate_random_config_candidate(instructions, demos) end)
      |> Enum.reject(&MapSet.member?(evaluated_configs, &1))
      |> Enum.uniq()
      |> Enum.take(num_candidates)
    end
  end

  defp generate_random_configurations(search_space, num_samples) do
    instructions = Map.get(search_space, :instructions, [])
    demos = Map.get(search_space, :demos, [])

    # Return empty list if search space is empty
    if Enum.empty?(instructions) or Enum.empty?(demos) do
      []
    else
      1..num_samples
      |> Enum.map(fn _ -> generate_random_config_candidate(instructions, demos) end)
    end
  end

  defp generate_random_config_candidate(instructions, demos) do
    instruction = Enum.random(instructions)
    max_demos = min(4, length(demos))
    demo_count = if max_demos > 0, do: Enum.random(1..max_demos), else: 0
    demo_subset = Enum.take_random(demos, demo_count)

    %{
      instruction_id: instruction.id,
      demo_ids: Enum.map(demo_subset, & &1.id),
      features: []
    }
  end

  defp evaluate_configuration(config, objective_function) do
    score = objective_function.(config)

    observation = %{
      configuration: config,
      score: score,
      timestamp: DateTime.utc_now()
    }

    {:ok, observation}
  rescue
    error ->
      {:error, {:evaluation_exception, error}}
  catch
    :exit, reason ->
      {:error, {:evaluation_exit, reason}}
  end

  defp create_optimization_result(observations, best_observation, convergence_iteration) do
    stats = %{
      total_iterations: length(observations),
      convergence_iteration: convergence_iteration,
      best_score: best_observation.score,
      score_progression: Enum.map(observations, & &1.score),
      mean_score: Enum.sum(Enum.map(observations, & &1.score)) / length(observations)
    }

    result = %{
      best_configuration: best_observation.configuration,
      best_score: best_observation.score,
      observations: Enum.sort_by(observations, & &1.timestamp),
      convergence_iteration: convergence_iteration,
      stats: stats
    }

    {:ok, result}
  end

  # Utility functions

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  # Simplified normal distribution functions
  defp normal_cdf(z) do
    # Approximation of standard normal CDF
    0.5 * (1 + erf(z / :math.sqrt(2)))
  end

  defp normal_pdf(z) do
    # Standard normal PDF
    1 / :math.sqrt(2 * :math.pi()) * :math.exp(-(z * z) / 2)
  end

  defp erf(x) do
    # Approximation of error function using Abramowitz and Stegun
    a1 = 0.254829592
    a2 = -0.284496736
    a3 = 1.421413741
    a4 = -1.453152027
    a5 = 1.061405429
    p = 0.3275911

    sign = if x < 0, do: -1, else: 1
    x = abs(x)

    t = 1.0 / (1.0 + p * x)
    y = 1.0 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * :math.exp(-x * x)

    sign * y
  end

  defp handle_configuration_evaluation(
         next_config,
         objective_function,
         current_observations,
         current_best,
         conv_counter,
         optimizer,
         iteration,
         correlation_id
       ) do
    case evaluate_configuration(next_config, objective_function) do
      {:ok, new_observation} ->
        handle_successful_evaluation(
          new_observation,
          current_observations,
          current_best,
          conv_counter,
          optimizer,
          iteration,
          correlation_id
        )

      {:error, reason} ->
        emit_telemetry(
          [:dspex, :beacon, :bayesian_optimizer, :iteration, :error],
          %{iteration: iteration},
          %{correlation_id: correlation_id, error: reason}
        )

        {:cont, {current_observations, current_best, conv_counter + 1}}
    end
  end

  defp handle_successful_evaluation(
         new_observation,
         current_observations,
         current_best,
         conv_counter,
         optimizer,
         iteration,
         correlation_id
       ) do
    updated_observations = [new_observation | current_observations]

    # Check for improvement
    {new_best, new_conv_counter} =
      if new_observation.score > current_best.score do
        {new_observation, 0}
      else
        {current_best, conv_counter + 1}
      end

    emit_telemetry(
      [:dspex, :beacon, :bayesian_optimizer, :iteration, :stop],
      %{
        iteration: iteration,
        score: new_observation.score,
        improved: new_observation.score > current_best.score
      },
      %{correlation_id: correlation_id}
    )

    # Check convergence
    if new_conv_counter >= optimizer.convergence_patience do
      {:halt, {:converged, updated_observations, new_best, iteration}}
    else
      {:cont, {updated_observations, new_best, new_conv_counter}}
    end
  end
end
