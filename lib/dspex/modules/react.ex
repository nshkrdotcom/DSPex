defmodule DSPex.Modules.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) module.

  Combines reasoning with tool usage. The model thinks about what to do,
  acts by calling tools, observes the results, and continues until done.

  Migrated to Snakepit v0.4.3 API (execute_in_session).

  Note: Tool registration with Elixir functions requires bidirectional
  tool support and is currently not fully implemented.
  """

  alias DSPex.Utils.ID

  @doc """
  Create a new ReAct module instance with tools.

  Note: Currently not implemented as it requires tool function registration.
  Use DSPy's built-in tools or implement tools on the Python side.

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
  """
  def create(_signature, _tools \\ [], _opts \\ []) do
    # ReAct with Elixir tool functions needs bidirectional tool support
    # to register the tool functions on the Python side
    {:error, :not_implemented}
  end

  @doc """
  Execute ReAct reasoning with the given inputs.

  Note: Currently not implemented. See create/3.
  """
  def execute(_react_id, _inputs, _opts \\ []) do
    {:error, :not_implemented}
  end

  @doc """
  Create and execute in one call (stateless).

  Note: Currently not implemented. See create/3.
  """
  def reason_and_act(_signature, _inputs, _tools \\ [], _opts \\ []) do
    {:error, :not_implemented}
  end
end
