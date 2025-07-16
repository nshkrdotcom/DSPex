defmodule PoolExample do
  @moduledoc """
  DSPex Pool Example
  
  This module demonstrates the powerful pooling capabilities of DSPex V2,
  showing how to use SessionPoolV2 for high-performance concurrent operations.
  
  Features demonstrated:
  - Session-based pool operations with affinity
  - Anonymous pool operations for stateless tasks
  - Concurrent execution with proper pool management
  - Error handling and recovery
  - Performance monitoring
  - Different pooling strategies
  """

  require Logger
  alias DSPex.PythonBridge.SessionPoolV2
  
  # Custom DSPy I/O logging - controlled separately from application logging
  @dspy_io_logging Application.compile_env(:pool_example, :dspy_io_logging, true)
  
  defp log_dspy_input(context, input) do
    if @dspy_io_logging do
      IO.puts("🔍 #{context} INPUT: #{inspect(input)}")
    end
  end
  
  defp log_dspy_response(context, response) do
    if @dspy_io_logging do
      IO.puts("✅ #{context} DSPY RESPONSE: #{inspect(response)}")
    end
  end

  @doc """
  Run a basic pool test showing session affinity.
  
  This demonstrates how sessions maintain state across multiple operations
  on the same Python worker process.
  """
  def run_session_affinity_test do
    Logger.info("🔄 Running Session Affinity Test")
    
    # Ensure pool is started
    ensure_pool_started()
    
    # Create programs in different sessions
    session1 = "session_#{System.unique_integer([:positive])}"
    session2 = "session_#{System.unique_integer([:positive])}"
    
    Logger.info("📦 Creating programs in separate sessions...")
    
    # Session 1: Create a program
    {:ok, prog1_result} = SessionPoolV2.execute_in_session(
      session1,
      :create_program,
      %{
        id: "prog_session1_#{System.unique_integer([:positive])}",
        signature: %{
          inputs: [%{name: "question", type: "string"}],
          outputs: [%{name: "answer", type: "string"}]
        }
      }
    )
    
    prog1_id = prog1_result["program_id"]
    Logger.info("✅ Session 1 created program: #{prog1_id}")
    
    # Session 2: Create a different program
    {:ok, prog2_result} = SessionPoolV2.execute_in_session(
      session2,
      :create_program,
      %{
        id: "prog_session2_#{System.unique_integer([:positive])}",
        signature: %{
          inputs: [%{name: "text", type: "string"}],
          outputs: [%{name: "summary", type: "string"}]
        }
      }
    )
    
    prog2_id = prog2_result["program_id"]
    Logger.info("✅ Session 2 created program: #{prog2_id}")
    
    # Execute programs in their respective sessions
    Logger.info("\n🚀 Executing programs in their sessions...")
    
    # Session 1 execution
    input1 = %{question: "What is session affinity?"}
    log_dspy_input("Session 1", input1)
    
    {:ok, exec1_result} = SessionPoolV2.execute_in_session(
      session1,
      :execute_program,
      %{
        program_id: prog1_id,
        inputs: input1
      }
    )
    
    log_dspy_response("Session 1", exec1_result["outputs"])
    
    # Session 2 execution
    input2 = %{text: "Session affinity ensures that related operations stay on the same worker."}
    log_dspy_input("Session 2", input2)
    
    {:ok, exec2_result} = SessionPoolV2.execute_in_session(
      session2,
      :execute_program,
      %{
        program_id: prog2_id,
        inputs: input2
      }
    )
    
    log_dspy_response("Session 2", exec2_result["outputs"])
    
    # Clean up sessions
    SessionPoolV2.end_session(session1)
    SessionPoolV2.end_session(session2)
    
    Logger.info("\n🎉 Session Affinity Test Complete!")
  end

  @doc """
  Run anonymous pool operations test.
  
  This demonstrates stateless operations that can run on any available worker.
  Note: In pool-worker mode, anonymous programs are local to each worker.
  """
  def run_anonymous_operations_test do
    Logger.info("🎭 Running Anonymous Operations Test")
    
    ensure_pool_started()
    
    # For truly anonymous operations, we need to create and execute in a single worker checkout
    # Since anonymous operations don't maintain affinity between calls, we'll use temporary sessions
    Logger.info("\n🚀 Executing 5 concurrent operations with temporary sessions...")
    
    tasks = for i <- 1..5 do
      Task.async(fn ->
        start_time = System.monotonic_time(:millisecond)
        
        # Use a unique temporary session for each operation to ensure same worker
        temp_session = "temp_#{i}_#{System.unique_integer([:positive])}"
        
        # Create program in the temporary session with explicit timeout
        create_result = SessionPoolV2.execute_in_session(
          temp_session,
          :create_program,
          %{
            id: "prog_#{i}_#{System.unique_integer([:positive])}",
            signature: %{
              inputs: [%{name: "question", type: "string"}],
              outputs: [%{name: "answer", type: "string"}]
            }
          },
          pool_timeout: 90_000,
          timeout: 60_000
        )
        
        result = case create_result do
          {:ok, prog_result} ->
            prog_id = prog_result["program_id"]
            
            # Execute in the same session (ensures same worker)
            input = %{question: "What is #{i} + #{i}?"}
            log_dspy_input("Anonymous request #{i}", input)
            
            exec_result = SessionPoolV2.execute_in_session(
              temp_session,
              :execute_program,
              %{
                program_id: prog_id,
                inputs: input
              },
              pool_timeout: 90_000,
              timeout: 60_000
            )
            
            # Clean up the temporary session
            SessionPoolV2.end_session(temp_session)
            
            exec_result
            
          {:error, reason} ->
            SessionPoolV2.end_session(temp_session)
            {:error, reason}
        end
        
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        {i, result, duration}
      end)
    end
    
    # Collect results with longer timeout to account for worker initialization
    results = Task.await_many(tasks, 120_000)
    
    Enum.each(results, fn {i, result, duration} ->
      case result do
        {:ok, response} ->
          output = response["outputs"] || response
          log_dspy_response("Request #{i} (#{duration}ms)", output)
          Logger.info("✅ Request #{i} completed in #{duration}ms")
        {:error, reason} ->
          Logger.warning("❌ Request #{i} failed: #{inspect(reason)}")
      end
    end)
    
    # Also test create_program + execute_program pattern with session affinity
    Logger.info("\n📦 Testing create + execute with session affinity...")
    
    # Use a temporary session to ensure the same worker handles both operations
    temp_session = "temp_anon_#{System.unique_integer([:positive])}"
    
    case SessionPoolV2.execute_in_session(
      temp_session,
      :create_program,
      %{
        id: "session_prog_#{System.unique_integer([:positive])}",
        signature: %{
          inputs: [%{name: "text", type: "string"}],
          outputs: [%{name: "reversed", type: "string"}]
        }
      }
    ) do
      {:ok, prog_result} ->
        prog_id = prog_result["program_id"]
        Logger.info("✅ Created program in session: #{prog_id}")
        
        input = %{text: "Hello World"}
        log_dspy_input("Anonymous create+execute", input)
        
        case SessionPoolV2.execute_in_session(
          temp_session,
          :execute_program,
          %{
            program_id: prog_id,
            inputs: input
          }
        ) do
          {:ok, exec_result} ->
            log_dspy_response("Anonymous create+execute", exec_result["outputs"])
            Logger.info("✅ Executed program successfully")
          {:error, reason} ->
            Logger.warning("❌ Failed to execute program: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.warning("❌ Failed to create program: #{inspect(reason)}")
    end
    
    # Clean up session
    SessionPoolV2.end_session(temp_session)
    
    Logger.info("\n🎉 Anonymous Operations Test Complete!")
  end

  @doc """
  Run a concurrent stress test on the pool.
  
  This demonstrates the pool's ability to handle high concurrent load.
  """
  def run_concurrent_stress_test(num_operations \\ 20) do
    Logger.info("💪 Running Concurrent Stress Test with #{num_operations} operations")
    
    ensure_pool_started()
    
    # Get pool status before test
    initial_status = SessionPoolV2.get_pool_status()
    Logger.info("📊 Initial pool status: #{inspect(initial_status)}")
    
    # Launch concurrent operations
    Logger.info("\n🚀 Launching #{num_operations} concurrent operations...")
    start_time = System.monotonic_time(:millisecond)
    
    tasks = for i <- 1..num_operations do
      Task.async(fn ->
        op_start = System.monotonic_time(:millisecond)
        
        # Mix of session and anonymous operations
        result = if rem(i, 3) == 0 do
          # Session operation (33% of requests)
          session_id = "stress_session_#{rem(i, 5)}"  # Reuse 5 sessions
          
          # Create program if not exists (first time for this session)
          prog_id = "stress_prog_#{session_id}"
          create_result = SessionPoolV2.execute_in_session(
            session_id,
            :create_program,
            %{
              id: prog_id,
              signature: %{
                name: "Calculator",
                inputs: [%{name: "expression", type: "string"}],
                outputs: [%{name: "result", type: "string"}]
              }
            }
          )
          
          case create_result do
            {:ok, _} ->
              # Execute the program
              input = %{expression: "Calculate: #{i} * #{i}"}
              log_dspy_input("Stress test #{i} session", input)
              
              result = SessionPoolV2.execute_in_session(
                session_id,
                :execute_program,
                %{
                  program_id: prog_id,
                  inputs: input
                }
              )
              
              case result do
                {:ok, response} ->
                  log_dspy_response("Stress test #{i} session", response["outputs"])
                _ -> nil
              end
              
              result
            {:error, {:communication_error, :python_error, "Program with ID '" <> _rest, _}} ->
              # Program already exists, just execute
              input = %{expression: "Calculate: #{i} * #{i}"}
              log_dspy_input("Stress test #{i} session (retry)", input)
              
              result = SessionPoolV2.execute_in_session(
                session_id,
                :execute_program,
                %{
                  program_id: prog_id,
                  inputs: input
                }
              )
              
              case result do
                {:ok, response} ->
                  log_dspy_response("Stress test #{i} session (retry)", response["outputs"])
                _ -> nil
              end
              
              result
            error ->
              error
          end
        else
          # Anonymous operation (67% of requests)
          anon_id = "anon_stress_#{i}_#{System.unique_integer([:positive])}"
          create_result = SessionPoolV2.execute_anonymous(
            :create_program,
            %{
              id: anon_id,
              signature: %{
                name: "Calculator",
                inputs: [%{name: "expression", type: "string"}],
                outputs: [%{name: "result", type: "string"}]
              }
            }
          )
          
          case create_result do
            {:ok, prog_result} ->
              input = %{expression: "Calculate: #{i} * #{i}"}
              log_dspy_input("Stress test #{i} anonymous", input)
              
              result = SessionPoolV2.execute_anonymous(
                :execute_program,
                %{
                  program_id: prog_result["program_id"],
                  inputs: input
                }
              )
              
              case result do
                {:ok, response} ->
                  log_dspy_response("Stress test #{i} anonymous", response["outputs"])
                _ -> nil
              end
              
              result
            error ->
              error
          end
        end
        
        op_end = System.monotonic_time(:millisecond)
        {i, result, op_end - op_start}
      end)
    end
    
    # Collect all results with longer timeout for stress test
    results = Task.await_many(tasks, 180_000)
    end_time = System.monotonic_time(:millisecond)
    total_duration = end_time - start_time
    
    # Analyze results
    successful = Enum.count(results, fn {_, result, _} -> match?({:ok, _}, result) end)
    failed = num_operations - successful
    durations = Enum.map(results, fn {_, _, duration} -> duration end)
    avg_duration = if durations != [], do: Enum.sum(durations) / length(durations), else: 0
    max_duration = if durations != [], do: Enum.max(durations), else: 0
    min_duration = if durations != [], do: Enum.min(durations), else: 0
    
    # Get pool status after test
    final_status = SessionPoolV2.get_pool_status()
    
    Logger.info("\n📊 Stress Test Results:")
    Logger.info("   Total operations: #{num_operations}")
    Logger.info("   Successful: #{successful}")
    Logger.info("   Failed: #{failed}")
    Logger.info("   Total duration: #{total_duration}ms")
    Logger.info("   Average op duration: #{Float.round(avg_duration, 2)}ms")
    Logger.info("   Min op duration: #{min_duration}ms")
    Logger.info("   Max op duration: #{max_duration}ms")
    Logger.info("   Throughput: #{Float.round(num_operations / (total_duration / 1000), 2)} ops/sec")
    Logger.info("   Final pool status: #{inspect(final_status)}")
    
    Logger.info("\n🎉 Concurrent Stress Test Complete!")
  end

  @doc """
  Run error handling and recovery test.
  
  This demonstrates the pool's resilience to errors and recovery mechanisms.
  """
  def run_error_recovery_test do
    Logger.info("🛡️ Running Error Handling and Recovery Test")
    
    ensure_pool_started()
    
    # Test various error scenarios
    test_scenarios = [
      {"Invalid program ID", fn ->
        SessionPoolV2.execute_anonymous(
          :execute_program,
          %{
            program_id: "non_existent_program",
            inputs: %{test: "data"}
          }
        )
      end},
      
      {"Missing required inputs", fn ->
        case SessionPoolV2.execute_anonymous(
          :create_program,
          %{
            id: "test_prog_#{System.unique_integer([:positive])}",
            signature: %{
              inputs: [%{name: "required_field", type: "string"}],
              outputs: [%{name: "result", type: "string"}]
            }
          }
        ) do
          {:ok, prog_result} ->
            SessionPoolV2.execute_anonymous(
              :execute_program,
              %{
                program_id: prog_result["program_id"],
                inputs: %{}  # Missing required field
              }
            )
          error ->
            error
        end
      end},
      
      {"Invalid command", fn ->
        SessionPoolV2.execute_anonymous(
          :invalid_command,
          %{some: "data"}
        )
      end}
    ]
    
    Enum.each(test_scenarios, fn {scenario_name, test_fn} ->
      Logger.info("\n🧪 Testing: #{scenario_name}")
      
      result = try do
        test_fn.()
      rescue
        error ->
          Logger.warning("❌ Test function crashed: #{inspect(error)}")
          {:error, :test_crashed}
      catch
        :exit, reason ->
          Logger.warning("❌ Test function exited: #{inspect(reason)}")
          {:error, :test_exited}
      end
      
      case result do
        {:error, error_tuple} when is_tuple(error_tuple) and tuple_size(error_tuple) == 4 ->
          {category, type, message, context} = error_tuple
          Logger.info("✅ Properly handled error:")
          Logger.info("   Category: #{category}")
          Logger.info("   Type: #{type}")
          Logger.info("   Message: #{message}")
          Logger.info("   Context: #{inspect(context)}")
          
        {:error, reason} ->
          Logger.info("✅ Error returned: #{inspect(reason)}")
          
        other ->
          Logger.warning("❌ Unexpected result: #{inspect(other)}")
      end
    end)
    
    Logger.info("\n🎉 Error Handling and Recovery Test Complete!")
  end

  @doc """
  Run all pool example tests.
  """
  def run_all_tests do
    Logger.info("🚀 Running All DSPex Pool Example Tests\n")
    
    tests = [
      {"Session Affinity Test", &run_session_affinity_test/0},
      {"Anonymous Operations Test", &run_anonymous_operations_test/0},
      {"Concurrent Stress Test", fn -> run_concurrent_stress_test(10) end},
      {"Error Recovery Test", &run_error_recovery_test/0}
    ]
    
    results = Enum.map(tests, fn {name, test_fn} ->
      try do
        Logger.info("Running #{name}...")
        test_fn.()
        {name, :ok}
      rescue
        error ->
          Logger.error("❌ #{name} failed: #{inspect(error)}")
          {name, {:error, error}}
      catch
        :exit, reason ->
          Logger.error("❌ #{name} exited: #{inspect(reason)}")
          {name, {:exit, reason}}
      end
    end)
    
    # Report results
    successful = Enum.count(results, fn {_, result} -> result == :ok end)
    total = length(results)
    
    Logger.info("\n📊 Test Results: #{successful}/#{total} passed")
    
    if successful == total do
      Logger.info("\n🎉 All Pool Example Tests Complete!")
      Logger.info("💡 This demonstrates DSPex V2's robust pooling capabilities")
    else
      Logger.warning("\n⚠️  Some tests failed - check logs above")
      Logger.info("💡 Error handling tests are expected to show Python errors")
    end
  end

  # Private helper functions

  defp ensure_pool_started do
    case Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
      nil ->
        Logger.info("SessionPoolV2 not running. It should be started by the application.")
        Logger.info("Attempting to start it manually...")
        case DSPex.PythonBridge.SessionPoolV2.start_link(
          name: DSPex.PythonBridge.SessionPoolV2,
          pool_size: 4,
          overflow: 2
        ) do
          {:ok, _pid} ->
            Logger.info("✅ SessionPoolV2 started successfully")
            :ok
          {:error, {:already_started, _pid}} ->
            Logger.info("✅ SessionPoolV2 already running")
            :ok
          error ->
            Logger.error("Failed to start SessionPoolV2: #{inspect(error)}")
            error
        end
      _pid ->
        :ok
    end
  end
end