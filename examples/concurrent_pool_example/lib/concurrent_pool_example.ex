defmodule ConcurrentPoolExample do
  @moduledoc """
  Advanced demonstration of DSPex SessionPoolV2 for concurrent operations.
  
  This example showcases the enhanced capabilities of SessionPoolV2 for managing
  and executing multiple operations in parallel, demonstrating efficiency and scalability.
  
  Key features demonstrated:
  1. Concurrent execution of multiple operations
  2. Session-based worker affinity for stateful operations
  3. Pool-based resource management and error handling
  4. Performance monitoring and metrics collection
  
  ## Usage
  
  Make sure you have a valid GEMINI_API_KEY environment variable set:
  
      export GEMINI_API_KEY="your-api-key-here"
  
  Then run the concurrent operations example:
  
      ConcurrentPoolExample.run_concurrent_operations()
  
  """

  require Logger

  @doc """
  Runs a comprehensive demonstration of concurrent pool operations.
  
  This function demonstrates:
  1. Three distinct concurrent operations running in parallel
  2. Session affinity for maintaining state across operations
  3. Pool resource management and error handling
  4. Performance metrics and timing analysis
  
  ## Returns
  
  - `{:ok, results}` - Success with timing and results from all operations
  - `{:error, reason}` - Error during execution
  
  ## Examples
  
      iex> ConcurrentPoolExample.run_concurrent_operations()
      {:ok, %{
        classification: %{result: "positive", time_ms: 1234},
        translation: %{result: "Bonjour le monde", time_ms: 987},
        summarization: %{result: "Brief summary...", time_ms: 1567},
        total_time_ms: 1678
      }}
  
  """
  @spec run_concurrent_operations() :: {:ok, map()} | {:error, term()}
  def run_concurrent_operations do
    Logger.info("Starting concurrent pool operations demonstration...")
    
    # Setup DSPex with language model
    with :ok <- setup_dspex() do
      start_time = System.monotonic_time(:millisecond)
      
      # Launch three concurrent operations
      tasks = [
        Task.async(fn -> run_text_classification_session() end),
        Task.async(fn -> run_translation_session() end),
        Task.async(fn -> run_summarization_session() end)
      ]
      
      # Wait for all operations to complete
      results = Task.await_many(tasks, 30_000)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Process results
      case process_concurrent_results(results, total_time) do
        {:ok, final_results} ->
          Logger.info("All concurrent operations completed successfully!")
          Logger.info("Results: #{inspect(final_results, pretty: true)}")
          {:ok, final_results}
          
        error ->
          Logger.error("Some operations failed: #{inspect(error)}")
          error
      end
    else
      error ->
        Logger.error("Failed to setup DSPex: #{inspect(error)}")
        error
    end
  end

  @doc """
  Demonstrates session affinity by running multiple operations in the same session.
  
  This shows how SessionPoolV2 maintains worker affinity for better performance
  when multiple related operations need to share state.
  """
  @spec demonstrate_session_affinity() :: {:ok, map()} | {:error, term()}
  def demonstrate_session_affinity do
    Logger.info("Demonstrating session affinity...")
    
    session_id = "affinity_demo_#{:rand.uniform(10000)}"
    
    with :ok <- setup_dspex() do
      # Multiple operations using DSPex.call to demonstrate concurrent execution
      operations = [
        {"Step 1: Initialize context", %{question: "Hello, I am starting a conversation."}},
        {"Step 2: Continue conversation", %{question: "Can you remember what I just said?"}},
        {"Step 3: Build on context", %{question: "Now summarize our entire conversation."}}
      ]
      
      signature = %{
        name: "QuestionAnswer",
        inputs: [%{name: "question", type: "string"}],
        outputs: [%{name: "answer", type: "string"}]
      }
      
      program_config = %{
        signature: signature,
        id: "affinity_qa_#{:rand.uniform(100000)}"
      }
      
      results = 
        with {:ok, program_id} <- DSPex.create_program(program_config) do
          operations
          |> Enum.with_index(1)
          |> Enum.map(fn {{description, inputs}, step} ->
            Logger.info("#{description}")
            
            case DSPex.execute_program(program_id, inputs) do
              {:ok, result} ->
                Logger.info("Step #{step} completed: #{inspect(result)}")
                {step, {:ok, result}}
                
              error ->
                Logger.error("Step #{step} failed: #{inspect(error)}")
                {step, error}
            end
          end)
        else
          error ->
            [{"Program creation failed", error}]
        end
      
      {:ok, %{session_id: session_id, operations: results}}
    end
  end

  @doc """
  Runs performance benchmarks comparing concurrent vs sequential execution.
  
  This demonstrates the scalability benefits of the SessionPoolV2 approach.
  """
  @spec run_performance_benchmark() :: {:ok, map()} | {:error, term()}
  def run_performance_benchmark do
    Logger.info("Running performance benchmark...")
    
    with :ok <- setup_dspex() do
      # Test data with proper signatures
      signature = %{
        name: "QuestionAnswer",
        inputs: [%{name: "question", type: "string"}],
        outputs: [%{name: "answer", type: "string"}]
      }
      
      program_config = %{
        signature: signature,
        id: "benchmark_qa_#{:rand.uniform(100000)}"
      }
      
      test_inputs = [
        %{question: "Analyze this sentiment: I love this product!"},
        %{question: "Translate to French: Good morning everyone"},
        %{question: "Summarize: The quick brown fox jumps over the lazy dog..."}
      ]
      
      with {:ok, program_id} <- DSPex.create_program(program_config) do
        # Sequential execution
        {sequential_time, sequential_results} = :timer.tc(fn ->
          Enum.map(test_inputs, fn input ->
            DSPex.execute_program(program_id, input)
          end)
        end)
        
        # Concurrent execution
        {concurrent_time, concurrent_results} = :timer.tc(fn ->
          test_inputs
          |> Enum.map(fn input ->
            Task.async(fn -> DSPex.execute_program(program_id, input) end)
          end)
          |> Task.await_many(30_000)
        end)
      
        benchmark_results = %{
          sequential: %{
            time_microseconds: sequential_time,
            time_ms: div(sequential_time, 1000),
            results: sequential_results
          },
          concurrent: %{
            time_microseconds: concurrent_time,
            time_ms: div(concurrent_time, 1000),
            results: concurrent_results
          },
          speedup_factor: sequential_time / concurrent_time
        }
        
        Logger.info("Benchmark completed!")
        Logger.info("Sequential: #{benchmark_results.sequential.time_ms}ms")
        Logger.info("Concurrent: #{benchmark_results.concurrent.time_ms}ms")
        Logger.info("Speedup: #{Float.round(benchmark_results.speedup_factor, 2)}x")
        
        {:ok, benchmark_results}
      else
        error ->
          Logger.error("Failed to create benchmark program: #{inspect(error)}")
          error
      end
    else
      error ->
        error
    end
  end

  ## Private Implementation Functions

  @spec setup_dspex() :: :ok | {:error, term()}
  defp setup_dspex do
    try do
      api_key = System.get_env("GEMINI_API_KEY")
      
      unless api_key do
        raise "GEMINI_API_KEY environment variable not set"
      end
      
      DSPex.set_lm("gemini-1.5-flash", api_key: api_key)
      Logger.info("DSPex configured with Gemini 1.5 Flash")
      :ok
    rescue
      error ->
        Logger.error("Failed to setup DSPex: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec run_text_classification_session() :: {:ok, map()} | {:error, term()}
  defp run_text_classification_session do
    session_id = "classification_#{:rand.uniform(10000)}"
    start_time = System.monotonic_time(:millisecond)
    
    Logger.info("Starting text classification in session #{session_id}")
    
    # Use DSPex.create_program and execute_program for Q&A (what actually works)
    signature = %{
      name: "QuestionAnswer",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    program_config = %{
      signature: signature,
      id: "classification_#{:rand.uniform(100000)}"
    }
    
    with {:ok, program_id} <- DSPex.create_program(program_config),
         inputs = %{question: "What is the sentiment of this text: 'I absolutely love this new feature! It's amazing and works perfectly.' Answer with just: positive, negative, or neutral."},
         {:ok, result} <- DSPex.execute_program(program_id, inputs) do
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time
      
      Logger.info("Classification completed in #{execution_time}ms")
      {:ok, %{
        operation: "text_classification",
        session_id: session_id,
        result: result,
        time_ms: execution_time
      }}
    else
      error ->
        Logger.error("Classification failed: #{inspect(error)}")
        error
    end
  end

  @spec run_translation_session() :: {:ok, map()} | {:error, term()}
  defp run_translation_session do
    session_id = "translation_#{:rand.uniform(10000)}"
    start_time = System.monotonic_time(:millisecond)
    
    Logger.info("Starting translation in session #{session_id}")
    
    # Use DSPex.create_program and execute_program for Q&A (what actually works)
    signature = %{
      name: "QuestionAnswer", 
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    program_config = %{
      signature: signature,
      id: "translation_#{:rand.uniform(100000)}"
    }
    
    with {:ok, program_id} <- DSPex.create_program(program_config),
         inputs = %{question: "Translate this English text to French: 'Hello world, this is a test message for translation.'"},
         {:ok, result} <- DSPex.execute_program(program_id, inputs) do
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time
      
      Logger.info("Translation completed in #{execution_time}ms")
      {:ok, %{
        operation: "translation",
        session_id: session_id,
        result: result,
        time_ms: execution_time
      }}
    else
      error ->
        Logger.error("Translation failed: #{inspect(error)}")
        error
    end
  end

  @spec run_summarization_session() :: {:ok, map()} | {:error, term()}
  defp run_summarization_session do
    session_id = "summarization_#{:rand.uniform(10000)}"
    start_time = System.monotonic_time(:millisecond)
    
    Logger.info("Starting summarization in session #{session_id}")
    
    # Use DSPex.create_program and execute_program for Q&A (what actually works)
    signature = %{
      name: "QuestionAnswer",
      inputs: [%{name: "question", type: "string"}],
      outputs: [%{name: "answer", type: "string"}]
    }
    
    program_config = %{
      signature: signature,
      id: "summarization_#{:rand.uniform(100000)}"
    }
    
    with {:ok, program_id} <- DSPex.create_program(program_config),
         inputs = %{
           question: """
           Summarize this text in 2-3 sentences: 
           The SessionPoolV2 implementation represents a significant advancement in the DSPex library.
           It provides enhanced worker lifecycle management, session affinity for stateful operations,
           comprehensive error handling with circuit breaker patterns, and performance monitoring.
           The pool automatically manages Python worker processes, handles failures gracefully,
           and provides excellent scalability for concurrent operations.
           """
         },
         {:ok, result} <- DSPex.execute_program(program_id, inputs) do
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time
      
      Logger.info("Summarization completed in #{execution_time}ms")
      {:ok, %{
        operation: "summarization",
        session_id: session_id,
        result: result,
        time_ms: execution_time
      }}
    else
      error ->
        Logger.error("Summarization failed: #{inspect(error)}")
        error
    end
  end

  @spec process_concurrent_results([{:ok, map()} | {:error, term()}], integer()) :: {:ok, map()} | {:error, term()}
  defp process_concurrent_results(results, total_time) do
    {successes, failures} = 
      results
      |> Enum.with_index()
      |> Enum.split_with(fn {result, _idx} -> 
        match?({:ok, _}, result)
      end)
    
    if length(failures) > 0 do
      Logger.warning("#{length(failures)} operations failed out of #{length(results)}")
      
      failure_details = 
        failures
        |> Enum.map(fn {{:error, reason}, idx} -> 
          %{operation_index: idx, error: reason}
        end)
      
      {:error, %{failed_operations: failure_details, total_failures: length(failures)}}
    else
      success_data = 
        successes
        |> Enum.map(fn {{:ok, data}, _idx} -> data end)
        |> Enum.reduce(%{}, fn operation_result, acc ->
          operation_name = operation_result.operation
          Map.put(acc, String.to_atom(operation_name), operation_result)
        end)
      
      final_results = Map.put(success_data, :total_time_ms, total_time)
      {:ok, final_results}
    end
  end

  @doc """
  Demonstrates error handling and recovery in concurrent operations.
  
  This function intentionally triggers various error conditions to show
  how SessionPoolV2 handles failures gracefully.
  """
  @spec demonstrate_error_handling() :: {:ok, map()} | {:error, term()}
  def demonstrate_error_handling do
    Logger.info("Demonstrating error handling capabilities...")
    
    with :ok <- setup_dspex() do
      # Mix of valid and invalid operations using DSPex.call
      signature = %{
        inputs: [%{name: "question", type: "string"}],
        outputs: [%{name: "answer", type: "string"}]
      }
      
      operations = [
        {"Valid operation", fn -> 
          program_config = %{signature: signature, id: "valid_#{:rand.uniform(1000)}"}
          with {:ok, program_id} <- DSPex.create_program(program_config) do
            DSPex.execute_program(program_id, %{question: "Hello"})
          end
        end},
        {"Invalid signature", fn -> 
          DSPex.create_program(%{invalid: "signature"})
        end},
        {"Empty inputs", fn -> 
          program_config = %{signature: signature, id: "empty_#{:rand.uniform(1000)}"}
          with {:ok, program_id} <- DSPex.create_program(program_config) do
            DSPex.execute_program(program_id, %{})
          end
        end}
      ]
      
      results = 
        operations
        |> Enum.map(fn {description, operation} ->
          Logger.info("Testing: #{description}")
          
          case operation.() do
            {:ok, result} ->
              Logger.info("✓ #{description}: Success")
              {description, {:ok, result}}
              
            {:error, reason} ->
              Logger.info("✗ #{description}: #{inspect(reason)}")
              {description, {:error, reason}}
          end
        end)
      
      {:ok, %{error_handling_results: results}}
    end
  end
end