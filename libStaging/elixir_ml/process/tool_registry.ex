defmodule ElixirML.Process.ToolRegistry do
  @moduledoc """
  Registry for ML tools and utilities.
  Manages tool discovery, registration, and lifecycle.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    state = %{
      tools: %{},
      tool_categories: %{},
      usage_stats: %{}
    }

    # Register built-in tools
    register_builtin_tools(state)
  end

  @doc """
  Register a new tool.
  """
  def register_tool(tool_name, tool_module, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_tool, tool_name, tool_module, metadata})
  end

  @doc """
  Get a registered tool.
  """
  def get_tool(tool_name) do
    GenServer.call(__MODULE__, {:get_tool, tool_name})
  end

  @doc """
  List all registered tools.
  """
  def list_tools(category \\ :all) do
    GenServer.call(__MODULE__, {:list_tools, category})
  end

  @doc """
  Get tool usage statistics.
  """
  def tool_stats do
    GenServer.call(__MODULE__, :tool_stats)
  end

  # Server callbacks

  def handle_call({:register_tool, tool_name, tool_module, metadata}, _from, state) do
    tool_info = %{
      module: tool_module,
      metadata: metadata,
      registered_at: System.monotonic_time(:millisecond),
      usage_count: 0
    }

    tools = Map.put(state.tools, tool_name, tool_info)

    # Update category mapping
    category = Map.get(metadata, :category, :general)
    category_tools = Map.get(state.tool_categories, category, [])
    tool_categories = Map.put(state.tool_categories, category, [tool_name | category_tools])

    new_state = %{state | tools: tools, tool_categories: tool_categories}

    {:reply, {:ok, tool_name}, new_state}
  end

  def handle_call({:get_tool, tool_name}, _from, state) do
    case Map.get(state.tools, tool_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tool_info ->
        # Update usage stats
        updated_tool = %{tool_info | usage_count: tool_info.usage_count + 1}
        tools = Map.put(state.tools, tool_name, updated_tool)

        usage_stats = Map.update(state.usage_stats, tool_name, 1, &(&1 + 1))

        new_state = %{state | tools: tools, usage_stats: usage_stats}

        {:reply, {:ok, tool_info.module}, new_state}
    end
  end

  def handle_call({:list_tools, category}, _from, state) do
    tools =
      case category do
        :all ->
          state.tools
          |> Enum.map(fn {name, info} ->
            %{name: name, module: info.module, metadata: info.metadata}
          end)

        specific_category ->
          tool_names = Map.get(state.tool_categories, specific_category, [])

          Enum.map(tool_names, fn name ->
            info = state.tools[name]
            %{name: name, module: info.module, metadata: info.metadata}
          end)
      end

    {:reply, tools, state}
  end

  def handle_call(:tool_stats, _from, state) do
    stats = %{
      total_tools: map_size(state.tools),
      categories: map_size(state.tool_categories),
      usage_stats: state.usage_stats,
      most_used_tool: find_most_used_tool(state.usage_stats),
      category_breakdown: calculate_category_breakdown(state.tool_categories)
    }

    {:reply, stats, state}
  end

  # Private functions

  defp register_builtin_tools(state) do
    builtin_tools = [
      {:schema_validator, ElixirML.Schema.Validator, %{category: :validation}},
      {:variable_optimizer, ElixirML.Variable.Optimizer, %{category: :optimization}},
      {:pipeline_executor, ElixirML.Process.Pipeline, %{category: :execution}},
      {:resource_manager, ElixirML.Process.ResourceManager, %{category: :management}}
    ]

    tools =
      Enum.reduce(builtin_tools, %{}, fn {name, module, metadata}, acc ->
        tool_info = %{
          module: module,
          metadata: metadata,
          registered_at: System.monotonic_time(:millisecond),
          usage_count: 0
        }

        Map.put(acc, name, tool_info)
      end)

    tool_categories =
      Enum.reduce(builtin_tools, %{}, fn {name, _module, metadata}, acc ->
        category = Map.get(metadata, :category, :general)
        category_tools = Map.get(acc, category, [])
        Map.put(acc, category, [name | category_tools])
      end)

    {:ok, %{state | tools: tools, tool_categories: tool_categories}}
  end

  defp find_most_used_tool(usage_stats) do
    case Enum.max_by(usage_stats, fn {_name, count} -> count end, fn -> nil end) do
      nil -> nil
      {name, count} -> %{name: name, usage_count: count}
    end
  end

  defp calculate_category_breakdown(tool_categories) do
    Enum.map(tool_categories, fn {category, tools} ->
      %{category: category, tool_count: length(tools)}
    end)
  end
end
