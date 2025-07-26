defmodule DSPex.Bridge.Behaviours.Bidirectional do
  @moduledoc """
  Behavior for modules that support Python → Elixir callbacks.
  
  This enables Python code to call back into Elixir functions during execution,
  creating truly bidirectional communication between the two runtimes.
  """
  
  @doc """
  Returns list of tools available to Python.
  
  Each tool is a {name, function} tuple where:
  - name: String name that Python will use to invoke the tool
  - function: 1-arity function that receives a map of arguments
  
  ## Example
  
      def elixir_tools do
        [
          {"validate_answer", &MyApp.Validators.validate_answer/1},
          {"fetch_context", &MyApp.Context.fetch/1}
        ]
      end
  """
  @callback elixir_tools() :: [{String.t(), function()}]
  
  @doc """
  Called when Python invokes an Elixir tool.
  
  This callback is useful for:
  - Logging tool invocations
  - Monitoring performance
  - Preprocessing arguments
  - Access control
  
  ## Parameters
  
  - `tool_name` - The name of the tool being invoked
  - `args` - The arguments passed from Python (as a map)
  - `session_context` - Session information including session_id, metadata, etc.
  
  ## Return Values
  
  - `:ok` - Continue with tool execution
  - `{:error, reason}` - Prevent tool execution and return error to Python
  """
  @callback on_python_callback(tool_name :: String.t(), args :: map(), session_context :: map()) :: 
    :ok | {:error, term()}
    
  @optional_callbacks [on_python_callback: 3]
end