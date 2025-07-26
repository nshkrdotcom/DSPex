defmodule ThreeLayerBench do
  use Benchfella

  # Setup for benchmarks
  setup_all do
    {:ok, _} = Application.ensure_all_started(:snakepit)
    {:ok, _} = Application.ensure_all_started(:snakepit_grpc_bridge)
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Pre-create test data
    alias DSPex.Modules.Predict
    alias DSPex.Native.Signature
    
    predictor = Predict.new(Signature.new("question -> answer"))
    
    {:ok, predictor: predictor}
  end

  # Layer 1: Snakepit Core Benchmarks
  
  bench "snakepit: pool execution" do
    Snakepit.Pool.execute("echo", %{message: "test"}, pool: Snakepit.DefaultPool)
  end

  bench "snakepit: session routing" do
    session_id = "bench_session_#{:rand.uniform(1000)}"
    Snakepit.Pool.execute("echo", %{message: "test"}, 
      pool: Snakepit.DefaultPool, 
      session_id: session_id
    )
  end

  bench "snakepit: concurrent execution", [count: 10] do
    tasks = for i <- 1..count do
      Task.async(fn ->
        Snakepit.Pool.execute("echo", %{message: "test_#{i}"}, pool: Snakepit.DefaultPool)
      end)
    end
    
    Task.await_many(tasks)
  end

  # Layer 2: SnakepitGrpcBridge Benchmarks
  
  bench "bridge: schema discovery (cached)" do
    # After first call, should be cached
    SnakepitGrpcBridge.Schema.DSPy.discover_schema("dspy")
  end

  bench "bridge: variable set/get" do
    session_id = "bench_#{:rand.uniform(100000)}"
    SnakepitGrpcBridge.Variables.set(session_id, "key", "value")
    SnakepitGrpcBridge.Variables.get(session_id, "key")
  end

  bench "bridge: dspy execution" do
    session_id = "bench_#{:rand.uniform(100000)}"
    SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{
      "class_path" => "dspy.Predict",
      "method" => "__init__",
      "args" => ["q -> a"],
      "kwargs" => %{}
    })
  end

  bench "bridge: cognitive worker execution" do
    {:ok, worker} = SnakepitGrpcBridge.Cognitive.Worker.start_link([])
    SnakepitGrpcBridge.Cognitive.Worker.execute(worker, "echo", %{msg: "test"})
    GenServer.stop(worker)
  end

  # Layer 3: DSPex Benchmarks
  
  bench "dspex: prediction", [predictor: bench_context[:predictor]] do
    DSPex.Modules.Predict.forward(predictor, %{question: "What is benchmarking?"})
  end

  bench "dspex: signature parsing" do
    DSPex.Native.Signature.new("input1, input2 -> output1, output2, output3")
  end

  bench "dspex: batch prediction", [predictor: bench_context[:predictor]] do
    inputs = for i <- 1..5 do
      %{question: "Question #{i}?"}
    end
    
    DSPex.Modules.Predict.forward_batch(predictor, inputs)
  end

  # End-to-End Benchmarks
  
  bench "e2e: simple prediction" do
    alias DSPex.Modules.Predict
    alias DSPex.Native.Signature
    
    predictor = Predict.new(Signature.new("q -> a"))
    Predict.forward(predictor, %{q: "Quick question?"})
  end

  bench "e2e: chain of thought" do
    alias DSPex.Modules.ChainOfThought
    alias DSPex.Native.Signature
    
    cot = ChainOfThought.new(Signature.new("q -> reasoning, answer"))
    ChainOfThought.forward(cot, %{q: "Complex question?"})
  end

  bench "e2e: with session context" do
    alias DSPex.Modules.Predict
    alias DSPex.Native.Signature
    
    session_id = "bench_#{:rand.uniform(100000)}"
    SnakepitGrpcBridge.Variables.set(session_id, "temperature", 0.5)
    
    predictor = Predict.new(Signature.new("q -> a"))
    Predict.forward(predictor, %{q: "Question?"}, session_id: session_id)
  end

  # Memory and Resource Benchmarks
  
  bench "memory: session creation and cleanup" do
    session_id = "mem_bench_#{:rand.uniform(100000)}"
    
    # Create session with data
    SnakepitGrpcBridge.initialize_session(session_id)
    SnakepitGrpcBridge.Variables.set(session_id, "data", String.duplicate("x", 1000))
    
    # Use session
    SnakepitGrpcBridge.Variables.get(session_id, "data")
    
    # Cleanup
    SnakepitGrpcBridge.cleanup_session(session_id)
  end

  bench "concurrency: parallel predictions", [count: 20] do
    alias DSPex.Modules.Predict
    alias DSPex.Native.Signature
    
    predictor = Predict.new(Signature.new("q -> a"))
    
    tasks = for i <- 1..count do
      Task.async(fn ->
        Predict.forward(predictor, %{q: "Concurrent question #{i}?"})
      end)
    end
    
    Task.await_many(tasks, 30_000)
  end
end