defmodule DSPex.Test.DataGenerators do
  @moduledoc """
  Test data generators for DSPex testing.

  Provides functions to generate realistic test data for various
  components of the system, ensuring consistent and meaningful test scenarios.
  """

  @doc """
  Generates a unique session ID for testing.
  """
  def session_id(prefix \\ "test") do
    "#{prefix}_#{System.unique_integer([:positive])}_#{:rand.uniform(10000)}"
  end

  @doc """
  Generates a batch of unique session IDs.
  """
  def session_ids(count, prefix \\ "test") do
    for i <- 1..count, do: "#{prefix}_#{i}_#{System.unique_integer([:positive])}"
  end

  @doc """
  Generates a program configuration with signature.
  """
  def program_config(opts \\ []) do
    type = Keyword.get(opts, :type, :simple)

    %{
      id: "test_program_#{System.unique_integer([:positive])}",
      signature: signature(type),
      description: "Test program for #{type} operations",
      metadata: %{
        created_at: DateTime.utc_now(),
        test_type: type
      }
    }
  end

  @doc """
  Generates different types of signatures for testing.
  """
  def signature(:simple) do
    %{
      inputs: [
        %{name: "query", type: "string", description: "Input query"}
      ],
      outputs: [
        %{name: "answer", type: "string", description: "Generated answer"}
      ]
    }
  end

  def signature(:complex) do
    %{
      inputs: [
        %{name: "context", type: "string", description: "Context information"},
        %{name: "question", type: "string", description: "User question"},
        %{name: "options", type: "object", description: "Additional options"}
      ],
      outputs: [
        %{name: "answer", type: "string", description: "Generated answer"},
        %{name: "confidence", type: "number", description: "Confidence score"},
        %{name: "sources", type: "array", description: "Source references"}
      ]
    }
  end

  def signature(:chain) do
    %{
      inputs: [
        %{name: "initial_input", type: "string", description: "Starting input"}
      ],
      outputs: [
        %{name: "step1_result", type: "string", description: "First transformation"},
        %{name: "step2_result", type: "string", description: "Second transformation"},
        %{name: "final_result", type: "string", description: "Final output"}
      ]
    }
  end

  def signature(:custom, fields) do
    %{
      inputs: Keyword.get(fields, :inputs, []),
      outputs: Keyword.get(fields, :outputs, [])
    }
  end

  @doc """
  Generates test input data matching a signature.
  """
  def inputs_for_signature(:simple) do
    %{
      "query" => Faker.Lorem.sentence()
    }
  end

  def inputs_for_signature(:complex) do
    %{
      "context" => Faker.Lorem.paragraph(),
      "question" => Faker.Lorem.sentence() <> "?",
      "options" => %{
        "temperature" => :rand.uniform(),
        "max_tokens" => Enum.random([100, 200, 500]),
        "mode" => Enum.random(["concise", "detailed", "technical"])
      }
    }
  end

  def inputs_for_signature(:chain) do
    %{
      "initial_input" => Faker.Lorem.words(3) |> Enum.join(" ")
    }
  end

  @doc """
  Generates a batch of operations for load testing.
  """
  def bulk_operations(count, opts \\ []) do
    session_id = Keyword.get(opts, :session_id, session_id())
    types = Keyword.get(opts, :types, [:create, :execute, :list, :delete])

    {operations, _} =
      Enum.reduce(1..count, {[], []}, fn i, {ops, programs} ->
        type = Enum.random(types)

        {op, updated_programs} =
          case type do
            :create ->
              config = program_config(type: Enum.random([:simple, :complex, :chain]))
              programs_new = [config.id | programs]

              op = %{
                type: :create,
                data: config,
                session_id: session_id,
                index: i
              }

              {op, programs_new}

            :execute ->
              if programs == [] do
                # Create a program first
                config = program_config(type: :simple)

                op = %{
                  type: :create,
                  data: config,
                  session_id: session_id,
                  index: i
                }

                {op, [config.id | programs]}
              else
                program_id = Enum.random(programs)

                op = %{
                  type: :execute,
                  data: %{
                    program_id: program_id,
                    inputs: inputs_for_signature(:simple)
                  },
                  session_id: session_id,
                  index: i
                }

                {op, programs}
              end

            :list ->
              op = %{
                type: :list,
                data: %{},
                session_id: session_id,
                index: i
              }

              {op, programs}

            :delete ->
              if programs == [] do
                # Skip delete if no programs
                op = %{
                  type: :list,
                  data: %{},
                  session_id: session_id,
                  index: i
                }

                {op, programs}
              else
                program_id = Enum.random(programs)
                programs_new = List.delete(programs, program_id)

                op = %{
                  type: :delete,
                  data: %{program_id: program_id},
                  session_id: session_id,
                  index: i
                }

                {op, programs_new}
              end
          end

        {[op | ops], updated_programs}
      end)

    Enum.reverse(operations)
  end

  @doc """
  Generates realistic workload patterns.
  """
  def workload_pattern(:steady, duration_seconds) do
    operations_per_second = 10

    for second <- 0..duration_seconds do
      %{
        timestamp: second,
        operations: operations_per_second
      }
    end
  end

  def workload_pattern(:ramp_up, duration_seconds) do
    max_ops = 50

    for second <- 0..duration_seconds do
      progress = second / duration_seconds
      operations = round(max_ops * progress)

      %{
        timestamp: second,
        operations: operations
      }
    end
  end

  def workload_pattern(:spike, duration_seconds) do
    base_ops = 5
    spike_ops = 100
    spike_start = div(duration_seconds, 3)
    spike_end = spike_start + div(duration_seconds, 6)

    for second <- 0..duration_seconds do
      operations =
        if second >= spike_start and second <= spike_end do
          spike_ops
        else
          base_ops
        end

      %{
        timestamp: second,
        operations: operations
      }
    end
  end

  def workload_pattern(:burst, duration_seconds) do
    burst_interval = 10
    burst_ops = 50
    idle_ops = 2

    for second <- 0..duration_seconds do
      operations =
        if rem(second, burst_interval) == 0 do
          burst_ops
        else
          idle_ops
        end

      %{
        timestamp: second,
        operations: operations
      }
    end
  end

  @doc """
  Generates error scenarios for chaos testing.
  """
  def error_scenario(:network_failure) do
    %{
      type: :network_failure,
      duration_ms: Enum.random([100, 500, 1000, 5000]),
      pattern: Enum.random([:complete_loss, :intermittent, :high_latency])
    }
  end

  def error_scenario(:resource_exhaustion) do
    %{
      type: :resource_exhaustion,
      resource: Enum.random([:memory, :cpu, :file_descriptors]),
      severity: Enum.random([0.5, 0.8, 0.95, 1.0])
    }
  end

  def error_scenario(:worker_crash) do
    %{
      type: :worker_crash,
      target: Enum.random([:random, :oldest, :newest, :busiest]),
      count: Enum.random([1, 2, 3])
    }
  end

  def error_scenario(:slow_operations) do
    %{
      type: :slow_operations,
      delay_ms: Enum.random([1000, 5000, 10000, 30000]),
      probability: Enum.random([0.1, 0.25, 0.5, 1.0])
    }
  end

  @doc """
  Generates expected outputs for verification.
  """
  def expected_output(:simple, inputs) do
    %{
      "answer" => "Response to: #{inputs["query"]}"
    }
  end

  def expected_output(:complex, inputs) do
    %{
      "answer" => "Answer considering context: #{String.slice(inputs["context"], 0..50)}...",
      "confidence" => 0.85,
      "sources" => ["source1", "source2"]
    }
  end

  def expected_output(:chain, inputs) do
    %{
      "step1_result" => "Processed: #{inputs["initial_input"]}",
      "step2_result" => "Transformed: #{inputs["initial_input"]}",
      "final_result" => "Final: #{inputs["initial_input"]}"
    }
  end

  @doc """
  Generates performance expectations for benchmarking.
  """
  def performance_expectations(operation_type) do
    case operation_type do
      :create_program ->
        %{
          p50_ms: 50,
          p95_ms: 100,
          p99_ms: 200,
          max_ms: 500
        }

      :execute_simple ->
        %{
          p50_ms: 100,
          p95_ms: 300,
          p99_ms: 500,
          max_ms: 1000
        }

      :execute_complex ->
        %{
          p50_ms: 500,
          p95_ms: 2000,
          p99_ms: 5000,
          max_ms: 10000
        }

      :list_programs ->
        %{
          p50_ms: 20,
          p95_ms: 50,
          p99_ms: 100,
          max_ms: 200
        }

      :pool_checkout ->
        %{
          p50_ms: 1,
          p95_ms: 5,
          p99_ms: 10,
          max_ms: 50
        }
    end
  end
end

# Add Faker-like functionality for test data
defmodule Faker do
  defmodule Lorem do
    def word do
      Enum.random(["test", "data", "example", "sample", "demo", "mock", "placeholder"])
    end

    def words(count) do
      for _ <- 1..count, do: word()
    end

    def sentence do
      count = Enum.random(5..10)
      words(count) |> Enum.join(" ") |> String.capitalize()
    end

    def paragraph do
      count = Enum.random(3..5)

      for _ <- 1..count,
          do:
            sentence()
            |> Enum.join(". ")
            |> Kernel.<>(".")
    end
  end
end
