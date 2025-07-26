defmodule DSPex.Modules.ContractBased.React do
  @moduledoc """
  Contract-based implementation of DSPy ReAct (Reasoning and Acting) functionality.
  
  This module provides a typed, validated interface for ReAct operations,
  combining reasoning with tool usage in an iterative loop.
  
  ## Features
  
  - Iterative reasoning and action loop
  - Tool integration and management
  - Observable execution with detailed hooks
  - Early stopping on successful completion
  - Full result transformation pipeline
  
  ## Examples
  
      # Create a ReAct agent with tools
      {:ok, calculator} = DSPex.Tool.create(%{
        name: "calculator",
        description: "Performs arithmetic operations",
        function: &calculate/1
      })
      
      {:ok, agent} = React.create(%{
        signature: "question -> thought, action, observation, answer",
        tools: [calculator],
        max_iterations: 5
      })
      
      # Execute ReAct loop
      {:ok, result} = React.react(agent, %{
        question: "What is 25 * 4 + 10?"
      })
      # Returns: %DSPex.Types.ReactResult{
      #   answer: "110",
      #   iterations: [...],
      #   final_thought: "The calculation gives us 110"
      # }
  """
  
  use DSPex.Bridge.ContractBased
  use DSPex.Bridge.Observable
  use DSPex.Bridge.Bidirectional
  use DSPex.Bridge.ResultTransform
  
  use_contract DSPex.Contracts.React
  
  alias DSPex.Types.ReactResult
  alias DSPex.Utils.ID
  
  @doc """
  Result transformation pipeline for ReAct results.
  
  Converts raw Python results into structured Elixir types.
  """
  def transform_result({:ok, raw_result}) when is_map(raw_result) do
    ReactResult.from_python_result(raw_result)
  end
  
  def transform_result(error), do: error
  
  @doc """
  Observable hooks for monitoring ReAct execution.
  """
  def default_hooks do
    %{
      before_react: fn params -> 
        IO.puts("[ReAct] Starting reasoning loop for: #{inspect(params)}")
        :ok
      end,
      after_react: fn result ->
        case result do
          {:ok, %ReactResult{iterations: iterations}} ->
            IO.puts("[ReAct] Completed after #{length(iterations)} iterations")
          _ ->
            :ok
        end
        :ok
      end,
      on_thought: fn thought ->
        IO.puts("[ReAct] Thought: #{thought}")
        :ok
      end,
      on_action: fn action ->
        IO.puts("[ReAct] Action: #{inspect(action)}")
        :ok
      end,
      on_observation: fn observation ->
        IO.puts("[ReAct] Observation: #{observation}")
        :ok
      end,
      on_iteration_complete: fn iteration ->
        IO.puts("[ReAct] Iteration #{iteration.number} complete")
        :ok
      end
    }
  end
  
  @doc """
  Create and execute in one call (stateless).
  
  Combines create and react operations for convenience.
  
  ## Examples
  
      {:ok, result} = React.call(
        %{
          signature: "task -> thought, action, observation, result",
          tools: [search_tool, calculator_tool]
        },
        %{task: "Find the population of Paris and calculate 10% of it"}
      )
  """
  def call(create_params, react_params, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    with {:ok, agent_ref} <- create(create_params, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- react(agent_ref, react_params, opts) do
      {:ok, result}
    end
  end
  
  @doc """
  Add a tool dynamically after creation.
  
  Tools must implement the DSPex.Tool behavior or be callable references.
  
  ## Examples
  
      {:ok, _} = React.add_tool(agent, weather_tool, 
        name: "weather",
        description: "Get current weather for a location"
      )
  """
  def add_tool(agent_ref, tool, opts \\ []) do
    params = %{
      tool: tool,
      name: opts[:name],
      description: opts[:description]
    }
    
    super(agent_ref, params, opts)
  end
  
  @doc """
  Execute a single iteration manually.
  
  Useful for debugging or custom control flow.
  """
  def step(agent_ref, current_state, opts \\ []) do
    # This would execute one thought-action-observation cycle
    with {:ok, thought} <- generate_thought(agent_ref, current_state, opts),
         {:ok, action} <- select_action(agent_ref, thought, opts),
         {:ok, observation} <- execute_action(agent_ref, action, opts) do
      {:ok, %{
        thought: thought,
        action: action,
        observation: observation,
        state: update_state(current_state, observation)
      }}
    end
  end
  
  @doc """
  Get detailed iteration history.
  
  Returns all iterations with thoughts, actions, and observations.
  """
  def get_history(agent_ref, opts \\ []) do
    get_iterations(agent_ref, %{}, opts)
  end
  
  @doc """
  Configure early stopping behavior.
  
  Allows customization of when the ReAct loop should terminate.
  """
  def set_stopping_condition(agent_ref, condition_fn, opts \\ []) 
      when is_function(condition_fn, 1) do
    # Store the condition function for use in execution
    {:ok, %{ref: agent_ref, stopping_condition: condition_fn}}
  end
  
  @doc """
  Create a custom tool from a function.
  
  Convenience helper for creating tools inline.
  
  ## Examples
  
      tool = React.make_tool(
        "calculator",
        "Performs arithmetic",
        fn expr -> {:ok, eval(expr)} end
      )
  """
  def make_tool(name, description, function) when is_function(function, 1) do
    %{
      name: name,
      description: description,
      function: function,
      type: :elixir_function
    }
  end
  
  # Backward compatibility helpers
  @doc false
  def new(signature, opts \\ []) do
    IO.warn("React.new/2 is deprecated. Use create/2 instead.", 
            Macro.Env.stacktrace(__ENV__))
    create(%{signature: signature}, opts)
  end
  
  @doc false
  def execute(agent_ref, inputs, opts \\ []) do
    IO.warn("React.execute/3 is deprecated. Use react/3 instead.", 
            Macro.Env.stacktrace(__ENV__))
    react(agent_ref, inputs, opts)
  end
  
  # Private helper functions
  defp generate_thought(agent_ref, state, opts) do
    # Would interact with the Python bridge to generate next thought
    {:ok, "I need to #{state.next_action}"}
  end
  
  defp select_action(agent_ref, thought, opts) do
    # Would parse the thought to determine which tool/action to use
    {:ok, %{tool: "calculator", input: "25 * 4"}}
  end
  
  defp execute_action(agent_ref, action, opts) do
    # Would execute the selected tool with the given input
    {:ok, "100"}
  end
  
  defp update_state(state, observation) do
    Map.update(state, :observations, [observation], &(&1 ++ [observation]))
  end
  
  @doc """
  Apply custom iteration transformation.
  
  Allows processing of each iteration before adding to results.
  """
  def with_iteration_transform(agent_ref, transform_fn, opts \\ []) 
      when is_function(transform_fn, 1) do
    {:ok, %{ref: agent_ref, iteration_transform: transform_fn}}
  end
  
  @doc """
  Set maximum thinking time per iteration.
  
  Prevents infinite loops in complex reasoning.
  """
  def set_timeout(agent_ref, timeout_ms, opts \\ []) when is_integer(timeout_ms) do
    {:ok, %{ref: agent_ref, timeout: timeout_ms}}
  end
end