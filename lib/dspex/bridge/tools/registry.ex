defmodule DSPex.Bridge.Tools.Registry do
  @moduledoc """
  Registry for bidirectional tools that can be called from Python.
  
  This GenServer maintains a registry of Elixir functions that can be
  invoked from Python code, enabling true bidirectional communication.
  
  ## Features
  
  - Function registration with metadata
  - Namespace support (e.g., "validation.email")
  - Hot code reloading support (stores module/function refs)
  - Thread-safe operations
  - Introspection capabilities
  
  ## Example
  
      # Register a tool
      Registry.register("validate_email", {MyApp.Validators, :email?}, %{
        description: "Validates email format",
        params: %{email: :string},
        returns: :boolean
      })
      
      # Look up and use
      {:ok, {module, function, metadata}} = Registry.lookup("validate_email")
      result = apply(module, function, [%{"email" => "test@example.com"}])
  """
  
  use GenServer
  require Logger
  
  @type tool_name :: String.t()
  @type tool_ref :: {module(), atom()}
  @type tool_metadata :: map()
  @type tool_entry :: {tool_ref, tool_metadata}
  
  # Client API
  
  @doc """
  Starts the tool registry.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Registers a tool with the given name, function reference, and metadata.
  
  The function must have arity 1 and accept a map as its argument.
  
  ## Examples
  
      Registry.register("uppercase", {String, :upcase}, %{
        description: "Converts string to uppercase"
      })
      
      Registry.register("validation.email", {MyApp.Validators, :email?}, %{
        description: "Validates email format",
        params: %{email: :string},
        returns: :boolean,
        examples: [
          %{input: %{"email" => "test@example.com"}, output: true},
          %{input: %{"email" => "invalid"}, output: false}
        ]
      })
  """
  @spec register(tool_name(), tool_ref(), tool_metadata()) :: :ok | {:error, term()}
  def register(name, {module, function} = tool_ref, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, name, tool_ref, metadata})
  end
  
  @doc """
  Unregisters a tool by name.
  """
  @spec unregister(tool_name()) :: :ok | {:error, :not_found}
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end
  
  @doc """
  Looks up a tool by name.
  
  Returns `{:ok, {module, function, metadata}}` if found, `{:error, :not_found}` otherwise.
  """
  @spec lookup(tool_name()) :: {:ok, {module(), atom(), tool_metadata()}} | {:error, :not_found}
  def lookup(name) do
    GenServer.call(__MODULE__, {:lookup, name})
  end
  
  @doc """
  Lists all registered tools.
  
  Returns a list of `{name, metadata}` tuples.
  """
  @spec list() :: [{tool_name(), tool_metadata()}]
  def list do
    GenServer.call(__MODULE__, :list)
  end
  
  @doc """
  Lists tools matching a namespace prefix.
  
  ## Example
  
      Registry.list_namespace("validation")
      # Returns all tools starting with "validation."
  """
  @spec list_namespace(String.t()) :: [{tool_name(), tool_metadata()}]
  def list_namespace(namespace) do
    GenServer.call(__MODULE__, {:list_namespace, namespace})
  end
  
  @doc """
  Executes a tool by name with the given arguments.
  
  This is a convenience function that looks up and executes in one call.
  """
  @spec execute(tool_name(), map()) :: {:ok, any()} | {:error, term()}
  def execute(name, args) when is_map(args) do
    with {:ok, {module, function, _metadata}} <- lookup(name) do
      try do
        result = apply(module, function, [args])
        {:ok, result}
      rescue
        error ->
          {:error, {:execution_failed, error}}
      end
    end
  end
  
  @doc """
  Checks if a tool exists.
  """
  @spec exists?(tool_name()) :: boolean()
  def exists?(name) do
    case lookup(name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end
  
  @doc """
  Clears all registered tools.
  
  Useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Use ETS for better concurrent reads
    table = :ets.new(:dspex_tools, [:set, :protected, :named_table])
    
    state = %{
      table: table,
      metadata_index: %{}  # Secondary index for namespace queries
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, name, {module, function} = tool_ref, metadata}, _from, state) do
    # Validate the function exists and has arity 1
    case validate_function(module, function) do
      :ok ->
        # Store in ETS
        entry = {tool_ref, metadata}
        :ets.insert(state.table, {name, entry})
        
        # Update namespace index
        new_index = update_namespace_index(state.metadata_index, name, metadata)
        
        Logger.debug("Registered tool: #{name} -> #{module}.#{function}/1")
        
        {:reply, :ok, %{state | metadata_index: new_index}}
        
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:unregister, name}, _from, state) do
    case :ets.lookup(state.table, name) do
      [{^name, _}] ->
        :ets.delete(state.table, name)
        new_index = remove_from_namespace_index(state.metadata_index, name)
        
        Logger.debug("Unregistered tool: #{name}")
        
        {:reply, :ok, %{state | metadata_index: new_index}}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:lookup, name}, _from, state) do
    case :ets.lookup(state.table, name) do
      [{^name, {{module, function}, metadata}}] ->
        {:reply, {:ok, {module, function, metadata}}, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:list, _from, state) do
    tools = :ets.tab2list(state.table)
    |> Enum.map(fn {name, {_ref, metadata}} -> {name, metadata} end)
    |> Enum.sort_by(&elem(&1, 0))
    
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call({:list_namespace, namespace}, _from, state) do
    prefix = namespace <> "."
    
    tools = :ets.tab2list(state.table)
    |> Enum.filter(fn {name, _} -> String.starts_with?(name, prefix) end)
    |> Enum.map(fn {name, {_ref, metadata}} -> {name, metadata} end)
    |> Enum.sort_by(&elem(&1, 0))
    
    {:reply, tools, state}
  end
  
  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, %{state | metadata_index: %{}}}
  end
  
  # Private functions
  
  defp validate_function(module, function) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:module_not_loaded, module}}
        
      not function_exported?(module, function, 1) ->
        {:error, {:function_not_exported, {module, function, 1}}}
        
      true ->
        :ok
    end
  end
  
  defp update_namespace_index(index, name, metadata) do
    namespace = extract_namespace(name)
    
    if namespace do
      Map.update(index, namespace, [name], fn names -> [name | names] end)
    else
      index
    end
  end
  
  defp remove_from_namespace_index(index, name) do
    namespace = extract_namespace(name)
    
    if namespace do
      case Map.get(index, namespace) do
        nil -> index
        names ->
          new_names = List.delete(names, name)
          if new_names == [] do
            Map.delete(index, namespace)
          else
            Map.put(index, namespace, new_names)
          end
      end
    else
      index
    end
  end
  
  defp extract_namespace(name) do
    case String.split(name, ".", parts: 2) do
      [namespace, _rest] -> namespace
      _ -> nil
    end
  end
end