defmodule DSPex.PredictIntegrationTest do
  use ExUnit.Case, async: false
  
  alias DSPex.Predict
  alias DSPex.Types.Prediction
  
  describe "Slice 1: Basic Predict with contracts" do
    setup do
      # Start telemetry handler for test
      test_pid = self()
      handler_id = "test-handler-#{System.unique_integer()}"
      
      :telemetry.attach_many(
        handler_id,
        [
          [:dspex, :bridge, :create_instance, :start],
          [:dspex, :bridge, :create_instance, :stop],
          [:dspex, :bridge, :create_instance, :exception],
          [:dspex, :bridge, :call_method, :start],
          [:dspex, :bridge, :call_method, :stop],
          [:dspex, :bridge, :call_method, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)
      
      {:ok, handler_id: handler_id}
    end
    
    test "contract-based Predict module works identically to the old one" do
      # Create predictor using new contract-based API
      {:ok, predictor} = Predict.create(%{signature: "question -> answer"})
      
      # Verify we get a proper reference
      assert {session_id, instance_id} = predictor
      assert is_binary(session_id)
      assert is_binary(instance_id)
      
      # Execute prediction
      {:ok, result} = Predict.predict(predictor, %{question: "What is 2+2?"})
      
      # Verify result is properly typed
      assert %Prediction{} = result
      assert is_binary(result.answer)
      assert result.answer != ""
    end
    
    test "telemetry events are emitted correctly" do
      # Create predictor
      {:ok, predictor} = Predict.create(%{signature: "question -> answer"})
      
      # Verify create_instance telemetry
      assert_receive {:telemetry_event, [:dspex, :bridge, :create_instance, :start], 
                      _measurements, metadata}
      assert metadata.python_class == "dspy.Predict"
      assert metadata.args == %{signature: "question -> answer"}
      
      assert_receive {:telemetry_event, [:dspex, :bridge, :create_instance, :stop], 
                      measurements, metadata}
      assert measurements.duration > 0
      assert metadata.success == true
      
      # Execute prediction
      {:ok, _result} = Predict.predict(predictor, %{question: "Why is the sky blue?"})
      
      # Verify call_method telemetry
      assert_receive {:telemetry_event, [:dspex, :bridge, :call_method, :start], 
                      _measurements, metadata}
      assert metadata.method_name == "__call__"
      assert metadata.args == %{question: "Why is the sky blue?"}
      
      assert_receive {:telemetry_event, [:dspex, :bridge, :call_method, :stop], 
                      measurements, metadata}
      assert measurements.duration > 0
      assert metadata.success == true
    end
    
    test "basic session management works" do
      # Session manager should be started automatically
      session1 = SnakepitGrpcBridge.Session.Manager.get_or_create("test-session-1")
      assert %SnakepitGrpcBridge.Session.Manager.Session{} = session1
      assert session1.id == "test-session-1"
      assert %DateTime{} = session1.created_at
      
      # Getting same session returns same instance
      session2 = SnakepitGrpcBridge.Session.Manager.get_or_create("test-session-1")
      assert session1 == session2
      
      # Different session ID creates new session
      session3 = SnakepitGrpcBridge.Session.Manager.get_or_create("test-session-2")
      assert session3.id == "test-session-2"
      assert session3.created_at != session1.created_at
    end
    
    test "success criteria example from vertical slice plan passes" do
      # This test implements the exact success criteria from the migration plan
      predictor = Predict.new("question -> answer")
      {:ok, result} = Predict.call(predictor, %{question: "What is 2+2?"})
      assert result.answer == "4"
    end
    
    test "backward compatibility is maintained" do
      # Old API with deprecation warnings
      assert capture_io(:stderr, fn ->
        {:ok, predictor} = Predict.new("question -> answer")
        {:ok, result} = Predict.execute(predictor, %{question: "What is AI?"})
        assert %Prediction{} = result
        assert is_binary(result.answer)
      end) =~ "deprecated"
    end
    
    test "one-shot prediction works" do
      {:ok, result} = Predict.call(
        %{signature: "question -> answer"}, 
        %{question: "What is the capital of France?"}
      )
      
      assert %Prediction{} = result
      assert result.answer =~ ~r/Paris/i
    end
    
    test "parameter validation works" do
      # Missing required parameter
      assert {:error, "Missing required parameter: signature"} = 
        Predict.create(%{})
      
      # Invalid parameter type
      assert {:error, _} = 
        Predict.create(%{signature: 123})
    end
    
    test "result transformation to typed struct works" do
      {:ok, predictor} = Predict.create(%{signature: "question -> answer"})
      {:ok, result} = Predict.predict(predictor, %{question: "Explain quantum physics"})
      
      # Verify all fields of Prediction struct
      assert %Prediction{
        answer: answer,
        confidence: confidence,
        reasoning: reasoning,
        metadata: metadata
      } = result
      
      assert is_binary(answer)
      assert is_nil(confidence) or is_float(confidence)
      assert is_nil(reasoning) or is_binary(reasoning)
      assert is_map(metadata)
    end
  end
  
  # Helper to capture IO output
  defp capture_io(device, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end