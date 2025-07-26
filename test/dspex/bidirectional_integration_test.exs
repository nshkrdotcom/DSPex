defmodule DSPex.BidirectionalIntegrationTest do
  use ExUnit.Case, async: false
  
  alias DSPex.Bridge.Tools.{Registry, Executor}
  alias DSPex.Tools
  alias DSPex.Examples.{BiChainOfThought, Validators, ContextProvider}
  
  require Logger
  
  setup do
    # Clear any existing tools
    Registry.clear()
    
    # Capture telemetry events
    :telemetry.attach_many(
      "test-handler",
      [
        [:dspex, :tools, :execute, :start],
        [:dspex, :tools, :execute, :stop],
        [:dspex, :tools, :execute, :exception]
      ],
      fn event, measurements, metadata, config ->
        send(config.test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{test_pid: self()}
    )
    
    on_exit(fn ->
      :telemetry.detach("test-handler")
      Registry.clear()
    end)
    
    :ok
  end
  
  describe "Basic tool calling" do
    test "Python calls simple Elixir function" do
      # Define a module with test functions
      defmodule TestTools do
        def uppercase(%{"text" => text}), do: String.upcase(text)
      end
      
      # Register a simple tool
      assert :ok = Registry.register("uppercase", {TestTools, :uppercase}, %{
        description: "Converts string to uppercase"
      })
      
      # Execute the tool
      assert {:ok, "HELLO WORLD"} = Executor.execute("uppercase", %{"text" => "hello world"}, %{
        session_id: "test-session"
      })
      
      # Verify telemetry was emitted
      assert_receive {:telemetry, [:dspex, :tools, :execute, :start], _, %{tool_name: "uppercase"}}
      assert_receive {:telemetry, [:dspex, :tools, :execute, :stop], %{duration: duration}, _}
      assert duration > 0
    end
    
    test "Parameters passed correctly" do
      # Register a tool that validates parameters
      validator = fn args ->
        assert is_map(args)
        assert Map.has_key?(args, "email")
        String.contains?(args["email"], "@")
      end
      
      assert :ok = Registry.register("validate_email", {__MODULE__, :test_validator}, %{})
      
      # Mock the function
      defmodule TestValidator do
        def test_validator(%{"email" => email}) do
          String.contains?(email, "@")
        end
      end
      
      assert :ok = Registry.register("validate_email", {TestValidator, :test_validator}, %{})
      
      # Test with valid email
      assert {:ok, true} = Executor.execute("validate_email", %{"email" => "test@example.com"}, %{
        session_id: "test-session"
      })
      
      # Test with invalid email
      assert {:ok, false} = Executor.execute("validate_email", %{"email" => "invalid"}, %{
        session_id: "test-session"
      })
    end
    
    test "Return values work correctly" do
      # Test different return types
      tools = [
        {"return_map", fn _args -> %{status: "ok", data: [1, 2, 3]} end},
        {"return_list", fn _args -> [1, 2, 3, 4, 5] end},
        {"return_string", fn _args -> "success" end},
        {"return_number", fn _args -> 42 end},
        {"return_boolean", fn _args -> true end},
        {"return_nil", fn _args -> nil end}
      ]
      
      for {name, func} <- tools do
        assert {:ok, {mod, fun}} = extract_function_ref(func)
        assert :ok = Registry.register(name, {mod, fun}, %{})
      end
      
      # Verify each return type
      assert {:ok, %{status: "ok", data: [1, 2, 3]}} = 
        Executor.execute("return_map", %{}, %{session_id: "test"})
        
      assert {:ok, [1, 2, 3, 4, 5]} = 
        Executor.execute("return_list", %{}, %{session_id: "test"})
        
      assert {:ok, "success"} = 
        Executor.execute("return_string", %{}, %{session_id: "test"})
        
      assert {:ok, 42} = 
        Executor.execute("return_number", %{}, %{session_id: "test"})
        
      assert {:ok, true} = 
        Executor.execute("return_boolean", %{}, %{session_id: "test"})
        
      assert {:ok, nil} = 
        Executor.execute("return_nil", %{}, %{session_id: "test"})
    end
    
    test "Errors handled gracefully" do
      # Register a tool that raises an error
      error_tool = fn _args -> raise "Something went wrong!" end
      
      assert {:ok, {mod, fun}} = extract_function_ref(error_tool)
      assert :ok = Registry.register("error_tool", {mod, fun}, %{})
      
      # Execute and verify error handling
      assert {:error, {:exception, %RuntimeError{message: "Something went wrong!"}}} = 
        Executor.execute("error_tool", %{}, %{session_id: "test"})
        
      # Verify exception telemetry
      assert_receive {:telemetry, [:dspex, :tools, :execute, :exception], _, %{
        tool_name: "error_tool",
        kind: :exit
      }}
    end
  end
  
  describe "Complex workflow tests" do
    test "Multi-step validation flow" do
      # Register validation tools
      Tools.register_module(BiChainOfThought)
      
      # Step 1: Validate reasoning
      reasoning = """
      First, we need to understand the problem.
      Second, we analyze the available data.
      Therefore, we can conclude that the solution is valid.
      """
      
      assert {:ok, true} = Tools.call("dspex.examples.bi_chain_of_thought.validate_reasoning", %{
        "reasoning" => reasoning
      })
      
      # Step 2: Score the reasoning
      assert {:ok, score} = Tools.call("dspex.examples.bi_chain_of_thought.score_reasoning", %{
        "reasoning" => reasoning
      })
      assert score > 0.5
      
      # Step 3: Improve if needed
      if score < 0.8 do
        assert {:ok, improved} = Tools.call("dspex.examples.bi_chain_of_thought.improve_reasoning", %{
          "reasoning" => reasoning,
          "domain" => "general"
        })
        
        assert improved["original_score"] == score
        assert String.length(improved["improved_reasoning"]) > String.length(reasoning)
      end
    end
    
    test "Tools calling other tools" do
      # Create a tool that calls another tool
      meta_tool = fn %{"tool" => tool_name, "args" => args} ->
        case Tools.call(tool_name, args) do
          {:ok, result} -> %{success: true, result: result}
          {:error, error} -> %{success: false, error: inspect(error)}
        end
      end
      
      assert {:ok, {mod, fun}} = extract_function_ref(meta_tool)
      assert :ok = Registry.register("meta_tool", {mod, fun}, %{})
      
      # Register a simple tool to be called
      assert :ok = Tools.register("add", fn %{"a" => a, "b" => b} -> a + b end)
      
      # Call the meta tool
      assert {:ok, %{success: true, result: 7}} = Tools.call("meta_tool", %{
        "tool" => "add",
        "args" => %{"a" => 3, "b" => 4}
      })
    end
    
    test "Session state interaction" do
      session_id = "test-session-#{System.unique_integer()}"
      
      # Register a stateful tool
      {:ok, agent} = Agent.start_link(fn -> %{} end)
      
      stateful_tool = fn
        %{"action" => "set", "key" => key, "value" => value} ->
          Agent.update(agent, &Map.put(&1, key, value))
          :ok
          
        %{"action" => "get", "key" => key} ->
          Agent.get(agent, &Map.get(&1, key))
          
        %{"action" => "list"} ->
          Agent.get(agent, & &1)
      end
      
      assert {:ok, {mod, fun}} = extract_function_ref(stateful_tool)
      assert :ok = Registry.register("session_state", {mod, fun}, %{})
      
      # Interact with state
      assert {:ok, :ok} = Executor.execute("session_state", 
        %{"action" => "set", "key" => "user", "value" => "alice"},
        %{session_id: session_id}
      )
      
      assert {:ok, :ok} = Executor.execute("session_state",
        %{"action" => "set", "key" => "score", "value" => 95},
        %{session_id: session_id}
      )
      
      assert {:ok, "alice"} = Executor.execute("session_state",
        %{"action" => "get", "key" => "user"},
        %{session_id: session_id}
      )
      
      assert {:ok, %{"user" => "alice", "score" => 95}} = Executor.execute("session_state",
        %{"action" => "list"},
        %{session_id: session_id}
      )
      
      Agent.stop(agent)
    end
    
    test "Concurrent tool calls" do
      # Register a slow tool
      slow_tool = fn %{"delay" => delay} ->
        Process.sleep(delay)
        {:ok, delay}
      end
      
      assert {:ok, {mod, fun}} = extract_function_ref(slow_tool)
      assert :ok = Registry.register("slow_tool", {mod, fun}, %{})
      
      # Execute multiple tools concurrently
      tasks = for delay <- [100, 200, 150, 50] do
        Task.async(fn ->
          Executor.execute("slow_tool", %{"delay" => delay}, %{
            session_id: "concurrent-test",
            timeout: 1000
          })
        end)
      end
      
      # Collect results
      results = Task.await_many(tasks, 5000)
      
      assert length(results) == 4
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      # Verify all completed
      delays = Enum.map(results, fn {:ok, delay} -> delay end) |> Enum.sort()
      assert delays == [50, 100, 150, 200]
    end
  end
  
  describe "Performance tests" do
    test "Tool execution time tracking" do
      # Register tools with different execution times
      fast_tool = fn _args -> :ok end
      medium_tool = fn _args -> Process.sleep(10); :ok end
      slow_tool = fn _args -> Process.sleep(50); :ok end
      
      for {name, func} <- [{"fast", fast_tool}, {"medium", medium_tool}, {"slow", slow_tool}] do
        assert {:ok, {mod, fun}} = extract_function_ref(func)
        assert :ok = Registry.register(name, {mod, fun}, %{})
      end
      
      # Execute and measure
      for tool <- ["fast", "medium", "slow"] do
        Executor.execute(tool, %{}, %{session_id: "perf-test"})
        
        assert_receive {:telemetry, [:dspex, :tools, :execute, :stop], measurements, %{
          tool_name: ^tool
        }}
        
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        
        case tool do
          "fast" -> assert duration_ms < 5
          "medium" -> assert duration_ms >= 10 and duration_ms < 30
          "slow" -> assert duration_ms >= 50 and duration_ms < 100
        end
      end
    end
    
    test "Overhead measurement" do
      # Simple function for baseline
      direct_func = fn x -> x * 2 end
      
      # Register it as a tool
      assert {:ok, {mod, fun}} = extract_function_ref(direct_func)
      assert :ok = Registry.register("multiply", {mod, fun}, %{})
      
      # Measure direct call time
      direct_start = System.monotonic_time()
      for _ <- 1..1000, do: direct_func.(5)
      direct_time = System.monotonic_time() - direct_start
      
      # Measure tool call time
      tool_start = System.monotonic_time()
      for _ <- 1..1000 do
        Executor.execute("multiply", %{"0" => 5}, %{session_id: "overhead-test"})
      end
      tool_time = System.monotonic_time() - tool_start
      
      # Calculate overhead
      overhead_ratio = tool_time / direct_time
      Logger.info("Tool overhead ratio: #{Float.round(overhead_ratio, 2)}x")
      
      # Overhead should be reasonable (less than 10x for this simple case)
      assert overhead_ratio < 10.0
    end
    
    test "Memory usage validation" do
      # Create a tool that allocates memory
      memory_tool = fn %{"size" => size} ->
        # Create a list of the specified size
        data = Enum.map(1..size, &to_string/1)
        length(data)
      end
      
      assert {:ok, {mod, fun}} = extract_function_ref(memory_tool)
      assert :ok = Registry.register("memory_tool", {mod, fun}, %{})
      
      # Get initial memory
      {:memory, initial_memory} = Process.info(self(), :memory)
      
      # Execute tool multiple times
      for _ <- 1..100 do
        {:ok, _} = Executor.execute("memory_tool", %{"size" => 1000}, %{
          session_id: "memory-test"
        })
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      
      # Check memory didn't leak significantly
      {:memory, final_memory} = Process.info(self(), :memory)
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be minimal after GC
      assert memory_increase < 1_000_000  # Less than 1MB increase
    end
  end
  
  describe "Error scenario tests" do
    test "Tool not found" do
      assert {:error, :not_found} = Executor.execute("nonexistent", %{}, %{
        session_id: "error-test"
      })
    end
    
    test "Tool timeout" do
      # Register a tool that never completes
      infinite_tool = fn _args ->
        Process.sleep(:infinity)
      end
      
      assert {:ok, {mod, fun}} = extract_function_ref(infinite_tool)
      assert :ok = Registry.register("infinite", {mod, fun}, %{})
      
      # Execute with short timeout
      assert {:error, :timeout} = Executor.execute("infinite", %{}, %{
        session_id: "timeout-test",
        timeout: 100
      })
      
      # Verify timeout telemetry
      assert_receive {:telemetry, [:dspex, :tools, :execute, :exception], _, %{
        kind: :timeout,
        timeout: 100
      }}
    end
    
    test "Tool exception" do
      # Various error scenarios
      error_tools = [
        {"arg_error", fn _args -> raise ArgumentError, "Invalid argument" end},
        {"match_error", fn _args -> [a, b] = [1] end},
        {"arithmetic_error", fn _args -> 1 / 0 end}
      ]
      
      for {name, func} <- error_tools do
        assert {:ok, {mod, fun}} = extract_function_ref(func)
        assert :ok = Registry.register(name, {mod, fun}, %{})
        
        assert {:error, {:exception, _}} = Executor.execute(name, %{}, %{
          session_id: "exception-test"
        })
      end
    end
    
    test "Serialization failure" do
      # Register a tool that returns a non-serializable value
      pid_tool = fn _args -> self() end
      
      assert {:ok, {mod, fun}} = extract_function_ref(pid_tool)
      assert :ok = Registry.register("return_pid", {mod, fun}, %{})
      
      # This should succeed (returns a PID)
      assert {:ok, pid} = Executor.execute("return_pid", %{}, %{
        session_id: "serialize-test"
      })
      
      assert is_pid(pid)
    end
  end
  
  describe "Real use case: ChainOfThought with validation" do
    @tag :integration
    test "ChainOfThought uses Elixir validation to improve quality" do
      # Register the BiChainOfThought module
      assert {:ok, tool_count} = Tools.register_module(BiChainOfThought)
      assert tool_count > 0
      
      # Initial reasoning that needs improvement
      initial_reasoning = """
      The answer is 42.
      """
      
      # Validate the initial reasoning
      assert {:ok, false} = Tools.call(
        "dspex.examples.bi_chain_of_thought.validate_reasoning",
        %{"reasoning" => initial_reasoning}
      )
      
      # Score it
      assert {:ok, low_score} = Tools.call(
        "dspex.examples.bi_chain_of_thought.score_reasoning",
        %{"reasoning" => initial_reasoning}
      )
      assert low_score < 0.5
      
      # Improve it
      assert {:ok, improvement} = Tools.call(
        "dspex.examples.bi_chain_of_thought.improve_reasoning",
        %{"reasoning" => initial_reasoning, "domain" => "general"}
      )
      
      # Validate improved reasoning
      improved_reasoning = improvement["improved_reasoning"]
      assert String.length(improved_reasoning) > String.length(initial_reasoning)
      
      # Score should be better
      assert {:ok, improved_score} = Tools.call(
        "dspex.examples.bi_chain_of_thought.score_reasoning",
        %{"reasoning" => improved_reasoning}
      )
      assert improved_score > low_score
      
      # Verify telemetry shows the tool calls
      assert_received {:telemetry, [:dspex, :tools, :execute, :stop], _, %{
        tool_name: "dspex.examples.bi_chain_of_thought.validate_reasoning"
      }}
    end
    
    test "Medical domain validation with specific rules" do
      # Register validators
      Tools.register_module(BiChainOfThought)
      
      # Medical reasoning example
      medical_reasoning = """
      First, we observe the patient presents with persistent cough and fever.
      
      Second, differential diagnosis includes:
      - Bacterial pneumonia
      - Viral respiratory infection
      - COVID-19
      
      Clinical examination reveals crackling sounds in the lower right lung.
      
      Therefore, the most likely diagnosis is bacterial pneumonia, and we should
      start antibiotic therapy while awaiting culture results.
      """
      
      # Fetch medical rules
      assert {:ok, rules} = Tools.call(
        "dspex.examples.bi_chain_of_thought.fetch_rules",
        %{"domain" => "medical"}
      )
      
      assert rules["required_keywords"]
      assert rules["evidence_based"]
      
      # Validate with medical rules
      assert {:ok, result} = Tools.call(
        "dspex.examples.bi_chain_of_thought.validate_reasoning",
        %{"reasoning" => medical_reasoning}
      )
      
      assert result == true
      
      # Get quality score
      assert {:ok, score} = Tools.call(
        "dspex.examples.bi_chain_of_thought.score_reasoning",
        %{"reasoning" => medical_reasoning}
      )
      
      assert score > 0.7
    end
  end
  
  # Helper function  
  defp extract_function_ref(func) when is_function(func) do
    info = Function.info(func)
    case {info[:type], info[:module], info[:name]} do
      {:external, module, name} -> {:ok, {module, name}}
      _ -> 
        # For anonymous functions, we can't extract a reference
        # Return the function itself - the test will need to handle this
        {:ok, func}
    end
  end
end