#!/usr/bin/env elixir

# DSPex V3 Pool - Production Scenario
# Simulates real-world usage patterns
# Run with: elixir examples/pool_v3_production.exs

Mix.install([
  {:dspex, path: "."}
])

defmodule ProductionScenario do
  require Logger
  
  @scenarios [
    chatbot: "Simulates a chatbot handling user queries",
    api_backend: "API server processing ML requests", 
    batch_processor: "Batch job processing documents",
    mixed_workload: "Combination of all patterns"
  ]
  
  def run do
    IO.puts("\n🏭 DSPex V3 Pool - Production Scenarios")
    IO.puts("=" |> String.duplicate(60))
    
    setup_environment()
    
    IO.puts("\nSelect scenario:")
    @scenarios
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, desc}, idx} ->
      IO.puts("  #{idx}. #{name} - #{desc}")
    end)
    IO.puts("  5. Run all scenarios")
    
    case IO.gets("\nYour choice (1-5): ") |> String.trim() do
      "1" -> run_chatbot_scenario()
      "2" -> run_api_scenario()
      "3" -> run_batch_scenario()
      "4" -> run_mixed_scenario()
      "5" -> run_all_scenarios()
      _ -> IO.puts("Invalid choice")
    end
  end
  
  defp setup_environment do
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Configure V3 pool for production
    Application.put_env(:dspex, :pool_config, %{
      v2_enabled: false,
      v3_enabled: true,
      pool_size: System.schedulers_online() * 2  # Production sizing
    })
    Application.put_env(:dspex, :pooling_enabled, true)
    
    # Start the pool
    IO.puts("\n🚀 Starting V3 Pool...")
    {startup_time, _} = :timer.tc(fn ->
      {:ok, _} = DSPex.Python.Registry.child_spec([]) |> Supervisor.start_link()
      {:ok, _} = DSPex.Python.WorkerSupervisor.start_link([])
      {:ok, _} = DSPex.Python.Pool.start_link()
      {:ok, _} = DSPex.PythonBridge.SessionStore.start_link()
    end)
    
    IO.puts("✅ Pool ready in #{div(startup_time, 1000)}ms")
    stats = DSPex.Python.Pool.get_stats()
    IO.puts("📊 Workers: #{stats.workers} | Available: #{stats.available}")
  end
  
  defp run_chatbot_scenario do
    IO.puts("\n💬 Chatbot Scenario - Handling user conversations")
    IO.puts("-" |> String.duplicate(50))
    
    # Create chatbot program
    {:ok, _} = DSPex.Python.Pool.execute(:create_program, %{
      id: "chatbot",
      signature: "user_message -> bot_response",
      instructions: "You are a helpful assistant. Be concise."
    })
    
    # Simulate users
    users = for i <- 1..20, do: "user_#{i}"
    
    IO.puts("Simulating 20 concurrent users...")
    start = System.monotonic_time(:millisecond)
    
    # Each user sends 5 messages
    tasks = for user <- users do
      Task.async(fn ->
        for msg_num <- 1..5 do
          DSPex.Python.SessionAdapter.execute_in_session(
            user,
            :execute_program,
            %{
              program_id: "chatbot",
              inputs: %{user_message: "Message #{msg_num} from #{user}"}
            }
          )
        end
      end)
    end
    
    Task.await_many(tasks, 30_000)
    elapsed = System.monotonic_time(:millisecond) - start
    
    IO.puts("\n📊 Results:")
    IO.puts("   Handled: 100 messages (20 users × 5 messages)")
    IO.puts("   Time: #{elapsed}ms")
    IO.puts("   Throughput: #{Float.round(100_000 / elapsed, 1)} msg/s")
    
    show_pool_health()
  end
  
  defp run_api_scenario do
    IO.puts("\n🌐 API Backend Scenario - High-throughput requests")
    IO.puts("-" |> String.duplicate(50))
    
    # Create classifier program
    {:ok, _} = DSPex.Python.Pool.execute(:create_program, %{
      id: "classifier",
      signature: "text -> category",
      instructions: "Classify text into categories: tech, business, sports, other"
    })
    
    IO.puts("Simulating API traffic spike...")
    
    # Simulate varying load
    phases = [
      {50, "Normal load"},
      {200, "Traffic spike"},
      {100, "Sustained high"},
      {25, "Cool down"}
    ]
    
    for {requests, description} <- phases do
      IO.puts("\n#{description}: #{requests} requests")
      
      start = System.monotonic_time(:millisecond)
      
      tasks = for i <- 1..requests do
        Task.async(fn ->
          DSPex.Python.Pool.execute(:execute_program, %{
            program_id: "classifier",
            inputs: %{text: "Sample text #{i} about technology and AI"}
          })
        end)
      end
      
      results = Task.await_many(tasks, 30_000)
      elapsed = System.monotonic_time(:millisecond) - start
      success = Enum.count(results, &match?({:ok, _}, &1))
      
      IO.puts("   Success: #{success}/#{requests}")
      IO.puts("   Time: #{elapsed}ms")
      IO.puts("   Rate: #{Float.round(requests * 1000 / elapsed, 1)} req/s")
    end
    
    show_pool_health()
  end
  
  defp run_batch_scenario do
    IO.puts("\n📄 Batch Processing Scenario - Document analysis")
    IO.puts("-" |> String.duplicate(50))
    
    # Create summarizer
    {:ok, _} = DSPex.Python.Pool.execute(:create_program, %{
      id: "summarizer",
      signature: "document -> summary",
      instructions: "Create a brief summary of the document"
    })
    
    # Simulate batch of documents
    documents = for i <- 1..50 do
      %{
        id: "doc_#{i}",
        content: "This is document #{i}. " |> String.duplicate(10)
      }
    end
    
    IO.puts("Processing batch of #{length(documents)} documents...")
    
    start = System.monotonic_time(:millisecond)
    
    # Process in parallel batches
    documents
    |> Enum.chunk_every(10)
    |> Enum.each(fn batch ->
      tasks = for doc <- batch do
        Task.async(fn ->
          {doc.id, DSPex.Python.Pool.execute(:execute_program, %{
            program_id: "summarizer",
            inputs: %{document: doc.content}
          })}
        end)
      end
      
      Task.await_many(tasks, 30_000)
      IO.write(".")
    end)
    
    elapsed = System.monotonic_time(:millisecond) - start
    
    IO.puts("\n\n📊 Results:")
    IO.puts("   Processed: #{length(documents)} documents")
    IO.puts("   Time: #{elapsed}ms")
    IO.puts("   Rate: #{Float.round(length(documents) * 1000 / elapsed, 1)} docs/s")
    
    show_pool_health()
  end
  
  defp run_mixed_scenario do
    IO.puts("\n🎯 Mixed Workload Scenario - Real production patterns")
    IO.puts("-" |> String.duplicate(50))
    
    # Create multiple programs
    programs = ["chatbot", "classifier", "summarizer", "calculator"]
    for prog <- programs do
      {:ok, _} = DSPex.Python.Pool.execute(:create_program, %{
        id: prog,
        signature: "input -> output",
        instructions: "Process #{prog} requests"
      })
    end
    
    IO.puts("Running mixed workload for 10 seconds...")
    
    # Track metrics
    counter = :counters.new(4, [:atomics])
    
    # Start different workload generators
    tasks = [
      # Steady chat messages
      Task.async(fn -> 
        generate_load("chatbot", 10, 100, counter, 1)
      end),
      
      # Bursty API calls
      Task.async(fn ->
        generate_load("classifier", 50, 50, counter, 2)
      end),
      
      # Heavy batch jobs
      Task.async(fn ->
        generate_load("summarizer", 2, 500, counter, 3)
      end),
      
      # Quick calculations
      Task.async(fn ->
        generate_load("calculator", 100, 10, counter, 4)
      end)
    ]
    
    # Run for 10 seconds
    Process.sleep(10_000)
    
    # Stop generators
    Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    
    IO.puts("\n📊 Results:")
    IO.puts("   Chatbot requests: #{:counters.get(counter, 1)}")
    IO.puts("   API requests: #{:counters.get(counter, 2)}")
    IO.puts("   Batch jobs: #{:counters.get(counter, 3)}")
    IO.puts("   Calculations: #{:counters.get(counter, 4)}")
    IO.puts("   Total: #{:counters.get(counter, 1) + :counters.get(counter, 2) + :counters.get(counter, 3) + :counters.get(counter, 4)}")
    
    show_pool_health()
  end
  
  defp run_all_scenarios do
    scenarios = [
      &run_chatbot_scenario/0,
      &run_api_scenario/0,
      &run_batch_scenario/0,
      &run_mixed_scenario/0
    ]
    
    for scenario <- scenarios do
      scenario.()
      IO.puts("\nPress Enter to continue...")
      IO.gets("")
    end
  end
  
  defp generate_load(program, rate_per_sec, delay_ms, counter, index) do
    interval = div(1000, rate_per_sec)
    
    Stream.repeatedly(fn ->
      Task.start(fn ->
        case DSPex.Python.Pool.execute(:execute_program, %{
          program_id: program,
          inputs: %{input: "test"}
        }) do
          {:ok, _} -> :counters.add(counter, index, 1)
          _ -> :ok
        end
      end)
      
      Process.sleep(interval)
    end)
    |> Stream.run()
  end
  
  defp show_pool_health do
    stats = DSPex.Python.Pool.get_stats()
    
    IO.puts("\n🏥 Pool Health:")
    IO.puts("   Workers: #{stats.workers} (#{stats.available} available, #{stats.busy} busy)")
    IO.puts("   Requests: #{stats.requests} total, #{stats.errors} errors")
    IO.puts("   Queue: #{stats.queued} queued, #{stats.queue_timeouts} timeouts")
  end
end

# Run the production scenario
ProductionScenario.run()