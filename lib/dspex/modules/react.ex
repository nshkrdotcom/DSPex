defmodule DSPex.Modules.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) module.

  Combines reasoning with tool usage. The model thinks about what to do,
  acts by calling tools, observes the results, and continues until done.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new ReAct module instance with tools.

  ## Examples

      tools = [
        %{
          name: "search",
          description: "Search the web for information",
          func: &MyApp.search/1
        },
        %{
          name: "calculate", 
          description: "Perform mathematical calculations",
          func: &MyApp.calculate/1
        }
      ]
      
      {:ok, react} = DSPex.Modules.ReAct.create("question -> answer", tools)
      {:ok, result} = DSPex.Modules.ReAct.execute(react, %{question: "What is 2+2?"})
  """
  def create(signature, tools \\ [], opts \\ []) do
    id = opts[:store_as] || ID.generate("react")

    # Convert Elixir function references to Python-compatible format
    python_tools = prepare_tools(tools)

    case Snakepit.Python.call(
           "dspy.ReAct",
           %{signature: signature, tools: python_tools},
           Keyword.merge([store_as: id], opts)
         ) do
      {:ok, _} -> {:ok, id}
      error -> error
    end
  end

  @doc """
  Execute ReAct reasoning with the given inputs.
  """
  def execute(react_id, inputs, opts \\ []) do
    Snakepit.Python.call("stored.#{react_id}.__call__", inputs, opts)
  end

  @doc """
  Create and execute in one call (stateless).
  """
  def reason_and_act(signature, inputs, tools \\ [], opts \\ []) do
    with {:ok, id} <-
           create(signature, tools, Keyword.put(opts, :session_id, ID.generate("session"))),
         {:ok, result} <- execute(id, inputs, opts) do
      {:ok, result}
    end
  end

  defp prepare_tools(tools) do
    # For now, tools need to be registered on Python side
    # This is a placeholder for future tool bridge implementation
    Enum.map(tools, fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        # Tool functions will need special handling via bridge
        func_id: register_tool_function(tool.func)
      }
    end)
  end

  defp register_tool_function(_func) do
    # TODO: Implement tool function registration bridge
    "placeholder_tool_id"
  end
end
