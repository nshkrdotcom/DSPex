#!/usr/bin/env elixir

# Test Layer Execution Script
# Runs the 3-layer testing architecture with appropriate configurations

defmodule TestLayers do
  @moduledoc """
  Script for running the 3-layer testing architecture.
  
  Usage:
    elixir scripts/test_layers.exs [layer] [options]
    
  Layers:
    layer1, mock     - Layer 1: Mock Adapter (fast unit tests)
    layer2, bridge   - Layer 2: Bridge Mock (protocol tests)  
    layer3, full     - Layer 3: Full Integration (E2E tests)
    all              - Run all layers in sequence
    
  Options:
    --verbose        - Enable verbose output
    --trace          - Enable test tracing
    --parallel       - Run layers in parallel (when applicable)
    --timing         - Show execution timing
    --stats          - Show test statistics
  """

  def main(args \\ System.argv()) do
    {opts, remaining_args, _} = OptionParser.parse(args, 
      switches: [
        verbose: :boolean,
        trace: :boolean,
        parallel: :boolean,
        timing: :boolean,
        stats: :boolean,
        help: :boolean
      ],
      aliases: [
        v: :verbose,
        t: :trace,
        p: :parallel,
        h: :help
      ]
    )
    
    if Keyword.get(opts, :help, false) do
      print_help()
      System.halt(0)
    end
    
    layer = case remaining_args do
      [] -> "layer1"  # Default to fastest layer
      [layer | _] -> layer
    end
    
    IO.puts("🧪 AshDSPex 3-Layer Testing Architecture")
    IO.puts("═══════════════════════════════════════")
    
    if Keyword.get(opts, :timing, false) do
      {time_microseconds, result} = :timer.tc(fn -> run_layer(layer, opts) end)
      time_seconds = time_microseconds / 1_000_000
      
      IO.puts("\n⏱️  Total execution time: #{Float.round(time_seconds, 2)} seconds")
      
      if Keyword.get(opts, :stats, false) do
        print_performance_stats(layer, time_seconds)
      end
      
      result
    else
      run_layer(layer, opts)
    end
  end

  defp run_layer("layer1", opts), do: run_layer("mock", opts)
  defp run_layer("layer2", opts), do: run_layer("bridge", opts)
  defp run_layer("layer3", opts), do: run_layer("full", opts)
  
  defp run_layer("mock", opts) do
    print_layer_header(1, "Mock Adapter", "Pure Elixir unit tests")
    run_test_mode(:mock_adapter, opts)
  end
  
  defp run_layer("bridge", opts) do
    print_layer_header(2, "Bridge Mock", "Protocol validation tests")
    run_test_mode(:bridge_mock, opts)
  end
  
  defp run_layer("full", opts) do
    print_layer_header(3, "Full Integration", "End-to-end tests with Python")
    run_test_mode(:full_integration, opts)
  end
  
  defp run_layer("all", opts) do
    IO.puts("🔄 Running all test layers in sequence")
    IO.puts("")
    
    results = if Keyword.get(opts, :parallel, false) do
      run_layers_parallel(opts)
    else
      run_layers_sequential(opts)
    end
    
    print_summary(results)
    
    # Exit with error if any layer failed
    if Enum.any?(results, fn {_, result} -> result != 0 end) do
      System.halt(1)
    else
      System.halt(0)
    end
  end
  
  defp run_layer(unknown, _opts) do
    IO.puts("❌ Unknown layer: #{unknown}")
    IO.puts("Valid layers: layer1/mock, layer2/bridge, layer3/full, all")
    print_help()
    System.halt(1)
  end

  defp run_layers_sequential(opts) do
    [
      {"Layer 1 (Mock)", fn -> run_test_mode(:mock_adapter, opts) end},
      {"Layer 2 (Bridge)", fn -> run_test_mode(:bridge_mock, opts) end},
      {"Layer 3 (Full)", fn -> run_test_mode(:full_integration, opts) end}
    ]
    |> Enum.map(fn {name, test_fn} ->
      IO.puts("🔄 Running #{name}...")
      result = test_fn.()
      {name, result}
    end)
  end

  defp run_layers_parallel(opts) do
    IO.puts("⚡ Running layers in parallel...")
    
    tasks = [
      {"Layer 1 (Mock)", Task.async(fn -> run_test_mode(:mock_adapter, opts) end)},
      {"Layer 2 (Bridge)", Task.async(fn -> run_test_mode(:bridge_mock, opts) end)}
      # Layer 3 runs sequentially due to Python bridge isolation requirements
    ]
    
    # Wait for parallel tasks
    parallel_results = Enum.map(tasks, fn {name, task} ->
      {name, Task.await(task, 60_000)}  # 1 minute timeout
    end)
    
    # Run Layer 3 after others complete
    layer3_result = {"Layer 3 (Full)", run_test_mode(:full_integration, opts)}
    
    parallel_results ++ [layer3_result]
  end

  defp run_test_mode(mode, opts) do
    # Set environment variable for this test run
    System.put_env("TEST_MODE", Atom.to_string(mode))
    
    # Build mix test command
    mix_args = build_mix_args(mode, opts)
    
    if Keyword.get(opts, :verbose, false) do
      IO.puts("🔧 Running: mix test #{Enum.join(mix_args, " ")}")
      IO.puts("🌍 TEST_MODE=#{mode}")
      IO.puts("")
    end
    
    # Execute mix test
    {output, exit_code} = System.cmd("mix", ["test" | mix_args], 
      stderr_to_stdout: true,
      env: [{"TEST_MODE", Atom.to_string(mode)}]
    )
    
    if Keyword.get(opts, :verbose, false) or exit_code != 0 do
      IO.puts(output)
    end
    
    if exit_code == 0 do
      IO.puts("✅ #{mode_name(mode)} tests passed")
    else
      IO.puts("❌ #{mode_name(mode)} tests failed (exit code: #{exit_code})")
    end
    
    exit_code
  end

  defp build_mix_args(mode, opts) do
    base_args = []
    
    base_args
    |> add_if(Keyword.get(opts, :trace, false), "--trace")
    |> add_if(Keyword.get(opts, :verbose, false), "--formatter", "ExUnit.CLIFormatter")
    |> add_mode_specific_args(mode)
  end

  defp add_if(args, condition, flag, value) when condition do
    args ++ [flag, value]
  end
  defp add_if(args, condition, flag) when condition do
    args ++ [flag]
  end
  defp add_if(args, _condition, _flag), do: args
  defp add_if(args, _condition, _flag, _value), do: args

  defp add_mode_specific_args(args, :mock_adapter) do
    # Mock adapter tests are fast and can run with high concurrency
    args ++ ["--max-cases", "50"]
  end

  defp add_mode_specific_args(args, :bridge_mock) do
    # Bridge mock tests need moderate concurrency
    args ++ ["--max-cases", "10"]
  end

  defp add_mode_specific_args(args, :full_integration) do
    # Full integration tests need to run sequentially
    args ++ ["--max-cases", "1", "--timeout", "60000"]
  end

  defp print_layer_header(layer_num, name, description) do
    IO.puts("📋 Layer #{layer_num}: #{name}")
    IO.puts("   #{description}")
    IO.puts("")
  end

  defp print_summary(results) do
    IO.puts("")
    IO.puts("📊 Test Layer Summary")
    IO.puts("═══════════════════════")
    
    Enum.each(results, fn {name, result} ->
      status = if result == 0, do: "✅ PASS", else: "❌ FAIL (#{result})"
      IO.puts("#{String.pad_trailing(name, 20)} #{status}")
    end)
    
    passed = Enum.count(results, fn {_, result} -> result == 0 end)
    total = length(results)
    
    IO.puts("")
    IO.puts("Total: #{passed}/#{total} layers passed")
    
    if passed == total do
      IO.puts("🎉 All test layers successful!")
    else
      IO.puts("💥 #{total - passed} layer(s) failed")
    end
  end

  defp print_performance_stats(layer, time_seconds) do
    target_times = %{
      "mock" => 5.0,      # Layer 1 target: under 5 seconds
      "bridge" => 15.0,   # Layer 2 target: under 15 seconds  
      "full" => 120.0     # Layer 3 target: under 2 minutes
    }
    
    target = Map.get(target_times, layer, 60.0)
    
    IO.puts("🎯 Performance Analysis:")
    IO.puts("   Target time: #{target}s")
    IO.puts("   Actual time: #{Float.round(time_seconds, 2)}s")
    
    if time_seconds <= target do
      IO.puts("   Status: ✅ Within target")
    else
      overhead = Float.round(time_seconds - target, 2)
      IO.puts("   Status: ⚠️  #{overhead}s over target")
    end
  end

  defp mode_name(:mock_adapter), do: "Layer 1 (Mock Adapter)"
  defp mode_name(:bridge_mock), do: "Layer 2 (Bridge Mock)"
  defp mode_name(:full_integration), do: "Layer 3 (Full Integration)"

  defp print_help do
    IO.puts(@moduledoc)
    IO.puts("")
    IO.puts("Examples:")
    IO.puts("  elixir scripts/test_layers.exs                    # Run Layer 1 (fastest)")
    IO.puts("  elixir scripts/test_layers.exs layer2 --verbose   # Run Layer 2 with output")
    IO.puts("  elixir scripts/test_layers.exs all --timing       # Run all layers with timing")
    IO.puts("  elixir scripts/test_layers.exs full --trace       # Run Layer 3 with tracing")
  end
end

# Execute if run as script
if __ENV__.file == Path.expand(__ENV__.file) do
  TestLayers.main()
end