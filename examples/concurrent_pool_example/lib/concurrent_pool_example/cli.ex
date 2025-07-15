defmodule ConcurrentPoolExample.CLI do
  @moduledoc """
  Command-line interface for the Concurrent Pool Example.
  
  Provides a simple way to run the concurrent pool demonstrations from the
  command line without needing to start an IEx session.
  """

  @doc """
  Main entry point for the CLI application.
  
  ## Usage
  
      mix run -e "ConcurrentPoolExample.CLI.main()"
      
  Or with command-line arguments:
  
      mix run -e "ConcurrentPoolExample.CLI.main()" -- concurrent
      mix run -e "ConcurrentPoolExample.CLI.main()" -- affinity
      mix run -e "ConcurrentPoolExample.CLI.main()" -- benchmark
      mix run -e "ConcurrentPoolExample.CLI.main()" -- errors
  """
  def main(args \\ []) do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:concurrent_pool_example)
    
    case args do
      [] -> 
        run_concurrent_operations_with_output()
        
      ["concurrent"] -> 
        run_concurrent_operations_with_output()
        
      ["affinity"] -> 
        demonstrate_session_affinity_with_output()
        
      ["benchmark"] -> 
        run_performance_benchmark_with_output()
        
      ["errors"] -> 
        demonstrate_error_handling_with_output()
        
      ["help"] -> 
        show_help()
        
      _ -> 
        IO.puts("Unknown command. Use 'help' for available commands.")
        show_help()
    end
  end

  defp run_concurrent_operations_with_output do
    IO.puts("\n=== Concurrent Pool Operations Demo ===")
    IO.puts("Running three concurrent operations: classification, translation, summarization...")
    
    case ConcurrentPoolExample.run_concurrent_operations() do
      {:ok, results} ->
        IO.puts("\n✅ All operations completed successfully!")
        
        total_time = Map.get(results, :total_time_ms, 0)
        IO.puts("Total execution time: #{total_time}ms")
        
        operations = Map.drop(results, [:total_time_ms])
        IO.puts("\nResults by operation:")
        
        Enum.each(operations, fn {operation, data} ->
          IO.puts("  #{operation}:")
          IO.puts("    Time: #{data.time_ms}ms")
          IO.puts("    Session: #{data.session_id}")
          IO.puts("    Result: #{inspect(data.result, limit: :infinity)}")
        end)
        
      {:error, error} ->
        IO.puts("\n❌ Some operations failed:")
        IO.puts("#{inspect(error, pretty: true)}")
        System.halt(1)
    end
  end

  defp demonstrate_session_affinity_with_output do
    IO.puts("\n=== Session Affinity Demo ===")
    IO.puts("Demonstrating how SessionPoolV2 maintains worker affinity...")
    
    case ConcurrentPoolExample.demonstrate_session_affinity() do
      {:ok, results} ->
        IO.puts("\n✅ Session affinity demonstration completed!")
        IO.puts("Session ID: #{results.session_id}")
        
        IO.puts("\nOperation results:")
        Enum.each(results.operations, fn {step, result} ->
          case result do
            {:ok, data} ->
              IO.puts("  Step #{step}: ✅ Success")
              IO.puts("    Result: #{inspect(data, limit: :infinity)}")
              
            {:error, error} ->
              IO.puts("  Step #{step}: ❌ Error")
              IO.puts("    Error: #{inspect(error)}")
          end
        end)
        
      {:error, error} ->
        IO.puts("\n❌ Session affinity demo failed:")
        IO.puts("#{inspect(error, pretty: true)}")
        System.halt(1)
    end
  end

  defp run_performance_benchmark_with_output do
    IO.puts("\n=== Performance Benchmark ===")
    IO.puts("Comparing sequential vs concurrent execution performance...")
    
    case ConcurrentPoolExample.run_performance_benchmark() do
      {:ok, benchmark} ->
        IO.puts("\n✅ Benchmark completed!")
        
        seq = benchmark.sequential
        conc = benchmark.concurrent
        speedup = benchmark.speedup_factor
        
        IO.puts("Sequential execution: #{seq.time_ms}ms")
        IO.puts("Concurrent execution: #{conc.time_ms}ms")
        IO.puts("Speedup factor: #{Float.round(speedup, 2)}x")
        
        if speedup > 1.0 do
          IO.puts("🚀 Concurrent execution was #{Float.round((speedup - 1) * 100, 1)}% faster!")
        else
          IO.puts("⚠️  Sequential execution was faster (possibly due to overhead)")
        end
        
      {:error, error} ->
        IO.puts("\n❌ Benchmark failed:")
        IO.puts("#{inspect(error, pretty: true)}")
        System.halt(1)
    end
  end

  defp demonstrate_error_handling_with_output do
    IO.puts("\n=== Error Handling Demo ===")
    IO.puts("Testing various error conditions and recovery...")
    
    case ConcurrentPoolExample.demonstrate_error_handling() do
      {:ok, results} ->
        IO.puts("\n✅ Error handling demonstration completed!")
        
        IO.puts("Test results:")
        Enum.each(results.error_handling_results, fn {description, result} ->
          case result do
            {:ok, _} ->
              IO.puts("  #{description}: ✅ Success (unexpected)")
              
            {:error, error} ->
              IO.puts("  #{description}: ❌ Error (expected)")
              IO.puts("    #{inspect(error, limit: 50)}")
          end
        end)
        
      {:error, error} ->
        IO.puts("\n❌ Error handling demo failed:")
        IO.puts("#{inspect(error, pretty: true)}")
        System.halt(1)
    end
  end

  defp show_help do
    IO.puts("""
    
    Concurrent Pool Example CLI
    
    Usage:
      mix run -e "ConcurrentPoolExample.CLI.main()" -- [COMMAND]
    
    Commands:
      concurrent   Run concurrent operations demo (default)
      affinity     Demonstrate session affinity
      benchmark    Run performance benchmark
      errors       Demonstrate error handling
      help         Show this help message
    
    Environment:
      Set GEMINI_API_KEY environment variable before running
    
    Examples:
      export GEMINI_API_KEY="your-key-here"
      mix run -e "ConcurrentPoolExample.CLI.main()"
      mix run -e "ConcurrentPoolExample.CLI.main()" -- benchmark
      mix run -e "ConcurrentPoolExample.CLI.main()" -- affinity
    """)
  end
end