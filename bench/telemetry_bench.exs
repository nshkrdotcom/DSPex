defmodule TelemetryBench do
  @moduledoc """
  Performance benchmarks for DSPex telemetry and monitoring infrastructure.
  
  Measures the overhead of telemetry instrumentation and validates that
  performance monitoring doesn't significantly impact system performance.
  """
  
  use Benchfella
  
  # Setup for benchmarks
  setup_all do
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Start telemetry handlers
    {:ok, _} = DSPex.Telemetry.Handler.start_link()
    {:ok, _} = DSPex.Telemetry.Metrics.start_link()
    
    # Attach metrics handler
    DSPex.Telemetry.Metrics.attach()
    
    # Create test session
    session = DSPex.Session.new()
    
    {:ok, session: session}
  end
  
  # Telemetry Event Benchmarks
  
  bench "telemetry: execute simple event" do
    :telemetry.execute(
      [:dspex, :benchmark, :test],
      %{value: 42},
      %{test: true}
    )
  end
  
  bench "telemetry: execute with measurements" do
    start_time = System.monotonic_time()
    # Simulate some work
    :timer.sleep(1)
    duration = System.monotonic_time() - start_time
    
    :telemetry.execute(
      [:dspex, :benchmark, :operation],
      %{duration: duration, count: 10},
      %{operation: "test"}
    )
  end
  
  bench "telemetry: span execution" do
    :telemetry.span(
      [:dspex, :benchmark, :span],
      %{operation: "test"},
      fn ->
        # Simulate work
        result = Enum.sum(1..100)
        {result, %{}}
      end
    )
  end
  
  # Bridge Telemetry Benchmarks
  
  bench "bridge: call with telemetry" do
    DSPex.Bridge.call_dspy("dspy", "settings", %{})
  end
  
  bench "bridge: create instance with telemetry" do
    session_id = "bench_#{:rand.uniform(100000)}"
    DSPex.Bridge.create_instance("dspy.Predict", %{"signature" => "q -> a"}, session_id: session_id)
  end
  
  # Contract Validation Telemetry
  
  bench "contract: validate params with telemetry" do
    spec = [
      name: {:required, :string},
      count: {:optional, :integer, 10},
      enabled: {:optional, :boolean, true}
    ]
    
    params = %{
      "name" => "test",
      "count" => 42
    }
    
    DSPex.Contract.Validation.validate_params(params, spec)
  end
  
  bench "contract: cast result with telemetry" do
    DSPex.Contract.Validation.cast_result("42", :integer)
  end
  
  # Session Telemetry Benchmarks
  
  bench "session: set variable with telemetry", [session: bench_context[:session]] do
    key = "key_#{:rand.uniform(1000)}"
    DSPex.Session.set_variable(session, key, "value")
  end
  
  bench "session: get variable with telemetry", [session: bench_context[:session]] do
    # Pre-set some variables
    DSPex.Session.set_variable(session, "bench_key", "bench_value")
    DSPex.Session.get_variable(session, "bench_key")
  end
  
  bench "session: create new with telemetry" do
    DSPex.Session.new(variables: %{"temp" => 0.7, "max_tokens" => 100})
  end
  
  # Metrics Collection Benchmarks
  
  bench "metrics: record measurement" do
    GenServer.cast(DSPex.Telemetry.Metrics, {:record_metric, "test.metric", 42, false})
  end
  
  bench "metrics: get summary" do
    # Pre-populate some metrics
    for i <- 1..100 do
      GenServer.cast(DSPex.Telemetry.Metrics, {:record_metric, "bench.metric", i, false})
    end
    
    DSPex.Telemetry.Metrics.get_summary()
  end
  
  bench "metrics: export prometheus" do
    DSPex.Telemetry.Metrics.export_prometheus()
  end
  
  # High-Volume Event Benchmarks
  
  bench "telemetry: 1000 events burst" do
    for i <- 1..1000 do
      :telemetry.execute(
        [:dspex, :benchmark, :burst],
        %{value: i},
        %{index: i}
      )
    end
  end
  
  bench "telemetry: concurrent events", [count: 100] do
    tasks = for i <- 1..count do
      Task.async(fn ->
        :telemetry.execute(
          [:dspex, :benchmark, :concurrent],
          %{value: i, thread: self()},
          %{index: i}
        )
      end)
    end
    
    Task.await_many(tasks)
  end
  
  # Tool Execution Telemetry
  
  bench "tools: execute with telemetry" do
    # Register a simple tool
    session_id = "tool_bench_#{:rand.uniform(1000)}"
    DSPex.Bridge.Tools.register_tool(session_id, "bench_tool", fn args ->
      Map.get(args, "value", 0) * 2
    end)
    
    # Execute with telemetry
    DSPex.Bridge.Tools.Executor.execute("bench_tool", %{"value" => 21}, %{
      session_id: session_id,
      caller: :elixir
    })
  end
  
  # Complex Operation Benchmarks
  
  bench "e2e: prediction with full telemetry" do
    session = DSPex.Session.new()
    DSPex.Session.set_variable(session, "temperature", 0.7)
    
    {:ok, {session_id, instance_id}} = DSPex.Bridge.create_instance(
      "dspy.Predict",
      %{"signature" => "question -> answer"},
      session_id: session.id
    )
    
    DSPex.Bridge.call_method(
      {session_id, instance_id},
      "__call__",
      %{"question" => "What is telemetry?"}
    )
  end
  
  # Memory Impact Benchmarks
  
  bench "memory: telemetry handler overhead" do
    # Measure memory before
    before_mem = :erlang.memory(:total)
    
    # Execute many events
    for i <- 1..10_000 do
      :telemetry.execute(
        [:dspex, :memory, :test],
        %{value: i, memory: before_mem},
        %{iteration: i}
      )
    end
    
    # Measure memory after
    after_mem = :erlang.memory(:total)
    
    # Return memory delta
    after_mem - before_mem
  end
  
  # Percentile Calculation Benchmarks
  
  bench "metrics: percentile calculation" do
    # Generate sample data
    samples = for _ <- 1..1000, do: :rand.uniform(1000)
    sorted = Enum.sort(samples)
    
    # Calculate percentiles
    p50 = Enum.at(sorted, round(0.50 * length(sorted)))
    p95 = Enum.at(sorted, round(0.95 * length(sorted)))
    p99 = Enum.at(sorted, round(0.99 * length(sorted)))
    
    {p50, p95, p99}
  end
end