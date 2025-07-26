defmodule DSPex.Contracts.ContractTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Contracts.{Predict, ChainOfThought, ReAct, ProgramOfThought, Retrieve}
  alias DSPex.Contracts.Types
  
  describe "contract metadata" do
    test "Predict contract has correct metadata" do
      metadata = Predict.__contract_metadata__()
      
      assert metadata.python_class == "dspy.Predict"
      assert metadata.contract_version == "1.0.0"
      assert length(metadata.methods) > 0
      
      # Check specific methods exist
      assert Predict.validate_method(:create)
      assert Predict.validate_method(:predict)
      assert Predict.validate_method(:forward)
    end
    
    test "ChainOfThought contract has correct metadata" do
      metadata = ChainOfThought.__contract_metadata__()
      
      assert metadata.python_class == "dspy.ChainOfThought"
      assert ChainOfThought.validate_method(:create)
      assert ChainOfThought.validate_method(:get_reasoning_steps)
    end
    
    test "all contracts have required methods" do
      contracts = [Predict, ChainOfThought, ReAct, ProgramOfThought, Retrieve]
      
      for contract <- contracts do
        assert contract.validate_method(:create), 
               "#{inspect(contract)} missing create method"
        assert contract.validate_method(:predict) or contract.validate_method(:retrieve),
               "#{inspect(contract)} missing execution method"
      end
    end
  end
  
  describe "method specs" do
    test "get_method_spec returns correct spec" do
      {:ok, spec} = Predict.get_method_spec(:create)
      
      assert spec.name == :create
      assert spec.python_name == :__init__
      assert spec.returns == :reference
      assert [{:signature, {:required, :string}}] = spec.params
    end
    
    test "get_method_spec returns error for unknown method" do
      assert {:error, :method_not_found} = Predict.get_method_spec(:unknown_method)
    end
  end
  
  describe "type conversion" do
    test "Prediction type conversion from Python result" do
      python_result = %{
        "answer" => "DSPy is a framework",
        "confidence" => 0.95,
        "reasoning" => "Based on documentation"
      }
      
      assert {:ok, %Types.Prediction{} = pred} = Types.Prediction.from_python_result(python_result)
      assert pred.answer == "DSPy is a framework"
      assert pred.confidence == 0.95
      assert pred.reasoning == "Based on documentation"
    end
    
    test "ChainOfThoughtResult type conversion" do
      python_result = %{
        "reasoning" => "Step 1\nStep 2\nStep 3",
        "answer" => "Final answer"
      }
      
      assert {:ok, %Types.ChainOfThoughtResult{} = cot} = 
             Types.ChainOfThoughtResult.from_python_result(python_result)
      assert cot.reasoning == ["Step 1", "Step 2", "Step 3"]
      assert cot.answer == "Final answer"
    end
    
    test "RetrieveResult with passages" do
      python_result = %{
        "passages" => [
          %{"text" => "Passage 1", "score" => 0.9},
          %{"text" => "Passage 2", "score" => 0.8}
        ],
        "query" => "test query"
      }
      
      assert {:ok, %Types.RetrieveResult{} = result} = 
             Types.RetrieveResult.from_python_result(python_result)
      assert length(result.passages) == 2
      assert result.query == "test query"
      
      [p1, p2] = result.passages
      assert p1.text == "Passage 1"
      assert p1.score == 0.9
    end
  end
end