defmodule ElixirML.Variable.MLTypes do
  @moduledoc """
  ML-specific variable types and configurations for ElixirML.

  Provides pre-configured variable types commonly used in machine learning
  applications, including model parameters, provider configurations, and
  optimization hints.
  """

  alias ElixirML.Variable
  alias ElixirML.Variable.Space

  @doc """
  Create a provider variable with model compatibility and cost/performance weights.

  ## Examples

      iex> provider_var = ElixirML.Variable.MLTypes.provider(:llm_provider)
      iex> provider_var.type
      :choice
      iex> :openai in provider_var.constraints.choices
      true
  """
  @spec provider(atom(), keyword()) :: Variable.t()
  def provider(name, opts \\ []) do
    providers = Keyword.get(opts, :providers, [:openai, :anthropic, :groq, :google])

    Variable.choice(name, providers,
      description: "LLM Provider selection",
      hints: [
        optimization_priority: :cost_performance,
        compatibility_aware: true
      ],
      metadata: %{
        cost_weights: %{
          openai: 1.0,
          anthropic: 1.2,
          groq: 0.3,
          google: 0.8
        },
        performance_weights: %{
          openai: 0.9,
          anthropic: 0.95,
          groq: 0.7,
          google: 0.85
        },
        latency_weights: %{
          openai: 0.8,
          anthropic: 0.7,
          groq: 0.95,
          google: 0.8
        }
      }
    )
  end

  @doc """
  Create a model variable with provider-specific model options.

  ## Examples

      iex> model_var = ElixirML.Variable.MLTypes.model(:model, provider: :openai)
      iex> "gpt-4" in model_var.constraints.choices
      true
  """
  @spec model(atom(), keyword()) :: Variable.t()
  def model(name, opts \\ []) do
    provider = Keyword.get(opts, :provider)

    models =
      case provider do
        :openai -> ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]
        :anthropic -> ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
        :groq -> ["llama-3-70b", "mixtral-8x7b", "gemma-7b"]
        :google -> ["gemini-pro", "gemini-pro-vision"]
        _ -> Keyword.get(opts, :models, ["gpt-4"])
      end

    Variable.choice(name, models,
      description: "Model selection for #{provider || "provider"}",
      dependencies: if(provider, do: [], else: [:provider]),
      hints: [
        performance_impact: :high,
        cost_impact: :high
      ],
      metadata: %{
        capabilities: model_capabilities(models),
        context_windows: model_context_windows(models)
      }
    )
  end

  @doc """
  Create an adapter variable with capability awareness.

  ## Examples

      iex> adapter_var = ElixirML.Variable.MLTypes.adapter(:response_adapter)
      iex> adapter_var.type
      :module
  """
  @spec adapter(atom(), keyword()) :: Variable.t()
  def adapter(name, opts \\ []) do
    adapters =
      Keyword.get(opts, :adapters, [
        ElixirML.Adapter.JSON,
        ElixirML.Adapter.Markdown,
        ElixirML.Adapter.Chat,
        ElixirML.Adapter.Structured
      ])

    Variable.module(name,
      modules: adapters,
      behavior: ElixirML.Adapter,
      description: "Response format adapter",
      hints: [
        performance_impact: :medium,
        model_compatibility: true
      ],
      metadata: %{
        output_formats: %{
          ElixirML.Adapter.JSON => :json,
          ElixirML.Adapter.Markdown => :markdown,
          ElixirML.Adapter.Chat => :text,
          ElixirML.Adapter.Structured => :structured
        }
      }
    )
  end

  @doc """
  Create a reasoning strategy variable for automatic strategy selection.

  ## Examples

      iex> reasoning_var = ElixirML.Variable.MLTypes.reasoning_strategy(:reasoning)
      iex> reasoning_var.type
      :module
  """
  @spec reasoning_strategy(atom(), keyword()) :: Variable.t()
  def reasoning_strategy(name, opts \\ []) do
    strategies =
      Keyword.get(opts, :strategies, [
        ElixirML.Reasoning.Predict,
        ElixirML.Reasoning.ChainOfThought,
        ElixirML.Reasoning.ProgramOfThought,
        ElixirML.Reasoning.ReAct,
        ElixirML.Reasoning.SelfConsistency
      ])

    Variable.module(name,
      modules: strategies,
      behavior: ElixirML.Reasoning.Strategy,
      description: "Reasoning strategy selection",
      hints: [
        performance_impact: :high,
        accuracy_impact: :high,
        cost_impact: :high
      ],
      metadata: %{
        complexity_levels: %{
          ElixirML.Reasoning.Predict => 1,
          ElixirML.Reasoning.ChainOfThought => 3,
          ElixirML.Reasoning.ProgramOfThought => 4,
          ElixirML.Reasoning.ReAct => 5,
          ElixirML.Reasoning.SelfConsistency => 6
        },
        token_multipliers: %{
          ElixirML.Reasoning.Predict => 1.0,
          ElixirML.Reasoning.ChainOfThought => 2.5,
          ElixirML.Reasoning.ProgramOfThought => 3.0,
          ElixirML.Reasoning.ReAct => 4.0,
          ElixirML.Reasoning.SelfConsistency => 8.0
        }
      }
    )
  end

  @doc """
  Create a temperature variable with model-specific ranges.

  ## Examples

      iex> temp_var = ElixirML.Variable.MLTypes.temperature(:temperature)
      iex> temp_var.constraints.range
      {0.0, 2.0}
  """
  @spec temperature(atom(), keyword()) :: Variable.t()
  def temperature(name, opts \\ []) do
    range = Keyword.get(opts, :range, {0.0, 2.0})
    default = Keyword.get(opts, :default, 0.7)

    Variable.float(name,
      range: range,
      default: default,
      description: "Sampling temperature for randomness control",
      hints: [
        continuous: true,
        smooth_optimization: true,
        local_search_friendly: true
      ],
      metadata: %{
        effect: "Higher values increase randomness and creativity",
        sweet_spot: {0.3, 1.0},
        extreme_values: %{
          deterministic: 0.0,
          very_creative: 1.5,
          chaotic: 2.0
        }
      }
    )
  end

  @doc """
  Create a max_tokens variable with dynamic ranges based on model.

  ## Examples

      iex> tokens_var = ElixirML.Variable.MLTypes.max_tokens(:max_tokens)
      iex> tokens_var.type
      :integer
  """
  @spec max_tokens(atom(), keyword()) :: Variable.t()
  def max_tokens(name, opts \\ []) do
    range = Keyword.get(opts, :range, {1, 4096})
    default = Keyword.get(opts, :default, 1000)

    Variable.integer(name,
      range: range,
      default: default,
      description: "Maximum tokens to generate",
      dependencies: Keyword.get(opts, :dependencies, [:model]),
      hints: [
        cost_impact: :high,
        performance_impact: :medium
      ],
      metadata: %{
        cost_scaling: :linear,
        typical_ranges: %{
          short_response: {50, 200},
          medium_response: {200, 1000},
          long_response: {1000, 4000}
        }
      }
    )
  end

  @doc """
  Create a top_p variable for nucleus sampling.

  ## Examples

      iex> top_p_var = ElixirML.Variable.MLTypes.top_p(:top_p)
      iex> top_p_var.constraints.range
      {0.0, 1.0}
  """
  @spec top_p(atom(), keyword()) :: Variable.t()
  def top_p(name, opts \\ []) do
    Variable.float(name,
      range: {0.0, 1.0},
      default: Keyword.get(opts, :default, 0.9),
      description: "Nucleus sampling probability threshold",
      hints: [
        continuous: true,
        complementary_to: :temperature
      ],
      metadata: %{
        effect: "Controls diversity by focusing on cumulative probability mass",
        interaction_with_temperature: "Use lower values with higher temperature"
      }
    )
  end

  @doc """
  Create a frequency_penalty variable.
  """
  @spec frequency_penalty(atom(), keyword()) :: Variable.t()
  def frequency_penalty(name, opts \\ []) do
    Variable.float(name,
      range: {-2.0, 2.0},
      default: Keyword.get(opts, :default, 0.0),
      description: "Penalty for token frequency",
      hints: [
        continuous: true,
        fine_tuning_parameter: true
      ]
    )
  end

  @doc """
  Create a presence_penalty variable.
  """
  @spec presence_penalty(atom(), keyword()) :: Variable.t()
  def presence_penalty(name, opts \\ []) do
    Variable.float(name,
      range: {-2.0, 2.0},
      default: Keyword.get(opts, :default, 0.0),
      description: "Penalty for token presence",
      hints: [
        continuous: true,
        fine_tuning_parameter: true
      ]
    )
  end

  @doc """
  Create a comprehensive ML model configuration variable space.

  This creates a complete variable space with all common ML parameters
  and their interdependencies properly configured.

  ## Examples

      iex> space = ElixirML.Variable.MLTypes.standard_ml_config()
      iex> map_size(space.variables) > 5
      true
  """
  @spec standard_ml_config(keyword()) :: Space.t()
  def standard_ml_config(opts \\ []) do
    space =
      Space.new(
        name: Keyword.get(opts, :name, "Standard ML Configuration"),
        metadata: %{
          version: "1.0",
          description: "Standard ML model configuration with common parameters"
        }
      )

    # Core variables
    variables = [
      provider(:provider),
      model(:model, dependencies: [:provider]),
      temperature(:temperature),
      max_tokens(:max_tokens, dependencies: [:model]),
      top_p(:top_p),
      reasoning_strategy(:reasoning_strategy),
      adapter(:adapter)
    ]

    # Add optional variables based on options
    variables =
      if Keyword.get(opts, :include_penalties, false) do
        variables ++
          [
            frequency_penalty(:frequency_penalty),
            presence_penalty(:presence_penalty)
          ]
      else
        variables
      end

    space = Space.add_variables(space, variables)

    # Add cross-variable constraints
    space
    |> Space.add_constraint(&validate_provider_model_compatibility/1)
    |> Space.add_constraint(&validate_token_limits/1)
    |> Space.add_constraint(&validate_temperature_top_p_interaction/1)
  end

  @doc """
  Extract variables from a signature module with ML-specific enhancements.
  """
  @spec extract_from_signature(module()) :: Space.t()
  def extract_from_signature(signature_module) do
    base_space = Space.from_signature(signature_module)

    # Enhance with ML-specific variables
    enhanced_variables = [
      provider(:provider),
      adapter(:adapter),
      reasoning_strategy(:reasoning_strategy),
      temperature(:temperature, range: {0.0, 2.0}, default: 0.7)
    ]

    Space.add_variables(base_space, enhanced_variables)
  end

  # Private helper functions

  @spec model_capabilities([String.t()]) :: %{String.t() => [atom()]}
  defp model_capabilities(models) do
    Enum.reduce(models, %{}, fn model, acc ->
      capabilities =
        case model do
          "gpt-4" -> [:text, :reasoning, :code, :math]
          "gpt-4-turbo" -> [:text, :reasoning, :code, :math, :vision]
          "claude-3-opus" -> [:text, :reasoning, :code, :analysis]
          "llama-3-70b" -> [:text, :reasoning, :code]
          "gemini-pro" -> [:text, :reasoning, :code, :multimodal]
          _ -> [:text]
        end

      Map.put(acc, model, capabilities)
    end)
  end

  @spec model_context_windows([String.t()]) :: %{String.t() => pos_integer()}
  defp model_context_windows(models) do
    Enum.reduce(models, %{}, fn model, acc ->
      context_window =
        case model do
          "gpt-4" -> 8192
          "gpt-4-turbo" -> 128_000
          "claude-3-opus" -> 200_000
          "llama-3-70b" -> 8192
          "gemini-pro" -> 32_768
          _ -> 4096
        end

      Map.put(acc, model, context_window)
    end)
  end

  # Cross-variable constraint validators

  @spec validate_provider_model_compatibility(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_provider_model_compatibility(config) do
    case {config[:provider], config[:model]} do
      {:openai, model} when model in ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"] ->
        {:ok, config}

      {:anthropic, model} when model in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"] ->
        {:ok, config}

      {:groq, model} when model in ["llama-3-70b", "mixtral-8x7b", "gemma-7b"] ->
        {:ok, config}

      {:google, model} when model in ["gemini-pro", "gemini-pro-vision"] ->
        {:ok, config}

      # No provider specified
      {nil, _} ->
        {:ok, config}

      # No model specified
      {_, nil} ->
        {:ok, config}

      {provider, model} ->
        {:error, "Model #{model} not compatible with provider #{provider}"}
    end
  end

  @spec validate_token_limits(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_token_limits(config) do
    max_tokens = config[:max_tokens]
    model = config[:model]

    if max_tokens && model do
      context_window =
        case model do
          "gpt-4" -> 8192
          "gpt-4-turbo" -> 128_000
          "claude-3-opus" -> 200_000
          _ -> 4096
        end

      if max_tokens > context_window do
        {:error,
         "max_tokens #{max_tokens} exceeds context window #{context_window} for model #{model}"}
      else
        {:ok, config}
      end
    else
      {:ok, config}
    end
  end

  @spec validate_temperature_top_p_interaction(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_temperature_top_p_interaction(config) do
    temp = config[:temperature]
    top_p = config[:top_p]

    if temp && top_p && temp > 1.5 && top_p < 0.3 do
      {:error, "High temperature (#{temp}) with low top_p (#{top_p}) may produce poor results"}
    else
      {:ok, config}
    end
  end

  @doc """
  Creates an embedding variable with specified dimensions.
  Based on Elixact patterns for vector embeddings.
  """
  @spec embedding(atom(), keyword()) :: Variable.t()
  def embedding(name, opts \\ []) do
    dimensions = Keyword.get(opts, :dimensions, 1536)

    Variable.composite(name,
      description: "Embedding vector with #{dimensions} dimensions",
      default: List.duplicate(0.0, dimensions),
      compute: fn _config -> List.duplicate(0.0, dimensions) end,
      metadata: %{
        ml_type: :embedding,
        dimensions: dimensions,
        normalization: :l2,
        range: {-1.0, 1.0},
        vector_norm: :l2
      }
    )
  end

  @doc """
  Creates a probability variable with proper range constraints.
  Enhanced from basic probability type.
  """
  @spec probability(atom(), keyword()) :: Variable.t()
  def probability(name, opts \\ []) do
    Variable.float(name,
      range: {0.0, 1.0},
      default: 0.5,
      precision: Keyword.get(opts, :precision, 0.001),
      description: "Probability value between 0.0 and 1.0",
      metadata: %{
        ml_type: :probability,
        statistical_type: :continuous
      }
    )
  end

  @doc """
  Creates a confidence score variable.
  Based on Elixact confidence estimation patterns.
  """
  @spec confidence_score(atom(), keyword()) :: Variable.t()
  def confidence_score(name, opts \\ []) do
    Variable.float(name,
      range: {0.0, 1.0},
      default: 0.5,
      description: "Confidence score for model predictions",
      metadata: %{
        ml_type: :confidence,
        calibration_method: Keyword.get(opts, :calibration, :platt_scaling)
      }
    )
  end

  @doc """
  Creates a token count variable for LLM operations.
  Based on Elixact token management patterns.
  """
  @spec token_count(atom(), keyword()) :: Variable.t()
  def token_count(name, opts \\ []) do
    max_tokens = Keyword.get(opts, :max, 4096)

    Variable.integer(name,
      range: {1, max_tokens},
      default: 100,
      description: "Token count for LLM operations",
      metadata: %{
        ml_type: :token_count,
        max_tokens: max_tokens,
        tokenizer: Keyword.get(opts, :tokenizer, :tiktoken)
      }
    )
  end

  @doc """
  Creates a cost estimation variable for LLM operations.
  Based on Elixact cost optimization patterns.
  """
  @spec cost_estimate(atom(), keyword()) :: Variable.t()
  def cost_estimate(name, opts \\ []) do
    currency = Keyword.get(opts, :currency, :usd)
    scaling = Keyword.get(opts, :scaling, :linear)

    Variable.float(name,
      range: {0.0, 1000.0},
      default: 0.01,
      precision: 0.0001,
      description: "Cost estimation for LLM operations",
      metadata: %{
        ml_type: :cost,
        currency: currency,
        scaling: scaling,
        cost_model: :token_based
      }
    )
  end

  @doc """
  Creates a latency estimation variable.
  Based on Sinter performance patterns.
  """
  @spec latency_estimate(atom(), keyword()) :: Variable.t()
  def latency_estimate(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30.0)

    Variable.float(name,
      range: {0.001, timeout},
      default: 1.0,
      description: "Latency estimation in seconds",
      metadata: %{
        ml_type: :latency,
        timeout: timeout,
        measurement_unit: :seconds
      }
    )
  end

  @doc """
  Creates a quality score variable for model outputs.
  Based on Elixact quality assessment patterns.
  """
  @spec quality_score(atom(), keyword()) :: Variable.t()
  def quality_score(name, opts \\ []) do
    Variable.float(name,
      range: {0.0, 10.0},
      default: 5.0,
      description: "Quality assessment score",
      metadata: %{
        ml_type: :quality,
        assessment_scale: Keyword.get(opts, :scale, :likert_10)
      }
    )
  end

  @doc """
  Creates a reasoning complexity variable.
  Based on Elixact reasoning assessment patterns.
  """
  @spec reasoning_complexity(atom(), keyword()) :: Variable.t()
  def reasoning_complexity(name, opts \\ []) do
    Variable.integer(name,
      range: {1, 10},
      default: 3,
      description: "Reasoning complexity assessment",
      metadata: %{
        ml_type: :complexity,
        reasoning_type: Keyword.get(opts, :reasoning_type, :general),
        complexity_levels: [:trivial, :simple, :moderate, :complex, :expert]
      }
    )
  end

  @doc """
  Creates a context window variable for LLM operations.
  Based on Elixact context management patterns.
  """
  @spec context_window(atom(), keyword()) :: Variable.t()
  def context_window(name, opts \\ []) do
    model = Keyword.get(opts, :model, "gpt-4")

    max_context =
      case model do
        "gpt-4" -> 8192
        "gpt-3.5-turbo" -> 4096
        "claude-3" -> 200_000
        _ -> 4096
      end

    Variable.integer(name,
      range: {1, max_context},
      default: div(max_context, 2),
      description: "Context window size for #{model}",
      metadata: %{
        ml_type: :context_window,
        model: model,
        max_context: max_context
      }
    )
  end

  @doc """
  Creates a batch size variable for batch processing.
  Based on Sinter performance optimization patterns.
  """
  @spec batch_size(atom(), keyword()) :: Variable.t()
  def batch_size(name, opts \\ []) do
    Variable.integer(name,
      range: {1, 1000},
      default: 32,
      description: "Batch size for processing operations",
      metadata: %{
        ml_type: :batch_size,
        optimization_target: :throughput,
        power_of_two: Keyword.get(opts, :power_of_two, false)
      }
    )
  end

  # Enhanced Variable Spaces

  @doc """
  Creates a comprehensive LLM optimization space.
  Based on Elixact optimization patterns.
  """
  @spec llm_optimization_space() :: Variable.Space.t()
  def llm_optimization_space do
    variables = [
      temperature(:temperature),
      probability(:top_p),
      token_count(:max_tokens, max: 4096),
      latency_estimate(:response_time),
      cost_estimate(:operation_cost),
      quality_score(:output_quality)
    ]

    Variable.Space.new(
      name: "LLM Optimization Space",
      metadata: %{
        space_type: :llm_optimization,
        optimization_objectives: [:quality, :cost, :latency],
        cost_quality_tradeoff: :pareto_optimal,
        latency_budget: 30.0
      }
    )
    |> Variable.Space.add_variables(variables)
  end

  @doc """
  Creates a teleprompter-specific optimization space.
  Based on DSPEx teleprompter patterns.
  """
  @spec teleprompter_optimization_space() :: Variable.Space.t()
  def teleprompter_optimization_space do
    variables = [
      temperature(:temperature),
      batch_size(:batch_size),
      confidence_score(:min_confidence),
      reasoning_complexity(:complexity_threshold),
      token_count(:max_context, max: 8192)
    ]

    Variable.Space.new(
      name: "Teleprompter Optimization Space",
      metadata: %{
        space_type: :teleprompter_optimization,
        algorithm_support: [:bayesian, :simba, :bootstrap],
        exploration_exploitation: 0.1,
        convergence_threshold: 0.01
      }
    )
    |> Variable.Space.add_variables(variables)
  end

  @doc """
  Creates a multi-objective optimization space.
  Based on Elixact multi-objective patterns.
  """
  @spec multi_objective_space() :: Variable.Space.t()
  def multi_objective_space do
    variables = [
      quality_score(:accuracy),
      latency_estimate(:inference_time),
      cost_estimate(:compute_cost),
      confidence_score(:prediction_confidence)
    ]

    Variable.Space.new(
      name: "Multi-Objective Optimization Space",
      metadata: %{
        space_type: :multi_objective,
        optimization_method: :nsga_ii,
        pareto_dominance: true,
        objective_weights: %{
          accuracy: 0.4,
          inference_time: 0.3,
          compute_cost: 0.2,
          prediction_confidence: 0.1
        }
      }
    )
    |> Variable.Space.add_variables(variables)
  end

  @doc """
  Creates provider-optimized variable spaces.
  Based on Sinter provider-specific patterns.
  """
  @spec provider_optimized_space(atom()) :: Variable.Space.t()
  def provider_optimized_space(provider) do
    base_variables = [
      temperature(:temperature),
      quality_score(:output_quality),
      latency_estimate(:response_time)
    ]

    provider_specific =
      case provider do
        :openai ->
          [
            probability(:top_p),
            token_count(:max_tokens, max: 4096),
            cost_estimate(:cost, currency: :usd, scaling: :token_based)
          ]

        :anthropic ->
          [
            token_count(:max_tokens, max: 100_000),
            cost_estimate(:cost, currency: :usd, scaling: :character_based),
            reasoning_complexity(:reasoning_depth)
          ]

        :groq ->
          [
            batch_size(:batch_size),
            latency_estimate(:inference_speed, timeout: 5.0),
            cost_estimate(:cost, currency: :usd, scaling: :throughput_based)
          ]

        _ ->
          []
      end

    all_variables = base_variables ++ provider_specific

    Variable.Space.new(
      name: "#{String.capitalize(to_string(provider))} Optimized Space",
      metadata: %{
        space_type: :provider_optimized,
        provider: provider,
        specialization: provider_specialization(provider),
        optimization_target: provider_optimization_target(provider)
      }
    )
    |> Variable.Space.add_variables(all_variables)
  end

  # Helper functions for provider optimization
  defp provider_optimization_target(:openai), do: :balanced
  defp provider_optimization_target(:anthropic), do: :quality
  defp provider_optimization_target(:groq), do: :speed
  defp provider_optimization_target(_), do: :general

  defp provider_specialization(:openai), do: :general_purpose
  defp provider_specialization(:anthropic), do: :reasoning_intensive
  defp provider_specialization(:groq), do: :high_throughput
  defp provider_specialization(_), do: :generic
end
