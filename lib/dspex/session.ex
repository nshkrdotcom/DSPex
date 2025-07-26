defmodule DSPex.Session do
  @moduledoc """
  Session management for DSPex.
  
  Provides a high-level interface for session variables that integrates
  with the SnakepitGrpcBridge session system.
  
  ## Examples
  
      # Create a new session
      session = DSPex.Session.new()
      
      # Set variables
      :ok = DSPex.Session.set_variable(session, "temperature", 0.7)
      :ok = DSPex.Session.set_variable(session, "max_tokens", 100)
      
      # Get variables
      0.7 = DSPex.Session.get_variable(session, "temperature")
      100 = DSPex.Session.get_variable(session, "max_tokens")
      
      # Use with predictor
      predictor = DSPex.Predict.new("question -> answer", session: session)
  """
  
  defstruct [:id, :created_at]
  
  alias DSPex.Utils.ID
  
  @type t :: %__MODULE__{
    id: String.t(),
    created_at: DateTime.t()
  }
  
  @doc """
  Creates a new session.
  """
  def new(opts \\ []) do
    session_id = Keyword.get(opts, :id, ID.generate("session"))
    created_at = DateTime.utc_now()
    initial_vars = Keyword.get(opts, :variables, %{})
    
    # Emit session created event
    :telemetry.execute(
      [:dspex, :session, :created],
      %{system_time: System.system_time()},
      %{session_id: session_id, initial_vars: initial_vars}
    )
    
    session = %__MODULE__{
      id: session_id,
      created_at: created_at
    }
    
    # Set initial variables if provided
    Enum.each(initial_vars, fn {name, value} ->
      set_variable(session, name, value)
    end)
    
    session
  end
  
  @doc """
  Sets a variable in the session.
  
  ## Examples
  
      :ok = DSPex.Session.set_variable(session, "temperature", 0.7)
  """
  def set_variable(%__MODULE__{id: session_id}, name, value) do
    name_str = to_string(name)
    
    # Measure size for telemetry
    size = case value do
      binary when is_binary(binary) -> byte_size(binary)
      list when is_list(list) -> length(list)
      map when is_map(map) -> map_size(map)
      _ -> 0
    end
    
    :telemetry.execute(
      [:dspex, :session, :variable, :set],
      %{size: size},
      %{
        session_id: session_id,
        var_name: name_str,
        var_type: type_name(value)
      }
    )
    
    # Store in Snakepit session
    case Snakepit.execute_in_session(session_id, "set_session_variable", %{
      "name" => name_str,
      "value" => value
    }) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Gets a variable from the session.
  
  ## Examples
  
      temperature = DSPex.Session.get_variable(session, "temperature")
      # Returns the value or nil if not found
  """
  def get_variable(%__MODULE__{id: session_id}, name, default \\ nil) do
    name_str = to_string(name)
    
    case Snakepit.execute_in_session(session_id, "get_session_variable", %{
      "name" => name_str
    }) do
      {:ok, %{"success" => true, "value" => value}} ->
        size = case value do
          binary when is_binary(binary) -> byte_size(binary)
          list when is_list(list) -> length(list)
          map when is_map(map) -> map_size(map)
          _ -> 0
        end
        
        :telemetry.execute(
          [:dspex, :session, :variable, :get],
          %{size: size},
          %{
            session_id: session_id,
            var_name: name_str,
            found: true
          }
        )
        
        value
        
      _ ->
        :telemetry.execute(
          [:dspex, :session, :variable, :get],
          %{size: 0},
          %{
            session_id: session_id,
            var_name: name_str,
            found: false
          }
        )
        
        default
    end
  end
  
  @doc """
  Gets all variables from the session.
  
  ## Examples
  
      variables = DSPex.Session.get_all_variables(session)
      # Returns: %{"temperature" => 0.7, "max_tokens" => 100}
  """
  def get_all_variables(%__MODULE__{id: session_id}) do
    case Snakepit.execute_in_session(session_id, "get_all_session_variables", %{}) do
      {:ok, %{"success" => true, "variables" => variables}} -> variables
      _ -> %{}
    end
  end
  
  @doc """
  Deletes a variable from the session.
  """
  def delete_variable(%__MODULE__{id: session_id}, name) do
    name_str = to_string(name)
    
    case Snakepit.execute_in_session(session_id, "delete_session_variable", %{
      "name" => name_str
    }) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, %{"success" => false, "error" => error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Clears all variables from the session.
  """
  def clear_variables(%__MODULE__{id: session_id}) do
    case Snakepit.execute_in_session(session_id, "clear_session_variables", %{}) do
      {:ok, %{"success" => true}} -> :ok
      _ -> :ok
    end
  end
  
  @doc """
  Marks a session as expired and emits telemetry.
  """
  def expire(%__MODULE__{id: session_id, created_at: created_at} = session) do
    lifetime_ms = DateTime.diff(DateTime.utc_now(), created_at, :millisecond)
    
    # Count total operations (rough estimate based on telemetry)
    total_operations = 0  # Would need to track this separately
    
    :telemetry.execute(
      [:dspex, :session, :expired],
      %{lifetime_ms: lifetime_ms, total_operations: total_operations},
      %{session_id: session_id, reason: :manual}
    )
    
    clear_variables(session)
  end
  
  # Private functions
  
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "float"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_atom(value), do: "atom"
  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(value) when is_tuple(value), do: "tuple"
  defp type_name(_), do: "unknown"
end