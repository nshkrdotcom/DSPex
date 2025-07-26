defmodule DSPex.Bridge.Behaviours.Observable do
  @moduledoc """
  Behavior for modules that emit custom telemetry events.
  
  This enables comprehensive monitoring and observability of bridge operations,
  allowing you to track performance, errors, and usage patterns.
  """
  
  @doc """
  Returns metadata to include with telemetry events.
  
  This metadata will be attached to all telemetry events emitted by the wrapper.
  Common metadata includes:
  - Model/version information
  - Request characteristics (size, complexity)
  - User/tenant information
  - Feature flags
  
  ## Parameters
  
  - `operation` - The operation being performed (:create, :call, etc.)
  - `args` - The arguments being passed to the operation
  
  ## Example
  
      def telemetry_metadata(:call, %{method: "__call__", question: question}) do
        %{
          question_length: String.length(question),
          model: "gpt-4",
          timestamp: DateTime.utc_now()
        }
      end
  """
  @callback telemetry_metadata(operation :: atom(), args :: map()) :: map()
  
  @doc """
  Called before operation execution.
  
  Use this for:
  - Pre-execution validation
  - Rate limiting
  - Logging
  - Starting timers
  
  Return `{:error, reason}` to prevent execution.
  """
  @callback before_execute(operation :: atom(), args :: map()) :: :ok | {:error, term()}
  
  @doc """
  Called after operation execution.
  
  Use this for:
  - Post-processing
  - Cleanup
  - Logging results
  - Recording metrics
  
  Note: This is called even if the operation failed.
  """
  @callback after_execute(operation :: atom(), args :: map(), result :: term()) :: :ok
  
  @optional_callbacks [before_execute: 2, after_execute: 3]
end