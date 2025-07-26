defmodule DSPex.React do
  @moduledoc """
  High-level wrapper for ReAct (Reasoning and Acting) functionality.
  
  This module provides a simplified API for ReAct operations,
  combining reasoning with tool usage in an iterative loop.
  
  ## Examples
  
      # Create tools
      search_tool = DSPex.React.make_tool("search", "Search the web", &search/1)
      calc_tool = DSPex.React.make_tool("calculator", "Do math", &calculate/1)
      
      # Simple usage
      {:ok, result} = DSPex.React.solve(
        "What is the population of Tokyo multiplied by 2?",
        tools: [search_tool, calc_tool],
        max_iterations: 5
      )
      
      # With session
      {:ok, session} = DSPex.Session.new()
      {:ok, agent} = DSPex.React.new(
        "question -> thought, action, observation, answer",
        tools: [search_tool, calc_tool],
        session: session
      )
      {:ok, result} = DSPex.React.execute(agent, %{
        question: "Find the GDP of France and calculate 5% of it"
      })
      
      # Access iterations
      Enum.each(result.iterations, fn iteration ->
        IO.puts("Thought: #{iteration.thought}")
        IO.puts("Action: #{iteration.action}")
        IO.puts("Observation: #{iteration.observation}")
      end)
  """
  
  alias DSPex.Modules.ContractBased.React, as: ContractImpl
  
  @doc """
  Create a new ReAct instance.
  
  ## Options
  
  - `:tools` - List of tools available to the agent
  - `:session` - DSPex.Session to use for this instance
  - `:max_iterations` - Maximum reasoning iterations (default: 5)
  - `:early_stop` - Stop when answer is found (default: true)
  - `:temperature` - LLM temperature setting (default: 0.7)
  """
  defdelegate new(signature, opts \\ []), to: ContractImpl
  
  @doc """
  Execute the ReAct reasoning loop.
  
  Takes an instance created with `new/2` and input parameters.
  """
  defdelegate execute(agent_ref, inputs, opts \\ []), to: ContractImpl
  
  @doc """
  Create a ReAct instance (contract-based API).
  
  ## Parameters
  
  - `params` - Map with `:signature`, `:tools`, and optional configuration
  - `opts` - Additional options
  """
  defdelegate create(params, opts \\ []), to: ContractImpl
  
  @doc """
  Execute reasoning and acting (contract-based API).
  
  Takes an instance and input parameters.
  """
  defdelegate react(agent_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  One-shot ReAct problem solving.
  
  Combines creation and execution in a single call.
  
  ## Examples
  
      {:ok, result} = DSPex.React.solve(
        "What is the weather in Paris and how does it compare to London?",
        tools: [weather_tool, comparison_tool],
        max_iterations: 3
      )
  """
  def solve(input, opts \\ []) when is_binary(input) do
    signature = opts[:signature] || "question -> thought, action, observation, answer"
    
    create_params = %{
      signature: signature,
      tools: opts[:tools] || [],
      max_iterations: opts[:max_iterations],
      early_stop: opts[:early_stop],
      temperature: opts[:temperature]
    }
    
    react_params = case String.split(signature, " -> ") do
      [inputs, _outputs] ->
        [field | _] = String.split(inputs, ", ")
        %{String.to_atom(String.trim(field)) => input}
      _ ->
        %{question: input}
    end
    
    ContractImpl.call(create_params, react_params, opts)
  end
  
  @doc """
  Create and execute in one call.
  """
  defdelegate call(create_params, react_params, opts \\ []), to: ContractImpl
  
  @doc """
  Add a tool to an existing ReAct instance.
  """
  defdelegate add_tool(agent_ref, tool, opts \\ []), to: ContractImpl
  
  @doc """
  Remove a tool by name.
  """
  defdelegate remove_tool(agent_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  List all available tools.
  """
  defdelegate list_tools(agent_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Get the iteration history from the last execution.
  """
  defdelegate get_history(agent_ref, opts \\ []), to: ContractImpl
  
  @doc """
  Get detailed iterations from the last execution.
  """
  defdelegate get_iterations(agent_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Execute a single step manually.
  
  Useful for debugging or custom control flow.
  """
  defdelegate step(agent_ref, current_state, opts \\ []), to: ContractImpl
  
  @doc """
  Create a tool from a function.
  
  ## Examples
  
      tool = DSPex.React.make_tool(
        "weather",
        "Get weather for a location",
        fn location -> {:ok, "Sunny, 22°C in #{location}"} end
      )
  """
  defdelegate make_tool(name, description, function), to: ContractImpl
  
  @doc """
  Compile the ReAct module with an optimizer.
  
  ## Examples
  
      {:ok, compiled} = DSPex.React.compile(agent,
        optimizer: "BootstrapFewShotWithRandomSearch",
        trainset: training_examples
      )
  """
  defdelegate compile(agent_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Reset the module state.
  """
  defdelegate reset(agent_ref, params \\ %{}, opts \\ []), to: ContractImpl
  
  @doc """
  Forward pass with raw parameters.
  """
  defdelegate forward(agent_ref, params, opts \\ []), to: ContractImpl
  
  @doc """
  Set a custom stopping condition.
  """
  defdelegate set_stopping_condition(agent_ref, condition_fn, opts \\ []), to: ContractImpl
  
  @doc """
  Set timeout for each iteration.
  """
  defdelegate set_timeout(agent_ref, timeout_ms, opts \\ []), to: ContractImpl
  
  @doc """
  Apply custom iteration transformation.
  """
  defdelegate with_iteration_transform(agent_ref, transform_fn, opts \\ []), to: ContractImpl
end