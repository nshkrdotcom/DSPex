defmodule DSPex.Bridge.Observable do
  @moduledoc """
  Adds comprehensive telemetry and observability to wrapped modules.
  
  This behavior automatically emits telemetry events for all operations,
  allowing you to monitor:
  
  - Performance metrics (latency, throughput)
  - Error rates and types
  - Usage patterns
  - Resource consumption
  
  ## Telemetry Events
  
  The following events are emitted:
  
  - `[:dspex, :wrapper, :create, :start]` - Before instance creation
  - `[:dspex, :wrapper, :create, :stop]` - After instance creation
  - `[:dspex, :wrapper, :create, :exception]` - On creation error
  - `[:dspex, :wrapper, :call, :start]` - Before method call
  - `[:dspex, :wrapper, :call, :stop]` - After method call
  - `[:dspex, :wrapper, :call, :exception]` - On call error
  
  ## Usage
  
      defmodule MyPredictor do
        use DSPex.Bridge.SimpleWrapper
        use DSPex.Bridge.Observable
        
        wrap_dspy "dspy.Predict"
        
        @impl DSPex.Bridge.Observable
        def telemetry_metadata(:call, %{method: "__call__", question: q}) do
          %{
            question_length: String.length(q),
            complexity: calculate_complexity(q)
          }
        end
      end
  """
  
  alias DSPex.Bridge.Behaviours
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Behaviours.Observable
      
      # Default implementations
      @impl Behaviours.Observable
      def telemetry_metadata(_operation, _args), do: %{}
      
      @impl Behaviours.Observable
      def before_execute(_operation, _args), do: :ok
      
      @impl Behaviours.Observable  
      def after_execute(_operation, _args, _result), do: :ok
      
      defoverridable [
        telemetry_metadata: 2, 
        before_execute: 2, 
        after_execute: 3
      ]
      
      # Register this behavior
      Module.register_attribute(__MODULE__, :dspex_behaviors, accumulate: true)
      @dspex_behaviors :observable
    end
  end
end