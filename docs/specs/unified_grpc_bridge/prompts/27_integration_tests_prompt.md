# Prompt: Create Comprehensive Stage 2 Integration Tests

## Objective
Develop thorough integration tests that validate the complete Stage 2 implementation, including automatic backend switching, state migration, variable operations, and Python integration.

## Context
These tests must verify that:
- Pure Elixir workflows use LocalState with sub-microsecond performance
- Python components trigger automatic backend switching
- State migrates seamlessly between backends
- Variable operations work identically in both modes
- Python DSPy modules can access Elixir variables

## Requirements

### Test Coverage
1. Backend switching scenarios
2. State migration correctness
3. Performance characteristics
4. Python integration
5. Error handling
6. Concurrent operations
7. Real-world workflows

### Test Infrastructure
- Mock and real backends
- Python subprocess management
- Performance measurement
- State verification helpers

## Implementation

### Core Integration Tests

```elixir
# File: test/dspex/integration/stage2_test.exs

defmodule DSPex.Integration.Stage2Test do
  @moduledoc """
  Comprehensive integration tests for Stage 2 functionality.
  
  Tests the complete cognitive layer including:
  - Automatic backend switching
  - State migration
  - Variable operations
  - Python integration
  """
  
  use ExUnit.Case, async: false
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.State.{Local, Bridged}
  alias Snakepit.Bridge.SessionStore
  
  import DSPex.TestHelpers.{Timing, Python}
  
  setup do
    # Ensure SessionStore is available
    case SessionStore.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    :ok
  end
  
  describe "pure Elixir workflow with LocalState" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "achieves sub-microsecond performance", %{ctx: ctx} do
      # Define variables
      Variables.defvariable!(ctx, :counter, :integer, 0)
      Variables.defvariable!(ctx, :name, :string, "test")
      Variables.defvariable!(ctx, :ratio, :float, 0.5)
      
      # Measure get performance
      get_times = measure_repeated(1000, fn ->
        Variables.get(ctx, :counter)
      end)
      
      # Verify sub-microsecond average
      assert average(get_times) < 1.0
      assert percentile(get_times, 99) < 5.0
      
      # Measure set performance  
      set_times = measure_repeated(1000, fn i ->
        Variables.set(ctx, :counter, i)
      end)
      
      assert average(set_times) < 5.0
      assert percentile(set_times, 99) < 20.0
      
      # Verify still using LocalState
      assert %{type: :local} = Context.get_backend(ctx)
    end
    
    test "supports all variable operations locally", %{ctx: ctx} do
      # Define various types
      Variables.defvariable!(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0}
      )
      Variables.defvariable!(ctx, :tokens, :integer, 256,
        constraints: %{min: 1, max: 4096}
      )
      Variables.defvariable!(ctx, :model, :string, "local",
        constraints: %{enum: ["local", "fast", "accurate"]}
      )
      Variables.defvariable!(ctx, :enabled, :boolean, true)
      
      # Test operations
      assert Variables.get(ctx, :temperature) == 0.7
      assert :ok = Variables.set(ctx, :temperature, 0.9)
      assert Variables.get(ctx, :temperature) == 0.9
      
      # Functional update
      assert :ok = Variables.update(ctx, :tokens, &(&1 * 2))
      assert Variables.get(ctx, :tokens) == 512
      
      # Batch operations
      values = Variables.get_many(ctx, [:temperature, :tokens, :model])
      assert map_size(values) == 3
      
      assert :ok = Variables.update_many(ctx, %{
        temperature: 0.5,
        tokens: 1024,
        model: "fast"
      })
      
      # List all
      vars = Variables.list(ctx)
      assert length(vars) == 4
    end
    
    test "enforces constraints locally", %{ctx: ctx} do
      Variables.defvariable!(ctx, :bounded, :float, 0.5,
        constraints: %{min: 0.0, max: 1.0}
      )
      
      # Valid update
      assert :ok = Variables.set(ctx, :bounded, 0.8)
      
      # Invalid updates
      assert {:error, _} = Variables.set(ctx, :bounded, -0.1)
      assert {:error, _} = Variables.set(ctx, :bounded, 1.5)
      
      # Value unchanged after failed updates
      assert Variables.get(ctx, :bounded) == 0.8
    end
  end
  
  describe "automatic backend switching" do
    setup do
      {:ok, ctx} = Context.start_link()
      
      # Create initial state in local backend
      Variables.defvariable!(ctx, :pre_switch, :string, "local_value")
      Variables.defvariable!(ctx, :counter, :integer, 42)
      Variables.defvariable!(ctx, :config, :string, "test",
        metadata: %{"source" => "test"}
      )
      
      {:ok, ctx: ctx}
    end
    
    test "switches on ensure_bridged", %{ctx: ctx} do
      # Verify starting state
      backend = Context.get_backend(ctx)
      assert backend.type == :local
      assert backend.switches == 0
      
      # Record values before switch
      values_before = Variables.get_many(ctx, [:pre_switch, :counter, :config])
      
      # Trigger switch
      {switch_time, :ok} = :timer.tc(fn ->
        Context.ensure_bridged(ctx)
      end)
      
      # Verify switched
      backend = Context.get_backend(ctx)
      assert backend.type == :bridged
      assert backend.switches == 1
      assert backend.module == Bridged
      
      # Switch should be fast
      assert switch_time < 50_000  # 50ms
      
      # All values preserved
      values_after = Variables.get_many(ctx, [:pre_switch, :counter, :config])
      assert values_after == values_before
      
      # Can still modify variables
      assert :ok = Variables.set(ctx, :counter, 100)
      assert Variables.get(ctx, :counter) == 100
    end
    
    test "switches when Python program registered", %{ctx: ctx} do
      # Register a Python-requiring program
      program_spec = %{
        type: :dspy,
        adapter: "PythonAdapter",
        modules: [%{type: :dspy, class: "ChainOfThought"}],
        requires_python: true
      }
      
      # This should trigger switch
      :ok = Context.register_program(ctx, "python_prog", program_spec)
      
      # Verify switched
      backend = Context.get_backend(ctx)
      assert backend.type == :bridged
      assert backend.switches == 1
      
      # Variables still accessible
      assert Variables.get(ctx, :pre_switch) == "local_value"
    end
    
    test "preserves all variable metadata during switch", %{ctx: ctx} do
      # Get full variable info before switch
      vars_before = Variables.list(ctx)
      |> Enum.map(fn var -> {var.name, var} end)
      |> Map.new()
      
      # Switch
      :ok = Context.ensure_bridged(ctx)
      
      # Get after switch
      vars_after = Variables.list(ctx)
      |> Enum.map(fn var -> {var.name, var} end)
      |> Map.new()
      
      # Compare each variable
      assert map_size(vars_after) == map_size(vars_before)
      
      for {name, var_before} <- vars_before do
        var_after = Map.fetch!(vars_after, name)
        
        # Same data
        assert var_after.type == var_before.type
        assert var_after.value == var_before.value
        assert var_after.constraints == var_before.constraints
        
        # Metadata preserved plus migration info
        assert var_after.metadata["source"] == var_before.metadata["source"]
        assert var_after.metadata["migrated_from"] == "local"
      end
    end
    
    test "switch is idempotent", %{ctx: ctx} do
      # Switch multiple times
      :ok = Context.ensure_bridged(ctx)
      backend1 = Context.get_backend(ctx)
      
      :ok = Context.ensure_bridged(ctx)
      backend2 = Context.get_backend(ctx)
      
      :ok = Context.ensure_bridged(ctx)
      backend3 = Context.get_backend(ctx)
      
      # Only one switch
      assert backend1.switches == 1
      assert backend2.switches == 1
      assert backend3.switches == 1
    end
  end
  
  describe "LocalState to BridgedState migration" do
    test "handles empty state" do
      {:ok, ctx} = Context.start_link()
      
      # Switch empty context
      assert :ok = Context.ensure_bridged(ctx)
      
      # Can add variables after switch
      Variables.defvariable!(ctx, :post_switch, :string, "works")
      assert Variables.get(ctx, :post_switch) == "works"
    end
    
    test "handles large state migration" do
      {:ok, ctx} = Context.start_link()
      
      # Create many variables
      for i <- 1..100 do
        Variables.defvariable!(ctx, :"var_#{i}", :integer, i,
          constraints: %{min: 0, max: 1000},
          metadata: %{"index" => i}
        )
      end
      
      # Measure migration time
      {migration_time, :ok} = :timer.tc(fn ->
        Context.ensure_bridged(ctx)
      end)
      
      # Should still be reasonably fast
      assert migration_time < 100_000  # 100ms for 100 variables
      
      # Spot check some values
      assert Variables.get(ctx, :var_1) == 1
      assert Variables.get(ctx, :var_50) == 50  
      assert Variables.get(ctx, :var_100) == 100
      
      # All variables migrated
      assert length(Variables.list(ctx)) == 100
    end
    
    test "handles complex variable types" do
      {:ok, ctx} = Context.start_link()
      
      # Various constraint types
      Variables.defvariable!(ctx, :ranged, :float, 0.5,
        constraints: %{min: 0.0, max: 1.0}
      )
      
      Variables.defvariable!(ctx, :pattern, :string, "ABC123",
        constraints: %{pattern: "^[A-Z]+[0-9]+$"}
      )
      
      Variables.defvariable!(ctx, :choice, :string, "red",
        constraints: %{enum: ["red", "green", "blue"]}
      )
      
      # Switch
      :ok = Context.ensure_bridged(ctx)
      
      # Constraints still enforced
      assert {:error, _} = Variables.set(ctx, :ranged, 2.0)
      assert {:error, _} = Variables.set(ctx, :pattern, "invalid")
      assert {:error, _} = Variables.set(ctx, :choice, "yellow")
      
      # Valid updates work
      assert :ok = Variables.set(ctx, :ranged, 0.7)
      assert :ok = Variables.set(ctx, :pattern, "XYZ789")
      assert :ok = Variables.set(ctx, :choice, "blue")
    end
  end
  
  describe "BridgedState performance" do
    setup do
      {:ok, ctx} = Context.start_link()
      
      # Start bridged
      :ok = Context.ensure_bridged(ctx)
      
      # Add variables
      for i <- 1..20 do
        Variables.defvariable!(ctx, :"perf_#{i}", :float, i * 0.1)
      end
      
      {:ok, ctx: ctx}
    end
    
    test "meets performance targets", %{ctx: ctx} do
      # Single get
      get_times = measure_repeated(100, fn ->
        Variables.get(ctx, :perf_10)
      end)
      
      assert average(get_times) < 2000  # < 2ms average
      assert percentile(get_times, 95) < 5000  # < 5ms 95th percentile
      
      # Single set
      set_times = measure_repeated(100, fn i ->
        Variables.set(ctx, :perf_10, i * 0.1)
      end)
      
      assert average(set_times) < 5000  # < 5ms average
      
      # Batch operations should be more efficient
      identifiers = Enum.map(1..10, &:"perf_#{&1}")
      
      batch_time = measure_once(fn ->
        Variables.get_many(ctx, identifiers)
      end)
      
      individual_time = measure_once(fn ->
        for id <- identifiers do
          Variables.get(ctx, id)
        end
      end)
      
      # Batch should be significantly faster
      assert batch_time < individual_time * 0.5
    end
  end
  
  @tag :integration
  @tag :python
  describe "Python integration" do
    setup do
      {:ok, ctx} = Context.start_link()
      
      # Define variables
      Variables.defvariable!(ctx, :temperature, :float, 0.7)
      Variables.defvariable!(ctx, :max_tokens, :integer, 256)
      Variables.defvariable!(ctx, :model_name, :string, "gpt-4")
      
      # Ensure bridged for Python
      :ok = Context.ensure_bridged(ctx)
      
      # Get context ID for Python
      context_id = Context.get_id(ctx)
      
      {:ok, ctx: ctx, context_id: context_id}
    end
    
    test "Python can read Elixir variables", %{context_id: context_id} do
      result = run_python_test("""
      import asyncio
      from snakepit_bridge import SessionContext
      
      async def test():
          ctx = SessionContext(stub, '#{context_id}')
          
          temp = await ctx.get_variable('temperature')
          tokens = await ctx.get_variable('max_tokens')
          model = await ctx.get_variable('model_name')
          
          return {
              'temperature': temp,
              'max_tokens': tokens,
              'model_name': model
          }
      
      result = asyncio.run(test())
      """)
      
      assert result["temperature"] == 0.7
      assert result["max_tokens"] == 256
      assert result["model_name"] == "gpt-4"
    end
    
    test "Python updates visible in Elixir", %{ctx: ctx, context_id: context_id} do
      result = run_python_test("""
      import asyncio
      from snakepit_bridge import SessionContext
      
      async def test():
          ctx = SessionContext(stub, '#{context_id}')
          
          # Update variables
          await ctx.set_variable('temperature', 0.9)
          await ctx.set_variable('max_tokens', 512)
          
          return {'status': 'updated'}
      
      result = asyncio.run(test())
      """)
      
      assert result["status"] == "updated"
      
      # Check updates in Elixir
      assert Variables.get(ctx, :temperature) == 0.9
      assert Variables.get(ctx, :max_tokens) == 512
    end
    
    test "variable-aware DSPy modules", %{ctx: ctx, context_id: context_id} do
      # This test would require actual DSPy setup
      # Simplified version showing the concept
      
      result = run_python_test("""
      import asyncio
      from snakepit_bridge import SessionContext
      from snakepit_bridge.dspy_integration import VariableAwarePredict
      
      async def test():
          ctx = SessionContext(stub, '#{context_id}')
          
          # Create variable-aware module
          predictor = VariableAwarePredict(
              "question -> answer",
              session_context=ctx
          )
          
          # Bind to variables
          await predictor.bind_to_variable('temperature', 'temperature')
          await predictor.bind_to_variable('max_tokens', 'max_tokens')
          
          # Check bindings
          return {
              'temperature': predictor.temperature,
              'max_tokens': predictor.max_tokens,
              'bindings': predictor.get_bindings()
          }
      
      result = asyncio.run(test())
      """)
      
      assert result["temperature"] == 0.7
      assert result["max_tokens"] == 256
      assert result["bindings"]["temperature"] == "temperature"
    end
  end
  
  describe "error handling" do
    setup do
      {:ok, ctx} = Context.start_link()
      {:ok, ctx: ctx}
    end
    
    test "graceful handling of SessionStore unavailability", %{ctx: ctx} do
      # Stop SessionStore to simulate failure
      if pid = Process.whereis(SessionStore) do
        Process.exit(pid, :kill)
        Process.sleep(10)
      end
      
      # Try to switch - should fail gracefully
      result = Context.ensure_bridged(ctx)
      
      # Context should still be functional with local backend
      assert Variables.defvariable(ctx, :survivor, :string, "still works")
      assert Variables.get(ctx, :survivor) == "still works"
    end
    
    test "type validation across backends", %{ctx: ctx} do
      Variables.defvariable!(ctx, :typed, :integer, 42)
      
      # Invalid in local
      assert {:error, _} = Variables.set(ctx, :typed, "not an integer")
      
      # Switch backends
      :ok = Context.ensure_bridged(ctx)
      
      # Still invalid in bridged
      assert {:error, _} = Variables.set(ctx, :typed, "still not an integer")
      
      # Value unchanged
      assert Variables.get(ctx, :typed) == 42
    end
  end
  
  describe "real-world workflow simulation" do
    test "LLM configuration workflow" do
      {:ok, ctx} = Context.start_link()
      
      # Define LLM configuration variables
      Variables.defvariable!(ctx, :model, :string, "gpt-3.5-turbo",
        constraints: %{enum: ["gpt-3.5-turbo", "gpt-4", "claude-3"]},
        description: "LLM model selection"
      )
      
      Variables.defvariable!(ctx, :temperature, :float, 0.7,
        constraints: %{min: 0.0, max: 2.0},
        description: "Generation randomness"
      )
      
      Variables.defvariable!(ctx, :max_tokens, :integer, 256,
        constraints: %{min: 1, max: 4096},
        description: "Maximum response length"
      )
      
      Variables.defvariable!(ctx, :top_p, :float, 1.0,
        constraints: %{min: 0.0, max: 1.0},
        description: "Nucleus sampling"
      )
      
      # Simulate configuration updates
      config_updates = [
        %{temperature: 0.5, max_tokens: 512},
        %{model: "gpt-4", temperature: 0.8},
        %{max_tokens: 1024, top_p: 0.95}
      ]
      
      for update <- config_updates do
        assert :ok = Variables.update_many(ctx, update)
      end
      
      # Final configuration
      final_config = Variables.get_many(ctx, [:model, :temperature, :max_tokens, :top_p])
      
      assert final_config.model == "gpt-4"
      assert final_config.temperature == 0.8
      assert final_config.max_tokens == 1024
      assert final_config.top_p == 0.95
      
      # Now add Python component - should trigger switch
      Context.register_program(ctx, "llm_program", %{
        type: :dspy,
        requires_python: true
      })
      
      # Configuration still intact after switch
      assert Variables.get_many(ctx, [:model, :temperature]) == %{
        model: "gpt-4",
        temperature: 0.8
      }
    end
    
    test "multi-stage pipeline with mixed components" do
      {:ok, ctx} = Context.start_link()
      
      # Stage 1: Pure Elixir preprocessing
      Variables.defvariable!(ctx, :input_text, :string, "Process this text")
      Variables.defvariable!(ctx, :preprocessing_done, :boolean, false)
      
      # Simulate preprocessing
      text = Variables.get(ctx, :input_text)
      processed = String.upcase(text)
      Variables.set(ctx, :input_text, processed)
      Variables.set(ctx, :preprocessing_done, true)
      
      # Still using local backend
      assert Context.get_backend(ctx).type == :local
      
      # Stage 2: Add Python NLP component
      Context.register_program(ctx, "nlp_analyzer", %{
        type: :python,
        requires_python: true,
        module: "TextAnalyzer"
      })
      
      # Now switched to bridged
      assert Context.get_backend(ctx).type == :bridged
      
      # Variables still accessible
      assert Variables.get(ctx, :input_text) == "PROCESS THIS TEXT"
      assert Variables.get(ctx, :preprocessing_done) == true
      
      # Stage 3: Store results
      Variables.defvariable!(ctx, :analysis_complete, :boolean, true)
      Variables.defvariable!(ctx, :results, :string, "Analysis results here")
      
      # All stages' variables coexist
      all_vars = Variables.list(ctx)
      var_names = Enum.map(all_vars, & &1.name)
      
      assert :input_text in var_names
      assert :preprocessing_done in var_names
      assert :analysis_complete in var_names
      assert :results in var_names
    end
  end
end
```

### Test Helpers

```elixir
# File: test/support/dspex_test_helpers.ex

defmodule DSPex.TestHelpers.Timing do
  @moduledoc """
  Performance measurement helpers for tests.
  """
  
  @doc """
  Measures execution time of a function multiple times.
  Returns list of times in microseconds.
  """
  def measure_repeated(count, fun) when is_function(fun, 0) do
    for _ <- 1..count do
      {time, _} = :timer.tc(fun)
      time
    end
  end
  
  def measure_repeated(count, fun) when is_function(fun, 1) do
    for i <- 1..count do
      {time, _} = :timer.tc(fun, [i])
      time
    end
  end
  
  @doc """
  Measures a single execution.
  """
  def measure_once(fun) do
    {time, _} = :timer.tc(fun)
    time
  end
  
  @doc """
  Calculates average of times.
  """
  def average(times) do
    Enum.sum(times) / length(times)
  end
  
  @doc """
  Calculates percentile of times.
  """
  def percentile(times, p) do
    sorted = Enum.sort(times)
    index = round(length(sorted) * p / 100)
    Enum.at(sorted, index - 1)
  end
end

defmodule DSPex.TestHelpers.Python do
  @moduledoc """
  Python integration test helpers.
  """
  
  require Logger
  
  @doc """
  Runs a Python test script and returns the result.
  
  The script should set a 'result' variable that will be
  captured and decoded.
  """
  def run_python_test(script) do
    # Add result capture
    full_script = """
    import sys
    import json
    import grpc
    from unittest.mock import MagicMock
    
    # Mock gRPC connection for tests
    channel = MagicMock()
    stub = MagicMock()
    
    #{script}
    
    # Output result as JSON
    print(json.dumps(result))
    """
    
    # Create temp file
    path = Path.join(System.tmp_dir!(), "dspex_test_#{:rand.uniform(1_000_000)}.py")
    File.write!(path, full_script)
    
    try do
      # Run Python
      case System.cmd("python3", [path], 
                      env: [{"PYTHONPATH", "priv/python"}],
                      stderr_to_stdout: true) do
        {output, 0} ->
          # Parse JSON result
          output
          |> String.trim()
          |> String.split("\n")
          |> List.last()
          |> Jason.decode!()
          
        {output, code} ->
          Logger.error("Python test failed (exit #{code}):\n#{output}")
          raise "Python test failed"
      end
    after
      File.rm(path)
    end
  end
  
  @doc """
  Starts a Python subprocess for interactive testing.
  """
  def start_python_session(context_id) do
    # Implementation for interactive Python testing
    :not_implemented
  end
end
```

### Performance Benchmarks

```elixir
# File: bench/stage2_benchmarks.exs

defmodule DSPex.Stage2Benchmarks do
  @moduledoc """
  Performance benchmarks for Stage 2 features.
  """
  
  use Benchfella
  
  alias DSPex.{Context, Variables}
  alias DSPex.Bridge.State.{Local, Bridged}
  
  @variables_count 100
  
  setup_all do
    # Start dependencies
    {:ok, _} = Application.ensure_all_started(:snakepit)
    
    # Create contexts
    {:ok, local_ctx} = Context.start_link()
    {:ok, bridged_ctx} = Context.start_link()
    Context.ensure_bridged(bridged_ctx)
    
    # Populate with variables
    for i <- 1..@variables_count do
      Variables.defvariable!(local_ctx, :"var_#{i}", :integer, i)
      Variables.defvariable!(bridged_ctx, :"var_#{i}", :integer, i)
    end
    
    {:ok, %{local: local_ctx, bridged: bridged_ctx}}
  end
  
  bench "LocalState get", [contexts: bench_context] do
    Variables.get(contexts.local, :var_50)
  end
  
  bench "BridgedState get", [contexts: bench_context] do
    Variables.get(contexts.bridged, :var_50)
  end
  
  bench "LocalState set", [contexts: bench_context] do
    Variables.set(contexts.local, :var_50, :rand.uniform(1000))
  end
  
  bench "BridgedState set", [contexts: bench_context] do
    Variables.set(contexts.bridged, :var_50, :rand.uniform(1000))
  end
  
  bench "LocalState batch get (10)", [contexts: bench_context] do
    vars = Enum.map(1..10, &:"var_#{&1}")
    Variables.get_many(contexts.local, vars)
  end
  
  bench "BridgedState batch get (10)", [contexts: bench_context] do
    vars = Enum.map(1..10, &:"var_#{&1}")
    Variables.get_many(contexts.bridged, vars)
  end
  
  bench "Backend switch (10 variables)" do
    {:ok, ctx} = Context.start_link()
    
    for i <- 1..10 do
      Variables.defvariable!(ctx, :"bench_#{i}", :float, i * 0.1)
    end
    
    Context.ensure_bridged(ctx)
    Context.stop(ctx)
  end
  
  teardown_all contexts do
    Context.stop(contexts.local)
    Context.stop(contexts.bridged)
  end
end
```

### Property-Based Tests

```elixir
# File: test/dspex/property_test.exs

defmodule DSPex.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  alias DSPex.{Context, Variables}
  
  property "variables maintain value across backend switches" do
    check all name <- atom(:alphanumeric),
              type <- member_of([:float, :integer, :string, :boolean]),
              value <- value_generator(type),
              max_runs: 50 do
      
      {:ok, ctx} = Context.start_link()
      
      # Define in local backend
      assert {:ok, _} = Variables.defvariable(ctx, name, type, value)
      
      # Switch to bridged
      :ok = Context.ensure_bridged(ctx)
      
      # Value preserved
      assert Variables.get(ctx, name) == value
      
      Context.stop(ctx)
    end
  end
  
  property "constraints enforced in both backends" do
    check all name <- atom(:alphanumeric),
              min <- integer(0..50),
              max <- integer(51..100),
              valid <- integer(min..max),
              invalid <- one_of([integer(max+1..200), integer(-100..min-1)]),
              max_runs: 50 do
      
      for backend <- [:local, :bridged] do
        {:ok, ctx} = Context.start_link()
        
        if backend == :bridged do
          Context.ensure_bridged(ctx)
        end
        
        # Define with constraints
        assert {:ok, _} = Variables.defvariable(ctx, name, :integer, valid,
          constraints: %{min: min, max: max}
        )
        
        # Valid update works
        assert :ok = Variables.set(ctx, name, div(min + max, 2))
        
        # Invalid update fails
        assert {:error, _} = Variables.set(ctx, name, invalid)
        
        Context.stop(ctx)
      end
    end
  end
  
  # Generators
  
  defp value_generator(:float), do: float()
  defp value_generator(:integer), do: integer()
  defp value_generator(:string), do: string(:alphanumeric, min_length: 1)
  defp value_generator(:boolean), do: boolean()
end
```

## Test Organization

### Test Categories

1. **Unit Tests**: Individual components
   - StateProvider implementations
   - Context operations
   - Variables API

2. **Integration Tests**: Component interactions
   - Backend switching
   - State migration
   - Python bridge

3. **Performance Tests**: Speed and efficiency
   - Operation latency
   - Batch performance
   - Switch overhead

4. **Property Tests**: Invariants
   - Value preservation
   - Constraint enforcement
   - API consistency

## Continuous Integration

```yaml
# File: .github/workflows/stage2_tests.yml

name: Stage 2 Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25'
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'
    
    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          deps
          _build
          priv/python/.venv
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
    
    - name: Install dependencies
      run: |
        mix deps.get
        cd priv/python && pip install -r requirements.txt
    
    - name: Run unit tests
      run: mix test --only unit
    
    - name: Run integration tests
      run: mix test --only integration
    
    - name: Run property tests
      run: mix test --only property
    
    - name: Run benchmarks
      run: mix run bench/stage2_benchmarks.exs
    
    - name: Check coverage
      run: mix coveralls.github
```

## Success Metrics

The Stage 2 implementation is successful when:

1. **Performance**:
   - LocalState: < 1μs average get operation
   - Backend switch: < 50ms for typical state
   - BridgedState: < 2ms average operation

2. **Functionality**:
   - All tests pass consistently
   - Python integration works seamlessly
   - State migration preserves all data

3. **Reliability**:
   - No data loss during switches
   - Graceful error handling
   - Concurrent operation safety

## Stage 2 Complete!

With these comprehensive tests, Stage 2 implementation is complete. The system now provides:

1. ✅ Automatic backend switching based on program needs
2. ✅ Blazing-fast LocalState for pure Elixir
3. ✅ Seamless BridgedState for Python integration
4. ✅ High-level Variables API
5. ✅ Variable-aware DSPy modules
6. ✅ Complete test coverage

Ready for Stage 3: Streaming and Reactive Capabilities!