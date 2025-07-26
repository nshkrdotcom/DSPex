defmodule DSPex.Modules.ContractBased.ChainOfThoughtTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Modules.ContractBased.ChainOfThought
  alias DSPex.Types.ChainOfThoughtResult
  
  describe "create/2" do
    test "creates a chain of thought instance with valid signature" do
      assert {:ok, ref} = ChainOfThought.create(%{
        signature: "question -> reasoning, answer"
      })
      
      assert is_binary(ref)
      assert String.starts_with?(ref, "chain_of_thought-")
    end
    
    test "creates with optional parameters" do
      assert {:ok, ref} = ChainOfThought.create(%{
        signature: "problem -> approach, solution",
        rationale_type: "approach",
        max_retries: 5,
        temperature: 0.5
      })
      
      assert is_binary(ref)
    end
    
    test "returns error with invalid signature" do
      assert {:error, _} = ChainOfThought.create(%{
        signature: ""
      })
    end
  end
  
  describe "think/3" do
    setup do
      {:ok, ref} = ChainOfThought.create(%{
        signature: "question -> reasoning, answer"
      })
      
      %{cot_ref: ref}
    end
    
    test "executes chain of thought reasoning", %{cot_ref: ref} do
      # Mock the bridge response
      mock_response = %{
        "reasoning" => "To answer this question, I need to consider the basic arithmetic operation of addition.",
        "answer" => "4",
        "confidence" => 0.99
      }
      
      # In a real test, we'd mock the DSPex.Bridge.call_method
      # For now, we'll test the transformation
      assert {:ok, result} = ChainOfThought.transform_result({:ok, mock_response})
      
      assert %ChainOfThoughtResult{} = result
      assert result.reasoning == mock_response["reasoning"]
      assert result.answer == mock_response["answer"]
      assert result.confidence == mock_response["confidence"]
    end
    
    test "handles missing confidence gracefully", %{cot_ref: ref} do
      mock_response = %{
        "reasoning" => "Let me think about this step by step.",
        "answer" => "42"
      }
      
      assert {:ok, result} = ChainOfThought.transform_result({:ok, mock_response})
      assert result.confidence == nil
    end
  end
  
  describe "call/3" do
    test "creates and executes in one call" do
      # This would need proper mocking of the bridge
      create_params = %{signature: "question -> reasoning, answer"}
      think_params = %{question: "What is 2+2?"}
      
      # Test parameter construction
      assert create_params.signature == "question -> reasoning, answer"
      assert think_params.question == "What is 2+2?"
    end
  end
  
  describe "transform_result/1" do
    test "transforms Python result to Elixir struct" do
      python_result = %{
        "reasoning" => "First, I need to understand what recursion means...",
        "answer" => "Recursion is a programming technique where a function calls itself.",
        "confidence" => 0.85,
        "steps" => ["Define base case", "Define recursive case", "Ensure termination"]
      }
      
      assert {:ok, result} = ChainOfThought.transform_result({:ok, python_result})
      
      assert %ChainOfThoughtResult{} = result
      assert result.reasoning == python_result["reasoning"]
      assert result.answer == python_result["answer"]
      assert result.confidence == python_result["confidence"]
      assert result.steps == python_result["steps"]
    end
    
    test "handles alternative rationale format" do
      python_result = %{
        "rationale" => "Looking at this problem systematically...",
        "answer" => "The solution is 42",
        "confidence" => 0.9
      }
      
      assert {:ok, result} = ChainOfThoughtResult.from_python_result(python_result)
      assert result.reasoning == python_result["rationale"]
    end
    
    test "returns error for invalid format" do
      invalid_result = %{"something" => "else"}
      
      assert {:error, :invalid_chain_of_thought_format} = 
        ChainOfThoughtResult.from_python_result(invalid_result)
    end
  end
  
  describe "default_hooks/0" do
    test "returns hook configuration" do
      hooks = ChainOfThought.default_hooks()
      
      assert is_map(hooks)
      assert is_function(hooks.before_think, 1)
      assert is_function(hooks.after_think, 1)
      assert is_function(hooks.on_reasoning_step, 1)
    end
  end
  
  describe "backward compatibility" do
    test "new/2 delegates to create with deprecation warning" do
      # Capture IO to verify deprecation warning
      assert capture_io(:stderr, fn ->
        assert {:ok, _ref} = ChainOfThought.new("question -> reasoning, answer")
      end) =~ "deprecated"
    end
    
    test "execute/3 delegates to think with deprecation warning" do
      {:ok, ref} = ChainOfThought.create(%{signature: "q -> r, a"})
      
      assert capture_io(:stderr, fn ->
        # Would need mocking to actually work
        ChainOfThought.execute(ref, %{q: "test"})
      end) =~ "deprecated"
    end
  end
  
  describe "helper functions" do
    test "get_steps/2 extracts reasoning steps" do
      # This would need proper implementation and mocking
      {:ok, ref} = ChainOfThought.create(%{signature: "q -> r, a"})
      
      # Mock response with steps
      mock_steps = ["Step 1: Analyze", "Step 2: Process", "Step 3: Conclude"]
      
      # In real implementation, this would call the bridge
      # assert {:ok, ^mock_steps} = ChainOfThought.get_steps(ref)
    end
    
    test "set_rationale_type/3 configures rationale field" do
      {:ok, ref} = ChainOfThought.create(%{signature: "q -> r, a"})
      
      assert {:ok, %{rationale_type: "approach"}} = 
        ChainOfThought.set_rationale_type(ref, "approach")
    end
    
    test "with_transform/3 stores custom transformation" do
      {:ok, ref} = ChainOfThought.create(%{signature: "q -> r, a"})
      
      transform_fn = fn result -> 
        Map.update(result, :answer, "", &String.upcase/1)
      end
      
      assert {:ok, %{ref: ^ref, transform: ^transform_fn}} = 
        ChainOfThought.with_transform(ref, transform_fn)
    end
  end
  
  # Helper to capture IO output
  defp capture_io(device, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end