defmodule DSPEx.Teleprompter.BEACON do
  @moduledoc """
  BEACON (Bayesian Exploration and Adaptive Compilation Of Narratives) teleprompter for DSPEx program optimization.

  BEACON is a simple yet effective Bayesian optimization teleprompter that:
  1. Bootstrap generates candidate demonstrations using a teacher program
  2. Uses Bayesian optimization to find the best instruction/demonstration combinations
  3. Evaluates candidates on a validation set to select optimal configurations

  ## Features

  - Pure single-node implementation with excellent concurrency
  - Bayesian optimization for efficient hyperparameter search
  - Configurable bootstrap generation and evaluation
  - Progress tracking and comprehensive telemetry
  - Fault tolerance with graceful error handling

  ## Algorithm Overview

  1. **Bootstrap Generation**: Use teacher program to generate candidate demonstrations
  2. **Instruction Proposal**: Generate instruction candidates using LLM
  3. **Bayesian Optimization**: Find optimal instruction/demo combinations
  4. **Validation**: Select best performing configuration

  ## Example Usage

      # Create BEACON teleprompter
      teleprompter = DSPEx.Teleprompter.BEACON.new(
        num_candidates: 20,
        max_bootstrapped_demos: 4,
        num_trials: 50,
        quality_threshold: 0.7
      )

      # Optimize student program
      {:ok, optimized_student} = teleprompter.compile(
        student_program,
        teacher_program,
        training_examples,
        metric_fn
      )
  """

  @behaviour DSPEx.Teleprompter

  alias DSPEx.{Client, Example, OptimizedProgram, Program}
  alias DSPEx.Services.ConfigManager
  alias DSPEx.Teleprompter.BEACON.BayesianOptimizer
  alias DSPEx.Teleprompter.BootstrapFewShot

  @enforce_keys []
  defstruct num_candidates: 20,
            max_bootstrapped_demos: 4,
            max_labeled_demos: 16,
            num_trials: 50,
            quality_threshold: 0.7,
            max_concurrency: 20,
            timeout: 60_000,
            teacher_retries: 2,
            progress_callback: nil,
            instruction_model: nil,
            evaluation_model: nil

  @type t :: %__MODULE__{
          num_candidates: pos_integer(),
          max_bootstrapped_demos: pos_integer(),
          max_labeled_demos: pos_integer(),
          num_trials: pos_integer(),
          quality_threshold: float(),
          max_concurrency: pos_integer(),
          timeout: timeout(),
          teacher_retries: pos_integer(),
          progress_callback: (map() -> :ok) | nil,
          instruction_model: atom() | nil,
          evaluation_model: atom() | nil
        }

  @type instruction_candidate :: %{
          id: String.t(),
          instruction: String.t(),
          quality_score: float() | nil,
          metadata: map()
        }

  @type demo_candidate :: %{
          id: String.t(),
          demo: Example.t(),
          quality_score: float(),
          metadata: map()
        }

  @type optimization_result :: %{
          best_instruction: String.t(),
          best_demos: [Example.t()],
          score: float(),
          trials: [map()],
          stats: map()
        }

  @doc """
  Create a new BEACON teleprompter with given options.

  ## Options

  - `:num_candidates` - Number of instruction candidates to generate (default: 20)
  - `:max_bootstrapped_demos` - Maximum bootstrapped demos to generate (default: 4)
  - `:max_labeled_demos` - Maximum labeled demos to include (default: 16)
  - `:num_trials` - Number of Bayesian optimization trials (default: 50)
  - `:quality_threshold` - Minimum quality score for demonstrations (default: 0.7)
  - `:max_concurrency` - Maximum concurrent operations (default: 20)
  - `:timeout` - Timeout for operations in ms (default: 60_000)
  - `:teacher_retries` - Number of retries for failed teacher requests (default: 2)
  - `:progress_callback` - Function to call with progress updates (default: nil)
  - `:instruction_model` - Model to use for instruction generation (default: nil)
  - `:evaluation_model` - Model to use for evaluation (default: nil)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl DSPEx.Teleprompter
  def compile(student, teacher, trainset, metric_fn, opts \\ [])

  def compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    do_compile(student, teacher, trainset, metric_fn, opts)
  end

  def compile(%__MODULE__{} = teleprompter, student, teacher, trainset, metric_fn, opts) do
    do_compile(
      student,
      teacher,
      trainset,
      metric_fn,
      Keyword.merge(struct_to_keyword(teleprompter), opts)
    )
  end

  # Private implementation

  defp do_compile(student, teacher, trainset, metric_fn, opts) when is_list(opts) do
    config = struct(__MODULE__, opts)
    correlation_id = Keyword.get(opts, :correlation_id) || generate_correlation_id()

    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        trainset_size: length(trainset),
        config: Map.take(config, [:num_candidates, :num_trials, :max_bootstrapped_demos])
      }
    )

    result =
      with :ok <- validate_inputs(student, teacher, trainset, metric_fn),
           {:ok, demo_candidates} <-
             bootstrap_demonstrations(teacher, trainset, config, correlation_id),
           {:ok, instruction_candidates} <-
             generate_instruction_candidates(student, trainset, config, correlation_id),
           {:ok, optimization_result} <-
             run_bayesian_optimization(
               student,
               demo_candidates,
               instruction_candidates,
               trainset,
               metric_fn,
               config,
               correlation_id
             ),
           {:ok, optimized_student} <-
             create_optimized_student(
               student,
               optimization_result,
               config
             ) do
        {:ok, optimized_student}
      else
        {:error, reason} -> {:error, reason}
      end

    duration = System.monotonic_time() - start_time
    success = match?({:ok, _}, result)

    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :stop],
      %{duration: duration, success: success},
      %{correlation_id: correlation_id}
    )

    result
  end

  defp validate_inputs(student, teacher, trainset, metric_fn) do
    cond do
      not is_struct(student) ->
        {:error, :invalid_student_program}

      not is_struct(teacher) ->
        {:error, :invalid_teacher_program}

      not is_list(trainset) or Enum.empty?(trainset) ->
        {:error, :invalid_or_empty_trainset}

      not is_function(metric_fn, 2) ->
        {:error, :invalid_metric_function}

      true ->
        :ok
    end
  end

  defp bootstrap_demonstrations(teacher, trainset, config, correlation_id) do
    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :bootstrap, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, trainset_size: length(trainset)}
    )

    # Use BootstrapFewShot to generate demonstrations
    bootstrap_opts = [
      num_threads: config.max_concurrency,
      max_bootstrapped_demos: config.max_bootstrapped_demos,
      quality_threshold: config.quality_threshold,
      teacher_retries: config.teacher_retries
    ]

    case BootstrapFewShot.compile(teacher, teacher, trainset, fn _, _ -> 1.0 end, bootstrap_opts) do
      {:ok, bootstrap_result} ->
        # Convert bootstrap result to demo candidates
        demo_candidates =
          bootstrap_result.demos
          |> Enum.with_index()
          |> Enum.map(fn {demo, index} ->
            %{
              id: "bootstrap_#{index}",
              demo: demo,
              # BootstrapFewShot already filters for quality
              quality_score: 1.0,
              metadata: %{
                source: :bootstrap,
                generated_at: DateTime.utc_now()
              }
            }
          end)

        emit_telemetry(
          [:dspex, :teleprompter, :beacon, :bootstrap, :stop],
          %{duration: System.monotonic_time()},
          %{correlation_id: correlation_id, candidates_generated: length(demo_candidates)}
        )

        {:ok, demo_candidates}

      {:error, reason} ->
        emit_telemetry(
          [:dspex, :teleprompter, :beacon, :bootstrap, :exception],
          %{},
          %{correlation_id: correlation_id, error: reason}
        )

        {:error, {:bootstrap_failed, reason}}
    end
  end

  defp generate_instruction_candidates(student, trainset, config, correlation_id) do
    start_time = System.monotonic_time()

    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :instruction, :start],
      %{system_time: System.system_time()},
      %{correlation_id: correlation_id, num_candidates: config.num_candidates}
    )

    # Get the signature from the student program
    signature = extract_signature(student)

    # Generate instruction candidates using LLM
    instruction_prompts = build_instruction_generation_prompts(signature, trainset, config)

    candidates =
      instruction_prompts
      |> Stream.with_index()
      |> Task.async_stream(
        fn {prompt, index} ->
          case generate_single_instruction(prompt, config, correlation_id) do
            {:ok, instruction} ->
              %{
                id: "inst_#{index}",
                instruction: instruction,
                quality_score: nil,
                metadata: %{
                  generated_at: DateTime.utc_now(),
                  prompt_type: Map.get(prompt, :type, :default),
                  source: :llm_generated
                }
              }

            {:error, _reason} ->
              nil
          end
        end,
        max_concurrency: config.max_concurrency,
        timeout: config.timeout
      )
      |> Stream.filter(&match?({:ok, %{}}, &1))
      |> Stream.map(fn {:ok, candidate} -> candidate end)
      |> Enum.to_list()

    duration = System.monotonic_time() - start_time

    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :instruction, :stop],
      %{duration: duration, success: length(candidates) > 0},
      %{
        correlation_id: correlation_id,
        candidates_generated: length(candidates)
      }
    )

    # Ensure we have at least one instruction candidate
    final_candidates =
      if Enum.empty?(candidates) do
        # Fallback to default instruction if LLM generation fails
        default_instruction = build_default_instruction(signature)

        [
          %{
            id: "inst_default",
            instruction: default_instruction,
            quality_score: nil,
            metadata: %{
              generated_at: DateTime.utc_now(),
              prompt_type: :fallback,
              source: :default
            }
          }
        ]
      else
        candidates
      end

    {:ok, final_candidates}
  end

  defp run_bayesian_optimization(
         student,
         demo_candidates,
         instruction_candidates,
         trainset,
         metric_fn,
         config,
         correlation_id
       ) do
    emit_telemetry(
      [:dspex, :teleprompter, :beacon, :optimization, :start],
      %{system_time: System.system_time()},
      %{
        correlation_id: correlation_id,
        num_trials: config.num_trials,
        demo_candidates: length(demo_candidates),
        instruction_candidates: length(instruction_candidates)
      }
    )

    # Create search space for Bayesian optimizer
    search_space = %{
      instructions: instruction_candidates,
      demos: demo_candidates
    }

    # Create objective function that evaluates configurations
    objective_function = fn bayesian_config ->
      # Convert Bayesian optimizer config to BEACON config format
      instruction = Enum.find(instruction_candidates, &(&1.id == bayesian_config.instruction_id))

      demos =
        Enum.filter(demo_candidates, &(bayesian_config.demo_ids |> Enum.member?(&1.id)))
        |> Enum.map(& &1.demo)

      test_config = %{
        instruction: instruction.instruction,
        demos: demos
      }

      # Create optimized program for testing
      test_program = create_test_program(student, test_config)

      # Evaluate on validation set (use subset of trainset)
      validation_set = Enum.take_random(trainset, min(10, length(trainset)))

      case evaluate_configuration(test_program, validation_set, metric_fn) do
        {:ok, score} -> score
        # Return poor score for failed evaluations
        {:error, _} -> 0.0
      end
    end

    # Create and run Bayesian optimizer
    optimizer =
      BayesianOptimizer.new(
        num_initial_samples: min(10, div(config.num_trials, 3)),
        convergence_patience: 5,
        acquisition_function: :expected_improvement
      )

    case BayesianOptimizer.optimize(
           optimizer,
           search_space,
           objective_function,
           max_iterations: config.num_trials,
           correlation_id: correlation_id
         ) do
      {:ok, bayesian_result} ->
        # Convert Bayesian result back to BEACON format
        best_instruction =
          Enum.find(
            instruction_candidates,
            &(&1.id == bayesian_result.best_configuration.instruction_id)
          )

        best_demos =
          Enum.filter(
            demo_candidates,
            &(bayesian_result.best_configuration.demo_ids |> Enum.member?(&1.id))
          )
          |> Enum.map(& &1.demo)

        optimization_result = %{
          best_instruction: best_instruction.instruction,
          best_demos: best_demos,
          score: bayesian_result.best_score,
          trials: convert_bayesian_trials_to_beacon_format(bayesian_result.observations),
          stats:
            Map.merge(bayesian_result.stats, %{
              bayesian_optimization: true,
              convergence_iteration: bayesian_result.convergence_iteration
            })
        }

        emit_telemetry(
          [:dspex, :teleprompter, :beacon, :optimization, :stop],
          %{duration: System.monotonic_time()},
          %{
            correlation_id: correlation_id,
            best_score: bayesian_result.best_score,
            total_trials: length(bayesian_result.observations),
            convergence_iteration: bayesian_result.convergence_iteration
          }
        )

        {:ok, optimization_result}

      {:error, reason} ->
        emit_telemetry(
          [:dspex, :teleprompter, :beacon, :optimization, :exception],
          %{},
          %{correlation_id: correlation_id, error: reason}
        )

        {:error, reason}
    end
  end

  defp convert_bayesian_trials_to_beacon_format(observations) do
    Enum.map(observations, fn obs ->
      %{
        instruction_id: obs.configuration.instruction_id,
        demo_ids: obs.configuration.demo_ids,
        score: obs.score,
        timestamp: obs.timestamp
      }
    end)
  end

  defp create_test_program(student, config) do
    case OptimizedProgram.simba_enhancement_strategy(student) do
      :native_full ->
        %{student | instruction: config.instruction, demos: config.demos}

      :native_demos ->
        %{student | demos: config.demos}

      :wrap_optimized ->
        OptimizedProgram.new(student, config.demos, %{instruction: config.instruction})
    end
  end

  defp evaluate_configuration(program, validation_set, metric_fn) do
    scores =
      validation_set
      |> Task.async_stream(
        fn example ->
          # Extract inputs from Example struct based on input_keys
          inputs =
            example.data
            |> Map.take(MapSet.to_list(example.input_keys))

          case Program.forward(program, inputs, timeout: 30_000) do
            {:ok, outputs} ->
              metric_fn.(example, outputs)

            {:error, _} ->
              0.0
          end
        end,
        max_concurrency: 3,
        timeout: 35_000
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, score} -> score end)
      |> Enum.to_list()

    if Enum.empty?(scores) do
      {:error, :no_valid_evaluations}
    else
      average_score = Enum.sum(scores) / length(scores)
      {:ok, average_score}
    end
  rescue
    error ->
      {:error, {:evaluation_exception, error}}
  end

  defp create_optimized_student(student, optimization_result, _config) do
    case OptimizedProgram.simba_enhancement_strategy(student) do
      :native_full ->
        optimized = %{
          student
          | instruction: optimization_result.best_instruction,
            demos: optimization_result.best_demos
        }

        {:ok, optimized}

      :native_demos ->
        optimized = %{student | demos: optimization_result.best_demos}
        {:ok, optimized}

      :wrap_optimized ->
        optimized =
          OptimizedProgram.new(
            student,
            optimization_result.best_demos,
            %{
              instruction: optimization_result.best_instruction,
              beacon_optimization: optimization_result.stats,
              optimized_at: DateTime.utc_now()
            }
          )

        {:ok, optimized}
    end
  end

  # Helper functions for LLM-based instruction generation

  defp extract_signature(student) do
    case student do
      %{signature: signature} -> signature
      %{program: %{signature: signature}} -> signature
      _ -> nil
    end
  end

  defp build_instruction_generation_prompts(signature, trainset, config) do
    # Get sample examples for context
    sample_examples = Enum.take(trainset, min(3, length(trainset)))

    # Get signature information
    {input_fields, output_fields} = get_signature_fields(signature)

    base_prompts = [
      %{
        type: :task_description,
        content: """
        I need to write an instruction for a language model to perform this task:

        Input fields: #{Enum.join(input_fields, ", ")}
        Output fields: #{Enum.join(output_fields, ", ")}

        Example data:
        #{format_examples_for_instruction(sample_examples)}

        Write a clear, concise instruction that tells the model how to transform the inputs into the outputs.
        Focus on the reasoning process and key considerations.
        """
      },
      %{
        type: :step_by_step,
        content: """
        Create a step-by-step instruction for this task:

        Task: Transform #{Enum.join(input_fields, ", ")} into #{Enum.join(output_fields, ", ")}

        Examples:
        #{format_examples_for_instruction(sample_examples)}

        Provide a clear instruction that breaks down the reasoning process into steps.
        """
      },
      %{
        type: :quality_focused,
        content: """
        Write an instruction emphasizing quality and accuracy for this task:

        Inputs: #{Enum.join(input_fields, ", ")}
        Outputs: #{Enum.join(output_fields, ", ")}

        Sample examples:
        #{format_examples_for_instruction(sample_examples)}

        Focus on accuracy, reasoning, and quality in your instruction.
        """
      }
    ]

    # Add more prompt variations based on config
    additional_prompts =
      if config.num_candidates > 3 do
        generate_additional_prompts(signature, sample_examples, config.num_candidates - 3)
      else
        []
      end

    base_prompts ++ additional_prompts
  end

  defp get_signature_fields(signature) do
    input_fields =
      if signature && function_exported?(signature, :input_fields, 0) do
        signature.input_fields()
      else
        ["input"]
      end

    output_fields =
      if signature && function_exported?(signature, :output_fields, 0) do
        signature.output_fields()
      else
        ["output"]
      end

    {input_fields, output_fields}
  end

  defp format_examples_for_instruction(examples) do
    examples
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {example, idx} ->
      inputs = Example.inputs(example)
      outputs = Example.outputs(example)

      "Example #{idx}:\n  Inputs: #{inspect(inputs)}\n  Outputs: #{inspect(outputs)}"
    end)
  end

  defp generate_additional_prompts(signature, sample_examples, count) do
    creativity_levels = [
      "be creative and think outside the box",
      "be precise and methodical",
      "be comprehensive and thorough",
      "focus on clarity and simplicity",
      "emphasize logical reasoning"
    ]

    1..count
    |> Enum.map(fn i ->
      creativity = Enum.at(creativity_levels, rem(i - 1, length(creativity_levels)))

      %{
        type: :variant,
        content: """
        Create an instruction for this task (#{creativity}):

        Signature: #{signature_name(signature)}
        Examples: #{format_examples_for_instruction(sample_examples)}

        Write an instruction that helps the model perform this task effectively.
        """
      }
    end)
  end

  defp signature_name(signature) do
    case signature do
      nil ->
        "Unknown"

      signature when is_atom(signature) ->
        # signature is a module atom
        signature
        |> Module.split()
        |> List.last()
    end
  end

  defp generate_single_instruction(prompt, config, correlation_id) do
    # Use instruction model if specified, otherwise use default
    model = config.instruction_model || get_default_instruction_model()

    messages = [
      %{
        role: "user",
        content: prompt.content
      }
    ]

    case Client.request(messages, %{provider: model, correlation_id: correlation_id}) do
      {:ok, response} ->
        instruction =
          response.choices
          |> List.first()
          |> get_in([Access.key(:message), Access.key(:content)])
          |> String.trim()

        {:ok, instruction}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_default_instruction_model do
    # Use the ConfigManager to get the default model for instruction generation
    ConfigManager.get_with_default([:teleprompters, :beacon, :default_instruction_model], :gemini)
  end

  defp build_default_instruction(signature) do
    {input_fields, output_fields} = get_signature_fields(signature)

    """
    Given the input fields #{Enum.join(input_fields, ", ")}, provide the output fields #{Enum.join(output_fields, ", ")}.
    Think step by step and provide accurate, well-reasoned responses.
    """
  end

  # Utility functions

  defp struct_to_keyword(struct) do
    struct
    |> Map.from_struct()
    |> Enum.to_list()
  end

  defp generate_correlation_id do
    node_hash = :erlang.phash2(node(), 65_536)
    timestamp = System.unique_integer([:positive])
    random = :erlang.unique_integer([:positive])
    "beacon-#{node_hash}-#{timestamp}-#{random}"
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    _ ->
      # Fail silently if telemetry is not available
      :ok
  end
end
