defmodule BridgePerformanceBench do
  @moduledoc """
  Performance benchmarks for DSPex bridge operations.
  
  Measures latency of:
  - Bridge calls
  - Tool executions
  - Session operations
  - Contract validations
  """
  
  use Benchfella
  
  setup_all do
    {:ok, _} = Application.ensure_all_started(:dspex)
    
    # Create session with variables
    session_id = "bench_session"
    
    # Register some test tools
    DSPex.Bridge.Tools.register_tool(session_id, "multiply", fn args ->
      Map.get(args, "x", 0) * Map.get(args, "y", 1)
    end)
    
    DSPex.Bridge.Tools.register_tool(session_id, "slow_operation", fn _args ->
      :timer.sleep(10)
      {:ok, "done"}
    end)
    
    DSPex.Bridge.Tools.register_tool(session_id, "validate_input", fn args ->
      case args do
        %{"value" => v} when is_number(v) and v > 0 -> {:ok, v}
        _ -> {:error, "Invalid input"}
      end
    end)
    
    # Create some DSPy instances
    {:ok, {pred_session, pred_instance}} = DSPex.Bridge.create_instance(
      "dspy.Predict",
      %{"signature" => "question -> answer"}
    )
    
    {:ok, {cot_session, cot_instance}} = DSPex.Bridge.create_instance(
      "dspy.ChainOfThought",
      %{"signature" => "question -> reasoning, answer"}
    )
    
    {:ok, 
      session_id: session_id,
      predict_ref: {pred_session, pred_instance},
      cot_ref: {cot_session, cot_instance}
    }
  end
  
  # Bridge Call Latency
  
  bench "bridge: static method call" do
    DSPex.Bridge.call_dspy("dspy", "settings", %{})
  end
  
  bench "bridge: instance creation" do
    DSPex.Bridge.create_instance("dspy.Predict", %{"signature" => "q -> a"})
  end
  
  bench "bridge: method call on instance", [predict_ref: bench_context[:predict_ref]] do
    DSPex.Bridge.call_method(predict_ref, "__call__", %{"question" => "Benchmark question?"})
  end
  
  bench "bridge: discovery (cached)" do
    DSPex.Bridge.discover_schema("dspy")
  end
  
  # Tool Execution Performance
  
  bench "tools: simple function", [session_id: bench_context[:session_id]] do
    DSPex.Bridge.Tools.Executor.execute("multiply", %{"x" => 7, "y" => 6}, %{
      session_id: session_id,
      caller: :elixir
    })
  end
  
  bench "tools: with validation", [session_id: bench_context[:session_id]] do
    DSPex.Bridge.Tools.Executor.execute("validate_input", %{"value" => 42}, %{
      session_id: session_id,
      caller: :elixir
    })
  end
  
  bench "tools: async execution", [session_id: bench_context[:session_id]] do
    {:ok, task} = DSPex.Bridge.Tools.Executor.execute_async("multiply", %{"x" => 10, "y" => 20}, %{
      session_id: session_id
    })
    Task.await(task)
  end
  
  bench "tools: concurrent execution", [session_id: bench_context[:session_id], count: 10] do
    tasks = for i <- 1..count do
      Task.async(fn ->
        DSPex.Bridge.Tools.Executor.execute("multiply", %{"x" => i, "y" => i}, %{
          session_id: session_id,
          caller: :elixir
        })
      end)
    end
    
    Task.await_many(tasks)
  end
  
  # Session Operations
  
  bench "session: create with variables" do
    DSPex.Session.new(variables: %{
      "temperature" => 0.7,
      "max_tokens" => 100,
      "model" => "gpt-3.5-turbo"
    })
  end
  
  bench "session: set/get cycle" do
    session = DSPex.Session.new()
    key = "bench_key_#{:rand.uniform(1000)}"
    
    DSPex.Session.set_variable(session, key, "test_value")
    DSPex.Session.get_variable(session, key)
  end
  
  bench "session: bulk operations" do
    session = DSPex.Session.new()
    
    # Set 10 variables
    for i <- 1..10 do
      DSPex.Session.set_variable(session, "key_#{i}", "value_#{i}")
    end
    
    # Get all variables
    DSPex.Session.get_all_variables(session)
  end
  
  # Contract Validation Performance
  
  bench "contract: simple validation" do
    spec = [name: {:required, :string}, age: {:optional, :integer, 0}]
    params = %{"name" => "Test User", "age" => 25}
    
    DSPex.Contract.Validation.validate_params(params, spec)
  end
  
  bench "contract: complex validation" do
    spec = [
      user: {:required, :map},
      items: {:required, {:list, :map}},
      metadata: {:optional, :map, %{}},
      tags: {:optional, {:list, :string}, []},
      enabled: {:optional, :boolean, true}
    ]
    
    params = %{
      "user" => %{"id" => 1, "name" => "Test"},
      "items" => [
        %{"id" => 1, "name" => "Item 1"},
        %{"id" => 2, "name" => "Item 2"}
      ],
      "tags" => ["benchmark", "test"]
    }
    
    DSPex.Contract.Validation.validate_params(params, spec)
  end
  
  bench "contract: type casting" do
    DSPex.Contract.Validation.cast_result("42", :integer)
  end
  
  # Enhanced Mode Operations
  
  bench "bridge: enhanced predict" do
    {:ok, enhanced_ref} = DSPex.Bridge.create_enhanced_wrapper(
      "dspy.Predict",
      signature: "question -> answer"
    )
    
    DSPex.Bridge.execute_enhanced(enhanced_ref, %{
      "question" => "What is performance?"
    })
  end
  
  bench "bridge: enhanced chain of thought" do
    {:ok, enhanced_ref} = DSPex.Bridge.create_enhanced_wrapper(
      "dspy.ChainOfThought",
      signature: "question -> reasoning, answer"
    )
    
    DSPex.Bridge.execute_enhanced(enhanced_ref, %{
      "question" => "Explain benchmarking"
    })
  end
  
  # Real-world Scenarios
  
  bench "scenario: rag pipeline simulation" do
    session = DSPex.Session.new()
    
    # Set context
    DSPex.Session.set_variable(session, "context", "Benchmarking measures performance...")
    
    # Create retriever (simulated)
    DSPex.Session.set_variable(session, "retrieved_docs", [
      "Doc 1: Performance testing is important",
      "Doc 2: Benchmarks help measure speed"
    ])
    
    # Create predictor
    {:ok, {sess_id, pred_id}} = DSPex.Bridge.create_instance(
      "dspy.Predict",
      %{"signature" => "context, question -> answer"},
      session_id: session.id
    )
    
    # Execute prediction
    DSPex.Bridge.call_method(
      {sess_id, pred_id},
      "__call__",
      %{
        "context" => DSPex.Session.get_variable(session, "context"),
        "question" => "What is benchmarking?"
      }
    )
  end
  
  bench "scenario: multi-step reasoning" do
    session = DSPex.Session.new()
    
    # Step 1: Initial analysis
    {:ok, step1} = DSPex.Bridge.create_enhanced_wrapper(
      "dspy.ChainOfThought",
      session_id: session.id,
      signature: "problem -> approach, considerations"
    )
    
    {:ok, result1} = DSPex.Bridge.execute_enhanced(step1, %{
      "problem" => "Optimize database queries"
    })
    
    # Step 2: Detailed planning
    DSPex.Session.set_variable(session, "approach", result1["approach"])
    
    {:ok, step2} = DSPex.Bridge.create_enhanced_wrapper(
      "dspy.Predict",
      session_id: session.id,
      signature: "approach, considerations -> implementation_steps"
    )
    
    DSPex.Bridge.execute_enhanced(step2, %{
      "approach" => result1["approach"],
      "considerations" => result1["considerations"]
    })
  end
  
  # Stress Tests
  
  bench "stress: rapid session creation", [count: 100] do
    for i <- 1..count do
      session = DSPex.Session.new()
      DSPex.Session.set_variable(session, "index", i)
    end
  end
  
  bench "stress: high-frequency tool calls", [session_id: bench_context[:session_id], count: 1000] do
    for i <- 1..count do
      DSPex.Bridge.Tools.Executor.execute("multiply", %{"x" => i, "y" => 2}, %{
        session_id: session_id,
        caller: :elixir
      })
    end
  end
end