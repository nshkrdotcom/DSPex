defmodule DSPEx.Teleprompter.SIMBA.Strategy do
  @moduledoc """
  Behavior for SIMBA optimization strategies.

  Strategies are simple rules that create new program variants from
  successful execution trajectories. This behavior defines the contract
  that all SIMBA strategies must implement.

  ## Strategy Implementation

  Each strategy must implement two callbacks:
  - `apply/3` - Apply the strategy to create a new program variant
  - `applicable?/2` (optional) - Check if strategy is applicable to given bucket

  ## Example Strategy

      defmodule MyStrategy do
        @behaviour DSPEx.Teleprompter.SIMBA.Strategy

        @impl true
        def apply(bucket, source_program, opts) do
          # Strategy implementation
          {:ok, enhanced_program}
        end

        @impl true
        def applicable?(bucket, opts) do
          # Check if strategy should be applied
          Bucket.has_improvement_potential?(bucket)
        end
      end

  """

  alias DSPEx.Teleprompter.SIMBA.{Bucket, ElixirMLSchemas}

  @doc """
  Apply the strategy to a bucket to create a new program variant.

  This is the core callback that strategies must implement. It takes a
  bucket of trajectories with performance information and creates a new
  program variant based on the successful patterns found.

  ## Parameters
  - `bucket` - Bucket containing trajectories to analyze
  - `source_program` - Base program to modify/enhance
  - `opts` - Strategy-specific options

  ## Returns
  - `{:ok, new_program}` - Successfully created new program variant
  - `{:skip, reason}` - Strategy not applicable or failed, with reason

  ## Examples

      def apply(bucket, source_program, opts) do
        case Bucket.best_trajectory(bucket) do
          %Trajectory{score: score} when score > 0.7 ->
            {:ok, create_enhanced_program(source_program, bucket)}
          _ ->
            {:skip, "No high-quality trajectories found"}
        end
      end

  """
  @callback apply(Bucket.t(), struct(), map()) ::
              {:ok, struct()} | {:skip, String.t()}

  @doc """
  Check if strategy is applicable to the given bucket.

  This optional callback allows strategies to pre-filter buckets before
  attempting to apply optimizations. If not implemented, the strategy
  is always considered applicable.

  ## Parameters
  - `bucket` - Bucket to analyze for applicability
  - `opts` - Strategy-specific options

  ## Returns
  - `true` - Strategy should be applied to this bucket
  - `false` - Strategy should be skipped for this bucket

  ## Examples

      def applicable?(bucket, _opts) do
        Bucket.has_improvement_potential?(bucket) and
        length(bucket.trajectories) >= 3
      end

  """
  @callback applicable?(Bucket.t(), map()) :: boolean()

  @optional_callbacks [applicable?: 2]

  @doc """
  Check if a module implements the SIMBA Strategy behavior.
  """
  @spec implements_strategy?(module()) :: boolean()
  def implements_strategy?(module) when is_atom(module) do
    behaviours = module.module_info(:attributes) |> Keyword.get(:behaviour, [])
    __MODULE__ in behaviours
  rescue
    UndefinedFunctionError -> false
  end

  def implements_strategy?(_), do: false

  @doc """
  Apply the first applicable strategy from a list of strategies.

  This utility function is used by SIMBA to find and apply the first
  strategy that is applicable to a given bucket.

  ## Parameters
  - `strategies` - List of strategy modules to try
  - `bucket` - Bucket to apply strategies to
  - `source_program` - Program to enhance
  - `opts` - Options to pass to strategies

  ## Returns
  - `{:ok, new_program}` - First applicable strategy succeeded
  - `{:skip, reason}` - No applicable strategies or all failed

  """
  @spec apply_first_applicable([module()], Bucket.t(), struct(), map()) ::
          {:ok, struct()} | {:skip, String.t()}
  def apply_first_applicable(strategies, bucket, source_program, opts \\ %{}) do
    # Validate bucket data before applying strategies
    with :ok <- validate_bucket_for_strategy_application(bucket),
         :ok <- validate_strategy_configuration(opts) do
      strategies
      |> Enum.reduce_while({:skip, "No strategies provided"}, fn strategy_module, _acc ->
        try_apply_strategy(strategy_module, bucket, source_program, opts)
      end)
    else
      {:error, reason} -> {:skip, "Validation failed: #{reason}"}
    end
  end

  defp try_apply_strategy(strategy_module, bucket, source_program, opts) do
    cond do
      not implements_strategy?(strategy_module) ->
        {:cont, {:skip, "#{strategy_module} does not implement Strategy behavior"}}

      function_exported?(strategy_module, :applicable?, 2) ->
        try_apply_with_applicability_check(strategy_module, bucket, source_program, opts)

      true ->
        try_apply_without_applicability_check(strategy_module, bucket, source_program, opts)
    end
  end

  defp try_apply_with_applicability_check(strategy_module, bucket, source_program, opts) do
    if strategy_module.applicable?(bucket, opts) do
      apply_strategy_and_handle_result(strategy_module, bucket, source_program, opts)
    else
      {:cont, {:skip, "Strategy #{strategy_module} not applicable"}}
    end
  end

  defp try_apply_without_applicability_check(strategy_module, bucket, source_program, opts) do
    apply_strategy_and_handle_result(strategy_module, bucket, source_program, opts)
  end

  defp apply_strategy_and_handle_result(strategy_module, bucket, source_program, opts) do
    case strategy_module.apply(bucket, source_program, opts) do
      {:ok, new_program} -> {:halt, {:ok, new_program}}
      {:skip, reason} -> {:cont, {:skip, reason}}
    end
  end

  @doc """
  Get strategy metadata and capabilities.

  Returns information about a strategy module including its name,
  capabilities, and configuration options.

  ## Parameters
  - `strategy_module` - Strategy module to introspect

  ## Returns
  Map with strategy information, or error if not a valid strategy.

  """
  @spec get_strategy_info(module()) :: {:ok, map()} | {:error, term()}
  def get_strategy_info(strategy_module) when is_atom(strategy_module) do
    if implements_strategy?(strategy_module) do
      strategy_name =
        strategy_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      info = %{
        module: strategy_module,
        name: strategy_name,
        has_applicability_check: function_exported?(strategy_module, :applicable?, 2),
        description: get_strategy_description(strategy_module)
      }

      {:ok, info}
    else
      {:error, {:not_a_strategy, strategy_module}}
    end
  end

  def get_strategy_info(_), do: {:error, :invalid_strategy_module}

  # Private helper functions

  defp get_strategy_description(strategy_module) do
    case Code.fetch_docs(strategy_module) do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} when is_binary(module_doc) ->
        # Extract first line of module documentation
        module_doc
        |> String.split("\n")
        |> List.first()
        |> String.trim()

      _ ->
        "No description available"
    end
  rescue
    _ -> "No description available"
  end

  # Sinter validation functions for strategy application

  @spec validate_bucket_for_strategy_application(Bucket.t()) :: :ok | {:error, String.t()}
  defp validate_bucket_for_strategy_application(bucket) do
    # Convert bucket to format expected by Sinter schema
    bucket_data = %{
      trajectories:
        Enum.map(bucket.trajectories, fn trajectory ->
          %{score: trajectory.score, success: trajectory.success}
        end),
      max_score: bucket.max_score || 0.0,
      min_score: bucket.min_score || 0.0,
      avg_score: bucket.avg_score || 0.0,
      max_to_min_gap: bucket.max_to_min_gap || 0.0,
      max_to_avg_gap: bucket.max_to_avg_gap || 0.0,
      metadata: bucket.metadata || %{}
    }

    case ElixirMLSchemas.validate_bucket(bucket_data) do
      {:ok, _validated} ->
        :ok

      {:error, errors} ->
        {:error, "Bucket validation failed: #{format_validation_errors(errors)}"}
    end
  end

  defp validate_strategy_configuration(opts) when is_map(opts) do
    # Create a minimal strategy config for validation
    strategy_config =
      Map.merge(
        %{
          strategy_name: "strategy_validation",
          enabled: true
        },
        opts
      )

    case ElixirMLSchemas.validate_strategy_config(strategy_config) do
      {:ok, _validated} ->
        :ok

      {:error, errors} ->
        {:error, "Strategy configuration validation failed: #{format_validation_errors(errors)}"}
    end
  end

  defp validate_strategy_configuration(_opts), do: :ok

  defp format_validation_errors(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn error ->
      "#{Enum.join(error.path, ".")}: #{error.message}"
    end)
  end
end
