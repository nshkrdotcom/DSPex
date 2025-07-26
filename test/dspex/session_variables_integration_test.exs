defmodule DSPex.SessionVariablesIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnakepitGrpcBridge.Session.{Manager, VariableStore, Persistence}
  
  describe "Slice 2: Session Variables" do
    setup do
      # Ensure services are started (they should already be started by the app)
      # If not started, start them as supervised children
      _ = case Process.whereis(Manager) do
        nil -> start_supervised(Manager)
        pid -> {:ok, pid}
      end
      
      _ = case Process.whereis(VariableStore) do
        nil -> start_supervised(VariableStore)
        pid -> {:ok, pid}
      end
      
      _ = case Process.whereis(Persistence) do
        nil -> start_supervised(Persistence)
        pid -> {:ok, pid}
      end
      
      # Setup telemetry handler
      test_pid = self()
      handler_id = "session-vars-test-#{System.unique_integer()}"
      
      :telemetry.attach_many(
        handler_id,
        [
          [:snakepit_grpc_bridge, :session, :variable, :set],
          [:snakepit_grpc_bridge, :session, :variable, :get],
          [:snakepit_grpc_bridge, :session, :persistence, :save],
          [:snakepit_grpc_bridge, :session, :persistence, :load]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)
      
      session_id = "test-session-#{System.unique_integer()}"
      {:ok, session_id: session_id}
    end
    
    test "variable storage and retrieval works", %{session_id: session_id} do
      # Set variables with different types
      {:ok, temp_var} = VariableStore.set_variable(session_id, "temperature", 0.7, :float)
      {:ok, tokens_var} = VariableStore.set_variable(session_id, "max_tokens", 100, :integer)
      {:ok, model_var} = VariableStore.set_variable(session_id, "model", "gpt-4", :string)
      {:ok, debug_var} = VariableStore.set_variable(session_id, "debug", true, :boolean)
      
      # Verify storage
      assert temp_var.value == 0.7
      assert temp_var.type == :float
      assert tokens_var.value == 100
      assert tokens_var.type == :integer
      
      # Retrieve variables
      {:ok, retrieved_temp} = VariableStore.get_variable(session_id, "temperature")
      assert retrieved_temp.value == 0.7
      assert retrieved_temp.type == :float
      
      {:ok, retrieved_tokens} = VariableStore.get_variable(session_id, "max_tokens")
      assert retrieved_tokens.value == 100
      
      # Get all variables
      {:ok, all_vars} = VariableStore.get_all_variables(session_id)
      assert map_size(all_vars) == 4
      assert all_vars["temperature"].value == 0.7
      assert all_vars["model"].value == "gpt-4"
      assert all_vars["debug"].value == true
    end
    
    test "variable constraints are enforced", %{session_id: session_id} do
      # Valid value within constraints
      {:ok, _} = VariableStore.set_variable(
        session_id, 
        "temperature", 
        0.7, 
        :float,
        constraints: %{min: 0.0, max: 2.0}
      )
      
      # Value below minimum
      {:error, reason} = VariableStore.set_variable(
        session_id,
        "temperature",
        -0.5,
        :float,
        constraints: %{min: 0.0, max: 2.0}
      )
      assert reason =~ "below minimum"
      
      # Value above maximum
      {:error, reason} = VariableStore.set_variable(
        session_id,
        "temperature", 
        3.0,
        :float,
        constraints: %{min: 0.0, max: 2.0}
      )
      assert reason =~ "above maximum"
      
      # String pattern constraint
      {:ok, _} = VariableStore.set_variable(
        session_id,
        "api_key",
        "sk-1234567890",
        :string,
        constraints: %{pattern: ~r/^sk-[a-zA-Z0-9]+$/}
      )
      
      {:error, reason} = VariableStore.set_variable(
        session_id,
        "api_key",
        "invalid-key",
        :string,
        constraints: %{pattern: ~r/^sk-[a-zA-Z0-9]+$/}
      )
      assert reason =~ "does not match pattern"
    end
    
    test "session persistence works correctly", %{session_id: session_id} do
      # Set some variables
      {:ok, _} = VariableStore.set_variable(session_id, "temperature", 0.8, :float)
      {:ok, _} = VariableStore.set_variable(session_id, "model", "gpt-4", :string)
      
      # Get all variables
      {:ok, variables} = VariableStore.get_all_variables(session_id)
      
      # Save session
      :ok = Persistence.save_session(session_id, variables, %{user: "test_user"})
      
      # Clear variables from store
      {:ok, 2} = VariableStore.clear_session_variables(session_id)
      
      # Verify variables are gone
      {:ok, empty_vars} = VariableStore.get_all_variables(session_id)
      assert map_size(empty_vars) == 0
      
      # Load session from persistence
      {:ok, session_data} = Persistence.load_session(session_id)
      assert session_data.id == session_id
      assert map_size(session_data.variables) == 2
      assert session_data.variables["temperature"].value == 0.8
      assert session_data.variables["model"].value == "gpt-4"
      assert session_data.metadata.user == "test_user"
    end
    
    @tag :integration
    test "cross-request state persistence", %{session_id: session_id} do
      # Simulate first request
      {:ok, predictor} = DSPex.Predict.create(%{signature: "question -> answer"}, 
                                               session_id: session_id)
      
      # Set variables in the session
      {:ok, _} = VariableStore.set_variable(session_id, "temperature", 0.9, :float)
      {:ok, _} = VariableStore.set_variable(session_id, "style", "concise", :string)
      
      # Execute prediction
      {:ok, result1} = DSPex.Predict.predict(predictor, %{question: "What is AI?"})
      assert result1.answer != ""
      
      # Simulate second request with same session
      # Variables should still be available
      {:ok, temp_var} = VariableStore.get_variable(session_id, "temperature")
      assert temp_var.value == 0.9
      
      {:ok, style_var} = VariableStore.get_variable(session_id, "style")
      assert style_var.value == "concise"
      
      # Execute another prediction - should use same settings
      {:ok, result2} = DSPex.Predict.predict(predictor, %{question: "Explain ML"})
      assert result2.answer != ""
    end
    
    test "telemetry events for variables are emitted", %{session_id: session_id} do
      # Set a variable
      {:ok, _} = VariableStore.set_variable(session_id, "test_var", 42, :integer)
      
      # Verify set telemetry
      assert_receive {:telemetry_event, [:snakepit_grpc_bridge, :session, :variable, :set],
                      measurements, metadata}
      assert measurements.variable_count == 1
      assert metadata.session_id == session_id
      assert metadata.variable_name == "test_var"
      assert metadata.variable_type == :integer
      
      # Get the variable
      {:ok, _} = VariableStore.get_variable(session_id, "test_var")
      
      # Verify get telemetry
      assert_receive {:telemetry_event, [:snakepit_grpc_bridge, :session, :variable, :get],
                      measurements, metadata}
      assert measurements.found == true
      assert metadata.session_id == session_id
      assert metadata.variable_name == "test_var"
    end
    
    test "export and import functionality", %{session_id: session_id} do
      # Create multiple sessions with variables
      session_ids = for i <- 1..3 do
        sid = "export-test-#{i}"
        {:ok, _} = VariableStore.set_variable(sid, "var_#{i}", i * 10, :integer)
        
        {:ok, vars} = VariableStore.get_all_variables(sid)
        :ok = Persistence.save_session(sid, vars)
        
        sid
      end
      
      # Export all sessions
      {:ok, export_data} = Persistence.export_all()
      assert export_data.version == "1.0"
      assert map_size(export_data.sessions) >= 3
      
      # Clear persistence
      for sid <- session_ids do
        Persistence.delete_session(sid)
      end
      
      # Import back
      {:ok, imported_count} = Persistence.import_all(export_data)
      assert imported_count >= 3
      
      # Verify imported data
      for {sid, i} <- Enum.with_index(session_ids, 1) do
        {:ok, session_data} = Persistence.load_session(sid)
        assert session_data.variables["var_#{i}"].value == i * 10
      end
    end
    
    test "variable updates preserve creation time", %{session_id: session_id} do
      # Set initial variable
      {:ok, var1} = VariableStore.set_variable(session_id, "counter", 1, :integer)
      created_at = var1.created_at
      
      # Wait a bit
      Process.sleep(10)
      
      # Update variable
      {:ok, var2} = VariableStore.set_variable(session_id, "counter", 2, :integer)
      
      # Creation time should be preserved
      assert var2.created_at == created_at
      # Update time should be different
      assert DateTime.compare(var2.updated_at, var1.updated_at) == :gt
    end
  end
  
  describe "Success criteria from vertical slice plan" do
    @tag :integration
    test "variables persist across calls" do
      session = DSPex.Session.new()
      session_id = session.id
      
      # Set variables
      :ok = DSPex.Session.set_variable(session, "temperature", 0.7)
      :ok = DSPex.Session.set_variable(session, "max_tokens", 100)
      
      # Use in prediction
      predictor = DSPex.Predict.new("question -> answer", session: session)
      {:ok, result} = DSPex.Predict.call(predictor, %{question: "What is AI?"})
      assert result.answer != ""
      
      # Verify variables were accessible
      assert DSPex.Session.get_variable(session, "temperature") == 0.7
      assert DSPex.Session.get_variable(session, "max_tokens") == 100
    end
  end
end