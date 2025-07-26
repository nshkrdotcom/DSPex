defmodule DSPex.Tools do
  @moduledoc """
  High-level API for managing bidirectional tools in DSPex.
  
  This module provides a convenient interface for registering and managing
  tools that can be called from Python code. It acts as a facade over
  the lower-level registry and executor modules.
  
  ## Example
  
      # Register a single tool
      DSPex.Tools.register("validate_email", &MyApp.Validators.email?/1)
      
      # Register all tools from a bidirectional module
      DSPex.Tools.register_module(MyApp.SmartPredictor)
      
      # Call a tool (for testing)
      {:ok, result} = DSPex.Tools.call("validate_email", %{"email" => "test@example.com"})
  """
  
  alias DSPex.Bridge.Tools.{Registry, Executor}
  alias DSPex.Bridge.Bidirectional
  require Logger
  
  @doc """
  Registers a single tool with the registry.
  
  ## Arguments
  
  - `name` - The name to register the tool under
  - `function` - A 1-arity function that accepts a map
  - `metadata` - Optional metadata about the tool
  
  ## Examples
  
      # Simple registration
      Tools.register("uppercase", &String.upcase/1)
      
      # With metadata
      Tools.register("validate_email", &MyApp.email?/1, %{
        description: "Validates email format",
        params: %{email: :string},
        returns: :boolean
      })
  """
  @spec register(String.t(), function(), map()) :: :ok | {:error, term()}
  def register(name, function, metadata \\ %{}) when is_function(function, 1) do
    case extract_module_function(function) do
      {:ok, {module, fun}} ->
        Registry.register(name, {module, fun}, metadata)
        
      :error ->
        {:error, {:invalid_function, "Could not extract module and function name"}}
    end
  end
  
  @doc """
  Registers all tools from a module that implements DSPex.Bridge.Bidirectional.
  
  The tools will be registered with namespaced names based on the module.
  For example, if `MyApp.Predictor` defines a tool "validate", it will be
  registered as "my_app.predictor.validate".
  
  ## Arguments
  
  - `module` - A module that implements the Bidirectional behavior
  - `session_id` - Optional session ID to associate with the tools
  
  ## Example
  
      defmodule MyApp.Predictor do
        use DSPex.Bridge.Bidirectional
        
        @impl true
        def elixir_tools do
          [
            {"validate", &validate/1},
            {"transform", &transform/1}
          ]
        end
        
        # ... tool implementations
      end
      
      # Register all tools
      {:ok, 2} = Tools.register_module(MyApp.Predictor)
  """
  @spec register_module(module(), String.t() | nil) :: {:ok, non_neg_integer()} | {:error, term()}
  def register_module(module, session_id \\ nil) do
    session_id = session_id || generate_session_id()
    Bidirectional.register_module_tools(module, session_id)
  end
  
  @doc """
  Unregisters a tool by name.
  
  Returns `:ok` if the tool was unregistered, `{:error, :not_found}` if it didn't exist.
  """
  @spec unregister(String.t()) :: :ok | {:error, :not_found}
  def unregister(name) do
    Registry.unregister(name)
  end
  
  @doc """
  Calls a registered tool by name.
  
  This is primarily for testing and debugging. In production, tools are
  typically called from Python through the gRPC bridge.
  
  ## Arguments
  
  - `name` - The registered name of the tool
  - `args` - Arguments to pass to the tool (must be a map)
  - `opts` - Optional execution options
  
  ## Options
  
  - `:timeout` - Execution timeout in milliseconds (default: 5000)
  - `:async` - If true, returns a Task instead of waiting for the result
  - `:session_id` - Session ID for tracking (default: auto-generated)
  
  ## Examples
  
      # Synchronous call
      {:ok, true} = Tools.call("validate_email", %{"email" => "test@example.com"})
      
      # With timeout
      {:ok, result} = Tools.call("slow_operation", %{data: data}, timeout: 10_000)
      
      # Asynchronous call
      {:ok, task} = Tools.call("process_data", %{data: data}, async: true)
      result = Task.await(task)
  """
  @spec call(String.t(), map(), keyword()) :: {:ok, any()} | {:error, term()}
  def call(name, args, opts \\ []) when is_map(args) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    {async, opts} = Keyword.pop(opts, :async, false)
    {session_id, _opts} = Keyword.pop(opts, :session_id, generate_session_id())
    
    context = %{
      session_id: session_id,
      caller: :elixir,
      timeout: timeout,
      async: async
    }
    
    Executor.execute(name, args, context)
  end
  
  @doc """
  Lists all registered tools.
  
  Returns a list of `{name, metadata}` tuples.
  
  ## Example
  
      tools = Tools.list()
      # [
      #   {"validate_email", %{description: "Validates email format"}},
      #   {"my_app.predictor.validate", %{module: MyApp.Predictor}}
      # ]
  """
  @spec list() :: [{String.t(), map()}]
  def list do
    Registry.list()
  end
  
  @doc """
  Lists tools in a specific namespace.
  
  ## Example
  
      Tools.list_namespace("my_app.predictor")
      # Returns all tools starting with "my_app.predictor."
  """
  @spec list_namespace(String.t()) :: [{String.t(), map()}]
  def list_namespace(namespace) do
    Registry.list_namespace(namespace)
  end
  
  @doc """
  Checks if a tool exists.
  
  ## Example
  
      if Tools.exists?("validate_email") do
        {:ok, result} = Tools.call("validate_email", %{"email" => email})
      end
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(name) do
    Registry.exists?(name)
  end
  
  @doc """
  Gets detailed information about a tool.
  
  Returns `{:ok, info}` where info contains the module, function, and metadata.
  """
  @spec info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def info(name) do
    case Registry.lookup(name) do
      {:ok, {module, function, metadata}} ->
        {:ok, %{
          name: name,
          module: module,
          function: function,
          metadata: metadata
        }}
        
      error ->
        error
    end
  end
  
  @doc """
  Clears all registered tools.
  
  This is mainly useful for testing. Use with caution in production.
  """
  @spec clear() :: :ok
  def clear do
    Registry.clear()
  end
  
  # Private functions
  
  defp extract_module_function(function) when is_function(function) do
    info = Function.info(function)
    
    case {info[:type], info[:module], info[:name]} do
      {:external, module, name} when is_atom(module) and is_atom(name) ->
        {:ok, {module, name}}
        
      _ ->
        :error
    end
  end
  
  defp generate_session_id do
    "tools-#{System.unique_integer([:positive])}"
  end
end