defmodule PoolExample.CLI do
  @moduledoc """
  CLI interface for the Pool Example application.
  
  Provides command-line access to different pool testing scenarios.
  """

  def main(args) do
    args
    |> parse_args()
    |> process()
  end

  defp parse_args(args) do
    {opts, command, _} =
      OptionParser.parse(args,
        switches: [
          help: :boolean,
          operations: :integer
        ],
        aliases: [
          h: :help,
          n: :operations
        ]
      )

    {command, opts}
  end

  defp process({["session_affinity"], _opts}) do
    setup_environment()
    PoolExample.run_session_affinity_test()
    shutdown_gracefully()
  end

  defp process({["anonymous"], _opts}) do
    setup_environment()
    PoolExample.run_anonymous_operations_test()
    shutdown_gracefully()
  end

  defp process({["stress"], opts}) do
    setup_environment()
    num_operations = Keyword.get(opts, :operations, 20)
    PoolExample.run_concurrent_stress_test(num_operations)
    shutdown_gracefully()
  end

  defp process({["error_recovery"], _opts}) do
    setup_environment()
    PoolExample.run_error_recovery_test()
    shutdown_gracefully()
  end

  defp process({["all"], _opts}) do
    setup_environment()
    PoolExample.run_all_tests()
    shutdown_gracefully()
  end

  defp process({_, opts}) do
    if Keyword.get(opts, :help, false) do
      print_help()
    else
      IO.puts("Unknown command. Use --help for usage information.")
      System.halt(1)
    end
  end

  defp setup_environment do
    # Ensure GEMINI_API_KEY is set
    unless System.get_env("GEMINI_API_KEY") do
      IO.puts("""
      ⚠️  Warning: GEMINI_API_KEY environment variable is not set.
      The examples will use mock responses instead of real AI.
      
      To use real AI, set your API key:
      export GEMINI_API_KEY="your-api-key-here"
      """)
    end

    # Wait for pool to be ready using event-driven approach
    wait_for_pool_ready()
  end

  defp print_help do
    IO.puts("""
    DSPex Pool Example CLI

    Usage:
      pool_example <command> [options]

    Commands:
      session_affinity    Test session affinity in the pool
      anonymous          Test anonymous pool operations
      stress             Run concurrent stress test
      error_recovery     Test error handling and recovery
      all                Run all tests

    Options:
      -h, --help         Show this help message
      -n, --operations   Number of operations for stress test (default: 20)

    Examples:
      pool_example session_affinity
      pool_example stress --operations 50
      pool_example all
    """)
  end

  defp wait_for_pool_ready do
    # Event-driven wait for pool to be ready
    case Process.whereis(DSPex.PythonBridge.SessionPoolV2) do
      nil ->
        # Pool not started yet, wait a bit and retry
        receive do
        after
          100 -> wait_for_pool_ready()
        end
      _pid ->
        # Pool is running, give it a moment to initialize workers
        # This should ideally use telemetry events but for now we'll use a short timeout
        receive do
        after
          100 -> :ok
        end
    end
  end

  defp shutdown_gracefully do
    # Stop the application cleanly
    Application.stop(:pool_example)
    Application.stop(:dspex)
    
    # Allow a brief moment for cleanup
    receive do
    after
      100 -> :ok
    end
    
    System.halt(0)
  end
end