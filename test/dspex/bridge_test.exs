defmodule DSPex.BridgeTest do
  use ExUnit.Case, async: true
  alias DSPex.Bridge

  describe "bridge initialization" do
    test "initializes with default configuration" do
      assert {:ok, bridge} = Bridge.start_link()
      assert Process.alive?(bridge)
      GenServer.stop(bridge)
    end

    test "initializes with custom configuration" do
      config = [
        adapter: DSPex.Adapters.Mock,
        pool_size: 3,
        timeout: 10_000
      ]
      
      assert {:ok, bridge} = Bridge.start_link(config)
      
      state = :sys.get_state(bridge)
      assert state.config[:pool_size] == 3
      assert state.config[:timeout] == 10_000
      
      GenServer.stop(bridge)
    end
  end

  describe "DSPy module calls" do
    setup do
      {:ok, bridge} = Bridge.start_link(adapter: DSPex.Adapters.Mock)
      
      on_exit(fn ->
        if Process.alive?(bridge) do
          GenServer.stop(bridge)
        end
      end)
      
      %{bridge: bridge}
    end

    test "calls DSPy modules through bridge", %{bridge: bridge} do
      result = Bridge.call_dspy(bridge, "dspy.Predict", "__init__", ["question -> answer"])
      
      assert {:ok, instance_id} = result
      assert is_binary(instance_id)
    end

    test "executes predictions", %{bridge: bridge} do
      # Initialize predictor
      {:ok, instance_id} = Bridge.call_dspy(bridge, "dspy.Predict", "__init__", ["question -> answer"])
      
      # Execute prediction
      result = Bridge.call_dspy(bridge, instance_id, "__call__", [], %{question: "What is DSPy?"})
      
      assert {:ok, prediction} = result
      assert Map.has_key?(prediction, :answer)
      assert is_binary(prediction.answer)
    end

    test "handles errors gracefully", %{bridge: bridge} do
      result = Bridge.call_dspy(bridge, "invalid.Module", "method", [])
      
      assert {:error, reason} = result
      assert is_binary(reason)
    end
  end

  describe "session management" do
    setup do
      {:ok, bridge} = Bridge.start_link(adapter: DSPex.Adapters.Mock)
      %{bridge: bridge}
    end

    test "maintains session context", %{bridge: bridge} do
      session_id = "test_session_#{:rand.uniform(1000)}"
      
      # Set session context
      :ok = Bridge.set_session_context(bridge, session_id, %{
        temperature: 0.7,
        model: "gpt-4"
      })
      
      # Execute with session
      {:ok, _} = Bridge.call_dspy(bridge, "dspy.Predict", "__init__", ["q -> a"], 
        session_id: session_id)
      
      # Context should be maintained
      {:ok, context} = Bridge.get_session_context(bridge, session_id)
      assert context.temperature == 0.7
      assert context.model == "gpt-4"
      
      GenServer.stop(bridge)
    end

    test "isolates sessions", %{bridge: bridge} do
      session1 = "session1"
      session2 = "session2"
      
      Bridge.set_session_context(bridge, session1, %{value: "one"})
      Bridge.set_session_context(bridge, session2, %{value: "two"})
      
      {:ok, context1} = Bridge.get_session_context(bridge, session1)
      {:ok, context2} = Bridge.get_session_context(bridge, session2)
      
      assert context1.value == "one"
      assert context2.value == "two"
      
      GenServer.stop(bridge)
    end
  end

  describe "tool integration" do
    setup do
      {:ok, bridge} = Bridge.start_link(adapter: DSPex.Adapters.Mock)
      %{bridge: bridge}
    end

    test "registers Elixir tools", %{bridge: bridge} do
      tool_fn = fn %{text: text} ->
        %{length: String.length(text), uppercase: String.upcase(text)}
      end
      
      :ok = Bridge.register_tool(bridge, "text_processor", tool_fn, %{
        description: "Processes text",
        parameters: [
          %{name: "text", type: "string", required: true}
        ]
      })
      
      # Verify tool is registered
      {:ok, tools} = Bridge.list_tools(bridge)
      assert "text_processor" in tools
      
      GenServer.stop(bridge)
    end

    test "executes registered tools", %{bridge: bridge} do
      # Register tool
      Bridge.register_tool(bridge, "multiplier", fn %{x: x, y: y} -> x * y end)
      
      # Execute tool
      {:ok, result} = Bridge.execute_tool(bridge, "multiplier", %{x: 5, y: 3})
      assert result == 15
      
      GenServer.stop(bridge)
    end

    test "validates tool parameters", %{bridge: bridge} do
      # Register tool with schema
      Bridge.register_tool(bridge, "validator", fn %{age: age} -> age >= 18 end, %{
        parameters: [
          %{name: "age", type: "integer", required: true}
        ]
      })
      
      # Valid call
      assert {:ok, true} = Bridge.execute_tool(bridge, "validator", %{age: 21})
      
      # Invalid call - missing parameter
      assert {:error, {:missing_parameter, "age"}} = 
        Bridge.execute_tool(bridge, "validator", %{})
      
      GenServer.stop(bridge)
    end
  end

  describe "streaming support" do
    setup do
      {:ok, bridge} = Bridge.start_link(adapter: DSPex.Adapters.Mock)
      %{bridge: bridge}
    end

    test "streams responses", %{bridge: bridge} do
      {:ok, stream} = Bridge.stream_call(bridge, "dspy.Generate", "stream", %{
        prompt: "Tell me a story",
        max_tokens: 100
      })
      
      # Collect stream chunks
      chunks = Enum.take(stream, 5)
      
      assert length(chunks) == 5
      assert Enum.all?(chunks, &is_binary/1)
      
      GenServer.stop(bridge)
    end

    test "handles stream errors", %{bridge: bridge} do
      {:ok, stream} = Bridge.stream_call(bridge, "dspy.Generate", "error_stream", %{})
      
      # Should get error in stream
      assert_raise RuntimeError, fn ->
        Enum.to_list(stream)
      end
      
      GenServer.stop(bridge)
    end
  end

  describe "telemetry" do
    setup do
      {:ok, bridge} = Bridge.start_link(adapter: DSPex.Adapters.Mock)
      %{bridge: bridge}
    end

    test "emits telemetry for bridge operations", %{bridge: bridge} do
      ref = make_ref()
      
      :telemetry.attach(
        "test-bridge-#{inspect(ref)}",
        [:dspex, :bridge, :call, :stop],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )
      
      Bridge.call_dspy(bridge, "dspy.Predict", "__init__", ["signature"])
      
      assert_receive {:telemetry, measurements, metadata}, 1000
      
      assert measurements.duration > 0
      assert metadata.module == "dspy.Predict"
      assert metadata.method == "__init__"
      assert metadata.success == true
      
      :telemetry.detach("test-bridge-#{inspect(ref)}")
      GenServer.stop(bridge)
    end
  end

  describe "error recovery" do
    setup do
      {:ok, bridge} = Bridge.start_link(
        adapter: DSPex.Adapters.Mock,
        retry_attempts: 3,
        retry_delay: 10
      )
      %{bridge: bridge}
    end

    test "retries failed operations", %{bridge: bridge} do
      # Configure to fail first 2 attempts
      Bridge.configure_mock_failures(bridge, 2)
      
      # Should succeed on 3rd attempt
      {:ok, _result} = Bridge.call_dspy(bridge, "dspy.Predict", "flaky_method", [])
      
      # Check retry stats
      stats = Bridge.get_stats(bridge)
      assert stats.retry_count == 2
      
      GenServer.stop(bridge)
    end

    test "gives up after max retries", %{bridge: bridge} do
      # Configure to always fail
      Bridge.configure_mock_failures(bridge, :always)
      
      # Should fail after retries
      {:error, reason} = Bridge.call_dspy(bridge, "dspy.Predict", "failing_method", [])
      assert reason =~ "max retries"
      
      GenServer.stop(bridge)
    end
  end
end