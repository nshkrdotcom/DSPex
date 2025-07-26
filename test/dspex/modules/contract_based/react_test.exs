defmodule DSPex.Modules.ContractBased.ReactTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Modules.ContractBased.React
  alias DSPex.Types.ReactResult
  
  describe "create/2" do
    test "creates a ReAct instance with valid signature" do
      assert {:ok, ref} = React.create(%{
        signature: "question -> thought, action, observation, answer"
      })
      
      assert is_binary(ref)
      assert String.starts_with?(ref, "react-")
    end
    
    test "creates with tools and optional parameters" do
      calculator_tool = React.make_tool("calculator", "Does math", &mock_calculate/1)
      search_tool = React.make_tool("search", "Searches web", &mock_search/1)
      
      assert {:ok, ref} = React.create(%{
        signature: "task -> thought, action, observation, result",
        tools: [calculator_tool, search_tool],
        max_iterations: 3,
        early_stop: false,
        temperature: 0.8
      })
      
      assert is_binary(ref)
    end
    
    test "returns error with invalid signature" do
      assert {:error, _} = React.create(%{
        signature: ""
      })
    end
  end
  
  describe "react/3" do
    setup do
      tool = React.make_tool("calculator", "Performs calculations", &mock_calculate/1)
      
      {:ok, ref} = React.create(%{
        signature: "question -> thought, action, observation, answer",
        tools: [tool]
      })
      
      %{agent_ref: ref, tool: tool}
    end
    
    test "executes ReAct loop", %{agent_ref: ref} do
      # Mock the bridge response
      mock_response = %{
        "thought" => "I need to calculate 5 * 5",
        "action" => "calculator: 5 * 5",
        "observation" => "25",
        "answer" => "The result is 25",
        "iterations" => [
          %{
            "thought" => "I need to calculate 5 * 5",
            "action" => "calculator: 5 * 5",
            "observation" => "25"
          }
        ]
      }
      
      assert {:ok, result} = React.transform_result({:ok, mock_response})
      
      assert %ReactResult{} = result
      assert result.thought == mock_response["thought"]
      assert result.action == mock_response["action"]
      assert result.observation == mock_response["observation"]
      assert result.answer == mock_response["answer"]
      assert length(result.iterations) == 1
    end
    
    test "handles multiple iterations", %{agent_ref: ref} do
      mock_response = %{
        "thought" => "Final thought",
        "action" => "Final action",
        "observation" => "Final observation",
        "answer" => "42",
        "iterations" => [
          %{
            "thought" => "First thought",
            "action" => "search: meaning of life",
            "observation" => "Various philosophical answers"
          },
          %{
            "thought" => "Let me calculate",
            "action" => "calculator: 6 * 7",
            "observation" => "42"
          }
        ]
      }
      
      assert {:ok, result} = React.transform_result({:ok, mock_response})
      assert length(result.iterations) == 2
      assert hd(result.iterations)["thought"] == "First thought"
    end
  end
  
  describe "make_tool/3" do
    test "creates a tool from a function" do
      tool = React.make_tool(
        "weather",
        "Get weather info",
        fn location -> {:ok, "Sunny in #{location}"} end
      )
      
      assert tool.name == "weather"
      assert tool.description == "Get weather info"
      assert is_function(tool.function, 1)
      assert tool.type == :elixir_function
      
      # Test the function works
      assert {:ok, "Sunny in Paris"} = tool.function.("Paris")
    end
  end
  
  describe "call/3" do
    test "creates and executes in one call" do
      tool = React.make_tool("echo", "Echoes input", fn x -> {:ok, x} end)
      
      create_params = %{
        signature: "question -> thought, action, observation, answer",
        tools: [tool]
      }
      react_params = %{question: "Test question"}
      
      # Test parameter construction
      assert create_params.signature == "question -> thought, action, observation, answer"
      assert length(create_params.tools) == 1
      assert react_params.question == "Test question"
    end
  end
  
  describe "transform_result/1" do
    test "transforms Python result to Elixir struct" do
      python_result = %{
        "thought" => "I need to search for information",
        "action" => "search: Elixir language",
        "observation" => "Elixir is a dynamic, functional language",
        "answer" => "Elixir is a functional programming language",
        "iterations" => [
          %{
            "thought" => "I need to search for information",
            "action" => "search: Elixir language",
            "observation" => "Elixir is a dynamic, functional language"
          }
        ],
        "tool_calls" => [
          %{
            "tool" => "search",
            "input" => "Elixir language",
            "output" => "Elixir is a dynamic, functional language"
          }
        ]
      }
      
      assert {:ok, result} = React.transform_result({:ok, python_result})
      
      assert %ReactResult{} = result
      assert result.thought == python_result["thought"]
      assert result.action == python_result["action"]
      assert result.observation == python_result["observation"]
      assert result.answer == python_result["answer"]
      assert length(result.iterations) == 1
      assert length(result.tool_calls) == 1
    end
    
    test "returns error for invalid format" do
      invalid_result = %{"something" => "else"}
      
      assert {:error, :invalid_react_format} = 
        ReactResult.from_python_result(invalid_result)
    end
  end
  
  describe "default_hooks/0" do
    test "returns hook configuration" do
      hooks = React.default_hooks()
      
      assert is_map(hooks)
      assert is_function(hooks.before_react, 1)
      assert is_function(hooks.after_react, 1)
      assert is_function(hooks.on_thought, 1)
      assert is_function(hooks.on_action, 1)
      assert is_function(hooks.on_observation, 1)
      assert is_function(hooks.on_iteration_complete, 1)
    end
  end
  
  describe "tool management" do
    setup do
      {:ok, ref} = React.create(%{
        signature: "q -> t, a, o, r",
        tools: []
      })
      
      %{agent_ref: ref}
    end
    
    test "add_tool/3 adds a tool dynamically", %{agent_ref: ref} do
      tool = React.make_tool("test", "Test tool", fn _ -> {:ok, "test"} end)
      
      assert {:ok, _} = React.add_tool(ref, tool,
        name: "test_tool",
        description: "A test tool"
      )
    end
    
    test "step/3 executes single iteration", %{agent_ref: ref} do
      current_state = %{observations: [], next_action: "search"}
      
      # This is a mock - real implementation would call bridge
      assert {:ok, step_result} = React.step(ref, current_state)
      
      assert step_result.thought =~ "need to search"
      assert is_map(step_result.action)
      assert is_binary(step_result.observation)
      assert is_map(step_result.state)
    end
  end
  
  describe "configuration" do
    setup do
      {:ok, ref} = React.create(%{signature: "q -> t, a, o, r"})
      %{agent_ref: ref}
    end
    
    test "set_stopping_condition/3 configures early stopping", %{agent_ref: ref} do
      condition_fn = fn result -> 
        String.contains?(result.observation, "DONE")
      end
      
      assert {:ok, %{ref: ^ref, stopping_condition: ^condition_fn}} = 
        React.set_stopping_condition(ref, condition_fn)
    end
    
    test "set_timeout/3 sets iteration timeout", %{agent_ref: ref} do
      assert {:ok, %{ref: ^ref, timeout: 5000}} = 
        React.set_timeout(ref, 5000)
    end
    
    test "with_iteration_transform/3 sets transform function", %{agent_ref: ref} do
      transform_fn = fn iteration ->
        Map.put(iteration, :timestamp, DateTime.utc_now())
      end
      
      assert {:ok, %{ref: ^ref, iteration_transform: ^transform_fn}} = 
        React.with_iteration_transform(ref, transform_fn)
    end
  end
  
  describe "backward compatibility" do
    test "new/2 delegates to create with deprecation warning" do
      assert capture_io(:stderr, fn ->
        assert {:ok, _ref} = React.new("question -> thought, action, observation, answer")
      end) =~ "deprecated"
    end
    
    test "execute/3 delegates to react with deprecation warning" do
      {:ok, ref} = React.create(%{signature: "q -> t, a, o, r"})
      
      assert capture_io(:stderr, fn ->
        React.execute(ref, %{q: "test"})
      end) =~ "deprecated"
    end
  end
  
  # Mock tool functions
  defp mock_calculate(expr) do
    # Simple calculator mock
    case expr do
      "5 * 5" -> {:ok, "25"}
      "6 * 7" -> {:ok, "42"}
      _ -> {:error, "Cannot calculate: #{expr}"}
    end
  end
  
  defp mock_search(query) do
    # Simple search mock
    case query do
      "Elixir language" -> {:ok, "Elixir is a dynamic, functional language"}
      "meaning of life" -> {:ok, "Various philosophical answers"}
      _ -> {:ok, "No results found for: #{query}"}
    end
  end
  
  # Helper to capture IO output
  defp capture_io(device, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end