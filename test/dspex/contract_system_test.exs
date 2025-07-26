defmodule DSPex.ContractSystemTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Contracts.Predict
  alias DSPex.Types.Prediction
  
  describe "Contract infrastructure" do
    test "contract module defines proper behavior" do
      # Contract should implement the behavior
      assert function_exported?(Predict, :contract_version, 0)
      assert function_exported?(Predict, :python_class, 0)
      assert function_exported?(Predict, :__methods__, 0)
      
      # Check contract version
      assert Predict.contract_version() == "1.0.0"
      
      # Check python class
      assert Predict.python_class() == "dspy.Predict"
      
      # Check methods are defined
      methods = Predict.__methods__()
      assert length(methods) == 7  # create, predict, forward, batch_forward, compile, inspect_signature, reset
      
      # Verify create method
      {_, create_method} = Enum.find(methods, fn {name, _} -> name == :create end)
      assert create_method.python_name == :__init__
      assert Keyword.get(create_method.params, :signature) == {:required, :string}
      assert create_method.returns == :reference
      
      # Verify predict method
      {_, predict_method} = Enum.find(methods, fn {name, _} -> name == :predict end)
      assert predict_method.python_name == :__call__
      assert predict_method.params == :variable_keyword
      assert predict_method.returns == {:struct, DSPex.Types.Prediction}
    end
  end
  
  describe "Type system" do
    test "Prediction type validates Python results correctly" do
      # Valid result with all fields
      {:ok, prediction} = Prediction.from_python_result(%{
        "answer" => "42",
        "confidence" => 0.95,
        "reasoning" => "The answer is 42 because...",
        "extra_field" => "gets stored in metadata"
      })
      
      assert prediction.answer == "42"
      assert prediction.confidence == 0.95
      assert prediction.reasoning == "The answer is 42 because..."
      assert prediction.metadata == %{"extra_field" => "gets stored in metadata"}
      
      # Valid result with minimal fields
      {:ok, minimal} = Prediction.from_python_result(%{"answer" => "minimal"})
      assert minimal.answer == "minimal"
      assert minimal.confidence == nil
      assert minimal.reasoning == nil
      assert minimal.metadata == %{}
      
      # Handle rationale as reasoning
      {:ok, with_rationale} = Prediction.from_python_result(%{
        "answer" => "test",
        "rationale" => "alternative reasoning field"
      })
      assert with_rationale.reasoning == "alternative reasoning field"
      
      # Invalid result - missing answer
      assert {:error, :invalid_prediction_format} = 
        Prediction.from_python_result(%{"confidence" => 0.5})
    end
    
    test "type coercion works correctly" do
      # Integer confidence gets converted to float
      {:ok, prediction} = Prediction.from_python_result(%{
        "answer" => "test",
        "confidence" => 1
      })
      assert prediction.confidence == 1.0
      assert is_float(prediction.confidence)
      
      # Non-string answer gets converted
      {:ok, number_answer} = Prediction.from_python_result(%{
        "answer" => 42
      })
      assert number_answer.answer == "42"
    end
  end
  
  describe "Three-layer architecture separation" do
    test "DSPex layer only uses contracts, not implementation details" do
      # The DSPex.Predict module should only reference contracts
      # and not have any direct Python/bridge implementation
      source = File.read!("lib/dspex/predict.ex")
      
      # Should use contract
      assert source =~ "use_contract DSPex.Contracts.Predict"
      
      # Should NOT contain direct Python calls
      refute source =~ "call_dspy"
      refute source =~ "__init__"
      refute source =~ "__call__"
      refute source =~ "dspy.Predict"
    end
    
    test "Contract layer is pure specification without implementation" do
      # Contracts should only define interfaces
      source = File.read!("lib/dspex/contracts/predict.ex")
      
      # Should define methods
      assert source =~ "defmethod"
      
      # Should NOT contain implementation
      refute source =~ "GenServer"
      refute source =~ "Snakepit"
      refute source =~ "execute_in_session"
    end
    
    test "Bridge layer handles all implementation details" do
      # Bridge should contain actual implementation
      source = File.read!("lib/dspex/bridge.ex")
      
      # Should have implementation details
      assert source =~ "Snakepit"
      assert source =~ "execute_in_session"
      assert source =~ "call_dspy"
    end
  end
  
  describe "Telemetry observability" do
    setup do
      events_agent = start_supervised!({Agent, fn -> [] end})
      
      handler_id = "contract-test-handler-#{System.unique_integer()}"
      
      :telemetry.attach(
        handler_id,
        [:dspex, :bridge, :create_instance, :stop],
        fn event, measurements, metadata, _config ->
          Agent.update(events_agent, fn events ->
            [{event, measurements, metadata} | events]
          end)
        end,
        nil
      )
      
      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)
      
      {:ok, events_agent: events_agent}
    end
    
    @tag :integration
    test "telemetry includes contract information", %{events_agent: events_agent} do
      {:ok, _predictor} = DSPex.Predict.create(%{signature: "q -> a"})
      
      # Give telemetry time to process
      Process.sleep(50)
      
      events = Agent.get(events_agent, & &1)
      assert length(events) > 0
      
      {_event, measurements, metadata} = hd(events)
      
      # Check measurements
      assert measurements.duration > 0
      
      # Check metadata
      assert metadata.python_class == "dspy.Predict"
      assert metadata.args == %{signature: "q -> a"}
      assert metadata.success == true
    end
  end
end