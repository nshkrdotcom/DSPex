defmodule DSPEx.OptimizedProgram do
  @moduledoc """
  Wrapper for programs that have been optimized with demonstrations and enhanced metadata support.

  This module provides a container for programs that don't natively support
  demonstration storage, allowing any program to be enhanced with few-shot
  learning capabilities through teleprompter optimization. Enhanced with
  comprehensive metadata support for SIMBA optimization tracking.

  ## Key Features

  - **Immutable Wrapper**: Safely wraps existing programs without modification
  - **Demo Storage**: Manages demonstrations for programs lacking native support
  - **Metadata Tracking**: Records optimization history and configuration with SIMBA support
  - **Flexible Integration**: Works with any DSPEx.Program implementation
  - **SIMBA Compatibility**: Full support for SIMBA optimization metadata and strategies

  ## Examples

      # Wrap a program with optimized demonstrations
      iex> program = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> demos = [%DSPEx.Example{data: %{question: "Hi", answer: "Hello"}, input_keys: MapSet.new([:question])}]
      iex> optimized = DSPEx.OptimizedProgram.new(program, demos)
      iex> optimized.program == program
      true

      # With SIMBA optimization metadata
      iex> simba_metadata = %{
      ...>   teleprompter: :simba,
      ...>   optimization_strategy: :append_demo,
      ...>   trajectory_analysis: %{...},
      ...>   performance_metrics: %{...}
      ...> }
      iex> optimized = DSPEx.OptimizedProgram.new(program, demos, simba_metadata)

  See `@type t` for the complete type specification.
  """

  use DSPEx.Program

  @enforce_keys [:program, :demos]
  defstruct [:program, :demos, :metadata, :instruction]

  @type t :: %__MODULE__{
          program: struct(),
          demos: [DSPEx.Example.t()],
          metadata: map() | nil,
          instruction: String.t() | nil
        }

  @doc """
  Create a new optimized program wrapper with enhanced metadata support.

  ## Parameters

  - `program`: The original program to wrap
  - `demos`: List of demonstration examples
  - `metadata`: Optional metadata about the optimization (default: empty map)

  ## Enhanced Metadata Support

  The metadata map can contain any optimization-specific information:
  - `:teleprompter` - Which teleprompter was used (:simba, :beacon, etc.)
  - `:optimization_strategy` - Strategy used (:append_demo, etc.)
  - `:performance_metrics` - Before/after performance data
  - `:trajectory_analysis` - SIMBA trajectory analysis results
  - `:instruction_candidates` - Generated instruction variants
  - `:optimization_history` - Step-by-step optimization process
  """
  @spec new(struct(), [DSPEx.Example.t()], map()) :: t()
  def new(program, demos, metadata \\ %{}) do
    # Handle nil metadata gracefully
    safe_metadata = metadata || %{}

    # Extract instruction from metadata if present (SIMBA optimization)
    instruction = extract_instruction_from_metadata(safe_metadata)

    %__MODULE__{
      program: program,
      demos: demos,
      instruction: instruction,
      metadata:
        Map.merge(
          %{
            optimized_at: DateTime.utc_now(),
            demo_count: length(demos),
            wrapper_version: "2.0"
          },
          safe_metadata
        )
    }
  end

  @impl DSPEx.Program
  def forward(%__MODULE__{program: program, demos: demos, instruction: instruction}, inputs, opts) do
    # Enhanced program execution with instruction and demo support
    case program do
      # Program has native demo and instruction support
      %{demos: _, instruction: _} ->
        enhanced_program = %{
          program
          | demos: demos,
            instruction: instruction || program.instruction
        }

        DSPEx.Program.forward(enhanced_program, inputs, opts)

      # Program has native demo support but not instruction
      %{demos: _} ->
        enhanced_program = %{program | demos: demos}
        # Pass instruction in options if available
        enhanced_opts =
          if instruction, do: Keyword.put(opts, :instruction, instruction), else: opts

        DSPEx.Program.forward(enhanced_program, inputs, enhanced_opts)

      # Program doesn't have native demo/instruction support
      _ ->
        enhanced_opts = build_enhanced_options(opts, demos, instruction)
        DSPEx.Program.forward(program, inputs, enhanced_opts)
    end
  end

  @doc """
  Get the demonstration examples from the optimized program.
  """
  @spec get_demos(t()) :: [DSPEx.Example.t()]
  def get_demos(%__MODULE__{demos: demos}), do: demos

  @doc """
  Get the original program from the optimized wrapper.
  """
  @spec get_program(t()) :: struct()
  def get_program(%__MODULE__{program: program}), do: program

  @doc """
  Get optimization metadata with SIMBA-specific enhancements.
  """
  @spec get_metadata(t()) :: map()
  def get_metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc """
  Get instruction from the optimized program (SIMBA enhancement).
  """
  @spec get_instruction(t()) :: String.t() | nil
  def get_instruction(%__MODULE__{instruction: instruction}), do: instruction

  @doc """
  Add additional demonstrations to the optimized program.
  """
  @spec add_demos(t(), [DSPEx.Example.t()]) :: t()
  def add_demos(%__MODULE__{demos: existing_demos} = optimized, new_demos) do
    updated_demos = existing_demos ++ new_demos

    %{
      optimized
      | demos: updated_demos,
        metadata:
          Map.merge(optimized.metadata, %{
            demo_count: length(updated_demos),
            last_demo_update: DateTime.utc_now()
          })
    }
  end

  @doc """
  Replace demonstrations in the optimized program.
  """
  @spec replace_demos(t(), [DSPEx.Example.t()]) :: t()
  def replace_demos(%__MODULE__{} = optimized, new_demos) do
    %{
      optimized
      | demos: new_demos,
        metadata:
          Map.merge(optimized.metadata, %{
            demo_count: length(new_demos),
            demos_replaced_at: DateTime.utc_now()
          })
    }
  end

  @doc """
  Update the instruction in the optimized program (SIMBA enhancement).
  """
  @spec update_instruction(t(), String.t() | nil) :: t()
  def update_instruction(%__MODULE__{} = optimized, new_instruction) do
    %{
      optimized
      | instruction: new_instruction,
        metadata:
          Map.merge(optimized.metadata, %{
            instruction_updated_at: DateTime.utc_now(),
            has_custom_instruction: not is_nil(new_instruction)
          })
    }
  end

  @doc """
  Update the wrapped program while preserving demos, instruction, and metadata.
  """
  @spec update_program(t(), struct()) :: t()
  def update_program(%__MODULE__{} = optimized, new_program) do
    %{
      optimized
      | program: new_program,
        metadata:
          Map.merge(optimized.metadata, %{
            program_updated_at: DateTime.utc_now(),
            original_program_type: DSPEx.Program.program_type(optimized.program),
            new_program_type: DSPEx.Program.program_type(new_program)
          })
    }
  end

  @doc """
  Add SIMBA-specific optimization metadata.
  """
  @spec add_simba_metadata(t(), map()) :: t()
  def add_simba_metadata(%__MODULE__{metadata: existing_metadata} = optimized, simba_metadata) do
    enhanced_metadata =
      Map.merge(existing_metadata, %{
        simba_optimization:
          Map.merge(
            %{
              optimized_at: DateTime.utc_now(),
              version: "1.0"
            },
            simba_metadata
          )
      })

    %{optimized | metadata: enhanced_metadata}
  end

  @doc """
  Get SIMBA-specific optimization data.
  """
  @spec get_simba_metadata(t()) :: map()
  def get_simba_metadata(%__MODULE__{metadata: metadata}) do
    Map.get(metadata, :simba_optimization, %{})
  end

  @doc """
  Check if a program natively supports demonstrations.

  Returns true if the program struct has a `demos` field, false otherwise.
  """
  @spec supports_native_demos?(struct()) :: boolean()
  def supports_native_demos?(program) when is_struct(program) do
    Map.has_key?(program, :demos)
  end

  def supports_native_demos?(_), do: false

  @doc """
  Check if a program natively supports instructions.

  Returns true if the program struct has an `instruction` field, false otherwise.
  Used by SIMBA to determine enhancement strategy.
  """
  @spec supports_native_instruction?(struct()) :: boolean()
  def supports_native_instruction?(program) when is_struct(program) do
    Map.has_key?(program, :instruction)
  end

  def supports_native_instruction?(_), do: false

  @doc """
  Determine SIMBA enhancement strategy for a program.

  Returns the optimal strategy for enhancing a program with SIMBA optimizations:
  - `:native_full` - Program supports both demos and instructions natively
  - `:native_demos` - Program supports demos but not instructions natively
  - `:wrap_optimized` - Program needs OptimizedProgram wrapper for enhancements

  ## Examples

      iex> predict = %DSPEx.Predict{signature: MySignature, client: :openai}
      iex> DSPEx.OptimizedProgram.simba_enhancement_strategy(predict)
      :native_demos  # Predict has demos field but no instruction field

      iex> predict_with_instruction = %CustomProgram{demos: [], instruction: ""}
      iex> DSPEx.OptimizedProgram.simba_enhancement_strategy(predict_with_instruction)
      :native_full

  """
  @spec simba_enhancement_strategy(struct()) :: :native_full | :native_demos | :wrap_optimized
  def simba_enhancement_strategy(program) when is_struct(program) do
    cond do
      supports_native_demos?(program) and supports_native_instruction?(program) ->
        :native_full

      supports_native_demos?(program) ->
        :native_demos

      true ->
        :wrap_optimized
    end
  end

  def simba_enhancement_strategy(_), do: :wrap_optimized

  @doc """
  Create an optimized program using SIMBA enhancement strategy.

  This function analyzes the source program and chooses the optimal way to
  apply SIMBA optimizations (demos and instruction).

  ## Parameters
  - `source_program` - Original program to enhance
  - `demos` - Demonstration examples to add
  - `instruction` - Instruction text (optional)
  - `metadata` - Additional metadata (optional)

  ## Returns
  Enhanced program using the optimal strategy for the source program type.

  """
  @spec enhance_with_simba_strategy(struct(), [DSPEx.Example.t()], String.t() | nil, map()) ::
          struct()
  def enhance_with_simba_strategy(source_program, demos, instruction \\ nil, metadata \\ %{}) do
    case simba_enhancement_strategy(source_program) do
      :native_full ->
        # Program supports both demos and instructions natively
        enhanced_program = %{source_program | demos: demos}

        enhanced_program =
          if instruction,
            do: %{enhanced_program | instruction: instruction},
            else: enhanced_program

        # Still wrap to preserve metadata
        new(enhanced_program, demos, Map.put(metadata, :enhancement_strategy, :native_full))

      :native_demos ->
        # Program supports demos but not instructions natively
        enhanced_program = %{source_program | demos: demos}

        # Wrap with OptimizedProgram to add instruction support
        enhanced_metadata =
          Map.merge(metadata, %{
            enhancement_strategy: :native_demos,
            instruction_via_wrapper: not is_nil(instruction)
          })

        new(enhanced_program, demos, enhanced_metadata)
        |> update_instruction(instruction)

      :wrap_optimized ->
        # Program needs OptimizedProgram wrapper for both demos and instructions
        enhanced_metadata =
          Map.merge(metadata, %{
            enhancement_strategy: :wrap_optimized,
            native_demo_support: false,
            native_instruction_support: false
          })

        new(source_program, demos, enhanced_metadata)
        |> update_instruction(instruction)
    end
  end

  @doc """
  Create a performance comparison between original and optimized programs.

  Useful for SIMBA optimization analysis and reporting.
  """
  @spec create_performance_comparison(t(), [DSPEx.Example.t()], function()) :: map()
  def create_performance_comparison(
        %__MODULE__{program: original_program} = optimized,
        test_examples,
        metric_fn
      ) do
    # Evaluate original program
    original_scores = evaluate_program_on_examples(original_program, test_examples, metric_fn)

    # Evaluate optimized program
    optimized_scores = evaluate_program_on_examples(optimized, test_examples, metric_fn)

    # Calculate statistics
    original_avg =
      if Enum.empty?(original_scores),
        do: 0.0,
        else: Enum.sum(original_scores) / length(original_scores)

    optimized_avg =
      if Enum.empty?(optimized_scores),
        do: 0.0,
        else: Enum.sum(optimized_scores) / length(optimized_scores)

    improvement = optimized_avg - original_avg
    relative_improvement = if original_avg > 0, do: improvement / original_avg, else: 0.0

    %{
      original_score: original_avg,
      optimized_score: optimized_avg,
      absolute_improvement: improvement,
      relative_improvement: relative_improvement,
      improved: improvement > 0,
      test_example_count: length(test_examples),
      optimization_metadata: get_metadata(optimized)
    }
  end

  # Private helper functions

  defp extract_instruction_from_metadata(metadata) when is_map(metadata) do
    metadata[:instruction] ||
      get_in(metadata, [:simba_optimization, :best_instruction]) ||
      get_in(metadata, [:beacon_optimization, :instruction])
  end

  defp extract_instruction_from_metadata(_), do: nil

  defp evaluate_program_on_examples(program, examples, metric_fn) do
    examples
    |> Enum.map(fn example ->
      inputs = DSPEx.Example.inputs(example)

      try do
        case DSPEx.Program.forward(program, inputs) do
          {:ok, outputs} ->
            metric_fn.(example, outputs)

          {:error, _} ->
            0.0
        end
      rescue
        _ -> 0.0
      end
    end)
  end

  # Extract the options building logic to reduce nesting
  defp build_enhanced_options(opts, demos, instruction) do
    opts
    |> Keyword.put(:demos, demos)
    |> maybe_add_instruction(instruction)
  end

  defp maybe_add_instruction(opts, nil), do: opts
  defp maybe_add_instruction(opts, instruction), do: Keyword.put(opts, :instruction, instruction)
end
