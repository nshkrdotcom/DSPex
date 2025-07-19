defmodule DSPEx.Program.Variable do
  @moduledoc """
  Helper module for DSPEx Program-Variable System integration.

  This module provides utilities for extracting variables from signatures,
  creating variable spaces, and managing variable configurations in DSPEx programs.
  """

  alias ElixirML.Variable
  alias ElixirML.Variable.{Space, MLTypes}

  @doc """
  Extract variables from a signature and create a variable space.

  Analyzes a DSPEx signature to automatically extract potential optimization
  variables and creates a comprehensive variable space for optimization.

  ## Parameters

  - `signature` - DSPEx signature module
  - `opts` - Optional configuration

  ## Options

  - `:include_ml_variables` - Include standard ML variables (default: true)
  - `:provider_choices` - Available providers (default: [:openai, :anthropic, :groq])
  - `:extract_temperature` - Extract temperature from signature (default: true)
  - `:extract_max_tokens` - Extract max_tokens from signature (default: true)

  ## Returns

  `ElixirML.Variable.Space` with extracted and standard variables.

  ## Examples

      space = DSPEx.Program.Variable.extract_from_signature(MySignature)
      # Creates space with provider, adapter, reasoning_strategy, temperature, etc.

  """
  @spec extract_from_signature(module(), keyword()) :: Space.t()
  def extract_from_signature(signature, opts \\ []) do
    include_ml = Keyword.get(opts, :include_ml_variables, true)
    provider_choices = Keyword.get(opts, :provider_choices, [:openai, :anthropic, :groq])

    # Start with empty space
    space = Space.new()

    # Add signature-specific variables
    space = add_signature_variables(space, signature, opts)

    # Add standard ML variables if requested
    if include_ml do
      add_standard_ml_variables(space, provider_choices)
    else
      space
    end
  end

  @doc """
  Create standard ML configuration variable space.

  Returns a variable space with common ML parameters like provider,
  model, temperature, max_tokens, and optional reasoning/adapter variables.

  ## Parameters

  - `opts` - Configuration options

  ## Options

  - `:provider_choices` - List of available providers (default: [:openai, :anthropic, :groq])
  - `:include_reasoning` - Include reasoning strategy variable (default: true)
  - `:include_adapters` - Include adapter variable (default: true)
  - `:temperature_range` - Temperature range tuple (default: {0.0, 2.0})
  - `:max_tokens_range` - Max tokens range tuple (default: {50, 4000})

  ## Returns

  Variable space with standard ML variables configured.

  """
  @spec standard_ml_config(keyword()) :: Space.t()
  def standard_ml_config(opts \\ []) do
    provider_choices = Keyword.get(opts, :provider_choices, [:openai, :anthropic, :groq])
    include_reasoning = Keyword.get(opts, :include_reasoning, true)
    include_adapters = Keyword.get(opts, :include_adapters, true)
    temperature_range = Keyword.get(opts, :temperature_range, {0.0, 2.0})
    max_tokens_range = Keyword.get(opts, :max_tokens_range, {50, 4000})

    Space.new()
    |> Space.add_variable(MLTypes.provider(:provider, providers: provider_choices))
    |> Space.add_variable(MLTypes.model(:model, models: ["gpt-4", "claude-3-sonnet"]))
    |> Space.add_variable(
      Variable.float(:temperature,
        range: temperature_range,
        default: 0.7,
        description: "Sampling temperature for model response"
      )
    )
    |> Space.add_variable(
      Variable.integer(:max_tokens,
        range: max_tokens_range,
        default: 1000,
        description: "Maximum tokens in model response"
      )
    )
    |> maybe_add_reasoning_variables(include_reasoning)
    |> maybe_add_adapter_variables(include_adapters)
  end

  @doc """
  Enhance a program with variable support.

  Takes an existing program struct and enhances it with variable management
  capabilities by adding a variable_space field and configuration.

  ## Parameters

  - `program` - Existing DSPEx program struct
  - `opts` - Enhancement options

  ## Options

  - `:auto_extract` - Automatically extract variables from signature (default: true)
  - `:include_ml_variables` - Include standard ML variables (default: true)
  - `:variable_space` - Specific variable space to use

  ## Returns

  Enhanced program struct with variable_space field.

  """
  @spec enhance_program(struct(), keyword()) :: struct()
  def enhance_program(program, opts \\ []) when is_struct(program) do
    auto_extract = Keyword.get(opts, :auto_extract, true)
    include_ml = Keyword.get(opts, :include_ml_variables, true)

    variable_space =
      case Keyword.get(opts, :variable_space) do
        nil ->
          cond do
            auto_extract and Map.has_key?(program, :signature) ->
              extract_from_signature(program.signature,
                include_ml_variables: include_ml
              )

            include_ml ->
              standard_ml_config()

            true ->
              Space.new()
          end

        space ->
          space
      end

    # Add variable_space field to program if it doesn't exist
    if Map.has_key?(program, :variable_space) do
      %{program | variable_space: variable_space}
    else
      Map.put(program, :variable_space, variable_space)
    end
  end

  @doc """
  Create a variable configuration from options.

  Extracts variable values from various option formats and creates
  a normalized variable configuration map.

  ## Parameters

  - `opts` - Options in various formats (keyword list, map, etc.)

  ## Returns

  Map with variable names as keys and values as values.

  """
  @spec config_from_opts(any()) :: %{atom() => any()}
  def config_from_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :variables) do
      nil -> extract_implicit_variables(opts)
      explicit_vars when is_map(explicit_vars) -> explicit_vars
      explicit_vars when is_list(explicit_vars) -> Map.new(explicit_vars)
      _ -> %{}
    end
  end

  def config_from_opts(opts) when is_map(opts) do
    case Map.get(opts, :variables) do
      nil -> extract_implicit_variables(opts)
      explicit_vars when is_map(explicit_vars) -> explicit_vars
      _ -> %{}
    end
  end

  # Note: Removed catch-all clause as it was unreachable -
  # all valid inputs are handled by the is_list and is_map guards

  # Private helper functions

  defp add_signature_variables(space, signature, opts) do
    extract_temperature = Keyword.get(opts, :extract_temperature, true)
    extract_max_tokens = Keyword.get(opts, :extract_max_tokens, true)

    space
    |> maybe_add_temperature_from_signature(signature, extract_temperature)
    |> maybe_add_max_tokens_from_signature(signature, extract_max_tokens)
    |> maybe_add_signature_specific_variables(signature)
  end

  defp add_standard_ml_variables(space, provider_choices) do
    space
    |> Space.add_variable(MLTypes.provider(:provider, providers: provider_choices))
    |> Space.add_variable(MLTypes.adapter(:adapter))
    |> Space.add_variable(MLTypes.reasoning_strategy(:reasoning_strategy))
    |> Space.add_variable(Variable.float(:temperature, range: {0.0, 2.0}, default: 0.7))
    |> Space.add_variable(Variable.integer(:max_tokens, range: {50, 4000}, default: 1000))
  end

  defp maybe_add_reasoning_variables(space, true) do
    Space.add_variable(space, MLTypes.reasoning_strategy(:reasoning_strategy))
  end

  defp maybe_add_reasoning_variables(space, false), do: space

  defp maybe_add_adapter_variables(space, true) do
    Space.add_variable(space, MLTypes.adapter(:adapter))
  end

  defp maybe_add_adapter_variables(space, false), do: space

  defp maybe_add_temperature_from_signature(space, signature, true) do
    # Check if signature has temperature hints or constraints
    if has_temperature_field?(signature) do
      Space.add_variable(
        space,
        Variable.float(:temperature,
          range: get_temperature_range(signature),
          default: get_temperature_default(signature)
        )
      )
    else
      space
    end
  end

  defp maybe_add_temperature_from_signature(space, _signature, false), do: space

  defp maybe_add_max_tokens_from_signature(space, signature, true) do
    # Check if signature has max_tokens hints or constraints
    if has_max_tokens_field?(signature) do
      Space.add_variable(
        space,
        Variable.integer(:max_tokens,
          range: get_max_tokens_range(signature),
          default: get_max_tokens_default(signature)
        )
      )
    else
      space
    end
  end

  defp maybe_add_max_tokens_from_signature(space, _signature, false), do: space

  defp maybe_add_signature_specific_variables(space, signature) do
    # Extract any signature-specific variables based on field analysis
    # This is a placeholder for future signature introspection
    if function_exported?(signature, :optimization_variables, 0) do
      signature.optimization_variables()
      |> Enum.reduce(space, fn variable, acc_space ->
        Space.add_variable(acc_space, variable)
      end)
    else
      space
    end
  end

  defp extract_implicit_variables(opts) when is_list(opts) do
    # Extract common variables from keyword options
    %{}
    |> maybe_put(:temperature, Keyword.get(opts, :temperature))
    |> maybe_put(:max_tokens, Keyword.get(opts, :max_tokens))
    |> maybe_put(:provider, Keyword.get(opts, :provider))
    |> maybe_put(:model, Keyword.get(opts, :model))
  end

  defp extract_implicit_variables(opts) when is_map(opts) do
    # Extract common variables from map options
    %{}
    |> maybe_put(:temperature, Map.get(opts, :temperature))
    |> maybe_put(:max_tokens, Map.get(opts, :max_tokens))
    |> maybe_put(:provider, Map.get(opts, :provider))
    |> maybe_put(:model, Map.get(opts, :model))
  end

  # Note: Removed catch-all clause as it was unreachable -
  # all valid inputs are handled by the is_list and is_map guards

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Placeholder functions for signature introspection
  # These would be enhanced with actual signature analysis in a full implementation

  defp has_temperature_field?(_signature), do: false
  defp has_max_tokens_field?(_signature), do: false

  defp get_temperature_range(_signature), do: {0.0, 2.0}
  defp get_temperature_default(_signature), do: 0.7

  defp get_max_tokens_range(_signature), do: {50, 4000}
  defp get_max_tokens_default(_signature), do: 1000
end
