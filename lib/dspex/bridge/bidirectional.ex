defmodule DSPex.Bridge.Bidirectional do
  @moduledoc """
  Adds bidirectional communication capabilities to wrapped modules.
  
  This allows Python code to call back into Elixir during execution,
  enabling sophisticated patterns like:
  
  - Validation callbacks
  - Data fetching from Elixir systems
  - Business rule evaluation
  - Real-time monitoring
  
  ## Usage
  
      defmodule MyPredictor do
        use DSPex.Bridge.SimpleWrapper
        use DSPex.Bridge.Bidirectional
        
        wrap_dspy "dspy.Predict"
        
        @impl DSPex.Bridge.Bidirectional
        def elixir_tools do
          [
            {"validate", &MyApp.validate/1},
            {"fetch_context", &MyApp.fetch_context/1}
          ]
        end
        
        @impl DSPex.Bridge.Bidirectional
        def on_python_callback(tool_name, args, context) do
          # Log the tool invocation  
          # IO.puts("Python called tool: \#{tool_name}")
          :ok
        end
      end
  
  ## Tool Registration
  
  When a module uses this behavior, its tools can be automatically registered:
  
      DSPex.Bridge.Bidirectional.register_module_tools(MyPredictor, "session-123")
  
  ## Tool Metadata
  
  Tools can include metadata for better documentation and validation:
  
      def elixir_tools do
        [
          {"validate", &validate/1, %{
            description: "Validates the input",
            params: %{value: :string},
            returns: :boolean
          }}
        ]
      end
  """
  
  alias DSPex.Bridge.Behaviours
  alias DSPex.Bridge.Tools
  require Logger
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Behaviours.Bidirectional
      
      # Default implementation
      @impl Behaviours.Bidirectional
      def on_python_callback(_tool_name, _args, _session_context), do: :ok
      
      defoverridable [on_python_callback: 3]
      
      # Register this behavior
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :bidirectional
      
      # Hook for automatic tool registration
      def __after_compile__(env, _bytecode) do
        if function_exported?(__MODULE__, :elixir_tools, 0) do
          DSPex.Bridge.Bidirectional.cache_module_tools(__MODULE__)
        end
      end
    end
  end
  
  @doc """
  Registers all tools from a bidirectional module.
  
  This extracts the tools defined in the module's elixir_tools/0 callback
  and registers them with the tool registry.
  
  ## Example
  
      DSPex.Bridge.Bidirectional.register_module_tools(MyPredictor, "session-123")
  """
  @spec register_module_tools(module(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def register_module_tools(module, session_id) do
    with :ok <- validate_bidirectional_module(module),
         tools <- extract_tools(module),
         :ok <- register_tools(tools, module, session_id) do
      {:ok, length(tools)}
    end
  end
  
  @doc """
  Extracts tool definitions from a module that implements the Bidirectional behavior.
  
  Returns a list of `{name, function, metadata}` tuples.
  """
  @spec tools_from_module(module()) :: [{String.t(), function(), map()}]
  def tools_from_module(module) do
    case validate_bidirectional_module(module) do
      :ok -> extract_tools(module)
      {:error, _} -> []
    end
  end
  
  @doc """
  Checks if a module implements the Bidirectional behavior.
  """
  @spec bidirectional?(module()) :: boolean()
  def bidirectional?(module) do
    case validate_bidirectional_module(module) do
      :ok -> true
      {:error, _} -> false
    end
  end
  
  @doc """
  Caches module tools for quick access.
  
  This is called automatically after module compilation.
  """
  @spec cache_module_tools(module()) :: :ok
  def cache_module_tools(module) do
    # This could be enhanced to store in ETS or similar for performance
    Logger.debug("Caching tools for module: #{inspect(module)}")
    :ok
  end
  
  # Private functions
  
  defp validate_bidirectional_module(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:module_not_loaded, module}}
        
      not function_exported?(module, :elixir_tools, 0) ->
        {:error, {:missing_callback, :elixir_tools}}
        
      not implements_behaviour?(module, Behaviours.Bidirectional) ->
        {:error, {:missing_behaviour, Behaviours.Bidirectional}}
        
      true ->
        :ok
    end
  end
  
  defp implements_behaviour?(module, behaviour) do
    module.__info__(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(behaviour)
  end
  
  defp extract_tools(module) do
    tools = module.elixir_tools()
    
    # Normalize tools to always have metadata
    Enum.map(tools, fn
      {name, function} when is_function(function, 1) ->
        {name, function, %{}}
        
      {name, function, metadata} when is_function(function, 1) and is_map(metadata) ->
        {name, function, metadata}
        
      invalid ->
        Logger.warning("Invalid tool definition in #{inspect(module)}: #{inspect(invalid)}")
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp register_tools(tools, module, session_id) do
    results = Enum.map(tools, fn {name, function, metadata} ->
      # Create a namespaced tool name
      full_name = "#{module_namespace(module)}.#{name}"
      
      # Enhance metadata with module info
      enhanced_metadata = Map.merge(metadata, %{
        module: module,
        session_id: session_id,
        registered_at: DateTime.utc_now()
      })
      
      # Get the actual function reference for hot code reloading
      case extract_function_ref(function) do
        {:ok, {mod, fun}} ->
          Tools.Registry.register(full_name, {mod, fun}, enhanced_metadata)
          
        :error ->
          Logger.warning("Could not extract function reference for tool: #{name}")
          {:error, {:invalid_function, name}}
      end
    end)
    
    # Check if any registration failed
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end
  
  defp module_namespace(module) do
    module
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> Enum.join(".")
  end
  
  defp extract_function_ref(function) when is_function(function) do
    info = Function.info(function)
    
    case {info[:type], info[:module], info[:name]} do
      {:external, module, name} when is_atom(module) and is_atom(name) ->
        {:ok, {module, name}}
        
      _ ->
        :error
    end
  end
end